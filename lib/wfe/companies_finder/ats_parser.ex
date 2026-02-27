defmodule Wfe.CompaniesFinder.ATSParser do
  @moduledoc """
  Parses ATS (Applicant Tracking System) URLs to extract company identifiers.

  Supports:
    * Ashby: jobs.ashbyhq.com/{company}
    * Greenhouse: boards.greenhouse.io/{company}
    * Lever: jobs.lever.co/{company}
    * Workable: apply.workable.com/{company}
    * Recruitee: {company}.recruitee.com
  """

  @type parsed_company :: %{
          ats: String.t(),
          ats_identifier: String.t(),
          source_url: String.t()
        }

  # CDX URL patterns for each ATS
  @ats_configs %{
    "ashby" => %{
      cdx_pattern: "jobs.ashbyhq.com/*",
      url_patterns: [
        ~r{^https?://jobs\.ashbyhq\.com/([a-zA-Z0-9][-a-zA-Z0-9]*[a-zA-Z0-9]|[a-zA-Z0-9])(?:/|$|\?)}i
      ]
    },
    "greenhouse" => %{
      cdx_pattern: "boards.greenhouse.io/*",
      url_patterns: [
        ~r{^https?://boards\.greenhouse\.io/([a-zA-Z0-9][-a-zA-Z0-9]*[a-zA-Z0-9]|[a-zA-Z0-9])(?:/|$|\?)}i
      ]
    },
    "lever" => %{
      cdx_pattern: "jobs.lever.co/*",
      url_patterns: [
        ~r{^https?://jobs\.lever\.co/([a-zA-Z0-9][-a-zA-Z0-9]*[a-zA-Z0-9]|[a-zA-Z0-9])(?:/|$|\?)}i
      ]
    },
    "workable" => %{
      cdx_pattern: "apply.workable.com/*",
      url_patterns: [
        ~r{^https?://apply\.workable\.com/([a-zA-Z0-9][-a-zA-Z0-9]*[a-zA-Z0-9]|[a-zA-Z0-9])(?:/|$|\?)}i
      ]
    },
    "recruitee" => %{
      cdx_pattern: "*.recruitee.com/*",
      url_patterns: [
        ~r{^https?://([a-zA-Z0-9][-a-zA-Z0-9]*[a-zA-Z0-9]|[a-zA-Z0-9])\.recruitee\.com(?:/|$|\?)}i
      ]
    }
  }

  # Identifiers that are not actual companies
  @blacklist MapSet.new(~w(
    embed embedded api static assets js css images img
    favicon robots sitemap cdn www mail ftp
    login logout auth oauth callback webhook webhooks
    test demo example sample sandbox staging dev
    admin administrator system root null undefined
    careers jobs job apply application applications
    search filter filters sort page pages
    health healthcheck ping status
    v1 v2 v3 api-docs docs documentation
    widget widgets iframe iframes
    app help support blog career
  ))

  @doc """
  Returns CDX search patterns for all supported ATS platforms.
  """
  @spec cdx_patterns() :: %{String.t() => String.t()}
  def cdx_patterns do
    Map.new(@ats_configs, fn {ats, config} -> {ats, config.cdx_pattern} end)
  end

  @doc """
  Returns the list of supported ATS names.
  """
  @spec supported_ats() :: [String.t()]
  def supported_ats, do: Map.keys(@ats_configs)

  @doc """
  Parse a URL and extract ATS and company identifier.

  Returns `nil` if the URL doesn't match any known ATS pattern
  or if the identifier is blacklisted.
  """
  @spec parse_url(String.t()) :: parsed_company() | nil
  def parse_url(url) when is_binary(url) do
    url = String.trim(url)

    Enum.find_value(@ats_configs, fn {ats, config} ->
      Enum.find_value(config.url_patterns, fn pattern ->
        case Regex.run(pattern, url) do
          [_, identifier] ->
            identifier = String.downcase(identifier)

            if valid_identifier?(identifier) do
              %{
                ats: ats,
                ats_identifier: identifier,
                source_url: url
              }
            end

          _ ->
            nil
        end
      end)
    end)
  end

  def parse_url(_), do: nil

  @doc """
  Parse multiple URLs and return unique, valid companies.
  """
  @spec parse_urls([String.t()]) :: [parsed_company()]
  def parse_urls(urls) when is_list(urls) do
    urls
    |> Stream.map(&parse_url/1)
    |> Stream.reject(&is_nil/1)
    |> Enum.uniq_by(&{&1.ats, &1.ats_identifier})
  end

  defp valid_identifier?(identifier) do
    not MapSet.member?(@blacklist, identifier) and
      String.length(identifier) >= 2 and
      String.length(identifier) <= 100 and
      not String.starts_with?(identifier, "-") and
      not String.ends_with?(identifier, "-") and
      not String.contains?(identifier, "--")
  end
end
