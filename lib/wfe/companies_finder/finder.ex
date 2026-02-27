defmodule Wfe.CompaniesFinder.Finder do
  @moduledoc """
  Discovers companies by searching through archived ATS URLs via CDX.

  This module coordinates the discovery process:
  1. Queries CDX API for each supported ATS platform
  2. Parses URLs to extract company identifiers
  3. Creates new companies in the database (skipping duplicates)
  """

  alias Wfe.CompaniesFinder.{CDXClient, ATSParser}
  alias Wfe.Companies

  require Logger

  @rate_limit_ms 2_000

  @type discovery_result :: %{
          ats: String.t(),
          found: non_neg_integer(),
          created: non_neg_integer(),
          skipped: non_neg_integer(),
          errors: non_neg_integer()
        }

  @type discovery_summary :: %{
          total_found: non_neg_integer(),
          total_created: non_neg_integer(),
          total_skipped: non_neg_integer(),
          total_errors: non_neg_integer(),
          by_ats: [discovery_result()]
        }

  @doc """
  Discover companies from all supported ATS platforms.

  Returns a summary of the discovery process.
  """
  @spec discover_all(keyword()) :: {:ok, discovery_summary()} | {:error, term()}
  def discover_all(opts \\ []) do
    Logger.info("Starting company discovery for all ATS platforms")

    results =
      ATSParser.cdx_patterns()
      |> Enum.map(fn {ats, pattern} ->
        result = discover_for_ats(ats, pattern, opts)

        # Rate limit between ATS queries
        unless opts[:skip_rate_limit] do
          Process.sleep(@rate_limit_ms)
        end

        result
      end)

    summary = build_summary(results)

    Logger.info("""
    Company discovery completed:
      Total found: #{summary.total_found}
      Total created: #{summary.total_created}
      Total skipped: #{summary.total_skipped}
      Total errors: #{summary.total_errors}
    """)

    {:ok, summary}
  end

  @doc """
  Discover companies for a specific ATS platform.
  """
  @spec discover_for_ats(String.t(), String.t(), keyword()) :: discovery_result()
  def discover_for_ats(ats, cdx_pattern, opts \\ []) do
    Logger.info("Discovering companies for ATS: #{ats}")

    case CDXClient.search(cdx_pattern, opts) do
      {:ok, urls} ->
        Logger.info("Found #{length(urls)} URLs for #{ats}")
        process_urls(ats, urls)

      {:error, reason} ->
        Logger.error("Failed to fetch CDX for #{ats}: #{inspect(reason)}")

        %{
          ats: ats,
          found: 0,
          created: 0,
          skipped: 0,
          errors: 1
        }
    end
  end

  defp process_urls(ats, urls) do
    companies = ATSParser.parse_urls(urls)
    Logger.info("Parsed #{length(companies)} unique companies for #{ats}")

    results =
      companies
      |> Enum.map(&create_if_new/1)
      |> Enum.frequencies()

    %{
      ats: ats,
      found: length(companies),
      created: Map.get(results, :created, 0),
      skipped: Map.get(results, :exists, 0),
      errors: Map.get(results, :error, 0)
    }
  end

  defp create_if_new(%{ats: ats, ats_identifier: identifier}) do
    case Companies.find_or_create_company(ats, identifier) do
      {:ok, :created, company} ->
        Logger.debug("Created company: #{company.name} (#{ats}/#{identifier})")
        :created

      {:ok, :exists, _company} ->
        :exists

      {:error, reason} ->
        Logger.warning("Failed to create company #{ats}/#{identifier}: #{inspect(reason)}")
        :error
    end
  end

  defp build_summary(results) do
    %{
      total_found: Enum.sum(Enum.map(results, & &1.found)),
      total_created: Enum.sum(Enum.map(results, & &1.created)),
      total_skipped: Enum.sum(Enum.map(results, & &1.skipped)),
      total_errors: Enum.sum(Enum.map(results, & &1.errors)),
      by_ats: results
    }
  end
end
