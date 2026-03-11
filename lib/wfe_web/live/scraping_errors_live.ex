defmodule WfeWeb.ScrapingErrorsLive do
  use WfeWeb, :live_view

  alias Wfe.Scrapers.FilterInsights

  @refresh_interval :timer.seconds(60)

  @time_ranges [
    {"All", nil},
    {"24h", "24h"},
    {"7d", "7d"},
    {"30d", "30d"}
  ]

  # ── Mount & Params ─────────────────────────────────────────────────────

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Process.send_after(self(), :refresh, @refresh_interval)

    {:ok,
     assign(socket,
       page_title: "Scraping Status",
       time_ranges: @time_ranges,
       ats_filter: nil,
       time_range: nil,
       errors_by_type: [],
       status_summary: %{success: 0, failed: 0, pending: 0},
       selected_error: nil,
       selected_companies: [],
       companies_total: 0,
       companies_page: 1,
       companies_total_pages: 1
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    ats = Map.get(params, "ats")
    range = Map.get(params, "range")
    selected = Map.get(params, "error")
    page = parse_page(params)

    socket =
      socket
      |> assign(
        ats_filter: ats,
        time_range: range,
        selected_error: selected,
        companies_page: page
      )
      |> load_data()

    {:noreply, socket}
  end

  # ── Events ─────────────────────────────────────────────────────────────

  @impl true
  def handle_event("filter", params, socket) do
    ats = nilify(Map.get(params, "ats", ""))
    range = nilify(Map.get(params, "range", ""))
    {:noreply, push_patch(socket, to: errors_path(ats, range, nil, 1))}
  end

  def handle_event("select_error", %{"error" => error}, socket) do
    # Toggle: if already selected, deselect
    selected = if socket.assigns.selected_error == error, do: nil, else: error

    path =
      errors_path(
        socket.assigns.ats_filter,
        socket.assigns.time_range,
        selected,
        1
      )

    {:noreply, push_patch(socket, to: path)}
  end

  def handle_event("select_success", _, socket) do
    selected = if socket.assigns.selected_error == "success", do: nil, else: "success"

    path =
      errors_path(
        socket.assigns.ats_filter,
        socket.assigns.time_range,
        selected,
        1
      )

    {:noreply, push_patch(socket, to: path)}
  end

  def handle_event("close_detail", _, socket) do
    path =
      errors_path(
        socket.assigns.ats_filter,
        socket.assigns.time_range,
        nil,
        1
      )

    {:noreply, push_patch(socket, to: path)}
  end

  @impl true
  def handle_info(:refresh, socket) do
    Process.send_after(self(), :refresh, @refresh_interval)
    {:noreply, load_data(socket)}
  end

  # ── Data Loading ───────────────────────────────────────────────────────

  defp load_data(socket) do
    opts = build_filter_opts(socket.assigns.ats_filter, socket.assigns.time_range)

    # Run queries concurrently
    tasks = [
      errors: fn -> FilterInsights.failed_jobs_by_error(opts) end,
      status: fn -> FilterInsights.scrape_status_summary(opts) end
    ]

    results =
      tasks
      |> Task.async_stream(fn {_k, f} -> f.() end,
        timeout: 10_000,
        on_timeout: :kill_task
      )
      |> Enum.zip(Keyword.keys(tasks))
      |> Map.new(fn
        {{:ok, result}, key} -> {key, result}
        {{:exit, :timeout}, :errors} -> {:errors, []}
        {{:exit, :timeout}, :status} -> {:status, %{success: 0, failed: 0, pending: 0}}
      end)

    socket =
      assign(socket,
        errors_by_type: results.errors,
        status_summary: results.status
      )

    # Load selected error/success companies if applicable
    load_selected_companies(socket, opts)
  end

  defp load_selected_companies(socket, opts) do
    case socket.assigns.selected_error do
      nil ->
        assign(socket,
          selected_companies: [],
          companies_total: 0,
          companies_total_pages: 1
        )

      "success" ->
        company_opts = Keyword.merge(opts, page: socket.assigns.companies_page)
        {companies, total} = FilterInsights.successful_companies(company_opts)

        assign(socket,
          selected_companies: companies,
          companies_total: total,
          companies_total_pages: calc_total_pages(total)
        )

      error ->
        company_opts = Keyword.merge(opts, page: socket.assigns.companies_page)
        {companies, total} = FilterInsights.companies_with_error(error, company_opts)

        assign(socket,
          selected_companies: companies,
          companies_total: total,
          companies_total_pages: calc_total_pages(total)
        )
    end
  end

  # ── Helpers ────────────────────────────────────────────────────────────

  defp build_filter_opts(ats, range) do
    opts = []
    opts = if ats && ats != "", do: [{:ats, ats} | opts], else: opts
    opts ++ since_opt(range)
  end

  defp since_opt("24h"), do: [since: DateTime.utc_now() |> DateTime.add(-86_400, :second)]
  defp since_opt("7d"), do: [since: DateTime.utc_now() |> DateTime.add(-7 * 86_400, :second)]
  defp since_opt("30d"), do: [since: DateTime.utc_now() |> DateTime.add(-30 * 86_400, :second)]
  defp since_opt(_), do: []

  defp nilify(""), do: nil
  defp nilify(v), do: v

  defp parse_page(params) do
    case Integer.parse(Map.get(params, "page", "1")) do
      {n, _} when n >= 1 -> n
      _ -> 1
    end
  end

  defp calc_total_pages(total) do
    max(1, ceil(total / FilterInsights.page_size()))
  end

  # ── Path Builders ──────────────────────────────────────────────────────

  defp errors_path(ats, range, error, page) do
    params =
      %{}
      |> maybe_put("ats", ats)
      |> maybe_put("range", range)
      |> maybe_put("error", error)
      |> maybe_put("page", page, &(&1 > 1))

    ~p"/admin/scraping/errors?#{params}"
  end

  defp maybe_put(map, _k, nil), do: map
  defp maybe_put(map, _k, ""), do: map
  defp maybe_put(map, k, v), do: Map.put(map, k, v)
  defp maybe_put(map, k, v, keep?), do: if(keep?.(v), do: Map.put(map, k, v), else: map)

  # ── Render ─────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-white text-zinc-900">
      <div class="max-w-6xl mx-auto p-6">
        <.back_link path={~p"/admin/scraping/filters"} label="Back to Filter Dashboard" />

        <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4 mb-8">
          <div>
            <h1 class="text-2xl font-bold text-zinc-900">Scraping Status</h1>
            <p class="text-sm text-zinc-500 mt-1">
              Company scrape outcomes and error breakdown
            </p>
          </div>

          <form phx-change="filter" class="flex flex-wrap items-center gap-3">
            <select
              name="ats"
              class="rounded-lg border border-zinc-300 bg-white px-3 py-2 text-sm text-zinc-900 focus:outline-none focus:ring-2 focus:ring-zinc-400 focus:border-zinc-400"
            >
              <option value="" selected={@ats_filter == nil}>All ATS</option>
              <option
                :for={ats <- Wfe.Scrapers.supported_ats()}
                value={ats}
                selected={@ats_filter == ats}
              >
                {String.capitalize(ats)}
              </option>
            </select>

            <div class="inline-flex rounded-lg overflow-hidden border border-zinc-300">
              <button
                :for={{label, value} <- @time_ranges}
                type="button"
                phx-click="filter"
                phx-value-ats={@ats_filter || ""}
                phx-value-range={value || ""}
                class={[
                  "px-3 py-2 text-sm font-medium transition-colors border-r border-zinc-300 last:border-r-0",
                  if((@time_range || "") == (value || ""),
                    do: "bg-zinc-900 text-white",
                    else: "bg-white text-zinc-700 hover:bg-zinc-100"
                  )
                ]}
              >
                {label}
              </button>
            </div>
          </form>
        </div>

        <%!-- Summary Cards --%>
        <div class="grid grid-cols-2 md:grid-cols-4 gap-4 mb-8">
          <.stat_card label="Successful" value={@status_summary.success} color="green" />
          <.stat_card label="Failed" value={@status_summary.failed} color="red" />
          <.stat_card label="Pending" value={@status_summary.pending} color="zinc" />
          <.stat_card
            label="Success Rate"
            value={format_success_rate(@status_summary)}
            color="blue"
          />
        </div>

        <div class="grid lg:grid-cols-3 gap-6 mb-8">
          <%!-- Donut Chart --%>
          <div class="lg:col-span-1">
            <.status_donut_chart
              status_summary={@status_summary}
              errors_by_type={@errors_by_type}
              selected_error={@selected_error}
            />
          </div>

          <%!-- Error Table --%>
          <div class="lg:col-span-2">
            <.error_breakdown_table
              errors_by_type={@errors_by_type}
              status_summary={@status_summary}
              selected_error={@selected_error}
            />
          </div>
        </div>

        <%!-- Selected Error Detail Panel --%>
        <.company_detail_panel
          :if={@selected_error}
          selected_error={@selected_error}
          companies={@selected_companies}
          total={@companies_total}
          page={@companies_page}
          total_pages={@companies_total_pages}
          ats_filter={@ats_filter}
          time_range={@time_range}
        />
      </div>
    </div>
    """
  end

  # ── Components ─────────────────────────────────────────────────────────

  defp status_donut_chart(assigns) do
    total_for_pct = assigns.status_summary.success + assigns.status_summary.failed

    segments =
      if total_for_pct == 0 do
        []
      else
        Enum.map(assigns.errors_by_type, fn %{error: error, count: count} ->
          %{
            key: error,
            label: humanize_error(error),
            count: count,
            pct: count / total_for_pct * 100,
            color: error_color(error)
          }
        end)
      end

    {segments, _} =
      Enum.map_reduce(segments, 0, fn seg, cumulative ->
        {Map.put(seg, :offset, 25 - cumulative), cumulative + seg.pct}
      end)

    assigns = assign(assigns, segments: segments, total: total_for_pct)

    ~H"""
    <div class="rounded-lg border border-zinc-200 bg-white p-6">
      <h2 class="text-lg font-semibold text-zinc-900 mb-4">Error Distribution</h2>

      <div :if={@total == 0} class="flex items-center justify-center h-48 text-zinc-400 text-sm">
        No failed scrapes recorded
      </div>

      <div :if={@total > 0} class="flex flex-col items-center gap-6">
        <div class="relative">
          <svg viewBox="0 0 42 42" class="w-40 h-40">
            <circle
              cx="21"
              cy="21"
              r="15.9155"
              fill="transparent"
              stroke="#e5e7eb"
              stroke-width="3"
            />
            <circle
              :for={seg <- @segments}
              cx="21"
              cy="21"
              r="15.9155"
              fill="transparent"
              stroke={seg.color}
              stroke-width={if @selected_error == seg.key, do: "4", else: "3"}
              stroke-dasharray={"#{seg.pct} #{100 - seg.pct}"}
              stroke-dashoffset={seg.offset}
              class="transition-all duration-200 cursor-pointer hover:opacity-80"
              phx-click="select_error"
              phx-value-error={seg.key}
            />
          </svg>
          <div class="absolute inset-0 flex items-center justify-center">
            <div class="text-center">
              <div class="text-2xl font-bold text-zinc-900">{@status_summary.failed}</div>
              <div class="text-xs text-zinc-500">failed</div>
            </div>
          </div>
        </div>

        <div class="grid grid-cols-2 gap-x-4 gap-y-1 text-sm w-full">
          <button
            :for={seg <- @segments}
            phx-click="select_error"
            phx-value-error={seg.key}
            class={[
              "flex items-center gap-2 px-2 py-1 rounded transition-colors text-left",
              if(@selected_error == seg.key, do: "bg-zinc-100", else: "hover:bg-zinc-50")
            ]}
          >
            <span
              class="w-2.5 h-2.5 rounded-full flex-shrink-0"
              style={"background-color: #{seg.color}"}
            >
            </span>
            <span class="text-zinc-600 truncate">{seg.label}</span>
            <span class="text-zinc-400 ml-auto">{seg.count}</span>
          </button>
        </div>
      </div>
    </div>
    """
  end

  defp error_breakdown_table(assigns) do
    total = assigns.status_summary.failed
    assigns = assign(assigns, :total, total)

    ~H"""
    <div class="rounded-lg border border-zinc-200 bg-white overflow-hidden">
      <div class="px-6 py-4 border-b border-zinc-200">
        <h2 class="text-lg font-semibold text-zinc-900">Failed Jobs by Error</h2>
        <p class="text-sm text-zinc-500 mt-1">Click a row to see affected companies</p>
      </div>

      <div
        :if={@errors_by_type == []}
        class="p-6 text-center text-zinc-500 text-sm"
      >
        No failed scrapes recorded.
      </div>

      <table :if={@errors_by_type != []} class="min-w-full divide-y divide-zinc-200">
        <thead class="bg-zinc-50">
          <tr>
            <th class="px-6 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
              Error
            </th>
            <th class="px-6 py-3 text-right text-xs font-medium text-zinc-500 uppercase tracking-wider">
              Count
            </th>
            <th class="px-6 py-3 text-right text-xs font-medium text-zinc-500 uppercase tracking-wider">
              Of failed
            </th>
          </tr>
        </thead>
        <tbody class="divide-y divide-zinc-200">
          <tr
            :for={error <- @errors_by_type}
            phx-click="select_error"
            phx-value-error={error.error}
            class={[
              "cursor-pointer transition-colors",
              if(@selected_error == error.error,
                do: "bg-amber-50",
                else: "hover:bg-zinc-50"
              )
            ]}
          >
            <td class="px-6 py-4">
              <div class="flex items-center gap-2">
                <span
                  class="w-2 h-2 rounded-full flex-shrink-0"
                  style={"background-color: #{error_color(error.error)}"}
                >
                </span>
                <span class="text-sm text-zinc-900">{humanize_error(error.error)}</span>
              </div>
            </td>
            <td class="px-6 py-4 text-sm text-right tabular-nums text-zinc-900 font-medium">
              {error.count}
            </td>
            <td class="px-6 py-4 text-sm text-right tabular-nums text-zinc-500">
              {format_pct(error.count, @total)}
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  defp company_detail_panel(assigns) do
    ~H"""
    <div class="rounded-lg border border-zinc-200 bg-white overflow-hidden">
      <div class="px-6 py-4 border-b border-zinc-200 flex items-center justify-between">
        <div>
          <h2 class="text-lg font-semibold text-zinc-900">
            {if @selected_error == "success",
              do: "Successful Companies",
              else: humanize_error(@selected_error)}
          </h2>
          <p class="text-sm text-zinc-500 mt-1">
            {@total} {if @total == 1, do: "company", else: "companies"}
          </p>
        </div>
        <button
          phx-click="close_detail"
          class="p-2 text-zinc-400 hover:text-zinc-600 transition-colors rounded-lg hover:bg-zinc-100"
          aria-label="Close"
        >
          <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M6 18L18 6M6 6l12 12"
            />
          </svg>
        </button>
      </div>

      <div :if={@companies == []} class="p-6 text-center text-zinc-500 text-sm">
        No companies found.
      </div>

      <table :if={@companies != []} class="min-w-full divide-y divide-zinc-200">
        <thead class="bg-zinc-50">
          <tr>
            <th class="px-6 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
              Company
            </th>
            <th class="px-6 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
              ATS
            </th>
            <th class="px-6 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
              Identifier
            </th>
            <th class="px-6 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
              Last Attempt
            </th>
          </tr>
        </thead>
        <tbody class="divide-y divide-zinc-200">
          <tr
            :for={company <- @companies}
            class="hover:bg-zinc-50 cursor-pointer"
            phx-click={JS.navigate(~p"/admin/scraping/company/#{company.id}")}
          >
            <td class="px-6 py-4 text-sm font-medium text-zinc-900">
              {company.name}
            </td>
            <td class="px-6 py-4 text-sm">
              <.ats_badge ats={company.ats} />
            </td>
            <td class="px-6 py-4 text-sm text-zinc-500 font-mono">
              {company.ats_identifier}
            </td>
            <td class="px-6 py-4 text-sm text-zinc-500">
              {format_datetime(company[:last_scraped_at] || company[:updated_at])}
            </td>
          </tr>
        </tbody>
      </table>

      <.pagination
        :if={@total_pages > 1}
        page={@page}
        total_pages={@total_pages}
        path_fn={fn p -> errors_path(@ats_filter, @time_range, @selected_error, p) end}
      />
    </div>
    """
  end

  # ── Formatting Helpers ─────────────────────────────────────────────────

  defp format_success_rate(%{success: s, failed: f}) do
    total = s + f
    if total == 0, do: "—", else: "#{Float.round(s / total * 100, 1)}%"
  end

  defp format_pct(_, 0), do: "—"
  defp format_pct(count, total), do: "#{Float.round(count / total * 100, 1)}%"

  defp humanize_error("not_found"), do: "Not Found (404)"
  defp humanize_error("rate_limited"), do: "Rate Limited (429)"
  defp humanize_error("server_error"), do: "Server Error (5xx)"
  defp humanize_error("timeout"), do: "Timeout"
  defp humanize_error("auth_error"), do: "Auth Error (401/403)"
  defp humanize_error("bad_gateway"), do: "Bad Gateway (502/504)"
  defp humanize_error("gone"), do: "Gone (410)"
  defp humanize_error("parse_error"), do: "Parse Error"
  defp humanize_error("network_error"), do: "Network Error"
  defp humanize_error("unknown_error"), do: "Unknown Error"
  defp humanize_error("http_" <> code), do: "HTTP #{code}"
  defp humanize_error(other), do: other

  defp error_color("not_found"), do: "#a1a1aa"
  defp error_color("rate_limited"), do: "#f97316"
  defp error_color("server_error"), do: "#ef4444"
  defp error_color("timeout"), do: "#f59e0b"
  defp error_color("auth_error"), do: "#8b5cf6"
  defp error_color("bad_gateway"), do: "#ec4899"
  defp error_color("gone"), do: "#6b7280"
  defp error_color("parse_error"), do: "#06b6d4"
  defp error_color("network_error"), do: "#3b82f6"
  defp error_color("unknown_error"), do: "#71717a"
  defp error_color("http_" <> _), do: "#71717a"
  defp error_color(_), do: "#71717a"
end
