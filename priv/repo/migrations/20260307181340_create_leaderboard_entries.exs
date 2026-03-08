defmodule BinzPoker.Repo.Migrations.CreateLeaderboardEntries do
  use Ecto.Migration

  def change do
    create table(:leaderboard_entries) do
      add :character_name, :string, null: false
      add :model, :string, null: false
      add :traits, :map, null: false
      add :backstory, :text
      add :hands_survived, :integer, default: 0
      add :peak_budget, :float, default: 0.0
      add :total_winnings, :float, default: 0.0
      add :total_token_cost, :float, default: 0.0
      add :cause_of_death, :string
      add :loans_taken, :integer, default: 0
      add :loans_repaid, :integer, default: 0
      add :died_at, :utc_datetime
      add :sim_id, references(:sims), null: true

      timestamps()
    end
  end
end
