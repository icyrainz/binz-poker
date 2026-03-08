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
