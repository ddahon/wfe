defmodule Wfe.Jobs.RemoteFilter do
  @moduledoc """
  Heuristic remote-job detection on parsed job maps.

  Used as a fallback when the ATS doesn't provide a structured remote flag.

  ## Extending

  Add a `{name, {mod, fun, extra_args}}` tuple to `@filters`. The function
  receives the job map as its first arg and must return a boolean
  (`true` = keep). All filters must pass.
  """

  require Logger

  @remote_patterns [
    ~r/\bremote\b/i,
    ~r/\banywhere\b/i,
    ~r/\bdistributed\b/i,
    ~r/\bwork from home\b/i,
    ~r/\bwfh\b/i,
    ~r/\bfully remote\b/i
  ]

  @onsite_patterns [
    ~r/\bon[- ]?site only\b/i,
    ~r/\bno remote\b/i,
    ~r/\bnot remote\b/i,
    ~r/\bin[- ]?office required\b/i,
    ~r/\bmust be located in\b/i
  ]

  # NOTE: `hybrid` is intentionally *not* rejected by default. Toggle it here
  # if your product wants strict fully-remote only.
  @reject_hybrid false
  @hybrid_patterns [~r/\bhybrid\b/i]

  @filters [
    {:location_looks_remote, {__MODULE__, :location_looks_remote?, []}},
    {:no_onsite_markers, {__MODULE__, :no_onsite_markers?, []}}
  ]

  @spec apply([map()]) :: [map()]
  def apply(jobs) when is_list(jobs) do
    Enum.reduce(@filters, jobs, fn {name, {m, f, a}}, acc ->
      {kept, dropped} = Enum.split_with(acc, &Kernel.apply(m, f, [&1 | a]))

      if dropped != [] do
        Logger.debug("[RemoteFilter] #{name} dropped #{length(dropped)}")
      end

      kept
    end)
  end

  # --- Filters --------------------------------------------------------------

  @doc false
  def location_looks_remote?(%{location: loc} = job) when is_binary(loc) and loc != "" do
    match_any?(loc, @remote_patterns) or description_looks_remote?(job)
  end

  def location_looks_remote?(job), do: description_looks_remote?(job)

  defp description_looks_remote?(%{description: desc}) when is_binary(desc) do
    match_any?(desc, @remote_patterns)
  end

  defp description_looks_remote?(_), do: false

  @doc false
  def no_onsite_markers?(job) do
    text = haystack(job)
    patterns = if @reject_hybrid, do: @onsite_patterns ++ @hybrid_patterns, else: @onsite_patterns
    not match_any?(text, patterns)
  end

  # --- Helpers --------------------------------------------------------------

  defp match_any?(text, patterns), do: Enum.any?(patterns, &Regex.match?(&1, text))

  defp haystack(job) do
    [job[:title], job[:location], job[:description]]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
  end
end
