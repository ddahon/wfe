defmodule Wfe.Repo.Migrations.AddIndexCompaniesLastScrapeError do
  use Ecto.Migration

  def change do
    # Partial index: only rows that actually have an error are indexed.
    # This makes both failed_jobs_by_error and total_failed_count index-only scans.
    create index(:companies, [:ats, :updated_at],
             where: "last_scrape_error IS NOT NULL",
             name: :companies_error_ats_updated_at_partial
           )
  end
end
