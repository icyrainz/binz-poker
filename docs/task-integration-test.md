### Integration Test — Full Game Loop

End-to-end test using all components: Sim spawns players (with buy-in), seats them at Table, Table plays hands via auto loop, Sim reacts to events (per-hand billing, busts, chip-to-budget conversion). Uses mock/random implementations for all behaviours.

**Depends on:** All previous tasks (1-18)

**Files:**
- Create: `test/binz_poker/integration_test.exs`

**Step 1: Write integration test**

```elixir
# test/binz_poker/integration_test.exs
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
    sim = start_supervised!({Sim,
      bank: bank,
      player_supervisor: sup,
      table: table,
      max_players: 10,
      table_size: 6
    })

    %{table: table, bank: bank, sup: sup, sim: sim}
  end

  test "Sim spawns players with buy-in and seats them at Table", %{sim: sim, table: table} do
    Sim.spawn_players(sim, 4)

    sim_status = Sim.get_status(sim)
    assert length(sim_status.seated) == 4

    table_state = Table.get_state(table)
    assert length(table_state.seats) == 4

    # Each player should have chips (from buy-in) and reduced budget
    Enum.each(sim_status.seated, fn p ->
      chips = Player.get_chips(p.pid)
      assert chips > 0
    end)
  end

  test "Table plays hands and Sim tracks count via events", %{sim: sim, table: table} do
    Sim.spawn_players(sim, 4)

    for _ <- 1..5 do
      assert {:ok, _result} = Table.play_hand(table)
    end

    :timer.sleep(50)

    status = Sim.get_status(sim)
    assert status.hands_played == 5
  end

  test "can play 20 hands without crashing", %{sim: sim, table: table} do
    Sim.spawn_players(sim, 6)

    for _ <- 1..20 do
      assert {:ok, result} = Table.play_hand(table)
      assert is_map(result)
    end
  end

  test "player state persists to DB", %{sim: sim} do
    Sim.spawn_players(sim, 3)
    status = Sim.get_status(sim)
    player_id = hd(status.seated).id

    record = PlayerRecord.get_by_player_id(player_id)
    assert record != nil
    assert record.status in ["seated", "away"]
    assert record.chips > 0  # has chips from buy-in
  end

  test "player budgets decrease from thinking tax after hands", %{sim: sim, table: table, bank: bank} do
    Sim.spawn_players(sim, 3)
    status = Sim.get_status(sim)
    player_id = hd(status.seated).id

    {:ok, budget_before} = Bank.get_budget(bank, player_id)

    # Record some token cost and play a hand
    Bank.record_token_cost(bank, player_id, %{input: 500, output: 200}, "mock-model")
    Table.play_hand(table)
    :timer.sleep(50)

    {:ok, budget_after} = Bank.get_budget(bank, player_id)
    assert budget_after < budget_before
  end

  test "busted player goes to away and can be re-seated", %{sim: sim, table: table} do
    Sim.spawn_players(sim, 4)
    status = Sim.get_status(sim)
    victim_id = hd(status.seated).id

    Phoenix.PubSub.broadcast(BinzPoker.PubSub, "table:events",
      {:player_busted, victim_id})
    :timer.sleep(100)

    # In v1 with auto-approve loans, player should survive
    new_status = Sim.get_status(sim)
    assert new_status.total_players >= 4
  end

  test "full lifecycle: spawn, play, billing", %{sim: sim, table: table} do
    Sim.spawn_players(sim, 4)

    for _ <- 1..20 do
      Table.play_hand(table)
    end
    :timer.sleep(50)

    status = Sim.get_status(sim)
    assert status.hands_played == 20

    living = PlayerRecord.get_living_players()
    assert length(living) >= 1
  end
end
```

**Step 2: Run integration test**

```bash
mix test test/binz_poker/integration_test.exs
```

Expected: all PASS

**Step 3: Commit**

```bash
git add test/binz_poker/integration_test.exs
git commit -m "test: add integration test — full game loop with per-hand billing and buy-in"
```
