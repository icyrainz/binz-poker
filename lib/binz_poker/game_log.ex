defmodule BinzPoker.GameLog do
  @callback log_event(event_type :: atom(), payload :: map()) :: :ok

  def impl, do: Application.get_env(:binz_poker, :game_log, BinzPoker.GameLog.PubSubLogger)
  def log_event(event_type, payload), do: impl().log_event(event_type, payload)
end
