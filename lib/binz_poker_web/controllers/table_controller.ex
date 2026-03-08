defmodule BinzPokerWeb.TableController do
  use BinzPokerWeb, :controller

  alias BinzPoker.{Table, Sim}
  alias BinzPoker.Schemas.{PlayerRecord, LeaderboardEntry, HandHistory, SimRecord}

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
    json(conn, %{
      hands_played: status.hands_played,
      total_players: status.total_players,
      seated: Enum.map(status.seated, fn p ->
        record = PlayerRecord.get_by_player_id(p.id)
        %{id: p.id, name: record && record.name, chips: record && record.chips, budget: record && record.budget}
      end),
      away: Enum.map(status.away, fn p ->
        record = PlayerRecord.get_by_player_id(p.id)
        %{id: p.id, name: record && record.name, chips: record && record.chips, budget: record && record.budget}
      end)
    })
  end

  def hand_history(conn, params) do
    sim_id = case SimRecord.get_current() do
      nil -> 0
      sim -> sim.id
    end
    limit = Map.get(params, "limit", "20") |> String.to_integer()
    hands = HandHistory.recent(sim_id, limit)
    json(conn, %{hands: Enum.map(hands, &hand_summary/1)})
  end

  def hand_detail(conn, %{"hand_number" => hand_number_str}) do
    sim_id = case SimRecord.get_current() do
      nil -> 0
      sim -> sim.id
    end
    hand_number = String.to_integer(hand_number_str)
    case HandHistory.get_by_hand(sim_id, hand_number) do
      nil -> conn |> put_status(404) |> json(%{error: "not_found"})
      hand -> json(conn, hand_to_json(hand))
    end
  end

  defp hand_summary(hand) do
    %{
      hand_number: hand.hand_number,
      method: hand.method,
      winners: hand.winners,
      player_count: map_size(hand.players || %{}),
      inserted_at: hand.inserted_at
    }
  end

  defp hand_to_json(hand) do
    %{
      hand_number: hand.hand_number,
      sim_id: hand.sim_id,
      table_id: hand.table_id,
      players: hand.players,
      hole_cards: hand.hole_cards,
      community_cards: hand.community_cards,
      actions: hand.actions,
      pots: hand.pots,
      winners: hand.winners,
      showdown_hands: hand.showdown_hands,
      method: hand.method,
      blinds: hand.blinds,
      played_at: hand.inserted_at
    }
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
