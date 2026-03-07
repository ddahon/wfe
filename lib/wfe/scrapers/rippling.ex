defmodule Wfe.Scrapers.Rippling do
  @behaviour Wfe.Scrapers.ATS
  import Wfe.Scrapers.ATS, only: [parse_iso8601: 1]

  # Rippling public ATS API:
  # GET https://ats.rippling.com/api/v1/{company}/jobs/
  # Returns a paginated envelope: { "results": [...], "next": "..." }

  @page_size 100

  @impl true
  def fetch_jobs(company) do
    base = "https://ats.rippling.com/api/v1/#{company.ats_identifier}/jobs/"
    fetch_all(base, [], 1)
  end

  @impl true
  def remote_hint(%{"remote" => true}), do: true
  def remote_hint(%{"remote" => false}), do: false
  def remote_hint(_), do: nil

  defp fetch_all(base, acc, page) do
    params = [page: page, page_size: @page_size]

    case Req.get(base, params: params, receive_timeout: 30_000) do
      {:ok, %{status: 200, body: %{"results" => jobs} = body}} ->
        parsed = Enum.map(jobs, &{&1, parse(&1)})
        all = acc ++ parsed

        if body["next"] do
          fetch_all(base, all, page + 1)
        else
          {:ok, all}
        end

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
      description: j["description"],
      location: j["location_description"] || j["location"],
      link: j["job_url"],
      posted_at: parse_iso8601(j["created_at"])
    }
  end
end
