defmodule BinzPoker.GameLog.Logger do
  @behaviour BinzPoker.GameLog
  require Logger

  @impl true
  def log_event(event_type, payload) do
    Logger.info("[BinzPoker] #{event_type}: #{inspect(payload)}")
    :ok
  end
end
