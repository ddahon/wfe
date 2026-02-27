defmodule Wfe.CompaniesFinder.Supervisor do
  @moduledoc """
  Supervisor for the companies finder background worker.
  """

  use Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    children = [
      {Wfe.CompaniesFinder.Worker, worker_opts()}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  defp worker_opts do
    Application.get_env(:wfe, :companies_finder, [])
  end
end
