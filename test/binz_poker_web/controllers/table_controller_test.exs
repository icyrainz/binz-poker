defmodule BinzPokerWeb.TableControllerTest do
  use BinzPokerWeb.ConnCase

  test "GET /api/leaderboard returns leaderboard", %{conn: conn} do
    conn = get(conn, "/api/leaderboard")
    assert %{"leaderboard" => _} = json_response(conn, 200)
  end
end
