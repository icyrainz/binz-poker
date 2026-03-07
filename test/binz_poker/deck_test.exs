defmodule BinzPoker.DeckTest do
  use ExUnit.Case, async: true
  alias BinzPoker.Deck

  test "new deck has 52 cards" do
    deck = Deck.new()
    assert length(deck.cards) == 52
  end

  test "all cards are unique" do
    deck = Deck.new()
    assert length(Enum.uniq(deck.cards)) == 52
  end

  test "shuffle randomizes order" do
    deck1 = Deck.new()
    deck2 = Deck.shuffle(deck1)
    refute deck1.cards == deck2.cards
  end

  test "deal takes N cards off the top" do
    deck = Deck.new() |> Deck.shuffle()
    {cards, remaining} = Deck.deal(deck, 2)
    assert length(cards) == 2
    assert length(remaining.cards) == 50
  end

  test "deal errors when not enough cards" do
    deck = %Deck{cards: []}
    assert {:error, :not_enough_cards} = Deck.deal(deck, 1)
  end
end
