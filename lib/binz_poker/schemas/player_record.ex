defmodule BinzPoker.Schemas.PlayerRecord do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  alias BinzPoker.Repo

  schema "players" do
    field :player_id, :string
    field :name, :string
    field :backstory, :string
    field :traits, :map
    field :model, :string
    field :status, :string, default: "away"
    field :chips, :integer, default: 0
    field :budget, :float, default: 5.00
    field :token_bill, :float, default: 0.0
    field :total_token_cost, :float, default: 0.0
    field :total_winnings, :float, default: 0.0
    field :peak_budget, :float, default: 5.00
    field :hands_played, :integer, default: 0
    field :hands_won, :integer, default: 0
    field :observations, :map, default: %{"events" => []}
    field :opponent_notes, :map, default: %{}
    field :sim_id, :integer

    timestamps()
  end

  def changeset(record, attrs) do
    record
    |> cast(attrs, [:player_id, :name, :backstory, :traits, :model, :status,
                    :chips, :budget, :token_bill, :total_token_cost, :total_winnings,
                    :peak_budget, :hands_played, :hands_won, :observations, :opponent_notes,
                    :sim_id])
    |> validate_required([:player_id, :name, :traits, :model])
    |> validate_inclusion(:status, ["seated", "away", "dead"])
    |> unique_constraint(:player_id)
  end

  def create(attrs) do
    %__MODULE__{}
    |> changeset(attrs)
    |> Repo.insert()
  end

  def get_by_player_id(player_id) do
    Repo.get_by(__MODULE__, player_id: player_id)
  end

  def get_living_players do
    __MODULE__
    |> where([p], p.status in ["seated", "away"])
    |> Repo.all()
  end

  def update_field(player_id, field, value) do
    case get_by_player_id(player_id) do
      nil -> {:error, :not_found}
      record ->
        record
        |> changeset(%{field => value})
        |> Repo.update()
    end
  end

  def update_fields(player_id, attrs) when is_map(attrs) do
    case get_by_player_id(player_id) do
      nil -> {:error, :not_found}
      record ->
        record
        |> changeset(attrs)
        |> Repo.update()
    end
  end

  def mark_dead(player_id) do
    update_field(player_id, :status, "dead")
  end

  def delete_by_player_id(player_id) do
    case get_by_player_id(player_id) do
      nil -> {:error, :not_found}
      record -> Repo.delete(record)
    end
  end
end
