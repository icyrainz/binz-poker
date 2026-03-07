### Ecto Schemas & Migrations — Players, Loans, Sims, Leaderboard

All persistent state lives in SQLite via Ecto. This task creates all four tables and their schemas. GenServers (Bank, Player, Sim) will read/write these in later tasks.

**Files:**
- Create: migration `create_players`
- Create: migration `create_loans`
- Create: migration `create_sims`
- Create: migration `create_leaderboard_entries`
- Create: `lib/binz_poker/schemas/player_record.ex`
- Create: `lib/binz_poker/schemas/loan_record.ex`
- Create: `lib/binz_poker/schemas/sim_record.ex`
- Create: `lib/binz_poker/schemas/leaderboard_entry.ex`
- Create: `test/binz_poker/schemas/player_record_test.exs`
- Create: `test/binz_poker/schemas/leaderboard_entry_test.exs`
- Create: `test/binz_poker/schemas/sim_record_test.exs`

**Step 1: Generate migrations**

```bash
mix ecto.gen.migration create_sims
mix ecto.gen.migration create_players
mix ecto.gen.migration create_loans
mix ecto.gen.migration create_leaderboard_entries
```

> **Note:** `create_sims` must run first because `players`, `loans`, and `leaderboard_entries` all have `references(:sims)` foreign keys.

**Step 2: Write migrations**

```elixir
# priv/repo/migrations/..._create_players.exs
defmodule BinzPoker.Repo.Migrations.CreatePlayers do
  use Ecto.Migration

  def change do
    create table(:players) do
      add :player_id, :string, null: false
      add :name, :string, null: false
      add :backstory, :text
      add :traits, :map, null: false
      add :model, :string, null: false
      add :status, :string, null: false, default: "away"  # seated | away | dead
      add :chips, :integer, default: 0  # starts at 0, buys in at table entry
      add :budget, :float, default: 5.00
      add :token_bill, :float, default: 0.0
      add :total_token_cost, :float, default: 0.0
      add :total_winnings, :float, default: 0.0
      add :peak_budget, :float, default: 5.00
      add :hands_played, :integer, default: 0
      add :hands_won, :integer, default: 0
      add :observations, :map, default: %{"events" => []}  # event stream: list of %{type, data, at}
      add :opponent_notes, :map, default: %{}
      add :sim_id, references(:sims), null: true

      timestamps()
    end

    create unique_index(:players, [:player_id])
  end
end
```

```elixir
# priv/repo/migrations/..._create_loans.exs
defmodule BinzPoker.Repo.Migrations.CreateLoans do
  use Ecto.Migration

  def change do
    create table(:loans) do
      add :player_id, :string, null: false
      add :requested_amount, :float, null: false
      add :granted_amount, :float
      add :interest_rate, :float
      add :message, :text
      add :status, :string, null: false, default: "pending"  # pending | approved | denied | repaid
      add :hands_remaining, :integer
      add :sim_id, references(:sims), null: true

      timestamps()
    end

    create index(:loans, [:player_id])
    create index(:loans, [:status])
  end
end
```

```elixir
# priv/repo/migrations/..._create_sims.exs
defmodule BinzPoker.Repo.Migrations.CreateSims do
  use Ecto.Migration

  def change do
    create table(:sims) do
      add :hand_count, :integer, default: 0
      add :status, :string, null: false, default: "running"  # running | paused | stopped
      add :max_players, :integer, default: 10
      add :table_size, :integer, default: 6
      # billing is per-hand, no cycle config needed
      add :dealer_seat, :integer, default: 0
      add :started_at, :utc_datetime
      add :stopped_at, :utc_datetime

      timestamps()
    end
  end
end
```

```elixir
# priv/repo/migrations/..._create_leaderboard_entries.exs
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
```

**Step 3: Write Ecto schemas**

```elixir
# lib/binz_poker/schemas/player_record.ex
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
```

```elixir
# lib/binz_poker/schemas/loan_record.ex
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
```

```elixir
# lib/binz_poker/schemas/sim_record.ex
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
    # no billing_cycle_hands — billing is per-hand
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
    |> order_by(desc: :inserted_at)
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
```

```elixir
# lib/binz_poker/schemas/leaderboard_entry.ex
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
```

**Step 4: Write failing tests**

```elixir
# test/binz_poker/schemas/player_record_test.exs
defmodule BinzPoker.Schemas.PlayerRecordTest do
  use BinzPoker.DataCase

  alias BinzPoker.Schemas.PlayerRecord
  alias BinzPoker.Schemas.SimRecord

  test "create and retrieve a player record" do
    {:ok, sim} = SimRecord.create(%{})
    {:ok, record} = PlayerRecord.create(%{
      player_id: "p1",
      name: "Rico",
      backstory: "A trader.",
      traits: %{aggression: "high", discipline: "low"},
      model: "gpt-4o",
      sim_id: sim.id
    })

    assert record.player_id == "p1"
    assert record.chips == 0
    assert record.budget == 5.00
    assert record.status == "away"
    assert record.sim_id == sim.id
  end

  test "get_living_players excludes dead" do
    PlayerRecord.create(%{player_id: "p1", name: "A", traits: %{}, model: "m", status: "seated"})
    PlayerRecord.create(%{player_id: "p2", name: "B", traits: %{}, model: "m", status: "dead"})
    PlayerRecord.create(%{player_id: "p3", name: "C", traits: %{}, model: "m", status: "away"})

    living = PlayerRecord.get_living_players()
    ids = Enum.map(living, & &1.player_id)
    assert "p1" in ids
    assert "p3" in ids
    refute "p2" in ids
  end

  test "update_fields persists changes" do
    PlayerRecord.create(%{player_id: "p1", name: "A", traits: %{}, model: "m"})
    {:ok, updated} = PlayerRecord.update_fields("p1", %{chips: 300, status: "seated"})
    assert updated.chips == 300
    assert updated.status == "seated"

    reloaded = PlayerRecord.get_by_player_id("p1")
    assert reloaded.chips == 300
  end
end
```

```elixir
# test/binz_poker/schemas/leaderboard_entry_test.exs
defmodule BinzPoker.Schemas.LeaderboardEntryTest do
  use BinzPoker.DataCase

  alias BinzPoker.Schemas.LeaderboardEntry

  test "record_death creates a leaderboard entry" do
    {:ok, entry} = LeaderboardEntry.record_death(%{
      character_name: "Rico",
      model: "gpt-4o",
      traits: %{aggression: "high"},
      backstory: "A trader.",
      hands_survived: 150,
      peak_budget: 8.50,
      total_winnings: 12.30,
      total_token_cost: 0.89,
      cause_of_death: "bankrupt",
      loans_taken: 2,
      loans_repaid: 1
    })

    assert entry.character_name == "Rico"
    assert entry.hands_survived == 150
  end

  test "top_survivors returns ordered by hands_survived desc" do
    for i <- 1..3 do
      LeaderboardEntry.record_death(%{
        character_name: "Player #{i}",
        model: "mock",
        traits: %{},
        hands_survived: i * 10,
        cause_of_death: "bankrupt"
      })
    end

    top = LeaderboardEntry.top_survivors(2)
    assert length(top) == 2
    assert hd(top).hands_survived == 30
  end
end
```

```elixir
# test/binz_poker/schemas/sim_record_test.exs
defmodule BinzPoker.Schemas.SimRecordTest do
  use BinzPoker.DataCase

  alias BinzPoker.Schemas.SimRecord

  test "create a sim and read it back" do
    {:ok, sim} = SimRecord.create(%{max_players: 8, table_size: 4})

    assert sim.hand_count == 0
    assert sim.status == "running"
    assert sim.max_players == 8
    assert sim.table_size == 4
    assert sim.dealer_seat == 0
    assert sim.started_at != nil

    reloaded = SimRecord.get(sim.id)
    assert reloaded.id == sim.id
    assert reloaded.status == "running"
  end

  test "get_current returns the latest running sim" do
    {:ok, _sim1} = SimRecord.create(%{})
    {:ok, sim2} = SimRecord.create(%{})

    current = SimRecord.get_current()
    assert current.id == sim2.id
  end

  test "update_fields persists changes" do
    {:ok, sim} = SimRecord.create(%{})
    {:ok, updated} = SimRecord.update_fields(sim.id, %{status: "paused", max_players: 12})

    assert updated.status == "paused"
    assert updated.max_players == 12
  end

  test "increment_hand_count increases by one" do
    {:ok, sim} = SimRecord.create(%{})
    assert sim.hand_count == 0

    {:ok, updated} = SimRecord.increment_hand_count(sim.id)
    assert updated.hand_count == 1

    {:ok, updated2} = SimRecord.increment_hand_count(sim.id)
    assert updated2.hand_count == 2
  end
end
```

**Step 5: Run migrations and tests**

```bash
mix ecto.migrate
mix test test/binz_poker/schemas/
```

Expected: all PASS

**Step 6: Commit**

```bash
git add lib/binz_poker/schemas/ priv/repo/migrations/ test/binz_poker/schemas/
git commit -m "feat: add Ecto schemas and migrations for players, loans, sims, leaderboard"
```
