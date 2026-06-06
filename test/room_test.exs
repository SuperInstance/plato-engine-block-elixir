defmodule Plato.RoomTest do
  use ExUnit.Case, async: false

  alias Plato.{Room, Sensor, Alarm}

  setup_all do
    # Ensure clean slate
    _ = stop_tree()
    {:ok, _} = start_tree()
    on_exit(fn -> stop_tree() end)
    :ok
  end

  setup do
    # Clean up any rooms from previous tests
    for {_, pid, _, _} <- Plato.RoomSupervisor.list_rooms() do
      Plato.RoomSupervisor.stop_room(pid)
    end
    # Give registry time to clean up
    Process.sleep(10)

    # Start a test room
    {:ok, _pid} = Plato.RoomSupervisor.start_room(
      name: "test_room",
      sensors: [
        Sensor.new("temperature", 72.0, unit: "°F", low: 60.0, high: 90.0),
        Sensor.new("pressure", 14.5, unit: "PSI", low: 12.0, high: 18.0)
      ],
      alarms: [
        Alarm.new("overheat", "temperature", :above, 85.0, message: "Engine overheating!"),
        Alarm.new("low_pressure", "pressure", :below, 12.5, message: "Pressure too low!")
      ],
      bounds: %{
        "temperature" => {60.0, 90.0},
        "pressure" => {12.0, 18.0}
      }
    )

    :ok
  end

  defp start_tree do
    # Stop any existing named trees
    try do
      Supervisor.stop(Plato.FleetSupervisor, :normal, 1000)
    catch
      :exit, _ -> :ok
    end
    children = [
      {Registry, keys: :unique, name: Plato.RoomRegistry},
      {Plato.RoomSupervisor, []}
    ]
    Supervisor.start_link(children, strategy: :one_for_one, name: Plato.RoomTest.Sup)
  end

  defp stop_tree do
    try do
      Supervisor.stop(Plato.RoomTest.Sup, :normal, 5000)
    catch
      :exit, _ -> :ok
    end
  end

  describe "room lifecycle" do
    test "room starts successfully" do
      assert [{:undefined, pid, :worker, _}] = Plato.RoomSupervisor.list_rooms()
      assert is_pid(pid)
    end

    test "room responds to status" do
      {:status, status} = Room.get_status("test_room")
      assert status.name == "test_room"
      assert status.tick == 0
      assert status.sensor_count == 2
    end
  end

  describe "tick" do
    test "tick increments counter" do
      {:ok, tick1} = Room.tick("test_room")
      {:ok, tick2} = Room.tick("test_room")
      assert tick2 > tick1
    end

    test "multiple ticks increment monotonically" do
      ticks = for _ <- 1..10 do
        {:ok, t} = Room.tick("test_room")
        t
      end
      assert ticks == Enum.sort(ticks)
      assert length(Enum.uniq(ticks)) == 10
    end
  end

  describe "sensors" do
    test "read sensor values" do
      {:ok, sensors} = Room.get_sensors("test_room")
      assert Map.has_key?(sensors, "temperature")
      assert Map.has_key?(sensors, "pressure")
    end

    test "update sensor value" do
      :ok = Room.update_sensor("test_room", "temperature", 95.0)
      {:ok, sensors} = Room.get_sensors("test_room")
      assert sensors["temperature"].value == 95.0
    end

    test "add new sensor via update" do
      :ok = Room.update_sensor("test_room", "humidity", 45.0)
      {:ok, sensors} = Room.get_sensors("test_room")
      assert Map.has_key?(sensors, "humidity")
      assert sensors["humidity"].value == 45.0
    end
  end

  describe "alarms" do
    test "no alarms initially" do
      {:alarms, alarms} = Room.get_alarms("test_room")
      assert alarms == []
    end

    test "alarm fires when threshold exceeded" do
      :ok = Room.update_sensor("test_room", "temperature", 95.0)
      Room.tick("test_room")
      {:alarms, alarms} = Room.get_alarms("test_room")
      assert "overheat" in alarms
    end

    test "alarm does not fire when value is normal" do
      :ok = Room.update_sensor("test_room", "temperature", 75.0)
      Room.tick("test_room")
      {:alarms, alarms} = Room.get_alarms("test_room")
      refute "overheat" in alarms
    end

    test "alarm cooldown prevents immediate re-fire" do
      :ok = Room.update_sensor("test_room", "temperature", 95.0)
      Room.tick("test_room")

      # Alarm is active, tick again — should still be in cooldown
      Room.tick("test_room")
      {:alarms, alarms} = Room.get_alarms("test_room")
      assert "overheat" in alarms
    end

    test "alarm clears after cooldown expires" do
      :ok = Room.update_sensor("test_room", "temperature", 95.0)
      Room.tick("test_room")

      # Tick past the cooldown (default 5)
      for _ <- 1..10 do
        Room.tick("test_room")
      end

      # Bring temperature back to normal
      :ok = Room.update_sensor("test_room", "temperature", 75.0)
      Room.tick("test_room")

      {:alarms, alarms} = Room.get_alarms("test_room")
      refute "overheat" in alarms
    end

    test "below-threshold alarm fires" do
      :ok = Room.update_sensor("test_room", "pressure", 10.0)
      Room.tick("test_room")
      {:alarms, alarms} = Room.get_alarms("test_room")
      assert "low_pressure" in alarms
    end
  end

  describe "history" do
    test "history is empty initially" do
      {:history, entries} = Room.get_history("test_room", 5)
      assert entries == []
    end

    test "history stores ticks" do
      Room.tick("test_room")
      Room.tick("test_room")
      {:history, entries} = Room.get_history("test_room", 5)
      assert length(entries) == 2
    end

    test "history respects max size" do
      for _ <- 1..60 do
        Room.tick("test_room")
      end
      {:history, entries} = Room.get_history("test_room", 100)
      assert length(entries) == 50  # default history_size
    end

    test "history snapshot includes sensor values" do
      :ok = Room.update_sensor("test_room", "temperature", 78.0)
      Room.tick("test_room")
      {:history, [entry | _]} = Room.get_history("test_room", 1)
      assert entry.sensors["temperature"] == 78.0
    end
  end

  describe "actuators" do
    test "set and read actuator" do
      :ok = Room.set_actuator("test_room", "pump", 1)
      {:ok, actuators} = Room.get_actuators("test_room")
      assert actuators["pump"] == 1
    end

    test "toggle actuator" do
      Room.set_actuator("test_room", "fan", 1)
      Room.set_actuator("test_room", "fan", 0)
      {:ok, actuators} = Room.get_actuators("test_room")
      assert actuators["fan"] == 0
    end
  end

  describe "ternary" do
    test "get ternary classification" do
      {:ok, trits} = Room.get_ternary("test_room")
      # temp=72.0 within {60,90} → 0; pressure=14.5 within {12,18} → 0
      assert trits["temperature"] == 0
      assert trits["pressure"] == 0
    end

    test "get packed ternary" do
      {:ok, packed, count} = Room.get_ternary_packed("test_room")
      assert is_integer(packed)
      assert count == 2
    end
  end
end
