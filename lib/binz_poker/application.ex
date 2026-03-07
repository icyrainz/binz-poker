defmodule BinzPoker.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Infrastructure
      BinzPokerWeb.Telemetry,
      BinzPoker.Repo,
      {Ecto.Migrator,
       repos: Application.fetch_env!(:binz_poker, :ecto_repos), skip: skip_migrations?()},
      {DNSCluster, query: Application.get_env(:binz_poker, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: BinzPoker.PubSub},
      {Finch, name: BinzPoker.Finch}
    ] ++ game_children() ++ [
      # Web — last entry
      BinzPokerWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: BinzPoker.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    BinzPokerWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp game_children do
    if Application.get_env(:binz_poker, :start_game, false) do
      [
        {Registry, keys: :unique, name: BinzPoker.PlayerRegistry},
        {BinzPoker.Bank, name: BinzPoker.Bank},
        {BinzPoker.PlayerSupervisor,
          name: BinzPoker.PlayerSupervisor,
          bank: BinzPoker.Bank,
          character_gen: Application.get_env(:binz_poker, :character_gen, BinzPoker.CharacterGen.Hardcoded),
          decision_engine: Application.get_env(:binz_poker, :decision_engine, BinzPoker.DecisionEngine.Random)},
        {BinzPoker.Table,
          name: BinzPoker.Table,
          hand_evaluator: Application.get_env(:binz_poker, :hand_evaluator, BinzPoker.HandEvaluator.Native),
          auto_start: false},
        {BinzPoker.Sim,
          name: BinzPoker.Sim,
          bank: BinzPoker.Bank,
          player_supervisor: BinzPoker.PlayerSupervisor,
          table: BinzPoker.Table}
      ]
    else
      []
    end
  end

  defp skip_migrations?() do
    # By default, sqlite migrations are run when using a release
    System.get_env("RELEASE_NAME") == nil
  end
end
