defmodule Wfe.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Fail fast if ATS list, scraper modules, and Oban queues are misaligned.
    Wfe.Scrapers.ConfigCheck.validate!()

    children = [
      WfeWeb.Telemetry,
      Wfe.Repo,
      {Oban, Application.fetch_env!(:wfe, Oban)},
      Wfe.Scrapers.CircuitBreaker,
      {DNSCluster, query: Application.get_env(:wfe, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Wfe.PubSub},
      {Finch, name: Wfe.Finch},
      WfeWeb.Endpoint,
      {Wfe.CompaniesFinder.Supervisor, []}
    ]

    opts = [strategy: :one_for_one, name: Wfe.Supervisor]
    result = Supervisor.start_link(children, opts)

    # Attach after the supervision tree so Oban's own handlers are in place.
    Wfe.Workers.ScrapeTelemetry.attach()

    result
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    WfeWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
