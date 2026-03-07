defmodule BinzPoker.Card do
  @enforce_keys [:suit, :rank]
  defstruct [:suit, :rank]

  @suits [:hearts, :diamonds, :clubs, :spades]
  @ranks [2, 3, 4, 5, 6, 7, 8, 9, 10, :jack, :queen, :king, :ace]

  def suits, do: @suits
  def ranks, do: @ranks

  def new(suit, rank) when suit in @suits and rank in @ranks do
    %__MODULE__{suit: suit, rank: rank}
  end

  def rank_value(:ace), do: 14
  def rank_value(:king), do: 13
  def rank_value(:queen), do: 12
  def rank_value(:jack), do: 11
  def rank_value(n) when is_integer(n) and n in 2..10, do: n

  def to_string(%__MODULE__{suit: suit, rank: rank}) do
    "#{rank_str(rank)}#{suit_str(suit)}"
  end

  defp rank_str(:ace), do: "A"
  defp rank_str(:king), do: "K"
  defp rank_str(:queen), do: "Q"
  defp rank_str(:jack), do: "J"
  defp rank_str(n), do: Integer.to_string(n)

  defp suit_str(:hearts), do: "♥"
  defp suit_str(:diamonds), do: "♦"
  defp suit_str(:clubs), do: "♣"
  defp suit_str(:spades), do: "♠"
end
