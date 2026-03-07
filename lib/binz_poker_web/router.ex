defmodule BinzPokerWeb.Router do
  use BinzPokerWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api", BinzPokerWeb do
    pipe_through :api
  end
end
