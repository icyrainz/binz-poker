defmodule BinzPoker.Repo.Migrations.CreateSims do
  use Ecto.Migration

  def change do
    create table(:sims) do
      add :hand_count, :integer, default: 0
      add :status, :string, null: false, default: "running"
      add :max_players, :integer, default: 10
      add :table_size, :integer, default: 6
      add :dealer_seat, :integer, default: 0
      add :started_at, :utc_datetime
      add :stopped_at, :utc_datetime

      timestamps()
    end
  end
end
