defmodule BinzPoker.Schemas.LeaderboardEntry do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  alias BinzPoker.Repo

  schema "leaderboard_entries" do
    field :character_name, :string
    field :model, :string
    field :traits, :map
    field :backstory, :string
    field :hands_survived, :integer, default: 0
    field :peak_budget, :float, default: 0.0
    field :total_winnings, :float, default: 0.0
    field :total_token_cost, :float, default: 0.0
    field :cause_of_death, :string
    field :loans_taken, :integer, default: 0
    field :loans_repaid, :integer, default: 0
    field :died_at, :utc_datetime
    field :sim_id, :integer

    timestamps()
  end

  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [:character_name, :model, :traits, :backstory, :hands_survived,
                    :peak_budget, :total_winnings, :total_token_cost, :cause_of_death,
                    :loans_taken, :loans_repaid, :died_at, :sim_id])
    |> validate_required([:character_name, :model, :cause_of_death])
  end

  def record_death(attrs) do
    attrs = Map.put_new(attrs, :died_at, DateTime.utc_now())
    %__MODULE__{}
    |> changeset(attrs)
    |> Repo.insert()
  end

  def top_survivors(limit \\ 10) do
    __MODULE__
    |> order_by(desc: :hands_survived)
    |> limit(^limit)
    |> Repo.all()
  end
end
