defmodule Wfe.CompaniesFinder.CDXClient do
  @moduledoc """
  Client for querying the Wayback Machine CDX API to find archived URLs.

  The CDX API allows searching through archived snapshots of websites,
  which we use to discover company career pages on various ATS platforms.
  """

  require Logger

  @base_url "https://web.archive.org/cdx/search/cdx"
  @default_timeout 120_000
  @max_retries 3
  @retry_delay_ms 2_000

  @type search_result :: {:ok, [String.t()]} | {:error, term()}

  @doc """
  Search the CDX API for URLs matching the given pattern.

  ## Options
    * `:limit` - Maximum number of results (default: 100_000)
    * `:collapse` - Field to collapse on for deduplication (default: "urlkey")
    * `:filter` - Status code filter (default: "statuscode:200")
    * `:from` - Start date in YYYYMMDD format
    * `:to` - End date in YYYYMMDD format
  """
  @spec search(String.t(), keyword()) :: search_result()
  def search(url_pattern, opts \\ []) do
    params = build_params(url_pattern, opts)
    url = "#{@base_url}?#{URI.encode_query(params)}"

    Logger.debug("CDX query: #{url}")

    fetch_with_retry(url, @max_retries)
  end

  defp build_params(url_pattern, opts) do
    [
      url: url_pattern,
      output: "json",
      fl: "original",
      collapse: Keyword.get(opts, :collapse, "urlkey"),
      filter: Keyword.get(opts, :filter, "statuscode:200"),
      limit: Keyword.get(opts, :limit, 100_000)
    ]
    |> maybe_add(:from, Keyword.get(opts, :from))
    |> maybe_add(:to, Keyword.get(opts, :to))
  end

  defp maybe_add(params, _key, nil), do: params
  defp maybe_add(params, key, value), do: Keyword.put(params, key, value)

  defp fetch_with_retry(url, retries_left) do
    case do_request(url) do
      {:ok, urls} ->
        {:ok, urls}

      {:error, reason} when retries_left > 0 ->
        Logger.warning("CDX request failed (#{retries_left} retries left): #{inspect(reason)}")
        Process.sleep(@retry_delay_ms)
        fetch_with_retry(url, retries_left - 1)

      {:error, reason} ->
        Logger.error("CDX request failed permanently: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp do_request(url) do
    # Using Req - add {:req, "~> 0.4"} to your mix.exs dependencies
    case Req.get(url, receive_timeout: @default_timeout, retry: false) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, parse_response(body)}

      {:ok, %{status: 429}} ->
        {:error, :rate_limited}

      {:ok, %{status: status, body: body}} ->
        {:error, {:http_error, status, body}}

      {:error, %Req.TransportError{reason: reason}} ->
        {:error, {:transport_error, reason}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_response(body) when is_list(body) do
    # JSON response: first row is header, rest are data rows
    case body do
      [_header | rows] ->
        Enum.map(rows, fn
          [url | _] -> url
          url when is_binary(url) -> url
        end)

      [] ->
        []
    end
  end

  defp parse_response(body) when is_binary(body) do
    # Plain text response (one URL per line)
    body
    |> String.split("\n", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp parse_response(_), do: []
end
