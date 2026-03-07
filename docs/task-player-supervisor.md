### Player Supervisor with Permadeath/Respawn

Manages Player GenServer lifecycle. On spawn, creates a `PlayerRecord` in DB first, then starts the GenServer (which loads from DB). On elimination, marks the DB record as dead, terminates the GenServer, and spawns a replacement.

**Depends on:** Task 7 (Ecto Schemas), Task 8 (Bank), Task 9 (Player)

**Files:**
- Create: `lib/binz_poker/player_supervisor.ex`
- Create: `test/binz_poker/player_supervisor_test.exs`

**Step 1: Write failing tests**

```elixir
# test/binz_poker/player_supervisor_test.exs
defmodule BinzPoker.PlayerSupervisorTest do
  use BinzPoker.DataCase

  alias BinzPoker.PlayerSupervisor
  alias BinzPoker.Bank
  alias BinzPoker.Schemas.PlayerRecord

  setup do
    bank = start_supervised!({Bank, name: :"bank_#{System.unique_integer()}"})
    sup = start_supervised!({PlayerSupervisor,
      bank: bank,
      character_gen: BinzPoker.CharacterGen.Hardcoded,
      decision_engine: BinzPoker.DecisionEngine.Random
    })
    %{sup: sup, bank: bank}
  end

  test "spawn_player creates DB record and starts GenServer", %{sup: sup} do
    {:ok, pid} = PlayerSupervisor.spawn_player(sup)
    assert Process.alive?(pid)
    # Verify DB record exists
    [%{id: id}] = PlayerSupervisor.list_players(sup)
    assert PlayerRecord.get_by_player_id(id) != nil
  end

  test "list_players returns all active players", %{sup: sup} do
    PlayerSupervisor.spawn_player(sup)
    PlayerSupervisor.spawn_player(sup)
    assert length(PlayerSupervisor.list_players(sup)) == 2
  end

  test "eliminate_and_respawn kills old, marks dead in DB, spawns new", %{sup: sup} do
    {:ok, _pid} = PlayerSupervisor.spawn_player(sup)
    [%{id: old_id, pid: old_pid}] = PlayerSupervisor.list_players(sup)
    {:ok, new_pid} = PlayerSupervisor.eliminate_and_respawn(sup, old_id)
    refute Process.alive?(old_pid)
    assert Process.alive?(new_pid)
    # Old player marked dead in DB
    old_record = PlayerRecord.get_by_player_id(old_id)
    assert old_record.status == "dead"
  end

  test "resume_players restarts GenServers for living DB records", %{sup: sup} do
    PlayerSupervisor.spawn_player(sup)
    players_before = PlayerSupervisor.list_players(sup)
    assert length(players_before) == 1
    # resume_players is called on app startup to restore from DB
  end
end
```

**Step 2: Run test to verify it fails**

```bash
mix test test/binz_poker/player_supervisor_test.exs
```

**Step 3: Implement PlayerSupervisor**

Key change: `do_spawn` creates a `PlayerRecord` in DB first. Player GenServer loads from DB on init (no character passed as arg). `eliminate_and_respawn` marks old record as dead. `resume_players` restores GenServers from DB on app startup.

```elixir
# lib/binz_poker/player_supervisor.ex
defmodule BinzPoker.PlayerSupervisor do
  use GenServer

  alias BinzPoker.Player
  alias BinzPoker.Bank
  alias BinzPoker.Schemas.PlayerRecord

  defstruct [:supervisor_pid, :bank, :character_gen, :decision_engine, players: %{}, counter: 0]

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  def spawn_player(sup \\ __MODULE__, opts \\ []), do: GenServer.call(sup, {:spawn_player, opts})
  def list_players(sup \\ __MODULE__), do: GenServer.call(sup, :list_players)
  def eliminate_and_respawn(sup \\ __MODULE__, player_id), do: GenServer.call(sup, {:eliminate_and_respawn, player_id})
  def get_player_pid(sup \\ __MODULE__, player_id), do: GenServer.call(sup, {:get_player_pid, player_id})
  def resume_players(sup \\ __MODULE__), do: GenServer.call(sup, :resume_players)

  @impl true
  def init(opts) do
    {:ok, supervisor_pid} = DynamicSupervisor.start_link(strategy: :one_for_one)

    # Determine counter from existing DB records to avoid ID collisions
    existing = PlayerRecord.get_living_players()
    max_num = existing
      |> Enum.map(fn r ->
        case Regex.run(~r/player_(\d+)/, r.player_id) do
          [_, n] -> String.to_integer(n)
          _ -> 0
        end
      end)
      |> Enum.max(fn -> 0 end)

    state = %__MODULE__{
      supervisor_pid: supervisor_pid,
      bank: Keyword.fetch!(opts, :bank),
      character_gen: Keyword.get(opts, :character_gen, BinzPoker.CharacterGen.Hardcoded),
      decision_engine: Keyword.get(opts, :decision_engine, BinzPoker.DecisionEngine.Random),
      counter: max_num
    }
    {:ok, state}
  end

  @impl true
  def handle_call({:spawn_player, opts}, _from, state) do
    {pid, new_state} = do_spawn(state, opts)
    {:reply, {:ok, pid}, new_state}
  end

  def handle_call(:list_players, _from, state) do
    players = Enum.map(state.players, fn {id, pid} -> %{id: id, pid: pid} end)
    {:reply, players, state}
  end

  def handle_call({:get_player_pid, player_id}, _from, state) do
    {:reply, Map.get(state.players, player_id), state}
  end

  def handle_call({:eliminate_and_respawn, player_id}, _from, state) do
    case Map.get(state.players, player_id) do
      nil ->
        {:reply, {:error, :not_found}, state}
      pid ->
        # Mark dead in DB (don't delete — preserve for leaderboard)
        PlayerRecord.mark_dead(player_id)
        DynamicSupervisor.terminate_child(state.supervisor_pid, pid)
        Bank.unregister_player(state.bank, player_id)
        cleaned = %{state | players: Map.delete(state.players, player_id)}
        {new_pid, new_state} = do_spawn(cleaned)
        {:reply, {:ok, new_pid}, new_state}
    end
  end

  def handle_call(:resume_players, _from, state) do
    # Restart GenServers for all living players in DB
    living = PlayerRecord.get_living_players()
    new_state = Enum.reduce(living, state, fn record, acc ->
      if Map.has_key?(acc.players, record.player_id) do
        acc  # Already running
      else
        Bank.register_player(acc.bank, record.player_id, record.budget)
        {:ok, pid} = DynamicSupervisor.start_child(
          acc.supervisor_pid,
          {Player, id: record.player_id, decision_engine: acc.decision_engine}
        )
        %{acc | players: Map.put(acc.players, record.player_id, pid)}
      end
    end)
    {:reply, :ok, new_state}
  end

  defp do_spawn(state, opts \\ []) do
    id = "player_#{state.counter + 1}"
    taken_names = Keyword.get(opts, :taken_names, [])
    {:ok, character} = state.character_gen.generate(model: "mock-model", taken_names: taken_names)
    budget = Application.get_env(:binz_poker, :starting_budget, 5.00)

    # Create DB record FIRST
    {:ok, _record} = PlayerRecord.create(%{
      player_id: id,
      name: character.name,
      backstory: character.backstory,
      traits: character.traits,
      model: character.model,
      status: "away",
      chips: 0,  # starts with 0, buys in at table entry
      budget: budget
    })

    # Register in Bank
    Bank.register_player(state.bank, id, budget)

    # Start GenServer (loads from DB)
    {:ok, pid} = DynamicSupervisor.start_child(
      state.supervisor_pid,
      {Player, id: id, decision_engine: state.decision_engine}
    )

    new_state = %{state |
      players: Map.put(state.players, id, pid),
      counter: state.counter + 1
    }
    {pid, new_state}
  end
end
```

**Step 4: Run tests**

```bash
mix test test/binz_poker/player_supervisor_test.exs
```

Expected: all PASS

**Step 5: Commit**

```bash
git add lib/binz_poker/player_supervisor.ex test/binz_poker/player_supervisor_test.exs
git commit -m "feat: add PlayerSupervisor with DB-backed spawn, eliminate, and resume"
```
