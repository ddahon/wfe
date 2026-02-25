defmodule Wfe.Repo.Migrations.CreateJobs do
  use Ecto.Migration

  def change do
    create table(:jobs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :title, :string
      add :description, :text
      add :location, :string
      add :link, :string
      add :posted_at, :utc_datetime

      add :company_id, references(:companies, on_delete: :delete_all, type: :binary_id),
        null: false

      timestamps(type: :utc_datetime)
    end

    create index(:jobs, [:company_id])
  end
end
