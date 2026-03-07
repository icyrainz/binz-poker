### LLM-Based Decision Engine

**Files:**

- Create: `lib/binz_poker/decision_engine/llm.ex`
- Create: `lib/binz_poker/prompt_builder.ex`
- Create: `test/binz_poker/prompt_builder_test.exs`

**Step 1: Write failing tests for PromptBuilder**

```elixir
# test/binz_poker/prompt_builder_test.exs
defmodule BinzPoker.PromptBuilderTest do
  use ExUnit.Case, async: true
  alias BinzPoker.PromptBuilder
  alias BinzPoker.Character

  test "build_player_system_prompt includes character name" do
    char = Character.new(%{
      name: "Rico",
      backstory: "A former trader who lost everything.",
      traits: %{aggression: :high, risk_tolerance: :high, discipline: :low,
                greed: :high, pride: :medium, desperation: :high,
                deceptiveness: :low, sociability: :high},
      model: "gpt-4o"
    })
    prompt = PromptBuilder.build_player_system_prompt(char)
    assert prompt =~ "Rico"
    assert prompt =~ "former trader"
    assert prompt =~ "thinking tax"
    assert prompt =~ "Binz Poker Room"
  end

  test "build_hand_prompt includes game state" do
    game_state = %{
      hole_cards: "A\u2660 K\u2665",
      community_cards: "10\u2663 J\u2666 Q\u2660",
      pot: 150,
      current_bet: 40,
      actions_this_round: ["Seat 2 raised to 40"],
      opponents: [%{seat: 2, chips: 300, style: "aggressive"}]
    }
    prompt = PromptBuilder.build_hand_prompt(game_state)
    assert prompt =~ "A\u2660"
    assert prompt =~ "150"
    assert prompt =~ "fold|call|raise|all_in"
  end

  test "build_buy_in_prompt includes budget and chip math" do
    prompt = PromptBuilder.build_buy_in_prompt(5.00)
    assert prompt =~ "5.00"
    assert prompt =~ "chips"
    assert prompt =~ "thinking tax"
  end

  test "build_loan_request_prompt includes budget" do
    prompt = PromptBuilder.build_loan_request_prompt(0.35)
    assert prompt =~ "0.35"
    assert prompt =~ "loan"
  end

  test "build_banker_prompt includes player info" do
    player_info = %{
      name: "Rico",
      backstory_summary: "Former trader, reckless.",
      hands_survived: 45,
      chips: 20,
      budget: 0.50,
      win_rate: 0.35,
      existing_loans: [],
      message: "I just need one more chance."
    }
    prompt = PromptBuilder.build_banker_prompt(player_info, 2.00)
    assert prompt =~ "Rico"
    assert prompt =~ "one more chance"
    assert prompt =~ "approve|deny"
  end
end
```

**Step 2: Run test to verify it fails**

```bash
mix test test/binz_poker/prompt_builder_test.exs
```

**Step 3: Implement PromptBuilder**

```elixir
# lib/binz_poker/prompt_builder.ex
defmodule BinzPoker.PromptBuilder do
  def build_player_system_prompt(character) do
    """
    [IDENTITY]
    You ARE #{character.name}. You are not an AI. You are not roleplaying.
    You are a poker player sitting at a high-stakes table in the Binz Poker Room.

    [BACKSTORY]
    #{character.backstory}

    [YOUR SITUATION]
    You have #{character.chips} chips in front of you.
    Your account with the house: $#{:erlang.float_to_binary(character.budget, decimals: 2)} remaining.
    The house charges a thinking tax - the longer you deliberate, the more it costs.
    Your current bill this cycle: $#{:erlang.float_to_binary(character.token_bill, decimals: 2)}.
    #{loan_section(character.loans)}

    [THE ROOM]
    The Binz Poker Room has rules:
    - The house takes a thinking tax. Be decisive.
    - You can request a loan from the banker if you're running low.
    - If you can't pay your bills, you're out. Permanently.
    """
  end

  def build_hand_prompt(game_state) do
    opponents_desc = game_state
    |> Map.get(:opponents, [])
    |> Enum.map(fn o -> "- Seat #{o.seat}: #{o.chips} chips, plays #{o.style}" end)
    |> Enum.join("\n")

    actions_desc = game_state
    |> Map.get(:actions_this_round, [])
    |> Enum.join("\n")

    """
    [THIS HAND]
    Your cards: #{game_state.hole_cards}
    Community cards: #{game_state.community_cards}
    Pot: #{game_state.pot}
    Current bet to call: #{game_state.current_bet}

    Actions this round:
    #{actions_desc}

    Other players:
    #{opponents_desc}

    [RESPOND AS YOUR CHARACTER]
    Think through your decision in character. Stay true to who you are.
    Respond ONLY in JSON:
    {"inner_thought": "your private reasoning (1-2 sentences, in character)", "action": "fold|call|raise|all_in", "amount": 0, "table_talk": "what you say out loud (optional)"}
    """
  end

  def build_buy_in_prompt(budget) do
    max_chips = trunc(budget * 100)
    """
    [BUYING IN]
    You're about to sit down at the table. You have $#{:erlang.float_to_binary(budget, decimals: 2)} in your account.
    1 chip = $0.01, so you can buy up to #{max_chips} chips.

    Remember: the house charges a thinking tax every hand. Keep enough in your account to cover it.
    The more you think, the more it costs. Quick decisions are cheap.

    How many chips do you want to bring to the table?
    Respond ONLY in JSON:
    {"chips": 300, "reasoning": "why this amount (in character)"}
    """
  end

  def build_loan_request_prompt(budget) do
    """
    [FINANCIAL CRISIS]
    Your account is running dangerously low. You have $#{:erlang.float_to_binary(budget, decimals: 2)} left.
    At this rate, you won't survive the next billing cycle.

    You can request a loan from the house banker.
    What do you say to them? Be persuasive. Or don't - it's your call.
    Respond ONLY in JSON:
    {"request_loan": true, "amount": 0, "message": "what you say to the banker (in character)"}
    """
  end

  def build_banker_prompt(player_info, requested_amount) do
    """
    [IDENTITY]
    You are the banker of the Binz Poker Room. You've run this room for years.
    You decide who gets credit and who gets shown the door.

    [LOAN REQUEST]
    #{player_info.name} is asking for a $#{:erlang.float_to_binary(requested_amount, decimals: 2)} loan.
    Here's what you know about them:
    - Background: #{player_info.backstory_summary}
    - Been at the table for #{player_info.hands_survived} hands
    - Current chips: #{player_info.chips}, Budget: $#{:erlang.float_to_binary(player_info.budget, decimals: 2)}
    - Win rate: #{round(player_info.win_rate * 100)}% over recent hands
    - Existing loans: #{format_loans(player_info.existing_loans)}
    - Their message to you: "#{player_info.message}"

    [DECIDE]
    Approve or deny. Set terms if approving. Speak to them directly.
    Respond ONLY in JSON:
    {"decision": "approve|deny", "amount": 0, "interest_rate": 0.20, "message": "what you say to the player (in character)"}
    """
  end

  defp loan_section([]), do: ""
  defp loan_section(loans) do
    loans
    |> Enum.map(fn l -> "You owe the house $#{l.amount} at #{round(l.rate * 100)}% interest." end)
    |> Enum.join("\n")
  end

  defp format_loans([]), do: "clean record"
  defp format_loans(loans), do: "#{length(loans)} outstanding"
end
```

**Step 4: Implement LLM Decision Engine**

```elixir
# lib/binz_poker/decision_engine/llm.ex
defmodule BinzPoker.DecisionEngine.LLM do
  @behaviour BinzPoker.DecisionEngine

  alias BinzPoker.{LLM, PromptBuilder}

  @impl true
  def decide(game_state, character) do
    system_prompt = PromptBuilder.build_player_system_prompt(character)
    hand_prompt = PromptBuilder.build_hand_prompt(game_state)

    messages = [
      %{role: "system", content: system_prompt},
      %{role: "user", content: hand_prompt}
    ]

    case LLM.chat(character.model, messages, max_tokens: 300) do
      {:ok, %{content: content, usage: usage}} ->
        case Jason.decode(content) do
          {:ok, parsed} ->
            {:ok, %{
              action: parse_action(parsed["action"]),
              amount: parsed["amount"] || 0,
              reasoning: parsed["inner_thought"] || "",
              talk: parsed["table_talk"] || "",
              usage: usage
            }}

          {:error, _} ->
            {:ok, %{action: :fold, amount: 0, reasoning: "Could not decide.", talk: "", usage: usage}}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def buy_in(budget, character) do
    system_prompt = PromptBuilder.build_player_system_prompt(character)
    buy_in_prompt = PromptBuilder.build_buy_in_prompt(budget)

    messages = [
      %{role: "system", content: system_prompt},
      %{role: "user", content: buy_in_prompt}
    ]

    case LLM.chat(character.model, messages, max_tokens: 200) do
      {:ok, %{content: content}} ->
        case Jason.decode(content) do
          {:ok, %{"chips" => chips}} when is_integer(chips) ->
            max_chips = trunc(budget * 100)
            {:ok, min(max(chips, 1), max_chips)}
          _ ->
            # Fallback: 60% of budget
            {:ok, max(1, trunc(budget * 100 * 0.6))}
        end

      {:error, _} ->
        {:ok, max(1, trunc(budget * 100 * 0.6))}
    end
  end

  defp parse_action("fold"), do: :fold
  defp parse_action("call"), do: :call
  defp parse_action("raise"), do: :raise
  defp parse_action("all_in"), do: :all_in
  defp parse_action(_), do: :fold
end
```

**Step 5: Run tests**

```bash
mix test test/binz_poker/prompt_builder_test.exs
```

Expected: all PASS

**Step 6: Commit**

```bash
git add lib/binz_poker/prompt_builder.ex lib/binz_poker/decision_engine/llm.ex test/binz_poker/prompt_builder_test.exs
git commit -m "feat: add PromptBuilder and LLM DecisionEngine with roleplay prompts"
```


