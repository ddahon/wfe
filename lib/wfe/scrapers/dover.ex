defmodule Wfe.Scrapers.Dover do
  @behaviour Wfe.Scrapers.ATS
  import Wfe.Scrapers.ATS, only: [parse_iso8601: 1]

  # Dover public jobs API:
  # GET https://app.dover.com/api/v1/jobs/?company_slug={company}&page_size=200
  # Paginated via `next` cursor in the response envelope.

  @base "https://app.dover.com/api/v1/jobs/"
  @page_size 200

  @impl true
  def fetch_jobs(company) do
    fetch_all(company.ats_identifier, [], nil)
  end

  @impl true
  def remote_hint(%{"remote_eligible" => true}), do: true
  def remote_hint(%{"remote_eligible" => false}), do: false
  def remote_hint(_), do: nil

  # Recursively follow the `next` cursor until exhausted.
  defp fetch_all(slug, acc, cursor) do
    params =
      [company_slug: slug, page_size: @page_size]
      |> then(fn p -> if cursor, do: [{:cursor, cursor} | p], else: p end)

    case Req.get(@base, params: params, receive_timeout: 30_000) do
      {:ok, %{status: 200, body: %{"results" => jobs} = body}} ->
        parsed = Enum.map(jobs, &{&1, parse(&1)})
        next = extract_cursor(body["next"])

        if next do
          fetch_all(slug, acc ++ parsed, next)
        else
          {:ok, acc ++ parsed}
        end

      {:ok, %{status: status, body: body}} ->
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Dover returns the full next-page URL; pull out the cursor param value.
  defp extract_cursor(nil), do: nil

  defp extract_cursor(url) when is_binary(url) do
    uri = URI.parse(url)

    uri.query
    |> URI.decode_query()
    |> Map.get("cursor")
  end

  defp parse(j) do
    %{
      external_id: j["id"] || j["job_id"],
      title: j["title"],
      description: j["description"],
      location: j["location"],
      link: build_link(j),
      posted_at: parse_iso8601(j["created_at"])
    }
  end

  defp build_link(%{"company_slug" => slug, "id" => id}),
    do: "https://app.dover.com/jobs/#{slug}/#{id}"

  defp build_link(_), do: nil
end
