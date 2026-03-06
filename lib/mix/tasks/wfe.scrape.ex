defmodule Mix.Tasks.Wfe.Scrape do
  @shortdoc "Manually trigger a full scrape"

  @moduledoc """
  Enqueues the scrape orchestrator.

      mix wfe.scrape

  Override the last-scraped threshold (default 6 hours):

      mix wfe.scrape --hours 0    # all companies (ignore last_scraped_at)
      mix wfe.scrape --hours 24  # only companies not scraped in 24h

  If a previous run appears stuck, cancel its jobs directly:

      iex> Oban.cancel_all_jobs(Oban.Job |> where(worker: "Wfe.Workers.ScrapeCompanyWorker"))
  """
  use Mix.Task

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    opts = parse_args(args)
    job_args = if hours = Keyword.get(opts, :threshold_hours), do: %{"threshold_hours" => hours}, else: %{}

    {:ok, job} =
      job_args
      |> Wfe.Workers.ScrapeOrchestrator.new()
      |> Oban.insert()

    Mix.shell().info("Orchestrator enqueued (job ##{job.id}).")
  end

  defp parse_args(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        switches: [hours: :integer],
        aliases: [h: :hours]
      )

    case Keyword.get(opts, :hours) do
      nil -> []
      h when h >= 0 -> [threshold_hours: h]
      _ -> Mix.raise("--hours must be >= 0")
    end
  end
end
