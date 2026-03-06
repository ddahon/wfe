defmodule Wfe.Scrapers do
  @moduledoc """
  Dispatches to the correct ATS scraper and applies remote + region filtering.

  Three-stage funnel:
    1. ATS hint          — scraper's `remote_hint/1` on the raw payload
    2. Remote heuristics — `Wfe.Jobs.RemoteFilter` on parsed fields
    3. Region filter     — `Wfe.Jobs.RegionFilter` drops single-country
                           roles and normalises `region`

  Every job's final outcome is logged to `filter_events`.
  """

  alias Wfe.Jobs.{RemoteFilter, RegionFilter}
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

  def fetch_jobs(%{ats: ats} = company) do
    case Map.fetch(@scrapers, ats) do
      {:ok, mod} ->
        with {:ok, pairs} <- mod.fetch_jobs(company) do
          {:ok, filter_pipeline(mod, company, pairs)}
        end

      :error ->
        {:error, {:unsupported_ats, ats}}
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # Filter pipeline
  # ──────────────────────────────────────────────────────────────────────────

  defp filter_pipeline(mod, company, pairs) do
    run_id = Ecto.UUID.generate()

    # ── Stage 1: ATS hint ────────────────────────────────────────────────
    by_hint = Enum.group_by(pairs, fn {raw, _} -> apply_hint(mod, raw) end)

    ats_remote = parsed(by_hint, true)
    ats_onsite = parsed(by_hint, false)
    ats_unknown = parsed(by_hint, nil)

    # ── Stage 2: Remote heuristics on undecided ─────────────────────────
    {heur_passed, heur_rejected} = RemoteFilter.apply_with_rejects(ats_unknown)

    # ── Stage 3: Region classification on all remote survivors ──────────
    # Runs on (ATS-remote ∪ heuristic-pass). Single-country roles die here;
    # survivors get a normalised :region field.
    remote_survivors = ats_remote ++ heur_passed
    {region_kept, region_rejected} = RegionFilter.apply(remote_survivors)

    # ── Audit: one final decision per job ────────────────────────────────
    # A job that passed stage 1 but failed stage 3 is recorded as a
    # region rejection — that's the interesting bit for tuning.
    decisions =
      Enum.map(ats_onsite, &{&1, "rejected", "ats_hint_onsite"}) ++
        Enum.map(heur_rejected, &{&1, "rejected", "heuristic_reject"}) ++
        Enum.map(region_rejected, fn {job, reason} -> {job, "rejected", reason} end) ++
        Enum.map(region_kept, fn job -> {job, "passed", "region:#{job[:region]}"} end)

    Task.start(fn -> FilterAudit.record(company, decisions, run_id) end)

    Logger.debug("""
    [Scrapers] #{company.name} (run #{run_id}): #{length(pairs)} fetched
      stage 1: #{length(ats_onsite)} rejected by ATS hint, #{length(ats_unknown)} undecided
      stage 2: #{length(heur_rejected)}/#{length(ats_unknown)} rejected by heuristics
      stage 3: #{length(region_rejected)}/#{length(remote_survivors)} rejected by region filter
      → #{length(region_kept)} kept #{region_breakdown(region_kept)}
    """)

    # Drop the helper atom before handing off to upsert — schema doesn't
    # know about it.
    Enum.map(region_kept, &Map.delete(&1, :region_atom))
  end

  defp parsed(grouped, key), do: grouped |> Map.get(key, []) |> Enum.map(&elem(&1, 1))

  defp apply_hint(mod, raw) do
    if function_exported?(mod, :remote_hint, 1), do: mod.remote_hint(raw), else: nil
  end

  # "(Global: 4, EMEA: 2, APAC: 1)" — nice to have in logs.
  defp region_breakdown([]), do: ""

  defp region_breakdown(jobs) do
    jobs
    |> Enum.frequencies_by(& &1[:region])
    |> Enum.map_join(", ", fn {r, n} -> "#{r}: #{n}" end)
    |> then(&"(#{&1})")
  end
end
