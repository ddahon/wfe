defmodule Wfe.Scrapers.Pinpoint do
  @behaviour Wfe.Scrapers.ATS
  import Wfe.Scrapers.ATS, only: [parse_iso8601: 1, join_location: 1]

  # Pinpoint public JSON API:
  # GET https://{company}.pinpointhq.com/api/v1/jobs
  # Returns a JSON:API envelope: { "data": [ { "id": ..., "attributes": {...} } ] }

  @impl true
  def fetch_jobs(company) do
    url = "https://#{company.ats_identifier}.pinpointhq.com/api/v1/jobs"

    case Req.get(url, receive_timeout: 30_000) do
      {:ok, %{status: 200, body: %{"data" => jobs}}} when is_list(jobs) ->
        {:ok, Enum.map(jobs, &{&1, parse(&1)})}

      {:ok, %{status: status, body: body}} ->
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def remote_hint(%{"attributes" => %{"remote" => true}}), do: true
  def remote_hint(%{"attributes" => %{"remote" => false}}), do: false
  def remote_hint(_), do: nil

  defp parse(%{"id" => id, "attributes" => attrs} = _raw) do
    %{
      external_id: to_string(id),
      title: attrs["title"],
      description: attrs["description"],
      location: build_location(attrs),
      link: attrs["apply_url"],
      posted_at: parse_iso8601(attrs["published_at"])
    }
  end

  defp build_location(attrs) do
    join_location([
      attrs["city"],
      attrs["state_province"],
      attrs["country"]
    ])
  end
end
