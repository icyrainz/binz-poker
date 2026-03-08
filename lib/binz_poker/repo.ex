defmodule BinzPoker.Repo do
  use Ecto.Repo,
    otp_app: :binz_poker,
    adapter: Ecto.Adapters.SQLite3
end
