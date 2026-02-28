defmodule Wfe.Repo.Migrations.AddJobSearchIndexes do
  use Ecto.Migration

  def change do
    # Primary filter + sort column. This is the single most important index.
    # Every query filters posted_at > cutoff AND sorts by posted_at DESC.
    # SQLite can use this for both the range scan and the order by.
    create index(:jobs, [:posted_at])

    # Covering index for the join — lets the planner walk posted_at,
    # then grab company_id without touching the main table row.
    create index(:jobs, [:posted_at, :company_id])

    # Expression index on lowercase title.
    # Used when a search term is present (lower(title) LIKE 'foo%').
    # Note: only helps prefix patterns, not '%foo%' — but still cheap to have.
    execute(
      "CREATE INDEX jobs_title_lower_idx ON jobs (lower(title))",
      "DROP INDEX jobs_title_lower_idx"
    )

    execute(
      "CREATE INDEX companies_name_lower_idx ON companies (lower(name))",
      "DROP INDEX companies_name_lower_idx"
    )

    # If you don't already have one: makes the join fast.
    create_if_not_exists index(:jobs, [:company_id])
  end
end
