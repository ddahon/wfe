defmodule Mix.Tasks.Wfe.Scrape do
  @shortdoc "Manually trigger a full scrape"

  @moduledoc """
  Enqueues the scrape orchestrator.

      mix wfe.scrape

  If a previous run appears stuck, cancel its jobs directly:

      iex> Oban.cancel_all_jobs(Oban.Job |> where(worker: "Wfe.Workers.ScrapeCompanyWorker"))
  """
  use Mix.Task

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    {:ok, job} =
      %{}
      |> Wfe.Workers.ScrapeOrchestrator.new()
      |> Oban.insert()

    Mix.shell().info("Orchestrator enqueued (job ##{job.id}).")
  end
end
