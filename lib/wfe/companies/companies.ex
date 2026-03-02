defmodule Wfe.Companies do
  import Ecto.Query
  alias Wfe.Repo
  alias Wfe.Companies.Company

  @valid_ats Company.valid_ats()

  def get_company!(id), do: Repo.get!(Company, id)

  @doc "Non-bang variant; telemetry handlers must not crash."
  def get_company(id), do: Repo.get(Company, id)

  @doc """
  Companies due for a scrape.

  No longer filters by scrape_status — Oban's unique constraint
  already prevents duplicate in-flight jobs. Select purely on staleness.
  """
  def list_scrape_candidates do
    threshold = DateTime.add(DateTime.utc_now(), -6, :hour)

    Company
    |> where([c], c.ats in @valid_ats and not is_nil(c.ats_identifier))
    |> where([c], is_nil(c.last_scraped_at) or c.last_scraped_at < ^threshold)
    |> Repo.all()
  end

  @doc "Record a successful scrape: stamp time, clear any prior error."
  def touch_last_scraped(%Company{} = company) do
    company
    |> Ecto.Changeset.change(
      last_scraped_at: DateTime.utc_now() |> DateTime.truncate(:second),
      last_scrape_error: nil
    )
    |> Repo.update()
  end

  @doc "Record final failure after all retries (called from telemetry handler)."
  def mark_scrape_failed(company, reason) do
    update_company(company, %{
      last_scrape_error: reason |> to_string() |> String.slice(0, 255)
    })
  end

  defp update_company(company, attrs) do
    company |> Ecto.Changeset.change(attrs) |> Repo.update()
  end

  @doc """
  Finds an existing company by ATS and identifier, or creates a new one.

  Returns:
    - `{:ok, :created, company}` if a new company was created
    - `{:ok, :exists, company}` if the company already exists
    - `{:error, changeset}` if creation failed
  """
  def find_or_create_company(ats, ats_identifier) do
    case get_by_ats(ats, ats_identifier) do
      nil ->
        name = humanize_identifier(ats_identifier)

        case create_company(%{name: name, ats: ats, ats_identifier: ats_identifier}) do
          {:ok, company} -> {:ok, :created, company}
          {:error, changeset} -> {:error, changeset}
        end

      company ->
        {:ok, :exists, company}
    end
  end

  @doc """
  Get a company by its ATS and identifier.
  """
  def get_by_ats(ats, ats_identifier) do
    Company
    |> where([c], c.ats == ^ats and c.ats_identifier == ^ats_identifier)
    |> Repo.one()
  end

  @doc """
  Create a new company.
  """
  def create_company(attrs) do
    %Company{}
    |> Company.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Upsert a company - create if not exists, otherwise return existing.
  Uses a database-level constraint for race condition safety.
  """
  def upsert_company(attrs) do
    %Company{}
    |> Company.changeset(attrs)
    |> Repo.insert(
      on_conflict: :nothing,
      conflict_target: [:ats, :ats_identifier],
      returning: true
    )
  end

  # Converts "acme-corp" to "Acme Corp"
  defp humanize_identifier(identifier) do
    identifier
    |> String.replace(~r/[-_]+/, " ")
    |> String.split()
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end
end
