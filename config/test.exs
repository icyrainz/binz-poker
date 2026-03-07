import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :binz_poker, BinzPoker.Repo,
  database: Path.expand("../binz_poker_test.db", __DIR__),
  pool_size: 5,
  pool: Ecto.Adapters.SQL.Sandbox

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :binz_poker, BinzPokerWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "7u88ifeSmWbkv2g3jIS9h9hWAUlWQZQxdJrs2LRHeEZfH8Jq/wuAUdUKWolOlnRB",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Binz Poker test overrides
config :binz_poker,
  hand_delay_ms: 0,
  auto_banker: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
