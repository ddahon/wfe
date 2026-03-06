defmodule Wfe.Workers.ScrapeTelemetry do
  @moduledoc """
  Telemetry handler for ScrapeCompanyWorker jobs.

  Handles cross-cutting concerns that used to live inline in perform/1:
    * Circuit-breaker success/failure tracking
    * Persisting the final error to the company after all retries exhaust

  Attach once at boot (see Wfe.Application).
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

  def handle_event([:oban, :job, :stop], _meas, %{worker: @worker} = meta, _cfg) do
    handle_success(meta)
  end

  def handle_event([:oban, :job, :exception], _meas, %{worker: @worker} = meta, _cfg) do
    handle_failure(meta)
  end

  def handle_event(_event, _meas, _meta, _cfg), do: :ok

  # --- Handlers ------------------------------------------------------------

  defp handle_success(%{queue: queue}) do
    CircuitBreaker.record_success(queue)
  end

  defp handle_failure(%{queue: queue, attempt: attempt, max_attempts: max} = meta) do
    # Don't count 404s as circuit breaker failures - these are expected
    # when companies remove their job boards
    unless is_404_error?(meta) do
      CircuitBreaker.record_failure(queue)
    end

    if attempt >= max do
      persist_failure(meta, extract_reason(meta))
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

  defp extract_reason(%{error: reason}), do: inspect(reason)
  defp extract_reason(_), do: "unknown"

  defp is_404_error?(meta) do
    case meta do
      %{error: %{status: 404}} ->
        true

      %{error: {:error, :not_found}} ->
        true

      %{error: :not_found} ->
        true

      %{kind: :error, error: %{__exception__: true} = exception} ->
        message = Exception.message(exception) |> String.downcase()
        String.contains?(message, "404") or String.contains?(message, "not found")

      _ ->
        reason = extract_reason(meta) |> String.downcase()
        String.contains?(reason, "404") or String.contains?(reason, "not_found")
    end
  end
end
