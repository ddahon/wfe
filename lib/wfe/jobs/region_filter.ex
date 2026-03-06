defmodule Wfe.Jobs.RegionFilter do
  @moduledoc """
  Post-remote-filter stage. Takes jobs already deemed "remote" and:

    * drops single-country roles
    * drops unclassifiable locations (strict mode — see `@reject_unknown`)
    * writes the canonical region into `:region` on survivors

  The original `:location` is left untouched so the raw ATS string survives
  for debugging.
  """

  alias Wfe.Jobs.RegionClassifier

  # Flip to `false` if you'd rather let unclassifiable locations through and
  # review them downstream. With the optimistic bare-remote default in the
  # classifier, `:unknown` is already rare — mostly multi-country combos
  # that span continents ("Remote - US, UK") or genuinely weird strings.
  @reject_unknown true

  @type reason :: String.t()
  @type rejected :: {map, reason}

  @spec apply([map]) :: {kept :: [map], rejected :: [rejected]}
  def apply(jobs) do
    {kept, rejected} =
      Enum.reduce(jobs, {[], []}, fn job, {keep, reject} ->
        case RegionClassifier.classify(job) do
          {:region, region, normalized} ->
            tagged = job |> Map.put(:region, normalized) |> Map.put(:region_atom, region)
            {[tagged | keep], reject}

          {:country, country} ->
            {keep, [{job, "single_country:#{country}"} | reject]}

          :unknown when @reject_unknown ->
            {keep, [{job, "region_unknown:#{job[:location] || "nil"}"} | reject]}

          :unknown ->
            {[Map.put(job, :region, nil) | keep], reject}
        end
      end)

    {Enum.reverse(kept), Enum.reverse(rejected)}
  end
end
