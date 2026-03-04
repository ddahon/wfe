defmodule Wfe.Scrapers.FilterInsights do
  @moduledoc """
  Query helpers for filter audit data. Use in dashboards, LiveViews,
  or `mix`-based reports.
  """

  import Ecto.Query
  alias Wfe.Repo
  alias Wfe.Scrapers.FilterEvent

  @doc """
  Summary counts grouped by outcome and reason.

      %{
        {"passed", "ats_hint_remote"} => 42,
        {"rejected", "heuristic_reject"} => 108,
        ...
      }
  """
  def summary(opts \\ []) do
    base_query(opts)
    |> group_by([e], [e.outcome, e.reason])
    |> select([e], {e.outcome, e.reason, count(e.id)})
    |> Repo.all()
    |> Map.new(fn {outcome, reason, count} -> {{outcome, reason}, count} end)
  end

  @doc """
  Pass rate as a float between 0.0 and 1.0.
  """
  def pass_rate(opts \\ []) do
    stats =
      base_query(opts)
      |> group_by([e], e.outcome)
      |> select([e], {e.outcome, count(e.id)})
      |> Repo.all()
      |> Map.new()

    total = (stats["passed"] || 0) + (stats["rejected"] || 0)
    if total == 0, do: 0.0, else: (stats["passed"] || 0) / total
  end

  @doc """
  Per-company breakdown: `[%{company_id, company_name, passed, rejected, total, pass_rate}]`
  """
  def by_company(opts \\ []) do
    base_query(opts)
    |> join(:inner, [e], c in assoc(e, :company))
    |> group_by([e, c], [c.id, c.name])
    |> select([e, c], %{
      company_id: c.id,
      company_name: c.name,
      passed: fragment("SUM(CASE WHEN ? = 'passed' THEN 1 ELSE 0 END)", e.outcome),
      rejected: fragment("SUM(CASE WHEN ? = 'rejected' THEN 1 ELSE 0 END)", e.outcome),
      total: count(e.id)
    })
    |> Repo.all()
    |> Enum.map(fn row ->
      Map.put(row, :pass_rate, if(row.total > 0, do: row.passed / row.total, else: 0.0))
    end)
  end

  @doc """
  All rejected jobs for a specific run or company. Useful for spot-checking
  false negatives.
  """
  def rejected(opts \\ []) do
    base_query(opts)
    |> where([e], e.outcome == "rejected")
    |> order_by([e], desc: e.inserted_at)
    |> Repo.all()
  end

  @doc """
  All events for a specific run, ordered chronologically.
  """
  def run_details(run_id) do
    from(e in FilterEvent, where: e.run_id == ^run_id, order_by: e.inserted_at)
    |> Repo.all()
  end

  @doc """
  Prune events older than `days` (default 30). Call from a periodic job.
  """
  def prune(days \\ 30) do
    cutoff = DateTime.utc_now() |> DateTime.add(-days * 86_400, :second)

    from(e in FilterEvent, where: e.inserted_at < ^cutoff)
    |> Repo.delete_all()
  end

  # --- Private --------------------------------------------------------------

  defp base_query(opts) do
    query = from(e in FilterEvent)

    query
    |> maybe_filter(:company_id, opts[:company_id])
    |> maybe_filter(:ats, opts[:ats])
    |> maybe_filter(:run_id, opts[:run_id])
    |> maybe_since(opts[:since])
  end

  defp maybe_filter(query, _field, nil), do: query
  defp maybe_filter(query, :company_id, id), do: where(query, [e], e.company_id == ^id)
  defp maybe_filter(query, :ats, ats), do: where(query, [e], e.ats == ^ats)
  defp maybe_filter(query, :run_id, rid), do: where(query, [e], e.run_id == ^rid)

  defp maybe_since(query, nil), do: query
  defp maybe_since(query, %DateTime{} = dt), do: where(query, [e], e.inserted_at >= ^dt)
end
