defmodule Wfe.Scrapers.ATS do
  @moduledoc """
  Behaviour for ATS scraper modules.

  Each scraper fetches raw postings and parses them into the normalized map
  used by `Wfe.Jobs.upsert_jobs/2`.

  Scrapers may optionally implement `remote_hint/1` to short-circuit
  heuristic remote detection using ATS-provided flags (e.g. Ashby `isRemote`,
  Lever `workplaceType`, Workable `telecommuting`).
  """

  @type job_map :: %{
          external_id: String.t(),
          title: String.t() | nil,
          description: String.t() | nil,
          location: String.t() | nil,
          link: String.t() | nil,
          posted_at: DateTime.t() | nil
        }

  @callback fetch_jobs(company :: struct()) :: {:ok, [map()]} | {:error, term()}

  @doc """
  Inspect a **raw** API job payload (pre-parse) and return:
    * `true`  — definitively remote, keep without heuristics
    * `false` — definitively not remote, drop without heuristics
    * `nil`   — unknown, fall through to heuristics
  """
  @callback remote_hint(raw_job :: map()) :: boolean() | nil
  @optional_callbacks remote_hint: 1

  # --- Shared helpers -------------------------------------------------------

  def parse_iso8601(nil), do: nil

  def parse_iso8601(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _} -> DateTime.truncate(dt, :second)
      _ -> nil
    end
  end

  def parse_unix_ms(nil), do: nil

  def parse_unix_ms(ms) when is_integer(ms) do
    ms |> DateTime.from_unix!(:millisecond) |> DateTime.truncate(:second)
  end

  @doc """
  Join non-blank location parts with ", ". Returns `nil` if all blank.
  Used by Workable and Recruitee.
  """
  def join_location(parts) when is_list(parts) do
    parts
    |> Enum.reject(&(&1 in [nil, ""]))
    |> case do
      [] -> nil
      list -> Enum.join(list, ", ")
    end
  end
end
