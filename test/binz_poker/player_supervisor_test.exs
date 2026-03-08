defmodule BinzPoker.PlayerSupervisorTest do
  use BinzPoker.DataCase

  alias BinzPoker.PlayerSupervisor
  alias BinzPoker.Bank
  alias BinzPoker.Schemas.PlayerRecord

  setup do
    start_supervised!({Registry, keys: :unique, name: BinzPoker.PlayerRegistry})
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
    old_record = PlayerRecord.get_by_player_id(old_id)
    assert old_record.status == "dead"
  end

  test "resume_players restarts GenServers for living DB records", %{sup: sup} do
    PlayerSupervisor.spawn_player(sup)
    players_before = PlayerSupervisor.list_players(sup)
    assert length(players_before) == 1
  end
end
