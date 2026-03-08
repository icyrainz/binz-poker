defmodule BinzPokerWeb.Router do
  use BinzPokerWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api", BinzPokerWeb do
    pipe_through :api

    # Read-only state
    get "/table/state", TableController, :state
    get "/players", TableController, :players
    get "/players/:player_id", TableController, :player
    get "/leaderboard", TableController, :leaderboard
    get "/sim/status", TableController, :sim_status
    get "/hands", TableController, :hand_history
    get "/hands/:hand_number", TableController, :hand_detail

    # Banker controls
    post "/banker/mode/auto", BankerController, :set_auto
    post "/banker/mode/manual", BankerController, :set_manual
    get "/banker/loans/pending", BankerController, :pending_loans
    post "/banker/loan/:id/approve", BankerController, :approve_loan
    post "/banker/loan/:id/deny", BankerController, :deny_loan

    # Table controls
    post "/table/pause", BankerController, :pause_table
    post "/table/resume", BankerController, :resume_table

    # Player management
    post "/banker/kick/:player_id", BankerController, :kick
  end
end
