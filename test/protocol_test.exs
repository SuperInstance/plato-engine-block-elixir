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
      assert Protocol.parse("actuator pump 1") == {:actuator, %{name: "pump", state: 1}}
    end

    test "parses 'actuator valve 0'" do
      assert Protocol.parse("actuator valve 0") == {:actuator, %{name: "valve", state: 0}}
    end

    test "rejects invalid actuator state" do
      assert {:unknown, _} = Protocol.parse("actuator pump 2")
    end

    test "parses 'sensor temperature 72.5'" do
      assert Protocol.parse("sensor temperature 72.5") == {:sensor, %{name: "temperature", value: 72.5}}
    end

    test "parses 'sensor temperature 72' (integer as float)" do
      assert Protocol.parse("sensor temperature 72") == {:sensor, %{name: "temperature", value: 72.0}}
    end

    test "parses 'status'" do
      assert Protocol.parse("status") == {:status, %{}}
    end

    test "parses 'alarms'" do
      assert Protocol.parse("alarms") == {:alarms, %{}}
    end

    test "parses 'help'" do
      assert Protocol.parse("help") == {:help, %{}}
    end

    test "empty string returns error" do
      assert {:unknown, _} = Protocol.parse("")
    end

    test "unknown command" do
      assert {:unknown, msg} = Protocol.parse("foobar")
      assert msg =~ "unknown command"
    end

    test "case insensitive" do
      assert Protocol.parse("TICK") == {:tick, %{}}
      assert Protocol.parse("History 10") == {:history, %{count: 10}}
    end
  end

  describe "format_response/1" do
    test "formats ok response" do
      assert Protocol.format_response({:ok, "done"}) == "OK done"
    end

    test "formats error response" do
      assert Protocol.format_response({:error, "bad"}) == "ERROR bad"
    end

    test "formats alarms response (none)" do
      assert Protocol.format_response({:alarms, []}) == "ALARMS none"
    end

    test "formats alarms response (with names)" do
      assert Protocol.format_response({:alarms, ["overheat", "low_pressure"]}) == "ALARMS overheat, low_pressure"
    end

    test "formats plain :ok" do
      assert Protocol.format_response(:ok) == "OK"
    end
  end
end
