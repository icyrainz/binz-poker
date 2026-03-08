defmodule BinzPoker.Repo.Migrations.CreateHandHistories do
  use Ecto.Migration

  def change do
    create table(:hand_histories) do
      add :hand_number, :integer, null: false
      add :sim_id, :integer
      add :table_id, :string
      add :players, :map        # %{player_id => %{name, seat, starting_chips}}
      add :hole_cards, :map     # %{player_id => ["Ah", "Kd"]}
      add :community_cards, {:array, :string}  # ["6h", "10h", "8c", "7s", "Jd"]
      add :actions, {:array, :map}  # [%{player: "player_1", action: "raise", amount: 100, street: "preflop"}, ...]
      add :pots, {:array, :map}     # [%{amount: 600, eligible: [...], winner: "player_1"}, ...]
      add :winners, :map            # %{player_id => chips_won}
      add :showdown_hands, :map     # %{player_id => %{rank: "full_house", cards: ["Ah","Kd"]}}
      add :method, :string          # "showdown" | "last_standing"
      add :blinds, :map             # %{sb_id: ..., bb_id: ..., sb_amt: ..., bb_amt: ...}

      timestamps()
    end

    create index(:hand_histories, [:sim_id])
    create index(:hand_histories, [:table_id])
    create index(:hand_histories, [:sim_id, :hand_number])
  end
end
