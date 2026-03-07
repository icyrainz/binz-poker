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
