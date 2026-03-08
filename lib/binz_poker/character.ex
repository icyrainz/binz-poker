defmodule BinzPoker.Character do
  defstruct [
    :name, :backstory, :traits, :model,
    budget: 5.00, chips: 0,
    hands_played: 0, hands_won: 0,
    token_bill: 0.0, total_token_cost: 0.0,
    total_winnings: 0.0, peak_budget: 5.00,
    loans: []
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
        chips: 0,
        budget: budget,
        peak_budget: budget,
        hands_played: 0,
        hands_won: 0,
        token_bill: 0.0,
        total_token_cost: 0.0,
        total_winnings: 0.0,
        loans: []
      })
    )
  end
end
