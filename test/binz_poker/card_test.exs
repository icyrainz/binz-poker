defmodule BinzPoker.CardTest do
  use ExUnit.Case, async: true
  alias BinzPoker.Card

  test "creates a card with suit and rank" do
    card = Card.new(:hearts, :ace)
    assert card.suit == :hearts
    assert card.rank == :ace
  end

  test "to_string formats card" do
    card = Card.new(:spades, :king)
    assert Card.to_string(card) == "K♠"
  end

  test "rank_value returns numeric value" do
    assert Card.rank_value(:ace) == 14
    assert Card.rank_value(:king) == 13
    assert Card.rank_value(2) == 2
    assert Card.rank_value(10) == 10
  end
end
