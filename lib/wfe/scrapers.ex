defmodule Wfe.Scrapers do
  @moduledoc """
  Dispatches to the correct ATS scraper and applies remote-only filtering.

  Filtering is two-tiered:
    1. ATS-provided hints (optional `remote_hint/1` callback on raw payload)
    2. Heuristic fallback on parsed fields (`Wfe.Jobs.RemoteFilter`)
  """

  alias Wfe.Jobs.RemoteFilter

  require Logger

  @scrapers %{
    "greenhouse" => Wfe.Scrapers.Greenhouse,
    "lever" => Wfe.Scrapers.Lever,
    "ashby" => Wfe.Scrapers.Ashby,
    "workable" => Wfe.Scrapers.Workable,
    "recruitee" => Wfe.Scrapers.Recruitee
  }

  def supported_ats, do: Map.keys(@scrapers)

  @doc """
  Fetch, filter for remote, and parse jobs for a company.
  Returns `{:ok, [normalized_job_map]}` or `{:error, reason}`.
  """
  def fetch_jobs(%{ats: ats} = company) do
    case Map.fetch(@scrapers, ats) do
      {:ok, mod} ->
        with {:ok, pairs} <- mod.fetch_jobs(company) do
          {:ok, filter_remote(mod, company, pairs)}
        end

      :error ->
        {:error, {:unsupported_ats, ats}}
    end
  end

  # --- Filtering ------------------------------------------------------------

  # Scrapers return `{raw, parsed}` tuples so we can consult raw ATS
  # fields for structured remote hints before resorting to text heuristics.
  defp filter_remote(mod, company, pairs) do
    # Bucket by hint result: true (keep), false (drop), nil (undecided).
    by_hint =
      Enum.group_by(pairs, fn {raw, _parsed} -> apply_hint(mod, raw) end)

    definite = parsed_for(by_hint, true)
    _dropped = parsed_for(by_hint, false)
    unknown = parsed_for(by_hint, nil)

    heuristic = RemoteFilter.apply(unknown)
    kept = definite ++ heuristic

    Logger.debug("""
    [Scrapers] #{company.name}: #{length(pairs)} fetched
      #{length(definite)} ATS-flagged remote
      #{length(parsed_for(by_hint, false))} ATS-flagged on-site
      #{length(heuristic)}/#{length(unknown)} passed heuristics
      #{length(kept)} kept
    """)

    kept
  end

  defp parsed_for(groups, key) do
    groups |> Map.get(key, []) |> Enum.map(&elem(&1, 1))
  end

  defp apply_hint(mod, raw) do
    if function_exported?(mod, :remote_hint, 1), do: mod.remote_hint(raw), else: nil
  end
end
