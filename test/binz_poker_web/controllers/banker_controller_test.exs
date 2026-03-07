defmodule BinzPokerWeb.BankerControllerTest do
  use BinzPokerWeb.ConnCase

  test "GET /api/banker/loans/pending returns pending loans", %{conn: conn} do
    conn = get(conn, "/api/banker/loans/pending")
    assert %{"loans" => _} = json_response(conn, 200)
  end
end
