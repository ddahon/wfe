defmodule Wfe.Repo.Migrations.AddRegionToJobs do
  use Ecto.Migration

  def change do
    alter table(:jobs) do
      # Canonical region: "Global", "EMEA", "APAC", "Americas",
      # "North America", "LATAM", "Europe". Nullable for legacy rows.
      add :region, :string
    end

    # "Show me all EMEA jobs" is the whole point of normalising.
    create index(:jobs, [:region])
  end
end
