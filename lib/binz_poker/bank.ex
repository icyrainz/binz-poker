defmodule BinzPoker.Bank do
  use GenServer

  alias BinzPoker.Schemas.{PlayerRecord, LoanRecord}

  @default_pricing %{
    "gpt-4o" => %{input: 0.0025, output: 0.01},
    "claude-opus-4-6" => %{input: 0.015, output: 0.075},
    "claude-sonnet-4-6" => %{input: 0.003, output: 0.015},
    "claude-haiku-4-5" => %{input: 0.0008, output: 0.004},
    "mock-model" => %{input: 0.001, output: 0.002}
  }

  @default_fallback_pricing %{input: 0.001, output: 0.002}

  defstruct ledger: %{}, pricing: @default_pricing

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def register_player(bank \\ __MODULE__, player_id, budget) do
    GenServer.call(bank, {:register_player, player_id, budget})
  end

  def get_budget(bank \\ __MODULE__, player_id) do
    GenServer.call(bank, {:get_budget, player_id})
  end

  def get_token_bill(bank \\ __MODULE__, player_id) do
    GenServer.call(bank, {:get_token_bill, player_id})
  end

  def record_token_cost(bank \\ __MODULE__, player_id, usage, model) do
    GenServer.cast(bank, {:record_token_cost, player_id, usage, model})
  end

  def settle_hand(bank \\ __MODULE__) do
    GenServer.call(bank, :settle_hand)
  end

  def buy_in(bank \\ __MODULE__, player_id, chips) do
    GenServer.call(bank, {:buy_in, player_id, chips})
  end

  def cash_out(bank \\ __MODULE__, player_id, chips) do
    GenServer.call(bank, {:cash_out, player_id, chips})
  end

  def request_loan(bank \\ __MODULE__, player_id, amount, message) do
    GenServer.call(bank, {:request_loan, player_id, amount, message})
  end

  def approve_loan(bank \\ __MODULE__, loan_id, amount) do
    GenServer.call(bank, {:approve_loan, loan_id, amount})
  end

  def deny_loan(bank \\ __MODULE__, loan_id) do
    GenServer.call(bank, {:deny_loan, loan_id})
  end

  def check_budget_broke(bank \\ __MODULE__) do
    GenServer.call(bank, :check_budget_broke)
  end

  def unregister_player(bank \\ __MODULE__, player_id) do
    GenServer.call(bank, {:unregister_player, player_id})
  end

  @impl true
  def init(opts) do
    pricing = Keyword.get(opts, :pricing, @default_pricing)

    ledger =
      PlayerRecord.get_living_players()
      |> Map.new(fn record ->
        {record.player_id, %{
          budget: record.budget,
          token_bill: record.token_bill,
          total_token_cost: record.total_token_cost,
          peak_budget: record.peak_budget
        }}
      end)

    {:ok, %__MODULE__{ledger: ledger, pricing: pricing}}
  end

  @impl true
  def handle_call({:register_player, player_id, budget}, _from, state) do
    entry = %{budget: budget, token_bill: 0.0, total_token_cost: 0.0, peak_budget: budget}
    ledger = Map.put(state.ledger, player_id, entry)
    {:reply, :ok, %{state | ledger: ledger}}
  end

  def handle_call({:get_budget, player_id}, _from, state) do
    case Map.get(state.ledger, player_id) do
      nil -> {:reply, {:error, :not_found}, state}
      entry -> {:reply, {:ok, entry.budget}, state}
    end
  end

  def handle_call({:get_token_bill, player_id}, _from, state) do
    case Map.get(state.ledger, player_id) do
      nil -> {:reply, {:error, :not_found}, state}
      entry -> {:reply, {:ok, entry.token_bill}, state}
    end
  end

  def handle_call(:settle_hand, _from, state) do
    {results, new_ledger} =
      Enum.reduce(state.ledger, {%{}, %{}}, fn {id, entry}, {res, ledger} ->
        new_budget = entry.budget - entry.token_bill
        new_peak = max(entry.peak_budget, new_budget)
        settled = %{entry | budget: new_budget, token_bill: 0.0, peak_budget: new_peak}

        PlayerRecord.update_fields(id, %{
          budget: new_budget,
          token_bill: 0.0,
          peak_budget: new_peak
        })

        {Map.put(res, id, settled), Map.put(ledger, id, settled)}
      end)

    {:reply, {:ok, results}, %{state | ledger: new_ledger}}
  end

  def handle_call({:buy_in, player_id, chips}, _from, state) do
    case Map.get(state.ledger, player_id) do
      nil ->
        {:reply, {:error, :not_found}, state}
      entry ->
        cost = chips * 0.01
        if cost > entry.budget do
          {:reply, {:error, :insufficient_budget}, state}
        else
          new_budget = entry.budget - cost
          updated = %{entry | budget: new_budget}
          PlayerRecord.update_fields(player_id, %{budget: new_budget, chips: chips})
          {:reply, :ok, %{state | ledger: Map.put(state.ledger, player_id, updated)}}
        end
    end
  end

  def handle_call({:cash_out, player_id, chips}, _from, state) do
    case Map.get(state.ledger, player_id) do
      nil ->
        {:reply, {:error, :not_found}, state}
      entry ->
        credit = chips * 0.01
        new_budget = entry.budget + credit
        new_peak = max(entry.peak_budget, new_budget)
        updated = %{entry | budget: new_budget, peak_budget: new_peak}
        PlayerRecord.update_fields(player_id, %{budget: new_budget, chips: 0, peak_budget: new_peak})
        {:reply, :ok, %{state | ledger: Map.put(state.ledger, player_id, updated)}}
    end
  end

  def handle_call({:request_loan, player_id, amount, message}, _from, state) do
    {:ok, loan} = LoanRecord.create(%{
      player_id: player_id,
      requested_amount: amount,
      message: message,
      status: "pending"
    })

    Phoenix.PubSub.broadcast(BinzPoker.PubSub, "bank:events",
      {:loan_requested, loan.id, player_id, amount, message})

    {:reply, {:ok, loan.id}, state}
  end

  def handle_call({:approve_loan, loan_id, amount}, _from, state) do
    case LoanRecord.approve(loan_id, amount, 0.0) do
      {:ok, loan} ->
        player_id = loan.player_id
        entry = Map.get(state.ledger, player_id)
        new_budget = entry.budget + amount
        new_peak = max(entry.peak_budget, new_budget)
        updated = %{entry | budget: new_budget, peak_budget: new_peak}

        PlayerRecord.update_fields(player_id, %{budget: new_budget, peak_budget: new_peak})
        new_state = %{state | ledger: Map.put(state.ledger, player_id, updated)}

        Phoenix.PubSub.broadcast(BinzPoker.PubSub, "bank:events",
          {:loan_decided, loan_id, player_id, :approved, amount})

        {:reply, :ok, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:deny_loan, loan_id}, _from, state) do
    case LoanRecord.deny(loan_id) do
      {:ok, loan} ->
        Phoenix.PubSub.broadcast(BinzPoker.PubSub, "bank:events",
          {:loan_decided, loan_id, loan.player_id, :denied, 0})
        {:reply, :ok, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:check_budget_broke, _from, state) do
    broke =
      state.ledger
      |> Enum.filter(fn {_id, entry} -> entry.budget <= 0 end)
      |> Enum.map(fn {id, _} -> id end)

    {:reply, {:ok, broke}, state}
  end

  def handle_call({:unregister_player, player_id}, _from, state) do
    {:reply, :ok, %{state | ledger: Map.delete(state.ledger, player_id)}}
  end

  @impl true
  def handle_cast({:record_token_cost, player_id, usage, model}, state) do
    case Map.get(state.ledger, player_id) do
      nil ->
        {:noreply, state}
      entry ->
        pricing = Map.get(state.pricing, model, @default_fallback_pricing)
        cost = (usage.input / 1000 * pricing.input) + (usage.output / 1000 * pricing.output)
        updated = %{entry |
          token_bill: entry.token_bill + cost,
          total_token_cost: entry.total_token_cost + cost
        }

        PlayerRecord.update_fields(player_id, %{
          token_bill: updated.token_bill,
          total_token_cost: updated.total_token_cost
        })

        {:noreply, %{state | ledger: Map.put(state.ledger, player_id, updated)}}
    end
  end
end
