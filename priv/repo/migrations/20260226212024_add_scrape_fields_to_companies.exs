defmodule Wfe.Repo.Migrations.AddScrapeFieldsToCompanies do
  use Ecto.Migration

  def change do
    alter table(:companies) do
      # The company's slug/board-id in the ATS (e.g. "stripe" for greenhouse)
      add :ats_identifier, :string
      add :scrape_status, :string, default: "pending", null: false
      add :scrape_error, :string
      add :last_scraped_at, :utc_datetime
    end

    create index(:companies, [:scrape_status])
    create index(:companies, [:ats])
  end
end
