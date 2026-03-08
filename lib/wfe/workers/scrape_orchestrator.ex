defmodule Wfe.Workers.ScrapeOrchestrator do
  @moduledoc """
  Finds companies needing a scrape and enqueues one ScrapeCompanyWorker
  per company into its ATS-specific queue.

  ## SQLite write-lock strategy

  SQLite allows exactly one writer. With 13 ATS queues × concurrency 2,
  up to 26 workers can be trying to write (Oban state transitions + job
  upserts) at the same moment the orchestrator is inserting jobs. When
  the original version inserted jobs one-by-one with `Oban.insert/1`,
  three things went wrong:

    1. Early inserts became `:available` immediately, workers picked them
       up, and their writes starved the orchestrator → very slow enqueue.
    2. Under contention, inserts hit SQLITE_BUSY → `{:error, _}` → silently
       dropped → "not all jobs get added".
    3. Candidates came back in table order (roughly grouped by ATS) so one
       queue filled completely before the next got anything.

  Mitigations:

    * Collect every changeset first, then `Oban.insert_all/1` in chunks
      (one lock acquisition per chunk instead of per job). Bypasses the
      per-insert uniqueness check, so we do our own dedup pass against
      in-flight jobs.
    * Schedule every job `@enqueue_delay_seconds` in the future. Jobs land
      as `:scheduled`, workers ignore them, the orchestrator finishes all
      its chunks with zero contention, *then* everything becomes available
      at once.
    * Interleave candidates round-robin by ATS so when jobs go live, all
      13 queues have work immediately rather than greenhouse finishing
      before lever starts.
  """
  use Oban.Worker, queue: :default, max_attempts: 1

  import Ecto.Query

  alias Wfe.Companies
  alias Wfe.Workers.ScrapeCompanyWorker

  require Logger

  # Delay before jobs become available. Must comfortably exceed the time
  # to insert all chunks. Even at 10k companies / 500 per chunk = 20
  # chunks, each chunk commits in milliseconds — 30s is a wide margin,
  # and costs nothing on a 24h cron schedule.
  @enqueue_delay_seconds 30

  # SQLite's SQLITE_MAX_VARIABLE_NUMBER defaults to 999 on older builds
  # (32_766 since 3.32.0, but exqlite's bundled version and runtime limit
  # aren't guaranteed). An Oban job row binds ~12 columns, so the hard
  # ceiling is ~80 rows on the old limit. 500 fits the modern limit with
  # room to spare; if you ever see "too many SQL variables", drop this to
  # 60 and you're safe on any SQLite build.
  @insert_chunk_size 500

  # Oban states that indicate a job is already in flight. Mirrors the
  # `unique: [states: ...]` on ScrapeCompanyWorker — we're reimplementing
  # that check here because insert_all/1 bypasses it.
  @in_flight_states ~w(available scheduled executing retryable)

  @impl true
  def perform(%Oban.Job{args: args}) do
    opts = if h = args["threshold_hours"], do: [threshold_hours: h], else: []

    candidates = Companies.list_scrape_candidates(opts)
    Logger.info("[Orchestrator] #{length(candidates)} candidate(s)")

    {changesets, skipped} = build_changesets(candidates)
    inserted = insert_jobs(changesets)

    Logger.info(
      "[Orchestrator] enqueued=#{inserted} " <>
        "skipped_in_flight=#{skipped} " <>
        "delay=#{@enqueue_delay_seconds}s"
    )

    :ok
  end

  # ──────────────────────────── building ────────────────────────────

  # Returns {[changeset], skipped_count}.
  # Filters out companies that already have an in-flight job, then
  # interleaves the remainder by ATS so all queues get work simultaneously.
  defp build_changesets([]), do: {[], 0}

  defp build_changesets(candidates) do
    in_flight = in_flight_company_ids()

    {to_enqueue, already_running} =
      Enum.split_with(candidates, fn c -> not MapSet.member?(in_flight, c.id) end)

    changesets =
      to_enqueue
      |> interleave_by_ats()
      |> Enum.map(&to_changeset/1)

    {changesets, length(already_running)}
  end

  defp to_changeset(company) do
    ScrapeCompanyWorker.new(
      %{"company_id" => company.id},
      queue: String.to_existing_atom(company.ats),
      schedule_in: @enqueue_delay_seconds
    )
  end

  # Company IDs with a ScrapeCompanyWorker job currently
  # available/scheduled/executing/retryable. One query up front instead
  # of a uniqueness lookup per insert.
  #
  # We pull *all* in-flight IDs rather than filtering by the candidate
  # set on the DB side. Simpler query, and the row count is bounded by
  # "companies scraped in the last few hours" — trivially small.
  defp in_flight_company_ids do
    worker = Oban.Worker.to_string(ScrapeCompanyWorker)

    Oban.Job
    |> where([j], j.worker == ^worker and j.state in @in_flight_states)
    |> select([j], j.args["company_id"])
    |> Wfe.Repo.all()
    |> MapSet.new()
  end

  # Round-robin interleave: group by ATS, then take the 1st from each
  # group, then the 2nd, etc.
  #
  #   in:  [g1, g2, g3, l1, l2, a1]   (g=greenhouse, l=lever, a=ashby)
  #   out: [g1, l1, a1, g2, l2, g3]
  #
  # list_scrape_candidates/1 already orders by staleness, so position
  # *within* each group is preserved — the stalest greenhouse company
  # still goes before the second-stalest greenhouse company.
  #
  # This mostly matters for the *first* run or after adding a batch of
  # companies from one ATS; steady-state the staleness ordering already
  # mixes ATSes naturally.
  defp interleave_by_ats(companies) do
    companies
    |> Enum.group_by(& &1.ats)
    |> Map.values()
    |> zip_longest()
  end

  # Enum.zip/1 stops at the shortest list. We want to keep going until
  # all lists are exhausted, dropping empties as we go.
  defp zip_longest([]), do: []

  defp zip_longest(lists) do
    {heads, tails} =
      Enum.flat_map_reduce(lists, [], fn
        [], tails -> {[], tails}
        [h | t], tails -> {[h], [t | tails]}
      end)

    # flat_map_reduce built tails in reverse; flip back to preserve the
    # round-robin order across passes.
    heads ++ zip_longest(Enum.reverse(tails))
  end

  # ──────────────────────────── inserting ────────────────────────────

  # Chunked bulk insert.
  #
  # Each chunk is its own INSERT statement (and its own implicit
  # transaction under Oban.Engines.Lite). We deliberately do NOT wrap all
  # chunks in a single Repo.transaction/1: holding the write lock for the
  # full duration would block Oban's internal bookkeeping and the Pruner
  # plugin. Chunk-level atomicity is fine here — a partial run just means
  # some companies wait for the next cron tick, and the in-flight dedup
  # on the next run prevents double-enqueuing whatever did succeed.
  #
  # The `schedule_in` delay ensures no ScrapeCompanyWorker starts
  # executing between chunks, so there's still no contention from *our*
  # workload.
  defp insert_jobs([]), do: 0

  defp insert_jobs(changesets) do
    changesets
    |> Enum.chunk_every(@insert_chunk_size)
    |> Enum.reduce(0, fn chunk, acc ->
      acc + length(Oban.insert_all(chunk))
    end)
  end
end
