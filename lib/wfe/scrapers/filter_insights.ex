defmodule Wfe.Scrapers.FilterInsights do
  @moduledoc """
  Query helpers for filter audit data.
  """

  import Ecto.Query
  alias Wfe.Repo
  alias Wfe.Scrapers.FilterEvent

  def summary(opts \\ []) do
    base_query(opts)
    |> group_by([e], [e.outcome, e.reason])
    |> select([e], {e.outcome, e.reason, count(e.id)})
    |> Repo.all()
    |> Map.new(fn {outcome, reason, count} -> {{outcome, reason}, count} end)
  end

  def total_counts(opts \\ []) do
    base_query(opts)
    |> group_by([e], e.outcome)
    |> select([e], {e.outcome, count(e.id)})
    |> Repo.all()
    |> Map.new()
  end

  def pass_rate(opts \\ []) do
    stats = total_counts(opts)
    total = (stats["passed"] || 0) + (stats["rejected"] || 0)
    if total == 0, do: 0.0, else: (stats["passed"] || 0) / total
  end

  def by_company(opts \\ []) do
    base_query(opts)
    |> join(:inner, [e], c in assoc(e, :company))
    |> group_by([e, c], [c.id, c.name, c.ats])
    |> select([e, c], %{
      company_id: c.id,
      company_name: c.name,
      ats: c.ats,
      passed: fragment("SUM(CASE WHEN ? = 'passed' THEN 1 ELSE 0 END)", e.outcome),
      rejected: fragment("SUM(CASE WHEN ? = 'rejected' THEN 1 ELSE 0 END)", e.outcome),
      total: count(e.id)
    })
    |> order_by([e, c], desc: count(e.id))
    |> Repo.all()
    |> Enum.map(fn row ->
      Map.put(row, :pass_rate, if(row.total > 0, do: row.passed / row.total, else: 0.0))
    end)
  end

  def by_ats(opts \\ []) do
    base_query(opts)
    |> group_by([e], e.ats)
    |> select([e], %{
      ats: e.ats,
      passed: fragment("SUM(CASE WHEN ? = 'passed' THEN 1 ELSE 0 END)", e.outcome),
      rejected: fragment("SUM(CASE WHEN ? = 'rejected' THEN 1 ELSE 0 END)", e.outcome),
      total: count(e.id)
    })
    |> order_by([e], desc: count(e.id))
    |> Repo.all()
    |> Enum.map(fn row ->
      Map.put(row, :pass_rate, if(row.total > 0, do: row.passed / row.total, else: 0.0))
    end)
  end

  def recent_runs(opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)

    base_query(opts)
    |> group_by([e], [e.run_id, e.ats])
    |> select([e], %{
      run_id: e.run_id,
      ats: e.ats,
      passed: fragment("SUM(CASE WHEN ? = 'passed' THEN 1 ELSE 0 END)", e.outcome),
      rejected: fragment("SUM(CASE WHEN ? = 'rejected' THEN 1 ELSE 0 END)", e.outcome),
      total: count(e.id),
      started_at: min(e.inserted_at)
    })
    |> order_by([e], desc: min(e.inserted_at))
    |> limit(^limit)
    |> Repo.all()
    |> Enum.map(fn row ->
      Map.put(row, :pass_rate, if(row.total > 0, do: row.passed / row.total, else: 0.0))
    end)
  end

  def run_details(run_id) do
    from(e in FilterEvent,
      where: e.run_id == ^run_id,
      join: c in assoc(e, :company),
      select: %{
        id: e.id,
        external_id: e.external_id,
        title: e.title,
        location: e.location,
        link: e.link,
        outcome: e.outcome,
        reason: e.reason,
        ats: e.ats,
        company_name: c.name,
        inserted_at: e.inserted_at
      },
      order_by: [e.outcome, e.reason, e.title]
    )
    |> Repo.all()
  end

  def run_summary(run_id) do
    from(e in FilterEvent,
      where: e.run_id == ^run_id,
      join: c in assoc(e, :company),
      group_by: [e.run_id, e.ats, c.name],
      select: %{
        run_id: e.run_id,
        ats: e.ats,
        company_name: c.name,
        passed: fragment("SUM(CASE WHEN ? = 'passed' THEN 1 ELSE 0 END)", e.outcome),
        rejected: fragment("SUM(CASE WHEN ? = 'rejected' THEN 1 ELSE 0 END)", e.outcome),
        total: count(e.id),
        started_at: min(e.inserted_at)
      }
    )
    |> Repo.one()
  end

  def company_events(company_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)
    outcome = Keyword.get(opts, :outcome)

    query =
      from(e in FilterEvent,
        where: e.company_id == ^company_id,
        order_by: [desc: e.inserted_at],
        limit: ^limit
      )

    query =
      if outcome do
        where(query, [e], e.outcome == ^outcome)
      else
        query
      end

    Repo.all(query)
  end

  def company_summary(company_id) do
    from(e in FilterEvent,
      where: e.company_id == ^company_id,
      join: c in assoc(e, :company),
      group_by: [c.id, c.name, c.ats],
      select: %{
        company_id: c.id,
        company_name: c.name,
        ats: c.ats,
        passed: fragment("SUM(CASE WHEN ? = 'passed' THEN 1 ELSE 0 END)", e.outcome),
        rejected: fragment("SUM(CASE WHEN ? = 'rejected' THEN 1 ELSE 0 END)", e.outcome),
        total: count(e.id),
        first_seen: min(e.inserted_at),
        last_seen: max(e.inserted_at)
      }
    )
    |> Repo.one()
  end

  def rejected(opts \\ []) do
    base_query(opts)
    |> where([e], e.outcome == "rejected")
    |> order_by([e], desc: e.inserted_at)
    |> limit(100)
    |> Repo.all()
  end

  def prune(days \\ 30) do
    cutoff = DateTime.utc_now() |> DateTime.add(-days * 86_400, :second)
    from(e in FilterEvent, where: e.inserted_at < ^cutoff) |> Repo.delete_all()
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
