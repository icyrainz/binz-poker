defmodule BinzPoker.Schemas.SimRecord do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  alias BinzPoker.Repo

  schema "sims" do
    field :hand_count, :integer, default: 0
    field :status, :string, default: "running"
    field :max_players, :integer, default: 10
    field :table_size, :integer, default: 6
    field :dealer_seat, :integer, default: 0
    field :started_at, :utc_datetime
    field :stopped_at, :utc_datetime

    timestamps()
  end

  def changeset(record, attrs) do
    record
    |> cast(attrs, [:hand_count, :status, :max_players, :table_size,
                    :dealer_seat, :started_at, :stopped_at])
    |> validate_inclusion(:status, ["running", "paused", "stopped"])
  end

  def create(attrs \\ %{}) do
    attrs = Map.put_new(attrs, :started_at, DateTime.utc_now())
    %__MODULE__{}
    |> changeset(attrs)
    |> Repo.insert()
  end

  def get(id) do
    Repo.get(__MODULE__, id)
  end

  def get_current do
    __MODULE__
    |> where([s], s.status == "running")
    |> order_by([s], [desc: s.inserted_at, desc: s.id])
    |> limit(1)
    |> Repo.one()
  end

  def update_fields(id, attrs) when is_map(attrs) do
    case get(id) do
      nil -> {:error, :not_found}
      record ->
        record
        |> changeset(attrs)
        |> Repo.update()
    end
  end

  def increment_hand_count(id) do
    case get(id) do
      nil -> {:error, :not_found}
      record ->
        record
        |> changeset(%{hand_count: record.hand_count + 1})
        |> Repo.update()
    end
  end
end
