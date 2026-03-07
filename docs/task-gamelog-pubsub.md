### GameLog PubSub Implementation

**Files:**

- Create: `lib/binz_poker/game_log/pub_sub_logger.ex`
- Create: `test/binz_poker/game_log/pub_sub_logger_test.exs`

**Step 1: Write failing test**

```elixir
# test/binz_poker/game_log/pub_sub_logger_test.exs
defmodule BinzPoker.GameLog.PubSubLoggerTest do
  use ExUnit.Case

  alias BinzPoker.GameLog.PubSubLogger

  test "log_event broadcasts via PubSub" do
    Phoenix.PubSub.subscribe(BinzPoker.PubSub, "game_log")
    PubSubLogger.log_event(:hand_dealt, %{hand_number: 1})
    assert_receive {:game_event, :hand_dealt, %{hand_number: 1}}, 1000
  end
end
```

**Step 2: Run test to verify it fails**

```bash
mix test test/binz_poker/game_log/pub_sub_logger_test.exs
```

**Step 3: Implement**

```elixir
# lib/binz_poker/game_log/pub_sub_logger.ex
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
```

**Step 4: Run test**

```bash
mix test test/binz_poker/game_log/pub_sub_logger_test.exs
```

Expected: PASS

**Step 5: Commit**

```bash
git add lib/binz_poker/game_log/pub_sub_logger.ex test/binz_poker/game_log/pub_sub_logger_test.exs
git commit -m "feat: add PubSub game logger"
```


