defmodule Wfe.Scrapers.FilterAudit do
  @moduledoc """
  Persists filter decisions to the `filter_events` table.

  Accepts a list of `{parsed_job, outcome, reason}` tuples from a single
  scraper run and bulk-inserts them. All events share a `run_id` so you
  can reconstruct exactly what happened in each invocation.
  """

  alias Wfe.Repo
  alias Wfe.Scrapers.FilterEvent

  @doc """
  Record a batch of filter decisions.

  ## Parameters
    - `company` – the company struct (needs `:id` and `:ats`)
    - `decisions` – list of `{parsed_job_map, outcome, reason}` tuples
    - `run_id` – UUID grouping all decisions from one fetch

  Inserts in chunks of 500 to stay within SQLite's variable limit.
  """
  def record(company, decisions, run_id) when is_list(decisions) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    entries =
      Enum.map(decisions, fn {parsed, outcome, reason} ->
        %{
          id: Ecto.UUID.generate(),
          company_id: company.id,
          external_id: parsed[:external_id] || "unknown",
          title: parsed[:title],
          location: parsed[:location],
          link: parsed[:link],
          outcome: outcome,
          reason: reason,
          ats: company.ats,
          run_id: run_id,
          inserted_at: now,
          updated_at: now
        }
      end)

    entries
    |> Enum.chunk_every(500)
    |> Enum.each(fn chunk ->
      Repo.insert_all(FilterEvent, chunk)
    end)

    :ok
  end
end
