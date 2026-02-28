defmodule Wfe.ScrapingDashboard.ScrapingDashboardLive do
  use Phoenix.LiveView

  alias Wfe.ScrapingDashboard

  @per_page 50

  @impl true
  def mount(_params, _session, socket) do
    states = ScrapingDashboard.list_states()
    queues = ScrapingDashboard.list_queues()
    workers = ScrapingDashboard.list_workers()

    socket =
      socket
      |> assign(
        page_title: "Scraping Dashboard",
        filters: default_filters(),
        states: states,
        queues: queues,
        workers: workers,
        page: 0,
        selected_job: nil
      )
      |> load_jobs()

    {:ok, socket}
  end

  @impl true
  def handle_event("filter", params, socket) do
    filters = %{
      state: Map.get(params, "state", ""),
      queue: Map.get(params, "queue", ""),
      worker: Map.get(params, "worker", ""),
      search: Map.get(params, "search", ""),
      has_errors: Map.get(params, "has_errors", "false") == "true"
    }

    socket =
      socket
      |> assign(filters: filters, page: 0, selected_job: nil)
      |> load_jobs()

    {:noreply, socket}
  end

  @impl true
  def handle_event("clear_filters", _params, socket) do
    socket =
      socket
      |> assign(filters: default_filters(), page: 0, selected_job: nil)
      |> load_jobs()

    {:noreply, socket}
  end

  @impl true
  def handle_event("next_page", _params, socket) do
    socket =
      socket
      |> assign(page: socket.assigns.page + 1)
      |> load_jobs()

    {:noreply, socket}
  end

  @impl true
  def handle_event("prev_page", _params, socket) do
    page = max(socket.assigns.page - 1, 0)

    socket =
      socket
      |> assign(page: page)
      |> load_jobs()

    {:noreply, socket}
  end

  @impl true
  def handle_event("select_job", %{"id" => id}, socket) do
    job = ScrapingDashboard.get_job(String.to_integer(id))
    {:noreply, assign(socket, selected_job: job)}
  end

  @impl true
  def handle_event("close_detail", _params, socket) do
    {:noreply, assign(socket, selected_job: nil)}
  end

  defp load_jobs(socket) do
    %{filters: filters, page: page} = socket.assigns

    opts =
      [
        limit: @per_page,
        offset: page * @per_page
      ]
      |> maybe_put(:state, filters.state)
      |> maybe_put(:queue, filters.queue)
      |> maybe_put(:worker, filters.worker)
      |> maybe_put(:search, filters.search)
      |> maybe_put_bool(:has_errors, filters.has_errors)

    jobs = ScrapingDashboard.list_jobs(opts)
    total = ScrapingDashboard.count_jobs(opts)
    total_pages = max(ceil(total / @per_page), 1)

    assign(socket, jobs: jobs, total: total, total_pages: total_pages)
  end

  defp maybe_put(opts, _key, ""), do: opts
  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  defp maybe_put_bool(opts, _key, false), do: opts
  defp maybe_put_bool(opts, key, true), do: Keyword.put(opts, key, true)

  defp default_filters do
    %{state: "", queue: "", worker: "", search: "", has_errors: false}
  end

  defp state_badge_class(state) do
    case state do
      "completed" -> "bg-green-100 text-green-800"
      "available" -> "bg-blue-100 text-blue-800"
      "executing" -> "bg-yellow-100 text-yellow-800"
      "scheduled" -> "bg-purple-100 text-purple-800"
      "retryable" -> "bg-orange-100 text-orange-800"
      "discarded" -> "bg-red-100 text-red-800"
      "cancelled" -> "bg-gray-100 text-gray-800"
      _ -> "bg-gray-100 text-gray-600"
    end
  end

  defp format_datetime(nil), do: "—"

  defp format_datetime(dt) when is_binary(dt) do
    dt
  end

  defp format_datetime(%DateTime{} = dt) do
    Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S UTC")
  end

  defp format_datetime(%NaiveDateTime{} = dt) do
    Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S")
  end

  defp company_name(%{company: %{name: name}}), do: name
  defp company_name(%{company: nil}), do: "Unknown"
  defp company_name(_), do: "—"

  defp company_ats(%{company: %{ats: ats}}), do: ats
  defp company_ats(_), do: "—"

  defp company_scrape_status(%{company: %{scrape_status: s}}), do: s || "—"
  defp company_scrape_status(_), do: "—"

  defp format_errors(errors) when is_list(errors) and length(errors) > 0 do
    errors
  end

  defp format_errors(errors) when is_binary(errors) do
    case Jason.decode(errors) do
      {:ok, list} when is_list(list) and length(list) > 0 -> list
      _ -> []
    end
  end

  defp format_errors(_), do: []

  defp short_worker(worker) when is_binary(worker) do
    worker
    |> String.split(".")
    |> List.last()
  end

  defp short_worker(w), do: w

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-50">
      <div class="max-w-7xl mx-auto px-4 py-6">
        <!-- Header -->
        <div class="mb-6">
          <h1 class="text-2xl font-bold text-gray-900">Scraping Dashboard</h1>
          <p class="text-sm text-gray-500 mt-1">
            {@total} jobs found
          </p>
        </div>
        
    <!-- Filters -->
        <form phx-change="filter" phx-submit="filter" class="bg-white rounded-lg shadow p-4 mb-6">
          <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-5 gap-4">
            <div>
              <label class="block text-xs font-medium text-gray-700 mb-1">Search</label>
              <input
                type="text"
                name="search"
                value={@filters.search}
                placeholder="Search workers, errors, args..."
                phx-debounce="300"
                class="w-full rounded-md border-gray-300 shadow-sm text-sm focus:ring-indigo-500 focus:border-indigo-500"
              />
            </div>
            <div>
              <label class="block text-xs font-medium text-gray-700 mb-1">State</label>
              <select
                name="state"
                class="w-full rounded-md border-gray-300 shadow-sm text-sm focus:ring-indigo-500 focus:border-indigo-500"
              >
                <option value="">All states</option>
                <%= for state <- @states do %>
                  <option value={state} selected={@filters.state == state}>{state}</option>
                <% end %>
              </select>
            </div>
            <div>
              <label class="block text-xs font-medium text-gray-700 mb-1">Queue</label>
              <select
                name="queue"
                class="w-full rounded-md border-gray-300 shadow-sm text-sm focus:ring-indigo-500 focus:border-indigo-500"
              >
                <option value="">All queues</option>
                <%= for queue <- @queues do %>
                  <option value={queue} selected={@filters.queue == queue}>{queue}</option>
                <% end %>
              </select>
            </div>
            <div>
              <label class="block text-xs font-medium text-gray-700 mb-1">Worker</label>
              <select
                name="worker"
                class="w-full rounded-md border-gray-300 shadow-sm text-sm focus:ring-indigo-500 focus:border-indigo-500"
              >
                <option value="">All workers</option>
                <%= for worker <- @workers do %>
                  <option value={worker} selected={@filters.worker == worker}>
                    {short_worker(worker)}
                  </option>
                <% end %>
              </select>
            </div>
            <div class="flex items-end gap-2">
              <label class="flex items-center gap-2 text-sm">
                <input
                  type="checkbox"
                  name="has_errors"
                  value="true"
                  checked={@filters.has_errors}
                  class="rounded border-gray-300 text-indigo-600 focus:ring-indigo-500"
                />
                <span class="text-gray-700">Errors only</span>
              </label>
              <button
                type="button"
                phx-click="clear_filters"
                class="ml-auto text-xs text-indigo-600 hover:text-indigo-800 underline"
              >
                Clear
              </button>
            </div>
          </div>
        </form>

        <div class="flex gap-6">
          <!-- Jobs Table -->
          <div class={if @selected_job, do: "w-1/2", else: "w-full"}>
            <div class="bg-white rounded-lg shadow overflow-hidden">
              <table class="min-w-full divide-y divide-gray-200">
                <thead class="bg-gray-50">
                  <tr>
                    <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                      ID
                    </th>
                    <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                      State
                    </th>
                    <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                      Worker
                    </th>
                    <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                      Company
                    </th>
                    <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                      Attempts
                    </th>
                    <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                      Errors
                    </th>
                    <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                      Inserted
                    </th>
                  </tr>
                </thead>
                <tbody class="divide-y divide-gray-200">
                  <%= for job <- @jobs do %>
                    <tr
                      phx-click="select_job"
                      phx-value-id={job.id}
                      class={"cursor-pointer hover:bg-indigo-50 transition #{if @selected_job && @selected_job.id == job.id, do: "bg-indigo-50", else: ""}"}
                    >
                      <td class="px-4 py-3 text-sm text-gray-900 font-mono">{job.id}</td>
                      <td class="px-4 py-3">
                        <span class={"inline-flex px-2 py-0.5 rounded-full text-xs font-medium #{state_badge_class(job.state)}"}>
                          {job.state}
                        </span>
                      </td>
                      <td class="px-4 py-3 text-sm text-gray-700">
                        {short_worker(job.worker)}
                      </td>
                      <td class="px-4 py-3 text-sm text-gray-700">
                        <div>{company_name(job)}</div>
                        <div class="text-xs text-gray-400">{company_ats(job)}</div>
                      </td>
                      <td class="px-4 py-3 text-sm text-gray-500">
                        {job.attempt}/{job.max_attempts}
                      </td>
                      <td class="px-4 py-3">
                        <% errors = format_errors(job.errors) %>
                        <%= if length(errors) > 0 do %>
                          <span class="inline-flex px-2 py-0.5 rounded-full text-xs font-medium bg-red-100 text-red-800">
                            {length(errors)} error(s)
                          </span>
                        <% else %>
                          <span class="text-xs text-gray-400">—</span>
                        <% end %>
                      </td>
                      <td class="px-4 py-3 text-xs text-gray-500">
                        {format_datetime(job.inserted_at)}
                      </td>
                    </tr>
                  <% end %>

                  <%= if @jobs == [] do %>
                    <tr>
                      <td colspan="7" class="px-4 py-12 text-center text-gray-400 text-sm">
                        No jobs match your filters.
                      </td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
              
    <!-- Pagination -->
              <div class="bg-gray-50 px-4 py-3 flex items-center justify-between border-t border-gray-200">
                <span class="text-sm text-gray-700">
                  Page {@page + 1} of {@total_pages}
                </span>
                <div class="flex gap-2">
                  <button
                    phx-click="prev_page"
                    disabled={@page == 0}
                    class="px-3 py-1 text-sm rounded bg-white border border-gray-300 text-gray-700 hover:bg-gray-50 disabled:opacity-50 disabled:cursor-not-allowed"
                  >
                    ← Prev
                  </button>
                  <button
                    phx-click="next_page"
                    disabled={@page + 1 >= @total_pages}
                    class="px-3 py-1 text-sm rounded bg-white border border-gray-300 text-gray-700 hover:bg-gray-50 disabled:opacity-50 disabled:cursor-not-allowed"
                  >
                    Next →
                  </button>
                </div>
              </div>
            </div>
          </div>
          
    <!-- Detail Panel -->
          <%= if @selected_job do %>
            <div class="w-1/2">
              <div class="bg-white rounded-lg shadow p-6 sticky top-6">
                <div class="flex items-center justify-between mb-4">
                  <h2 class="text-lg font-semibold text-gray-900">
                    Job #{@selected_job.id}
                  </h2>
                  <button
                    phx-click="close_detail"
                    class="text-gray-400 hover:text-gray-600 text-xl leading-none"
                  >
                    ×
                  </button>
                </div>
                
    <!-- Job Info -->
                <div class="space-y-3 mb-6">
                  <div class="grid grid-cols-2 gap-3 text-sm">
                    <div>
                      <span class="text-gray-500">State</span>
                      <div>
                        <span class={"inline-flex px-2 py-0.5 rounded-full text-xs font-medium #{state_badge_class(@selected_job.state)}"}>
                          {@selected_job.state}
                        </span>
                      </div>
                    </div>
                    <div>
                      <span class="text-gray-500">Queue</span>
                      <div class="font-medium">{@selected_job.queue}</div>
                    </div>
                    <div>
                      <span class="text-gray-500">Worker</span>
                      <div class="font-medium font-mono text-xs">{@selected_job.worker}</div>
                    </div>
                    <div>
                      <span class="text-gray-500">Attempts</span>
                      <div class="font-medium">
                        {@selected_job.attempt}/{@selected_job.max_attempts}
                      </div>
                    </div>
                    <div>
                      <span class="text-gray-500">Priority</span>
                      <div class="font-medium">{@selected_job.priority}</div>
                    </div>
                    <div>
                      <span class="text-gray-500">Inserted</span>
                      <div class="font-medium text-xs">
                        {format_datetime(@selected_job.inserted_at)}
                      </div>
                    </div>
                    <div>
                      <span class="text-gray-500">Scheduled</span>
                      <div class="font-medium text-xs">
                        {format_datetime(@selected_job.scheduled_at)}
                      </div>
                    </div>
                    <div>
                      <span class="text-gray-500">Attempted</span>
                      <div class="font-medium text-xs">
                        {format_datetime(@selected_job.attempted_at)}
                      </div>
                    </div>
                    <div>
                      <span class="text-gray-500">Completed</span>
                      <div class="font-medium text-xs">
                        {format_datetime(@selected_job.completed_at)}
                      </div>
                    </div>
                    <div>
                      <span class="text-gray-500">Discarded</span>
                      <div class="font-medium text-xs">
                        {format_datetime(@selected_job.discarded_at)}
                      </div>
                    </div>
                  </div>
                </div>
                
    <!-- Company Info -->
                <div class="border-t pt-4 mb-4">
                  <h3 class="text-sm font-semibold text-gray-700 mb-2">Company</h3>
                  <%= if @selected_job.company do %>
                    <div class="bg-gray-50 rounded p-3 text-sm space-y-1">
                      <div>
                        <span class="text-gray-500">Name:</span>
                        <span class="font-medium">{@selected_job.company.name}</span>
                      </div>
                      <div>
                        <span class="text-gray-500">ATS:</span>
                        <span class="font-medium">{@selected_job.company.ats}</span>
                      </div>
                      <div>
                        <span class="text-gray-500">ATS Identifier:</span>
                        <span class="font-mono text-xs">
                          {@selected_job.company.ats_identifier}
                        </span>
                      </div>
                      <div>
                        <span class="text-gray-500">Scrape Status:</span>
                        <span class="font-medium">
                          {@selected_job.company.scrape_status || "—"}
                        </span>
                      </div>
                      <%= if @selected_job.company.scrape_error do %>
                        <div>
                          <span class="text-gray-500">Scrape Error:</span>
                          <span class="text-red-600 text-xs">
                            {@selected_job.company.scrape_error}
                          </span>
                        </div>
                      <% end %>
                      <div>
                        <span class="text-gray-500">Last Scraped:</span>
                        <span class="text-xs">
                          {format_datetime(@selected_job.company.last_scraped_at)}
                        </span>
                      </div>
                    </div>
                  <% else %>
                    <p class="text-sm text-gray-400 italic">Company not found</p>
                  <% end %>
                </div>
                
    <!-- Args -->
                <div class="border-t pt-4 mb-4">
                  <h3 class="text-sm font-semibold text-gray-700 mb-2">Args</h3>
                  <pre class="bg-gray-900 text-green-400 rounded p-3 text-xs overflow-x-auto"><%= format_json(@selected_job.args) %></pre>
                </div>
                
    <!-- Errors -->
                <div class="border-t pt-4">
                  <h3 class="text-sm font-semibold text-gray-700 mb-2">Errors</h3>
                  <% errors = format_errors(@selected_job.errors) %>
                  <%= if length(errors) > 0 do %>
                    <div class="space-y-2">
                      <%= for {error, idx} <- Enum.with_index(errors) do %>
                        <div class="bg-red-50 border border-red-200 rounded p-3">
                          <div class="text-xs font-medium text-red-800 mb-1">
                            Attempt {idx + 1}
                          </div>
                          <pre class="text-xs text-red-700 whitespace-pre-wrap break-words"><%= format_error_entry(error) %></pre>
                        </div>
                      <% end %>
                    </div>
                  <% else %>
                    <p class="text-sm text-gray-400 italic">No errors recorded</p>
                  <% end %>
                </div>
                
    <!-- Meta / Tags -->
                <%= if @selected_job[:meta] && @selected_job.meta != %{} do %>
                  <div class="border-t pt-4 mt-4">
                    <h3 class="text-sm font-semibold text-gray-700 mb-2">Meta</h3>
                    <pre class="bg-gray-900 text-green-400 rounded p-3 text-xs overflow-x-auto"><%= format_json(@selected_job.meta) %></pre>
                  </div>
                <% end %>

                <%= if @selected_job[:tags] && @selected_job.tags != [] do %>
                  <div class="border-t pt-4 mt-4">
                    <h3 class="text-sm font-semibold text-gray-700 mb-2">Tags</h3>
                    <div class="flex flex-wrap gap-1">
                      <%= for tag <- @selected_job.tags do %>
                        <span class="inline-flex px-2 py-0.5 rounded bg-gray-200 text-gray-700 text-xs">
                          {tag}
                        </span>
                      <% end %>
                    </div>
                  </div>
                <% end %>
              </div>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  defp format_json(data) when is_map(data) do
    Jason.encode!(data, pretty: true)
  end

  defp format_json(data) when is_binary(data) do
    case Jason.decode(data) do
      {:ok, decoded} -> Jason.encode!(decoded, pretty: true)
      _ -> data
    end
  end

  defp format_json(data), do: inspect(data)

  defp format_error_entry(error) when is_map(error) do
    Jason.encode!(error, pretty: true)
  end

  defp format_error_entry(error) when is_binary(error), do: error
  defp format_error_entry(error), do: inspect(error)
end
