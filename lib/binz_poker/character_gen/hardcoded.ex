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
