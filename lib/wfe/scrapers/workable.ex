defmodule Wfe.Scrapers.Workable do
  @behaviour Wfe.Scrapers.ATS
  import Wfe.Scrapers.ATS, only: [parse_iso8601: 1, join_location: 1]

  @base "https://apply.workable.com/api/v1/widget/accounts"

  @impl true
  def fetch_jobs(company) do
    url = "#{@base}/#{company.ats_identifier}"

    case Req.get(url, receive_timeout: 30_000) do
      {:ok, %{status: 200, body: %{"jobs" => jobs}}} ->
        {:ok, Enum.map(jobs, &{&1, parse(company.ats_identifier, &1)})}

      {:ok, %{status: status, body: body}} ->
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  # Workable: `telecommuting: true` means remote-friendly.
  def remote_hint(%{"telecommuting" => true}), do: true
  def remote_hint(%{"telecommuting" => false}), do: false
  def remote_hint(_), do: nil

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
    base = join_location([j["city"], j["state"], j["country"]]) || j["location"]

    case {base, j["telecommuting"]} do
      {nil, true} -> "Remote"
      {loc, true} -> "#{loc} (Remote)"
      {loc, _} -> loc
    end
  end
end
