defmodule Wfe.Scrapers.Teamtailor do
  @behaviour Wfe.Scrapers.ATS
  import Wfe.Scrapers.ATS, only: [parse_iso8601: 1]

  # Teamtailor public JSON:API:
  # GET https://{company}.teamtailor.com/api/v1/jobs
  # Requires the Accept-Version header; no auth for public roles.
  # Paginated via "links.next" in the envelope.

  @api_version "20210218"

  @impl true
  def fetch_jobs(company) do
    base = "https://#{company.ats_identifier}.teamtailor.com/api/v1/jobs"
    fetch_all(base, [])
  end

  @impl true
  def remote_hint(%{"attributes" => %{"remote-status" => "remote"}}), do: true
  def remote_hint(%{"attributes" => %{"remote-status" => "hybrid"}}), do: nil
  def remote_hint(%{"attributes" => %{"remote-status" => "on-site"}}), do: false
  def remote_hint(_), do: nil

  defp fetch_all(url, acc) do
    case Req.get(url,
           receive_timeout: 30_000,
           headers: [{"accept-version", @api_version}]
         ) do
      {:ok, %{status: 200, body: %{"data" => jobs} = body}} ->
        parsed = Enum.map(jobs, &{&1, parse(&1)})
        all = acc ++ parsed

        case get_in(body, ["links", "next"]) do
          next when is_binary(next) and next != "" ->
            fetch_all(next, all)

          _ ->
            {:ok, all}
        end

      {:ok, %{status: status, body: body}} ->
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse(%{"id" => id, "attributes" => attrs}) do
    %{
      external_id: to_string(id),
      title: attrs["title"],
      description: attrs["body"],
      location: nil,
      # Location is a relationship object; resolving it requires extra calls
      link: attrs["career-site-url"],
      posted_at: parse_iso8601(attrs["created-at"])
    }
  end
end
