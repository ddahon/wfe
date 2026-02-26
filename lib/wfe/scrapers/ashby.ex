defmodule Wfe.Scrapers.Ashby do
  @behaviour Wfe.Scrapers.ATS
  import Wfe.Scrapers.ATS, only: [parse_iso8601: 1]

  @base "https://api.ashbyhq.com/posting-api/job-board"

  @impl true
  def fetch_jobs(company) do
    url = "#{@base}/#{company.ats_identifier}"

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
      external_id: j["id"],
      title: j["title"],
      description: j["descriptionPlain"] || j["descriptionHtml"],
      location: j["location"],
      link: j["jobUrl"],
      posted_at: parse_iso8601(j["publishedAt"])
    }
  end
end
