defmodule Plato.FleetTest do
  use ExUnit.Case, async: false

  alias Plato.{Fleet, Sensor, Alarm}

  setup_all do
    _ = stop_tree()
    {:ok, _} = start_tree()
    on_exit(fn -> stop_tree() end)
    :ok
  end

  setup do
    # Clean rooms from previous tests
    for name <- Fleet.get_rooms() do
      Fleet.remove_room(name)
    end
    Process.sleep(10)
    :ok
  end

  defp start_tree do
    Plato.FleetSupervisor.start_link([])
  end

  defp stop_tree do
    try do
      Supervisor.stop(Plato.FleetSupervisor, :normal, 5000)
    catch
      :exit, _ -> :ok
    end
  end

  describe "fleet lifecycle" do
    test "starts with no rooms" do
      rooms = Fleet.get_rooms()
      assert rooms == []
    end

    test "add a room" do
      {:ok, "engine"} = Fleet.add_room("engine", sensors: [
        Sensor.new("temperature", 72.0)
      ])
      rooms = Fleet.get_rooms()
      assert "engine" in rooms
    end

    test "add multiple rooms" do
      Fleet.add_room("engine", sensors: [Sensor.new("temp", 72.0)])
      Fleet.add_room("bridge", sensors: [Sensor.new("temp", 70.0)])
      Fleet.add_room("cargo", sensors: [Sensor.new("temp", 65.0)])

      rooms = Fleet.get_rooms()
      assert length(rooms) == 3
    end

    test "cannot add duplicate room" do
      {:ok, "dup"} = Fleet.add_room("dup")
      {:error, :already_exists} = Fleet.add_room("dup")
    end

    test "remove a room" do
      Fleet.add_room("temp_room")
      :ok = Fleet.remove_room("temp_room")
      rooms = Fleet.get_rooms()
      refute "temp_room" in rooms
    end

    test "remove non-existent room returns error" do
      {:error, :not_found} = Fleet.remove_room("ghost")
    end
  end

  describe "fleet operations" do
    setup do
      Fleet.add_room("engine", sensors: [
        Sensor.new("temperature", 72.0)
      ], alarms: [
        Alarm.new("overheat", "temperature", :above, 85.0)
      ])
      Fleet.add_room("bridge", sensors: [
        Sensor.new("temperature", 70.0)
      ])
      :ok
    end

    test "broadcast tick to all rooms" do
      {:ok, results} = Fleet.broadcast_tick()
      assert length(results) == 2
      for {_name, result} <- results do
        assert match?({:ok, _}, result)
      end
    end

    test "broadcast actuator to all rooms" do
      {:ok, results} = Fleet.broadcast_actuator("alarm_bell", 1)
      assert length(results) == 2
    end

    test "tick specific room" do
      {:ok, tick} = Fleet.tick_room("engine")
      assert is_integer(tick)
    end

    test "tick non-existent room" do
      {:error, :not_found} = Fleet.tick_room("ghost")
    end

    test "update sensor on specific room" do
      :ok = Fleet.update_sensor("engine", "temperature", 95.0)
      {:status, status} = Fleet.get_room_status("engine")
      assert status.sensor_count == 1
    end

    test "get room status" do
      {:status, status} = Fleet.get_room_status("engine")
      assert status.name == "engine"
    end
  end

  describe "fleet health" do
    test "healthy fleet with no alarms" do
      Fleet.add_room("room1", sensors: [Sensor.new("temp", 72.0)])
      {:ok, health} = Fleet.get_health()
      assert health.status == :healthy
      assert health.total_rooms == 1
      assert health.alive_rooms == 1
    end

    test "alarmed fleet with active alarms" do
      Fleet.add_room("engine", sensors: [
        Sensor.new("temperature", 95.0)
      ], alarms: [
        Alarm.new("overheat", "temperature", :above, 85.0)
      ])
      Fleet.broadcast_tick()
      {:ok, health} = Fleet.get_health()
      assert health.status == :alarmed
      assert health.total_alarms > 0
    end
  end
end
