defmodule Mix.Tasks.Wfe.CleanJobs do
  @shortdoc "Delete all records from jobs and oban_jobs tables"

  @moduledoc """
  Cleans the jobs table (scraped job postings), oban_jobs table (Oban queue),
  and filter_events table (filter audit).

      mix wfe.clean_jobs --confirm

  Target only one table:

      mix wfe.clean_jobs --confirm --jobs-only        # only jobs
      mix wfe.clean_jobs --confirm --oban-only        # only oban_jobs
      mix wfe.clean_jobs --confirm --filter-events-only  # only filter_events

  Requires --confirm to prevent accidental data loss.
  """
  use Mix.Task

  import Ecto.Query

  @impl Mix.Task
  def run(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        switches: [
          confirm: :boolean,
          "jobs-only": :boolean,
          "oban-only": :boolean,
          "filter-events-only": :boolean
        ],
        aliases: [c: :confirm]
      )

    unless Keyword.get(opts, :confirm) do
      Mix.raise("""
      This will delete all data from the target table(s). Use --confirm to proceed.

        mix wfe.clean_jobs --confirm
      """)
    end

    Mix.Task.run("app.start")

    jobs_only? = Keyword.get(opts, :"jobs-only", false)
    oban_only? = Keyword.get(opts, :"oban-only", false)
    # OptionParser converts --filter-events-only to :filter_events_only
    filter_events_only? = Keyword.get(opts, :filter_events_only, false)

    # If any -only flag, clean only that table; otherwise clean all three
    any_only? = jobs_only? or oban_only? or filter_events_only?
    clean_jobs? = jobs_only? or not any_only?
    clean_oban? = oban_only? or not any_only?
    clean_filter_events? = filter_events_only? or not any_only?

    if clean_jobs? do
      {count, _} = from(j in Wfe.Jobs.Job) |> Wfe.Repo.delete_all()
      Mix.shell().info("Deleted #{count} rows from jobs table.")
    end

    if clean_oban? do
      {count, _} = from(j in Oban.Job) |> Wfe.Repo.delete_all()
      Mix.shell().info("Deleted #{count} rows from oban_jobs table.")
    end

    if clean_filter_events? do
      {count, _} = from(e in Wfe.Scrapers.FilterEvent) |> Wfe.Repo.delete_all()
      Mix.shell().info("Deleted #{count} rows from filter_events table.")
    end
  end
end
