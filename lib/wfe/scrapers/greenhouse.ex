defmodule Wfe.Scrapers.Greenhouse do
  @behaviour Wfe.Scrapers.ATS
  import Wfe.Scrapers.ATS, only: [parse_iso8601: 1]

  @base "https://boards-api.greenhouse.io/v1/boards"

  @impl true
  def fetch_jobs(company) do
    url = "#{@base}/#{company.ats_identifier}/jobs?content=true"

    case Req.get(url, receive_timeout: 30_000) do
      {:ok, %{status: 200, body: %{"jobs" => jobs}}} ->
        {:ok, Enum.map(jobs, &parse/1)}

      {:ok, %{status: status, body: body}} ->
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse(j) do
    %{
      external_id: to_string(j["id"]),
      title: j["title"],
      description: j["content"],
      location: get_in(j, ["location", "name"]),
      link: j["absolute_url"],
      posted_at: parse_iso8601(j["updated_at"])
    }
  end
end
