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
