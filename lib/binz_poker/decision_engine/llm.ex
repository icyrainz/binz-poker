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
