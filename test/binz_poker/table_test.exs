defmodule BinzPoker.TableTest.CallOnlyEngine do
  @moduledoc false
  @behaviour BinzPoker.DecisionEngine

  @impl true
  def decide(_game_state, _character) do
    {:ok, %{action: :call, amount: 0, reasoning: "Always call.", talk: ""}}
  end

  @impl true
  def buy_in(_budget, _character), do: {:ok, 500}
end

defmodule BinzPoker.TableTest do
  use BinzPoker.DataCase

  alias BinzPoker.Table
  alias BinzPoker.Player
  alias BinzPoker.Schemas.PlayerRecord

  defp spawn_test_player(id, chips \\ 500) do
    {:ok, _} = PlayerRecord.create(%{
      player_id: id, name: "Player #{id}", traits: %{}, model: "mock-model",
      status: "seated", chips: chips, budget: 5.00
    })
    start_supervised!({Player, [
      id: id,
      decision_engine: BinzPoker.TableTest.CallOnlyEngine
    ]}, id: String.to_atom(id))
  end

  setup do
    start_supervised!({Registry, keys: :unique, name: BinzPoker.PlayerRegistry})

    pids = for i <- 1..3 do
      pid = spawn_test_player("p#{i}")
      {"p#{i}", pid}
    end

    table = start_supervised!({Table,
      hand_evaluator: BinzPoker.HandEvaluator.Native,
      auto_start: false
    })

    for {id, pid} <- pids do
      Table.request_seat(table, id, pid)
    end

    %{table: table, pids: pids}
  end

  test "play_hand completes without crashing", %{table: table} do
    assert {:ok, result} = Table.play_hand(table)
    assert is_map(result)
    assert Map.has_key?(result, :winners)
    assert Map.has_key?(result, :pots)
  end

  test "hand increments hand counter", %{table: table} do
    assert Table.get_hand_number(table) == 0
    Table.play_hand(table)
    assert Table.get_hand_number(table) == 1
  end

  test "request_seat and leave_seat manage seats", %{table: table} do
    state = Table.get_state(table)
    assert length(state.seats) == 3

    Table.leave_seat(table, "p1")
    state = Table.get_state(table)
    assert length(state.seats) == 2
  end

  test "can play 10 hands without crashing", %{table: table} do
    for _ <- 1..10 do
      assert {:ok, _result} = Table.play_hand(table)
    end
  end
end
