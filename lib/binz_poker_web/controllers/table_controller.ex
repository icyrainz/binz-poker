defmodule BinzPokerWeb.TableController do
  use BinzPokerWeb, :controller

  alias BinzPoker.{Table, Sim}
  alias BinzPoker.Schemas.{PlayerRecord, LeaderboardEntry}

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
    json(conn, status)
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
