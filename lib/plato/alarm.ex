defmodule Plato.Alarm do
  @moduledoc """
  An alarm rule for a room sensor.

  Alarms evaluate sensor values against thresholds and fire when conditions
  are met. They support cooldown periods to prevent alarm fatigue.

  The ternary nature of Plato maps naturally to alarm states:
  - -1 (below): value is below low threshold
  -  0 (normal): value is within range
  -  1 (above): value exceeds high threshold
  """

  @type t :: %__MODULE__{
    name: String.t(),
    sensor: String.t(),
    condition: :above | :below | :outside,
    threshold: number(),
    cooldown: non_neg_integer(),
    message: String.t()
  }

  @enforce_keys [:name, :sensor, :condition, :threshold]
  defstruct [:name, :sensor, :condition, :threshold, :message, cooldown: 5]

  @doc "Create a new alarm rule"
  def new(name, sensor, condition, threshold, opts \\ []) do
    %__MODULE__{
      name: name,
      sensor: sensor,
      condition: condition,
      threshold: threshold,
      cooldown: Keyword.get(opts, :cooldown, 5),
      message: Keyword.get(opts, :message, "Alarm #{name} triggered")
    }
  end

  @doc """
  Evaluate an alarm against a sensor value.
  Returns {:fire, message} if the alarm should fire, :ok otherwise.
  """
  def evaluate(%__MODULE__{condition: :above, threshold: t, message: msg}, value) when value > t do
    {:fire, msg}
  end
  def evaluate(%__MODULE__{condition: :below, threshold: t, message: msg}, value) when value < t do
    {:fire, msg}
  end
  def evaluate(%__MODULE__{condition: :outside, threshold: {low, high}, message: msg}, value) do
    if value < low or value > high, do: {:fire, msg}, else: :ok
  end
  def evaluate(_, _), do: :ok
end
