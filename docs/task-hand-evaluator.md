### Hand Evaluator

**Files:**

- Create: `lib/binz_poker/hand_evaluator.ex` (behaviour)
- Create: `lib/binz_poker/hand_evaluator/native.ex` (implementation)
- Create: `test/binz_poker/hand_evaluator/native_test.exs`

**Step 1: Define behaviour**

```elixir
# lib/binz_poker/hand_evaluator.ex
defmodule BinzPoker.HandEvaluator do
  alias BinzPoker.Card

  @type hand_rank ::
    :royal_flush | :straight_flush | :four_of_a_kind | :full_house |
    :flush | :straight | :three_of_a_kind | :two_pair | :one_pair | :high_card

  @callback evaluate(cards :: [Card.t()]) :: {:ok, %{rank: hand_rank(), kickers: [integer()]}}
  @callback compare(hand_a :: map(), hand_b :: map()) :: :gt | :lt | :eq

  def impl do
    Application.get_env(:binz_poker, :hand_evaluator, BinzPoker.HandEvaluator.Native)
  end

  def evaluate(cards), do: impl().evaluate(cards)
  def compare(a, b), do: impl().compare(a, b)
end
```

**Step 2: Write failing tests**

```elixir
# test/binz_poker/hand_evaluator/native_test.exs
defmodule BinzPoker.HandEvaluator.NativeTest do
  use ExUnit.Case, async: true
  alias BinzPoker.HandEvaluator.Native
  alias BinzPoker.Card

  defp cards(list) do
    Enum.map(list, fn {rank, suit} -> Card.new(suit, rank) end)
  end

  describe "evaluate/1" do
    test "detects royal flush" do
      hand = cards([{10, :hearts}, {:jack, :hearts}, {:queen, :hearts}, {:king, :hearts}, {:ace, :hearts}])
      assert {:ok, %{rank: :royal_flush}} = Native.evaluate(hand)
    end

    test "detects straight flush" do
      hand = cards([{5, :clubs}, {6, :clubs}, {7, :clubs}, {8, :clubs}, {9, :clubs}])
      assert {:ok, %{rank: :straight_flush}} = Native.evaluate(hand)
    end

    test "detects four of a kind" do
      hand = cards([{8, :hearts}, {8, :diamonds}, {8, :clubs}, {8, :spades}, {:king, :hearts}])
      assert {:ok, %{rank: :four_of_a_kind}} = Native.evaluate(hand)
    end

    test "detects full house" do
      hand = cards([{3, :hearts}, {3, :diamonds}, {3, :clubs}, {10, :spades}, {10, :hearts}])
      assert {:ok, %{rank: :full_house}} = Native.evaluate(hand)
    end

    test "detects flush" do
      hand = cards([{2, :diamonds}, {5, :diamonds}, {8, :diamonds}, {:jack, :diamonds}, {:ace, :diamonds}])
      assert {:ok, %{rank: :flush}} = Native.evaluate(hand)
    end

    test "detects straight" do
      hand = cards([{4, :hearts}, {5, :diamonds}, {6, :clubs}, {7, :spades}, {8, :hearts}])
      assert {:ok, %{rank: :straight}} = Native.evaluate(hand)
    end

    test "detects ace-low straight" do
      hand = cards([{:ace, :hearts}, {2, :diamonds}, {3, :clubs}, {4, :spades}, {5, :hearts}])
      assert {:ok, %{rank: :straight}} = Native.evaluate(hand)
    end

    test "detects three of a kind" do
      hand = cards([{7, :hearts}, {7, :diamonds}, {7, :clubs}, {2, :spades}, {9, :hearts}])
      assert {:ok, %{rank: :three_of_a_kind}} = Native.evaluate(hand)
    end

    test "detects two pair" do
      hand = cards([{4, :hearts}, {4, :diamonds}, {9, :clubs}, {9, :spades}, {:ace, :hearts}])
      assert {:ok, %{rank: :two_pair}} = Native.evaluate(hand)
    end

    test "detects one pair" do
      hand = cards([{6, :hearts}, {6, :diamonds}, {2, :clubs}, {8, :spades}, {:king, :hearts}])
      assert {:ok, %{rank: :one_pair}} = Native.evaluate(hand)
    end

    test "detects high card" do
      hand = cards([{2, :hearts}, {5, :diamonds}, {8, :clubs}, {:jack, :spades}, {:ace, :hearts}])
      assert {:ok, %{rank: :high_card}} = Native.evaluate(hand)
    end

    test "picks best 5 from 7 cards" do
      # 7 cards: should find the flush in diamonds
      hand = cards([
        {2, :diamonds}, {5, :diamonds}, {8, :diamonds}, {:jack, :diamonds}, {:ace, :diamonds},
        {3, :hearts}, {:king, :clubs}
      ])
      assert {:ok, %{rank: :flush}} = Native.evaluate(hand)
    end
  end

  describe "compare/2" do
    test "higher rank wins" do
      flush = %{rank: :flush, kickers: [14, 11, 8, 5, 2]}
      straight = %{rank: :straight, kickers: [8]}
      assert Native.compare(flush, straight) == :gt
      assert Native.compare(straight, flush) == :lt
    end

    test "same rank compares kickers" do
      pair_kings = %{rank: :one_pair, kickers: [13, 10, 8, 3]}
      pair_jacks = %{rank: :one_pair, kickers: [11, 10, 8, 3]}
      assert Native.compare(pair_kings, pair_jacks) == :gt
    end

    test "identical hands are equal" do
      hand = %{rank: :flush, kickers: [14, 11, 8, 5, 2]}
      assert Native.compare(hand, hand) == :eq
    end
  end
end
```

**Step 3: Run test to verify it fails**

```bash
mix test test/binz_poker/hand_evaluator/native_test.exs
```

**Step 4: Implement Native hand evaluator**

This is the most complex pure-logic module. Implement `BinzPoker.HandEvaluator.Native` with:

- `evaluate/1` — takes 5-7 cards, finds best 5-card hand, returns `{:ok, %{rank, kickers}}`
- `compare/2` — compares two evaluated hands
- Must handle all combinations when given 7 cards (Texas Hold'em: 2 hole + 5 community)
- Use `rank_order` list for comparison: `[:royal_flush, :straight_flush, :four_of_a_kind, :full_house, :flush, :straight, :three_of_a_kind, :two_pair, :one_pair, :high_card]`

```elixir
# lib/binz_poker/hand_evaluator/native.ex
defmodule BinzPoker.HandEvaluator.Native do
  @behaviour BinzPoker.HandEvaluator
  alias BinzPoker.Card

  @rank_order [:royal_flush, :straight_flush, :four_of_a_kind, :full_house,
               :flush, :straight, :three_of_a_kind, :two_pair, :one_pair, :high_card]

  @impl true
  def evaluate(cards) when length(cards) >= 5 do
    cards
    |> combinations(5)
    |> Enum.map(&evaluate_five/1)
    |> Enum.max_by(fn %{rank: rank, kickers: kickers} ->
      {-Enum.find_index(@rank_order, &(&1 == rank)), kickers}
    end)
    |> then(&{:ok, &1})
  end

  @impl true
  def compare(%{rank: rank_a, kickers: k_a}, %{rank: rank_b, kickers: k_b}) do
    idx_a = Enum.find_index(@rank_order, &(&1 == rank_a))
    idx_b = Enum.find_index(@rank_order, &(&1 == rank_b))

    cond do
      idx_a < idx_b -> :gt
      idx_a > idx_b -> :lt
      k_a > k_b -> :gt
      k_a < k_b -> :lt
      true -> :eq
    end
  end

  defp evaluate_five(cards) do
    values = cards |> Enum.map(&Card.rank_value(&1.rank)) |> Enum.sort(:desc)
    suits = Enum.map(cards, & &1.suit)
    is_flush = length(Enum.uniq(suits)) == 1
    is_straight = straight?(values)
    groups = values |> Enum.frequencies() |> Map.values() |> Enum.sort(:desc)

    cond do
      is_flush and values == [14, 13, 12, 11, 10] ->
        %{rank: :royal_flush, kickers: values}

      is_flush and is_straight ->
        %{rank: :straight_flush, kickers: [straight_high(values)]}

      groups == [4, 1] ->
        {quad, kicker} = split_groups(values, 4)
        %{rank: :four_of_a_kind, kickers: quad ++ kicker}

      groups == [3, 2] ->
        {trips, pair} = split_groups(values, 3)
        %{rank: :full_house, kickers: trips ++ pair}

      is_flush ->
        %{rank: :flush, kickers: values}

      is_straight ->
        %{rank: :straight, kickers: [straight_high(values)]}

      groups == [3, 1, 1] ->
        {trips, rest} = split_groups(values, 3)
        %{rank: :three_of_a_kind, kickers: trips ++ Enum.sort(rest, :desc)}

      groups == [2, 2, 1] ->
        freqs = Enum.frequencies(values)
        pairs = freqs |> Enum.filter(fn {_, c} -> c == 2 end) |> Enum.map(&elem(&1, 0)) |> Enum.sort(:desc)
        kicker = freqs |> Enum.filter(fn {_, c} -> c == 1 end) |> Enum.map(&elem(&1, 0))
        %{rank: :two_pair, kickers: pairs ++ kicker}

      groups == [2, 1, 1, 1] ->
        {pair, rest} = split_groups(values, 2)
        %{rank: :one_pair, kickers: pair ++ Enum.sort(rest, :desc)}

      true ->
        %{rank: :high_card, kickers: values}
    end
  end

  defp straight?(values) do
    sorted = Enum.sort(values, :desc)
    consecutive?(sorted) or sorted == [14, 5, 4, 3, 2]
  end

  defp consecutive?([_]), do: true
  defp consecutive?([a, b | rest]), do: a - b == 1 and consecutive?([b | rest])

  defp straight_high(values) do
    sorted = Enum.sort(values, :desc)
    if sorted == [14, 5, 4, 3, 2], do: 5, else: hd(sorted)
  end

  defp split_groups(values, target_count) do
    freqs = Enum.frequencies(values)
    group = freqs |> Enum.filter(fn {_, c} -> c == target_count end) |> Enum.map(&elem(&1, 0)) |> Enum.sort(:desc)
    rest = freqs |> Enum.filter(fn {_, c} -> c != target_count end) |> Enum.map(&elem(&1, 0)) |> Enum.sort(:desc)
    {group, rest}
  end

  defp combinations(_, 0), do: [[]]
  defp combinations([], _), do: []
  defp combinations([h | t], k) do
    (for sub <- combinations(t, k - 1), do: [h | sub]) ++ combinations(t, k)
  end
end
```

**Step 5: Run tests**

```bash
mix test test/binz_poker/hand_evaluator/native_test.exs
```

Expected: all PASS

**Step 6: Commit**

```bash
git add lib/binz_poker/hand_evaluator.ex lib/binz_poker/hand_evaluator/native.ex test/binz_poker/hand_evaluator/native_test.exs
git commit -m "feat: add HandEvaluator behaviour and Native implementation"
```

---
