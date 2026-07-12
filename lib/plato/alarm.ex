defmodule Plato.Alarm do
  @moduledoc """
  An alarm rule for a room sensor.

  Alarms evaluate sensor values against thresholds and fire when conditions
  are met. They support cooldown periods to prevent alarm fatigue.

  Supports all 6 PLATO Wire Protocol v0.1 conditions:
  - `:lt` (<), `:gt` (>), `:eq` (==), `:ne` (!=), `:le` (<=), `:ge` (>=)
  - Legacy aliases: `:above` (>), `:below` (<), `:outside` (range check)
  """

  @type condition :: :lt | :gt | :eq | :ne | :le | :ge | :above | :below | :outside
  @type t :: %__MODULE__{
    name: String.t(),
    sensor: String.t(),
    condition: condition(),
    threshold: number() | {number(), number()},
    cooldown: non_neg_integer(),
    last_triggered: float() | nil,
    message: String.t()
  }

  @enforce_keys [:name, :sensor, :condition, :threshold]
  defstruct [:name, :sensor, :condition, :threshold, :message, :last_triggered, cooldown: 30]

  @doc "Create a new alarm rule"
  def new(name, sensor, condition, threshold, opts \\ []) do
    %__MODULE__{
      name: name,
      sensor: sensor,
      condition: condition,
      threshold: threshold,
      cooldown: Keyword.get(opts, :cooldown, 30),
      message: Keyword.get(opts, :message, "Alarm #{name} triggered"),
      last_triggered: nil
    }
  end

  @doc """
  Evaluate an alarm against a sensor value.
  Returns {:fire, message} if the alarm should fire, :ok otherwise.

  Supports all 6 spec conditions plus legacy aliases.
  """
  # Spec conditions
  def evaluate(%__MODULE__{condition: :lt, threshold: t, message: msg}, value) when value < t, do: {:fire, msg}
  def evaluate(%__MODULE__{condition: :gt, threshold: t, message: msg}, value) when value > t, do: {:fire, msg}
  def evaluate(%__MODULE__{condition: :eq, threshold: t, message: msg}, value) when value == t, do: {:fire, msg}
  def evaluate(%__MODULE__{condition: :ne, threshold: t, message: msg}, value) when value != t, do: {:fire, msg}
  def evaluate(%__MODULE__{condition: :le, threshold: t, message: msg}, value) when value <= t, do: {:fire, msg}
  def evaluate(%__MODULE__{condition: :ge, threshold: t, message: msg}, value) when value >= t, do: {:fire, msg}

  # Legacy aliases
  def evaluate(%__MODULE__{condition: :above, threshold: t, message: msg}, value) when value > t, do: {:fire, msg}
  def evaluate(%__MODULE__{condition: :below, threshold: t, message: msg}, value) when value < t, do: {:fire, msg}
  def evaluate(%__MODULE__{condition: :outside, threshold: {low, high}, message: msg}, value) do
    if value < low or value > high, do: {:fire, msg}, else: :ok
  end

  def evaluate(_, _), do: :ok

  @doc "Convert condition to spec operator string for JSON serialization"
  @spec condition_to_string(condition()) :: String.t()
  def condition_to_string(:lt), do: "<"
  def condition_to_string(:gt), do: ">"
  def condition_to_string(:eq), do: "=="
  def condition_to_string(:ne), do: "!="
  def condition_to_string(:le), do: "<="
  def condition_to_string(:ge), do: ">="
  def condition_to_string(:above), do: ">"
  def condition_to_string(:below), do: "<"
  def condition_to_string(:outside), do: "outside"

  @doc "Parse a condition operator string into an atom"
  @spec parse_condition(String.t()) :: {:ok, condition()} | :error
  def parse_condition("<"), do: {:ok, :lt}
  def parse_condition(">"), do: {:ok, :gt}
  def parse_condition("=="), do: {:ok, :eq}
  def parse_condition("!="), do: {:ok, :ne}
  def parse_condition("<="), do: {:ok, :le}
  def parse_condition(">="), do: {:ok, :ge}
  def parse_condition(_), do: :error
end
