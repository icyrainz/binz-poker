defmodule BinzPoker.GameLog.PubSubLoggerTest do
  use ExUnit.Case

  alias BinzPoker.GameLog.PubSubLogger

  test "log_event broadcasts via PubSub" do
    Phoenix.PubSub.subscribe(BinzPoker.PubSub, "game_log")
    PubSubLogger.log_event(:hand_dealt, %{hand_number: 1})
    assert_receive {:game_event, :hand_dealt, %{hand_number: 1}}, 1000
  end
end
