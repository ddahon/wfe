defmodule Wfe.Scrapers.SmartRecruiters do
  @behaviour Wfe.Scrapers.ATS
  import Wfe.Scrapers.ATS, only: [parse_iso8601: 1, join_location: 1]

  # SmartRecruiters public API (no auth required for public postings):
  # GET https://api.smartrecruiters.com/v1/companies/{company}/postings
  # Paginated: { "content": [...], "totalFound": N, "offset": N, "limit": N }

  @base "https://api.smartrecruiters.com/v1/companies"
  @page_size 100

  @impl true
  def fetch_jobs(company) do
    fetch_all(company.ats_identifier, [], 0)
  end

  @impl true
  # SmartRecruiters surfaces a typeOfJob field ("remote", "hybrid", etc.)
  def remote_hint(%{"typeOfJob" => "remote"}), do: true
  def remote_hint(%{"typeOfJob" => "telecommuting"}), do: true
  def remote_hint(_), do: nil

  defp fetch_all(company_id, acc, offset) do
    url = "#{@base}/#{company_id}/postings"
    params = [limit: @page_size, offset: offset]

    case Req.get(url, params: params, receive_timeout: 30_000) do
      {:ok, %{status: 200, body: %{"content" => jobs, "totalFound" => total}}} ->
        parsed = Enum.map(jobs, &{&1, parse(&1)})
        all = acc ++ parsed
        next_offset = offset + length(jobs)

        if next_offset < total do
          fetch_all(company_id, all, next_offset)
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
      external_id: j["id"],
      title: j["name"],
      description: nil,
      # Full description requires a separate GET .../postings/{id} call
      location: build_location(j),
      link: build_link(j),
      posted_at: parse_iso8601(j["releasedDate"])
    }
  end

  defp build_location(%{"location" => loc}) when is_map(loc) do
    join_location([
      loc["city"],
      loc["region"],
      loc["country"]
    ])
  end

  defp build_location(_), do: nil

  defp build_link(%{"company" => %{"identifier" => company_id}, "id" => id}),
    do: "https://careers.smartrecruiters.com/#{company_id}/#{id}"

  defp build_link(_), do: nil
end
