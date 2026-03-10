defmodule Wfe.Scrapers.ErrorReason do
  @moduledoc """
  Canonical error reasons for scrape failures.

  Every scraper returns `{:error, term()}` where `term` can be:
    - a plain atom              (:timeout, :not_found, …)
    - an HTTP tuple             ({:http_error, status} | {:http_error, status, body} |
                                 {:http, status} | {:http, status, body})
    - a map with :status        (%{status: 404})
    - a Req/Mint/Finch struct   (%Req.TransportError{reason: :timeout})
    - a string                  ("404 Not Found")
    - anything else             → "unknown_error"

  `normalize/1` collapses all of those into one of the canonical strings
  below so that the error breakdown table groups them correctly.

  Canonical strings (stored in companies.last_scrape_error):
    "not_found"          — HTTP 404 or explicit :not_found
    "rate_limited"       — HTTP 429 or any rate-limit signal
    "server_error"       — HTTP 5xx
    "timeout"            — connect / read timeout
    "auth_error"         — HTTP 401 / 403
    "bad_gateway"        — HTTP 502 / 504
    "gone"               — HTTP 410 (board removed)
    "parse_error"        — response arrived but couldn't be decoded
    "network_error"      — TCP/DNS-level failure
    "http_<status>"      — any other HTTP status not listed above
    "unknown_error"      — everything else
  """

  # ── Public API ────────────────────────────────────────────────────────

  @spec normalize(term()) :: String.t()
  def normalize(reason) do
    reason
    |> unwrap()
    |> classify()
  end

  # ── Unwrapping ────────────────────────────────────────────────────────
  # Peel off the outer {:error, _} / {:discard, _} if the caller forgot to
  # unwrap, then extract the real signal.

  defp unwrap({:error, inner}), do: unwrap(inner)
  defp unwrap({:discard, inner}), do: unwrap(inner)
  defp unwrap(reason), do: reason

  # ── Classification ────────────────────────────────────────────────────

  # ---- HTTP status tuples (all shapes scrapers actually return) ----------

  # {:http_error, status} | {:http_error, status, _body}
  defp classify({:http_error, status}), do: from_status(status)
  defp classify({:http_error, status, _body}), do: from_status(status)

  # {:http, status} | {:http, status, _body}
  defp classify({:http, status}), do: from_status(status)
  defp classify({:http, status, _body}), do: from_status(status)

  # Map with a :status key (e.g. %{status: 404, body: …})
  defp classify(%{status: status}) when is_integer(status), do: from_status(status)

  # ---- Transport / timeout -----------------------------------------------

  # Req wraps transport errors in %Req.TransportError{reason: reason}
  defp classify(%{__struct__: Req.TransportError, reason: reason}),
    do: classify_transport(reason)

  # Mint and Finch surface similar shapes
  defp classify(%{__struct__: _, reason: reason}), do: classify_transport(reason)

  # Plain atoms
  defp classify(:timeout), do: "timeout"
  defp classify(:connect_timeout), do: "timeout"
  defp classify(:recv_timeout), do: "timeout"
  defp classify(:not_found), do: "not_found"
  defp classify(:gone), do: "gone"
  defp classify(:rate_limited), do: "rate_limited"
  defp classify(:unauthorized), do: "auth_error"
  defp classify(:forbidden), do: "auth_error"
  defp classify(:parse_error), do: "parse_error"
  defp classify({:parse_error, _}), do: "parse_error"

  # ---- Strings (scraper passed a pre-formatted message) ------------------

  defp classify(str) when is_binary(str) do
    lower = String.downcase(str)

    cond do
      Regex.match?(~r/\b404\b/, lower) -> "not_found"
      Regex.match?(~r/\b410\b/, lower) -> "gone"
      Regex.match?(~r/\b429\b/, lower) -> "rate_limited"
      Regex.match?(~r/\b401\b|\b403\b/, lower) -> "auth_error"
      Regex.match?(~r/\b502\b|\b504\b/, lower) -> "bad_gateway"
      Regex.match?(~r/\b5\d{2}\b/, lower) -> "server_error"
      String.contains?(lower, "timeout") -> "timeout"
      String.contains?(lower, "rate limit") -> "rate_limited"
      String.contains?(lower, "not found") -> "not_found"
      true -> "unknown_error"
    end
  end

  defp classify(:unknown), do: "unknown_error"
  defp classify(_), do: "unknown_error"

  # ── Status code → canonical string ────────────────────────────────────

  defp from_status(404), do: "not_found"
  defp from_status(410), do: "gone"
  defp from_status(429), do: "rate_limited"
  defp from_status(401), do: "auth_error"
  defp from_status(403), do: "auth_error"
  defp from_status(502), do: "bad_gateway"
  defp from_status(504), do: "bad_gateway"
  defp from_status(s) when s in 500..599, do: "server_error"
  defp from_status(s) when is_integer(s), do: "http_#{s}"

  # ── Transport error atoms (from Req/Mint/Finch) ────────────────────────

  defp classify_transport(:timeout), do: "timeout"
  defp classify_transport(:connect_timeout), do: "timeout"
  defp classify_transport(:closed), do: "network_error"
  defp classify_transport(:econnrefused), do: "network_error"
  defp classify_transport(:nxdomain), do: "network_error"
  defp classify_transport(:enotconn), do: "network_error"
  defp classify_transport(:ehostunreach), do: "network_error"
  defp classify_transport(_), do: "network_error"
end
