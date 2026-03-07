### Core Data Structures — Card, Deck

**Files:**

- Create: `lib/binz_poker/card.ex`
- Create: `lib/binz_poker/deck.ex`
- Create: `test/binz_poker/card_test.exs`
- Create: `test/binz_poker/deck_test.exs`

**Step 1: Write failing tests for Card**

```elixir
# test/binz_poker/card_test.exs
defmodule BinzPoker.CardTest do
  use ExUnit.Case, async: true
  alias BinzPoker.Card

  test "creates a card with suit and rank" do
    card = Card.new(:hearts, :ace)
    assert card.suit == :hearts
    assert card.rank == :ace
  end

  test "to_string formats card" do
    card = Card.new(:spades, :king)
    assert Card.to_string(card) == "K\u2660"
  end

  test "rank_value returns numeric value" do
    assert Card.rank_value(:ace) == 14
    assert Card.rank_value(:king) == 13
    assert Card.rank_value(2) == 2
    assert Card.rank_value(10) == 10
  end
end
```

**Step 2: Run test to verify it fails**

```bash
mix test test/binz_poker/card_test.exs
```

Expected: FAIL — module not found.

**Step 3: Implement Card**

```elixir
# lib/binz_poker/card.ex
defmodule BinzPoker.Card do
  @enforce_keys [:suit, :rank]
  defstruct [:suit, :rank]

  @suits [:hearts, :diamonds, :clubs, :spades]
  @ranks [2, 3, 4, 5, 6, 7, 8, 9, 10, :jack, :queen, :king, :ace]

  def suits, do: @suits
  def ranks, do: @ranks

  def new(suit, rank) when suit in @suits and rank in @ranks do
    %__MODULE__{suit: suit, rank: rank}
  end

  def rank_value(:ace), do: 14
  def rank_value(:king), do: 13
  def rank_value(:queen), do: 12
  def rank_value(:jack), do: 11
  def rank_value(n) when is_integer(n) and n in 2..10, do: n

  def to_string(%__MODULE__{suit: suit, rank: rank}) do
    "#{rank_str(rank)}#{suit_str(suit)}"
  end

  defp rank_str(:ace), do: "A"
  defp rank_str(:king), do: "K"
  defp rank_str(:queen), do: "Q"
  defp rank_str(:jack), do: "J"
  defp rank_str(n), do: Integer.to_string(n)

  defp suit_str(:hearts), do: "\u2665"
  defp suit_str(:diamonds), do: "\u2666"
  defp suit_str(:clubs), do: "\u2663"
  defp suit_str(:spades), do: "\u2660"
end
```

**Step 4: Run test to verify it passes**

```bash
mix test test/binz_poker/card_test.exs
```

Expected: PASS

**Step 5: Write failing tests for Deck**

```elixir
# test/binz_poker/deck_test.exs
defmodule BinzPoker.DeckTest do
  use ExUnit.Case, async: true
  alias BinzPoker.Deck

  test "new deck has 52 cards" do
    deck = Deck.new()
    assert length(deck.cards) == 52
  end

  test "all cards are unique" do
    deck = Deck.new()
    assert length(Enum.uniq(deck.cards)) == 52
  end

  test "shuffle randomizes order" do
    deck1 = Deck.new()
    deck2 = Deck.shuffle(deck1)
    # Very unlikely to be the same order
    refute deck1.cards == deck2.cards
  end

  test "deal takes N cards off the top" do
    deck = Deck.new() |> Deck.shuffle()
    {cards, remaining} = Deck.deal(deck, 2)
    assert length(cards) == 2
    assert length(remaining.cards) == 50
  end

  test "deal errors when not enough cards" do
    deck = %Deck{cards: []}
    assert {:error, :not_enough_cards} = Deck.deal(deck, 1)
  end
end
```

**Step 6: Run test to verify it fails**

```bash
mix test test/binz_poker/deck_test.exs
```

**Step 7: Implement Deck**

```elixir
# lib/binz_poker/deck.ex
defmodule BinzPoker.Deck do
  alias BinzPoker.Card

  defstruct cards: []

  def new do
    cards =
      for suit <- Card.suits(), rank <- Card.ranks() do
        Card.new(suit, rank)
      end

    %__MODULE__{cards: cards}
  end

  def shuffle(%__MODULE__{cards: cards} = _deck) do
    %__MODULE__{cards: Enum.shuffle(cards)}
  end

  def deal(%__MODULE__{cards: cards}, n) when length(cards) >= n do
    {dealt, remaining} = Enum.split(cards, n)
    {dealt, %__MODULE__{cards: remaining}}
  end

  def deal(%__MODULE__{}, _n), do: {:error, :not_enough_cards}
end
```

**Step 8: Run tests**

```bash
mix test test/binz_poker/card_test.exs test/binz_poker/deck_test.exs
```

Expected: all PASS

**Step 9: Commit**

```bash
git add lib/binz_poker/card.ex lib/binz_poker/deck.ex test/binz_poker/card_test.exs test/binz_poker/deck_test.exs
git commit -m "feat: add Card and Deck core data structures"
```

---
