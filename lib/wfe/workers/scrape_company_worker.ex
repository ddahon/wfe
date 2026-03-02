defmodule Wfe.Workers.ScrapeCompanyWorker do
  @moduledoc """
  Scrapes a single company. Runs in the ATS-specific queue
  (concurrency 1 → no parallel calls to the same ATS).
  """
  use Oban.Worker,
    max_attempts: 3,
    # Dedupe on args+queue while job is pending/running/retrying.
    unique: [
      period: 600,
      fields: [:args, :queue],
      states: [:available, :scheduled, :executing, :retryable]
    ]

  alias Wfe.{Companies, Jobs, Scrapers}
  alias Wfe.Scrapers.CircuitBreaker

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"company_id" => id}, attempt: attempt, max_attempts: max}) do
    company = Companies.get_company!(id)
    Companies.mark_scrape_in_progress(company)

    Logger.info("[Scraper] #{company.name} (#{company.ats}) — attempt #{attempt}/#{max}")

    case Scrapers.fetch_jobs(company) do
      {:ok, jobs} ->
        {count, _} = Jobs.upsert_jobs(company, jobs)
        Logger.info("[Scraper] #{company.name}: upserted #{count} jobs")
        Companies.mark_scrape_complete(company)
        CircuitBreaker.record_success(company.ats)
        Process.sleep(500)
        :ok

      {:error, reason} ->
        Logger.warning("[Scraper] #{company.name} failed: #{inspect(reason)}")
        CircuitBreaker.record_failure(company.ats)

        if attempt >= max do
          Companies.mark_scrape_failed(company, inspect(reason))
        end

        {:error, reason}
    end
  end
end
