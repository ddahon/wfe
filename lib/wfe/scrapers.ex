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
        with {:ok, jobs} <- mod.fetch_jobs(company) do
          {:ok, filter_remote(mod, company, jobs)}
        end

      :error ->
        {:error, {:unsupported_ats, ats}}
    end
  end

  # --- Filtering ------------------------------------------------------------

  # Scrapers now return `{raw, parsed}` tuples so we can consult raw
  # ATS fields for remote hints before falling back to text heuristics.
  defp filter_remote(mod, company, raw_parsed_pairs) do
    total = length(raw_parsed_pairs)

    {definite_keep, unknown} =
      Enum.reduce(raw_parsed_pairs, {[], []}, fn {raw, parsed}, {keep, unk} ->
        case apply_hint(mod, raw) do
          true -> {[parsed | keep], unk}
          false -> {keep, unk}
          nil -> {keep, [parsed | unk]}
        end
      end)

    heuristic_keep = RemoteFilter.apply(unknown)
    kept = definite_keep ++ heuristic_keep

    Logger.debug(
      "[Scrapers] #{company.name}: #{total} fetched → " <>
        "#{length(definite_keep)} ATS-flagged remote, " <>
        "#{length(heuristic_keep)}/#{length(unknown)} passed heuristics, " <>
        "#{length(kept)} kept"
    )

    kept
  end

  defp apply_hint(mod, raw) do
    if function_exported?(mod, :remote_hint, 1) do
      mod.remote_hint(raw)
    else
      nil
    end
  end
end
