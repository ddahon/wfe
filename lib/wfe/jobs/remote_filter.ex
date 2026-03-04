defmodule Wfe.Jobs.RemoteFilter do
  @moduledoc """
  Heuristic remote-job detection based on title, location, and description text.
  """

  def apply(jobs) do
    Enum.filter(jobs, &remote?/1)
  end

  @doc """
  Like `apply/1` but returns `{passed, rejected}` so callers can audit both.
  """
  def apply_with_rejects(jobs) do
    {passed, rejected} = Enum.split_with(jobs, &remote?/1)
    {passed, rejected}
  end

  defp remote?(job) do
    text =
      [job[:title], job[:location], job[:description]]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(" ")
      |> String.downcase()

    String.contains?(text, "remote")
  end
end
