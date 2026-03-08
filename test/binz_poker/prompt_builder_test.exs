defmodule BinzPoker.PromptBuilderTest do
  use ExUnit.Case, async: true
  alias BinzPoker.PromptBuilder
  alias BinzPoker.Character

  test "build_player_system_prompt includes character name" do
    char = Character.new(%{
      name: "Rico",
      backstory: "A former trader who lost everything.",
      traits: %{aggression: :high, risk_tolerance: :high, discipline: :low,
                greed: :high, pride: :medium, desperation: :high,
                deceptiveness: :low, sociability: :high},
      model: "gpt-4o"
    })
    prompt = PromptBuilder.build_player_system_prompt(char)
    assert prompt =~ "Rico"
    assert prompt =~ "former trader"
    assert prompt =~ "thinking tax"
    assert prompt =~ "Binz Poker Room"
  end

  test "build_hand_prompt includes game state" do
    game_state = %{
      hole_cards: "A♠ K♥",
      community_cards: "10♣ J♦ Q♠",
      pot: 150,
      current_bet: 40,
      actions_this_round: ["Seat 2 raised to 40"],
      opponents: [%{seat: 2, chips: 300, style: "aggressive"}]
    }
    prompt = PromptBuilder.build_hand_prompt(game_state)
    assert prompt =~ "A♠"
    assert prompt =~ "150"
    assert prompt =~ "fold|call|raise|all_in"
  end

  test "build_buy_in_prompt includes budget and chip math" do
    prompt = PromptBuilder.build_buy_in_prompt(5.00)
    assert prompt =~ "5.00"
    assert prompt =~ "chips"
    assert prompt =~ "thinking tax"
  end

  test "build_loan_request_prompt includes budget" do
    prompt = PromptBuilder.build_loan_request_prompt(0.35)
    assert prompt =~ "0.35"
    assert prompt =~ "loan"
  end

  test "build_banker_prompt includes player info" do
    player_info = %{
      name: "Rico",
      backstory_summary: "Former trader, reckless.",
      hands_survived: 45,
      chips: 20,
      budget: 0.50,
      win_rate: 0.35,
      existing_loans: [],
      message: "I just need one more chance."
    }
    prompt = PromptBuilder.build_banker_prompt(player_info, 2.00)
    assert prompt =~ "Rico"
    assert prompt =~ "one more chance"
    assert prompt =~ "approve|deny"
  end
end
