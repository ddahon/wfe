defmodule Wfe.Workers.ScrapeOrchestrator do
  @moduledoc """
  Finds companies needing a scrape and enqueues one ScrapeCompanyWorker
  per company into its ATS-specific queue.
  """
  use Oban.Worker, queue: :default, max_attempts: 1

  alias Wfe.Companies
  alias Wfe.Workers.ScrapeCompanyWorker

  require Logger

  @impl true
  def perform(_job) do
    candidates = Companies.list_scrape_candidates()
    Logger.info("[Orchestrator] Found #{length(candidates)} candidates")

    # Oban.insert_all/1 bypasses :unique; insert/1 respects it.
    {inserted, dupes} =
      Enum.reduce(candidates, {0, 0}, fn company, {ins, dup} ->
        %{"company_id" => company.id}
        |> ScrapeCompanyWorker.new(queue: String.to_existing_atom(company.ats))
        |> Oban.insert()
        |> case do
          {:ok, %Oban.Job{conflict?: true}} ->
            {ins, dup + 1}

          {:ok, _job} ->
            {ins + 1, dup}

          {:error, reason} ->
            Logger.warning("[Orchestrator] insert failed for #{company.id}: #{inspect(reason)}")
            {ins, dup}
        end
      end)

    Logger.info("[Orchestrator] Enqueued #{inserted}, skipped #{dupes} duplicates")
    :ok
  end
end
