defmodule BinzPoker.IntegrationTest do
  use BinzPoker.DataCase

  alias BinzPoker.{Table, Bank, PlayerSupervisor, Sim, Player}
  alias BinzPoker.Schemas.{PlayerRecord, SimRecord}

  setup do
    start_supervised!({Registry, keys: :unique, name: BinzPoker.PlayerRegistry})
    bank = start_supervised!({Bank, name: :"bank_int_#{System.unique_integer()}"})
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

    %{table: table, bank: bank, sup: sup, sim: sim}
  end

  defp play_hand_safe(table) do
    case Table.play_hand(table) do
      {:ok, result} -> {:ok, result}
      {:error, :not_enough_players} ->
        :timer.sleep(30)
        Table.play_hand(table)
    end
  end

  test "full game loop: spawn, seat, play hands, billing, DB persistence", %{sim: sim, table: table} do
    # 1. Spawn and seat players
    Sim.spawn_players(sim, 6)

    sim_status = Sim.get_status(sim)
    assert length(sim_status.seated) == 6
    assert length(sim_status.away) == 0

    table_state = Table.get_state(table)
    assert length(table_state.seats) == 6

    # Each player has chips from buy-in
    Enum.each(sim_status.seated, fn p ->
      assert Player.get_chips(p.pid) > 0
    end)

    # 2. DB persistence
    player_id = hd(sim_status.seated).id
    record = PlayerRecord.get_by_player_id(player_id)
    assert record != nil
    assert record.status in ["seated", "away"]
    assert record.chips > 0

    # 3. Play multiple hands
    hands_completed = Enum.reduce(1..20, 0, fn _, acc ->
      case play_hand_safe(table) do
        {:ok, result} ->
          assert is_map(result)
          acc + 1
        _ -> acc
      end
    end)

    :timer.sleep(50)

    # Should have completed at least some hands
    assert hands_completed >= 5

    # 4. Sim tracked hand count via events
    status = Sim.get_status(sim)
    assert status.hands_played == hands_completed

    # 5. Living players still exist
    living = PlayerRecord.get_living_players()
    assert length(living) >= 1
  end
end
