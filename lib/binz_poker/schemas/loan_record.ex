defmodule BinzPoker.Schemas.LoanRecord do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  alias BinzPoker.Repo

  schema "loans" do
    field :player_id, :string
    field :requested_amount, :float
    field :granted_amount, :float
    field :interest_rate, :float
    field :message, :string
    field :status, :string, default: "pending"
    field :hands_remaining, :integer
    field :sim_id, :integer

    timestamps()
  end

  def changeset(record, attrs) do
    record
    |> cast(attrs, [:player_id, :requested_amount, :granted_amount, :interest_rate,
                    :message, :status, :hands_remaining, :sim_id])
    |> validate_required([:player_id, :requested_amount])
    |> validate_inclusion(:status, ["pending", "approved", "denied", "repaid"])
  end

  def create(attrs) do
    %__MODULE__{}
    |> changeset(attrs)
    |> Repo.insert()
  end

  def get_pending_for_player(player_id) do
    __MODULE__
    |> where([l], l.player_id == ^player_id and l.status == "pending")
    |> Repo.all()
  end

  def get_active_for_player(player_id) do
    __MODULE__
    |> where([l], l.player_id == ^player_id and l.status == "approved")
    |> Repo.all()
  end

  def get_pending do
    __MODULE__
    |> where([l], l.status == "pending")
    |> Repo.all()
  end

  def approve(loan_id, granted_amount, interest_rate) do
    deadline = Application.get_env(:binz_poker, :loan_repayment_deadline_hands, 50)
    case Repo.get(__MODULE__, loan_id) do
      nil -> {:error, :not_found}
      loan ->
        loan
        |> changeset(%{
          status: "approved",
          granted_amount: granted_amount,
          interest_rate: interest_rate,
          hands_remaining: deadline
        })
        |> Repo.update()
    end
  end

  def deny(loan_id) do
    case Repo.get(__MODULE__, loan_id) do
      nil -> {:error, :not_found}
      loan ->
        loan
        |> changeset(%{status: "denied"})
        |> Repo.update()
    end
  end
end
