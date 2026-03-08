defmodule Wfe.Companies do
  import Ecto.Query
  alias Wfe.Repo
  alias Wfe.Companies.Company

  @valid_ats Company.valid_ats()

  def get_company!(id), do: Repo.get!(Company, id)
  def get_company(id), do: Repo.get(Company, id)

  @doc """
  Companies due for a scrape.

  Ordered by `last_scraped_at NULLS FIRST` so the stalest companies get
  queued first, and — critically — so ATSes are *interleaved* rather than
  inserted in contiguous blocks. This means all Oban queues receive work
  roughly simultaneously instead of one queue filling up before the next
  starts.
  """
  def list_scrape_candidates(opts \\ []) do
    hours = Keyword.get(opts, :threshold_hours, 6)
    threshold = DateTime.add(DateTime.utc_now(), -hours, :hour)

    Company
    |> where([c], c.ats in @valid_ats and not is_nil(c.ats_identifier))
    |> where([c], is_nil(c.last_scraped_at) or c.last_scraped_at < ^threshold)
    |> order_by([c], asc_nulls_first: c.last_scraped_at)
    |> Repo.all()
  end

  @doc """
  Stamp `last_scraped_at` unconditionally.

  Called on *every* scrape attempt regardless of outcome, so
  `list_scrape_candidates/1` doesn't re-select a company that just ran.
  Does NOT touch `last_scrape_error` — that's the job of
  `mark_scrape_succeeded/1` and `mark_scrape_failed/2`.
  """
  def touch_last_scraped(%Company{} = company) do
    update_company(company, %{
      last_scraped_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
  end

  @doc "Clear any prior error. Call after a successful scrape."
  def mark_scrape_succeeded(%Company{} = company) do
    update_company(company, %{last_scrape_error: nil})
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

  # ───────────────────────── find / create ─────────────────────────

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

  def get_by_ats(ats, ats_identifier) do
    Company
    |> where([c], c.ats == ^ats and c.ats_identifier == ^ats_identifier)
    |> Repo.one()
  end

  def create_company(attrs) do
    %Company{} |> Company.changeset(attrs) |> Repo.insert()
  end

  def upsert_company(attrs) do
    %Company{}
    |> Company.changeset(attrs)
    |> Repo.insert(
      on_conflict: :nothing,
      conflict_target: [:ats, :ats_identifier],
      returning: true
    )
  end

  defp humanize_identifier(identifier) do
    identifier
    |> String.replace(~r/[-_]+/, " ")
    |> String.split()
    |> Enum.map_join(" ", &String.capitalize/1)
  end
end
