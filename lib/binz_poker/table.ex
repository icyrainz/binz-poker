defmodule BinzPoker.Table do
  use GenServer

  alias BinzPoker.{Deck, Player}

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

      # Blind bets are tracked as preflop round_bets; total_bets starts empty
      # to avoid double-counting when merge_bets runs at round end.
      preflop_bets = total_bets

      hand = %{
        deck: deck, hole_cards: hole_cards, community_cards: [],
        chip_stacks: chip_stacks, total_bets: %{},
        folded: MapSet.new(), all_in: MapSet.new(),
        seats: state.seats, seat_order: seat_order,
        big_blind: state.big_blind
      }
      hand = if chip_stacks[sb_id] == 0, do: %{hand | all_in: MapSet.put(hand.all_in, sb_id)}, else: hand
      hand = if chip_stacks[bb_id] == 0, do: %{hand | all_in: MapSet.put(hand.all_in, bb_id)}, else: hand

      # Betting rounds
      hand = run_all_rounds(hand, state, bb_seat, preflop_bets)

      # Showdown
      result = resolve_hand(hand, state)

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
        hand = %{hand | deck: deck, community_cards: flop}
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
            hand = %{hand | deck: deck, community_cards: hand.community_cards ++ [tc]}
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
                hand = %{hand | deck: deck, community_cards: hand.community_cards ++ [rc]}
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
    %{hand | deck: deck, community_cards: hand.community_cards ++ cards}
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
        %{winners: %{winner_id => total}, pots: pots, method: :last_standing, hands: %{}}
      _ ->
        evaluated = Map.new(non_folded, fn id ->
          cards = Map.get(hand.hole_cards, id, []) ++ hand.community_cards
          {:ok, eval} = state.hand_evaluator.evaluate(cards)
          {id, eval}
        end)
        winners = Enum.reduce(pots, %{}, fn pot, acc ->
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
            tied
            |> Enum.with_index()
            |> Enum.reduce(acc, fn {{id, _}, idx}, a ->
              extra = if idx == 0, do: remainder, else: 0
              Map.update(a, id, share + extra, &(&1 + share + extra))
            end)
          end
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
