defmodule Plato do
  @moduledoc """
  Plato — BEAM/OTP actor model for marine vessel room monitoring.

  ## The Plato Thesis on the BEAM

  The BEAM VM's actor model IS the Plato thesis made runtime:

  - **Each room = a GenServer process** — supervised, fault-tolerant, stateful
  - **Fleet = a Supervisor tree** — hierarchical management of room processes
  - **Agent = another GenServer** — subscribes to rooms, makes decisions
  - **Hot code reload** — update room logic without stopping
  - **Message passing** — the Plato text protocol, but typed
  - **Process isolation** — rooms can't corrupt each other's state
  - **Pattern matching** — ternary evaluation is native in Elixir

  ## Quick Start

      # Start the fleet
      {:ok, _} = Plato.FleetSupervisor.start_link()

      # Add rooms
      Plato.Fleet.add_room("engine", sensors: [
        Plato.Sensor.new("temperature", 72.0, unit: "°F", low: 60.0, high: 90.0),
        Plato.Sensor.new("pressure", 14.5, unit: "PSI", low: 12.0, high: 18.0)
      ], bounds: %{"temperature" => {60.0, 90.0}, "pressure" => {12.0, 18.0}},
      alarms: [
        Plato.Alarm.new("engine_overheat", "temperature", :above, 85.0)
      ])

      # Tick the fleet
      Plato.Fleet.broadcast_tick()

      # Check health
      {:ok, health} = Plato.Fleet.get_health()

  ## Ternary Logic

  Every sensor reading is classified as one of three states:

      Plato.Ternary.to_trit(95.0, {60.0, 90.0})  # => 1 (above)
      Plato.Ternary.to_trit(72.0, {60.0, 90.0})  # => 0 (normal)
      Plato.Ternary.to_trit(50.0, {60.0, 90.0})  # => -1 (below)

  Ternary values pack into integers for compact storage:

      packed = Plato.Ternary.pack([1, 0, -1, 0])
  """

  alias Plato.{Room, Fleet, Sensor, Alarm, Ternary, Protocol, FleetSupervisor}

  @doc """
  Convenience: start the entire Plato system with default rooms.
  """
  def start(opts \\ []) do
    FleetSupervisor.start_link(opts)
  end

  @doc """
  Convenience: add a room with a simple config.
  """
  def add_room(name, opts \\ []) do
    Fleet.add_room(name, opts)
  end

  @doc """
  Convenience: tick all rooms.
  """
  def tick_all do
    Fleet.broadcast_tick()
  end

  @doc """
  Convenience: get fleet health.
  """
  def health do
    Fleet.get_health()
  end
end
