defmodule Wfe.Scrapers.Breezy do
  @behaviour Wfe.Scrapers.ATS
  import Wfe.Scrapers.ATS, only: [join_location: 1]

  # Breezy HR public API:
  # GET https://{company}.breezy.hr/json
  # Returns a JSON array of position objects directly.

  @impl true
  def fetch_jobs(company) do
    url = "https://#{company.ats_identifier}.breezy.hr/json"

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
  def remote_hint(%{"location" => %{"name" => name}}) when is_binary(name) do
    # Breezy uses the string "Remote" as a location value rather than a flag
    if String.downcase(name) =~ "remote", do: true, else: nil
  end

  def remote_hint(_), do: nil

  defp parse(j) do
    %{
      external_id: j["_id"],
      title: j["name"],
      description: nil,
      # Breezy's list endpoint omits full description; detail requires a second call
      location: build_location(j),
      link: j["url"],
      posted_at: nil
      # Publication date is not in the list response
    }
  end

  defp build_location(%{"location" => %{"name" => name}}) when is_binary(name), do: name
  defp build_location(_), do: nil
end


