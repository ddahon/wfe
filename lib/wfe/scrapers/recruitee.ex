defmodule Wfe.Scrapers.Recruitee do
  @behaviour Wfe.Scrapers.ATS
  import Wfe.Scrapers.ATS, only: [parse_iso8601: 1, join_location: 1]

  @impl true
  def fetch_jobs(company) do
    url = "https://#{company.ats_identifier}.recruitee.com/api/offers"

    case Req.get(url, receive_timeout: 30_000) do
      {:ok, %{status: 200, body: %{"offers" => jobs}}} ->
        {:ok, Enum.map(jobs, &{&1, parse(company.ats_identifier, &1)})}

      {:ok, %{status: status, body: body}} ->
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  # Recruitee has a `remote` boolean on offers.
  def remote_hint(%{"remote" => true}), do: true
  def remote_hint(%{"remote" => false}), do: false
  def remote_hint(_), do: nil

  defp parse(identifier, j) do
    %{
      external_id: to_string(j["id"]),
      title: j["title"],
      description: j["description"],
      location: join_location([j["city"], j["state"], j["country"]]) || j["location"],
      link: j["careers_url"] || "https://#{identifier}.recruitee.com/o/#{j["slug"]}",
      posted_at: parse_iso8601(j["published_at"] || j["created_at"])
    }
  end
end
