defmodule Plato.Ternary do
  use Bitwise
  @moduledoc """
  Ternary logic for the Plato system.

  The Plato thesis models every value as one of three states relative to bounds:
  - -1 (below / too low)
  -  0 (normal / within range)
  -  1 (above / too high)

  This maps beautifully to Elixir's pattern matching. Ternary values can be
  packed into integers for compact storage and transmission, with two bits per
  value (encoding -1, 0, 1 plus a fourth state for "no data").

  ## Packing Scheme

  Each ternary value uses 2 bits:
  - 00 → 0 (normal)
  - 01 → 1 (above)
  - 10 → 2 (below = -1)
  - 11 → 3 (no data / error)
  """

  @type trit :: -1 | 0 | 1
  @type trit_or_nil :: trit() | nil

  @doc """
  Classify a value into a trit based on bounds.

  ## Examples

      iex> Plato.Ternary.to_trit(25.0, {20.0, 30.0})
      0
      iex> Plato.Ternary.to_trit(35.0, {20.0, 30.0})
      1
      iex> Plato.Ternary.to_trit(15.0, {20.0, 30.0})
      -1
  """
  @spec to_trit(number(), {number(), number()}) :: trit()
  def to_trit(value, {low, high}) when value < low, do: -1
  def to_trit(value, {_low, high}) when value > high, do: 1
  def to_trit(_, _), do: 0

  @doc "Classify with explicit boundaries (keyword list)"
  def to_trit_kw(value, opts) when is_list(opts) do
    to_trit(value, {Keyword.fetch!(opts, :low), Keyword.fetch!(opts, :high)})
  end

  @doc """
  Encode a trit to 2-bit integer for packing.

  - -1 → 2
  -  0 → 0
  -  1 → 1
  - nil → 3 (no data)
  """
  @spec encode_trit(trit_or_nil()) :: 0..3
  def encode_trit(-1), do: 2
  def encode_trit(0), do: 0
  def encode_trit(1), do: 1
  def encode_trit(nil), do: 3

  @doc """
  Decode a 2-bit integer back to a trit.

  Returns nil for the "no data" code (3).
  """
  @spec decode_trit(0..3) :: trit_or_nil()
  def decode_trit(2), do: -1
  def decode_trit(0), do: 0
  def decode_trit(1), do: 1
  def decode_trit(3), do: nil

  @doc """
  Pack a list of trits into a compact integer.

  Each trit uses 2 bits, packed from least-significant.
  """
  @spec pack([trit_or_nil()]) :: non_neg_integer()
  def pack(trits) do
    trits
    |> Enum.with_index()
    |> Enum.reduce(0, fn {trit, idx}, acc ->
      bor(acc, bsl(encode_trit(trit), idx * 2))
    end)
  end

  @doc """
  Unpack an integer back into a list of trits.

  Takes the count of trits to unpack.
  """
  @spec unpack(non_neg_integer(), non_neg_integer()) :: [trit_or_nil()]
  def unpack(_packed, 0), do: []
  def unpack(packed, count) do
    for i <- 0..(count - 1) do
      decode_trit(band(bsr(packed, i * 2), 0x3))
    end
  end

  @doc """
  Convert a trit to a human-readable label.
  """
  @spec to_label(trit()) :: String.t()
  def to_label(-1), do: "BELOW"
  def to_label(0), do: "NORMAL"
  def to_label(1), do: "ABOVE"

  @doc """
  Classify a map of sensor readings against their bounds.
  Returns a map of sensor_name => trit.
  """
  @spec classify_sensors(map(), map()) :: map()
  def classify_sensors(readings, bounds) do
    Map.new(readings, fn {name, value} ->
      case Map.get(bounds, name) do
        {low, high} -> {name, to_trit(value, {low, high})}
        nil -> {name, nil}
      end
    end)
  end
end
