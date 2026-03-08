defmodule BinzPoker.DecisionEngine do
  @callback decide(game_state :: map(), character :: map()) ::
    {:ok, %{action: atom(), amount: integer(), reasoning: String.t(), talk: String.t()}}
  @callback buy_in(budget :: float(), character :: map()) ::
    {:ok, integer()}

  def impl, do: Application.get_env(:binz_poker, :decision_engine, BinzPoker.DecisionEngine.LLM)
  def decide(game_state, character), do: impl().decide(game_state, character)
  def buy_in(budget, character), do: impl().buy_in(budget, character)
end
