defmodule Wfe.Scrapers.ConfigCheck do
  @moduledoc """
  Fail fast at boot if the ATS list, scraper modules, and Oban queues
  are out of sync. Called from Wfe.Application.start/2.
  """

  alias Wfe.Companies.Company
  alias Wfe.Scrapers

  def validate! do
    ats = Company.valid_ats()

    check!("scraper module", ats -- Scrapers.supported_ats())
    check!("Oban queue", ats -- configured_queues())

    :ok
  end

  defp check!(_what, []), do: :ok

  defp check!(what, missing) do
    raise """
    Scraper misconfiguration: ATS #{inspect(missing)} listed in
    Company.valid_ats/0 but has no matching #{what}.
    """
  end

  defp configured_queues do
    :wfe
    |> Application.get_env(Oban, [])
    |> Keyword.get(:queues, [])
    |> Keyword.keys()
    |> Enum.map(&to_string/1)
  end
end
