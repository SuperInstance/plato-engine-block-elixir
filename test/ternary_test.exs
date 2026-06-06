defmodule Plato.TernaryTest do
  use ExUnit.Case, async: true

  alias Plato.Ternary

  describe "to_trit/2" do
    test "returns 0 for value within bounds" do
      assert Ternary.to_trit(25.0, {20.0, 30.0}) == 0
    end

    test "returns 1 for value above high bound" do
      assert Ternary.to_trit(35.0, {20.0, 30.0}) == 1
    end

    test "returns -1 for value below low bound" do
      assert Ternary.to_trit(15.0, {20.0, 30.0}) == -1
    end

    test "returns 0 at exact low boundary" do
      assert Ternary.to_trit(20.0, {20.0, 30.0}) == 0
    end

    test "returns 0 at exact high boundary" do
      assert Ternary.to_trit(30.0, {20.0, 30.0}) == 0
    end

    test "works with integer values" do
      assert Ternary.to_trit(5, {0, 10}) == 0
      assert Ternary.to_trit(15, {0, 10}) == 1
      assert Ternary.to_trit(-5, {0, 10}) == -1
    end

    test "works with keyword list bounds" do
      assert Ternary.to_trit_kw(25.0, low: 20.0, high: 30.0) == 0
    end
  end

  describe "encode_trit/1 and decode_trit/1" do
    test "encode -1 → 2" do
      assert Ternary.encode_trit(-1) == 2
    end

    test "encode 0 → 0" do
      assert Ternary.encode_trit(0) == 0
    end

    test "encode 1 → 1" do
      assert Ternary.encode_trit(1) == 1
    end

    test "encode nil → 3" do
      assert Ternary.encode_trit(nil) == 3
    end

    test "decode 2 → -1" do
      assert Ternary.decode_trit(2) == -1
    end

    test "decode 0 → 0" do
      assert Ternary.decode_trit(0) == 0
    end

    test "decode 1 → 1" do
      assert Ternary.decode_trit(1) == 1
    end

    test "decode 3 → nil" do
      assert Ternary.decode_trit(3) == nil
    end

    test "roundtrip: encode then decode returns original" do
      for trit <- [-1, 0, 1, nil] do
        assert Ternary.decode_trit(Ternary.encode_trit(trit)) == trit
      end
    end
  end

  describe "pack/1 and unpack/2" do
    test "pack empty list returns 0" do
      assert Ternary.pack([]) == 0
    end

    test "pack single trit" do
      assert Ternary.pack([0]) == 0
      assert Ternary.pack([1]) == 1
      assert Ternary.pack([-1]) == 2
    end

    test "pack multiple trits" do
      # [1, 0] => bit0=1, bit1=0 => 01
      assert Ternary.pack([1, 0]) == 1
      # [0, 1] => bit0=0, bit1=1 => 10 = 2... no: bit0=0, bit2-3=1 => 4
      assert Ternary.pack([0, 1]) == 4
      # [-1, 0, 1] => bit0-1=2(10), bit2-3=0(00), bit4-5=1(01) => 100010 = 18
      assert Ternary.pack([-1, 0, 1]) == 18
    end

    test "unpack empty returns empty list" do
      assert Ternary.unpack(0, 0) == []
    end

    test "unpack single trit" do
      assert Ternary.unpack(0, 1) == [0]
      assert Ternary.unpack(1, 1) == [1]
      assert Ternary.unpack(2, 1) == [-1]
    end

    test "roundtrip: pack then unpack returns original" do
      trits = [1, 0, -1, 0, 1, -1]
      packed = Ternary.pack(trits)
      assert Ternary.unpack(packed, length(trits)) == trits
    end

    test "roundtrip with nil values" do
      trits = [1, nil, -1, 0]
      packed = Ternary.pack(trits)
      assert Ternary.unpack(packed, length(trits)) == trits
    end

    test "pack and unpack long sequence" do
      trits = for _ <- 1..32, do: Enum.random([-1, 0, 1])
      packed = Ternary.pack(trits)
      assert Ternary.unpack(packed, length(trits)) == trits
    end
  end

  describe "to_label/1" do
    test "-1 is BELOW" do
      assert Ternary.to_label(-1) == "BELOW"
    end

    test "0 is NORMAL" do
      assert Ternary.to_label(0) == "NORMAL"
    end

    test "1 is ABOVE" do
      assert Ternary.to_label(1) == "ABOVE"
    end
  end

  describe "classify_sensors/2" do
    test "classifies sensor readings against bounds" do
      readings = %{"temp" => 95.0, "pressure" => 14.0}
      bounds = %{"temp" => {60.0, 90.0}, "pressure" => {12.0, 18.0}}
      result = Ternary.classify_sensors(readings, bounds)
      assert result == %{"temp" => 1, "pressure" => 0}
    end

    test "returns nil for sensors without bounds" do
      readings = %{"unknown" => 42.0}
      bounds = %{}
      result = Ternary.classify_sensors(readings, bounds)
      assert result == %{"unknown" => nil}
    end
  end
end
