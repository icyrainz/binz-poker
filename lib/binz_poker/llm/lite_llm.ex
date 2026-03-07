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
