### LLM-Based Character Generator

**Files:**

- Create: `lib/binz_poker/character_gen/llm_based.ex`

**Step 1: Implement**

```elixir
# lib/binz_poker/character_gen/llm_based.ex
defmodule BinzPoker.CharacterGen.LLMBased do
  @behaviour BinzPoker.CharacterGen

  alias BinzPoker.{Character, LLM}

  @impl true
  def generate(opts \\ []) do
    model = Keyword.get(opts, :model, "gpt-4o")
    traits = Character.random_traits()

    traits_desc = traits
    |> Enum.map(fn {k, v} -> "#{k}: #{v}" end)
    |> Enum.join(", ")

    messages = [
      %{role: "system", content: "You create poker player characters. Respond ONLY in JSON."},
      %{role: "user", content: """
        Create a poker player character with these personality traits: #{traits_desc}

        Generate a compelling name and 2-3 paragraph backstory that explains WHY this person
        has these traits and why they're playing poker at the Binz Poker Room.
        Make it gritty, specific, and human. No cliches.

        Respond in JSON:
        {"name": "Full Name or Nickname", "backstory": "2-3 paragraphs"}
        """}
    ]

    case LLM.chat(model, messages, max_tokens: 500) do
      {:ok, %{content: content}} ->
        case Jason.decode(content) do
          {:ok, %{"name" => name, "backstory" => backstory}} ->
            character = Character.new(%{
              name: name,
              backstory: backstory,
              traits: traits,
              model: model
            })
            {:ok, character}

          _ ->
            fallback_generate(traits, model)
        end

      {:error, _} ->
        fallback_generate(traits, model)
    end
  end

  defp fallback_generate(traits, model) do
    names = ["Ace", "Shadow", "Lucky", "Bones", "Slim", "Red", "Doc", "Duke"]
    name = Enum.random(names)
    character = Character.new(%{
      name: name,
      backstory: "#{name} walked into the Binz Poker Room with a past they'd rather forget.",
      traits: traits,
      model: model
    })
    {:ok, character}
  end
end
```

**Step 2: Verify compilation**

```bash
mix compile
```

**Step 3: Commit**

```bash
git add lib/binz_poker/character_gen/llm_based.ex
git commit -m "feat: add LLM-based character generator with backstory creation"
```


