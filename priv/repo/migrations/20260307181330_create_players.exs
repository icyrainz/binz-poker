defmodule BinzPoker.Repo.Migrations.CreatePlayers do
  use Ecto.Migration

  def change do
    create table(:players) do
      add :player_id, :string, null: false
      add :name, :string, null: false
      add :backstory, :text
      add :traits, :map, null: false
      add :model, :string, null: false
      add :status, :string, null: false, default: "away"
      add :chips, :integer, default: 0
      add :budget, :float, default: 5.00
      add :token_bill, :float, default: 0.0
      add :total_token_cost, :float, default: 0.0
      add :total_winnings, :float, default: 0.0
      add :peak_budget, :float, default: 5.00
      add :hands_played, :integer, default: 0
      add :hands_won, :integer, default: 0
      add :observations, :map, default: %{"events" => []}
      add :opponent_notes, :map, default: %{}
      add :sim_id, references(:sims), null: true

      timestamps()
    end

    create unique_index(:players, [:player_id])
  end
end
