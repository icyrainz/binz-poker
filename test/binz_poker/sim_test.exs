defmodule BinzPoker.SimTest do
  use BinzPoker.DataCase

  alias BinzPoker.{Sim, Bank, PlayerSupervisor, Table, Player}
  alias BinzPoker.Schemas.SimRecord

  setup do
    start_supervised!({Registry, keys: :unique, name: BinzPoker.PlayerRegistry})
    bank = start_supervised!({Bank, name: :"bank_#{System.unique_integer()}"})
    sup = start_supervised!({PlayerSupervisor,
      bank: bank,
      character_gen: BinzPoker.CharacterGen.Hardcoded,
      decision_engine: BinzPoker.DecisionEngine.Random
    })
    table = start_supervised!({Table,
      hand_evaluator: BinzPoker.HandEvaluator.Native,
      auto_start: false
    })
    {:ok, sim_record} = SimRecord.create(%{status: "running"})
    sim = start_supervised!({Sim,
      bank: bank,
      player_supervisor: sup,
      table: table,
      sim_id: sim_record.id,
      max_players: 10,
      table_size: 6
    })
    %{sim: sim, bank: bank, sup: sup, table: table, sim_record: sim_record}
  end

  test "spawn_players creates players, does buy-in, and seats them", %{sim: sim} do
    Sim.spawn_players(sim, 6)
    status = Sim.get_status(sim)
    assert length(status.seated) == 6
    assert length(status.away) == 0
    Enum.each(status.seated, fn p ->
      assert Player.get_chips(p.pid) > 0
    end)
  end

  test "spawn beyond table size puts extras in away", %{sim: sim} do
    Sim.spawn_players(sim, 8)
    status = Sim.get_status(sim)
    assert length(status.seated) == 6
    assert length(status.away) == 2
  end

  test "reacts to hand_result by incrementing counter", %{sim: sim} do
    Sim.spawn_players(sim, 3)
    Phoenix.PubSub.broadcast(BinzPoker.PubSub, "table:events",
      {:hand_result, %{hand_number: 1, winners: %{}, pots: []}})
    :timer.sleep(20)
    status = Sim.get_status(sim)
    assert status.hands_played == 1
  end

  test "reacts to player_busted", %{sim: sim} do
    Sim.spawn_players(sim, 3)
    status = Sim.get_status(sim)
    busted_id = hd(status.seated).id

    Phoenix.PubSub.broadcast(BinzPoker.PubSub, "table:events",
      {:player_busted, busted_id})
    :timer.sleep(50)

    status = Sim.get_status(sim)
    refute Enum.any?(status.seated, &(&1.id == busted_id))
  end

  test "reacts to seat_available by seating away players", %{sim: sim, table: table} do
    Sim.spawn_players(sim, 8)
    status = Sim.get_status(sim)
    assert length(status.away) == 2

    # Simulate the real bust flow: Table removes the player, then broadcasts events
    busted_id = hd(status.seated).id
    Table.leave_seat(table, busted_id)
    Phoenix.PubSub.broadcast(BinzPoker.PubSub, "table:events",
      {:player_busted, busted_id})
    :timer.sleep(30)

    Phoenix.PubSub.broadcast(BinzPoker.PubSub, "table:events",
      {:seat_available, 1})
    :timer.sleep(30)

    status = Sim.get_status(sim)
    # Busted player moved to away, one away player took the freed seat
    assert length(status.seated) == 6
  end

  test "get_status returns current state", %{sim: sim} do
    status = Sim.get_status(sim)
    assert is_list(status.seated)
    assert is_list(status.away)
    assert status.hands_played == 0
    assert status.total_players == 0
  end
end
