### Sim GenServer — Event-Driven World Reactor

The Sim is a purely reactive process. It does NOT have a tick loop and does NOT tell the Table to play hands. Instead, it subscribes to PubSub events and reacts: hand results trigger per-hand billing and budget checks, player busts trigger chip-to-budget conversion and loan flow, seat availability triggers buy-in decisions and seating.

**Event model:**
- `{:hand_result, result}` on `"table:events"` — settle thinking tax, check for budget-broke players
- `{:player_busted, player_id}` on `"table:events"` — chips=0, check budget, trigger loan if needed
- `{:seat_available, count}` on `"table:events"` — trigger buy-in for waiting players, seat them
- `{:loan_decided, loan_id, player_id, :approved/:denied, amount}` on `"bank:events"` — re-seat or eliminate

**v1 banker:** Auto-approve all loans. No LLM banker.

**Depends on:** Task 7 (Ecto Schemas), Task 8 (Bank), Task 9 (Player), Task 10 (PlayerSupervisor), Task 11 (Table)

**Files:**
- Create: `lib/binz_poker/sim.ex`
- Create: `test/binz_poker/sim_test.exs`

**Step 1: Write failing tests**

```elixir
# test/binz_poker/sim_test.exs
defmodule BinzPoker.SimTest do
  use BinzPoker.DataCase

  alias BinzPoker.{Sim, Bank, PlayerSupervisor, Table, Player}
  alias BinzPoker.Schemas.{PlayerRecord, SimRecord}

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
    # Each seated player should have chips > 0 (from buy-in)
    Enum.each(status.seated, fn p ->
      pid = p.pid
      assert Player.get_chips(pid) > 0
    end)
  end

  test "spawn beyond table size puts extras in away", %{sim: sim} do
    Sim.spawn_players(sim, 8)
    status = Sim.get_status(sim)
    assert length(status.seated) == 6
    assert length(status.away) == 2
  end

  test "reacts to hand_result by incrementing counter and settling bill", %{sim: sim} do
    Sim.spawn_players(sim, 3)
    Phoenix.PubSub.broadcast(BinzPoker.PubSub, "table:events",
      {:hand_result, %{hand_number: 1, winners: %{}, pots: []}})
    :timer.sleep(20)
    status = Sim.get_status(sim)
    assert status.hands_played == 1
  end

  test "reacts to player_busted — converts chips to budget", %{sim: sim} do
    Sim.spawn_players(sim, 3)
    status = Sim.get_status(sim)
    busted_id = hd(status.seated).id

    Phoenix.PubSub.broadcast(BinzPoker.PubSub, "table:events",
      {:player_busted, busted_id})
    :timer.sleep(50)

    status = Sim.get_status(sim)
    refute Enum.any?(status.seated, &(&1.id == busted_id))
  end

  test "reacts to seat_available by doing buy-in and seating away players", %{sim: sim} do
    Sim.spawn_players(sim, 8)
    status = Sim.get_status(sim)
    assert length(status.away) == 2

    Phoenix.PubSub.broadcast(BinzPoker.PubSub, "table:events",
      {:seat_available, 1})
    :timer.sleep(20)

    status = Sim.get_status(sim)
    assert length(status.seated) == 7
    assert length(status.away) == 1
  end

  test "reacts to loan_decided :denied + broke -> eliminates and respawns", %{sim: sim} do
    Sim.spawn_players(sim, 3)
    status = Sim.get_status(sim)
    doomed_id = hd(status.seated).id

    # Simulate bust (0 chips, 0 budget)
    Phoenix.PubSub.broadcast(BinzPoker.PubSub, "table:events",
      {:player_busted, doomed_id})
    :timer.sleep(50)

    Phoenix.PubSub.broadcast(BinzPoker.PubSub, "bank:events",
      {:loan_decided, 1, doomed_id, :denied, 0})
    :timer.sleep(50)

    status = Sim.get_status(sim)
    refute Enum.any?(status.seated ++ status.away, &(&1.id == doomed_id))
    assert status.total_players == 3
  end

  test "get_status returns current state", %{sim: sim} do
    status = Sim.get_status(sim)
    assert is_list(status.seated)
    assert is_list(status.away)
    assert status.hands_played == 0
    assert status.total_players == 0
  end
end
```

**Step 2: Run test to verify it fails**

```bash
mix test test/binz_poker/sim_test.exs
```

**Step 3: Implement Sim GenServer**

Key design: purely reactive via PubSub. No tick loop. Per-hand billing (not cycles). Buy-in decision before seating. Auto-approve loans.

```elixir
# lib/binz_poker/sim.ex
defmodule BinzPoker.Sim do
  use GenServer

  alias BinzPoker.{Table, Bank, PlayerSupervisor, Player}
  alias BinzPoker.Schemas.{PlayerRecord, LeaderboardEntry, SimRecord}

  defstruct [
    :bank, :player_supervisor, :table, :sim_id,
    max_players: 10, table_size: 6,
    player_states: %{},            # player_id => :seated | :away | :busted_awaiting_loan
    hands_played: 0,
    banker_mode: :auto             # :auto (v1: auto-approve loans) | :manual (v2: human/LLM decides)
  ]

  # ---- Client API ----

  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def spawn_players(sim \\ __MODULE__, count), do: GenServer.call(sim, {:spawn_players, count})
  def get_status(sim \\ __MODULE__), do: GenServer.call(sim, :get_status)
  def resume_from_db(sim \\ __MODULE__), do: GenServer.call(sim, :resume_from_db)
  def set_banker_mode(sim \\ __MODULE__, mode) when mode in [:auto, :manual], do: GenServer.call(sim, {:set_banker_mode, mode})

  # ---- Server ----

  @impl true
  def init(opts) do
    sim_id = case Keyword.get(opts, :sim_id) do
      nil ->
        case SimRecord.get_current() do
          nil -> {:ok, sim} = SimRecord.create(%{}); sim.id
          sim -> sim.id
        end
      id -> id
    end

    state = %__MODULE__{
      bank: Keyword.fetch!(opts, :bank),
      player_supervisor: Keyword.fetch!(opts, :player_supervisor),
      table: Keyword.fetch!(opts, :table),
      sim_id: sim_id,
      max_players: Keyword.get(opts, :max_players, 10),
      table_size: Keyword.get(opts, :table_size, 6)
    }

    Phoenix.PubSub.subscribe(BinzPoker.PubSub, "table:events")
    Phoenix.PubSub.subscribe(BinzPoker.PubSub, "bank:events")

    state = case SimRecord.get(sim_id) do
      nil -> state
      sim_record -> %{state | hands_played: sim_record.hand_count}
    end

    {:ok, state}
  end

  # ---- Sync handlers ----

  @impl true
  def handle_call({:spawn_players, count}, _from, state) do
    # Spawn all players first (as :away), then fill seats once
    new_state = Enum.reduce(1..count, state, fn _, acc -> spawn_one_no_seat(acc) end)
    new_state = fill_empty_seats(new_state)
    {:reply, :ok, new_state}
  end

  def handle_call(:get_status, _from, state) do
    players = PlayerSupervisor.list_players(state.player_supervisor)
    seated = Enum.filter(players, fn p -> Map.get(state.player_states, p.id) == :seated end)
    away = Enum.filter(players, fn p -> Map.get(state.player_states, p.id) in [:away, :busted_awaiting_loan] end)
    {:reply, %{
      seated: seated,
      away: away,
      hands_played: state.hands_played,
      total_players: map_size(state.player_states)
    }, state}
  end

  def handle_call({:set_banker_mode, mode}, _from, state) do
    {:reply, :ok, %{state | banker_mode: mode}}
  end

  def handle_call(:resume_from_db, _from, state) do
    PlayerSupervisor.resume_players(state.player_supervisor)
    players = PlayerSupervisor.list_players(state.player_supervisor)

    new_states = Map.new(players, fn p ->
      record = PlayerRecord.get_by_player_id(p.id)
      status = if record && record.status in ["seated", "away"],
        do: String.to_existing_atom(record.status),
        else: :away
      {p.id, status}
    end)

    # Re-seat players that were seated
    seated = Enum.filter(new_states, fn {_, s} -> s == :seated end)
    Enum.each(seated, fn {id, _} ->
      pid = PlayerSupervisor.get_player_pid(state.player_supervisor, id)
      if pid, do: Table.request_seat(state.table, id, pid)
    end)

    {:reply, :ok, %{state | player_states: new_states}}
  end

  # ---- Event handlers (PubSub) ----

  @impl true
  def handle_info({:hand_result, _result}, state) do
    new_hands = state.hands_played + 1
    SimRecord.increment_hand_count(state.sim_id)

    # Settle thinking tax for this hand
    Bank.settle_hand(state.bank)

    # Check for budget-broke players
    {:ok, broke} = Bank.check_budget_broke(state.bank)
    state = Enum.reduce(broke, state, fn player_id, acc ->
      handle_budget_broke(acc, player_id)
    end)

    {:noreply, %{state | hands_played: new_hands}}
  end

  def handle_info({:player_busted, player_id}, state) do
    # Player has 0 chips. Table already removed them.
    # Cash out chips (0) to budget — no-op for amount, but formalizes the state change.
    Bank.cash_out(state.bank, player_id, 0)

    # Check if they have budget to re-buy-in
    {:ok, budget} = Bank.get_budget(state.bank, player_id)

    state = if budget > 0 do
      # Has budget — can re-enter when seat available
      %{state | player_states: Map.put(state.player_states, player_id, :away)}
    else
      # Broke — auto-approve loan (v1)
      {:ok, loan_id} = Bank.request_loan(state.bank, player_id, 2.00, "I need to get back in the game.")
      Bank.approve_loan(state.bank, loan_id, 2.00)
      %{state | player_states: Map.put(state.player_states, player_id, :away)}
    end

    {:noreply, state}
  end

  def handle_info({:seat_available, _count}, state) do
    {:noreply, fill_empty_seats(state)}
  end

  def handle_info({:loan_decided, _loan_id, player_id, :approved, _amount}, state) do
    # Player got funded — eligible for re-seating
    new_states = Map.put(state.player_states, player_id, :away)
    state = %{state | player_states: new_states}
    {:noreply, fill_empty_seats(state)}
  end

  def handle_info({:loan_decided, _loan_id, player_id, :denied, _amount}, state) do
    # Denied — check if truly dead
    {:ok, budget} = Bank.get_budget(state.bank, player_id)
    pid = PlayerSupervisor.get_player_pid(state.player_supervisor, player_id)
    chips = if pid, do: Player.get_chips(pid), else: 0

    state = if budget <= 0 and chips <= 0 do
      eliminate_player(state, player_id, "loan_denied")
    else
      # Still has some money — can survive
      %{state | player_states: Map.put(state.player_states, player_id, :away)}
    end

    {:noreply, state}
  end

  def handle_info({:loan_requested, _loan_id, _player_id, _amount, _message}, state) do
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # ---- Private: Budget broke handling ----

  defp handle_budget_broke(state, player_id) do
    pid = PlayerSupervisor.get_player_pid(state.player_supervisor, player_id)
    if pid do
      chips = Player.get_chips(pid)
      # Kick from table — convert all chips to budget
      Table.leave_seat(state.table, player_id)
      Bank.cash_out(state.bank, player_id, chips)
      Player.set_chips(pid, 0)
      Player.set_status(pid, :away)

      # After cash-out, check if budget is now positive
      {:ok, new_budget} = Bank.get_budget(state.bank, player_id)
      if new_budget > 0 do
        # Chips saved them — they can re-buy-in
        %{state | player_states: Map.put(state.player_states, player_id, :away)}
      else
        # Truly broke — auto-approve loan (v1)
        {:ok, loan_id} = Bank.request_loan(state.bank, player_id, 2.00, "I'm broke, need help.")
        Bank.approve_loan(state.bank, loan_id, 2.00)
        %{state | player_states: Map.put(state.player_states, player_id, :away)}
      end
    else
      state
    end
  end

  # ---- Private: Elimination ----

  defp eliminate_player(state, player_id, cause) do
    pid = PlayerSupervisor.get_player_pid(state.player_supervisor, player_id)
    if pid do
      char = Player.get_character(pid)
      LeaderboardEntry.record_death(%{
        character_name: char.name,
        model: char.model,
        traits: char.traits,
        backstory: char.backstory,
        hands_survived: char.hands_played,
        peak_budget: char.peak_budget,
        total_winnings: char.total_winnings,
        total_token_cost: char.total_token_cost,
        cause_of_death: cause,
        sim_id: state.sim_id
      })
    end

    PlayerSupervisor.eliminate_and_respawn(state.player_supervisor, player_id)
    Phoenix.PubSub.broadcast(BinzPoker.PubSub, "sim:events",
      {:player_eliminated, player_id, cause})

    new_states = Map.delete(state.player_states, player_id)
    state = %{state | player_states: new_states}

    # Respawn created a new player — find, register, and try to seat
    spawn_one_and_seat(state)
  end

  # ---- Private: Seating with Buy-In ----

  defp fill_empty_seats(state) do
    empty = state.table_size - count_seated(state)

    away_ids = state.player_states
      |> Enum.filter(fn {_, s} -> s == :away end)
      |> Enum.map(fn {id, _} -> id end)

    {new_state, _} = Enum.reduce(away_ids, {state, empty}, fn id, {acc, seats} ->
      if seats > 0 do
        pid = PlayerSupervisor.get_player_pid(acc.player_supervisor, id)
        if pid do
          # Check if player has budget for buy-in
          {:ok, budget} = Bank.get_budget(acc.bank, id)
          if budget > 0 do
            # Ask player for buy-in decision
            {:ok, buy_in_chips} = Player.request_buy_in(pid, budget)
            # Ensure buy-in doesn't exceed budget
            max_chips = trunc(budget * 100)
            buy_in_chips = min(buy_in_chips, max_chips)
            buy_in_chips = max(buy_in_chips, 1)  # minimum 1 chip

            # Execute buy-in via Bank
            Bank.buy_in(acc.bank, id, buy_in_chips)
            Player.set_chips(pid, buy_in_chips)
            Player.set_status(pid, :seated)
            Table.request_seat(acc.table, id, pid)

            new_states = Map.put(acc.player_states, id, :seated)
            {%{acc | player_states: new_states}, seats - 1}
          else
            {acc, seats}
          end
        else
          {acc, seats}
        end
      else
        {acc, seats}
      end
    end)

    new_state
  end

  # Spawn a player as :away without trying to seat them. Used by spawn_players batch.
  defp spawn_one_no_seat(state) do
    total = map_size(state.player_states)
    if total >= state.max_players do
      state
    else
      taken = get_taken_names(state)
      {:ok, _pid} = PlayerSupervisor.spawn_player(state.player_supervisor, taken_names: taken)
      players = PlayerSupervisor.list_players(state.player_supervisor)
      newest = Enum.find(players, fn p -> not Map.has_key?(state.player_states, p.id) end)

      if newest do
        %{state | player_states: Map.put(state.player_states, newest.id, :away)}
      else
        state
      end
    end
  end

  # Spawn a player and immediately try to seat them. Used by eliminate_and_respawn.
  defp spawn_one_and_seat(state) do
    state = spawn_one_no_seat(state)
    fill_empty_seats(state)
  end

  defp count_seated(state) do
    state.player_states |> Map.values() |> Enum.count(&(&1 == :seated))
  end

  defp get_taken_names(state) do
    state.player_states
    |> Map.keys()
    |> Enum.map(fn id ->
      pid = PlayerSupervisor.get_player_pid(state.player_supervisor, id)
      if pid, do: Player.get_character(pid).name, else: nil
    end)
    |> Enum.reject(&is_nil/1)
  end
end
```

**Step 4: Run tests**

```bash
mix test test/binz_poker/sim_test.exs
```

Expected: all PASS

**Step 5: Commit**

```bash
git add lib/binz_poker/sim.ex test/binz_poker/sim_test.exs
git commit -m "feat: add Sim GenServer — per-hand billing, buy-in flow, auto-approve loans"
```
