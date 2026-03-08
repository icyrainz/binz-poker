defmodule BinzPoker.Table do
  use GenServer
  require Logger

  alias BinzPoker.{Deck, Player, Card}
  alias BinzPoker.Schemas.HandHistory

  defstruct [
    :hand_evaluator,
    seats: %{},              # seat_num => %{player_id: id, pid: pid}
    table_size: 6,
    hand_number: 0,
    dealer_seat: 0,
    small_blind: 1,
    big_blind: 2,
    hand_delay_ms: 5000,
    action_delay_ms: 0,
    auto_run: false,
    status: :idle,
    sim_id: nil,
    table_id: nil
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
      action_delay_ms: Application.get_env(:binz_poker, :action_delay_ms, 0),
      auto_run: Keyword.get(opts, :auto_start, false),
      sim_id: Keyword.get(opts, :sim_id),
      table_id: Keyword.get(opts, :table_id, "table_1")
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

      hand_num = state.hand_number + 1
      Logger.info("[HAND ##{hand_num}] ========== NEW HAND ==========")
      player_list = Enum.map_join(seated, ", ", fn %{player_id: _id, pid: pid} ->
        char = Player.get_character(pid)
        "#{char.name}(#{Player.get_chips(pid)})"
      end)
      Logger.info("[HAND ##{hand_num}] Players: #{player_list}")
      sb_name = state.seats[sb_seat] |> Map.get(:pid) |> Player.get_character() |> Map.get(:name)
      bb_name = state.seats[bb_seat] |> Map.get(:pid) |> Player.get_character() |> Map.get(:name)
      Logger.info("[HAND ##{hand_num}] Blinds: #{sb_name} posts SB #{sb_amt}, #{bb_name} posts BB #{bb_amt}")
      Enum.each(hole_cards, fn {id, cards} ->
        pid = find_pid_from_seated(seated, id)
        name = if pid, do: Player.get_character(pid).name, else: id
        Logger.info("[HAND ##{hand_num}] #{name} dealt: #{fmt_cards(cards)}")
      end)

      # Blind bets are tracked as preflop round_bets; total_bets starts empty
      # to avoid double-counting when merge_bets runs at round end.
      preflop_bets = total_bets

      hand = %{
        deck: deck, hole_cards: hole_cards, community_cards: [],
        chip_stacks: chip_stacks, total_bets: %{},
        folded: MapSet.new(), all_in: MapSet.new(),
        seats: state.seats, seat_order: seat_order,
        big_blind: state.big_blind,
        actions_log: [], street: "preflop"
      }
      hand = if chip_stacks[sb_id] == 0, do: %{hand | all_in: MapSet.put(hand.all_in, sb_id)}, else: hand
      hand = if chip_stacks[bb_id] == 0, do: %{hand | all_in: MapSet.put(hand.all_in, bb_id)}, else: hand

      # Betting rounds
      hand = Map.put(hand, :action_delay_ms, state.action_delay_ms)
      hand = Map.put(hand, :hand_num, hand_num)
      hand = run_all_rounds(hand, state, bb_seat, preflop_bets)

      # Showdown
      result = resolve_hand(hand, state)

      # Persist hand history
      HandHistory.create(%{
        hand_number: hand_num,
        sim_id: state.sim_id || get_current_sim_id(),
        table_id: state.table_id,
        players: Map.new(seated, fn %{player_id: id, pid: pid} ->
          seat_num = Enum.find_value(state.seats, fn {s, %{player_id: sid}} -> if sid == id, do: s end)
          {id, %{name: Player.get_character(pid).name, seat: seat_num, starting_chips: chip_stacks[id] + Map.get(total_bets, id, 0)}}
        end),
        hole_cards: Map.new(hole_cards, fn {id, cards} -> {id, Enum.map(cards, &Card.to_string/1)} end),
        community_cards: Enum.map(hand.community_cards, &Card.to_string/1),
        actions: hand.actions_log,
        pots: Enum.map(result.pots, fn pot -> %{amount: pot.amount, eligible: pot.eligible} end),
        winners: result.winners,
        showdown_hands: Map.new(result.hands, fn {id, eval} ->
          {id, %{rank: Atom.to_string(eval.rank), kickers: eval.kickers}}
        end),
        method: Atom.to_string(result.method),
        blinds: %{sb_id: sb_id, bb_id: bb_id, sb_amt: sb_amt, bb_amt: bb_amt}
      })

      # Apply net chip deltas back to Player GenServers
      Enum.each(seated, fn %{player_id: id, pid: pid} ->
        gs_chips = Player.get_chips(pid)
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
      {dealt, rem_deck} = Deck.deal(d, 2)
      {Map.put(cards, id, dealt), rem_deck}
    end)
  end

  # ==== BETTING ROUNDS ====

  defp run_all_rounds(hand, state, bb_seat, preflop_bets) do
    can_bet? = fn h ->
      all = Map.keys(h.chip_stacks)
      active = Enum.count(all, fn id -> not MapSet.member?(h.folded, id) and not MapSet.member?(h.all_in, id) end)
      non_folded = Enum.count(all, fn id -> not MapSet.member?(h.folded, id) end)
      {active, non_folded}
    end

    dealer_seat = Enum.at(hand.seat_order, rem(state.dealer_seat, length(hand.seat_order)))

    # Preflop: start left of BB, use blind bets as initial round bets
    start = next_seat_after(hand.seat_order, bb_seat)
    hand = betting_round(hand, start, hand.big_blind, preflop_bets)

    {active, nf} = can_bet?.(hand)
    if nf <= 1 do
      hand
    else
      if active == 0 do
        deal_remaining_community(hand, 5)
      else
        # Flop
        {flop, deck} = Deck.deal(hand.deck, 3)
        hand = %{hand | deck: deck, community_cards: flop, street: "flop"}
        Logger.info("[HAND] === FLOP: #{fmt_cards(flop)} ===")
        post_start = next_seat_after(hand.seat_order, dealer_seat)
        hand = betting_round(hand, post_start, 0, %{})
        {active, nf} = can_bet?.(hand)
        if nf <= 1 do
          hand
        else
          if active == 0 do
            deal_remaining_community(hand, 5 - length(hand.community_cards))
          else
            # Turn
            {[tc], deck} = Deck.deal(hand.deck, 1)
            hand = %{hand | deck: deck, community_cards: hand.community_cards ++ [tc], street: "turn"}
            Logger.info("[HAND] === TURN: #{fmt_cards(hand.community_cards)} ===")
            hand = betting_round(hand, post_start, 0, %{})
            {active, nf} = can_bet?.(hand)
            if nf <= 1 do
              hand
            else
              if active == 0 do
                deal_remaining_community(hand, 5 - length(hand.community_cards))
              else
                # River
                {[rc], deck} = Deck.deal(hand.deck, 1)
                hand = %{hand | deck: deck, community_cards: hand.community_cards ++ [rc], street: "river"}
                Logger.info("[HAND] === RIVER: #{fmt_cards(hand.community_cards)} ===")
                betting_round(hand, post_start, 0, %{})
              end
            end
          end
        end
      end
    end
  end

  defp deal_remaining_community(hand, 0), do: hand
  defp deal_remaining_community(hand, n) when n > 0 do
    {cards, deck} = Deck.deal(hand.deck, n)
    hand = %{hand | deck: deck, community_cards: hand.community_cards ++ cards}
    Logger.info("[HAND] === BOARD: #{fmt_cards(hand.community_cards)} ===")
    hand
  end

  defp betting_round(hand, start_seat, current_bet, round_bets) do
    ids = hand.seat_order |> Enum.map(fn s -> hand.seats[s].player_id end)
    start_id = hand.seats[start_seat].player_id
    {before, rest} = Enum.split_while(ids, &(&1 != start_id))
    order = rest ++ before
    do_betting_loop(hand, order, order, current_bet, round_bets, MapSet.new(), hand.big_blind)
  end

  defp do_betting_loop(hand, _order, [], _current_bet, round_bets, _acted, _min_raise) do
    merge_bets(hand, round_bets)
  end

  defp do_betting_loop(hand, order, [player_id | rest], current_bet, round_bets, acted, min_raise) do
    cond do
      MapSet.member?(hand.folded, player_id) or MapSet.member?(hand.all_in, player_id) ->
        do_betting_loop(hand, order, rest, current_bet, round_bets, acted, min_raise)

      MapSet.member?(acted, player_id) and Map.get(round_bets, player_id, 0) >= current_bet ->
        do_betting_loop(hand, order, rest, current_bet, round_bets, acted, min_raise)

      true ->
        pid = find_pid(hand, player_id)
        chips = hand.chip_stacks[player_id]
        my_bet = Map.get(round_bets, player_id, 0)
        to_call = current_bet - my_bet
        pot_total = (Map.values(hand.total_bets) |> Enum.sum()) + (Map.values(round_bets) |> Enum.sum())

        can_raise = chips > to_call
        available = [:fold] ++
          (if to_call == 0, do: [:check], else: [:call]) ++
          (if can_raise, do: [:raise], else: []) ++
          [:all_in]

        game_view = %{
          hole_cards: Map.get(hand.hole_cards, player_id, []),
          community_cards: hand.community_cards,
          pot: pot_total, current_bet: current_bet, to_call: to_call,
          min_raise: current_bet + min_raise, player_chips: chips,
          available_actions: available
        }

        decision = case Player.request_decision(pid, game_view) do
          {:ok, d} -> d
          _ -> %{action: :fold, amount: 0}
        end

        {hand, new_bet, round_bets, acted, min_raise, effective_action} =
          apply_action(hand, player_id, decision, current_bet, round_bets, acted, min_raise)

        {log_action_name, log_amount} = case effective_action do
          {:fold, _} -> {:fold, 0}
          {:check, _} -> {:check, 0}
          {:call, amt} -> {:call, amt}
          {:raise, amt} -> {:raise, amt}
          {:all_in, amt} -> {:all_in, amt}
        end
        log_action(hand, player_id, log_action_name, log_amount, Map.get(hand, :action_delay_ms, 0))

        hand = Map.update!(hand, :actions_log, fn log ->
          log ++ [%{player: player_id, action: Atom.to_string(log_action_name), amount: log_amount, street: hand.street}]
        end)

        nf = Enum.count(Map.keys(hand.chip_stacks), fn id -> not MapSet.member?(hand.folded, id) end)
        if nf <= 1 do
          merge_bets(hand, round_bets)
        else
          if new_bet > current_bet do
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
         current_bet, round_bets, MapSet.put(acted, id), min_raise, {:fold, 0}}

      action when action in [:call, :check] ->
        actual = min(current_bet - my_bet, chips)
        new_chips = chips - actual
        hand = %{hand | chip_stacks: Map.put(hand.chip_stacks, id, new_chips)}
        hand = if new_chips == 0, do: %{hand | all_in: MapSet.put(hand.all_in, id)}, else: hand
        eff = cond do
          new_chips == 0 -> {:all_in, my_bet + actual}
          actual == 0 -> {:check, 0}
          true -> {:call, actual}
        end
        {hand, current_bet, Map.put(round_bets, id, my_bet + actual), MapSet.put(acted, id), min_raise, eff}

      :raise ->
        raise_to = max(decision.amount, current_bet + min_raise) |> min(my_bet + chips)
        if raise_to <= current_bet do
          # Can't actually raise — treat as call/all-in
          actual = min(current_bet - my_bet, chips)
          new_chips = chips - actual
          hand = %{hand | chip_stacks: Map.put(hand.chip_stacks, id, new_chips)}
          hand = if new_chips == 0, do: %{hand | all_in: MapSet.put(hand.all_in, id)}, else: hand
          eff = if new_chips == 0, do: {:all_in, my_bet + actual}, else: {:call, actual}
          {hand, current_bet, Map.put(round_bets, id, my_bet + actual), MapSet.put(acted, id), min_raise, eff}
        else
          cost = raise_to - my_bet
          new_chips = chips - cost
          hand = %{hand | chip_stacks: Map.put(hand.chip_stacks, id, new_chips)}
          hand = if new_chips == 0, do: %{hand | all_in: MapSet.put(hand.all_in, id)}, else: hand
          new_min = raise_to - current_bet
          eff = if new_chips == 0, do: {:all_in, raise_to}, else: {:raise, raise_to}
          {hand, raise_to, Map.put(round_bets, id, raise_to), MapSet.new([id]), new_min, eff}
        end

      :all_in ->
        new_bet = my_bet + chips
        hand = %{hand | chip_stacks: Map.put(hand.chip_stacks, id, 0), all_in: MapSet.put(hand.all_in, id)}
        round_bets = Map.put(round_bets, id, new_bet)
        if new_bet > current_bet do
          {hand, new_bet, round_bets, MapSet.new([id]), max(new_bet - current_bet, min_raise), {:all_in, new_bet}}
        else
          {hand, current_bet, round_bets, MapSet.put(acted, id), min_raise, {:all_in, new_bet}}
        end

      _ ->
        {%{hand | folded: MapSet.put(hand.folded, id)},
         current_bet, round_bets, MapSet.put(acted, id), min_raise, {:fold, 0}}
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
        Enum.reduce(remaining, {0, %{}}, fn {id, bet}, {sum, rem_map} ->
          if bet > 0 do
            c = min(bet, min_bet)
            {sum + c, Map.put(rem_map, id, bet - c)}
          else
            {sum, Map.put(rem_map, id, 0)}
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
        name = player_name(hand, winner_id)
        Logger.info("[HAND] #{name} wins #{total} chips (everyone else folded)")
        %{winners: %{winner_id => total}, pots: pots, method: :last_standing, hands: %{}}
      _ ->
        Logger.info("[HAND] === SHOWDOWN === Board: #{fmt_cards(hand.community_cards)}")
        evaluated = Map.new(non_folded, fn id ->
          cards = Map.get(hand.hole_cards, id, []) ++ hand.community_cards
          {:ok, eval} = state.hand_evaluator.evaluate(cards)
          name = player_name(hand, id)
          hole = fmt_cards(Map.get(hand.hole_cards, id, []))
          Logger.info("[HAND] #{name} shows #{hole} -> #{eval.rank}")
          {id, eval}
        end)
        winners = pots |> Enum.with_index() |> Enum.reduce(%{}, fn {pot, pot_idx}, acc ->
          eligible_hands = Enum.filter(evaluated, fn {id, _} -> id in pot.eligible end)
          # Dead money: if no eligible non-folded players for this pot, give to best overall hand
          contenders = if eligible_hands == [], do: Enum.to_list(evaluated), else: eligible_hands
          if contenders == [] do
            acc
          else
            {_, best_eval} = Enum.max_by(contenders, fn {_, e} -> {rank_val(e.rank), e.kickers} end)
            tied = Enum.filter(contenders, fn {_, e} ->
              {rank_val(e.rank), e.kickers} == {rank_val(best_eval.rank), best_eval.kickers}
            end)
            share = div(pot.amount, length(tied))
            remainder = rem(pot.amount, length(tied))

            pot_label = if pot_idx == 0, do: "Main pot", else: "Side pot ##{pot_idx}"
            eligible_names = Enum.map_join(pot.eligible, ", ", &player_name(hand, &1))
            winner_names = Enum.map_join(tied, ", ", fn {id, _} -> player_name(hand, id) end)
            Logger.info("[HAND] #{pot_label} (#{pot.amount} chips, eligible: #{eligible_names}) -> #{winner_names}")

            tied
            |> Enum.with_index()
            |> Enum.reduce(acc, fn {{id, _}, idx}, a ->
              extra = if idx == 0, do: remainder, else: 0
              Map.update(a, id, share + extra, &(&1 + share + extra))
            end)
          end
        end)
        Enum.each(winners, fn {id, amount} ->
          name = player_name(hand, id)
          Logger.info("[HAND] #{name} wins #{amount} chips!")
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

  defp find_pid_from_seated(seated, player_id) do
    case Enum.find(seated, fn %{player_id: id} -> id == player_id end) do
      %{pid: pid} -> pid
      _ -> nil
    end
  end

  defp next_seat_after(seat_order, seat) do
    idx = Enum.find_index(seat_order, &(&1 == seat))
    Enum.at(seat_order, rem(idx + 1, length(seat_order)))
  end

  defp get_current_sim_id do
    case BinzPoker.Schemas.SimRecord.get_current() do
      nil -> nil
      sim -> sim.id
    end
  end

  defp fmt_cards(cards), do: Enum.map_join(cards, " ", &Card.to_string/1)

  defp player_name(hand, id) do
    pid = find_pid(hand, id)
    if pid do
      char = Player.get_character(pid)
      char.name
    else
      id
    end
  end

  defp log_action(hand, id, action, amount, delay_ms) do
    name = player_name(hand, id)
    msg = case action do
      :fold -> "#{name} folds"
      :check -> "#{name} checks"
      :call -> "#{name} calls #{amount}"
      :raise -> "#{name} raises to #{amount}"
      :all_in -> "#{name} goes ALL IN for #{amount}"
      _ -> "#{name} #{action} #{amount}"
    end
    Logger.info("[HAND] #{msg}")
    if delay_ms > 0, do: Process.sleep(delay_ms)
  end
end
