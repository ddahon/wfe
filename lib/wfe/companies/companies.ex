defmodule Wfe.Companies do
  import Ecto.Query
  alias Wfe.Repo
  alias Wfe.Companies.Company

  @valid_ats ~w(greenhouse lever ashby)
  @stale_after_hours 6

  def get_company!(id), do: Repo.get!(Company, id)

  @doc """
  Returns companies that need scraping:
  - Never scraped, OR
  - Failed last time, OR
  - Stuck in progress (crash recovery), OR
  - Successfully scraped but stale
  """
  def list_scrape_candidates do
    cutoff = DateTime.utc_now() |> DateTime.add(-@stale_after_hours, :hour)

    Company
    |> where([c], c.ats in @valid_ats and not is_nil(c.ats_identifier))
    |> where(
      [c],
      c.scrape_status != "completed" or
        is_nil(c.last_scraped_at) or
        c.last_scraped_at < ^cutoff
    )
    |> Repo.all()
  end

  def mark_scrape_in_progress(company) do
    update_company(company, %{scrape_status: "in_progress", scrape_error: nil})
  end

  def mark_scrape_complete(company) do
    update_company(company, %{
      scrape_status: "completed",
      scrape_error: nil,
      last_scraped_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
  end

  def mark_scrape_failed(company, reason) do
    update_company(company, %{
      scrape_status: "failed",
      scrape_error: reason |> to_string() |> String.slice(0, 255)
    })
  end

  @doc "Reset everything — useful for forcing a full re-scrape."
  def reset_scrape_status do
    Repo.update_all(Company, set: [scrape_status: "pending", scrape_error: nil])
  end

  defp update_company(company, attrs) do
    company |> Ecto.Changeset.change(attrs) |> Repo.update()
  end
end
