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

  # alarm set <id> <sensor> <op> <threshold> <cooldown>
  # e.g. "alarm set low_rpm rpm < 1500 60"
  defp do_parse(["alarm", "set", id | rest]) do
    case rest do
      [sensor, op, threshold_str, cooldown_str] ->
        # Validate operator
        case Plato.Alarm.parse_condition(op) do
          {:ok, _cond} ->
            case Float.parse(threshold_str) do
              {threshold, _} ->
                case Integer.parse(cooldown_str) do
                  {cd, _} ->
                    condition_str = "#{sensor} #{op} #{threshold}"
                    {:alarm_set, %{id: id, condition: condition_str, cooldown: cd}}
                  _ ->
                    {:unknown, "invalid cooldown"}
                end
              :error ->
                {:unknown, "invalid threshold"}
            end
          :error ->
            {:unknown, "invalid condition operator '#{op}'"}
        end
      # Legacy: "alarm set <id> <condition> <cooldown>" where condition is pre-formatted
      [condition, cooldown] ->
        {cd, _} = Integer.parse(cooldown)
        {:alarm_set, %{id: id, condition: condition, cooldown: cd}}
      _ ->
        {:unknown, "usage: alarm set <id> <sensor> <op> <threshold> <cooldown>"}
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

  All responses include real Unix timestamps.
  """
  @spec format_response(term()) :: String.t()
  def format_response({:ok, %{tick: tick_num, sensors: sensors}}) when is_map(sensors) do
    # Tick response with sensor data and real Unix timestamp
    data = sensors
    |> Enum.map(fn {k, v} -> ~s("#{k}":#{format_float(v)}) end)
    |> Enum.join(",")
    ~s({"type":"tick","t":#{unix_timestamp()},"seq":#{tick_num},"data":{#{data}}})
  end

  def format_response({:ok, %{tick: tick_num}}) do
    ~s({"type":"ack","message":"tick #{tick_num}"})
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
      # Real Unix timestamps from entry, or fall back to sequence-based estimate
      t = Map.get(entry, :t, unix_timestamp())
      ~s({"t":#{format_float(t)},"seq":#{Map.get(entry, :tick, 0)},"data":{#{data_str}}})
    end)
    |> Enum.join(",")
    ~s({"type":"history","count":#{length(entries)},"ticks":[#{ticks}]})
  end

  def format_response({:alarms, alarms}) when is_list(alarms) do
    # Full spec-compliant alarm_list with condition, cooldown_sec, last_triggered
    alarm_json = alarms
    |> Enum.map(fn alarm ->
      cond_str = Map.get(alarm, :condition, "")
      cooldown = Map.get(alarm, :cooldown_sec, 30)
      last_t = Map.get(alarm, :last_triggered)
      state = Map.get(alarm, :state, "idle")
      last_t_str = if last_t, do: format_float(last_t), else: "null"
      ~s({"id":"#{Map.get(alarm, :id, "")}","condition":"#{escape_json(cond_str)}","cooldown_sec":#{cooldown},"last_triggered":#{last_t_str},"state":"#{state}"})
    end)
    |> Enum.join(",")
    ~s({"type":"alarm_list","alarms":[#{alarm_json}]})
  end

  def format_response({:alarm_set_ack, id}) do
    ~s({"type":"ack","command":"alarm_set","id":"#{escape_json(id)}"})
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

  defp unix_timestamp do
    :erlang.system_time(:second)
  end

  defp format_float(v) when is_float(v), do: :erlang.float_to_binary(v, [:compact, decimals: 4])
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
  def execute({:alarm_set, %{id: id, condition: condition, cooldown: cooldown}}, room) do
    Plato.Room.set_alarm(room, %{id: id, condition: condition, cooldown: cooldown})
  end
  def execute({:subscribe, _}, _room), do: :subscribed
  def execute({:unsubscribe, _}, _room), do: :unsubscribed
  def execute({:status, _}, room), do: Plato.Room.get_status(room)
  def execute({:help, _}, _room), do: :help
  def execute({:quit, _}, _room), do: :bye
  def execute({:unknown, msg}, _room), do: {:error, msg}
end
