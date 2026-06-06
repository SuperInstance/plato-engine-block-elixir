defmodule Plato.Sensor do
  @moduledoc """
  A sensor reading from a room.

  Each sensor has a name, a numeric value, and optional bounds
  that define the normal operating range.
  """

  @type t :: %__MODULE__{
    name: String.t(),
    value: number(),
    unit: String.t(),
    low: number() | nil,
    high: number() | nil
  }

  @enforce_keys [:name, :value]
  defstruct [:name, :value, :unit, :low, :high]

  @doc "Create a new sensor reading"
  def new(name, value, opts \\ []) do
    %__MODULE__{
      name: name,
      value: value,
      unit: Keyword.get(opts, :unit, ""),
      low: Keyword.get(opts, :low),
      high: Keyword.get(opts, :high)
    }
  end

  @doc "Check if the sensor value is within bounds"
  def in_bounds?(%__MODULE__{value: v, low: low, high: high}) when is_number(low) and is_number(high) do
    v >= low and v <= high
  end
  def in_bounds?(_), do: true

  @doc "Check if sensor value exceeds high threshold"
  def exceeds_high?(%__MODULE__{value: v, high: high}) when is_number(high), do: v > high
  def exceeds_high?(_), do: false

  @doc "Check if sensor value below low threshold"
  def below_low?(%__MODULE__{value: v, low: low}) when is_number(low), do: v < low
  def below_low?(_), do: false
end
