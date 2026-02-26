defmodule Wfe.Workers.ScrapeOrchestrator do
  @moduledoc """
  Finds companies needing a scrape and enqueues one worker per company
  into the ATS-specific queue.
  """
  use Oban.Worker, queue: :default, max_attempts: 1

  alias Wfe.Companies
  alias Wfe.Workers.ScrapeCompanyWorker

  require Logger

  @impl Oban.Worker
  def perform(_job) do
    candidates = Companies.list_scrape_candidates()
    Logger.info("[Orchestrator] Enqueuing #{length(candidates)} companies")

    candidates
    |> Enum.map(fn company ->
      ScrapeCompanyWorker.new(
        %{company_id: company.id},
        queue: String.to_existing_atom(company.ats)
      )
    end)
    |> Oban.insert_all()

    :ok
  end
end
