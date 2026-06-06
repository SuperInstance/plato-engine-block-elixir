defmodule Plato.IntegrationTest do
  use ExUnit.Case, async: false

  alias Plato.{Fleet, Sensor, Alarm, Protocol}

  setup_all do
    _ = stop_tree()
    {:ok, _} = start_tree()
    on_exit(fn -> stop_tree() end)
    :ok
  end

  setup do
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

  describe "full fleet lifecycle" do
    test "start fleet, tick 50 times, detect crisis, resolve" do
      # Add engine room with sensors and alarms
      Fleet.add_room("engine",
        sensors: [
          Sensor.new("temperature", 72.0, unit: "°F", low: 60.0, high: 90.0),
          Sensor.new("pressure", 14.5, unit: "PSI", low: 12.0, high: 18.0),
          Sensor.new("rpm", 1200, unit: "RPM", low: 800, high: 2000)
        ],
        alarms: [
          Alarm.new("engine_overheat", "temperature", :above, 85.0, message: "ENGINE OVERHEAT"),
          Alarm.new("pressure_drop", "pressure", :below, 12.5, message: "PRESSURE DROPPING"),
          Alarm.new("overspeed", "rpm", :above, 1800, message: "ENGINE OVERSPEED")
        ],
        bounds: %{
          "temperature" => {60.0, 90.0},
          "pressure" => {12.0, 18.0},
          "rpm" => {800, 2000}
        }
      )

      # Add bridge room
      Fleet.add_room("bridge",
        sensors: [
          Sensor.new("heading", 180.0, unit: "°"),
          Sensor.new("speed", 12.5, unit: "knots", low: 0, high: 25)
        ],
        bounds: %{
          "speed" => {0.0, 25.0}
        }
      )

      # Normal operation: tick 20 times
      for _ <- 1..20 do
        Fleet.broadcast_tick()
      end

      # Verify healthy
      {:ok, health} = Fleet.get_health()
      assert health.status == :healthy
      assert health.alive_rooms == 2

      # Simulate crisis: engine overheating
      Fleet.update_sensor("engine", "temperature", 88.0)
      Fleet.update_sensor("engine", "pressure", 11.0)
      Fleet.broadcast_tick()

      # Crisis: alarms should fire
      {:ok, health} = Fleet.get_health()
      assert health.status == :alarmed
      assert health.total_alarms > 0

      # Continue crisis for 10 more ticks
      for _ <- 1..10 do
        Fleet.broadcast_tick()
      end

      # Resolve: bring values back to normal
      Fleet.update_sensor("engine", "temperature", 75.0)
      Fleet.update_sensor("engine", "pressure", 14.5)

      # Tick through cooldown period
      for _ <- 1..15 do
        Fleet.broadcast_tick()
      end

      # Verify healthy again
      {:ok, health} = Fleet.get_health()
      assert health.status == :healthy
      assert health.total_alarms == 0
    end

    test "ternary classification through full cycle" do
      Fleet.add_room("engine",
        sensors: [
          Sensor.new("temp", 72.0)
        ],
        bounds: %{"temp" => {60.0, 90.0}}
      )

      # Normal
      {:ok, trits} = Plato.Room.get_ternary("engine")
      assert trits["temp"] == 0

      # Push above
      Fleet.update_sensor("engine", "temp", 95.0)
      {:ok, trits} = Plato.Room.get_ternary("engine")
      assert trits["temp"] == 1

      # Push below
      Fleet.update_sensor("engine", "temp", 50.0)
      {:ok, trits} = Plato.Room.get_ternary("engine")
      assert trits["temp"] == -1

      # Back to normal
      Fleet.update_sensor("engine", "temp", 72.0)
      {:ok, trits} = Plato.Room.get_ternary("engine")
      assert trits["temp"] == 0
    end

    test "protocol executes commands against room" do
      Fleet.add_room("engine",
        sensors: [Sensor.new("temp", 72.0)],
        bounds: %{"temp" => {60.0, 90.0}}
      )

      # Parse and execute commands
      cmd = Protocol.parse("tick")
      {:ok, _tick} = Protocol.execute(cmd, "engine")

      cmd = Protocol.parse("sensor temp 95.0")
      :ok = Protocol.execute(cmd, "engine")

      cmd = Protocol.parse("tick")
      {:ok, _tick} = Protocol.execute(cmd, "engine")

      cmd = Protocol.parse("status")
      {:status, status} = Protocol.execute(cmd, "engine")
      assert status.tick > 0

      cmd = Protocol.parse("history 5")
      {:history, entries} = Protocol.execute(cmd, "engine")
      assert length(entries) > 0
    end

    test "room process isolation — rooms are independent" do
      Fleet.add_room("room_a", sensors: [Sensor.new("temp", 72.0)])
      Fleet.add_room("room_b", sensors: [Sensor.new("temp", 70.0)])

      # Both rooms alive
      {:status, status_a} = Plato.Room.get_status("room_a")
      {:status, status_b} = Plato.Room.get_status("room_b")
      assert status_a.name == "room_a"
      assert status_b.name == "room_b"

      # Room A ticks independently
      {:ok, _} = Fleet.tick_room("room_a")

      # Room B is unaffected
      {:status, status_b2} = Plato.Room.get_status("room_b")
      assert status_b2.tick == 0
    end

    test "ternary pack/unpack in fleet context" do
      Fleet.add_room("engine",
        sensors: [
          Sensor.new("temp", 72.0),
          Sensor.new("pressure", 14.5),
          Sensor.new("rpm", 1200.0)
        ],
        bounds: %{
          "temp" => {60.0, 90.0},
          "pressure" => {12.0, 18.0},
          "rpm" => {800.0, 2000.0}
        }
      )

      # All normal → packed should be 0 (all trits are 0)
      {:ok, packed, count} = Plato.Room.get_ternary_packed("engine")
      assert packed == 0
      assert count == 3

      # Push one above
      Fleet.update_sensor("engine", "temp", 95.0)
      {:ok, packed, _count} = Plato.Room.get_ternary_packed("engine")
      # Bounds sorted alphabetically: pressure, rpm, temp
      # pressure=0→0, rpm=0→0, temp=1→1 => packed = 0b000001 = 1
      assert packed == 16
    end
  end
end
