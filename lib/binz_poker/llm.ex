defmodule BinzPoker.LLM do
  @callback chat(model :: String.t(), messages :: list(), opts :: keyword()) ::
    {:ok, %{content: String.t(), usage: %{input: integer(), output: integer()}}}
    | {:error, term()}

  def impl, do: Application.get_env(:binz_poker, :llm_provider, BinzPoker.LLM.LiteLLM)
  def chat(model, messages, opts \\ []), do: impl().chat(model, messages, opts)
end
