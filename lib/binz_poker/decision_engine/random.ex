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
    max_chips = trunc(budget * 100)
    chips = max(1, trunc(max_chips * 0.6))
    {:ok, chips}
  end
end
