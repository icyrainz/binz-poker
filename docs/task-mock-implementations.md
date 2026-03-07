### Mock/Test Implementations

**Files:**

- Create: `lib/binz_poker/llm/mock.ex`
- Create: `lib/binz_poker/decision_engine/random.ex`
- Create: `lib/binz_poker/character_gen/hardcoded.ex`
- Create: `lib/binz_poker/game_log/logger.ex`
- Create: `test/binz_poker/decision_engine/random_test.exs`

**Step 1: Write failing test for Random decision engine**

```elixir
# test/binz_poker/decision_engine/random_test.exs
defmodule BinzPoker.DecisionEngine.RandomTest do
  use ExUnit.Case, async: true
  alias BinzPoker.DecisionEngine.Random

  test "decide returns a valid action" do
    game_state = %{
      hole_cards: [%{suit: :hearts, rank: :ace}, %{suit: :spades, rank: :king}],
      community_cards: [],
      pot: 30,
      current_bet: 10,
      min_raise: 20,
      player_chips: 200
    }
    character = %{name: "Test Player", traits: %{}}

    {:ok, decision} = Random.decide(game_state, character)
    assert decision.action in [:fold, :call, :raise, :all_in]
    assert is_binary(decision.reasoning)
    assert is_binary(decision.talk)
  end

  test "decide respects current bet (can't raise more than chips)" do
    game_state = %{
      hole_cards: [],
      community_cards: [],
      pot: 100,
      current_bet: 50,
      min_raise: 100,
      player_chips: 60
    }
    character = %{name: "Broke Player", traits: %{}}

    for _ <- 1..50 do
      {:ok, decision} = Random.decide(game_state, character)
      if decision.action == :raise do
        assert decision.amount <= 60
      end
    end
  end
end
```

**Step 2: Run test to verify it fails**

```bash
mix test test/binz_poker/decision_engine/random_test.exs
```

**Step 3: Implement all mock/test modules**

```elixir
# lib/binz_poker/decision_engine/random.ex
defmodule BinzPoker.DecisionEngine.Random do
  @behaviour BinzPoker.DecisionEngine

  @impl true
  def decide(game_state, _character) do
    actions = [:fold, :call, :raise, :all_in]
    action = Enum.random(actions)
    chips = Map.get(game_state, :player_chips, 0)
    min_raise = Map.get(game_state, :min_raise, 0)

    amount =
      case action do
        :raise -> min(Enum.random(min_raise..max(min_raise, chips)), chips)
        :all_in -> chips
        _ -> 0
      end

    {:ok, %{
      action: action,
      amount: amount,
      reasoning: "Random decision.",
      talk: ""
    }}
  end

  @impl true
  def buy_in(budget, _character) do
    # Random engine: buy in with ~60% of budget, leave rest for thinking tax
    max_chips = trunc(budget * 100)  # 1 chip = $0.01
    chips = max(1, trunc(max_chips * 0.6))
    {:ok, chips}
  end
end
```

```elixir
# lib/binz_poker/llm/mock.ex
defmodule BinzPoker.LLM.Mock do
  @behaviour BinzPoker.LLM

  @impl true
  def chat(_model, _messages, _opts \\ []) do
    {:ok, %{
      content: ~s({"action": "call", "amount": 0, "inner_thought": "Mock thought.", "table_talk": ""}),
      usage: %{input: 100, output: 50}
    }}
  end
end
```

```elixir
# lib/binz_poker/character_gen/hardcoded.ex
defmodule BinzPoker.CharacterGen.Hardcoded do
  @behaviour BinzPoker.CharacterGen
  alias BinzPoker.Character

  @names ["Rico", "Sister Mary", "Snake Eyes", "The Professor", "Lucky Lucy",
          "Big Al", "Slim Jim", "Red", "Doc Holiday", "Iron Mike"]

  @impl true
  def generate(opts \\ []) do
    taken = Keyword.get(opts, :taken_names, [])
    available = @names -- taken
    name = Keyword.get(opts, :name, Enum.random(if(available == [], do: @names, else: available)))
    model = Keyword.get(opts, :model, "mock-model")
    traits = Character.random_traits()

    character = Character.new(%{
      name: name,
      backstory: "#{name} walked into the Binz Poker Room with nothing to lose.",
      traits: traits,
      model: model
    })

    {:ok, character}
  end
end
```

```elixir
# lib/binz_poker/game_log/logger.ex
defmodule BinzPoker.GameLog.Logger do
  @behaviour BinzPoker.GameLog
  require Logger

  @impl true
  def log_event(event_type, payload) do
    Logger.info("[BinzPoker] #{event_type}: #{inspect(payload)}")
    :ok
  end
end
```

**Step 4: Run tests**

```bash
mix test test/binz_poker/decision_engine/random_test.exs
```

Expected: PASS

**Step 5: Update test config**

Add to `config/test.exs`:

```elixir
config :binz_poker,
  decision_engine: BinzPoker.DecisionEngine.Random,
  llm_provider: BinzPoker.LLM.Mock,
  character_gen: BinzPoker.CharacterGen.Hardcoded,
  game_log: BinzPoker.GameLog.Logger
```

**Step 6: Commit**

```bash
git add lib/binz_poker/llm/mock.ex lib/binz_poker/decision_engine/random.ex lib/binz_poker/character_gen/hardcoded.ex lib/binz_poker/game_log/logger.ex test/binz_poker/decision_engine/random_test.exs config/test.exs
git commit -m "feat: add mock/test implementations for all behaviours"
```


