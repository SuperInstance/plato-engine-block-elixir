defmodule Plato.Fleet do
  @moduledoc """
  FleetManager — orchestrates a fleet of rooms.

  The FleetManager is the top-level coordinator for the Plato system.
  It manages room lifecycle, broadcasts commands, and monitors fleet health.

  ## Architecture

  ```
  FleetSupervisor
  ├── FleetManager (GenServer — this module)
  ├── RoomSupervisor (DynamicSupervisor)
  │   ├── Room "engine"
  │   ├── Room "bridge"
  │   └── Room "cargo_hold"
  └── RoomRegistry (Registry for room lookup)
  ```

  ## Health

  Fleet health is determined by:
  - How many rooms are running vs. expected
  - How many active alarms across all rooms
  - Whether any room has recently restarted
  """

  use GenServer

  @default_rooms []

  # --- Client API ---

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Add a room to the fleet"
  def add_room(name, opts \\ []) do
    GenServer.call(__MODULE__, {:add_room, name, opts})
  end

  @doc "Remove a room from the fleet"
  def remove_room(name) do
    GenServer.call(__MODULE__, {:remove_room, name})
  end

  @doc "Broadcast a tick to all rooms"
  def broadcast_tick do
    GenServer.call(__MODULE__, :broadcast_tick)
  end

  @doc "Broadcast an actuator command to all rooms"
  def broadcast_actuator(actuator_name, state) do
    GenServer.call(__MODULE__, {:broadcast_actuator, actuator_name, state})
  end

  @doc "Get fleet health summary"
  def get_health do
    GenServer.call(__MODULE__, :get_health)
  end

  @doc "Get list of all room names"
  def get_rooms do
    GenServer.call(__MODULE__, :get_rooms)
  end

  @doc "Tick a specific room"
  def tick_room(name) do
    GenServer.call(__MODULE__, {:tick_room, name})
  end

  @doc "Update a sensor on a specific room"
  def update_sensor(room_name, sensor_name, value) do
    GenServer.call(__MODULE__, {:update_sensor, room_name, sensor_name, value})
  end

  @doc "Get room status"
  def get_room_status(name) do
    GenServer.call(__MODULE__, {:get_room_status, name})
  end

  # --- Server Callbacks ---

  @impl true
  def init(opts) do
    room_configs = Keyword.get(opts, :rooms, @default_rooms)
    rooms = %{}

    # Start configured rooms
    rooms = Enum.reduce(room_configs, rooms, fn room_opts, acc ->
      name = Keyword.fetch!(room_opts, :name)
      case Plato.RoomSupervisor.start_room(room_opts) do
        {:ok, _pid} -> Map.put(acc, name, room_opts)
        {:error, {:already_started, _pid}} -> Map.put(acc, name, room_opts)
        _ -> acc
      end
    end)

    {:ok, %{rooms: rooms, tick_count: 0}}
  end

  @impl true
  def handle_call({:add_room, name, opts}, _from, state) do
    room_opts = Keyword.put(opts, :name, name)
    case Plato.RoomSupervisor.start_room(room_opts) do
      {:ok, _pid} ->
        {:reply, {:ok, name}, %{state | rooms: Map.put(state.rooms, name, room_opts)}}
      {:error, {:already_started, _pid}} ->
        {:reply, {:error, :already_exists}, state}
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:remove_room, name}, _from, state) do
    case Registry.lookup(Plato.RoomRegistry, name) do
      [{pid, _}] ->
        Plato.RoomSupervisor.stop_room(pid)
        {:reply, :ok, %{state | rooms: Map.delete(state.rooms, name)}}
      [] ->
        {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call(:broadcast_tick, _from, state) do
    results = for {name, _opts} <- state.rooms do
      case find_room(name) do
        nil -> {name, :not_found}
        pid ->
          try do
            {name, Plato.Room.tick(pid)}
          catch
            :exit, _ -> {name, :crashed}
          end
      end
    end
    {:reply, {:ok, results}, %{state | tick_count: state.tick_count + 1}}
  end

  def handle_call({:broadcast_actuator, actuator_name, actuator_state}, _from, state) do
    results = for {name, _opts} <- state.rooms do
      case find_room(name) do
        nil -> {name, :not_found}
        pid ->
          try do
            {name, Plato.Room.set_actuator(pid, actuator_name, actuator_state)}
          catch
            :exit, _ -> {name, :crashed}
          end
      end
    end
    {:reply, {:ok, results}, state}
  end

  def handle_call(:get_health, _from, state) do
    total = map_size(state.rooms)
    alive = Enum.count(state.rooms, fn {name, _} -> find_room(name) != nil end)

    all_alarms = for {name, _} <- state.rooms,
                      pid = find_room(name),
                      pid != nil,
                      {:alarms, alarms} <- [Plato.Room.get_alarms(pid)] do
      {name, alarms}
    end

    alarm_count = Enum.reduce(all_alarms, 0, fn {_, a}, acc -> acc + length(a) end)

    health = %{
      total_rooms: total,
      alive_rooms: alive,
      total_alarms: alarm_count,
      fleet_tick: state.tick_count,
      status: health_status(alive, total, alarm_count)
    }

    {:reply, {:ok, health}, state}
  end

  def handle_call(:get_rooms, _from, state) do
    {:reply, Map.keys(state.rooms), state}
  end

  def handle_call({:tick_room, name}, _from, state) do
    reply = case find_room(name) do
      nil -> {:error, :not_found}
      pid -> Plato.Room.tick(pid)
    end
    {:reply, reply, state}
  end

  def handle_call({:update_sensor, room_name, sensor_name, value}, _from, state) do
    reply = case find_room(room_name) do
      nil -> {:error, :not_found}
      pid -> Plato.Room.update_sensor(pid, sensor_name, value)
    end
    {:reply, reply, state}
  end

  def handle_call({:get_room_status, name}, _from, state) do
    reply = case find_room(name) do
      nil -> {:error, :not_found}
      pid -> Plato.Room.get_status(pid)
    end
    {:reply, reply, state}
  end

  # --- Private ---

  defp find_room(name) do
    case Registry.lookup(Plato.RoomRegistry, name) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  defp health_status(alive, total, _alarm_count) when alive < total, do: :degraded
  defp health_status(_alive, _total, alarm_count) when alarm_count > 0, do: :alarmed
  defp health_status(alive, total, _alarms) when alive == total, do: :healthy
  defp health_status(_, _, _), do: :unknown
end
