defmodule BinzPoker.GameLog.PubSubLogger do
  @behaviour BinzPoker.GameLog
  require Logger

  @impl true
  def log_event(event_type, payload) do
    Logger.info("[BinzPoker] #{event_type}: #{inspect(payload)}")
    Phoenix.PubSub.broadcast(BinzPoker.PubSub, "game_log", {:game_event, event_type, payload})
    :ok
  end
end
