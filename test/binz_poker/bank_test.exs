defmodule BinzPoker.BankTest do
  use BinzPoker.DataCase

  alias BinzPoker.Bank
  alias BinzPoker.Schemas.PlayerRecord

  setup do
    {:ok, _} = PlayerRecord.create(%{
      player_id: "p1", name: "Rico", traits: %{}, model: "mock-model",
      budget: 5.00, chips: 0, status: "away"
    })
    bank = start_supervised!({Bank, name: :"bank_#{System.unique_integer()}"})
    %{bank: bank}
  end

  test "loads player budgets from DB on init", %{bank: bank} do
    assert {:ok, 5.00} = Bank.get_budget(bank, "p1")
  end

  test "record_token_cost accumulates bill in memory and DB", %{bank: bank} do
    Bank.record_token_cost(bank, "p1", %{input: 500, output: 100}, "gpt-4o")
    :timer.sleep(10)
    assert {:ok, bill} = Bank.get_token_bill(bank, "p1")
    assert bill > 0
    record = PlayerRecord.get_by_player_id("p1")
    assert record.token_bill > 0
  end

  test "settle_hand deducts bill from budget and resets bill", %{bank: bank} do
    Bank.record_token_cost(bank, "p1", %{input: 1000, output: 500}, "gpt-4o")
    :timer.sleep(10)
    {:ok, results} = Bank.settle_hand(bank)
    assert results["p1"].budget < 5.00
    assert results["p1"].token_bill == 0.0
    record = PlayerRecord.get_by_player_id("p1")
    assert record.budget < 5.00
    assert record.token_bill == 0.0
  end

  test "buy_in converts budget to chips", %{bank: bank} do
    :ok = Bank.buy_in(bank, "p1", 300)
    assert {:ok, 2.00} = Bank.get_budget(bank, "p1")
    record = PlayerRecord.get_by_player_id("p1")
    assert record.budget == 2.00
    assert record.chips == 300
  end

  test "cash_out converts chips to budget", %{bank: bank} do
    Bank.buy_in(bank, "p1", 300)
    :ok = Bank.cash_out(bank, "p1", 300)
    assert {:ok, 5.00} = Bank.get_budget(bank, "p1")
    record = PlayerRecord.get_by_player_id("p1")
    assert record.budget == 5.00
    assert record.chips == 0
  end

  test "request_loan creates a LoanRecord", %{bank: bank} do
    {:ok, loan_id} = Bank.request_loan(bank, "p1", 2.00, "I need chips")
    assert is_integer(loan_id)
  end

  test "approve_loan adds to budget and persists", %{bank: bank} do
    {:ok, loan_id} = Bank.request_loan(bank, "p1", 2.00, "I need chips")
    :ok = Bank.approve_loan(bank, loan_id, 2.00)
    assert {:ok, 7.00} = Bank.get_budget(bank, "p1")
    record = PlayerRecord.get_by_player_id("p1")
    assert record.budget == 7.00
  end

  test "check_budget_broke returns players with budget <= 0", %{bank: bank} do
    Bank.record_token_cost(bank, "p1", %{input: 100_000, output: 50_000}, "claude-opus-4-6")
    :timer.sleep(10)
    Bank.settle_hand(bank)
    {:ok, broke} = Bank.check_budget_broke(bank)
    assert "p1" in broke
  end
end
