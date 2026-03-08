defmodule BinzPoker.Deck do
  alias BinzPoker.Card

  defstruct cards: []

  def new do
    cards =
      for suit <- Card.suits(), rank <- Card.ranks() do
        Card.new(suit, rank)
      end

    %__MODULE__{cards: cards}
  end

  def shuffle(%__MODULE__{cards: cards} = _deck) do
    %__MODULE__{cards: Enum.shuffle(cards)}
  end

  def deal(%__MODULE__{cards: cards}, n) when length(cards) >= n do
    {dealt, remaining} = Enum.split(cards, n)
    {dealt, %__MODULE__{cards: remaining}}
  end

  def deal(%__MODULE__{}, _n), do: {:error, :not_enough_cards}
end
