defmodule BinzPoker.PlayerTest do
  use BinzPoker.DataCase

  alias BinzPoker.Player
  alias BinzPoker.Schemas.PlayerRecord

  setup do
    start_supervised!({Registry, keys: :unique, name: BinzPoker.PlayerRegistry})

    {:ok, _record} = PlayerRecord.create(%{
      player_id: "p1",
      name: "Test Player",
      backstory: "Just testing.",
      traits: %{aggression: "medium", sociability: "low", discipline: "high",
                risk_tolerance: "medium", greed: "low", pride: "medium",
                desperation: "low", deceptiveness: "low"},
      model: "mock-model",
      status: "seated",
      chips: 300,
      budget: 2.00
    })

    player = start_supervised!({Player,
      id: "p1",
      decision_engine: BinzPoker.DecisionEngine.Random
    })
    %{player: player}
  end

  test "loads state from DB on init", %{player: player} do
    assert Player.get_chips(player) == 300
    assert Player.get_status(player) == :seated
    char = Player.get_character(player)
    assert char.name == "Test Player"
  end

  test "update_chips modifies and persists", %{player: player} do
    Player.update_chips(player, -50)
    assert Player.get_chips(player) == 250
    record = PlayerRecord.get_by_player_id("p1")
    assert record.chips == 250
  end

  test "set_chips sets exact value and persists", %{player: player} do
    Player.set_chips(player, 400)
    assert Player.get_chips(player) == 400
    record = PlayerRecord.get_by_player_id("p1")
    assert record.chips == 400
  end

  test "set_status changes state and persists", %{player: player} do
    Player.set_status(player, :away)
    assert Player.get_status(player) == :away
    record = PlayerRecord.get_by_player_id("p1")
    assert record.status == "away"
  end

  test "request_decision returns a valid action", %{player: player} do
    game_state = %{
      hole_cards: [],
      community_cards: [],
      pot: 30,
      current_bet: 10,
      min_raise: 20,
      player_chips: 300
    }
    {:ok, decision} = Player.request_decision(player, game_state)
    assert decision.action in [:fold, :call, :raise, :all_in]
  end

  test "request_buy_in returns a chip amount", %{player: player} do
    {:ok, amount} = Player.request_buy_in(player, 5.00)
    assert is_integer(amount)
    assert amount > 0
    assert amount <= 500
  end

  test "add_observation stores event as map", %{player: player} do
    Player.add_observation(player, %{type: "hand_result", data: %{winner: "p2"}, at: DateTime.utc_now()})
    observations = Player.get_observations(player)
    assert length(observations) == 1
    assert hd(observations).type == "hand_result"
  end
end
