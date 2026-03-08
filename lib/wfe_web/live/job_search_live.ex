defmodule WfeWeb.JobSearchLive do
  use WfeWeb, :live_view

  alias Wfe.Jobs.Search
  alias Wfe.Companies
  alias WfeWeb.Theme

  @presets [
    {"Fullstack", "fullstack"},
    {"Backend", "backend"},
    {"Frontend", "frontend"},
    {"DevOps", "devops"},
    {"Data Engineer", "data engineer"},
    {"ML / AI", "machine learning"}
  ]

  @age_filters [
    {"All (90d)", nil},
    {"Last 24h", 1},
    {"Last 3 days", 3},
    {"Last week", 7}
  ]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       company: nil,
       presets: @presets,
       age_filters: @age_filters,
       jobs_empty?: true
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    query = Map.get(params, "q", "")
    page = params |> Map.get("page", "1") |> parse_pos_int(1)
    age = params |> Map.get("age") |> parse_age()

    {jobs, total} = Search.search(query, page, age)
    page_size = Search.page_size()
    total_pages = max(1, ceil(total / page_size))

    {:noreply,
     socket
     |> assign(
       query: query,
       page: page,
       age: age,
       total: total,
       total_pages: total_pages,
       jobs_empty?: jobs == [],
       has_filters?: query != "" or age != nil
     )
     |> stream(:jobs, jobs, reset: true)}
  end

  @impl true
  def handle_event("search", %{"q" => q}, socket) do
    {:noreply, push_patch(socket, to: self_path(q, 1, socket.assigns.age))}
  end

  def handle_event("preset", %{"preset" => q}, socket) do
    {:noreply, push_patch(socket, to: self_path(q, 1, socket.assigns.age))}
  end

  def handle_event("show_company", %{"id" => id}, socket) do
    {:noreply, assign(socket, company: Companies.get_company!(id))}
  end

  def handle_event("close_company", _params, socket) do
    {:noreply, assign(socket, company: nil)}
  end

  defp self_path(q, page, age) do
    params =
      %{}
      |> maybe_put("q", q, &(&1 != ""))
      |> maybe_put("page", page, &(&1 > 1))
      |> maybe_put("age", age, &(!is_nil(&1)))

    ~p"/?#{params}"
  end

  defp maybe_put(map, k, v, keep?), do: if(keep?.(v), do: Map.put(map, k, v), else: map)

  defp parse_pos_int(nil, default), do: default

  defp parse_pos_int(raw, default) do
    case Integer.parse(to_string(raw)) do
      {n, _} when n >= 1 -> n
      _ -> default
    end
  end

  defp parse_age(nil), do: nil
  defp parse_age(""), do: nil
  defp parse_age(raw), do: parse_pos_int(raw, nil)

  defp page_path_fn(query, age) do
    fn page -> self_path(query, page, age) end
  end

  # ────────────────────────────────────────────────────────
  # Render
  # ────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="max-w-4xl mx-auto">
        <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-2 mb-6">
          <h1 class={["text-2xl sm:text-3xl font-bold", Theme.text_heading()]}>Job Search</h1>

          <.link
            :if={@has_filters?}
            patch={~p"/"}
            class={Theme.reset_link()}
          >
            <.icon name="hero-x-mark" class="w-4 h-4" />
            Clear all filters
          </.link>
        </div>

        <.search_bar query={@query} />
        <.age_filter_bar age={@age} age_filters={@age_filters} query={@query} />
        <.role_selector presets={@presets} query={@query} />

        <p class={["text-sm mb-4", Theme.text_muted()]}>
          {@total} result{if @total != 1, do: "s"}
        </p>

        <.job_list jobs={@streams.jobs} jobs_empty?={@jobs_empty?} />

        <.pagination
          page={@page}
          total_pages={@total_pages}
          path_fn={page_path_fn(@query, @age)}
        />

        <.company_modal :if={@company} company={@company} />
      </div>
    </Layouts.app>
    """
  end

  # ────────────────────────────────────────────────────────
  # Components
  # ────────────────────────────────────────────────────────

  defp search_bar(assigns) do
    ~H"""
    <div class="mb-4">
      <form id="search-form" phx-submit="search" class="flex gap-2">
        <input
          type="text"
          name="q"
          value={@query}
          placeholder="Search job titles or companies…"
          autocomplete="off"
          class={["flex-1 min-w-0", Theme.input()]}
        />
        <button type="submit" class={Theme.btn_primary()}>
          <span class="hidden sm:inline">Search</span>
          <.icon name="hero-magnifying-glass" class="w-5 h-5 sm:hidden" />
        </button>
      </form>
    </div>
    """
  end

  defp age_filter_bar(assigns) do
    ~H"""
    <div class="mb-4 flex flex-wrap items-center gap-2">
      <span class={["text-sm", Theme.text_muted()]}>Posted:</span>

      <.link
        :for={{label, days} <- @age_filters}
        patch={self_path(@query, 1, days)}
        class={[
          "rounded-full px-3 py-1 text-xs sm:text-sm border transition-colors",
          if(@age == days, do: Theme.pill_active(), else: Theme.pill_inactive())
        ]}
      >
        {label}
      </.link>
    </div>
    """
  end

  defp role_selector(assigns) do
    ~H"""
    <div class="mb-6">
      <form id="role-form" phx-change="preset">
        <div class="flex items-center gap-3">
          <label for="role-select" class={["text-sm whitespace-nowrap", Theme.text_muted()]}>
            Role:
          </label>
          <div class="relative">
            <select
              id="role-select"
              name="preset"
              class={Theme.select()}
              aria-label="Filter by role type"
            >
              <option value="">All roles</option>
              <option :for={{label, q} <- @presets} value={q} selected={@query == q}>
                {label}
              </option>
            </select>
            <div class="pointer-events-none absolute inset-y-0 right-0 flex items-center pr-3">
              <.icon name="hero-chevron-down" class={["h-4 w-4", Theme.text_muted()]} />
            </div>
          </div>
        </div>
      </form>
    </div>
    """
  end

  defp job_list(assigns) do
    ~H"""
    <ul id="jobs" phx-update="stream" class={["divide-y", Theme.divider()]}>
      <li :if={@jobs_empty?} class={["text-center py-12", Theme.text_muted()]}>
        No jobs found.
      </li>
      <li :for={{id, job} <- @jobs} id={id} class="py-4">
        <div class="flex flex-col sm:flex-row sm:items-start sm:justify-between gap-1 sm:gap-4">
          <div class="min-w-0 flex-1">
            <a
              href={job.link}
              target="_blank"
              rel="noopener noreferrer"
              class={["text-base sm:text-lg font-semibold hover:underline", Theme.text_link()]}
            >
              {job.title}
            </a>
            <div class={["mt-1 text-sm", Theme.text_body()]}>
              <button
                type="button"
                phx-click="show_company"
                phx-value-id={job.company_id}
                class={["font-medium hover:underline", Theme.text_heading()]}
              >
                {job.company.name}
              </button>
              <span :if={job.location} class="ml-2">• {job.location}</span>
            </div>
          </div>
          <div :if={job.posted_at} class={["text-xs whitespace-nowrap", Theme.text_faint()]}>
            {Calendar.strftime(job.posted_at, "%b %d, %Y")}
          </div>
        </div>
      </li>
    </ul>
    """
  end

  defp company_modal(assigns) do
    ~H"""
    <div class={["fixed inset-0 z-50 flex items-center justify-center p-4", Theme.modal_overlay()]}>
      <div
        id="company-modal"
        class={["w-full max-w-md rounded-lg p-6 shadow-xl", Theme.modal_surface()]}
        phx-click-away="close_company"
        phx-window-keydown="close_company"
        phx-key="Escape"
      >
        <div class="flex items-start justify-between mb-4">
          <h2 class={["text-xl font-bold", Theme.text_heading()]}>{@company.name}</h2>
          <button
            type="button"
            phx-click="close_company"
            class={Theme.btn_ghost()}
            aria-label="Close"
          >
            <.icon name="hero-x-mark" class="w-5 h-5" />
          </button>
        </div>

        <dl class="space-y-2 text-sm">
          <div :if={@company.ats}>
            <dt class={["font-medium", Theme.text_muted()]}>ATS</dt>
            <dd class={Theme.text_heading()}>{@company.ats}</dd>
          </div>
          <div :if={@company.ats_identifier}>
            <dt class={["font-medium", Theme.text_muted()]}>Identifier</dt>
            <dd class={Theme.text_heading()}>{@company.ats_identifier}</dd>
          </div>
          <div :if={@company.last_scraped_at}>
            <dt class={["font-medium", Theme.text_muted()]}>Last Scraped</dt>
            <dd class={Theme.text_heading()}>
              {Calendar.strftime(@company.last_scraped_at, "%b %d, %Y at %H:%M UTC")}
            </dd>
          </div>
          <div :if={@company.last_scrape_error}>
            <dt class={["font-medium", Theme.text_muted()]}>Last Error</dt>
            <dd class={["break-words", Theme.text_error()]}>{@company.last_scrape_error}</dd>
          </div>
        </dl>
      </div>
    </div>
    """
  end
end
