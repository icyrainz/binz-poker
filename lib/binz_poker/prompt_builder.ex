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
