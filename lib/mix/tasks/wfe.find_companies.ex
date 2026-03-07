defmodule Mix.Tasks.Wfe.FindCompanies do
  @shortdoc "Discovers companies from ATS platforms via CDX archive search"

  @moduledoc """
  Discovers companies from ATS platforms by searching CDX (Common Crawl / Wayback
  Machine) for known ATS URL patterns, then persists any new companies to the
  database.

  ## Usage

      mix wfe.find_companies [options]

  ## Options

      --ats NAME         Only run discovery for a specific ATS (can be repeated)
      --dry-run          Parse and print companies without writing to the database
      --skip-rate-limit  Remove the 2 s pause between ATS queries (useful in CI)
      --quiet            Suppress the per-ATS progress table; only print the summary

  ## Examples

      # Discover from all supported ATS platforms
      mix wfe.find_companies

      # Discover only from Greenhouse and Lever
      mix wfe.find_companies --ats greenhouse --ats lever

      # See what would be found without touching the database
      mix wfe.find_companies --dry-run

      # Fast run without rate-limit pauses, minimal output
      mix wfe.find_companies --skip-rate-limit --quiet
  """

  use Mix.Task

  alias Wfe.CompaniesFinder.{ATSParser, CDXClient, Finder}

  # Make sure Ecto repos and the app are available
  @requirements ["app.start"]

  @switches [
    ats: [:string, :keep],
    dry_run: :boolean,
    skip_rate_limit: :boolean,
    quiet: :boolean
  ]

  @aliases [
    a: :ats,
    d: :dry_run,
    q: :quiet
  ]

  @impl Mix.Task
  def run(argv) do
    {opts, _rest, invalid} = OptionParser.parse(argv, strict: @switches, aliases: @aliases)

    unless Enum.empty?(invalid) do
      invalid_flags = Enum.map_join(invalid, ", ", fn {flag, _} -> flag end)
      Mix.raise("Unknown option(s): #{invalid_flags}\n\n#{@moduledoc}")
    end

    dry_run? = Keyword.get(opts, :dry_run, false)
    quiet? = Keyword.get(opts, :quiet, false)
    skip_rate_limit? = Keyword.get(opts, :skip_rate_limit, false)
    requested_ats = opts |> Keyword.get_values(:ats) |> Enum.map(&String.downcase/1)

    validate_ats_names!(requested_ats)

    finder_opts = [
      dry_run: dry_run?,
      skip_rate_limit: skip_rate_limit?
    ]

    if dry_run? do
      Mix.shell().info([:yellow, "** Dry-run mode – nothing will be written to the database **"])
    end

    Mix.shell().info([:bright, "\nWfe Company Discovery"])
    Mix.shell().info(String.duplicate("─", 60))

    result =
      if Enum.empty?(requested_ats) do
        run_all(finder_opts, quiet?)
      else
        run_for_ats(requested_ats, finder_opts, quiet?)
      end

    case result do
      {:ok, summary} ->
        unless quiet?, do: print_per_ats_table(summary.by_ats)
        print_summary(summary)
        maybe_exit_nonzero(summary)

      {:error, reason} ->
        Mix.shell().error("Discovery failed: #{inspect(reason)}")
        exit({:shutdown, 1})
    end
  end

  # ---------------------------------------------------------------------------
  # Runners
  # ---------------------------------------------------------------------------

  defp run_all(opts, quiet?) do
    unless quiet? do
      Mix.shell().info("Searching all #{map_size(ATSParser.cdx_patterns())} ATS platforms…\n")
    end

    Finder.discover_all(opts)
  end

  defp run_for_ats(ats_names, opts, quiet?) do
    unless quiet? do
      Mix.shell().info("Searching #{length(ats_names)} ATS platform(s): #{Enum.join(ats_names, ", ")}\n")
    end

    patterns = ATSParser.cdx_patterns()

    results =
      ats_names
      |> Enum.with_index(1)
      |> Enum.map(fn {ats, idx} ->
        pattern = Map.fetch!(patterns, ats)
        result = Finder.discover_for_ats(ats, pattern, opts)

        if !opts[:skip_rate_limit] && idx < length(ats_names) do
          Process.sleep(2_000)
        end

        result
      end)

    summary = %{
      total_found: Enum.sum(Enum.map(results, & &1.found)),
      total_created: Enum.sum(Enum.map(results, & &1.created)),
      total_skipped: Enum.sum(Enum.map(results, & &1.skipped)),
      total_errors: Enum.sum(Enum.map(results, & &1.errors)),
      by_ats: results
    }

    {:ok, summary}
  end

  # ---------------------------------------------------------------------------
  # Validation
  # ---------------------------------------------------------------------------

  defp validate_ats_names!([]), do: :ok

  defp validate_ats_names!(names) do
    supported = ATSParser.supported_ats()

    unknown = Enum.reject(names, &(&1 in supported))

    unless Enum.empty?(unknown) do
      Mix.raise("""
      Unknown ATS name(s): #{Enum.join(unknown, ", ")}

      Supported platforms:
        #{Enum.join(Enum.sort(supported), "\n  ")}
      """)
    end
  end

  # ---------------------------------------------------------------------------
  # Output helpers
  # ---------------------------------------------------------------------------

  defp print_per_ats_table(results) do
    Mix.shell().info("\nResults by ATS platform:")
    Mix.shell().info(String.duplicate("─", 60))

    header = "  #{pad("ATS", 20)} #{pad("Found", 8)} #{pad("Created", 9)} #{pad("Skipped", 9)} #{pad("Errors", 7)}"
    Mix.shell().info([:bright, header])
    Mix.shell().info(String.duplicate("─", 60))

    Enum.each(results, fn r ->
      error_color = if r.errors > 0, do: :red, else: :normal

      line =
        "  #{pad(r.ats, 20)} #{pad(r.found, 8)} #{pad(r.created, 9)} #{pad(r.skipped, 9)}"

      errors_part = " #{pad(r.errors, 7)}"

      Mix.shell().info([line, [error_color, errors_part]])
    end)

    Mix.shell().info(String.duplicate("─", 60))
  end

  defp print_summary(summary) do
    Mix.shell().info("\nSummary:")

    Mix.shell().info([
      :green,
      "  Created : #{summary.total_created}"
    ])

    Mix.shell().info("  Skipped : #{summary.total_skipped}")

    if summary.total_errors > 0 do
      Mix.shell().info([:red, "  Errors  : #{summary.total_errors}"])
    else
      Mix.shell().info("  Errors  : #{summary.total_errors}")
    end

    Mix.shell().info([:bright, "  Total   : #{summary.total_found}"])
    Mix.shell().info("")
  end

  # Exit with a non-zero code if every single ATS failed, so CI pipelines
  # can detect a fully broken run.  Partial failures (some ATS worked, some
  # didn't) are treated as warnings, not hard failures.
  defp maybe_exit_nonzero(%{by_ats: by_ats} = summary) do
    all_failed? =
      Enum.all?(by_ats, fn r -> r.errors > 0 and r.found == 0 end)

    if all_failed? and summary.total_errors > 0 do
      Mix.shell().error("All ATS queries failed.")
      exit({:shutdown, 1})
    end
  end

  defp pad(value, width) when is_integer(value), do: pad(to_string(value), width)

  defp pad(value, width) when is_binary(value) do
    String.pad_trailing(value, width)
  end
end
