defmodule Plato.Room do
  @moduledoc """
  A GenServer representing a single monitored room.

  Each room is an isolated OTP process that maintains:
  - A collection of sensors with current readings
  - A set of alarm rules evaluated each tick
  - A history buffer of recent ticks
  - Actuator states (binary controls)

  This is the core Plato concept: a room is a living, supervised process
  that can crash and restart independently of any other room.

  ## Supervision

  Rooms are started under `Plato.RoomSupervisor` (a DynamicSupervisor).
  If a room process crashes, the supervisor restarts it.

  ## State

  The room state includes:
  - `:name` — human-readable room identifier
  - `:sensors` — map of sensor_name => %Plato.Sensor{}
  - `:alarms` — list of %Plato.Alarm{} rules
  - `:actuators` — map of actuator_name => 0 | 1
  - `:history` — circular buffer of tick snapshots
  - `:active_alarms` — map of alarm_name => ticks_remaining_cooldown
  - `:tick_count` — monotonically increasing tick counter
  - `:ternary_bounds` — map of sensor_name => {low, high} for ternary classification
  """

  use GenServer

  alias Plato.{Sensor, Alarm, Ternary}

  @default_history_size 50
  @default_alarm_cooldown 5

  # --- Client API ---

  @doc "Start a room process (usually called by the supervisor)"
  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: via_tuple(name))
  end

  @doc "Get the via tuple for a named room"
  def via_tuple(name), do: {:via, Registry, {Plato.RoomRegistry, name}}

  @doc "Send a tick to the room"
  def tick(room) when is_binary(room), do: GenServer.call(via_tuple(room), :tick)
  def tick(room), do: GenServer.call(room, :tick)

  @doc "Update a sensor value"
  def update_sensor(room, name, value) when is_binary(room) do
    GenServer.call(via_tuple(room), {:update_sensor, name, value})
  end
  def update_sensor(room, name, value) do
    GenServer.call(room, {:update_sensor, name, value})
  end

  @doc "Set an actuator state (0 or 1)"
  def set_actuator(room, name, state) when state in [0, 1] and is_binary(room) do
    GenServer.call(via_tuple(room), {:set_actuator, name, state})
  end
  def set_actuator(room, name, state) when state in [0, 1] do
    GenServer.call(room, {:set_actuator, name, state})
  end

  @doc "Add an alarm rule to the room"
  def add_alarm(room, %Alarm{} = alarm) when is_binary(room) do
    GenServer.call(via_tuple(room), {:add_alarm, alarm})
  end
  def add_alarm(room, %Alarm{} = alarm) do
    GenServer.call(room, {:add_alarm, alarm})
  end

  @doc "Get current room status"
  def get_status(room) when is_binary(room), do: GenServer.call(via_tuple(room), :get_status)
  def get_status(room), do: GenServer.call(room, :get_status)

  @doc "Get active alarms"
  def get_alarms(room) when is_binary(room), do: GenServer.call(via_tuple(room), :get_alarms)
  def get_alarms(room), do: GenServer.call(room, :get_alarms)

  @doc "Get last n history entries"
  def get_history(room, n \\ 10)
  def get_history(room, n) when is_binary(room), do: GenServer.call(via_tuple(room), {:get_history, n})
  def get_history(room, n), do: GenServer.call(room, {:get_history, n})

  @doc "Get current sensor values"
  def get_sensors(room) when is_binary(room), do: GenServer.call(via_tuple(room), :get_sensors)
  def get_sensors(room), do: GenServer.call(room, :get_sensors)

  @doc "Get actuator states"
  def get_actuators(room) when is_binary(room), do: GenServer.call(via_tuple(room), :get_actuators)
  def get_actuators(room), do: GenServer.call(room, :get_actuators)

  @doc "Get the ternary classification of current sensors"
  def get_ternary(room) when is_binary(room), do: GenServer.call(via_tuple(room), :get_ternary)
  def get_ternary(room), do: GenServer.call(room, :get_ternary)

  @doc "Get the packed ternary state as an integer"
  def get_ternary_packed(room) when is_binary(room), do: GenServer.call(via_tuple(room), :get_ternary_packed)
  def get_ternary_packed(room), do: GenServer.call(room, :get_ternary_packed)

  @doc "Stop the room gracefully"
  def stop(room) when is_binary(room), do: GenServer.stop(via_tuple(room))
  def stop(room), do: GenServer.stop(room)

  # --- Server Callbacks ---

  @impl true
  def init(opts) do
    name = Keyword.fetch!(opts, :name)
    history_size = Keyword.get(opts, :history_size, @default_history_size)
    alarm_cooldown = Keyword.get(opts, :alarm_cooldown, @default_alarm_cooldown)

    sensors = Keyword.get(opts, :sensors, [])
    alarms = Keyword.get(opts, :alarms, [])
    actuators = Keyword.get(opts, :actuators, [])
    bounds = Keyword.get(opts, :bounds, %{})

    state = %{
      name: name,
      sensors: Map.new(sensors, fn %Sensor{name: n} = s -> {n, s} end),
      alarms: alarms,
      actuators: Map.new(actuators, fn {n, v} -> {n, v} end),
      history: [],
      history_size: history_size,
      alarm_cooldown: alarm_cooldown,
      active_alarms: %{},
      tick_count: 0,
      ternary_bounds: bounds
    }

    {:ok, state}
  end

  @impl true
  def handle_call(:tick, _from, state) do
    state = do_tick(state)
    {:reply, {:ok, state.tick_count}, state}
  end

  def handle_call({:update_sensor, name, value}, _from, state) do
    sensor = Map.get(state.sensors, name, Sensor.new(name, value))
    sensor = %{sensor | value: value}
    sensors = Map.put(state.sensors, name, sensor)
    {:reply, :ok, %{state | sensors: sensors}}
  end

  def handle_call({:set_actuator, name, val}, _from, state) do
    actuators = Map.put(state.actuators, name, val)
    {:reply, :ok, %{state | actuators: actuators}}
  end

  def handle_call({:add_alarm, %Alarm{} = alarm}, _from, state) do
    {:reply, :ok, %{state | alarms: [alarm | state.alarms]}}
  end

  def handle_call(:get_status, _from, state) do
    status = %{
      name: state.name,
      tick: state.tick_count,
      sensor_count: map_size(state.sensors),
      active_alarm_count: map_size(state.active_alarms),
      actuator_count: map_size(state.actuators)
    }
    {:reply, {:status, status}, state}
  end

  def handle_call(:get_alarms, _from, state) do
    alarm_names = Map.keys(state.active_alarms)
    {:reply, {:alarms, alarm_names}, state}
  end

  def handle_call({:get_history, n}, _from, state) do
    entries = state.history |> Enum.take(n)
    {:reply, {:history, entries}, state}
  end

  def handle_call(:get_sensors, _from, state) do
    {:reply, {:ok, state.sensors}, state}
  end

  def handle_call(:get_actuators, _from, state) do
    {:reply, {:ok, state.actuators}, state}
  end

  def handle_call(:get_ternary, _from, state) do
    readings = Map.new(state.sensors, fn {name, s} -> {name, s.value} end)
    trits = Ternary.classify_sensors(readings, state.ternary_bounds)
    {:reply, {:ok, trits}, state}
  end

  def handle_call(:get_ternary_packed, _from, state) do
    readings = Map.new(state.sensors, fn {name, s} -> {name, s.value} end)
    trits = Ternary.classify_sensors(readings, state.ternary_bounds)
    ordered = for {name, _} <- Enum.sort(state.ternary_bounds), do: Map.get(trits, name, nil)
    packed = Ternary.pack(ordered)
    {:reply, {:ok, packed, length(ordered)}, state}
  end

  # --- Private ---

  defp do_tick(state) do
    # Evaluate all alarms
    {new_active, fired} = evaluate_alarms(state)

    # Record history snapshot
    snapshot = build_snapshot(state)
    history = [snapshot | state.history] |> Enum.take(state.history_size)

    # Decay cooldowns
    decayed = decay_cooldowns(state.active_alarms)

    # Merge: newly fired alarms get fresh cooldown
    final_active = Enum.reduce(fired, decayed, fn name, acc ->
      cooldown = alarm_cooldown_for(state, name)
      Map.put(acc, name, cooldown)
    end)

    %{state |
      tick_count: state.tick_count + 1,
      history: history,
      active_alarms: final_active
    }
  end

  defp evaluate_alarms(state) do
    fired =
      for alarm <- state.alarms,
          sensor = Map.get(state.sensors, alarm.sensor),
          sensor != nil,
          eval = Alarm.evaluate(alarm, sensor.value),
          match?({:fire, _}, eval),
          not Map.has_key?(state.active_alarms, alarm.name) do
        alarm.name
      end

    {state.active_alarms, fired}
  end

  defp build_snapshot(state) do
    sensors = Map.new(state.sensors, fn {name, s} -> {name, s.value} end)
    actuators = Map.merge(%{}, state.actuators)
    %{tick: state.tick_count, sensors: sensors, actuators: actuators}
  end

  defp decay_cooldowns(active) do
    active
    |> Enum.map(fn {name, cd} -> {name, cd - 1} end)
    |> Enum.reject(fn {_, cd} -> cd <= 0 end)
    |> Map.new()
  end

  defp alarm_cooldown_for(state, alarm_name) do
    case Enum.find(state.alarms, &(&1.name == alarm_name)) do
      %Alarm{cooldown: cd} -> cd
      nil -> state.alarm_cooldown
    end
  end
end
