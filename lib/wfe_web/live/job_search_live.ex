defmodule WfeWeb.JobSearchLive do
  use WfeWeb, :live_view

  alias Wfe.Jobs.Search
  alias Wfe.Companies

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
       jobs_empty?: jobs == []
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

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="max-w-4xl mx-auto p-6">
        <h1 class="text-3xl font-bold mb-6">Job Search</h1>

        <.search_bar query={@query} />
        <.age_filter_bar age={@age} age_filters={@age_filters} query={@query} />
        <.role_selector presets={@presets} query={@query} />

        <p class="text-sm text-zinc-500 mb-4">
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

  defp search_bar(assigns) do
    ~H"""
    <div class="mb-4">
      <form id="search-form" phx-submit="search" class="flex gap-2">
        <input
          type="text"
          name="q"
          value={@query}
          placeholder="Search job titles or company names..."
          autocomplete="off"
          class="flex-1 rounded-lg border border-zinc-300 bg-white px-4 py-2 text-zinc-900 placeholder-zinc-400 focus:outline-none focus:ring-2 focus:ring-zinc-400 focus:border-zinc-400"
        />
        <button
          type="submit"
          class="rounded-lg bg-zinc-900 px-5 py-2 text-white hover:bg-zinc-700 transition-colors"
        >
          Search
        </button>
      </form>
    </div>
    """
  end

  defp age_filter_bar(assigns) do
    ~H"""
    <div class="mb-4 flex flex-wrap items-center gap-2">
      <span class="text-sm text-zinc-500">Posted within:</span>

      <.link
        :for={{label, days} <- @age_filters}
        patch={self_path(@query, 1, days)}
        class={[
          "rounded-full px-3 py-1 text-sm border transition-colors",
          if(@age == days,
            do: "bg-zinc-900 text-white border-zinc-900",
            else: "bg-white text-zinc-700 border-zinc-300 hover:bg-zinc-100"
          )
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
          <label for="role-select" class="text-sm text-zinc-500 whitespace-nowrap">
            Role type:
          </label>
          <div class="relative">
            <select
              id="role-select"
              name="preset"
              class="appearance-none rounded-lg border border-zinc-300 bg-white pl-4 pr-10 py-2 text-sm text-zinc-900 shadow-sm hover:border-zinc-400 focus:outline-none focus:ring-2 focus:ring-zinc-400 focus:border-zinc-400 cursor-pointer transition-colors"
              aria-label="Filter by role type"
            >
              <option value="">All roles</option>
              <option :for={{label, q} <- @presets} value={q} selected={@query == q}>
                {label}
              </option>
            </select>
            <div class="pointer-events-none absolute inset-y-0 right-0 flex items-center pr-3">
              <.icon name="hero-chevron-down" class="h-4 w-4 text-zinc-500" />
            </div>
          </div>
        </div>
      </form>
    </div>
    """
  end

  defp job_list(assigns) do
    ~H"""
    <ul id="jobs" phx-update="stream" class="divide-y divide-zinc-200">
      <li :if={@jobs_empty?} class="text-center text-zinc-500 py-12">
        No jobs found.
      </li>
      <li :for={{id, job} <- @jobs} id={id} class="py-4">
        <div class="flex items-start justify-between gap-4">
          <div class="min-w-0 flex-1">
            <a
              href={job.link}
              target="_blank"
              rel="noopener noreferrer"
              class="text-lg font-semibold text-blue-600 hover:underline"
            >
              {job.title}
            </a>
            <div class="mt-1 text-sm text-zinc-600">
              <button
                type="button"
                phx-click="show_company"
                phx-value-id={job.company_id}
                class="font-medium text-zinc-900 hover:underline"
              >
                {job.company.name}
              </button>
              <span :if={job.location} class="ml-2">• {job.location}</span>
            </div>
          </div>
          <div :if={job.posted_at} class="text-xs text-zinc-400 whitespace-nowrap">
            {Calendar.strftime(job.posted_at, "%b %d, %Y")}
          </div>
        </div>
      </li>
    </ul>
    """
  end

  defp company_modal(assigns) do
    ~H"""
    <div class="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4">
      <div
        id="company-modal"
        class="w-full max-w-md rounded-lg bg-white p-6 shadow-xl"
        phx-click-away="close_company"
        phx-window-keydown="close_company"
        phx-key="Escape"
      >
        <div class="flex items-start justify-between mb-4">
          <h2 class="text-xl font-bold text-zinc-900">{@company.name}</h2>
          <button
            type="button"
            phx-click="close_company"
            class="text-zinc-400 hover:text-zinc-600"
            aria-label="Close"
          >
            <.icon name="hero-x-mark" class="w-5 h-5" />
          </button>
        </div>

        <dl class="space-y-2 text-sm">
          <div :if={@company.ats}>
            <dt class="font-medium text-zinc-500">ATS</dt>
            <dd class="text-zinc-900">{@company.ats}</dd>
          </div>
          <div :if={@company.ats_identifier}>
            <dt class="font-medium text-zinc-500">Identifier</dt>
            <dd class="text-zinc-900">{@company.ats_identifier}</dd>
          </div>
          <div :if={@company.last_scraped_at}>
            <dt class="font-medium text-zinc-500">Last Scraped</dt>
            <dd class="text-zinc-900">
              {Calendar.strftime(@company.last_scraped_at, "%b %d, %Y at %H:%M UTC")}
            </dd>
          </div>
          <div :if={@company.last_scrape_error}>
            <dt class="font-medium text-zinc-500">Last Error</dt>
            <dd class="text-red-600 break-words">{@company.last_scrape_error}</dd>
          </div>
        </dl>
      </div>
    </div>
    """
  end
end
