### Application Supervision Tree — Wire It All Together

Add all GenServers to the Application supervision tree in correct dependency order. The Sim must start after Bank, PlayerSupervisor, and Table since it subscribes to their events.

**Depends on:** Task 8 (Bank), Task 10 (PlayerSupervisor), Task 11 (Table), Task 12 (Sim)

**Files:**
- Modify: `lib/binz_poker/application.ex`

**Step 1: Wire up the supervision tree**

Edit `lib/binz_poker/application.ex`:

```elixir
defmodule BinzPoker.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Infrastructure
      BinzPoker.Repo,
      BinzPokerWeb.Telemetry,
      {Phoenix.PubSub, name: BinzPoker.PubSub},
      {Finch, name: BinzPoker.Finch},
      {Registry, keys: :unique, name: BinzPoker.PlayerRegistry},

      # Game processes (order matters — Sim depends on all three above it)
      # Note: Sim auto-creates or resumes a SimRecord on init (no sim_id needed here)
      {BinzPoker.Bank, name: BinzPoker.Bank},
      {BinzPoker.PlayerSupervisor,
        name: BinzPoker.PlayerSupervisor,
        bank: BinzPoker.Bank,
        character_gen: Application.get_env(:binz_poker, :character_gen, BinzPoker.CharacterGen.Hardcoded),
        decision_engine: Application.get_env(:binz_poker, :decision_engine, BinzPoker.DecisionEngine.Random)},
      {BinzPoker.Table,
        name: BinzPoker.Table,
        hand_evaluator: Application.get_env(:binz_poker, :hand_evaluator, BinzPoker.HandEvaluator.Native),
        auto_start: false},
      {BinzPoker.Sim,
        name: BinzPoker.Sim,
        bank: BinzPoker.Bank,
        player_supervisor: BinzPoker.PlayerSupervisor,
        table: BinzPoker.Table},

      # Web
      BinzPokerWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: BinzPoker.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    BinzPokerWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
```

**Step 2: Run full test suite**

```bash
mix test
```

Expected: all tests pass

**Step 3: Verify the app starts**

```bash
mix phx.server
```

Verify: app starts, no crashes, endpoints respond.

**Step 4: Commit**

```bash
git add lib/binz_poker/application.ex
git commit -m "feat: wire up full OTP supervision tree with Sim reactor"
```
