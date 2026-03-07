# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :binz_poker,
  ecto_repos: [BinzPoker.Repo],
  generators: [timestamp_type: :utc_datetime],
  max_players: 10,
  table_size: 6,
  starting_budget: 5.00,
  small_blind: 1,
  big_blind: 2,
  hand_delay_ms: 5000,
  auto_banker: true,
  litellm_url: "http://litellm.lan/v1",
  litellm_key: "sk-litellm-master-changeme"

# Configure the endpoint
config :binz_poker, BinzPokerWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: BinzPokerWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: BinzPoker.PubSub,
  live_view: [signing_salt: "tJya1JdM"]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
