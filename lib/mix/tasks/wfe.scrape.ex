defmodule Mix.Tasks.Wfe.Scrape do
  @moduledoc "Manually trigger a full scrape. Usage: mix wfe.scrape [--reset]"
  use Mix.Task

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    if "--reset" in args do
      Wfe.Companies.reset_scrape_status()
      Mix.shell().info("Reset all company scrape statuses.")
    end

    {:ok, job} =
      Wfe.Workers.ScrapeOrchestrator.new(%{})
      |> Oban.insert()

    Mix.shell().info("Orchestrator enqueued (job ##{job.id}).")
    Mix.shell().info("Watch progress with: Oban.check_queue(queue: :greenhouse) etc.")
  end
end
