defmodule Wfe.Jobs.ContentHash do
  @moduledoc """
  Deterministic fingerprint for job content.
  Light normalization avoids false negatives from whitespace/casing noise.
  """

  @spec compute(String.t() | nil, String.t() | nil) :: String.t()
  def compute(title, description) do
    :crypto.hash(:sha256, [normalize(title), "\x00", normalize(description)])
    |> Base.encode16(case: :lower)
  end

  defp normalize(nil), do: ""

  defp normalize(str) when is_binary(str) do
    str
    |> String.downcase()
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
  end
end
