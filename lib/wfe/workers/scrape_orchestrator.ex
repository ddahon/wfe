defmodule Wfe.Workers.ScrapeOrchestrator do
  @moduledoc """
  Finds companies needing a scrape and enqueues one worker per company
  into the ATS-specific queue.
  """
  use Oban.Worker, queue: :default, max_attempts: 1

  alias Wfe.Companies
  alias Wfe.Companies.Company
  alias Wfe.Workers.ScrapeCompanyWorker

  require Logger

  defp queue_for_ats(ats) do
    if ats in Company.valid_ats() do
      String.to_atom(ats)
    else
      raise "Unknown ATS for queue: #{inspect(ats)}. Add to Company.valid_ats and Oban queues."
    end
  end

  @impl Oban.Worker
  def perform(_job) do
    candidates = Companies.list_scrape_candidates()
    Logger.info("[Orchestrator] Found #{length(candidates)} candidates")

    # Oban.insert_all bypasses :unique checks. Use insert/1 so the worker's
    # `unique` option actually dedupes in-flight jobs for the same company.
    {inserted, dupes} =
      Enum.reduce(candidates, {0, 0}, fn company, {ins, dup} ->
        result =
          %{company_id: company.id}
          |> ScrapeCompanyWorker.new(queue: queue_for_ats(company.ats))
          |> Oban.insert()

        case result do
          {:ok, %Oban.Job{conflict?: true}} -> {ins, dup + 1}
          {:ok, _} -> {ins + 1, dup}
          {:error, reason} ->
            Logger.warning("[Orchestrator] insert failed for #{company.id}: #{inspect(reason)}")
            {ins, dup}
        end
      end)

    Logger.info("[Orchestrator] Enqueued #{inserted}, skipped #{dupes} duplicates")
    :ok
  end
end
