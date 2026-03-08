defmodule Wfe.Workers.ScrapeCompanyWorker do
  @moduledoc """
  Scrapes a single company.

  Runs in an ATS-specific queue (concurrency 2 → up to 2 concurrent calls per ATS).
  Cross-cutting concerns — circuit breaker, final-failure persistence —
  are handled by Wfe.Workers.ScrapeTelemetry.
  """
  use Oban.Worker,
    max_attempts: 3,
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

    result = Scrapers.fetch_jobs(company)

    # Stamp last_scraped_at regardless of outcome. The orchestrator selects
    # on this column; if we only stamped on success, a company that
    # consistently 404s or errors would be picked up on every single run.
    # Error details are persisted separately by the telemetry handler.
    Companies.touch_last_scraped(company)

    case result do
      {:ok, jobs} ->
        {count, _} = Jobs.upsert_jobs(company, jobs)
        Companies.mark_scrape_succeeded(company)
        Logger.info("[Scraper] #{company.name}: upserted #{count} jobs")
        :ok

      # 404 = stale/wrong board URL. Retrying won't help; discard immediately
      # so we don't waste attempts and don't trip the circuit breaker.
      {:error, reason} = err ->
        if not_found?(reason) do
          Logger.info("[Scraper] #{company.name}: 404 — discarding, no retry")
          {:discard, reason}
        else
          err
        end
    end
  end

  defp not_found?(:not_found), do: true
  defp not_found?({:http_error, 404}), do: true
  defp not_found?({:http_error, 404, _}), do: true
  defp not_found?({:http, 404}), do: true
  defp not_found?({:http, 404, _}), do: true
  defp not_found?(%{status: 404}), do: true
  defp not_found?(r) when is_binary(r), do: String.contains?(r, "404")
  defp not_found?(_), do: false
end
