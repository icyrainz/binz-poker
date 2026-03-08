defmodule BinzPoker.Room do
  alias BinzPoker.{Table, Sim}

  def start(player_count \\ 6) do
    Sim.resume_from_db()

    status = Sim.get_status()
    current = status.total_players
    to_spawn = max(0, player_count - current)

    if to_spawn > 0 do
      Sim.spawn_players(to_spawn)
    end

    Table.start_auto()
    {:ok, "Binz Poker Room is live with #{player_count} players"}
  end

  def stop do
    Table.stop_auto()
    {:ok, "Table paused — players still alive"}
  end

  def resume do
    Table.start_auto()
    {:ok, "Table resumed"}
  end

  def status do
    %{
      sim: Sim.get_status(),
      table: Table.get_state()
    }
  end
end
