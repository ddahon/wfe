defmodule Wfe.Scrapers.Jobvite do
  @behaviour Wfe.Scrapers.ATS
  import Wfe.Scrapers.ATS, only: [join_location: 1]

  # Jobvite public XML/JSON feed:
  # GET https://jobs.jobvite.com/api/jobs?c={companyId}&cb=1
  # The `cb` param requests JSON (JSONP callback suppressed).
  # The company identifier from the CDX finder is the Jobvite company token.

  @base "https://jobs.jobvite.com/api/jobs"

  @impl true
  def fetch_jobs(company) do
    url = "#{@base}?c=#{company.ats_identifier}&cb=1"

    case Req.get(url, receive_timeout: 30_000) do
      {:ok, %{status: 200, body: %{"requisitions" => jobs}}} when is_list(jobs) ->
        {:ok, Enum.map(jobs, &{&1, parse(&1)})}

      {:ok, %{status: status, body: body}} ->
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def remote_hint(%{"remote" => true}), do: true
  def remote_hint(%{"remote" => false}), do: false
  def remote_hint(_), do: nil

  defp parse(j) do
    %{
      external_id: j["id"],
      title: j["title"],
      description: j["description"],
      location: build_location(j),
      link: j["applyLink"] || j["jobLink"],
      posted_at: nil
      # Jobvite's public feed does not surface a reliable ISO timestamp
    }
  end

  defp build_location(j) do
    join_location([j["location"]])
  end
end
