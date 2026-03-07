### Character & Traits Data Structures

**Files:**

- Create: `lib/binz_poker/character.ex`
- Create: `test/binz_poker/character_test.exs`

**Step 1: Write failing tests**

```elixir
# test/binz_poker/character_test.exs
defmodule BinzPoker.CharacterTest do
  use ExUnit.Case, async: true
  alias BinzPoker.Character

  test "random_traits returns all 8 traits" do
    traits = Character.random_traits()
    assert Map.keys(traits) |> Enum.sort() == [
      :aggression, :deceptiveness, :desperation, :discipline,
      :greed, :pride, :risk_tolerance, :sociability
    ]
  end

  test "each trait is low, medium, or high" do
    traits = Character.random_traits()
    Enum.each(traits, fn {_key, val} ->
      assert val in [:low, :medium, :high]
    end)
  end

  test "new creates a character with required fields" do
    char = Character.new(%{
      name: "Rico",
      backstory: "A former trader.",
      traits: Character.random_traits(),
      model: "gpt-4o",
      budget: 5.00
    })
    assert char.name == "Rico"
    assert char.budget == 5.00
    assert char.chips == 0  # starts with 0 chips, buys in at table entry
    assert char.hands_played == 0
    assert char.token_bill == 0.0
  end
end
```

**Step 2: Run test to verify it fails**

```bash
mix test test/binz_poker/character_test.exs
```

**Step 3: Implement Character**

```elixir
# lib/binz_poker/character.ex
defmodule BinzPoker.Character do
  defstruct [
    :name, :backstory, :traits, :model,
    budget: 5.00, chips: 0,
    hands_played: 0, hands_won: 0,
    token_bill: 0.0, total_token_cost: 0.0,
    total_winnings: 0.0, peak_budget: 5.00
  ]

  @traits [:aggression, :risk_tolerance, :discipline, :greed,
           :pride, :desperation, :deceptiveness, :sociability]
  @levels [:low, :medium, :high]

  def trait_names, do: @traits

  def random_traits do
    Map.new(@traits, fn trait -> {trait, Enum.random(@levels)} end)
  end

  def new(attrs) do
    budget = Map.get(attrs, :budget, Application.get_env(:binz_poker, :starting_budget, 5.00))

    struct!(__MODULE__,
      Map.merge(attrs, %{
        chips: 0,  # starts with 0, buys in at table entry
        budget: budget,
        peak_budget: budget,
        hands_played: 0,
        hands_won: 0,
        token_bill: 0.0,
        total_token_cost: 0.0,
        total_winnings: 0.0
      })
    )
  end
end
```

**Step 4: Run test**

```bash
mix test test/binz_poker/character_test.exs
```

Expected: PASS

**Step 5: Commit**

```bash
git add lib/binz_poker/character.ex test/binz_poker/character_test.exs
git commit -m "feat: add Character struct with random trait generation"
```


