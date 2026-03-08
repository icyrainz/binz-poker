defmodule BinzPoker.DecisionEngine.RandomTest do
  use ExUnit.Case, async: true
  alias BinzPoker.DecisionEngine.Random

  test "decide returns a valid action" do
    game_state = %{
      hole_cards: [%{suit: :hearts, rank: :ace}, %{suit: :spades, rank: :king}],
      community_cards: [],
      pot: 30,
      current_bet: 10,
      min_raise: 20,
      player_chips: 200
    }
    character = %{name: "Test Player", traits: %{}}

    {:ok, decision} = Random.decide(game_state, character)
    assert decision.action in [:fold, :call, :raise, :all_in]
    assert is_binary(decision.reasoning)
    assert is_binary(decision.talk)
  end

  test "decide respects current bet (can't raise more than chips)" do
    game_state = %{
      hole_cards: [],
      community_cards: [],
      pot: 100,
      current_bet: 50,
      min_raise: 100,
      player_chips: 60
    }
    character = %{name: "Broke Player", traits: %{}}

    for _ <- 1..50 do
      {:ok, decision} = Random.decide(game_state, character)
      if decision.action == :raise do
        assert decision.amount <= 60
      end
    end
  end
end
