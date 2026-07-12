defmodule Plato.ProtocolTest do
  use ExUnit.Case, async: true

  alias Plato.Protocol

  describe "parse/1" do
    test "parses 'tick'" do
      assert Protocol.parse("tick") == {:tick, %{}}
    end

    test "parses 'tick' with whitespace" do
      assert Protocol.parse("  tick  ") == {:tick, %{}}
    end

    test "parses 'history 5'" do
      assert Protocol.parse("history 5") == {:history, %{count: 5}}
    end

    test "parses 'history' with default count" do
      assert Protocol.parse("history") == {:history, %{count: 10}}
    end

    test "parses 'actuator pump 1'" do
      assert Protocol.parse("actuator pump 1") == {:actuator, %{name: "pump", value: 1.0}}
    end

    test "parses 'actuator valve 0'" do
      assert Protocol.parse("actuator valve 0") == {:actuator, %{name: "valve", value: 0.0}}
    end

    test "parses 'actuator throttle 0.5'" do
      assert Protocol.parse("actuator throttle 0.5") == {:actuator, %{name: "throttle", value: 0.5}}
    end

    test "parses 'alarm list'" do
      assert Protocol.parse("alarm list") == {:alarm_list, %{}}
    end

    test "parses 'alarm set' with full condition" do
      result = Protocol.parse("alarm set overheat coolant_temp_c > 95 30")
      assert {:alarm_set, %{id: "overheat", condition: cond_str, cooldown: 30}} = result
      assert cond_str =~ "coolant_temp_c"
      assert cond_str =~ ">"
      assert cond_str =~ "95"
    end

    test "parses 'alarm set' with <= operator" do
      result = Protocol.parse("alarm set low_pressure pressure <= 50 60")
      assert {:alarm_set, %{id: "low_pressure"}} = result
    end

    test "rejects invalid alarm set operator" do
      assert {:unknown, _} = Protocol.parse("alarm set test foo ~= 50 30")
    end

    test "parses 'subscribe'" do
      assert Protocol.parse("subscribe") == {:subscribe, %{}}
    end

    test "parses 'unsubscribe'" do
      assert Protocol.parse("unsubscribe") == {:unsubscribe, %{}}
    end

    test "parses 'help'" do
      assert Protocol.parse("help") == {:help, %{}}
    end

    test "parses 'quit'" do
      assert Protocol.parse("quit") == {:quit, %{}}
    end

    test "parses 'alarms' as alias for alarm list" do
      assert Protocol.parse("alarms") == {:alarm_list, %{}}
    end

    test "empty string returns error" do
      assert {:unknown, _} = Protocol.parse("")
    end

    test "unknown command" do
      assert {:unknown, msg} = Protocol.parse("foobar")
      assert msg =~ "unknown command"
    end
  end

  describe "format_response/1" do
    test "formats tick response as JSON with timestamp" do
      result = Protocol.format_response({:ok, %{tick: 42, sensors: %{"temp" => 22.5}}})
      assert result =~ "\"type\":\"tick\""
      assert result =~ "\"seq\":42"
      assert result =~ "\"temp\":"
      # Should not have hardcoded 0.0 timestamp
      refute result =~ "\"t\":0.0"
    end

    test "formats error response as JSON" do
      result = Protocol.format_response({:error, "bad command"})
      assert result =~ "\"type\":\"error\""
      assert result =~ "bad command"
    end

    test "formats alarm_list with full fields" do
      alarms = [
        %{id: "overheat", condition: "coolant_temp_c > 95", cooldown_sec: 30, last_triggered: 1749234437.0, state: "active"},
        %{id: "bilge_high", condition: "bilge_cm > 10", cooldown_sec: 60, last_triggered: nil, state: "idle"}
      ]
      result = Protocol.format_response({:alarms, alarms})
      assert result =~ "\"type\":\"alarm_list\""
      assert result =~ "\"overheat\""
      assert result =~ "\"cooldown_sec\":30"
      assert result =~ "\"last_triggered\":1749234437"
      assert result =~ "\"state\":\"active\""
      assert result =~ "\"last_triggered\":null"
    end

    test "formats alarm_set ack" do
      result = Protocol.format_response({:alarm_set_ack, "overheat"})
      assert result =~ "\"type\":\"ack\""
      assert result =~ "\"command\":\"alarm_set\""
      assert result =~ "\"id\":\"overheat\""
    end

    test "formats subscribed with tick_hz" do
      result = Protocol.format_response(:subscribed)
      assert result =~ "\"type\":\"subscribed\""
      assert result =~ "\"tick_hz\""
    end

    test "formats unsubscribed" do
      result = Protocol.format_response(:unsubscribed)
      assert result =~ "\"type\":\"unsubscribed\""
    end

    test "formats bye" do
      result = Protocol.format_response(:bye)
      assert result =~ "\"type\":\"bye\""
    end

    test "formats help with all commands" do
      result = Protocol.format_response(:help)
      assert result =~ "\"type\":\"help\""
      assert result =~ "tick"
      assert result =~ "history"
      assert result =~ "alarm list"
      assert result =~ "alarm set"
    end

    test "formats history with timestamps" do
      entries = [
        %{tick: 30, t: 1749234400.0, sensors: %{"temp" => 95.0}},
        %{tick: 31, t: 1749234405.0, sensors: %{"temp" => 96.0}}
      ]
      result = Protocol.format_response({:history, entries})
      assert result =~ "\"type\":\"history\""
      assert result =~ "\"count\":2"
      assert result =~ "1749234400"
      assert result =~ "1749234405"
    end
  end

  describe "Alarm conditions" do
    test "all 6 spec operators are parseable" do
      for op <- ["<", ">", "==", "!=", "<=", ">="] do
        assert {:ok, _} = Plato.Alarm.parse_condition(op)
      end
    end

    test "invalid operator returns error" do
      assert :error = Plato.Alarm.parse_condition("~=")
    end

    test "condition to string round-trips" do
      assert "<" == Plato.Alarm.condition_to_string(:lt)
      assert ">" == Plato.Alarm.condition_to_string(:gt)
      assert "==" == Plato.Alarm.condition_to_string(:eq)
      assert "!=" == Plato.Alarm.condition_to_string(:ne)
      assert "<=" == Plato.Alarm.condition_to_string(:le)
      assert ">=" == Plato.Alarm.condition_to_string(:ge)
    end

    test "evaluate all conditions" do
      a1 = Plato.Alarm.new("test1", "temp", :gt, 90.0)
      assert {:fire, _} = Plato.Alarm.evaluate(a1, 95.0)
      assert :ok = Plato.Alarm.evaluate(a1, 85.0)

      a2 = Plato.Alarm.new("test2", "temp", :lt, 50.0)
      assert {:fire, _} = Plato.Alarm.evaluate(a2, 40.0)

      a3 = Plato.Alarm.new("test3", "temp", :eq, 100.0)
      assert {:fire, _} = Plato.Alarm.evaluate(a3, 100.0)

      a4 = Plato.Alarm.new("test4", "temp", :ne, 100.0)
      assert {:fire, _} = Plato.Alarm.evaluate(a4, 99.0)

      a5 = Plato.Alarm.new("test5", "temp", :le, 50.0)
      assert {:fire, _} = Plato.Alarm.evaluate(a5, 50.0)

      a6 = Plato.Alarm.new("test6", "temp", :ge, 50.0)
      assert {:fire, _} = Plato.Alarm.evaluate(a6, 50.0)
    end
  end
end
