defmodule Wfe.Scrapers.Lever do
  @behaviour Wfe.Scrapers.ATS
  import Wfe.Scrapers.ATS, only: [parse_unix_ms: 1]

  @base "https://api.lever.co/v0/postings"

  @impl true
  def fetch_jobs(company) do
    url = "#{@base}/#{company.ats_identifier}?mode=json"

    case Req.get(url, receive_timeout: 30_000) do
      {:ok, %{status: 200, body: jobs}} when is_list(jobs) ->
        {:ok, Enum.map(jobs, &{&1, parse(&1)})}

      {:ok, %{status: status, body: body}} ->
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  # Lever v0 has `workplaceType`: "remote" | "hybrid" | "on-site"
  def remote_hint(%{"workplaceType" => "remote"}), do: true
  def remote_hint(%{"workplaceType" => "on-site"}), do: false
  def remote_hint(%{"workplaceType" => "onsite"}), do: false
  # hybrid → nil → let heuristics decide based on description
  def remote_hint(_), do: nil

  defp parse(j) do
    %{
      external_id: j["id"],
      title: j["text"],
      description: j["descriptionPlain"] || j["description"],
      location: get_in(j, ["categories", "location"]),
      link: j["hostedUrl"],
      posted_at: parse_unix_ms(j["createdAt"])
    }
  end
end
