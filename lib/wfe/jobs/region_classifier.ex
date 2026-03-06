defmodule Wfe.Jobs.RegionClassifier do
  @moduledoc """
  Classifies remote job locations into broad hiring regions.

  ## Results

    * `{:region, atom, normalized_string}` — location spans a recognised
      region (or the whole world). Keep the job; store `normalized_string`
      in `jobs.region`.
    * `{:country, country_name}` — location is restricted to a single
      country. Reject.
    * `:unknown` — conflicting or unrecognised signals. Caller decides
      (default policy: reject, see `RegionFilter`).

  ## Classification order (first match wins)

    1. Explicit region keyword (EMEA, APAC, …) in the location string.
    2. Global keyword (worldwide, anywhere, …) **without** a country qualifier.
    3. Multiple countries that all belong to one region → infer the region.
       E.g. "Remote - Spain, Portugal" → Europe.
    4. Exactly one country → single-country restriction.
    5. Bare "Remote" / "Fully Remote" with no geo qualifier → peek at
       title/description for positive signals, else default to Global.
    6. Anything else → `:unknown`.

  The country list is intentionally non-exhaustive — it covers what actually
  shows up in ATS feeds. Expand it when the audit log surfaces misses.
  """

  require Logger

  @type region ::
          :global | :emea | :apac | :americas | :north_america | :latam | :europe

  @type result ::
          {:region, region, String.t()}
          | {:country, String.t()}
          | :unknown

  # ──────────────────────────────────────────────────────────────────────────
  # Region display names (what ends up in jobs.region)
  # ──────────────────────────────────────────────────────────────────────────

  @region_names %{
    global: "Global",
    emea: "EMEA",
    apac: "APAC",
    americas: "Americas",
    north_america: "North America",
    latam: "LATAM",
    europe: "Europe"
  }

  @doc "Canonical display string for a region atom."
  def region_name(region), do: Map.fetch!(@region_names, region)

  @doc "All supported region atoms."
  def regions, do: Map.keys(@region_names)

  # ──────────────────────────────────────────────────────────────────────────
  # Region keyword patterns
  #
  # Ordered roughly by specificity. We collect ALL matches and pick the
  # broadest — "Europe, Middle East & Africa" should resolve to EMEA, not
  # stop at the first "Europe" hit.
  # ──────────────────────────────────────────────────────────────────────────

  @region_patterns [
    # EMEA ─────────────────────────────────────────────────────────────────
    {~r/\bemea\b/iu, :emea},
    {~r/\beurope\b.*\b(middle\s*east|mena|africa)\b/iu, :emea},
    {~r/\b(middle\s*east|mena|africa)\b.*\beurope\b/iu, :emea},

    # APAC ─────────────────────────────────────────────────────────────────
    {~r/\bapac\b/iu, :apac},
    {~r/\bapj\b/iu, :apac},
    {~r/\bjapac\b/iu, :apac},
    {~r/\basia[\s-]*pac(ific)?\b/iu, :apac},
    {~r/\baus(tralia)?\s*(\/|&|and|\+)\s*nz\b/iu, :apac},
    {~r/\banz\b/iu, :apac},

    # LATAM ────────────────────────────────────────────────────────────────
    {~r/\blatam\b/iu, :latam},
    {~r/\blatin\s*america\b/iu, :latam},
    {~r/\bsouth\s*america\b/iu, :latam},
    {~r/\bcentral\s*america\b/iu, :latam},

    # North America ────────────────────────────────────────────────────────
    # Bare "NA" is too ambiguous (N/A, sodium). Require the full phrase or
    # a "Remote - NA" style context.
    {~r/\bnorth\s*america\b/iu, :north_america},
    {~r/\bnoram\b/iu, :north_america},
    {~r/\bremote\b[^a-z]{0,5}\bna\b/iu, :north_america},
    {~r/\bus\s*(\/|&|and|\+|,)\s*canada\b/iu, :north_america},
    {~r/\bcanada\s*(\/|&|and|\+|,)\s*us\b/iu, :north_america},

    # Americas (both continents) ───────────────────────────────────────────
    {~r/\bthe\s+americas\b/iu, :americas},
    # Negative lookbehinds keep "North Americas"/"Latin Americas" typos from
    # landing here. Fixed-width so PCRE is happy.
    {~r/(?<!north\s)(?<!south\s)(?<!latin\s)\bamericas\b/iu, :americas},
    {~r/\bamer\b/iu, :americas},

    # Europe (narrower than EMEA) ──────────────────────────────────────────
    {~r/\beurope(an)?\b/iu, :europe},
    {~r/\beea\b/iu, :europe},
    # "EU" needs delimiter guards — can't use \b alone without catching
    # "eu" inside words on some inputs. Match standalone token only.
    {~r/(?:^|[\s,\-(\/])eu(?:$|[\s,\-)\/])/iu, :europe},
    {~r/\bcee\b/iu, :europe},
    {~r/\bdach\b/iu, :europe},
    {~r/\bnordics?\b/iu, :europe},
    {~r/\bbenelux\b/iu, :europe},
    {~r/\biberia\b/iu, :europe}
  ]

  # Broader regions win when multiple patterns fire on the same string.
  @region_breadth %{
    global: 100,
    emea: 50,
    apac: 50,
    americas: 50,
    europe: 30,
    north_america: 30,
    latam: 30
  }

  # Parent region for multi-country inference. Countries that map to
  # different sub-regions but share a parent still yield a classification.
  #   Germany (:europe) + Israel (:emea) → parents both :emea → EMEA ✓
  #   US (:north_america) + Brazil (:latam) → both :americas → Americas ✓
  #   Germany (:europe) + Japan (:apac) → :emea ≠ :apac → unknown ✗
  @region_parent %{
    europe: :emea,
    north_america: :americas,
    latam: :americas
  }

  # ──────────────────────────────────────────────────────────────────────────
  # Global patterns
  # ──────────────────────────────────────────────────────────────────────────

  @global_patterns [
    ~r/\bworld[\s-]*wide\b/iu,
    ~r/\bglobal(ly)?\b/iu,
    ~r/\banywhere\b/iu,
    ~r/\bany\s+(location|country|region|time\s*zone)\b/iu,
    ~r/\ball\s+(locations?|countries|regions|time\s*zones?)\b/iu,
    ~r/\bno\s+location\s+(restriction|requirement)/iu,
    ~r/\bfully\s+distributed\b/iu,
    ~r/\binternational\b/iu,
    # Yes, people really do put globe emoji in location fields.
    ~r/🌍|🌎|🌏|🌐/u,
    # "Earth" shows up more than you'd expect.
    ~r/\bearth\b/iu
  ]

  # ──────────────────────────────────────────────────────────────────────────
  # Countries
  #
  # Single source of truth: {canonical_name, region, [aliases]}.
  # Everything else (regexes, region map) is derived from this at compile
  # time.
  #
  # Alias notes:
  #   - Periods are stripped in normalize/1, so "U.S." → "US" automatically.
  #   - Adjective forms ("german", "french") catch "German residents only".
  #   - Bare "US" is handled separately — it's also an English pronoun.
  # ──────────────────────────────────────────────────────────────────────────

  @countries [
    # ── North America ────────────────────────────────────────────────────
    {"United States", :north_america,
     ~w(usa) ++
       [
         "united states",
         "united states of america",
         "us only",
         "us-only",
         "us based",
         "us-based",
         "us residents",
         "us citizens"
       ]},
    {"Canada", :north_america, ~w(canada canadian)},

    # ── LATAM ────────────────────────────────────────────────────────────
    # Mexico: geographically NA, but job posters overwhelmingly group it
    # with LATAM. Follow the convention, not the map.
    {"Mexico", :latam, ~w(mexico méxico mexican)},
    {"Brazil", :latam, ~w(brazil brasil brazilian)},
    {"Argentina", :latam, ~w(argentina argentinian argentine)},
    {"Chile", :latam, ~w(chile chilean)},
    {"Colombia", :latam, ~w(colombia colombian)},
    {"Peru", :latam, ~w(peru perú peruvian)},
    {"Uruguay", :latam, ~w(uruguay uruguayan)},
    {"Costa Rica", :latam, ["costa rica", "costa rican"]},

    # ── Europe ───────────────────────────────────────────────────────────
    {"United Kingdom", :europe,
     ~w(uk gb) ++
       ["united kingdom", "great britain", "britain", "british", "england", "scotland", "wales"]},
    {"Ireland", :europe, ~w(ireland irish éire)},
    {"Germany", :europe, ~w(germany deutschland german)},
    {"France", :europe, ~w(france french)},
    {"Spain", :europe, ~w(spain españa spanish)},
    {"Portugal", :europe, ~w(portugal português portuguese)},
    {"Italy", :europe, ~w(italy italia italian)},
    {"Netherlands", :europe, ~w(netherlands nederland holland dutch)},
    {"Belgium", :europe, ~w(belgium belgië belgique belgian)},
    {"Luxembourg", :europe, ~w(luxembourg)},
    {"Switzerland", :europe, ~w(switzerland schweiz suisse svizzera swiss)},
    {"Austria", :europe, ~w(austria österreich austrian)},
    {"Poland", :europe, ~w(poland polska polish)},
    {"Czech Republic", :europe, ["czech republic", "czechia", "czech"]},
    {"Slovakia", :europe, ~w(slovakia slovak)},
    {"Hungary", :europe, ~w(hungary magyar hungarian)},
    {"Romania", :europe, ~w(romania românia romanian)},
    {"Bulgaria", :europe, ~w(bulgaria bulgarian)},
    {"Greece", :europe, ~w(greece greek ελλάδα)},
    {"Sweden", :europe, ~w(sweden sverige swedish)},
    {"Denmark", :europe, ~w(denmark danmark danish)},
    {"Norway", :europe, ~w(norway norge norwegian)},
    {"Finland", :europe, ~w(finland suomi finnish)},
    {"Estonia", :europe, ~w(estonia eesti estonian)},
    {"Latvia", :europe, ~w(latvia latvian)},
    {"Lithuania", :europe, ~w(lithuania lithuanian)},
    {"Croatia", :europe, ~w(croatia hrvatska croatian)},
    {"Slovenia", :europe, ~w(slovenia slovenian)},
    {"Serbia", :europe, ~w(serbia serbian)},
    {"Ukraine", :europe, ~w(ukraine україна ukrainian)},
    {"Cyprus", :europe, ~w(cyprus)},
    {"Malta", :europe, ~w(malta maltese)},

    # ── Middle East & Africa (map straight to :emea — we don't surface
    #    ME or Africa as standalone regions since postings rarely use them)
    {"Israel", :emea, ~w(israel israeli)},
    {"UAE", :emea, ["uae", "united arab emirates", "emirati", "dubai", "abu dhabi"]},
    {"Saudi Arabia", :emea, ["saudi arabia", "saudi", "ksa"]},
    {"Turkey", :emea, ~w(turkey türkiye turkish)},
    {"Egypt", :emea, ~w(egypt egyptian)},
    {"South Africa", :emea, ["south africa", "south african"]},
    {"Nigeria", :emea, ~w(nigeria nigerian)},
    {"Kenya", :emea, ~w(kenya kenyan)},
    {"Morocco", :emea, ~w(morocco moroccan)},
    {"Tunisia", :emea, ~w(tunisia tunisian)},
    {"Ghana", :emea, ~w(ghana ghanaian)},

    # ── APAC ─────────────────────────────────────────────────────────────
    {"Australia", :apac, ~w(australia australian aussie)},
    {"New Zealand", :apac, ["new zealand", "kiwi"] ++ ~w(nz)},
    {"Japan", :apac, ~w(japan japanese 日本)},
    {"South Korea", :apac, ["south korea", "korea", "korean"]},
    {"China", :apac, ~w(china chinese prc 中国)},
    {"Taiwan", :apac, ~w(taiwan taiwanese)},
    {"Hong Kong", :apac, ["hong kong", "hongkong"] ++ ~w(hk)},
    {"Singapore", :apac, ~w(singapore singaporean sg)},
    {"India", :apac, ~w(india indian)},
    {"Philippines", :apac, ~w(philippines filipino ph)},
    {"Indonesia", :apac, ~w(indonesia indonesian)},
    {"Vietnam", :apac, ~w(vietnam vietnamese)},
    {"Thailand", :apac, ~w(thailand thai)},
    {"Malaysia", :apac, ~w(malaysia malaysian)},
    {"Pakistan", :apac, ~w(pakistan pakistani)},
    {"Bangladesh", :apac, ~w(bangladesh bangladeshi)}
  ]

  # Derived lookups ────────────────────────────────────────────────────────

  @country_to_region Map.new(@countries, fn {name, region, _} -> {name, region} end)

  # One compiled regex per country. ~60 regexes × short location strings is
  # well under a millisecond per job — not worth collapsing into a
  # mega-regex yet.
  @country_regexes Enum.map(@countries, fn {name, _region, aliases} ->
                     pattern =
                       aliases
                       |> Enum.map(&Regex.escape/1)
                       |> Enum.join("|")

                     {name, Regex.compile!("\\b(?:#{pattern})\\b", "iu")}
                   end)

  # Bare "US" — the two-letter token is ambiguous (English pronoun). Only
  # treat it as the country when it sits in a geographic context: "Remote
  # US", "US-based", "US residents", "US timezone", etc.
  @us_token_re ~r/(?:^|[\s,\-(\/])us(?:$|[\s,\-)\/])/iu
  @us_context_re ~r/\b(remote|based|only|residents?|citizens?|time\s*zones?|tz|located|eligible|authorized|authorised|work\s+in)\b/iu

  # US states — seeing one means the job is US-restricted even if "United
  # States" isn't spelled out. "Georgia" is ambiguous (country vs state);
  # in remote-job feeds it's almost always the state.
  @us_states (~w(
               alabama alaska arizona arkansas california colorado connecticut
               delaware florida georgia hawaii idaho illinois indiana iowa
               kansas kentucky louisiana maine maryland massachusetts michigan
               minnesota mississippi missouri montana nebraska nevada ohio
               oklahoma oregon pennsylvania tennessee texas utah vermont
               virginia washington wisconsin wyoming
             ) ++
               [
                 "new hampshire",
                 "new jersey",
                 "new mexico",
                 "new york",
                 "north carolina",
                 "north dakota",
                 "rhode island",
                 "south carolina",
                 "south dakota",
                 "west virginia",
                 "district of columbia"
               ])
             |> Enum.map(&Regex.escape/1)
             |> Enum.join("|")
             |> then(&Regex.compile!("\\b(?:#{&1})\\b", "iu"))

  # ──────────────────────────────────────────────────────────────────────────
  # Timezone → region hints
  #
  # Only consulted when the word "timezone"/"tz"/"hours" appears — otherwise
  # "est" could collide with superlatives and "ct" with abbreviations.
  # A timezone spans many countries, so it's a legitimate region signal.
  # ──────────────────────────────────────────────────────────────────────────

  @tz_guard_re ~r/\b(time\s*zones?|timezone|tz|working\s+hours|overlap)\b|utc[+\-]|gmt[+\-]/iu

  @timezone_regions [
    {~r/\b(cet|cest|eet|eest|wet|west|bst)\b/iu, :europe},
    {~r/\b(est|edt|pst|pdt|cst|cdt|mst|mdt)\b/iu, :north_america},
    {~r/\b(et|pt|ct|mt)\s*(time\s*zone|timezone|tz|hours)/iu, :north_america},
    {~r/\b(aest|aedt|awst|acst|nzst|nzdt)\b/iu, :apac},
    {~r/\b(jst|kst|sgt|hkt|ict|pht)\b/iu, :apac},
    {~r/\b(brt|art|clt|cot|pet)\b/iu, :latam}
  ]

  # ──────────────────────────────────────────────────────────────────────────
  # Bare-remote patterns
  #
  # Location strings that say "remote" and nothing else. These are the
  # trickiest: many companies write "Remote" and mean "remote in our
  # country". We peek at title/description for a positive region/global
  # signal; absent that, default to Global. See `bare_remote_default/0` to
  # change the policy.
  # ──────────────────────────────────────────────────────────────────────────

  @bare_remote_patterns [
    ~r/^\s*remote\s*$/iu,
    ~r/^\s*fully\s+remote\s*$/iu,
    ~r/^\s*100\s*%\s*remote\s*$/iu,
    ~r/^\s*remote[\s\-–—]*(first|only|ok|friendly)\s*$/iu,
    ~r/^\s*distributed\s*$/iu,
    ~r/^\s*wfh\s*$/iu,
    ~r/^\s*work\s+from\s+home\s*$/iu
  ]

  # Cap how much description text we scan. The geo constraint, if present,
  # is almost always in the first few paragraphs.
  @fallback_scan_limit 2_000

  # ══════════════════════════════════════════════════════════════════════════
  # Public API
  # ══════════════════════════════════════════════════════════════════════════

  @doc """
  Classify a parsed job map. Looks at `:location` first, falls back to
  `:title` + `:description` for bare-remote cases.
  """
  @spec classify(map) :: result
  def classify(job) when is_map(job) do
    classify(
      field(job, :location),
      field(job, :title),
      field(job, :description)
    )
  end

  @doc """
  Classify from raw strings. `title`/`description` are only consulted when
  `location` is a bare-remote string with no geographic qualifier.
  """
  @spec classify(String.t() | nil, String.t() | nil, String.t() | nil) :: result
  def classify(location, title, description)

  def classify(nil, _title, _desc), do: :unknown
  def classify("", _title, _desc), do: :unknown

  def classify(location, title, description) when is_binary(location) do
    loc = normalize(location)

    cond do
      # 1. Explicit region keyword — highest confidence.
      region = match_region(loc) ->
        {:region, region, @region_names[region]}

      # 2. Global keyword. If a country ALSO appears ("Worldwide, US
      #    preferred"), signals conflict — punt to :unknown rather than
      #    guessing wrong in either direction.
      match_global?(loc) ->
        if has_country?(loc), do: :unknown, else: {:region, :global, "Global"}

      # 3. Several countries that share a region → infer it.
      #    "Remote - Spain, Portugal" → Europe.
      region = infer_region_from_countries(loc) ->
        {:region, region, @region_names[region]}

      # 4. Exactly one country → single-country restriction.
      country = single_country(loc) ->
        {:country, country}

      # 5. Just "Remote" — check title/description for a positive signal.
      bare_remote?(loc) ->
        classify_bare_remote(title, description)

      # 6. Something we don't understand.
      true ->
        :unknown
    end
  end

  # ══════════════════════════════════════════════════════════════════════════
  # Stage 1 — Region keywords
  # ══════════════════════════════════════════════════════════════════════════

  defp match_region(text) do
    matches =
      @region_patterns
      |> Enum.filter(fn {re, _} -> Regex.match?(re, text) end)
      |> Enum.map(&elem(&1, 1))
      |> Enum.uniq()

    case matches do
      [] -> match_timezone_region(text)
      [single] -> single
      multiple -> Enum.max_by(multiple, &@region_breadth[&1])
    end
  end

  defp match_timezone_region(text) do
    # Guard keeps short tokens like "et"/"pt"/"ct" from firing on noise.
    if Regex.match?(@tz_guard_re, text) do
      Enum.find_value(@timezone_regions, fn {re, region} ->
        if Regex.match?(re, text), do: region
      end)
    end
  end

  # ══════════════════════════════════════════════════════════════════════════
  # Stage 2 — Global keywords
  # ══════════════════════════════════════════════════════════════════════════

  defp match_global?(text) do
    Enum.any?(@global_patterns, &Regex.match?(&1, text))
  end

  # ══════════════════════════════════════════════════════════════════════════
  # Stage 3 & 4 — Country detection
  # ══════════════════════════════════════════════════════════════════════════

  defp has_country?(text), do: matched_countries(text) != []

  defp single_country(text) do
    case matched_countries(text) do
      [only] -> only
      _ -> nil
    end
  end

  defp infer_region_from_countries(text) do
    case matched_countries(text) do
      countries when length(countries) >= 2 ->
        countries
        |> Enum.map(&@country_to_region[&1])
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq()
        |> common_region()

      _ ->
        nil
    end
  end

  # All countries sit in the same leaf region → that region.
  # Different leaves but same parent → the parent.
  # Otherwise → no common ground.
  defp common_region([]), do: nil
  defp common_region([single]), do: single

  defp common_region(regions) do
    regions
    |> Enum.map(&(@region_parent[&1] || &1))
    |> Enum.uniq()
    |> case do
      [parent] -> parent
      _ -> nil
    end
  end

  defp matched_countries(text) do
    from_list =
      @country_regexes
      |> Enum.filter(fn {_name, re} -> Regex.match?(re, text) end)
      |> Enum.map(&elem(&1, 0))

    from_list
    |> maybe_add_us(text)
    |> maybe_add_us_from_state(text)
    |> Enum.uniq()
  end

  defp maybe_add_us(countries, text) do
    if "United States" in countries do
      countries
    else
      if Regex.match?(@us_token_re, text) and Regex.match?(@us_context_re, text) do
        ["United States" | countries]
      else
        countries
      end
    end
  end

  defp maybe_add_us_from_state(countries, text) do
    if "United States" not in countries and Regex.match?(@us_states, text) do
      ["United States" | countries]
    else
      countries
    end
  end

  # ══════════════════════════════════════════════════════════════════════════
  # Stage 5 — Bare remote
  # ══════════════════════════════════════════════════════════════════════════

  defp bare_remote?(text) do
    Enum.any?(@bare_remote_patterns, &Regex.match?(&1, text))
  end

  # Deliberately asymmetric: we look for POSITIVE region/global signals in
  # title+description, but NOT for country restrictions. Descriptions mention
  # countries constantly in non-restrictive ways ("our HQ is in Berlin",
  # "clients across Germany and France") — treating those as restrictions
  # would reject most of the catalog.
  #
  # If bare-remote false-positives become a problem, the surgical fix is
  # snippet extraction: regex for phrases like "must be located in" /
  # "authorized to work in" and run country detection only on the trailing
  # ~50 chars. Left out of v1 to keep this readable.
  defp classify_bare_remote(title, description) do
    fallback =
      [title, description]
      |> Enum.filter(&is_binary/1)
      |> Enum.join(" ")
      |> String.slice(0, @fallback_scan_limit)

    cond do
      fallback == "" ->
        bare_remote_default()

      region = match_region(fallback) ->
        {:region, region, @region_names[region]}

      match_global?(fallback) ->
        {:region, :global, "Global"}

      true ->
        bare_remote_default()
    end
  end

  # Policy knob. Optimistic by default: bare "Remote" → Global.
  # Flip to `:unknown` if your audit shows too many country-restricted jobs
  # slipping through under this assumption.
  defp bare_remote_default, do: {:region, :global, "Global"}

  # ══════════════════════════════════════════════════════════════════════════
  # Helpers
  # ══════════════════════════════════════════════════════════════════════════

  # Strip periods so "U.S." / "U.K." collapse into "US" / "UK" and hit the
  # existing aliases without us maintaining dotted variants everywhere.
  defp normalize(str) do
    str
    |> String.replace(".", "")
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
  end

  defp field(map, key), do: map[key] || map[to_string(key)]
end
