defmodule BinzPoker.Schemas.LeaderboardEntryTest do
  use BinzPoker.DataCase

  alias BinzPoker.Schemas.LeaderboardEntry

  test "record_death creates a leaderboard entry" do
    {:ok, entry} = LeaderboardEntry.record_death(%{
      character_name: "Rico",
      model: "gpt-4o",
      traits: %{aggression: "high"},
      backstory: "A trader.",
      hands_survived: 150,
      peak_budget: 8.50,
      total_winnings: 12.30,
      total_token_cost: 0.89,
      cause_of_death: "bankrupt",
      loans_taken: 2,
      loans_repaid: 1
    })

    assert entry.character_name == "Rico"
    assert entry.hands_survived == 150
  end

  test "top_survivors returns ordered by hands_survived desc" do
    for i <- 1..3 do
      LeaderboardEntry.record_death(%{
        character_name: "Player #{i}",
        model: "mock",
        traits: %{},
        hands_survived: i * 10,
        cause_of_death: "bankrupt"
      })
    end

    top = LeaderboardEntry.top_survivors(2)
    assert length(top) == 2
    assert hd(top).hands_survived == 30
  end
end
