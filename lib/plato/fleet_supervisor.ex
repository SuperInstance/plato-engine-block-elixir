defmodule Plato.FleetSupervisor do
  @moduledoc """
  Top-level supervisor for the Plato fleet.

  Supervision tree:
  ```
  FleetSupervisor
  ├── RoomRegistry (Registry)
  ├── RoomSupervisor (DynamicSupervisor)
  └── FleetManager (GenServer)
  ```

  The order matters: Registry must start first so rooms can register,
  then the DynamicSupervisor for rooms, then FleetManager which starts
  rooms under the supervisor.

  Restart strategy: one_for_one — if any child crashes, only it restarts.
  """

  use Supervisor

  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    room_configs = Keyword.get(opts, :rooms, [])

    children = [
      {Registry, keys: :unique, name: Plato.RoomRegistry},
      {Plato.RoomSupervisor, []},
      {Plato.Fleet, rooms: room_configs}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
