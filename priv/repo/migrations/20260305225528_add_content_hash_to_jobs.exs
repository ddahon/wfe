defmodule Wfe.Repo.Migrations.AddContentHashToJobs do
  use Ecto.Migration

  def change do
    alter table(:jobs) do
      add :content_hash, :string, size: 64
    end

    # Composite index: lookups are always scoped to a company
    create index(:jobs, [:company_id, :content_hash])
  end
end
