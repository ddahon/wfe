defmodule Wfe.Scrapers.ATS do
  @callback fetch_jobs(company :: struct()) :: {:ok, [map()]} | {:error, term()}

  # Shared datetime helpers
  def parse_iso8601(nil), do: nil

  def parse_iso8601(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _} -> DateTime.truncate(dt, :second)
      _ -> nil
    end
  end

  def parse_unix_ms(nil), do: nil

  def parse_unix_ms(ms) when is_integer(ms) do
    ms |> DateTime.from_unix!(:millisecond) |> DateTime.truncate(:second)
  end
end
