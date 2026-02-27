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

  # Only create queue atoms for known ATS (whitelist) to avoid to_existing_atom failures
  # and unbounded atom creation. Uses Company.valid_ats/0 as single source of truth.
  defp queue_for_ats(ats) do
    if ats in Company.valid_ats() do
      String.to_atom(ats)
    else
      raise "Unknown ATS for queue: #{inspect(ats)}. Add to Company.valid_ats and Oban queues."
    end
  end

  @insert_batch_size 500

  @impl Oban.Worker
  def perform(_job) do
    candidates = Companies.list_scrape_candidates()
    Logger.info("[Orchestrator] Enqueuing #{length(candidates)} companies")

    candidates
    |> Enum.map(fn company ->
      queue = queue_for_ats(company.ats)

      ScrapeCompanyWorker.new(
        %{company_id: company.id},
        queue: queue
      )
    end)
    |> Enum.chunk_every(@insert_batch_size)
    |> Enum.each(&Oban.insert_all/1)

    :ok
  end
end
