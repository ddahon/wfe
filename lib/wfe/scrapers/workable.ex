defmodule Wfe.Scrapers.Workable do
  @behaviour Wfe.Scrapers.ATS
  import Wfe.Scrapers.ATS, only: [parse_iso8601: 1]

  @base "https://apply.workable.com/api/v1/widget/accounts"

  @impl true
  def fetch_jobs(company) do
    url = "#{@base}/#{company.ats_identifier}"

    case Req.get(url, receive_timeout: 30_000) do
      {:ok, %{status: 200, body: %{"jobs" => jobs}}} ->
        {:ok, Enum.map(jobs, &parse(company.ats_identifier, &1))}

      {:ok, %{status: status, body: body}} ->
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse(slug, j) do
    shortcode = j["shortcode"]

    %{
      external_id: shortcode,
      title: j["title"],
      description: j["description"],
      location: format_location(j),
      link: "https://apply.workable.com/#{slug}/j/#{shortcode}/",
      posted_at: parse_iso8601(j["published_on"])
    }
  end

  defp format_location(j) do
    [j["city"], j["state"], j["country"]]
    |> Enum.reject(&is_nil/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join(", ")
    |> case do
      "" -> j["location"] || if j["telecommuting"], do: "Remote"
      loc -> if j["telecommuting"], do: "#{loc} (Remote)", else: loc
    end
  end
end
