defmodule Wfe.Scrapers do
  @moduledoc """
  Dispatches to the correct ATS scraper and applies remote-only filtering.

  Filtering is two-tiered:
    1. ATS-provided hints (optional `remote_hint/1` callback on raw payload)
    2. Heuristic fallback on parsed fields (`Wfe.Jobs.RemoteFilter`)

  Every decision is recorded in `filter_events` for auditing.
  """

  alias Wfe.Jobs.RemoteFilter
  alias Wfe.Scrapers.FilterAudit

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

  # --- Filtering with Audit -------------------------------------------------

  defp filter_remote(mod, company, pairs) do
    run_id = Ecto.UUID.generate()

    # 1. Bucket by ATS hint: true / false / nil
    by_hint =
      Enum.group_by(pairs, fn {raw, _parsed} -> apply_hint(mod, raw) end)

    # 2. Build decisions for ATS-hinted jobs
    ats_remote_decisions =
      by_hint
      |> Map.get(true, [])
      |> Enum.map(fn {_raw, parsed} -> {parsed, "passed", "ats_hint_remote"} end)

    ats_onsite_decisions =
      by_hint
      |> Map.get(false, [])
      |> Enum.map(fn {_raw, parsed} -> {parsed, "rejected", "ats_hint_onsite"} end)

    # 3. Run heuristics on undecided jobs
    unknown_parsed = by_hint |> Map.get(nil, []) |> Enum.map(&elem(&1, 1))
    {heuristic_passed, heuristic_rejected} = RemoteFilter.apply_with_rejects(unknown_parsed)

    heuristic_pass_decisions =
      Enum.map(heuristic_passed, fn parsed -> {parsed, "passed", "heuristic_pass"} end)

    heuristic_reject_decisions =
      Enum.map(heuristic_rejected, fn parsed -> {parsed, "rejected", "heuristic_reject"} end)

    # 4. Collect all decisions and persist
    all_decisions =
      ats_remote_decisions ++
        ats_onsite_decisions ++
        heuristic_pass_decisions ++
        heuristic_reject_decisions

    # Persist asynchronously so it doesn't slow down the pipeline.
    # If you prefer guaranteed writes, remove the Task wrapper.
    Task.start(fn ->
      FilterAudit.record(company, all_decisions, run_id)
    end)

    # 5. Return only the kept jobs
    kept_parsed = Enum.map(ats_remote_decisions, &elem(&1, 0)) ++ heuristic_passed

    Logger.debug("""
    [Scrapers] #{company.name} (run #{run_id}): #{length(pairs)} fetched
      #{length(ats_remote_decisions)} ATS-flagged remote
      #{length(ats_onsite_decisions)} ATS-flagged on-site
      #{length(heuristic_passed)}/#{length(unknown_parsed)} passed heuristics
      #{length(kept_parsed)} kept
    """)

    kept_parsed
  end

  defp apply_hint(mod, raw) do
    if function_exported?(mod, :remote_hint, 1), do: mod.remote_hint(raw), else: nil
  end
end
