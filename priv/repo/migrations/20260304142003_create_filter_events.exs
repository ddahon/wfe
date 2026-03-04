defmodule Wfe.Repo.Migrations.CreateFilterEvents do
  use Ecto.Migration

  def change do
    create table(:filter_events, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :company_id, references(:companies, type: :binary_id, on_delete: :delete_all),
        null: false

      add :external_id, :string, null: false
      add :title, :string
      add :location, :string
      add :link, :string

      # "passed" or "rejected"
      add :outcome, :string, null: false
      # e.g. "ats_hint_remote", "ats_hint_onsite", "heuristic_pass", "heuristic_reject"
      add :reason, :string, null: false
      # Which ATS scraper module produced this
      add :ats, :string, null: false
      # Groups all events from a single fetch_jobs call
      add :run_id, :binary_id, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:filter_events, [:company_id])
    create index(:filter_events, [:run_id])
    create index(:filter_events, [:outcome])
    create index(:filter_events, [:inserted_at])
    create index(:filter_events, [:company_id, :external_id])
  end
end
