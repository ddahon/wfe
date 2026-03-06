defmodule Wfe.Scrapers.FilterInsights do
  @moduledoc """
  Query helpers for filter audit data.
  """

  import Ecto.Query
  alias Wfe.Repo
  alias Wfe.Scrapers.FilterEvent
  alias Wfe.Companies.Company

  @page_size 25

  @sortable_fields ~w(total passed rejected pass_rate started_at)

  def page_size, do: @page_size

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
    page = Keyword.get(opts, :page, 1)
    sort_by = Keyword.get(opts, :sort_by, :started_at)
    sort_dir = Keyword.get(opts, :sort_dir, :desc)
    search = Keyword.get(opts, :search)

    query =
      base_query(opts)
      |> join(:inner, [e], c in assoc(e, :company))
      |> maybe_search(search)
      |> group_by([e, c], [e.run_id, e.ats, c.name, c.id])
      |> select([e, c], %{
        run_id: e.run_id,
        ats: e.ats,
        company_name: c.name,
        company_id: c.id,
        passed: fragment("SUM(CASE WHEN ? = 'passed' THEN 1 ELSE 0 END)", e.outcome),
        rejected: fragment("SUM(CASE WHEN ? = 'rejected' THEN 1 ELSE 0 END)", e.outcome),
        total: count(e.id),
        started_at: min(e.inserted_at)
      })
      |> apply_sort(sort_by, sort_dir)

    total_query =
      base_query(opts)
      |> join(:inner, [e], c in assoc(e, :company))
      |> maybe_search(search)
      |> select([e, c], fragment("COUNT(DISTINCT ?)", e.run_id))

    total = Repo.one(total_query) || 0

    runs =
      query
      |> limit(^@page_size)
      |> offset(^(@page_size * (page - 1)))
      |> Repo.all()
      |> Enum.map(fn row ->
        Map.put(row, :pass_rate, if(row.total > 0, do: row.passed / row.total, else: 0.0))
      end)

    {runs, total}
  end

  def run_details(run_id, opts \\ []) do
    page = Keyword.get(opts, :page, 1)

    query =
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

    total = Repo.aggregate(from(e in FilterEvent, where: e.run_id == ^run_id), :count) || 0

    events =
      query
      |> limit(^@page_size)
      |> offset(^(@page_size * (page - 1)))
      |> Repo.all()

    {events, total}
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
    page = Keyword.get(opts, :page, 1)
    outcome = Keyword.get(opts, :outcome)

    query =
      from(e in FilterEvent,
        where: e.company_id == ^company_id,
        order_by: [desc: e.inserted_at]
      )

    query = if outcome, do: where(query, [e], e.outcome == ^outcome), else: query

    total = Repo.aggregate(query, :count) || 0

    events =
      query
      |> limit(^@page_size)
      |> offset(^(@page_size * (page - 1)))
      |> Repo.all()

    {events, total}
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

  # Search uses the joined company table (binding index [e, c])
  defp maybe_search(query, nil), do: query
  defp maybe_search(query, ""), do: query

  defp maybe_search(query, search) do
    pattern = "%" <> String.replace(search, "%", "\\%") <> "%"
    where(query, [e, c], fragment("? LIKE ? ESCAPE '\\'", c.name, ^pattern))
  end

  # Sort with validated field names
  defp apply_sort(query, sort_by, sort_dir)
       when sort_by in @sortable_fields or is_atom(sort_by) do
    field = if is_binary(sort_by), do: String.to_existing_atom(sort_by), else: sort_by

    case {field, sort_dir} do
      {:total, :asc} ->
        order_by(query, [e, c], asc: count(e.id))

      {:total, _} ->
        order_by(query, [e, c], desc: count(e.id))

      {:passed, :asc} ->
        order_by(query, [e, c],
          asc: fragment("SUM(CASE WHEN ? = 'passed' THEN 1 ELSE 0 END)", e.outcome)
        )

      {:passed, _} ->
        order_by(query, [e, c],
          desc: fragment("SUM(CASE WHEN ? = 'passed' THEN 1 ELSE 0 END)", e.outcome)
        )

      {:rejected, :asc} ->
        order_by(query, [e, c],
          asc: fragment("SUM(CASE WHEN ? = 'rejected' THEN 1 ELSE 0 END)", e.outcome)
        )

      {:rejected, _} ->
        order_by(query, [e, c],
          desc: fragment("SUM(CASE WHEN ? = 'rejected' THEN 1 ELSE 0 END)", e.outcome)
        )

      {:pass_rate, :asc} ->
        order_by(query, [e, c],
          asc:
            fragment(
              "CAST(SUM(CASE WHEN ? = 'passed' THEN 1 ELSE 0 END) AS FLOAT) / MAX(COUNT(?), 1)",
              e.outcome,
              e.id
            )
        )

      {:pass_rate, _} ->
        order_by(query, [e, c],
          desc:
            fragment(
              "CAST(SUM(CASE WHEN ? = 'passed' THEN 1 ELSE 0 END) AS FLOAT) / MAX(COUNT(?), 1)",
              e.outcome,
              e.id
            )
        )

      {:started_at, :asc} ->
        order_by(query, [e, c], asc: min(e.inserted_at))

      {:started_at, _} ->
        order_by(query, [e, c], desc: min(e.inserted_at))

      _ ->
        order_by(query, [e, c], desc: min(e.inserted_at))
    end
  end

  defp apply_sort(query, _, _), do: order_by(query, [e, c], desc: min(e.inserted_at))

  @doc """
  Returns a breakdown of failed scrape jobs grouped by error reason.
  """
  def failed_jobs_by_error(opts \\ []) do
    since = Keyword.get(opts, :since)
    ats = Keyword.get(opts, :ats)

    query =
      from c in Company,
        where: not is_nil(c.last_scrape_error),
        group_by: c.last_scrape_error,
        select: %{
          error: c.last_scrape_error,
          count: count(c.id)
        },
        order_by: [desc: count(c.id)]

    query =
      if since do
        from c in query, where: c.updated_at >= ^since
      else
        query
      end

    query =
      if ats && ats != "" do
        from c in query, where: c.ats == ^ats
      else
        query
      end

    Repo.all(query)
  end

  def total_failed_count(opts \\ []) do
    since = Keyword.get(opts, :since)
    ats = Keyword.get(opts, :ats)

    query =
      from c in Company,
        where: not is_nil(c.last_scrape_error),
        select: count(c.id)

    query =
      if since do
        from c in query, where: c.updated_at >= ^since
      else
        query
      end

    query =
      if ats && ats != "" do
        from c in query, where: c.ats == ^ats
      else
        query
      end

    Repo.one(query) || 0
  end
end
