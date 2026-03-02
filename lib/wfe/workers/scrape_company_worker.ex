defmodule Wfe.Workers.ScrapeCompanyWorker do
  @moduledoc """
  Scrapes a single company.

  Runs in an ATS-specific queue (concurrency 1 → serial calls per ATS).
  Cross-cutting concerns — circuit breaker, final-failure persistence —
  are handled by Wfe.Workers.ScrapeTelemetry.
  """
  use Oban.Worker,
    max_attempts: 3,
    # Dedupe on args+queue as long as *any* matching job is in-flight,
    # regardless of how long ago it was inserted.
    unique: [
      period: :infinity,
      fields: [:args, :queue],
      states: [:available, :scheduled, :executing, :retryable]
    ]

  alias Wfe.{Companies, Jobs, Scrapers}

  require Logger

  @impl Oban.Worker
  def timeout(_job), do: :timer.seconds(60)

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"company_id" => id}, attempt: attempt, max_attempts: max}) do
    company = Companies.get_company!(id)

    Logger.info("[Scraper] #{company.name} (#{company.ats}) — attempt #{attempt}/#{max}")

    with {:ok, jobs} <- Scrapers.fetch_jobs(company) do
      {count, _} = Jobs.upsert_jobs(company, jobs)
      Companies.touch_last_scraped(company)
      Logger.info("[Scraper] #{company.name}: upserted #{count} jobs")
      :ok
    end

    # {:error, reason} flows out → Oban retries with backoff,
    # telemetry handler feeds the circuit breaker.
  end
end
