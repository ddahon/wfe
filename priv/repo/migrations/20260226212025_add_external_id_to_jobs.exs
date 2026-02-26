defmodule Wfe.Repo.Migrations.AddExternalIdToJobs do
  use Ecto.Migration

  def change do
    alter table(:jobs) do
      # ID from the ATS — used for upsert deduplication
      add :external_id, :string, null: false
    end

    create unique_index(:jobs, [:company_id, :external_id])
  end
end
