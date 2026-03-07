defmodule Wfe.Scrapers.BambooHR do
  @behaviour Wfe.Scrapers.ATS
  import Wfe.Scrapers.ATS, only: [join_location: 1]

  # BambooHR exposes a public JSON feed at:
  # https://{company}.bamboohr.com/careers/list
  # No API key required for public listings.

  @impl true
  def fetch_jobs(company) do
    url = "https://#{company.ats_identifier}.bamboohr.com/careers/list"

    case Req.get(url,
           receive_timeout: 30_000,
           # BambooHR returns JSON only when this header is present
           headers: [{"accept", "application/json"}]
         ) do
      {:ok, %{status: 200, body: %{"result" => jobs}}} when is_list(jobs) ->
        {:ok, Enum.map(jobs, &{&1, parse(&1)})}

      {:ok, %{status: status, body: body}} ->
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  # BambooHR does not surface a reliable remote flag in its public feed.
  def remote_hint(_), do: nil

  defp parse(j) do
    %{
      external_id: to_string(j["id"]),
      title: j["jobOpeningName"],
      description: j["description"],
      location: build_location(j),
      link: j["jobUrl"],
      posted_at: nil
      # BambooHR public feed does not include a posting date
    }
  end

  defp build_location(j) do
    join_location([
      j["city"],
      j["state"],
      j["country"]
    ])
  end
end
