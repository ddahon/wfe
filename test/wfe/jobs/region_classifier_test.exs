defmodule Wfe.Jobs.RegionClassifierTest do
  use ExUnit.Case, async: true

  alias Wfe.Jobs.RegionClassifier, as: C

  # Shorthand: classify location-only
  defp loc(s), do: C.classify(s, nil, nil)

  describe "explicit region keywords" do
    test "EMEA variants" do
      assert {:region, :emea, "EMEA"} = loc("Remote - EMEA")
      assert {:region, :emea, "EMEA"} = loc("EMEA (Remote)")
      assert {:region, :emea, "EMEA"} = loc("Remote — Europe, Middle East & Africa")
      assert {:region, :emea, "EMEA"} = loc("Africa / Europe - Remote")
    end

    test "APAC variants" do
      assert {:region, :apac, "APAC"} = loc("Remote APAC")
      assert {:region, :apac, "APAC"} = loc("Asia-Pacific")
      assert {:region, :apac, "APAC"} = loc("Asia Pac - Remote")
      assert {:region, :apac, "APAC"} = loc("Remote (ANZ)")
      assert {:region, :apac, "APAC"} = loc("Australia & NZ - Remote")
    end

    test "Americas vs North America vs LATAM" do
      assert {:region, :americas, "Americas"} = loc("Remote - Americas")
      assert {:region, :americas, "Americas"} = loc("The Americas (Remote)")
      assert {:region, :north_america, "North America"} = loc("Remote - North America")
      assert {:region, :north_america, "North America"} = loc("Remote - NA")
      assert {:region, :north_america, "North America"} = loc("US / Canada Remote")
      assert {:region, :latam, "LATAM"} = loc("Remote LATAM")
      assert {:region, :latam, "LATAM"} = loc("Latin America — Remote")
      assert {:region, :latam, "LATAM"} = loc("South America")
    end

    test "Europe variants" do
      assert {:region, :europe, "Europe"} = loc("Remote - Europe")
      assert {:region, :europe, "Europe"} = loc("European Remote")
      assert {:region, :europe, "Europe"} = loc("Remote (EU)")
      assert {:region, :europe, "Europe"} = loc("Remote - EEA")
      assert {:region, :europe, "Europe"} = loc("DACH - Remote")
      assert {:region, :europe, "Europe"} = loc("Remote Nordics")
      assert {:region, :europe, "Europe"} = loc("Benelux (Remote)")
    end

    test "EU delimiter guard — no false positives inside words" do
      # "Eugene" contains "eu" but not as a standalone token
      refute match?({:region, :europe, _}, loc("Eugene, Oregon"))
      # but standalone EU passes
      assert {:region, :europe, _} = loc("Remote / EU")
    end

    test "broadest region wins on overlap" do
      # Mentions both Europe and EMEA — EMEA is broader
      assert {:region, :emea, "EMEA"} = loc("Remote - Europe / EMEA timezone")
      # Americas beats North America
      assert {:region, :americas, _} = loc("North America & the Americas")
    end
  end

  describe "global keywords" do
    test "common phrasings" do
      assert {:region, :global, "Global"} = loc("Worldwide")
      assert {:region, :global, "Global"} = loc("Remote (Worldwide)")
      assert {:region, :global, "Global"} = loc("Anywhere")
      assert {:region, :global, "Global"} = loc("Remote - Global")
      assert {:region, :global, "Global"} = loc("Fully Distributed")
      assert {:region, :global, "Global"} = loc("Any location")
      assert {:region, :global, "Global"} = loc("🌍 Remote")
    end

    test "global + country qualifier → unknown (conflicting signals)" do
      # We don't want to reject these outright — "preferred" is soft — but
      # we also can't confidently call them global. Flag for review.
      assert :unknown = loc("Worldwide (US timezone preferred)")
      assert :unknown = loc("Global - must be based in Germany")
    end
  end

  describe "single-country rejection" do
    test "explicit country names" do
      assert {:country, "Germany"} = loc("Remote - Germany")
      assert {:country, "United Kingdom"} = loc("Remote, UK")
      assert {:country, "United Kingdom"} = loc("Remote (United Kingdom)")
      assert {:country, "Brazil"} = loc("Remote Brasil")
      assert {:country, "Australia"} = loc("Australia - Remote")
      assert {:country, "Netherlands"} = loc("Remote — Netherlands")
    end

    test "bare US with geographic context" do
      assert {:country, "United States"} = loc("Remote US")
      assert {:country, "United States"} = loc("US-based, Remote")
      assert {:country, "United States"} = loc("Remote (US only)")
      assert {:country, "United States"} = loc("Remote - US residents")
    end

    test "dotted country codes normalise" do
      assert {:country, "United States"} = loc("Remote — U.S.A.")
      assert {:country, "United Kingdom"} = loc("Remote (U.K.)")
    end

    test "US state implies US" do
      assert {:country, "United States"} = loc("Remote - California")
      assert {:country, "United States"} = loc("Remote (Texas)")
      assert {:country, "United States"} = loc("New York - Remote")
    end

    test "adjective forms" do
      assert {:country, "Germany"} = loc("Remote — German residents only")
      assert {:country, "France"} = loc("Remote for French candidates")
    end
  end

  describe "multi-country region inference" do
    test "same leaf region" do
      assert {:region, :europe, _} = loc("Remote - Spain, Portugal")
      assert {:region, :europe, _} = loc("Remote: Germany / France / Netherlands")
      assert {:region, :latam, _} = loc("Remote — Brazil, Argentina, Chile")
      assert {:region, :apac, _} = loc("Remote - Japan & Singapore")
    end

    test "different leaves, shared parent" do
      # Europe + (Israel→emea) share parent EMEA
      assert {:region, :emea, _} = loc("Remote - Germany, Israel")
      # NA + LATAM share parent Americas
      assert {:region, :americas, _} = loc("Remote - USA, Brazil")
      assert {:region, :americas, _} = loc("Remote: Canada / Mexico / Colombia")
    end

    test "no common ancestor → unknown" do
      assert :unknown = loc("Remote - USA, UK")
      assert :unknown = loc("Remote — Germany, Japan")
      assert :unknown = loc("Remote - Australia, Canada")
    end

    test "region keyword still wins over country inference" do
      # Explicit EMEA keyword beats the Germany+France inference — same
      # answer here, but confirms precedence.
      assert {:region, :emea, _} = loc("Remote EMEA - Germany, France preferred")
    end
  end

  describe "timezone hints" do
    test "only fires with timezone context word" do
      assert {:region, :europe, _} = loc("Remote (CET timezone)")
      assert {:region, :north_america, _} = loc("Remote - PST working hours")
      assert {:region, :apac, _} = loc("Remote — AEST tz")
    end

    test "timezone abbreviation without guard word → no region match" do
      # "Remote EST" without "timezone"/"tz"/"hours" — too risky, the guard
      # keeps us from matching "est" substrings. Result falls through to
      # :unknown (not bare-remote, not a country).
      assert :unknown = loc("Remote EST")
    end
  end

  describe "bare remote" do
    test "defaults to global when no other signal" do
      assert {:region, :global, _} = loc("Remote")
      assert {:region, :global, _} = loc("Fully Remote")
      assert {:region, :global, _} = loc("100% Remote")
      assert {:region, :global, _} = loc("Remote-first")
      assert {:region, :global, _} = loc("Distributed")
    end

    test "picks up region from description when location is bare" do
      assert {:region, :emea, _} =
               C.classify("Remote", "Senior Engineer", "We're hiring across EMEA for this role.")

      assert {:region, :global, _} =
               C.classify("Remote", nil, "Work from anywhere in the world.")
    end

    test "does NOT reject based on country mentioned in description" do
      # HQ mentions shouldn't kill the job. This is the asymmetry in
      # classify_bare_remote — positive signals only.
      assert {:region, :global, _} =
               C.classify("Remote", nil, "Our headquarters is in Berlin, Germany.")
    end
  end

  describe "edge cases" do
    test "nil and empty" do
      assert :unknown = C.classify(nil, nil, nil)
      assert :unknown = loc("")
    end

    test "whitespace-only" do
      assert :unknown = loc("   ")
    end

    test "unrecognised gibberish" do
      assert :unknown = loc("Hybrid - 3 days/week")
      assert :unknown = loc("Flexible")
    end

    test "map interface with atom and string keys" do
      assert {:region, :emea, _} = C.classify(%{location: "Remote EMEA"})
      assert {:region, :emea, _} = C.classify(%{"location" => "Remote EMEA"})
    end
  end
end
