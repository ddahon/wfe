defmodule WfeWeb.ScrapingDashboardLive do
  use WfeWeb, :live_view

  alias Wfe.Scrapers.FilterInsights

  @refresh_interval :timer.seconds(30)

  @time_ranges [
    {"All", nil},
    {"24h", "24h"},
    {"7d", "7d"},
    {"30d", "30d"}
  ]

  @tabs [
    {"filters", "Filter Data"},
    {"errors", "Error Breakdown"}
  ]

  # ── Mount & Params ─────────────────────────────────────────────────────

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Process.send_after(self(), :refresh, @refresh_interval)

    {:ok,
     assign(socket,
       page_title: "Scraping Dashboard",
       time_ranges: @time_ranges,
       tabs: @tabs
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, params) do
    ats = Map.get(params, "ats")
    range = Map.get(params, "range")
    search = Map.get(params, "search")
    sort_by = Map.get(params, "sort_by", "started_at")
    sort_dir = Map.get(params, "sort_dir", "desc")
    page = parse_page(params)
    active_tab = Map.get(params, "tab", "filters")

    socket
    |> assign(
      page_title: "Scraping Dashboard",
      ats_filter: ats,
      time_range: range,
      search: search,
      sort_by: sort_by,
      sort_dir: sort_dir,
      page: page,
      active_tab: active_tab
    )
    |> load_overview_data()
  end

  defp apply_action(socket, :run_detail, %{"run_id" => run_id} = params) do
    page = parse_page(params)
    {events, total} = FilterInsights.run_details(run_id, page: page)
    run_info = FilterInsights.run_summary(run_id)
    total_pages = calc_total_pages(total)

    assign(socket,
      page_title: "Run Details",
      run_id: run_id,
      run_info: run_info,
      run_events: events,
      page: page,
      total_pages: total_pages,
      total: total
    )
  end

  defp apply_action(socket, :company_detail, %{"company_id" => company_id} = params) do
    page = parse_page(params)
    outcome = Map.get(params, "outcome")
    summary = FilterInsights.company_summary(company_id)
    {events, total} = FilterInsights.company_events(company_id, page: page, outcome: outcome)
    total_pages = calc_total_pages(total)

    assign(socket,
      page_title: "Company Filter Details",
      detail_company_id: company_id,
      company_summary: summary,
      company_events: events,
      company_outcome_filter: outcome,
      page: page,
      total_pages: total_pages,
      total: total
    )
  end

  # ── Events ─────────────────────────────────────────────────────────────

  @impl true
  def handle_event("filter", params, socket) do
    ats = Map.get(params, "ats", socket.assigns[:ats_filter])
    range = Map.get(params, "range", socket.assigns[:time_range])
    search = Map.get(params, "search", socket.assigns[:search])

    ats = if ats == "", do: nil, else: ats
    range = if range == "", do: nil, else: range
    search = if search == "", do: nil, else: search

    path =
      index_path(
        ats,
        range,
        search,
        socket.assigns.sort_by,
        socket.assigns.sort_dir,
        1,
        socket.assigns.active_tab
      )

    {:noreply, push_patch(socket, to: path)}
  end

  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    path =
      index_path(
        socket.assigns.ats_filter,
        socket.assigns.time_range,
        socket.assigns.search,
        socket.assigns.sort_by,
        socket.assigns.sort_dir,
        1,
        tab
      )

    {:noreply, push_patch(socket, to: path)}
  end

  def handle_event("sort", %{"field" => field}, socket) do
    {sort_by, sort_dir} =
      if socket.assigns.sort_by == field do
        new_dir = if socket.assigns.sort_dir == "asc", do: "desc", else: "asc"
        {field, new_dir}
      else
        {field, "desc"}
      end

    path =
      index_path(
        socket.assigns.ats_filter,
        socket.assigns.time_range,
        socket.assigns.search,
        sort_by,
        sort_dir,
        1,
        socket.assigns.active_tab
      )

    {:noreply, push_patch(socket, to: path)}
  end

  def handle_event("filter-company-outcome", %{"outcome" => outcome}, socket) do
    outcome = if outcome == "", do: nil, else: outcome
    path = company_path(socket.assigns.detail_company_id, outcome, 1)
    {:noreply, push_patch(socket, to: path)}
  end

  @impl true
  def handle_info(:refresh, socket) do
    Process.send_after(self(), :refresh, @refresh_interval)

    socket =
      case socket.assigns.live_action do
        :index -> load_overview_data(socket)
        _ -> socket
      end

    {:noreply, socket}
  end

  # ── Data Loading ───────────────────────────────────────────────────────
  defp load_overview_data(socket) do
    a = socket.assigns
    base_opts = build_filter_opts(a[:ats_filter], a[:time_range])

    run_opts =
      base_opts
      |> Keyword.merge(
        page: a.page,
        search: a[:search],
        sort_by: safe_atom(a[:sort_by], :started_at),
        sort_dir: safe_atom(a[:sort_dir], :desc)
      )

    {runs, runs_total} = FilterInsights.recent_runs(run_opts)
    runs_total_pages = calc_total_pages(runs_total)

    # Load error breakdown data
    errors_by_type = FilterInsights.failed_jobs_by_error(base_opts)
    total_failed = FilterInsights.total_failed_count(base_opts)

    assign(socket,
      summary: FilterInsights.summary(base_opts),
      totals: FilterInsights.total_counts(base_opts),
      pass_rate: FilterInsights.pass_rate(base_opts),
      by_company: FilterInsights.by_company(base_opts),
      by_ats: FilterInsights.by_ats(base_opts),
      recent_runs: runs,
      runs_total: runs_total,
      total_pages: runs_total_pages,
      errors_by_type: errors_by_type,
      total_failed: total_failed
    )
  end

  defp build_filter_opts(ats, range) do
    opts = []
    opts = if ats && ats != "", do: [{:ats, ats} | opts], else: opts
    opts ++ since_opt(range)
  end

  defp safe_atom(val, default) when is_binary(val) do
    try do
      String.to_existing_atom(val)
    rescue
      ArgumentError -> default
    end
  end

  defp safe_atom(val, _default) when is_atom(val), do: val
  defp safe_atom(_, default), do: default

  defp since_opt("24h"), do: [since: DateTime.utc_now() |> DateTime.add(-86_400, :second)]
  defp since_opt("7d"), do: [since: DateTime.utc_now() |> DateTime.add(-7 * 86_400, :second)]
  defp since_opt("30d"), do: [since: DateTime.utc_now() |> DateTime.add(-30 * 86_400, :second)]
  defp since_opt(_), do: []

  # ── Path Builders ──────────────────────────────────────────────────────

  defp index_path(ats, range, search, sort_by, sort_dir, page, tab \\ "filters") do
    params =
      %{}
      |> maybe_put("ats", ats)
      |> maybe_put("range", range)
      |> maybe_put("search", search)
      |> maybe_put("sort_by", sort_by, &(&1 != "started_at"))
      |> maybe_put("sort_dir", sort_dir, &(&1 != "desc"))
      |> maybe_put("page", page, &(&1 > 1))
      |> maybe_put("tab", tab, &(&1 != "filters"))

    ~p"/admin/scraping?#{params}"
  end

  defp run_path(run_id, page) do
    params = %{} |> maybe_put("page", page, &(&1 > 1))
    ~p"/admin/scraping/run/#{run_id}?#{params}"
  end

  defp company_path(company_id, outcome, page) do
    params =
      %{}
      |> maybe_put("outcome", outcome)
      |> maybe_put("page", page, &(&1 > 1))

    ~p"/admin/scraping/company/#{company_id}?#{params}"
  end

  defp maybe_put(map, _k, nil), do: map
  defp maybe_put(map, _k, ""), do: map
  defp maybe_put(map, k, v), do: Map.put(map, k, v)
  defp maybe_put(map, k, v, keep?), do: if(keep?.(v), do: Map.put(map, k, v), else: map)

  defp parse_page(params) do
    case Integer.parse(Map.get(params, "page", "1")) do
      {n, _} when n >= 1 -> n
      _ -> 1
    end
  end

  defp calc_total_pages(total) do
    max(1, ceil(total / FilterInsights.page_size()))
  end

  # ── Render: Run Detail ─────────────────────────────────────────────────

  @impl true
  def render(%{live_action: :run_detail} = assigns) do
    ~H"""
    <div class="min-h-screen bg-white text-zinc-900">
      <div class="max-w-6xl mx-auto p-6">
        <.back_link path={~p"/admin/scraping"} label="Back to Dashboard" />

        <div class="mb-8">
          <h1 class="text-2xl font-bold text-zinc-900">Run Details</h1>
          <p class="text-sm text-zinc-500 font-mono mt-1">{short_id(@run_id)}</p>
        </div>

        <%= if @run_info do %>
          <div class="grid grid-cols-2 md:grid-cols-5 gap-4 mb-8">
            <.stat_card label="Company" value={@run_info.company_name} />
            <.stat_card label="ATS" value={String.capitalize(@run_info.ats)} />
            <.stat_card label="Total" value={@run_info.total} />
            <.stat_card label="Passed" value={@run_info.passed} color="green" />
            <.stat_card label="Rejected" value={@run_info.rejected} color="red" />
          </div>
        <% end %>

        <.events_table events={@run_events} show_when={false} />

        <.pagination
          page={@page}
          total_pages={@total_pages}
          path_fn={fn p -> run_path(@run_id, p) end}
        />
      </div>
    </div>
    """
  end

  # ── Render: Company Detail ─────────────────────────────────────────────

  def render(%{live_action: :company_detail} = assigns) do
    ~H"""
    <div class="min-h-screen bg-white text-zinc-900">
      <div class="max-w-6xl mx-auto p-6">
        <.back_link path={~p"/admin/scraping"} label="Back to Dashboard" />

        <%= if @company_summary do %>
          <div class="mb-8">
            <h1 class="text-2xl font-bold text-zinc-900">{@company_summary.company_name}</h1>
            <p class="text-sm text-zinc-500 mt-1">
              ATS: {String.capitalize(@company_summary.ats)} · First seen: {format_datetime(
                @company_summary.first_seen
              )} · Last seen: {format_datetime(@company_summary.last_seen)}
            </p>
          </div>

          <div class="grid grid-cols-2 md:grid-cols-4 gap-4 mb-8">
            <.stat_card label="Total Evaluated" value={@company_summary.total} />
            <.stat_card label="Passed" value={@company_summary.passed} color="green" />
            <.stat_card label="Rejected" value={@company_summary.rejected} color="red" />
            <.stat_card
              label="Pass Rate"
              value={format_percent(@company_summary.passed, @company_summary.total)}
              color="blue"
            />
          </div>
        <% end %>

        <div class="mb-4">
          <form phx-change="filter-company-outcome">
            <select
              name="outcome"
              class="rounded-lg border border-zinc-300 bg-white px-3 py-2 text-sm text-zinc-900 focus:outline-none focus:ring-2 focus:ring-zinc-400 focus:border-zinc-400"
            >
              <option value="" selected={@company_outcome_filter == nil}>All outcomes</option>
              <option value="passed" selected={@company_outcome_filter == "passed"}>
                Passed only
              </option>
              <option value="rejected" selected={@company_outcome_filter == "rejected"}>
                Rejected only
              </option>
            </select>
          </form>
        </div>

        <.events_table events={@company_events} show_when={true} />

        <.pagination
          page={@page}
          total_pages={@total_pages}
          path_fn={fn p -> company_path(@detail_company_id, @company_outcome_filter, p) end}
        />
      </div>
    </div>
    """
  end

  # ── Render: Index ──────────────────────────────────────────────────────

  def render(%{live_action: :index} = assigns) do
    ~H"""
    <div class="min-h-screen bg-white text-zinc-900">
      <div class="max-w-6xl mx-auto p-6">
        <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4 mb-8">
          <div>
            <h1 class="text-2xl font-bold text-zinc-900">Scraping Filter Dashboard</h1>
            <p class="text-sm text-zinc-500 mt-1">
              Remote job filter performance and audit trail
            </p>
          </div>

          <form phx-change="filter" class="flex flex-wrap items-center gap-3">
            <input
              type="text"
              name="search"
              value={@search}
              placeholder="Search companies..."
              phx-debounce="300"
              class="rounded-lg border border-zinc-300 bg-white px-3 py-2 text-sm text-zinc-900 placeholder:text-zinc-400 focus:outline-none focus:ring-2 focus:ring-zinc-400 focus:border-zinc-400 w-40"
            />

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
                phx-value-search={@search || ""}
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

        <%!-- Overview Stats --%>
        <div class="grid grid-cols-2 md:grid-cols-6 gap-4 mb-8">
          <.stat_card
            label="Total Evaluated"
            value={Map.get(@totals, "passed", 0) + Map.get(@totals, "rejected", 0)}
          />
          <.stat_card label="Passed" value={Map.get(@totals, "passed", 0)} color="green" />
          <.stat_card label="Rejected" value={Map.get(@totals, "rejected", 0)} color="red" />
          <.stat_card label="Failed Jobs" value={@total_failed} color="amber" />
          <.stat_card
            label="Pass Rate"
            value={format_percent_float(@pass_rate)}
            color="blue"
          />
          <.stat_card label="Companies" value={length(@by_company)} color="purple" />
        </div>

        <%!-- Tab Navigation --%>
        <div class="border-b border-zinc-200 mb-6">
          <nav class="-mb-px flex space-x-8">
            <button
              :for={{tab_id, tab_label} <- @tabs}
              phx-click="switch_tab"
              phx-value-tab={tab_id}
              class={[
                "py-4 px-1 border-b-2 font-medium text-sm transition-colors",
                if(@active_tab == tab_id,
                  do: "border-zinc-900 text-zinc-900",
                  else: "border-transparent text-zinc-500 hover:text-zinc-700 hover:border-zinc-300"
                )
              ]}
            >
              {tab_label}
            </button>
          </nav>
        </div>

        <%!-- Tab Content --%>
        <%= if @active_tab == "filters" do %>
          <%!-- Breakdown Cards --%>
          <div class="grid md:grid-cols-2 gap-6 mb-8">
            <.filter_breakdown_card summary={@summary} totals={@totals} />
            <.ats_breakdown_card by_ats={@by_ats} />
          </div>

          <%!-- Recent Runs --%>
          <.runs_table
            runs={@recent_runs}
            page={@page}
            total_pages={@total_pages}
            ats_filter={@ats_filter}
            time_range={@time_range}
            search={@search}
            sort_by={@sort_by}
            sort_dir={@sort_dir}
            active_tab={@active_tab}
          />
        <% else %>
          <%!-- Error Breakdown Tab --%>
          <.error_breakdown_card errors_by_type={@errors_by_type} total_failed={@total_failed} />
        <% end %>
      </div>
    </div>
    """
  end

  # ── Private Components ─────────────────────────────────────────────────

  defp error_breakdown_card(assigns) do
    ~H"""
    <div class="rounded-lg border border-zinc-200 bg-white overflow-hidden">
      <div class="px-6 py-4 border-b border-zinc-200">
        <h2 class="text-lg font-semibold text-zinc-900">Failed Jobs by Error</h2>
        <p class="text-sm text-zinc-500 mt-1">
          Total failed: {@total_failed} companies
        </p>
      </div>

      <div :if={@errors_by_type == []} class="p-6">
        <p class="text-zinc-500 text-sm">No failed jobs recorded.</p>
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
              Percentage
            </th>
          </tr>
        </thead>
        <tbody class="divide-y divide-zinc-200">
          <tr :for={error <- @errors_by_type} class="hover:bg-zinc-50">
            <td class="px-6 py-4">
              <div class="flex items-center gap-2">
                <.error_severity_indicator error={error.error} />
                <span class="text-sm text-zinc-900 font-mono truncate max-w-md" title={error.error}>
                  {truncate_error(error.error)}
                </span>
              </div>
            </td>
            <td class="px-6 py-4 text-sm text-right tabular-nums text-zinc-900 font-medium">
              {error.count}
            </td>
            <td class="px-6 py-4 text-sm text-right tabular-nums text-zinc-500">
              {format_percent(error.count, @total_failed)}
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  defp error_severity_indicator(assigns) do
    color =
      cond do
        String.contains?(String.downcase(assigns.error || ""), "timeout") -> "amber"
        String.contains?(String.downcase(assigns.error || ""), "404") -> "zinc"
        String.contains?(String.downcase(assigns.error || ""), "500") -> "red"
        String.contains?(String.downcase(assigns.error || ""), "rate") -> "orange"
        true -> "red"
      end

    assigns = assign(assigns, :color, color)

    ~H"""
    <span class={[
      "inline-block w-2 h-2 rounded-full",
      @color == "amber" && "bg-amber-500",
      @color == "zinc" && "bg-zinc-400",
      @color == "red" && "bg-red-500",
      @color == "orange" && "bg-orange-500"
    ]}>
    </span>
    """
  end

  defp truncate_error(nil), do: "Unknown error"

  defp truncate_error(error) when byte_size(error) > 80 do
    String.slice(error, 0, 77) <> "..."
  end

  defp truncate_error(error), do: error

  defp filter_breakdown_card(assigns) do
    total = Map.get(assigns.totals, "passed", 0) + Map.get(assigns.totals, "rejected", 0)
    assigns = assign(assigns, :total, total)

    ~H"""
    <div class="rounded-lg border border-zinc-200 bg-white p-6">
      <h2 class="text-lg font-semibold text-zinc-900 mb-4">Filter Breakdown</h2>
      <div class="space-y-3">
        <.bar_stat
          label="ATS flagged remote"
          count={Map.get(@summary, {"passed", "ats_hint_remote"}, 0)}
          total={@total}
          color="green"
        />
        <.bar_stat
          label="Heuristic pass"
          count={Map.get(@summary, {"passed", "heuristic_pass"}, 0)}
          total={@total}
          color="emerald"
        />
        <.bar_stat
          label="ATS flagged on-site"
          count={Map.get(@summary, {"rejected", "ats_hint_onsite"}, 0)}
          total={@total}
          color="red"
        />
        <.bar_stat
          label="Heuristic reject"
          count={Map.get(@summary, {"rejected", "heuristic_reject"}, 0)}
          total={@total}
          color="orange"
        />
      </div>
    </div>
    """
  end

  defp ats_breakdown_card(assigns) do
    ~H"""
    <div class="rounded-lg border border-zinc-200 bg-white p-6">
      <h2 class="text-lg font-semibold text-zinc-900 mb-4">By ATS</h2>
      <div :if={@by_ats == []} class="text-zinc-500 text-sm">No data yet.</div>
      <div class="space-y-3">
        <div :for={row <- @by_ats} class="flex items-center justify-between">
          <div class="flex items-center gap-2">
            <.ats_badge ats={row.ats} />
            <span class="text-xs text-zinc-500">{row.total} jobs</span>
          </div>
          <.pass_rate_bar rate={row.pass_rate} />
        </div>
      </div>
    </div>
    """
  end

  attr :runs, :list, required: true
  attr :page, :integer, required: true
  attr :total_pages, :integer, required: true
  attr :ats_filter, :string, default: nil
  attr :time_range, :string, default: nil
  attr :search, :string, default: nil
  attr :sort_by, :string, default: "started_at"
  attr :sort_dir, :string, default: "desc"
  attr :active_tab, :string, default: "filters"

  defp runs_table(assigns) do
    ~H"""
    <div class="rounded-lg border border-zinc-200 bg-white overflow-hidden">
      <div class="px-6 py-4 border-b border-zinc-200">
        <h2 class="text-lg font-semibold text-zinc-900">Recent Runs</h2>
      </div>
      <table class="min-w-full divide-y divide-zinc-200">
        <thead class="bg-zinc-50">
          <tr>
            <th class="px-4 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
              Run
            </th>
            <th class="px-4 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
              Company
            </th>
            <th class="px-4 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
              ATS
            </th>
            <.sortable_header field="total" label="Total" sort_by={@sort_by} sort_dir={@sort_dir} />
            <.sortable_header
              field="passed"
              label="Passed"
              sort_by={@sort_by}
              sort_dir={@sort_dir}
            />
            <.sortable_header
              field="rejected"
              label="Rejected"
              sort_by={@sort_by}
              sort_dir={@sort_dir}
            />
            <.sortable_header
              field="pass_rate"
              label="Rate"
              sort_by={@sort_by}
              sort_dir={@sort_dir}
            />
            <th class="px-4 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
              When
            </th>
            <th class="px-4 py-3"></th>
          </tr>
        </thead>
        <tbody class="divide-y divide-zinc-200">
          <tr :for={run <- @runs} class="hover:bg-zinc-50">
            <td class="px-4 py-3 font-mono text-xs text-zinc-600">{short_id(run.run_id)}</td>
            <td class="px-4 py-3 text-sm text-zinc-900">{run.company_name}</td>
            <td class="px-4 py-3 text-sm">
              <.ats_badge ats={run.ats} />
            </td>
            <td class="px-4 py-3 text-sm text-right tabular-nums">{run.total}</td>
            <td class="px-4 py-3 text-sm text-right tabular-nums text-green-700">{run.passed}</td>
            <td class="px-4 py-3 text-sm text-right tabular-nums text-red-700">{run.rejected}</td>
            <td class="px-4 py-3 text-sm text-right tabular-nums">
              {format_percent_float(run.pass_rate)}
            </td>
            <td class="px-4 py-3 text-zinc-500 text-xs">{format_datetime(run.started_at)}</td>
            <td class="px-4 py-3 text-sm text-right">
              <.link
                navigate={~p"/admin/scraping/run/#{run.run_id}"}
                class="text-zinc-600 hover:text-zinc-900 font-medium"
              >
                Inspect →
              </.link>
            </td>
          </tr>
        </tbody>
      </table>
      <.empty_state :if={@runs == []} message="No runs recorded yet." />
    </div>

    <.pagination
      page={@page}
      total_pages={@total_pages}
      path_fn={
        fn p -> index_path(@ats_filter, @time_range, @search, @sort_by, @sort_dir, p, @active_tab) end
      }
    />
    """
  end

  attr :field, :string, required: true
  attr :label, :string, required: true
  attr :sort_by, :string, required: true
  attr :sort_dir, :string, required: true

  defp sortable_header(assigns) do
    ~H"""
    <th
      class="px-4 py-3 text-right text-xs font-medium text-zinc-500 uppercase tracking-wider cursor-pointer hover:bg-zinc-100 select-none"
      phx-click="sort"
      phx-value-field={@field}
    >
      <span class="inline-flex items-center gap-1">
        {@label}
        <.sort_indicator field={@field} sort_by={@sort_by} sort_dir={@sort_dir} />
      </span>
    </th>
    """
  end

  defp sort_indicator(assigns) do
    ~H"""
    <span class={["text-zinc-400", @field != @sort_by && "invisible"]}>
      <%= if @field == @sort_by do %>
        <%= if @sort_dir == "asc" do %>
          ↑
        <% else %>
          ↓
        <% end %>
      <% else %>
        ↓
      <% end %>
    </span>
    """
  end

  attr :events, :list, required: true
  attr :show_when, :boolean, default: true

  defp events_table(assigns) do
    ~H"""
    <div class="rounded-lg border border-zinc-200 bg-white overflow-hidden">
      <table class="min-w-full divide-y divide-zinc-200">
        <thead class="bg-zinc-50">
          <tr>
            <th class="px-4 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
              Title
            </th>
            <th class="px-4 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
              Location
            </th>
            <th class="px-4 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
              Outcome
            </th>
            <th class="px-4 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
              Reason
            </th>
            <th
              :if={@show_when}
              class="px-4 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider"
            >
              When
            </th>
            <th class="px-4 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
              Link
            </th>
          </tr>
        </thead>
        <tbody class="divide-y divide-zinc-200">
          <tr :for={event <- @events} class="hover:bg-zinc-50">
            <td class="px-4 py-3 text-sm font-medium text-zinc-900">
              {Map.get(event, :title) || "—"}
            </td>
            <td class="px-4 py-3 text-sm text-zinc-500">
              {Map.get(event, :location) || "—"}
            </td>
            <td class="px-4 py-3 text-sm">
              <.outcome_badge outcome={Map.get(event, :outcome)} />
            </td>
            <td class="px-4 py-3 text-sm">
              <.reason_badge reason={Map.get(event, :reason)} />
            </td>
            <td :if={@show_when} class="px-4 py-3 text-xs text-zinc-500">
              {format_datetime(Map.get(event, :inserted_at))}
            </td>
            <td class="px-4 py-3 text-sm">
              <%= if link = Map.get(event, :link) do %>
                <a href={link} target="_blank" class="text-zinc-600 hover:text-zinc-900">
                  View ↗
                </a>
              <% else %>
                <span class="text-zinc-400">—</span>
              <% end %>
            </td>
          </tr>
        </tbody>
      </table>
      <.empty_state :if={@events == []} message="No events found." />
    </div>
    """
  end
end
