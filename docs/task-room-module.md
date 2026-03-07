### Room Module — Convenient Start/Stop/Status

A convenience module for IEx and scripts. Handles the full startup sequence: resume from DB (or spawn fresh players), seat them at the Table, and start the auto hand loop. Also provides stop and status commands.

**Depends on:** Task 12 (Sim), Task 11 (Table), Task 18 (Supervision Tree)

**Files:**
- Create: `lib/binz_poker/room.ex`

**Step 1: Create Room convenience module**

```elixir
# lib/binz_poker/room.ex
defmodule BinzPoker.Room do
  alias BinzPoker.{Table, Sim}

  @doc """
  Start the poker room. Resumes from DB if players exist, otherwise spawns fresh.
  Then starts the Table's auto hand loop.
  """
  def start(player_count \\ 6) do
    # Resume any existing players from DB
    Sim.resume_from_db()

    # Check how many we have
    status = Sim.get_status()
    current = status.total_players
    to_spawn = max(0, player_count - current)

    if to_spawn > 0 do
      Sim.spawn_players(to_spawn)
    end

    # Start auto-play on the Table
    Table.start_auto()
    {:ok, "Binz Poker Room is live with #{player_count} players"}
  end

  @doc "Pause the Table's auto hand loop. Players and Sim remain active."
  def stop do
    Table.stop_auto()
    {:ok, "Table paused — players still alive"}
  end

  @doc "Resume the Table's auto hand loop."
  def resume do
    Table.start_auto()
    {:ok, "Table resumed"}
  end

  @doc "Get current room status: sim state + table state."
  def status do
    %{
      sim: Sim.get_status(),
      table: Table.get_state()
    }
  end
end
```

**Step 2: Verify it works in IEx**

```bash
iex -S mix phx.server
```

Then in IEx:

```elixir
BinzPoker.Room.start()
BinzPoker.Room.status()
BinzPoker.Room.stop()
BinzPoker.Room.resume()
```

**Step 3: Commit**

```bash
git add lib/binz_poker/room.ex
git commit -m "feat: add Room module for convenient start/stop/resume/status"
```
