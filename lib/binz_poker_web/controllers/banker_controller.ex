defmodule BinzPokerWeb.BankerController do
  use BinzPokerWeb, :controller

  alias BinzPoker.{Table, Bank, Sim, PlayerSupervisor}
  alias BinzPoker.Schemas.LoanRecord

  def set_auto(conn, _params) do
    Sim.set_banker_mode(BinzPoker.Sim, :auto)
    json(conn, %{mode: "auto", status: "ok"})
  end

  def set_manual(conn, _params) do
    Sim.set_banker_mode(BinzPoker.Sim, :manual)
    json(conn, %{mode: "manual", status: "ok"})
  end

  def pending_loans(conn, _params) do
    loans = LoanRecord.get_pending()
    json(conn, %{loans: Enum.map(loans, fn l ->
      %{id: l.id, player_id: l.player_id, amount: l.requested_amount,
        message: l.message, requested_at: l.inserted_at}
    end)})
  end

  def approve_loan(conn, %{"id" => id}) do
    loan_id = String.to_integer(id)
    amount = Map.get(conn.body_params, "amount", 2.00)
    case Bank.approve_loan(BinzPoker.Bank, loan_id, amount) do
      :ok -> json(conn, %{status: "approved"})
      {:error, reason} -> conn |> put_status(400) |> json(%{error: to_string(reason)})
    end
  end

  def deny_loan(conn, %{"id" => id}) do
    loan_id = String.to_integer(id)
    case Bank.deny_loan(BinzPoker.Bank, loan_id) do
      :ok -> json(conn, %{status: "denied"})
      {:error, reason} -> conn |> put_status(400) |> json(%{error: to_string(reason)})
    end
  end

  def pause_table(conn, _params) do
    Table.stop_auto()
    json(conn, %{status: "paused"})
  end

  def resume_table(conn, _params) do
    Table.start_auto()
    json(conn, %{status: "resumed"})
  end

  def kick(conn, %{"player_id" => player_id}) do
    case PlayerSupervisor.eliminate_and_respawn(BinzPoker.PlayerSupervisor, player_id) do
      {:ok, _} -> json(conn, %{status: "kicked", player_id: player_id})
      {:error, reason} -> conn |> put_status(400) |> json(%{error: to_string(reason)})
    end
  end
end
