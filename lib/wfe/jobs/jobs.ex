defmodule Wfe.Jobs do
  alias Wfe.Repo
  alias Wfe.Jobs.Job

  @doc """
  Bulk upsert jobs for a company. New jobs are inserted,
  existing ones (matched on company_id + external_id) are updated.
  """
  def upsert_jobs(company, job_attrs_list) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    entries =
      Enum.map(job_attrs_list, fn attrs ->
        attrs
        |> Map.put(:id, Ecto.UUID.generate())
        |> Map.put(:company_id, company.id)
        |> Map.put(:inserted_at, now)
        |> Map.put(:updated_at, now)
      end)

    Repo.insert_all(Job, entries,
      on_conflict: {:replace, [:title, :description, :location, :link, :posted_at, :updated_at]},
      conflict_target: [:company_id, :external_id]
    )
  end
end
