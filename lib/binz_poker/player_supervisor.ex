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
    pid = case Registry.lookup(BinzPoker.PlayerRegistry, player_id) do
      [{pid, _}] -> pid
      [] -> nil
    end
    {:reply, pid, state}
  end

  def handle_call({:eliminate_and_respawn, player_id}, _from, state) do
    case Map.get(state.players, player_id) do
      nil ->
        {:reply, {:error, :not_found}, state}
      pid ->
        PlayerRecord.mark_dead(player_id)
        DynamicSupervisor.terminate_child(state.supervisor_pid, pid)
        Bank.unregister_player(state.bank, player_id)
        cleaned = %{state | players: Map.delete(state.players, player_id)}
        {new_pid, new_state} = do_spawn(cleaned)
        {:reply, {:ok, new_pid}, new_state}
    end
  end

  def handle_call(:resume_players, _from, state) do
    living = PlayerRecord.get_living_players()
    new_state = Enum.reduce(living, state, fn record, acc ->
      if Map.has_key?(acc.players, record.player_id) do
        acc
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

    {:ok, _record} = PlayerRecord.create(%{
      player_id: id,
      name: character.name,
      backstory: character.backstory,
      traits: character.traits,
      model: character.model,
      status: "away",
      chips: 0,
      budget: budget
    })

    Bank.register_player(state.bank, id, budget)

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
