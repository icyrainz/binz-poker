### LiteLLM Client

**Files:**

- Create: `lib/binz_poker/llm/lite_llm.ex`
- Create: `test/binz_poker/llm/lite_llm_test.exs`

**Step 1: Write test (integration test, tagged)**

```elixir
# test/binz_poker/llm/lite_llm_test.exs
defmodule BinzPoker.LLM.LiteLLMTest do
  use ExUnit.Case

  alias BinzPoker.LLM.LiteLLM

  @moduletag :integration

  test "chat returns a response with usage" do
    {:ok, result} = LiteLLM.chat("gpt-4o", [
      %{role: "user", content: "Say hello in one word."}
    ])

    assert is_binary(result.content)
    assert result.usage.input > 0
    assert result.usage.output > 0
  end
end
```

**Step 2: Implement LiteLLM client**

```elixir
# lib/binz_poker/llm/lite_llm.ex
defmodule BinzPoker.LLM.LiteLLM do
  @behaviour BinzPoker.LLM

  @impl true
  def chat(model, messages, opts \\ []) do
    url = Application.get_env(:binz_poker, :litellm_url, "http://litellm.lan/v1")
    key = Application.get_env(:binz_poker, :litellm_key, "")
    max_tokens = Keyword.get(opts, :max_tokens, 500)

    body = Jason.encode!(%{
      model: model,
      messages: messages,
      max_tokens: max_tokens,
      response_format: %{type: "json_object"}
    })

    headers = [
      {"content-type", "application/json"},
      {"authorization", "Bearer #{key}"}
    ]

    request = Finch.build(:post, "#{url}/chat/completions", headers, body)

    case Finch.request(request, BinzPoker.Finch, receive_timeout: 30_000) do
      {:ok, %Finch.Response{status: 200, body: response_body}} ->
        parsed = Jason.decode!(response_body)
        choice = hd(parsed["choices"])
        usage = parsed["usage"]

        {:ok, %{
          content: choice["message"]["content"],
          usage: %{
            input: usage["prompt_tokens"],
            output: usage["completion_tokens"]
          }
        }}

      {:ok, %Finch.Response{status: status, body: body}} ->
        {:error, %{status: status, body: body}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
```

**Step 3: Add Finch to supervision tree**

Edit `lib/binz_poker/application.ex` to add `{Finch, name: BinzPoker.Finch}` to the children list.

**Step 4: Run integration test (requires LiteLLM access)**

```bash
mix test test/binz_poker/llm/lite_llm_test.exs --include integration
```

**Step 5: Commit**

```bash
git add lib/binz_poker/llm/lite_llm.ex test/binz_poker/llm/lite_llm_test.exs lib/binz_poker/application.ex
git commit -m "feat: add LiteLLM client with Finch HTTP"
```


