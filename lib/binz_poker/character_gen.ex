defmodule BinzPoker.CharacterGen do
  @callback generate(opts :: keyword()) :: {:ok, %BinzPoker.Character{}}

  def impl, do: Application.get_env(:binz_poker, :character_gen, BinzPoker.CharacterGen.LLMBased)
  def generate(opts \\ []), do: impl().generate(opts)
end
