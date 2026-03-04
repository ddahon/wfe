defmodule WfeWeb.ScrapingDashboardLive do
  use WfeWeb, :live_view

  alias Wfe.Scrapers.FilterInsights

  @refresh_interval :timer.seconds(30)

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Process.send_after(self(), :refresh, @refresh_interval)

    {:ok,
     socket
     |> assign(:page_title, "Scraping Dashboard")
     |> assign(:time_range, "all")
     |> assign(:ats_filter, nil)
     |> load_overview_data()}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Scraping Dashboard")
    |> load_overview_data()
  end

  defp apply_action(socket, :run_detail, %{"run_id" => run_id}) do
    events = FilterInsights.run_details(run_id)
    run_info = FilterInsights.run_summary(run_id)

    socket
    |> assign(:page_title, "Run Details")
    |> assign(:run_id, run_id)
    |> assign(:run_info, run_info)
    |> assign(:run_events, events)
  end

  defp apply_action(socket, :company_detail, %{"company_id" => company_id}) do
    summary = FilterInsights.company_summary(company_id)
    events = FilterInsights.company_events(company_id, limit: 200)

    socket
    |> assign(:page_title, "Company Filter Details")
    |> assign(:detail_company_id, company_id)
    |> assign(:company_summary, summary)
    |> assign(:company_events, events)
    |> assign(:company_outcome_filter, nil)
  end

  @impl true
  def handle_event("filter-time-range", %{"range" => range}, socket) do
    {:noreply,
     socket
     |> assign(:time_range, range)
     |> load_overview_data()}
  end

  def handle_event("filter-ats", %{"ats" => ats}, socket) do
    ats_filter = if ats == "", do: nil, else: ats

    {:noreply,
     socket
     |> assign(:ats_filter, ats_filter)
     |> load_overview_data()}
  end

  def handle_event("filter-company-outcome", %{"outcome" => outcome}, socket) do
    outcome_filter = if outcome == "", do: nil, else: outcome

    events =
      FilterInsights.company_events(
        socket.assigns.detail_company_id,
        limit: 200,
        outcome: outcome_filter
      )

    {:noreply,
     socket
     |> assign(:company_outcome_filter, outcome_filter)
     |> assign(:company_events, events)}
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

  defp load_overview_data(socket) do
    opts = build_filter_opts(socket.assigns)

    socket
    |> assign(:summary, FilterInsights.summary(opts))
    |> assign(:totals, FilterInsights.total_counts(opts))
    |> assign(:pass_rate, FilterInsights.pass_rate(opts))
    |> assign(:by_company, FilterInsights.by_company(opts))
    |> assign(:by_ats, FilterInsights.by_ats(opts))
    |> assign(:recent_runs, FilterInsights.recent_runs(opts))
  end

  defp build_filter_opts(assigns) do
    opts = []
    opts = if assigns[:ats_filter], do: [{:ats, assigns.ats_filter} | opts], else: opts
    opts = opts ++ since_opt(assigns[:time_range])
    opts
  end

  defp since_opt("24h"),
    do: [since: DateTime.utc_now() |> DateTime.add(-86_400, :second)]

  defp since_opt("7d"),
    do: [since: DateTime.utc_now() |> DateTime.add(-7 * 86_400, :second)]

  defp since_opt("30d"),
    do: [since: DateTime.utc_now() |> DateTime.add(-30 * 86_400, :second)]

  defp since_opt(_), do: []

  # ── Templates ──────────────────────────────────────────────────────────

  @impl true
  def render(%{live_action: :run_detail} = assigns) do
    ~H"""
    <div class="max-w-7xl mx-auto px-4 py-8">
      <.back_link path={~p"/admin/scraping"} label="Back to Dashboard" />

      <div class="mb-8">
        <h1 class="text-2xl font-bold text-gray-900">Run Details</h1>
        <p class="text-sm text-gray-500 font-mono mt-1">{short_id(@run_id)}</p>
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

      <div class="bg-white shadow rounded-lg overflow-hidden">
        <table class="min-w-full divide-y divide-gray-200">
          <thead class="bg-gray-50">
            <tr>
              <th class="table-header">Title</th>
              <th class="table-header">Location</th>
              <th class="table-header">Outcome</th>
              <th class="table-header">Reason</th>
              <th class="table-header">Link</th>
            </tr>
          </thead>
          <tbody class="bg-white divide-y divide-gray-200">
            <tr :for={event <- @run_events} class="hover:bg-gray-50">
              <td class="table-cell font-medium text-gray-900">{event.title || "—"}</td>
              <td class="table-cell text-gray-500">{event.location || "—"}</td>
              <td class="table-cell">
                <.outcome_badge outcome={event.outcome} />
              </td>
              <td class="table-cell">
                <.reason_badge reason={event.reason} />
              </td>
              <td class="table-cell">
                <%= if event.link do %>
                  <a
                    href={event.link}
                    target="_blank"
                    class="text-indigo-600 hover:text-indigo-900 text-sm"
                  >
                    View ↗
                  </a>
                <% else %>
                  <span class="text-gray-400">—</span>
                <% end %>
              </td>
            </tr>
          </tbody>
        </table>

        <div :if={@run_events == []} class="p-8 text-center text-gray-500">
          No events found for this run.
        </div>
      </div>
    </div>
    """
  end

  def render(%{live_action: :company_detail} = assigns) do
    ~H"""
    <div class="max-w-7xl mx-auto px-4 py-8">
      <.back_link path={~p"/admin/scraping"} label="Back to Dashboard" />

      <%= if @company_summary do %>
        <div class="mb-8">
          <h1 class="text-2xl font-bold text-gray-900">{@company_summary.company_name}</h1>
          <p class="text-sm text-gray-500 mt-1">
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
        <select
          phx-change="filter-company-outcome"
          name="outcome"
          class="rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 text-sm"
        >
          <option value="" selected={@company_outcome_filter == nil}>All outcomes</option>
          <option value="passed" selected={@company_outcome_filter == "passed"}>Passed only</option>
          <option value="rejected" selected={@company_outcome_filter == "rejected"}>
            Rejected only
          </option>
        </select>
      </div>

      <div class="bg-white shadow rounded-lg overflow-hidden">
        <table class="min-w-full divide-y divide-gray-200">
          <thead class="bg-gray-50">
            <tr>
              <th class="table-header">Title</th>
              <th class="table-header">Location</th>
              <th class="table-header">Outcome</th>
              <th class="table-header">Reason</th>
              <th class="table-header">When</th>
              <th class="table-header">Link</th>
            </tr>
          </thead>
          <tbody class="bg-white divide-y divide-gray-200">
            <tr :for={event <- @company_events} class="hover:bg-gray-50">
              <td class="table-cell font-medium text-gray-900">{event.title || "—"}</td>
              <td class="table-cell text-gray-500">{event.location || "—"}</td>
              <td class="table-cell">
                <.outcome_badge outcome={event.outcome} />
              </td>
              <td class="table-cell">
                <.reason_badge reason={event.reason} />
              </td>
              <td class="table-cell text-gray-500 text-xs">
                {format_datetime(event.inserted_at)}
              </td>
              <td class="table-cell">
                <%= if event.link do %>
                  <a
                    href={event.link}
                    target="_blank"
                    class="text-indigo-600 hover:text-indigo-900 text-sm"
                  >
                    View ↗
                  </a>
                <% else %>
                  <span class="text-gray-400">—</span>
                <% end %>
              </td>
            </tr>
          </tbody>
        </table>

        <div :if={@company_events == []} class="p-8 text-center text-gray-500">
          No events found.
        </div>
      </div>
    </div>
    """
  end

  def render(%{live_action: :index} = assigns) do
    ~H"""
    <div class="max-w-7xl mx-auto px-4 py-8">
      <div class="flex items-center justify-between mb-8">
        <div>
          <h1 class="text-2xl font-bold text-gray-900">Scraping Filter Dashboard</h1>
          <p class="text-sm text-gray-500 mt-1">
            Remote job filter performance and audit trail
          </p>
        </div>
        <div class="flex items-center gap-3">
          <select
            phx-change="filter-ats"
            name="ats"
            class="rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 text-sm"
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

          <div class="inline-flex rounded-md shadow-sm">
            <.time_button range="all" current={@time_range} label="All" position="left" />
            <.time_button range="24h" current={@time_range} label="24h" position="middle" />
            <.time_button range="7d" current={@time_range} label="7d" position="middle" />
            <.time_button range="30d" current={@time_range} label="30d" position="right" />
          </div>
        </div>
      </div>

      <%!-- Overview Stats --%>
      <div class="grid grid-cols-2 md:grid-cols-5 gap-4 mb-8">
        <.stat_card
          label="Total Evaluated"
          value={Map.get(@totals, "passed", 0) + Map.get(@totals, "rejected", 0)}
        />
        <.stat_card label="Passed" value={Map.get(@totals, "passed", 0)} color="green" />
        <.stat_card label="Rejected" value={Map.get(@totals, "rejected", 0)} color="red" />
        <.stat_card label="Pass Rate" value={format_percent_float(@pass_rate)} color="blue" />
        <.stat_card label="Companies" value={length(@by_company)} color="purple" />
      </div>

      <%!-- Breakdown by Reason --%>
      <div class="grid md:grid-cols-2 gap-6 mb-8">
        <div class="bg-white shadow rounded-lg p-6">
          <h2 class="text-lg font-semibold text-gray-900 mb-4">Filter Breakdown</h2>
          <div class="space-y-3">
            <.reason_row
              label="ATS flagged remote"
              count={Map.get(@summary, {"passed", "ats_hint_remote"}, 0)}
              total={Map.get(@totals, "passed", 0) + Map.get(@totals, "rejected", 0)}
              color="green"
            />
            <.reason_row
              label="Heuristic pass"
              count={Map.get(@summary, {"passed", "heuristic_pass"}, 0)}
              total={Map.get(@totals, "passed", 0) + Map.get(@totals, "rejected", 0)}
              color="emerald"
            />
            <.reason_row
              label="ATS flagged on-site"
              count={Map.get(@summary, {"rejected", "ats_hint_onsite"}, 0)}
              total={Map.get(@totals, "passed", 0) + Map.get(@totals, "rejected", 0)}
              color="red"
            />
            <.reason_row
              label="Heuristic reject"
              count={Map.get(@summary, {"rejected", "heuristic_reject"}, 0)}
              total={Map.get(@totals, "passed", 0) + Map.get(@totals, "rejected", 0)}
              color="orange"
            />
          </div>
        </div>

        <div class="bg-white shadow rounded-lg p-6">
          <h2 class="text-lg font-semibold text-gray-900 mb-4">By ATS</h2>
          <div :if={@by_ats == []} class="text-gray-500 text-sm">No data yet.</div>
          <div class="space-y-3">
            <div :for={row <- @by_ats} class="flex items-center justify-between">
              <div class="flex items-center gap-2">
                <span class="text-sm font-medium text-gray-900">
                  {String.capitalize(row.ats)}
                </span>
                <span class="text-xs text-gray-500">{row.total} jobs</span>
              </div>
              <div class="flex items-center gap-3">
                <div class="w-32 bg-gray-200 rounded-full h-2">
                  <div
                    class="bg-indigo-500 h-2 rounded-full"
                    style={"width: #{Float.round(row.pass_rate * 100, 1)}%"}
                  >
                  </div>
                </div>
                <span class="text-sm font-mono text-gray-700 w-12 text-right">
                  {format_percent_float(row.pass_rate)}
                </span>
              </div>
            </div>
          </div>
        </div>
      </div>

      <%!-- Company Table --%>
      <div class="bg-white shadow rounded-lg overflow-hidden mb-8">
        <div class="px-6 py-4 border-b border-gray-200">
          <h2 class="text-lg font-semibold text-gray-900">By Company</h2>
        </div>
        <table class="min-w-full divide-y divide-gray-200">
          <thead class="bg-gray-50">
            <tr>
              <th class="table-header">Company</th>
              <th class="table-header">ATS</th>
              <th class="table-header text-right">Total</th>
              <th class="table-header text-right">Passed</th>
              <th class="table-header text-right">Rejected</th>
              <th class="table-header text-right">Pass Rate</th>
              <th class="table-header"></th>
            </tr>
          </thead>
          <tbody class="bg-white divide-y divide-gray-200">
            <tr :for={row <- @by_company} class="hover:bg-gray-50">
              <td class="table-cell font-medium text-gray-900">{row.company_name}</td>
              <td class="table-cell">
                <.ats_badge ats={row.ats} />
              </td>
              <td class="table-cell text-right tabular-nums">{row.total}</td>
              <td class="table-cell text-right tabular-nums text-green-700">{row.passed}</td>
              <td class="table-cell text-right tabular-nums text-red-700">{row.rejected}</td>
              <td class="table-cell text-right">
                <div class="flex items-center justify-end gap-2">
                  <div class="w-16 bg-gray-200 rounded-full h-1.5">
                    <div
                      class="bg-green-500 h-1.5 rounded-full"
                      style={"width: #{Float.round(row.pass_rate * 100, 1)}%"}
                    >
                    </div>
                  </div>
                  <span class="text-sm tabular-nums">{format_percent_float(row.pass_rate)}</span>
                </div>
              </td>
              <td class="table-cell text-right">
                <.link
                  navigate={~p"/admin/scraping/company/#{row.company_id}"}
                  class="text-indigo-600 hover:text-indigo-900 text-sm"
                >
                  Details →
                </.link>
              </td>
            </tr>
          </tbody>
        </table>
        <div :if={@by_company == []} class="p-8 text-center text-gray-500">
          No filter events recorded yet. Run a scrape to generate data.
        </div>
      </div>

      <%!-- Recent Runs --%>
      <div class="bg-white shadow rounded-lg overflow-hidden">
        <div class="px-6 py-4 border-b border-gray-200">
          <h2 class="text-lg font-semibold text-gray-900">Recent Runs</h2>
        </div>
        <table class="min-w-full divide-y divide-gray-200">
          <thead class="bg-gray-50">
            <tr>
              <th class="table-header">Run ID</th>
              <th class="table-header">ATS</th>
              <th class="table-header text-right">Total</th>
              <th class="table-header text-right">Passed</th>
              <th class="table-header text-right">Rejected</th>
              <th class="table-header text-right">Pass Rate</th>
              <th class="table-header">When</th>
              <th class="table-header"></th>
            </tr>
          </thead>
          <tbody class="bg-white divide-y divide-gray-200">
            <tr :for={run <- @recent_runs} class="hover:bg-gray-50">
              <td class="table-cell font-mono text-xs text-gray-600">{short_id(run.run_id)}</td>
              <td class="table-cell">
                <.ats_badge ats={run.ats} />
              </td>
              <td class="table-cell text-right tabular-nums">{run.total}</td>
              <td class="table-cell text-right tabular-nums text-green-700">{run.passed}</td>
              <td class="table-cell text-right tabular-nums text-red-700">{run.rejected}</td>
              <td class="table-cell text-right tabular-nums">
                {format_percent_float(run.pass_rate)}
              </td>
              <td class="table-cell text-gray-500 text-xs">
                {format_datetime(run.started_at)}
              </td>
              <td class="table-cell text-right">
                <.link
                  navigate={~p"/admin/scraping/run/#{run.run_id}"}
                  class="text-indigo-600 hover:text-indigo-900 text-sm"
                >
                  Inspect →
                </.link>
              </td>
            </tr>
          </tbody>
        </table>
        <div :if={@recent_runs == []} class="p-8 text-center text-gray-500">
          No runs recorded yet.
        </div>
      </div>
    </div>
    """
  end

  # ── Function Components ────────────────────────────────────────────────

  attr :label, :string, required: true
  attr :value, :any, required: true
  attr :color, :string, default: "gray"

  defp stat_card(assigns) do
    ~H"""
    <div class="bg-white shadow rounded-lg p-4">
      <dt class="text-sm font-medium text-gray-500 truncate">{@label}</dt>
      <dd class={[
        "mt-1 text-2xl font-bold tabular-nums",
        stat_color(@color)
      ]}>
        {@value}
      </dd>
    </div>
    """
  end

  defp stat_color("green"), do: "text-green-700"
  defp stat_color("red"), do: "text-red-700"
  defp stat_color("blue"), do: "text-blue-700"
  defp stat_color("purple"), do: "text-purple-700"
  defp stat_color(_), do: "text-gray-900"

  attr :label, :string, required: true
  attr :count, :integer, required: true
  attr :total, :integer, required: true
  attr :color, :string, required: true

  defp reason_row(assigns) do
    pct = if assigns.total > 0, do: assigns.count / assigns.total * 100, else: 0
    assigns = assign(assigns, :pct, pct)

    ~H"""
    <div>
      <div class="flex justify-between text-sm mb-1">
        <span class="text-gray-700">{@label}</span>
        <span class="font-mono text-gray-900">{@count}</span>
      </div>
      <div class="w-full bg-gray-200 rounded-full h-2">
        <div class={bar_color(@color)} style={"width: #{Float.round(@pct, 1)}%"}></div>
      </div>
    </div>
    """
  end

  defp bar_color("green"), do: "bg-green-500 h-2 rounded-full"
  defp bar_color("emerald"), do: "bg-emerald-500 h-2 rounded-full"
  defp bar_color("red"), do: "bg-red-500 h-2 rounded-full"
  defp bar_color("orange"), do: "bg-orange-500 h-2 rounded-full"
  defp bar_color(_), do: "bg-gray-500 h-2 rounded-full"

  attr :outcome, :string, required: true

  defp outcome_badge(assigns) do
    ~H"""
    <span class={[
      "inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium",
      if(@outcome == "passed",
        do: "bg-green-100 text-green-800",
        else: "bg-red-100 text-red-800"
      )
    ]}>
      {@outcome}
    </span>
    """
  end

  attr :reason, :string, required: true

  defp reason_badge(assigns) do
    ~H"""
    <span class={[
      "inline-flex items-center px-2 py-0.5 rounded text-xs font-medium",
      reason_badge_color(@reason)
    ]}>
      {humanize_reason(@reason)}
    </span>
    """
  end

  defp reason_badge_color("ats_hint_remote"), do: "bg-green-50 text-green-700"
  defp reason_badge_color("ats_hint_onsite"), do: "bg-red-50 text-red-700"
  defp reason_badge_color("heuristic_pass"), do: "bg-emerald-50 text-emerald-700"
  defp reason_badge_color("heuristic_reject"), do: "bg-orange-50 text-orange-700"
  defp reason_badge_color(_), do: "bg-gray-50 text-gray-700"

  defp humanize_reason("ats_hint_remote"), do: "ATS: Remote"
  defp humanize_reason("ats_hint_onsite"), do: "ATS: On-site"
  defp humanize_reason("heuristic_pass"), do: "Heuristic: Pass"
  defp humanize_reason("heuristic_reject"), do: "Heuristic: Reject"
  defp humanize_reason(other), do: other

  attr :ats, :string, required: true

  defp ats_badge(assigns) do
    ~H"""
    <span class={[
      "inline-flex items-center px-2 py-0.5 rounded text-xs font-medium",
      ats_badge_color(@ats)
    ]}>
      {String.capitalize(@ats)}
    </span>
    """
  end

  defp ats_badge_color("greenhouse"), do: "bg-green-50 text-green-700"
  defp ats_badge_color("lever"), do: "bg-blue-50 text-blue-700"
  defp ats_badge_color("ashby"), do: "bg-purple-50 text-purple-700"
  defp ats_badge_color("workable"), do: "bg-yellow-50 text-yellow-700"
  defp ats_badge_color("recruitee"), do: "bg-pink-50 text-pink-700"
  defp ats_badge_color(_), do: "bg-gray-50 text-gray-700"

  attr :range, :string, required: true
  attr :current, :string, required: true
  attr :label, :string, required: true
  attr :position, :string, required: true

  defp time_button(assigns) do
    ~H"""
    <button
      phx-click="filter-time-range"
      phx-value-range={@range}
      class={[
        "px-3 py-1.5 text-sm font-medium border",
        time_button_position(@position),
        if(@range == @current,
          do: "bg-indigo-600 text-white border-indigo-600 z-10",
          else: "bg-white text-gray-700 border-gray-300 hover:bg-gray-50"
        )
      ]}
    >
      {@label}
    </button>
    """
  end

  defp time_button_position("left"), do: "rounded-l-md"
  defp time_button_position("right"), do: "rounded-r-md -ml-px"
  defp time_button_position(_), do: "-ml-px"

  attr :path, :string, required: true
  attr :label, :string, required: true

  defp back_link(assigns) do
    ~H"""
    <.link
      navigate={@path}
      class="inline-flex items-center gap-1 text-sm text-indigo-600 hover:text-indigo-800 mb-4"
    >
      <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
        <path stroke-linecap="round" stroke-linejoin="round" d="M15.75 19.5L8.25 12l7.5-7.5" />
      </svg>
      {@label}
    </.link>
    """
  end

  # ── Helpers ────────────────────────────────────────────────────────────

  defp short_id(nil), do: "—"
  defp short_id(uuid), do: String.slice(uuid, 0, 8)

  defp format_percent_float(rate) when is_float(rate) do
    "#{Float.round(rate * 100, 1)}%"
  end

  defp format_percent_float(_), do: "0%"

  defp format_percent(passed, total) when is_integer(total) and total > 0 do
    "#{Float.round(passed / total * 100, 1)}%"
  end

  defp format_percent(_, _), do: "0%"

  defp format_datetime(nil), do: "—"

  defp format_datetime(%DateTime{} = dt) do
    Calendar.strftime(dt, "%b %d, %H:%M")
  end

  defp format_datetime(%NaiveDateTime{} = dt) do
    Calendar.strftime(dt, "%b %d, %H:%M")
  end
end
