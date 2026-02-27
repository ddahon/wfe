# lib/wfe/scrapers/recruitee.ex
defmodule Wfe.Scrapers.Recruitee do
  @behaviour Wfe.Scrapers.ATS
  import Wfe.Scrapers.ATS, only: [parse_iso8601: 1]

  @impl true
  def fetch_jobs(company) do
    url = "https://#{company.ats_identifier}.recruitee.com/api/offers"

    case Req.get(url, receive_timeout: 30_000) do
      {:ok, %{status: 200, body: %{"offers" => jobs}}} ->
        {:ok, Enum.map(jobs, &parse(company.ats_identifier, &1))}

      {:ok, %{status: status, body: body}} ->
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse(identifier, j) do
    %{
      external_id: to_string(j["id"]),
      title: j["title"],
      description: j["description"],
      location: parse_location(j),
      link: j["careers_url"] || "https://#{identifier}.recruitee.com/o/#{j["slug"]}",
      posted_at: parse_iso8601(j["published_at"] || j["created_at"])
    }
  end

  defp parse_location(j) do
    [j["city"], j["state"], j["country"]]
    |> Enum.reject(&is_nil/1)
    |> Enum.reject(&(&1 == ""))
    |> case do
      [] -> j["location"]
      parts -> Enum.join(parts, ", ")
    end
  end
end
