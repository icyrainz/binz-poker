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

    Bank.settle_hand(state.bank)

    {:ok, broke} = Bank.check_budget_broke(state.bank)
    state = Enum.reduce(broke, state, fn player_id, acc ->
      handle_budget_broke(acc, player_id)
    end)

    {:noreply, %{state | hands_played: new_hands}}
  end

  def handle_info({:player_busted, player_id}, state) do
    Bank.cash_out(state.bank, player_id, 0)

    {:ok, budget} = Bank.get_budget(state.bank, player_id)

    state = if budget > 0 do
      %{state | player_states: Map.put(state.player_states, player_id, :away)}
    else
      {:ok, loan_id} = Bank.request_loan(state.bank, player_id, 2.00, "I need to get back in the game.")
      Bank.approve_loan(state.bank, loan_id, 2.00)
      %{state | player_states: Map.put(state.player_states, player_id, :away)}
    end

    {:noreply, state}
  end

  def handle_info({:seat_available, count}, state) do
    {:noreply, fill_empty_seats(state, count)}
  end

  def handle_info({:loan_decided, _loan_id, player_id, :approved, _amount}, state) do
    new_states = Map.put(state.player_states, player_id, :away)
    state = %{state | player_states: new_states}
    {:noreply, fill_empty_seats(state)}
  end

  def handle_info({:loan_decided, _loan_id, player_id, :denied, _amount}, state) do
    {:ok, budget} = Bank.get_budget(state.bank, player_id)
    pid = PlayerSupervisor.get_player_pid(state.player_supervisor, player_id)
    chips = if pid, do: Player.get_chips(pid), else: 0

    state = if budget <= 0 and chips <= 0 do
      eliminate_player(state, player_id, "loan_denied")
    else
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
      Table.leave_seat(state.table, player_id)
      Bank.cash_out(state.bank, player_id, chips)
      Player.set_chips(pid, 0)
      Player.set_status(pid, :away)

      {:ok, new_budget} = Bank.get_budget(state.bank, player_id)
      if new_budget > 0 do
        %{state | player_states: Map.put(state.player_states, player_id, :away)}
      else
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

    spawn_one_and_seat(state)
  end

  # ---- Private: Seating with Buy-In ----

  defp fill_empty_seats(state, extra_seats \\ 0) do
    # Sync player_states with actual Table seats
    table_state = Table.get_state(state.table)
    table_player_ids = MapSet.new(table_state.seats, & &1.player_id)

    # Mark players as :away if they think they're seated but aren't at the table
    synced_states = Map.new(state.player_states, fn {id, status} ->
      if status == :seated and not MapSet.member?(table_player_ids, id) do
        {id, :away}
      else
        {id, status}
      end
    end)
    state = %{state | player_states: synced_states}

    internal_empty = state.table_size - count_seated(state)
    empty = max(internal_empty, extra_seats)

    away_ids = state.player_states
      |> Enum.filter(fn {_, s} -> s == :away end)
      |> Enum.map(fn {id, _} -> id end)

    {new_state, _} = Enum.reduce(away_ids, {state, empty}, fn id, {acc, seats} ->
      if seats > 0 do
        pid = PlayerSupervisor.get_player_pid(acc.player_supervisor, id)
        if pid do
          {:ok, budget} = Bank.get_budget(acc.bank, id)
          if budget > 0 do
            {:ok, buy_in_chips} = Player.request_buy_in(pid, budget)
            max_chips = trunc(budget * 100)
            buy_in_chips = min(buy_in_chips, max_chips)
            buy_in_chips = max(buy_in_chips, 1)

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
