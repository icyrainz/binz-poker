### Phoenix JSON API — Banker Controls & Table State

The API lets a human observe the simulation. In v1, loans are auto-approved (no manual banker mode). The API provides read-only state and table controls (pause/resume).

**Depends on:** Task 7 (Ecto Schemas), Task 8 (Bank), Task 11 (Table), Task 12 (Sim)

**Files:**
- Create: `lib/binz_poker_web/controllers/banker_controller.ex`
- Create: `lib/binz_poker_web/controllers/table_controller.ex`
- Modify: `lib/binz_poker_web/router.ex`
- Create: `test/binz_poker_web/controllers/table_controller_test.exs`
- Create: `test/binz_poker_web/controllers/banker_controller_test.exs`

**Step 1: Add routes**

Edit `lib/binz_poker_web/router.ex`:

```elixir
scope "/api", BinzPokerWeb do
  pipe_through :api

  # Read-only state
  get "/table/state", TableController, :state
  get "/players", TableController, :players
  get "/players/:player_id", TableController, :player
  get "/leaderboard", TableController, :leaderboard
  get "/sim/status", TableController, :sim_status

  # Banker controls
  post "/banker/mode/auto", BankerController, :set_auto
  post "/banker/mode/manual", BankerController, :set_manual
  get "/banker/loans/pending", BankerController, :pending_loans
  post "/banker/loan/:id/approve", BankerController, :approve_loan
  post "/banker/loan/:id/deny", BankerController, :deny_loan

  # Table controls
  post "/table/pause", BankerController, :pause_table
  post "/table/resume", BankerController, :resume_table

  # Player management
  post "/banker/kick/:player_id", BankerController, :kick
end
```

**Step 2: Implement TableController**

```elixir
# lib/binz_poker_web/controllers/table_controller.ex
defmodule BinzPokerWeb.TableController do
  use BinzPokerWeb, :controller

  alias BinzPoker.{Table, Sim}
  alias BinzPoker.Schemas.{PlayerRecord, LeaderboardEntry}

  def state(conn, _params) do
    state = Table.get_state()
    json(conn, state)
  end

  def players(conn, _params) do
    players = PlayerRecord.get_living_players()
    json(conn, %{players: Enum.map(players, &player_summary/1)})
  end

  def player(conn, %{"player_id" => player_id}) do
    case PlayerRecord.get_by_player_id(player_id) do
      nil -> conn |> put_status(404) |> json(%{error: "not_found"})
      record -> json(conn, player_detail(record))
    end
  end

  def leaderboard(conn, _params) do
    entries = LeaderboardEntry.top_survivors(20)
    json(conn, %{leaderboard: Enum.map(entries, fn e ->
      %{
        name: e.character_name,
        model: e.model,
        hands_survived: e.hands_survived,
        peak_budget: e.peak_budget,
        cause_of_death: e.cause_of_death,
        died_at: e.died_at
      }
    end)})
  end

  def sim_status(conn, _params) do
    status = Sim.get_status()
    json(conn, status)
  end

  defp player_summary(record) do
    %{
      id: record.player_id,
      name: record.name,
      status: record.status,
      chips: record.chips,
      budget: record.budget
    }
  end

  defp player_detail(record) do
    %{
      id: record.player_id,
      name: record.name,
      backstory: record.backstory,
      traits: record.traits,
      model: record.model,
      status: record.status,
      chips: record.chips,
      budget: record.budget,
      token_bill: record.token_bill,
      total_token_cost: record.total_token_cost,
      total_winnings: record.total_winnings,
      peak_budget: record.peak_budget,
      hands_played: record.hands_played,
      hands_won: record.hands_won
    }
  end
end
```

**Step 3: Implement BankerController**

```elixir
# lib/binz_poker_web/controllers/banker_controller.ex
defmodule BinzPokerWeb.BankerController do
  use BinzPokerWeb, :controller

  alias BinzPoker.{Table, Bank, Sim, PlayerSupervisor}
  alias BinzPoker.Schemas.LoanRecord

  def set_auto(conn, _params) do
    Sim.set_banker_mode(BinzPoker.Sim, :auto)
    json(conn, %{mode: "auto", status: "ok"})
  end

  def set_manual(conn, _params) do
    Sim.set_banker_mode(BinzPoker.Sim, :manual)
    json(conn, %{mode: "manual", status: "ok"})
  end

  def pending_loans(conn, _params) do
    loans = LoanRecord.get_pending()
    json(conn, %{loans: Enum.map(loans, fn l ->
      %{id: l.id, player_id: l.player_id, amount: l.requested_amount,
        message: l.message, requested_at: l.inserted_at}
    end)})
  end

  def approve_loan(conn, %{"id" => id}) do
    loan_id = String.to_integer(id)
    amount = Map.get(conn.body_params, "amount", 2.00)
    case Bank.approve_loan(BinzPoker.Bank, loan_id, amount) do
      :ok -> json(conn, %{status: "approved"})
      {:error, reason} -> conn |> put_status(400) |> json(%{error: to_string(reason)})
    end
  end

  def deny_loan(conn, %{"id" => id}) do
    loan_id = String.to_integer(id)
    case Bank.deny_loan(BinzPoker.Bank, loan_id) do
      :ok -> json(conn, %{status: "denied"})
      {:error, reason} -> conn |> put_status(400) |> json(%{error: to_string(reason)})
    end
  end

  def pause_table(conn, _params) do
    Table.stop_auto()
    json(conn, %{status: "paused"})
  end

  def resume_table(conn, _params) do
    Table.start_auto()
    json(conn, %{status: "resumed"})
  end

  def kick(conn, %{"player_id" => player_id}) do
    case PlayerSupervisor.eliminate_and_respawn(BinzPoker.PlayerSupervisor, player_id) do
      {:ok, _} -> json(conn, %{status: "kicked", player_id: player_id})
      {:error, reason} -> conn |> put_status(400) |> json(%{error: to_string(reason)})
    end
  end
end
```

**Step 4: Write controller tests**

```elixir
# test/binz_poker_web/controllers/table_controller_test.exs
defmodule BinzPokerWeb.TableControllerTest do
  use BinzPokerWeb.ConnCase

  test "GET /api/leaderboard returns leaderboard", %{conn: conn} do
    conn = get(conn, "/api/leaderboard")
    assert %{"leaderboard" => _} = json_response(conn, 200)
  end

  test "GET /api/sim/status returns sim status", %{conn: conn} do
    conn = get(conn, "/api/sim/status")
    assert %{"hands_played" => _} = json_response(conn, 200)
  end
end
```

```elixir
# test/binz_poker_web/controllers/banker_controller_test.exs
defmodule BinzPokerWeb.BankerControllerTest do
  use BinzPokerWeb.ConnCase

  test "POST /api/banker/mode/auto sets auto mode", %{conn: conn} do
    conn = post(conn, "/api/banker/mode/auto")
    assert %{"mode" => "auto"} = json_response(conn, 200)
  end

  test "POST /api/banker/mode/manual sets manual mode", %{conn: conn} do
    conn = post(conn, "/api/banker/mode/manual")
    assert %{"mode" => "manual"} = json_response(conn, 200)
  end

  test "GET /api/banker/loans/pending returns pending loans", %{conn: conn} do
    conn = get(conn, "/api/banker/loans/pending")
    assert %{"loans" => _} = json_response(conn, 200)
  end
end
```

**Step 5: Run tests**

```bash
mix test test/binz_poker_web/controllers/
```

Expected: all PASS

**Step 6: Commit**

```bash
git add lib/binz_poker_web/controllers/ lib/binz_poker_web/router.ex test/binz_poker_web/controllers/
git commit -m "feat: add Phoenix JSON API — banker mode controls, table state, leaderboard"
```
