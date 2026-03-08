defmodule BinzPoker.Schemas.HandHistory do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  alias BinzPoker.Repo

  schema "hand_histories" do
    field :hand_number, :integer
    field :sim_id, :integer
    field :table_id, :string
    field :players, :map
    field :hole_cards, :map
    field :community_cards, {:array, :string}
    field :actions, {:array, :map}
    field :pots, {:array, :map}
    field :winners, :map
    field :showdown_hands, :map
    field :method, :string
    field :blinds, :map

    timestamps()
  end

  def changeset(record, attrs) do
    record
    |> cast(attrs, [:hand_number, :sim_id, :table_id, :players, :hole_cards, :community_cards,
                    :actions, :pots, :winners, :showdown_hands, :method, :blinds])
    |> validate_required([:hand_number])
  end

  def create(attrs) do
    %__MODULE__{}
    |> changeset(attrs)
    |> Repo.insert()
  end

  def get_by_hand(sim_id, hand_number) do
    __MODULE__
    |> where([h], h.sim_id == ^sim_id and h.hand_number == ^hand_number)
    |> Repo.one()
  end

  def recent(sim_id, limit \\ 20) do
    __MODULE__
    |> where([h], h.sim_id == ^sim_id)
    |> order_by([h], desc: h.hand_number)
    |> limit(^limit)
    |> Repo.all()
  end
end
