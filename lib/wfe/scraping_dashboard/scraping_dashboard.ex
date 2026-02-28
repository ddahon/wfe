defmodule Wfe.ScrapingDashboard do
  @moduledoc """
  Context for querying Oban jobs with associated company data
  for debugging scraping issues.
  """

  import Ecto.Query
  alias Wfe.Repo
  alias Wfe.Companies

  @doc """
  Lists Oban jobs with optional filters.

  Options:
    - :state - filter by job state (e.g., "available", "completed", "discarded", "retryable")
    - :queue - filter by queue name
    - :worker - filter by worker module name
    - :company_id - filter by company_id in args
    - :has_errors - if true, only jobs with non-empty errors
    - :search - free text search across worker, queue, errors
    - :limit - max results (default 50)
    - :offset - pagination offset (default 0)
  """
  def list_jobs(opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    offset = Keyword.get(opts, :offset, 0)

    query =
      "oban_jobs"
      |> select([j], %{
        id: j.id,
        state: j.state,
        queue: j.queue,
        worker: j.worker,
        args: j.args,
        errors: j.errors,
        attempt: j.attempt,
        max_attempts: j.max_attempts,
        inserted_at: j.inserted_at,
        scheduled_at: j.scheduled_at,
        attempted_at: j.attempted_at,
        completed_at: j.completed_at,
        cancelled_at: j.cancelled_at,
        discarded_at: j.discarded_at
      })
      |> apply_filters(opts)
      |> order_by([j], desc: j.inserted_at)
      |> limit(^limit)
      |> offset(^offset)

    jobs = Repo.all(query)

    # Batch-load associated companies
    company_ids =
      jobs
      |> Enum.map(&extract_company_id/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    companies_map = load_companies_map(company_ids)

    Enum.map(jobs, fn job ->
      company_id = extract_company_id(job)
      company = if company_id, do: Map.get(companies_map, company_id)
      Map.put(job, :company, company)
    end)
  end

  @doc """
  Counts jobs matching the given filters (same options as list_jobs, minus :limit/:offset).
  """
  def count_jobs(opts \\ []) do
    "oban_jobs"
    |> apply_filters(opts)
    |> select([j], count(j.id))
    |> Repo.one()
  end

  @doc """
  Returns a single job by ID with its associated company.
  """
  def get_job(id) do
    job =
      "oban_jobs"
      |> select([j], %{
        id: j.id,
        state: j.state,
        queue: j.queue,
        worker: j.worker,
        args: j.args,
        meta: j.meta,
        tags: j.tags,
        errors: j.errors,
        attempt: j.attempt,
        max_attempts: j.max_attempts,
        priority: j.priority,
        inserted_at: j.inserted_at,
        scheduled_at: j.scheduled_at,
        attempted_at: j.attempted_at,
        attempted_by: j.attempted_by,
        completed_at: j.completed_at,
        cancelled_at: j.cancelled_at,
        discarded_at: j.discarded_at
      })
      |> where([j], j.id == ^id)
      |> Repo.one()

    case job do
      nil ->
        nil

      job ->
        company_id = extract_company_id(job)

        company =
          if company_id do
            try do
              Companies.get_company!(company_id)
            rescue
              Ecto.NoResultsError -> nil
            end
          end

        Map.put(job, :company, company)
    end
  end

  @doc """
  Returns distinct states present in the oban_jobs table, for filter dropdowns.
  """
  def list_states do
    "oban_jobs"
    |> select([j], j.state)
    |> distinct(true)
    |> order_by([j], j.state)
    |> Repo.all()
  end

  @doc """
  Returns distinct queues present in the oban_jobs table, for filter dropdowns.
  """
  def list_queues do
    "oban_jobs"
    |> select([j], j.queue)
    |> distinct(true)
    |> order_by([j], j.queue)
    |> Repo.all()
  end

  @doc """
  Returns distinct workers present in the oban_jobs table, for filter dropdowns.
  """
  def list_workers do
    "oban_jobs"
    |> select([j], j.worker)
    |> distinct(true)
    |> order_by([j], j.worker)
    |> Repo.all()
  end

  # --- Private ---

  defp apply_filters(query, opts) do
    query
    |> filter_by_state(Keyword.get(opts, :state))
    |> filter_by_queue(Keyword.get(opts, :queue))
    |> filter_by_worker(Keyword.get(opts, :worker))
    |> filter_by_company_id(Keyword.get(opts, :company_id))
    |> filter_by_has_errors(Keyword.get(opts, :has_errors))
    |> filter_by_search(Keyword.get(opts, :search))
  end

  defp filter_by_state(query, nil), do: query
  defp filter_by_state(query, ""), do: query
  defp filter_by_state(query, state), do: where(query, [j], j.state == ^state)

  defp filter_by_queue(query, nil), do: query
  defp filter_by_queue(query, ""), do: query
  defp filter_by_queue(query, queue), do: where(query, [j], j.queue == ^queue)

  defp filter_by_worker(query, nil), do: query
  defp filter_by_worker(query, ""), do: query
  defp filter_by_worker(query, worker), do: where(query, [j], j.worker == ^worker)

  defp filter_by_company_id(query, nil), do: query
  defp filter_by_company_id(query, ""), do: query

  defp filter_by_company_id(query, company_id) do
    # SQLite JSON extraction: args is stored as JSON string
    where(query, [j], fragment("json_extract(?, '$.company_id') = ?", j.args, ^company_id))
  end

  defp filter_by_has_errors(query, true) do
    where(query, [j], fragment("json_array_length(?) > 0", j.errors))
  end

  defp filter_by_has_errors(query, _), do: query

  defp filter_by_search(query, nil), do: query
  defp filter_by_search(query, ""), do: query

  defp filter_by_search(query, search) do
    pattern = "%#{search}%"

    where(
      query,
      [j],
      like(j.worker, ^pattern) or
        like(j.queue, ^pattern) or
        like(type(j.errors, :string), ^pattern) or
        like(type(j.args, :string), ^pattern)
    )
  end

  defp extract_company_id(%{args: args}) when is_map(args) do
    Map.get(args, "company_id")
  end

  defp extract_company_id(%{args: args}) when is_binary(args) do
    case Jason.decode(args) do
      {:ok, decoded} -> Map.get(decoded, "company_id")
      _ -> nil
    end
  end

  defp extract_company_id(_), do: nil

  defp load_companies_map([]), do: %{}

  defp load_companies_map(company_ids) do
    import Ecto.Query
    alias Wfe.Companies.Company

    Company
    |> where([c], c.id in ^company_ids)
    |> Repo.all()
    |> Map.new(fn c -> {c.id, c} end)
  end
end
