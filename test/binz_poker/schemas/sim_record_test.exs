defmodule BinzPoker.Schemas.SimRecordTest do
  use BinzPoker.DataCase

  alias BinzPoker.Schemas.SimRecord

  test "create a sim and read it back" do
    {:ok, sim} = SimRecord.create(%{max_players: 8, table_size: 4})

    assert sim.hand_count == 0
    assert sim.status == "running"
    assert sim.max_players == 8
    assert sim.table_size == 4
    assert sim.dealer_seat == 0
    assert sim.started_at != nil

    reloaded = SimRecord.get(sim.id)
    assert reloaded.id == sim.id
    assert reloaded.status == "running"
  end

  test "get_current returns the latest running sim" do
    {:ok, _sim1} = SimRecord.create(%{})
    {:ok, sim2} = SimRecord.create(%{})

    current = SimRecord.get_current()
    assert current.id == sim2.id
  end

  test "update_fields persists changes" do
    {:ok, sim} = SimRecord.create(%{})
    {:ok, updated} = SimRecord.update_fields(sim.id, %{status: "paused", max_players: 12})

    assert updated.status == "paused"
    assert updated.max_players == 12
  end

  test "increment_hand_count increases by one" do
    {:ok, sim} = SimRecord.create(%{})
    assert sim.hand_count == 0

    {:ok, updated} = SimRecord.increment_hand_count(sim.id)
    assert updated.hand_count == 1

    {:ok, updated2} = SimRecord.increment_hand_count(sim.id)
    assert updated2.hand_count == 2
  end
end
