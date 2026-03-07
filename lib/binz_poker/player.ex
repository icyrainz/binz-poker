defmodule BinzPoker.Player do
  use GenServer

  alias BinzPoker.Character
  alias BinzPoker.Schemas.PlayerRecord

  defstruct [
    :id, :character, :decision_engine,
    status: :away,
    observations: []
  ]

  def start_link(opts) do
    id = Keyword.fetch!(opts, :id)
    GenServer.start_link(__MODULE__, opts, name: via(id))
  end

  def via(id), do: {:via, Registry, {BinzPoker.PlayerRegistry, id}}

  def get_character(player), do: GenServer.call(player, :get_character)
  def get_chips(player), do: GenServer.call(player, :get_chips)
  def get_status(player), do: GenServer.call(player, :get_status)
  def get_observations(player), do: GenServer.call(player, :get_observations)
  def set_status(player, status), do: GenServer.call(player, {:set_status, status})
  def set_chips(player, chips), do: GenServer.call(player, {:set_chips, chips})
  def update_chips(player, delta), do: GenServer.call(player, {:update_chips, delta})
  def add_observation(player, event), do: GenServer.cast(player, {:add_observation, event})
  def request_decision(player, game_state), do: GenServer.call(player, {:decide, game_state}, 30_000)
  def request_buy_in(player, budget), do: GenServer.call(player, {:buy_in_decision, budget}, 30_000)

  @impl true
  def init(opts) do
    id = Keyword.fetch!(opts, :id)

    record = PlayerRecord.get_by_player_id(id)

    character = %Character{
      name: record.name,
      backstory: record.backstory,
      traits: atomize_trait_keys(record.traits),
      model: record.model,
      chips: record.chips,
      budget: record.budget,
      token_bill: record.token_bill,
      total_token_cost: record.total_token_cost,
      total_winnings: record.total_winnings,
      peak_budget: record.peak_budget,
      hands_played: record.hands_played,
      hands_won: record.hands_won
    }

    state = %__MODULE__{
      id: id,
      character: character,
      decision_engine: Keyword.get(opts, :decision_engine,
        Application.get_env(:binz_poker, :decision_engine, BinzPoker.DecisionEngine.Random)),
      status: String.to_existing_atom(record.status),
      observations: Map.get(record.observations, "events", [])
    }

    {:ok, state}
  end

  @impl true
  def handle_call(:get_character, _from, state) do
    {:reply, state.character, state}
  end

  def handle_call(:get_chips, _from, state) do
    {:reply, state.character.chips, state}
  end

  def handle_call(:get_status, _from, state) do
    {:reply, state.status, state}
  end

  def handle_call(:get_observations, _from, state) do
    {:reply, state.observations, state}
  end

  def handle_call({:set_status, new_status}, _from, state) do
    PlayerRecord.update_fields(state.id, %{status: Atom.to_string(new_status)})
    {:reply, :ok, %{state | status: new_status}}
  end

  def handle_call({:set_chips, chips}, _from, state) do
    updated_char = %{state.character | chips: chips}
    PlayerRecord.update_fields(state.id, %{chips: chips})
    {:reply, :ok, %{state | character: updated_char}}
  end

  def handle_call({:update_chips, delta}, _from, state) do
    new_chips = state.character.chips + delta
    updated_char = %{state.character | chips: new_chips}
    PlayerRecord.update_fields(state.id, %{chips: new_chips})
    {:reply, :ok, %{state | character: updated_char}}
  end

  def handle_call({:decide, game_state}, _from, state) do
    game_state_with_chips = Map.put(game_state, :player_chips, state.character.chips)
    result = state.decision_engine.decide(game_state_with_chips, state.character)
    {:reply, result, state}
  end

  def handle_call({:buy_in_decision, budget}, _from, state) do
    result = state.decision_engine.buy_in(budget, state.character)
    {:reply, result, state}
  end

  @impl true
  def handle_cast({:add_observation, event}, state) do
    observations = [event | state.observations] |> Enum.take(50)
    if rem(length(observations), 5) == 0 do
      PlayerRecord.update_fields(state.id, %{observations: %{"events" => observations}})
    end
    {:noreply, %{state | observations: observations}}
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  defp atomize_trait_keys(traits) when is_map(traits) do
    Map.new(traits, fn
      {k, v} when is_binary(k) and is_binary(v) -> {String.to_atom(k), String.to_atom(v)}
      {k, v} when is_binary(k) -> {String.to_atom(k), v}
      {k, v} when is_atom(k) -> {k, v}
    end)
  end
end
