defmodule Plato.Protocol do
  @moduledoc """
  Text protocol parser for the Plato system.

  Commands follow a simple text format:
  - `tick` — advance the room one tick
  - `history <n>` — get last n history entries
  - `actuator <name> <state>` — set an actuator (0 or 1)
  - `sensor <name> <value>` — update a sensor value
  - `status` — get room status
  - `alarms` — list active alarms
  - `help` — show available commands

  This is the same text protocol used in the Rust implementation,
  but parsed with Elixir pattern matching.
  """

  @type command :: {
    :tick | :history | :actuator | :sensor | :status | :alarms | :help | :unknown,
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
      {:actuator, %{name: "pump", state: 1}}

      iex> Plato.Protocol.parse("sensor temperature 72.5")
      {:sensor, %{name: "temperature", value: 72.5}}
  """
  @spec parse(String.t()) :: command()
  def parse(input) do
    input
    |> String.trim()
    |> String.downcase()
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
  defp do_parse(["actuator", name, state]) do
    case Integer.parse(state) do
      {s, ""} when s in [0, 1] -> {:actuator, %{name: name, state: s}}
      _ -> {:unknown, "actuator state must be 0 or 1"}
    end
  end
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
  defp do_parse(["alarms"]), do: {:alarms, %{}}
  defp do_parse(["help"]), do: {:help, %{}}
  defp do_parse([cmd | _rest]) when cmd in ["tick", "history", "actuator", "sensor", "status", "alarms", "help"] do
    {:unknown, "invalid arguments for '#{cmd}'"}
  end
  defp do_parse([unknown | _]), do: {:unknown, "unknown command '#{unknown}'"}
  defp do_parse([]), do: {:unknown, "empty command"}

  @doc """
  Format a command response as a text string.
  """
  @spec format_response(term()) :: String.t()
  def format_response({:ok, message}), do: "OK #{message}"
  def format_response({:error, message}), do: "ERROR #{message}"
  def format_response({:status, data}) when is_map(data) do
    parts = Enum.map(data, fn {k, v} -> "#{k}=#{v}" end)
    "STATUS " <> Enum.join(parts, " ")
  end
  def format_response({:history, entries}) when is_list(entries) do
    "HISTORY " <> (entries |> Enum.map(&format_history_entry/1) |> Enum.join("; "))
  end
  def format_response({:alarms, alarms}) when is_list(alarms) do
    if Enum.empty?(alarms) do
      "ALARMS none"
    else
      "ALARMS " <> Enum.join(alarms, ", ")
    end
  end
  def format_response(:ok), do: "OK"
  def format_response(message) when is_binary(message), do: message

  defp format_history_entry({tick, data}) do
    parts = Enum.map(data, fn {k, v} -> "#{k}=#{v}" end)
    "##{tick} " <> Enum.join(parts, ",")
  end
  defp format_history_entry(data) when is_map(data) do
    parts = Enum.map(data, fn {k, v} -> "#{k}=#{v}" end)
    Enum.join(parts, ",")
  end

  @doc """
  Execute a parsed command against a room (via its PID or name).
  Returns the response tuple.
  """
  @spec execute(command(), pid() | atom()) :: term()
  def execute({:tick, _}, room), do: Plato.Room.tick(room)
  def execute({:history, %{count: n}}, room), do: Plato.Room.get_history(room, n)
  def execute({:actuator, %{name: name, state: state}}, room) do
    Plato.Room.set_actuator(room, name, state)
  end
  def execute({:sensor, %{name: name, value: value}}, room) do
    Plato.Room.update_sensor(room, name, value)
  end
  def execute({:status, _}, room), do: Plato.Room.get_status(room)
  def execute({:alarms, _}, room), do: Plato.Room.get_alarms(room)
  def execute({:help, _}, _room) do
    {:ok, "Commands: tick, history <n>, actuator <name> <0|1>, sensor <name> <value>, status, alarms, help"}
  end
  def execute({:unknown, msg}, _room), do: {:error, msg}
end
