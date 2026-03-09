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
       page_title: "Scraping Errors",
       time_ranges: @time_ranges,
       # Placeholders so the template never sees missing assigns before
       # handle_params fires.
       ats_filter: nil,
       time_range: nil,
       errors_by_type: [],
       total_failed: 0
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    ats = Map.get(params, "ats")
    range = Map.get(params, "range")

    socket =
      socket
      |> assign(ats_filter: ats, time_range: range)
      |> load_error_data()

    {:noreply, socket}
  end

  # ── Events ─────────────────────────────────────────────────────────────

  @impl true
  def handle_event("filter", params, socket) do
    ats = nilify(Map.get(params, "ats", ""))
    range = nilify(Map.get(params, "range", ""))
    {:noreply, push_patch(socket, to: errors_path(ats, range))}
  end

  @impl true
  def handle_info(:refresh, socket) do
    Process.send_after(self(), :refresh, @refresh_interval)
    {:noreply, load_error_data(socket)}
  end

  # ── Data Loading ───────────────────────────────────────────────────────

  # Both queries touch the same small set of rows (companies with errors).
  # Running them in parallel cuts wall-clock time roughly in half.
  defp load_error_data(socket) do
    opts = build_filter_opts(socket.assigns.ats_filter, socket.assigns.time_range)

    [errors_task, total_task] =
      [
        fn -> FilterInsights.failed_jobs_by_error(opts) end,
        fn -> FilterInsights.total_failed_count(opts) end
      ]
      |> Enum.map(&Task.async/1)

    errors_by_type = Task.await(errors_task, 10_000)
    total_failed = Task.await(total_task, 10_000)

    assign(socket, errors_by_type: errors_by_type, total_failed: total_failed)
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

  # ── Path Builders ──────────────────────────────────────────────────────

  defp errors_path(ats, range) do
    params =
      %{}
      |> maybe_put("ats", ats)
      |> maybe_put("range", range)

    ~p"/admin/scraping/errors?#{params}"
  end

  defp maybe_put(map, _k, nil), do: map
  defp maybe_put(map, _k, ""), do: map
  defp maybe_put(map, k, v), do: Map.put(map, k, v)

  # ── Render ─────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-white text-zinc-900">
      <div class="max-w-6xl mx-auto p-6">
        <.back_link path={~p"/admin/scraping/filters"} label="Back to Filter Dashboard" />

        <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4 mb-8">
          <div>
            <h1 class="text-2xl font-bold text-zinc-900">Scraping Error Breakdown</h1>
            <p class="text-sm text-zinc-500 mt-1">
              Failed scrape jobs grouped by error
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

        <.error_breakdown_card errors_by_type={@errors_by_type} total_failed={@total_failed} />
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
        <p class="text-sm text-zinc-500 mt-1">Total failed: {@total_failed} companies</p>
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
                <span
                  class="text-sm text-zinc-900 font-mono truncate max-w-md"
                  title={error.error}
                >
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
      "inline-block w-2 h-2 rounded-full flex-shrink-0",
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
end
