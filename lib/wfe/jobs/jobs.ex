defmodule Wfe.Jobs do
  import Ecto.Query

  alias Wfe.Repo
  alias Wfe.Jobs.{Job, ContentHash}

  require Logger

  @doc """
  Bulk upsert jobs for a company.

  Deduplication:
    1. Within the incoming batch (same content_hash → keep first)
    2. Against existing DB rows (indexed lookup on company_id + content_hash)

  A job is skipped if its content already exists in the DB. This also
  short-circuits no-op updates (same external_id, unchanged content).
  """
  def upsert_jobs(company, job_attrs_list) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    # -- 1. Attach hashes ----------------------------------------------------
    hashed =
      Enum.map(job_attrs_list, fn attrs ->
        Map.put(attrs, :content_hash, ContentHash.compute(attrs[:title], attrs[:description]))
      end)

    # -- 2. Dedupe within this batch ----------------------------------------
    batch_unique = Enum.uniq_by(hashed, & &1.content_hash)

    # -- 3. Dedupe against DB (single indexed query) ------------------------
    incoming_hashes = Enum.map(batch_unique, & &1.content_hash)

    existing_hashes =
      Job
      |> where([j], j.content_hash in ^incoming_hashes)
      |> select([j], j.content_hash)
      |> Repo.all()
      |> MapSet.new()

    fresh = Enum.reject(batch_unique, &MapSet.member?(existing_hashes, &1.content_hash))

    skipped = length(job_attrs_list) - length(fresh)

    if skipped > 0 do
      Logger.debug("[Jobs] #{company.name}: skipped #{skipped} duplicate(s) by content")
    end

    # -- 4. Insert -----------------------------------------------------------
    entries =
      Enum.map(fresh, fn attrs ->
        attrs
        |> Map.put(:id, Ecto.UUID.generate())
        |> Map.put(:company_id, company.id)
        |> Map.put(:inserted_at, now)
        |> Map.put(:updated_at, now)
      end)

    Repo.insert_all(Job, entries,
      on_conflict:
        {:replace,
         [:title, :description, :location, :link, :posted_at, :content_hash, :updated_at]},
      conflict_target: [:company_id, :external_id]
    )
  end
end
