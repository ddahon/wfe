defmodule Wfe.Repo.Migrations.NormalizeLastScrapeError do
  use Ecto.Migration

  # Map every known raw inspect() string that was stored before normalization
  # to its canonical form. Add rows here as you discover new patterns in
  # production data.
  @mappings [
    # 404 shapes
    {~r/\{:http_error,\s*404/, "not_found"},
    {~r/\{:http,\s*404/, "not_found"},
    {~r/not.found/i, "not_found"},
    # 429
    {~r/\{:http_error,\s*429/, "rate_limited"},
    {~r/rate.limit/i, "rate_limited"},
    # 5xx
    {~r/\{:http_error,\s*5\d\d/, "server_error"},
    # timeout
    {~r/timeout/i, "timeout"},
    # network
    {~r/:econnrefused/, "network_error"},
    {~r/:nxdomain/, "network_error"},
    {~r/:closed/, "network_error"}
  ]

  def up do
    # SQLite has no native regex UPDATE, so we pull and update in Elixir.
    # The companies table is small; this is fine as a one-shot migration.
    repo().query!(
      "SELECT id, last_scrape_error FROM companies WHERE last_scrape_error IS NOT NULL"
    )
    |> Map.fetch!(:rows)
    |> Enum.each(fn [id, raw] ->
      canonical = normalize(raw)

      if canonical != raw do
        repo().query!(
          "UPDATE companies SET last_scrape_error = ? WHERE id = ?",
          [canonical, id]
        )
      end
    end)
  end

  def down, do: :ok

  defp normalize(raw) do
    Enum.find_value(@mappings, raw, fn {pattern, canonical} ->
      if Regex.match?(pattern, raw), do: canonical
    end)
  end
end
