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
    assert char.chips == 0
    assert char.hands_played == 0
    assert char.token_bill == 0.0
  end
end
