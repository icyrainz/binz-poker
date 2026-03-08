defmodule BinzPoker.Repo.Migrations.CreateLoans do
  use Ecto.Migration

  def change do
    create table(:loans) do
      add :player_id, :string, null: false
      add :requested_amount, :float, null: false
      add :granted_amount, :float
      add :interest_rate, :float
      add :message, :text
      add :status, :string, null: false, default: "pending"
      add :hands_remaining, :integer
      add :sim_id, references(:sims), null: true

      timestamps()
    end

    create index(:loans, [:player_id])
    create index(:loans, [:status])
  end
end
