defmodule Plato.RoomSupervisor do
  @moduledoc """
  DynamicSupervisor for room processes.

  Each room runs as an independent GenServer under this supervisor.
  If a room crashes, it restarts automatically — rooms can't corrupt
  each other's state because they're isolated processes.

  This is the BEAM advantage: fault tolerance through process isolation,
  not defensive programming.
  """

  use DynamicSupervisor

  def start_link(opts) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc "Start a new room under this supervisor"
  def start_room(opts) do
    spec = {Plato.Room, opts}
    DynamicSupervisor.start_child(__MODULE__, spec)
  end

  @doc "Stop a room"
  def stop_room(pid) do
    DynamicSupervisor.terminate_child(__MODULE__, pid)
  end

  @doc "List all running rooms"
  def list_rooms do
    DynamicSupervisor.which_children(__MODULE__)
  end

  @doc "Count running rooms"
  def count_rooms do
    DynamicSupervisor.count_children(__MODULE__)
  end
end
