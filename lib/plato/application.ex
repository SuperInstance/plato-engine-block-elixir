defmodule Plato.Application do
  @moduledoc """
  OTP Application callback for Plato.

  When the application starts, it launches the full supervision tree:
  FleetSupervisor → [Registry, RoomSupervisor, FleetManager]

  Rooms are started dynamically via FleetManager.add_room/2.
  """

  use Application

  @impl true
  def start(_type, _args) do
    Plato.FleetSupervisor.start_link([])
  end
end
