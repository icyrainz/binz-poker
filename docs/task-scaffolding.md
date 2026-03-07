### Phoenix Project Scaffolding

**Files:**

- Create: entire Phoenix project at `~/repo/binz-poker`

**Step 1: Generate Phoenix project**

```bash
cd ~/repo
mix phx.new binz_poker --no-html --no-assets --no-mailer --no-dashboard --database sqlite3
cd binz_poker
```

Use `--no-html --no-assets --no-mailer --no-dashboard` since we only need JSON API + OTP. SQLite via `--database sqlite3`.

**Step 2: Verify it compiles and tests pass**

```bash
mix deps.get
mix ecto.create
mix test
```

Expected: all default Phoenix tests pass.

**Step 3: Clean up and configure**

Edit `config/config.exs` to add binz_poker app config:

```elixir
config :binz_poker,
  max_players: 10,
  table_size: 6,
  starting_budget: 5.00,
  small_blind: 1,
  big_blind: 2,
  hand_delay_ms: 5000,
  auto_banker: true,
  litellm_url: "http://litellm.lan/v1",
  litellm_key: "sk-litellm-master-changeme"
```

Edit `config/test.exs` to add test overrides:

```elixir
config :binz_poker,
  hand_delay_ms: 0,
  auto_banker: true
```

**Step 4: Commit**

```bash
git init
git add -A
git commit -m "feat: scaffold Phoenix project with SQLite"
```

---
