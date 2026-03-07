### Behaviours — LLM, DecisionEngine, CharacterGen, GameLog

**Files:**

- Create: `lib/binz_poker/llm.ex` (behaviour + dispatcher)
- Create: `lib/binz_poker/decision_engine.ex` (behaviour + dispatcher)
- Create: `lib/binz_poker/character_gen.ex` (behaviour + dispatcher)
- Create: `lib/binz_poker/game_log.ex` (behaviour + dispatcher)

**Step 1: Create all four behaviour modules**

```elixir
# lib/binz_poker/llm.ex
defmodule BinzPoker.LLM do
  @callback chat(model :: String.t(), messages :: list(), opts :: keyword()) ::
    {:ok, %{content: String.t(), usage: %{input: integer(), output: integer()}}}
    | {:error, term()}

  def impl, do: Application.get_env(:binz_poker, :llm_provider, BinzPoker.LLM.LiteLLM)
  def chat(model, messages, opts \\ []), do: impl().chat(model, messages, opts)
end
```

```elixir
# lib/binz_poker/decision_engine.ex
defmodule BinzPoker.DecisionEngine do
  @callback decide(game_state :: map(), character :: map()) ::
    {:ok, %{action: atom(), amount: integer(), reasoning: String.t(), talk: String.t()}}
  @callback buy_in(budget :: float(), character :: map()) ::
    {:ok, integer()}

  def impl, do: Application.get_env(:binz_poker, :decision_engine, BinzPoker.DecisionEngine.LLM)
  def decide(game_state, character), do: impl().decide(game_state, character)
  def buy_in(budget, character), do: impl().buy_in(budget, character)
end
```

```elixir
# lib/binz_poker/character_gen.ex
defmodule BinzPoker.CharacterGen do
  @callback generate(opts :: keyword()) :: {:ok, %BinzPoker.Character{}}

  def impl, do: Application.get_env(:binz_poker, :character_gen, BinzPoker.CharacterGen.LLMBased)
  def generate(opts \\ []), do: impl().generate(opts)
end
```

```elixir
# lib/binz_poker/game_log.ex
defmodule BinzPoker.GameLog do
  @callback log_event(event_type :: atom(), payload :: map()) :: :ok

  def impl, do: Application.get_env(:binz_poker, :game_log, BinzPoker.GameLog.PubSubLogger)
  def log_event(event_type, payload), do: impl().log_event(event_type, payload)
end
```

**Step 2: Verify compilation**

```bash
mix compile
```

Expected: no errors

**Step 3: Commit**

```bash
git add lib/binz_poker/llm.ex lib/binz_poker/decision_engine.ex lib/binz_poker/character_gen.ex lib/binz_poker/game_log.ex
git commit -m "feat: add behaviour definitions for LLM, DecisionEngine, CharacterGen, GameLog"
```


