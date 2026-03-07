defmodule Wfe.CompaniesFinder.CDXClient do
  @moduledoc """
  Client for querying the Wayback Machine CDX API to find archived URLs.

  Automatically paginates through the full result set using the CDX
  `showResumeKey` / `resumeKey` cursor mechanism, so callers always
  receive every matching URL — not just the first page.
  """

  require Logger

  @base_url "https://web.archive.org/cdx/search/cdx"
  @default_timeout 120_000
  @max_retries 3
  @retry_delay_ms 2_000
  @default_page_size 50_000
  @page_delay_ms 1_500

  @type search_result :: {:ok, [String.t()]} | {:error, term()}

  @doc """
  Search the CDX API for URLs matching the given pattern.

  Paginates automatically until all results have been retrieved.

  ## Options
    * `:page_size`  - Results per CDX request (default: #{@default_page_size})
    * `:max_pages`  - Safety cap on the number of pages (default: unlimited)
    * `:collapse`   - Field to collapse for deduplication (default: `"urlkey"`)
    * `:filter`     - Status-code filter (default: `"statuscode:200"`)
    * `:from`       - Start date in `YYYYMMDD` format
    * `:to`         - End date in `YYYYMMDD` format
  """
  @spec search(String.t(), keyword()) :: search_result()
  def search(url_pattern, opts \\ []) do
    page_size = Keyword.get(opts, :page_size, @default_page_size)
    max_pages = Keyword.get(opts, :max_pages, :infinity)
    base_params = build_base_params(url_pattern, opts)

    Logger.info("CDX search: #{url_pattern} (page_size=#{page_size})")

    fetch_all_pages(base_params, page_size, max_pages, _resume_key = nil, _acc = [], _page = 1)
  end

  # ---------------------------------------------------------------------------
  # Pagination
  # ---------------------------------------------------------------------------

  defp fetch_all_pages(_base_params, _page_size, max_pages, _resume_key, acc, page)
       when is_integer(max_pages) and page > max_pages do
    Logger.info("CDX pagination stopped: reached max_pages limit (#{max_pages})")
    {:ok, acc}
  end

  defp fetch_all_pages(base_params, page_size, max_pages, resume_key, acc, page) do
    params =
      base_params
      |> Keyword.put(:limit, page_size)
      |> Keyword.put(:showResumeKey, true)
      |> maybe_add(:resumeKey, resume_key)

    url = "#{@base_url}?#{URI.encode_query(params)}"
    Logger.debug("CDX page #{page}: #{url}")

    case fetch_with_retry(url, @max_retries) do
      {:ok, {urls, new_resume_key}} ->
        all_urls = acc ++ urls

        Logger.info(
          "CDX page #{page}: #{length(urls)} URLs (total: #{length(all_urls)})"
        )

        if new_resume_key != nil and urls != [] do
          Process.sleep(@page_delay_ms)
          fetch_all_pages(base_params, page_size, max_pages, new_resume_key, all_urls, page + 1)
        else
          {:ok, all_urls}
        end

      {:error, reason} ->
        if acc != [] do
          Logger.warning(
            "CDX pagination stopped after #{length(acc)} URLs due to error: #{inspect(reason)}"
          )

          {:ok, acc}
        else
          {:error, reason}
        end
    end
  end

  # ---------------------------------------------------------------------------
  # HTTP with retries
  # ---------------------------------------------------------------------------

  defp fetch_with_retry(url, retries_left) do
    case do_request(url) do
      {:ok, _} = success ->
        success

      {:error, :rate_limited} when retries_left > 0 ->
        backoff = @retry_delay_ms * (@max_retries - retries_left + 1) * 2

        Logger.warning(
          "CDX rate-limited, backing off #{backoff}ms (#{retries_left} retries left)"
        )

        Process.sleep(backoff)
        fetch_with_retry(url, retries_left - 1)

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

  # ---------------------------------------------------------------------------
  # Params
  # ---------------------------------------------------------------------------

  defp build_base_params(url_pattern, opts) do
    [
      url: url_pattern,
      output: "json",
      fl: "original",
      collapse: Keyword.get(opts, :collapse, "urlkey"),
      filter: Keyword.get(opts, :filter, "statuscode:200")
    ]
    |> maybe_add(:from, Keyword.get(opts, :from))
    |> maybe_add(:to, Keyword.get(opts, :to))
  end

  defp maybe_add(params, _key, nil), do: params
  defp maybe_add(params, key, value), do: Keyword.put(params, key, value)

  # ---------------------------------------------------------------------------
  # Response parsing
  # ---------------------------------------------------------------------------

  # JSON response (Req auto-decodes): first row is the header, and when
  # `showResumeKey=true` the API appends `[], ["<key>"]` after the data rows.
  defp parse_response(body) when is_list(body) do
    case body do
      [] ->
        {[], nil}

      [_header | rows] ->
        {data_rows, resume_key} = extract_resume_key_json(rows)

        urls =
          Enum.map(data_rows, fn
            [url | _] -> url
            url when is_binary(url) -> url
          end)

        {urls, resume_key}
    end
  end

  # Plain-text fallback (one URL per line, resume key after a blank line at end).
  defp parse_response(body) when is_binary(body) do
    {text_body, resume_key} = extract_resume_key_text(body)

    urls =
      text_body
      |> String.split("\n", trim: true)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    {urls, resume_key}
  end

  defp parse_response(_), do: {[], nil}

  # Pattern: [...data_rows, [], ["<resume_key>"]]
  defp extract_resume_key_json(rows) do
    case Enum.reverse(rows) do
      [[key] | [[] | rest]] when is_binary(key) and key != "" ->
        {Enum.reverse(rest), key}

      _ ->
        {rows, nil}
    end
  end

  # The resume key sits after the *last* blank line in the text body.
  defp extract_resume_key_text(body) do
    trimmed = String.trim_trailing(body)

    case :binary.matches(trimmed, "\n\n") do
      [] ->
        {trimmed, nil}

      matches ->
        {pos, _len} = List.last(matches)
        data = binary_part(trimmed, 0, pos)

        candidate =
          trimmed
          |> binary_part(pos + 2, byte_size(trimmed) - pos - 2)
          |> String.trim()

        # Resume keys are non-empty, single-line strings that don't look like URLs.
        if candidate != "" and not String.contains?(candidate, "\n") do
          {data, candidate}
        else
          {trimmed, nil}
        end
    end
  end
end
