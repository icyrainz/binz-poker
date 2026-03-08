defmodule BinzPoker.Schemas.PlayerRecordTest do
  use BinzPoker.DataCase

  alias BinzPoker.Schemas.PlayerRecord
  alias BinzPoker.Schemas.SimRecord

  test "create and retrieve a player record" do
    {:ok, sim} = SimRecord.create(%{})
    {:ok, record} = PlayerRecord.create(%{
      player_id: "p1",
      name: "Rico",
      backstory: "A trader.",
      traits: %{aggression: "high", discipline: "low"},
      model: "gpt-4o",
      sim_id: sim.id
    })

    assert record.player_id == "p1"
    assert record.chips == 0
    assert record.budget == 5.00
    assert record.status == "away"
    assert record.sim_id == sim.id
  end

  test "get_living_players excludes dead" do
    PlayerRecord.create(%{player_id: "p1", name: "A", traits: %{}, model: "m", status: "seated"})
    PlayerRecord.create(%{player_id: "p2", name: "B", traits: %{}, model: "m", status: "dead"})
    PlayerRecord.create(%{player_id: "p3", name: "C", traits: %{}, model: "m", status: "away"})

    living = PlayerRecord.get_living_players()
    ids = Enum.map(living, & &1.player_id)
    assert "p1" in ids
    assert "p3" in ids
    refute "p2" in ids
  end

  test "update_fields persists changes" do
    PlayerRecord.create(%{player_id: "p1", name: "A", traits: %{}, model: "m"})
    {:ok, updated} = PlayerRecord.update_fields("p1", %{chips: 300, status: "seated"})
    assert updated.chips == 300
    assert updated.status == "seated"

    reloaded = PlayerRecord.get_by_player_id("p1")
    assert reloaded.chips == 300
  end
end
