defmodule Wfe.Workers.ScrapeTelemetry do
  @moduledoc """
  Telemetry handler for ScrapeCompanyWorker jobs.

    * Circuit breaker: counts transient failures only. Discards are the
      worker's explicit "this isn't going to fix itself" signal, so they
      don't count toward the threshold.
    * Final-failure persistence: on last attempt OR on discard.
  """

  alias Wfe.Companies
  alias Wfe.Scrapers.CircuitBreaker

  require Logger

  @worker "Wfe.Workers.ScrapeCompanyWorker"
  @events [[:oban, :job, :stop], [:oban, :job, :exception]]

  def attach do
    :telemetry.attach_many("wfe-scrape", @events, &__MODULE__.handle_event/4, nil)
  end

  # --- Event router --------------------------------------------------------

  def handle_event([:oban, :job, :stop], _m, %{worker: @worker, state: :success} = meta, _) do
    handle_success(meta)
  end

  def handle_event([:oban, :job, :stop], _m, %{worker: @worker} = meta, _) do
    handle_failure(meta)
  end

  def handle_event([:oban, :job, :exception], _m, %{worker: @worker} = meta, _) do
    handle_failure(meta)
  end

  def handle_event(_event, _meas, _meta, _cfg), do: :ok

  # --- Handlers ------------------------------------------------------------

  defp handle_success(%{queue: queue}) do
    CircuitBreaker.record_success(queue)
  end

  defp handle_failure(%{queue: queue, attempt: attempt, max_attempts: max} = meta) do
    reason = raw_reason(meta)
    discarded? = Map.get(meta, :state) == :discard

    if discarded? do
      Logger.info("[ScrapeTelemetry] #{queue}: discarded — skipping circuit breaker")
    else
      CircuitBreaker.record_failure(queue)
    end

    # Persist when retries are exhausted OR the worker gave up early.
    if discarded? or attempt >= max do
      persist_failure(meta, format_reason(reason))
    end
  end

  # --- Helpers -------------------------------------------------------------

  defp persist_failure(%{args: %{"company_id" => id}}, reason) do
    case Companies.get_company(id) do
      nil ->
        :ok

      company ->
        Logger.warning("[Scraper] #{company.name}: discarded — #{reason}")
        Companies.mark_scrape_failed(company, reason)
    end
  end

  defp persist_failure(_meta, _reason), do: :ok

  defp raw_reason(%{result: {:error, reason}}), do: reason
  defp raw_reason(%{result: {:discard, reason}}), do: reason
  defp raw_reason(%{error: reason}), do: reason
  defp raw_reason(%{reason: reason}), do: reason
  defp raw_reason(_), do: :unknown

  defp format_reason(r) when is_binary(r), do: r
  defp format_reason(r), do: inspect(r)
end
