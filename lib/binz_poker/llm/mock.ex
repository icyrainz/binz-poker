defmodule BinzPoker.LLM.Mock do
  @behaviour BinzPoker.LLM

  @impl true
  def chat(_model, _messages, _opts \\ []) do
    {:ok, %{
      content: ~s({"action": "call", "amount": 0, "inner_thought": "Mock thought.", "table_talk": ""}),
      usage: %{input: 100, output: 50}
    }}
  end
end
