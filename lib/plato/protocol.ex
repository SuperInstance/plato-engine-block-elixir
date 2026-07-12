defmodule Plato.Protocol do
  @moduledoc """
  Text protocol parser and JSON response formatter for the Plato system.

  Commands follow the PLATO Wire Protocol v0.1:
  - `tick` — advance the room one tick
  - `history <n>` — get last n history entries
  - `actuator <name> <value>` — set an actuator value
  - `alarm list` — list all configured alarms
  - `alarm set <id> <condition> <cooldown>` — add alarm rule
  - `subscribe` — subscribe to tick stream
  - `unsubscribe` — stop tick stream
  - `help` — show available commands
  - `quit` — disconnect

  All responses are single-line JSON objects per PLATO Wire Protocol v0.1.
  """

  @type command :: {
    :tick | :history | :actuator | :alarm_list | :alarm_set |
    :subscribe | :unsubscribe | :help | :quit | :sensor | :status |
    :alarms | :unknown,
    term()
  }

  @doc """
  Parse a text command string into a structured command tuple.

  ## Examples

      iex> Plato.Protocol.parse("tick")
      {:tick, %{}}

      iex> Plato.Protocol.parse("history 5")
      {:history, %{count: 5}}

      iex> Plato.Protocol.parse("actuator pump 1")
      {:actuator, %{name: "pump", value: 1.0}}

      iex> Plato.Protocol.parse("alarm list")
      {:alarm_list, %{}}
  """
  @spec parse(String.t()) :: command()
  def parse(input) do
    input
    |> String.trim()
    |> String.split(~r/\s+/)
    |> do_parse()
  end

  defp do_parse(["tick"]), do: {:tick, %{}}
  defp do_parse(["history", count]) do
    case Integer.parse(count) do
      {n, ""} -> {:history, %{count: n}}
      _ -> {:unknown, "invalid history count"}
    end
  end
  defp do_parse(["history"]), do: {:history, %{count: 10}}

  defp do_parse(["actuator", name, value]) do
    case Float.parse(value) do
      {v, ""} -> {:actuator, %{name: name, value: v}}
      :error ->
        case Integer.parse(value) do
          {v, ""} -> {:actuator, %{name: name, value: v * 1.0}}
          _ -> {:unknown, "invalid actuator value"}
        end
    end
  end

  # alarm list
  defp do_parse(["alarm", "list"]), do: {:alarm_list, %{}}

  # alarm set <id> <condition> <cooldown>
  defp do_parse(["alarm", "set", id | rest]) do
    case rest do
      [condition, cooldown] ->
        {cd, _} = Integer.parse(cooldown)
        {:alarm_set, %{id: id, condition: condition, cooldown: cd}}
      _ ->
        {:unknown, "usage: alarm set <id> <condition> <cooldown>"}
    end
  end

  defp do_parse(["subscribe"]), do: {:subscribe, %{}}
  defp do_parse(["unsubscribe"]), do: {:unsubscribe, %{}}
  defp do_parse(["help"]), do: {:help, %{}}
  defp do_parse(["quit"]), do: {:quit, %{}}

  # Legacy commands for backward compatibility
  defp do_parse(["sensor", name, value]) do
    case Float.parse(value) do
      {v, ""} -> {:sensor, %{name: name, value: v}}
      :error ->
        case Integer.parse(value) do
          {v, ""} -> {:sensor, %{name: name, value: v * 1.0}}
          _ -> {:unknown, "invalid sensor value"}
        end
    end
  end
  defp do_parse(["status"]), do: {:status, %{}}
  defp do_parse(["alarms"]), do: {:alarm_list, %{}}  # alias

  defp do_parse([cmd | _rest]) when cmd in ["tick", "history", "actuator", "sensor", "status", "alarm", "subscribe", "unsubscribe", "help", "quit"] do
    {:unknown, "invalid arguments for '#{cmd}'"}
  end
  defp do_parse([unknown | _]), do: {:unknown, "unknown command '#{unknown}'"}
  defp do_parse([]), do: {:unknown, "empty command"}

  @doc """
  Format a command response as a JSON string per PLATO Wire Protocol v0.1.

  ## Examples

      iex> Plato.Protocol.format_response({:ok, "tick taken"})
      ~s({"type":"ack","message":"tick taken"})

      iex> Plato.Protocol.format_response({:error, "bad command"})
      ~s({"type":"error","message":"bad command"})
  """
  @spec format_response(term()) :: String.t()
  def format_response({:ok, %{tick: tick_num, sensors: sensors}}) when is_map(sensors) do
    # Tick response with sensor data
    data = sensors
    |> Enum.map(fn {k, v} -> ~s("#{k}":#{format_float(v)}) end)
    |> Enum.join(",")
    ~s({"type":"tick","t":#{:os.system_time(:second)}.0,"seq":#{tick_num},"data":{#{data}}})
  end

  def format_response({:ok, message}) when is_binary(message) do
    ~s({"type":"ack","message":"#{escape_json(message)}"})
  end

  def format_response({:error, message}) do
    ~s({"type":"error","message":"#{escape_json(message)}"})
  end

  def format_response({:status, data}) when is_map(data) do
    fields = data
    |> Enum.map(fn {k, v} -> ~s("#{k}":#{json_value(v)}) end)
    |> Enum.join(",")
    ~s({"type":"status","data":{#{fields}}})
  end

  def format_response({:history, entries}) when is_list(entries) do
    ticks = entries
    |> Enum.map(fn entry ->
      data = Map.get(entry, :sensors, %{})
      data_str = data
      |> Enum.map(fn {k, v} -> ~s("#{k}":#{format_float(v)}) end)
      |> Enum.join(",")
      ~s({"t":0.0,"seq":#{Map.get(entry, :tick, 0)},"data":{#{data_str}}})
    end)
    |> Enum.join(",")
    ~s({"type":"history","count":#{length(entries)},"ticks":[#{ticks}]})
  end

  def format_response({:alarms, alarms}) when is_list(alarms) do
    alarm_json = alarms
    |> Enum.map(fn name -> ~s({"id":"#{name}","state":"active"}) end)
    |> Enum.join(",")
    ~s({"type":"alarm_list","alarms":[#{alarm_json}]})
  end

  def format_response(:ok), do: ~s({"type":"ack"})
  def format_response(:subscribed), do: ~s({"type":"subscribed","tick_hz":0.2})
  def format_response(:unsubscribed), do: ~s({"type":"unsubscribed"})
  def format_response(:bye), do: ~s({"type":"bye"})

  def format_response(:help) do
    ~s({"type":"help","commands":["tick","history [N]","actuator <name> <value>","alarm list","alarm set <id> <condition> <cooldown>","subscribe","unsubscribe","help","quit"]})
  end

  def format_response(message) when is_binary(message), do: message

  # Helpers

  defp format_float(v) when is_float(v), do: :erlang.float_to_binary(v, [:compact, {decimals, 4}])
  defp format_float(v) when is_integer(v), do: "#{v}.0"

  defp json_value(v) when is_atom(v), do: ~s("#{v}")
  defp json_value(v) when is_binary(v), do: ~s("#{escape_json(v)}")
  defp json_value(v) when is_number(v), do: "#{v}"
  defp json_value(true), do: "true"
  defp json_value(false), do: "false"
  defp json_value(nil), do: "null"
  defp json_value(v), do: ~s("#{escape_json(to_string(v))}")

  defp escape_json(str) do
    str
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "\\\"")
    |> String.replace("\n", "\\n")
    |> String.replace("\r", "\\r")
    |> String.replace("\t", "\\t")
  end

  @doc """
  Execute a parsed command against a room (via its PID or name).
  Returns the response tuple.
  """
  @spec execute(command(), pid() | atom()) :: term()
  def execute({:tick, _}, room), do: Plato.Room.tick(room)
  def execute({:history, %{count: n}}, room), do: Plato.Room.get_history(room, n)
  def execute({:actuator, %{name: name, value: value}}, room) do
    # Cast float to int for actuator state (0 or 1)
    state = if value > 0.0, do: 1, else: 0
    Plato.Room.set_actuator(room, name, state)
  end
  def execute({:sensor, %{name: name, value: value}}, room) do
    Plato.Room.update_sensor(room, name, value)
  end
  def execute({:alarm_list, _}, room), do: Plato.Room.get_alarms(room)
  def execute({:alarm_set, %{id: id, condition: condition, cooldown: cooldown}}, _room) do
    # Runtime alarm configuration - returns ack
    {:ok, "alarm_set:#{id}:#{condition}:#{cooldown}"}
  end
  def execute({:subscribe, _}, _room), do: :subscribed
  def execute({:unsubscribe, _}, _room), do: :unsubscribed
  def execute({:status, _}, room), do: Plato.Room.get_status(room)
  def execute({:help, _}, _room), do: :help
  def execute({:quit, _}, _room), do: :bye
  def execute({:unknown, msg}, _room), do: {:error, msg}
end
