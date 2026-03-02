defmodule Wfe.Repo.Migrations.DropCompanyScrapeStatus do
  use Ecto.Migration

  def change do
    drop_if_exists index(:companies, [:scrape_status])

    alter table(:companies) do
      remove :scrape_status
    end

    execute "ALTER TABLE companies RENAME COLUMN scrape_error TO last_scrape_error;",
            "ALTER TABLE companies RENAME COLUMN last_scrape_error TO scrape_error;"
  end
end
