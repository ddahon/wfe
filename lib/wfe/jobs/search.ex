defmodule Wfe.Jobs.Search do
  @moduledoc """
  Job search & pagination. SQLite-compatible.
  """
  import Ecto.Query
  alias Wfe.Repo
  alias Wfe.Jobs.Job
  alias Wfe.Companies.Company

  @page_size 20

  # Hard cap: never show jobs older than this
  @max_age_days 90

  def page_size, do: @page_size

  @doc """
  Searches jobs by title or company name.
  `max_age_days`: only jobs with `posted_at` newer than this many days ago.
                  nil or > #{@max_age_days} is clamped to #{@max_age_days}.
  Returns `{jobs, total_count}`.
  """
  def search(query_string, page, max_age_days \\ nil)
      when is_binary(query_string) and page >= 1 do
    trimmed = String.trim(query_string)
    age = clamp_age(max_age_days)
    cutoff = DateTime.utc_now() |> DateTime.add(-age, :day) |> DateTime.truncate(:second)

    base = base_query(trimmed, cutoff)

    total =
      base
      |> exclude(:preload)
      |> exclude(:order_by)
      |> exclude(:select)
      |> select([j], count(j.id))
      |> Repo.one()

    jobs =
      base
      |> limit(^@page_size)
      |> offset(^((page - 1) * @page_size))
      |> Repo.all()

    {jobs, total}
  end

  defp clamp_age(nil), do: @max_age_days
  defp clamp_age(d) when d > 0 and d <= @max_age_days, do: d
  defp clamp_age(_), do: @max_age_days

  defp base_query("", cutoff) do
    jobs_since(cutoff)
  end

  defp base_query(term, cutoff) do
    pat = "%#{escape_like(String.downcase(term))}%"

    jobs_since(cutoff)
    |> where(
      [j, c],
      fragment("lower(?) LIKE ? ESCAPE '\\'", j.title, ^pat) or
        fragment("lower(?) LIKE ? ESCAPE '\\'", c.name, ^pat)
    )
  end

  defp jobs_since(cutoff) do
    from j in Job,
      join: c in Company,
      on: c.id == j.company_id,
      where: j.posted_at > ^cutoff,
      order_by: [desc: j.posted_at],
      preload: [company: c]
  end

  defp escape_like(s), do: String.replace(s, ~r/[\\%_]/, "\\\\\\0")
end
