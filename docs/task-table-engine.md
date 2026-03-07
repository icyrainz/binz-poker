### Table GenServer — Complete Poker Engine

The Table is the poker engine. It manages its own seat list, runs hands continuously in an event-driven loop, and broadcasts results via PubSub. It knows nothing about budgets, loans, billing, or survival.

**Complete No Limit Hold'em:** proper betting rounds with unlimited re-raises, side pots, 0-chip bust detection and seat removal.

**Event-driven loop:** Not tick-based. Runs hands back-to-back with a configurable delay. After each hand, broadcasts results and checks for busted players.

**Seat management:** Table owns its seats. Players request seats, Table accepts/rejects. When a player busts (0 chips), Table removes them and broadcasts `{:player_busted, player_id}` and `{:seat_available, count}`.

**Depends on:** Task 3 (Hand Evaluator), Task 9 (Player GenServer)

**Files:**
- Create: `lib/binz_poker/table.ex`
- Create: `test/binz_poker/table_test.exs`

**Step 1: Write failing tests**

```elixir
# test/binz_poker/table_test.exs
defmodule BinzPoker.TableTest do
  use BinzPoker.DataCase

  alias BinzPoker.Table
  alias BinzPoker.Player
  alias BinzPoker.Schemas.PlayerRecord

  # Helper: create a player in DB and start GenServer
  defp spawn_test_player(id, chips \\ 500) do
    {:ok, _} = PlayerRecord.create(%{
      player_id: id, name: "Player #{id}", traits: %{}, model: "mock-model",
      status: "seated", chips: chips, budget: 5.00
    })
    start_supervised!({Player, [
      id: id,
      decision_engine: BinzPoker.DecisionEngine.Random
    ]}, id: String.to_atom(id))
  end

  setup do
    # Start PlayerRegistry for name registration
    start_supervised!({Registry, keys: :unique, name: BinzPoker.PlayerRegistry})

    # Spawn 3 test players
    pids = for i <- 1..3 do
      pid = spawn_test_player("p#{i}")
      {"p#{i}", pid}
    end

    table = start_supervised!({Table,
      hand_evaluator: BinzPoker.HandEvaluator.Native,
      auto_start: false
    })

    # Seat all players
    for {id, pid} <- pids do
      Table.request_seat(table, id, pid)
    end

    %{table: table, pids: pids}
  end

  test "play_hand completes without crashing", %{table: table} do
    assert {:ok, result} = Table.play_hand(table)
    assert is_map(result)
    assert Map.has_key?(result, :winners)
    assert Map.has_key?(result, :pots)
  end

  test "hand increments hand counter", %{table: table} do
    assert Table.get_hand_number(table) == 0
    Table.play_hand(table)
    assert Table.get_hand_number(table) == 1
  end

  test "request_seat and leave_seat manage seats", %{table: table} do
    state = Table.get_state(table)
    assert length(state.seats) == 3

    Table.leave_seat(table, "p1")
    state = Table.get_state(table)
    assert length(state.seats) == 2
  end

  test "can play 10 hands without crashing", %{table: table} do
    for _ <- 1..10 do
      assert {:ok, _result} = Table.play_hand(table)
    end
  end
end
```

**Step 2: Run test to verify it fails**

```bash
mix test test/binz_poker/table_test.exs
```

**Step 3: Implement Table GenServer**

This is the largest module. Key sections:
1. Seat management
2. Hand orchestration (deal, betting rounds, showdown)
3. Betting round with re-raise support
4. Side pot calculation
5. Event broadcasting

```elixir
# lib/binz_poker/table.ex
defmodule BinzPoker.Table do
  use GenServer

  alias BinzPoker.{Deck, Player, Card}

  defstruct [
    :hand_evaluator,
    seats: %{},              # seat_num => %{player_id: id, pid: pid}
    table_size: 6,
    hand_number: 0,
    dealer_seat: 0,
    small_blind: 1,
    big_blind: 2,
    hand_delay_ms: 5000,
    auto_run: false,
    status: :idle
  ]

  # ---- Client API ----

  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def play_hand(table \\ __MODULE__), do: GenServer.call(table, :play_hand, 120_000)
  def get_hand_number(table \\ __MODULE__), do: GenServer.call(table, :get_hand_number)
  def get_state(table \\ __MODULE__), do: GenServer.call(table, :get_state)
  def request_seat(table \\ __MODULE__, player_id, pid), do: GenServer.call(table, {:request_seat, player_id, pid})
  def leave_seat(table \\ __MODULE__, player_id), do: GenServer.call(table, {:leave_seat, player_id})
  def start_auto(table \\ __MODULE__), do: GenServer.cast(table, :start_auto)
  def stop_auto(table \\ __MODULE__), do: GenServer.cast(table, :stop_auto)

  # ---- Server ----

  @impl true
  def init(opts) do
    state = %__MODULE__{
      hand_evaluator: Keyword.get(opts, :hand_evaluator, BinzPoker.HandEvaluator.Native),
      table_size: Application.get_env(:binz_poker, :table_size, 6),
      small_blind: Application.get_env(:binz_poker, :small_blind, 1),
      big_blind: Application.get_env(:binz_poker, :big_blind, 2),
      hand_delay_ms: Application.get_env(:binz_poker, :hand_delay_ms, 5000),
      auto_run: Keyword.get(opts, :auto_start, false)
    }
    if state.auto_run, do: send(self(), :play_next)
    {:ok, state}
  end

  @impl true
  def handle_call(:play_hand, _from, state) do
    case do_play_hand(state) do
      {:ok, result, new_state} -> {:reply, {:ok, result}, new_state}
      {:error, reason, state} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:get_hand_number, _from, state) do
    {:reply, state.hand_number, state}
  end

  def handle_call(:get_state, _from, state) do
    seats_info = Enum.map(state.seats, fn {seat_num, %{player_id: id, pid: pid}} ->
      %{seat: seat_num, player_id: id, chips: Player.get_chips(pid)}
    end)
    {:reply, %{
      hand_number: state.hand_number,
      status: state.status,
      seats: seats_info,
      dealer_seat: state.dealer_seat
    }, state}
  end

  def handle_call({:request_seat, player_id, pid}, _from, state) do
    occupied = Map.keys(state.seats) |> MapSet.new()
    available = 1..state.table_size |> MapSet.new() |> MapSet.difference(occupied) |> MapSet.to_list()

    case available do
      [] -> {:reply, {:error, :table_full}, state}
      [seat | _] ->
        new_seats = Map.put(state.seats, seat, %{player_id: player_id, pid: pid})
        {:reply, {:ok, seat}, %{state | seats: new_seats}}
    end
  end

  def handle_call({:leave_seat, player_id}, _from, state) do
    new_seats = state.seats
      |> Enum.reject(fn {_, %{player_id: id}} -> id == player_id end)
      |> Map.new()
    empty = state.table_size - map_size(new_seats)
    if empty > 0 do
      Phoenix.PubSub.broadcast(BinzPoker.PubSub, "table:events", {:seat_available, empty})
    end
    {:reply, :ok, %{state | seats: new_seats}}
  end

  @impl true
  def handle_cast(:start_auto, state) do
    send(self(), :play_next)
    {:noreply, %{state | auto_run: true}}
  end
  def handle_cast(:stop_auto, state), do: {:noreply, %{state | auto_run: false}}

  @impl true
  def handle_info(:play_next, %{auto_run: true} = state) do
    state = case do_play_hand(state) do
      {:ok, _, new_state} -> new_state
      {:error, _, new_state} -> new_state
    end
    Process.send_after(self(), :play_next, state.hand_delay_ms)
    {:noreply, state}
  end
  def handle_info(:play_next, state), do: {:noreply, state}
  def handle_info(_msg, state), do: {:noreply, state}

  # ==== CORE GAME LOGIC ====

  defp do_play_hand(state) do
    seated = Map.values(state.seats)
    if length(seated) < 2 do
      {:error, :not_enough_players, state}
    else
      state = %{state | status: :playing}

      # Snapshot chips from Player GenServers
      chip_stacks = Map.new(seated, fn %{player_id: id, pid: pid} -> {id, Player.get_chips(pid)} end)

      # Positions
      seat_order = state.seats |> Map.keys() |> Enum.sort()
      num = length(seat_order)
      d_idx = rem(state.dealer_seat, num)
      sb_seat = Enum.at(seat_order, rem(d_idx + 1, num))
      bb_seat = Enum.at(seat_order, rem(d_idx + 2, num))
      sb_id = state.seats[sb_seat].player_id
      bb_id = state.seats[bb_seat].player_id

      # Post blinds
      sb_amt = min(state.small_blind, chip_stacks[sb_id])
      bb_amt = min(state.big_blind, chip_stacks[bb_id])
      chip_stacks = chip_stacks
        |> Map.update!(sb_id, &(&1 - sb_amt))
        |> Map.update!(bb_id, &(&1 - bb_amt))
      total_bets = %{sb_id => sb_amt, bb_id => bb_amt}

      # Deal
      deck = Deck.new() |> Deck.shuffle()
      {hole_cards, deck} = deal_hole_cards(deck, seated)

      hand = %{
        deck: deck, hole_cards: hole_cards, community_cards: [],
        chip_stacks: chip_stacks, total_bets: total_bets,
        folded: MapSet.new(), all_in: MapSet.new(),
        seats: state.seats, seat_order: seat_order,
        big_blind: state.big_blind
      }
      hand = if chip_stacks[sb_id] == 0, do: %{hand | all_in: MapSet.put(hand.all_in, sb_id)}, else: hand
      hand = if chip_stacks[bb_id] == 0, do: %{hand | all_in: MapSet.put(hand.all_in, bb_id)}, else: hand

      # Betting rounds
      hand = run_all_rounds(hand, state, bb_seat)

      # Showdown
      result = resolve_hand(hand, state)

      # Apply net chip deltas back to Player GenServers
      Enum.each(seated, fn %{player_id: id, pid: pid} ->
        gs_chips = Player.get_chips(pid)  # still has pre-hand value
        final = hand.chip_stacks[id] + Map.get(result.winners, id, 0)
        delta = final - gs_chips
        if delta != 0, do: Player.update_chips(pid, delta)
      end)

      # Bust check — remove busted players from seats, set away, broadcast
      busted_seats = Enum.filter(state.seats, fn {_seat, %{player_id: _id, pid: pid}} ->
        Player.get_chips(pid) <= 0
      end)

      new_seats = Enum.reduce(busted_seats, state.seats, fn {seat, %{player_id: id, pid: pid}}, seats ->
        Player.set_status(pid, :away)
        Phoenix.PubSub.broadcast(BinzPoker.PubSub, "table:events", {:player_busted, id})
        Map.delete(seats, seat)
      end)

      if length(busted_seats) > 0 do
        empty_count = state.table_size - map_size(new_seats)
        Phoenix.PubSub.broadcast(BinzPoker.PubSub, "table:events", {:seat_available, empty_count})
      end

      new_state = %{state | seats: new_seats, hand_number: state.hand_number + 1, dealer_seat: state.dealer_seat + 1, status: :idle}
      Phoenix.PubSub.broadcast(BinzPoker.PubSub, "table:events",
        {:hand_result, Map.put(result, :hand_number, new_state.hand_number)})
      {:ok, result, new_state}
    end
  end

  defp deal_hole_cards(deck, players) do
    Enum.reduce(players, {%{}, deck}, fn %{player_id: id}, {cards, d} ->
      {dealt, rem} = Deck.deal(d, 2)
      {Map.put(cards, id, dealt), rem}
    end)
  end

  # ==== BETTING ROUNDS ====

  defp run_all_rounds(hand, state, bb_seat) do
    can_bet? = fn h ->
      all = Map.keys(h.chip_stacks)
      active = Enum.count(all, fn id -> not MapSet.member?(h.folded, id) and not MapSet.member?(h.all_in, id) end)
      non_folded = Enum.count(all, fn id -> not MapSet.member?(h.folded, id) end)
      {active, non_folded}
    end

    dealer_seat = Enum.at(hand.seat_order, rem(state.dealer_seat, length(hand.seat_order)))

    # Preflop: start left of BB
    start = next_seat_after(hand.seat_order, bb_seat)
    hand = betting_round(hand, start, hand.big_blind, hand.total_bets)

    {active, nf} = can_bet?.(hand)
    if nf <= 1 or active == 0 do hand else
      # Flop
      {flop, deck} = Deck.deal(hand.deck, 3)
      hand = %{hand | deck: deck, community_cards: flop}
      post_start = next_seat_after(hand.seat_order, dealer_seat)
      hand = betting_round(hand, post_start, 0, %{})
      {active, nf} = can_bet?.(hand)
      if nf <= 1 or active == 0 do hand else
        # Turn
        {[tc], deck} = Deck.deal(hand.deck, 1)
        hand = %{hand | deck: deck, community_cards: hand.community_cards ++ [tc]}
        hand = betting_round(hand, post_start, 0, %{})
        {active, nf} = can_bet?.(hand)
        if nf <= 1 or active == 0 do hand else
          # River
          {[rc], deck} = Deck.deal(hand.deck, 1)
          hand = %{hand | deck: deck, community_cards: hand.community_cards ++ [rc]}
          betting_round(hand, post_start, 0, %{})
        end
      end
    end
  end

  defp betting_round(hand, start_seat, current_bet, round_bets) do
    ids = hand.seat_order |> Enum.map(fn s -> hand.seats[s].player_id end)
    start_id = hand.seats[start_seat].player_id
    {before, rest} = Enum.split_while(ids, &(&1 != start_id))
    order = rest ++ before
    do_betting_loop(hand, order, order, current_bet, round_bets, MapSet.new(), hand.big_blind)
  end

  # Walks `remaining` for the current sweep. When a raise happens, `remaining`
  # resets to the full `order` (minus the raiser, who is already in `acted`).
  # When `remaining` is exhausted and everyone has matched, the round ends.
  defp do_betting_loop(hand, _order, [], _current_bet, round_bets, _acted, _min_raise) do
    merge_bets(hand, round_bets)
  end

  defp do_betting_loop(hand, order, [player_id | rest], current_bet, round_bets, acted, min_raise) do
    cond do
      MapSet.member?(hand.folded, player_id) or MapSet.member?(hand.all_in, player_id) ->
        # Skip folded/all-in players
        do_betting_loop(hand, order, rest, current_bet, round_bets, acted, min_raise)

      MapSet.member?(acted, player_id) and Map.get(round_bets, player_id, 0) >= current_bet ->
        # Already acted and matched the bet — skip
        do_betting_loop(hand, order, rest, current_bet, round_bets, acted, min_raise)

      true ->
        # This player needs to act
        pid = find_pid(hand, player_id)
        chips = hand.chip_stacks[player_id]
        my_bet = Map.get(round_bets, player_id, 0)
        to_call = current_bet - my_bet
        pot_total = (Map.values(hand.total_bets) |> Enum.sum()) + (Map.values(round_bets) |> Enum.sum())

        game_view = %{
          hole_cards: Map.get(hand.hole_cards, player_id, []),
          community_cards: hand.community_cards,
          pot: pot_total, current_bet: current_bet, to_call: to_call,
          min_raise: current_bet + min_raise, player_chips: chips
        }

        decision = case Player.request_decision(pid, game_view) do
          {:ok, d} -> d
          _ -> %{action: :fold, amount: 0}
        end

        {hand, new_bet, round_bets, acted, min_raise} =
          apply_action(hand, player_id, decision, current_bet, round_bets, acted, min_raise)

        nf = Enum.count(Map.keys(hand.chip_stacks), fn id -> not MapSet.member?(hand.folded, id) end)
        if nf <= 1 do
          merge_bets(hand, round_bets)
        else
          if new_bet > current_bet do
            # Raise happened — restart sweep from the full order (raiser is in `acted`)
            do_betting_loop(hand, order, order, new_bet, round_bets, acted, min_raise)
          else
            do_betting_loop(hand, order, rest, new_bet, round_bets, acted, min_raise)
          end
        end
    end
  end

  defp apply_action(hand, id, decision, current_bet, round_bets, acted, min_raise) do
    chips = hand.chip_stacks[id]
    my_bet = Map.get(round_bets, id, 0)

    case decision.action do
      :fold ->
        {%{hand | folded: MapSet.put(hand.folded, id)},
         current_bet, round_bets, MapSet.put(acted, id), min_raise}

      :call ->
        actual = min(current_bet - my_bet, chips)
        new_chips = chips - actual
        hand = %{hand | chip_stacks: Map.put(hand.chip_stacks, id, new_chips)}
        hand = if new_chips == 0, do: %{hand | all_in: MapSet.put(hand.all_in, id)}, else: hand
        {hand, current_bet, Map.put(round_bets, id, my_bet + actual), MapSet.put(acted, id), min_raise}

      :raise ->
        raise_to = max(decision.amount, current_bet + min_raise) |> min(my_bet + chips)
        cost = raise_to - my_bet
        new_chips = chips - cost
        hand = %{hand | chip_stacks: Map.put(hand.chip_stacks, id, new_chips)}
        hand = if new_chips == 0, do: %{hand | all_in: MapSet.put(hand.all_in, id)}, else: hand
        new_min = raise_to - current_bet
        {hand, raise_to, Map.put(round_bets, id, raise_to), MapSet.new([id]), new_min}

      :all_in ->
        new_bet = my_bet + chips
        hand = %{hand | chip_stacks: Map.put(hand.chip_stacks, id, 0), all_in: MapSet.put(hand.all_in, id)}
        round_bets = Map.put(round_bets, id, new_bet)
        if new_bet > current_bet do
          {hand, new_bet, round_bets, MapSet.new([id]), max(new_bet - current_bet, min_raise)}
        else
          {hand, current_bet, round_bets, MapSet.put(acted, id), min_raise}
        end

      _ ->
        {%{hand | folded: MapSet.put(hand.folded, id)},
         current_bet, round_bets, MapSet.put(acted, id), min_raise}
    end
  end

  defp merge_bets(hand, round_bets) do
    new_total = Enum.reduce(round_bets, hand.total_bets, fn {id, amt}, acc ->
      Map.update(acc, id, amt, &(&1 + amt))
    end)
    %{hand | total_bets: new_total}
  end

  # ==== SIDE POTS ====

  defp build_pots(total_bets, folded) do
    do_build_pots(total_bets, folded, [])
  end

  defp do_build_pots(remaining, folded, pots) do
    active = remaining |> Enum.filter(fn {_, b} -> b > 0 end) |> Map.new()
    if map_size(active) == 0 do
      Enum.reverse(pots)
    else
      min_bet = active |> Map.values() |> Enum.min()
      {pot_amount, new_remaining} =
        Enum.reduce(remaining, {0, %{}}, fn {id, bet}, {sum, rem} ->
          if bet > 0 do
            c = min(bet, min_bet)
            {sum + c, Map.put(rem, id, bet - c)}
          else
            {sum, Map.put(rem, id, 0)}
          end
        end)
      eligible = active |> Map.keys() |> Enum.reject(&MapSet.member?(folded, &1))
      do_build_pots(new_remaining, folded, [%{amount: pot_amount, eligible: eligible} | pots])
    end
  end

  # ==== SHOWDOWN ====

  defp resolve_hand(hand, state) do
    non_folded = Map.keys(hand.chip_stacks) |> Enum.reject(&MapSet.member?(hand.folded, &1))
    pots = build_pots(hand.total_bets, hand.folded)

    case non_folded do
      [winner_id] ->
        total = pots |> Enum.map(& &1.amount) |> Enum.sum()
        %{winners: %{winner_id => total}, pots: pots, method: :last_standing, hands: %{}}
      _ ->
        evaluated = Map.new(non_folded, fn id ->
          cards = Map.get(hand.hole_cards, id, []) ++ hand.community_cards
          {:ok, eval} = state.hand_evaluator.evaluate(cards)
          {id, eval}
        end)
        winners = Enum.reduce(pots, %{}, fn pot, acc ->
          eligible_hands = Enum.filter(evaluated, fn {id, _} -> id in pot.eligible end)
          {_, best_eval} = Enum.max_by(eligible_hands, fn {_, e} -> {rank_val(e.rank), e.kickers} end)
          # Find ALL players tied for best hand (split pot)
          tied = Enum.filter(eligible_hands, fn {_, e} ->
            {rank_val(e.rank), e.kickers} == {rank_val(best_eval.rank), best_eval.kickers}
          end)
          share = div(pot.amount, length(tied))
          remainder = rem(pot.amount, length(tied))
          # Give remainder chip to first tied player (arbitrary but deterministic)
          tied
          |> Enum.with_index()
          |> Enum.reduce(acc, fn {{id, _}, idx}, a ->
            extra = if idx == 0, do: remainder, else: 0
            Map.update(a, id, share + extra, &(&1 + share + extra))
          end)
        end)
        %{winners: winners, pots: pots, method: :showdown, hands: evaluated}
    end
  end

  @rank_order [:royal_flush, :straight_flush, :four_of_a_kind, :full_house,
               :flush, :straight, :three_of_a_kind, :two_pair, :one_pair, :high_card]

  defp rank_val(rank), do: -Enum.find_index(@rank_order, &(&1 == rank))

  # ==== HELPERS ====

  defp find_pid(hand, player_id) do
    hand.seats |> Map.values() |> Enum.find(fn %{player_id: id} -> id == player_id end) |> Map.get(:pid)
  end

  defp next_seat_after(seat_order, seat) do
    idx = Enum.find_index(seat_order, &(&1 == seat))
    Enum.at(seat_order, rem(idx + 1, length(seat_order)))
  end
end
```

**Key design notes:**

1. **Betting loop:** `do_betting_loop` walks `remaining` for the current sweep. When a raise happens, `remaining` resets to the full `order` so all players get a chance to respond. When `remaining` is exhausted and everyone has matched, the round ends.

2. **Re-raises:** On raise, `acted` resets to `{raiser}` only. Everyone else must act again. No cap — true no-limit.

3. **Side pots:** `build_pots` peels off the minimum bet each iteration, creating naturally layered pots with correct eligibility.

4. **All-in partial:** Below current bet = doesn't reopen. Above current bet = treated as raise, reopens.

5. **Chip sync:** Table snapshots from GenServers at hand start, tracks internally, applies net delta at end.

6. **Bust handling:** After hand, any 0-chip player is removed from seats, set to away status, then `{:player_busted, id}` broadcast for Sim to manage loan/elimination flow.

**Step 4: Run tests**

```bash
mix test test/binz_poker/table_test.exs
```

Expected: all PASS

**Step 5: Commit**

```bash
git add lib/binz_poker/table.ex test/binz_poker/table_test.exs
git commit -m "feat: add complete poker engine with re-raises, side pots, seat management"
```
