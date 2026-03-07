### Player GenServer — Reactive Agent

The Player is a reactive agent. In v1, it has no autonomous tick loop — it only responds when asked for decisions by the Table (poker) or Sim (buy-in). It loads state from `PlayerRecord` in DB on init and writes through on every state change.

**v1 scope:** Poker decisions + buy-in decisions. No inner monologue, no trash-talk, no autonomous behavior.
**v2 scope:** Add tick loop for inner monologue, observations, trash-talk, voluntary chip-to-budget conversion.

**Depends on:** Task 7 (Ecto Schemas), Task 8 (Bank)

**Files:**
- Create: `lib/binz_poker/player.ex`
- Create: `test/binz_poker/player_test.exs`

**Step 1: Write failing tests**

```elixir
# test/binz_poker/player_test.exs
defmodule BinzPoker.PlayerTest do
  use BinzPoker.DataCase

  alias BinzPoker.Player
  alias BinzPoker.Schemas.PlayerRecord

  setup do
    # Start PlayerRegistry for name registration
    start_supervised!({Registry, keys: :unique, name: BinzPoker.PlayerRegistry})

    # Create DB record first — Player loads from it
    {:ok, _record} = PlayerRecord.create(%{
      player_id: "p1",
      name: "Test Player",
      backstory: "Just testing.",
      traits: %{aggression: "medium", sociability: "low", discipline: "high",
                risk_tolerance: "medium", greed: "low", pride: "medium",
                desperation: "low", deceptiveness: "low"},
      model: "mock-model",
      status: "seated",
      chips: 300,
      budget: 2.00
    })

    player = start_supervised!({Player,
      id: "p1",
      decision_engine: BinzPoker.DecisionEngine.Random
    })
    %{player: player}
  end

  test "loads state from DB on init", %{player: player} do
    assert Player.get_chips(player) == 300
    assert Player.get_status(player) == :seated
    char = Player.get_character(player)
    assert char.name == "Test Player"
  end

  test "update_chips modifies and persists", %{player: player} do
    Player.update_chips(player, -50)
    assert Player.get_chips(player) == 250
    record = PlayerRecord.get_by_player_id("p1")
    assert record.chips == 250
  end

  test "set_chips sets exact value and persists", %{player: player} do
    Player.set_chips(player, 400)
    assert Player.get_chips(player) == 400
    record = PlayerRecord.get_by_player_id("p1")
    assert record.chips == 400
  end

  test "set_status changes state and persists", %{player: player} do
    Player.set_status(player, :away)
    assert Player.get_status(player) == :away
    record = PlayerRecord.get_by_player_id("p1")
    assert record.status == "away"
  end

  test "request_decision returns a valid action", %{player: player} do
    game_state = %{
      hole_cards: [],
      community_cards: [],
      pot: 30,
      current_bet: 10,
      min_raise: 20,
      player_chips: 300
    }
    {:ok, decision} = Player.request_decision(player, game_state)
    assert decision.action in [:fold, :call, :raise, :all_in]
  end

  test "request_buy_in returns a chip amount", %{player: player} do
    # For Random engine, returns a random buy-in
    {:ok, amount} = Player.request_buy_in(player, 5.00)
    assert is_integer(amount)
    assert amount > 0
    assert amount <= 500  # max chips for $5.00
  end

  test "add_observation stores event as map", %{player: player} do
    Player.add_observation(player, %{type: "hand_result", data: %{winner: "p2"}, at: DateTime.utc_now()})
    observations = Player.get_observations(player)
    assert length(observations) == 1
    assert hd(observations).type == "hand_result"
  end
end
```

**Step 2: Run test to verify it fails**

```bash
mix test test/binz_poker/player_test.exs
```

**Step 3: Implement Player GenServer**

No tick loop. Just responds to decisions and tracks state.

```elixir
# lib/binz_poker/player.ex
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

  # Sync API
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

    # Load state from DB
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

  # --- Sync handlers ---

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
    # In v1 with Random engine: buy in with ~60% of budget
    # In LLM mode: LLM decides based on character traits
    result = state.decision_engine.buy_in(budget, state.character)
    {:reply, result, state}
  end

  # --- Async handlers ---

  @impl true
  def handle_cast({:add_observation, event}, state) do
    observations = [event | state.observations] |> Enum.take(50)
    # Persist every 5 observations
    if rem(length(observations), 5) == 0 do
      PlayerRecord.update_fields(state.id, %{observations: %{"events" => observations}})
    end
    {:noreply, %{state | observations: observations}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # --- Private ---

  defp atomize_trait_keys(traits) when is_map(traits) do
    Map.new(traits, fn
      {k, v} when is_binary(k) -> {String.to_atom(k), String.to_atom(v)}
      {k, v} when is_atom(k) -> {k, v}
    end)
  end
end
```

**Step 4: Run tests**

```bash
mix test test/binz_poker/player_test.exs
```

Expected: all PASS

**Step 5: Commit**

```bash
git add lib/binz_poker/player.ex test/binz_poker/player_test.exs
git commit -m "feat: add Player GenServer — reactive agent with poker and buy-in decisions"
```
