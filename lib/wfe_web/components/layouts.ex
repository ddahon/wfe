defmodule WfeWeb.Layouts do
  @moduledoc """
  Holds layouts used by the application.
  """
  use WfeWeb, :html

  alias WfeWeb.Theme

  embed_templates "layouts/*"

  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current scope"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div class={["min-h-screen flex flex-col", Theme.page_bg()]}>
      <.app_header />

      <main class="flex-1 px-4 py-6 sm:px-6 lg:px-8">
        {render_slot(@inner_block)}
      </main>

      <.app_footer />
    </div>

    <.flash_group flash={@flash} />
    """
  end

  # ── Header ─────────────────────────────────────────────

  defp app_header(assigns) do
    ~H"""
    <header class={["sticky top-0 z-40 border-b shadow-sm", Theme.header_bg(), Theme.header_border()]}>
      <div class="max-w-4xl mx-auto px-4 sm:px-6 lg:px-8">
        <div class="flex items-center justify-between h-14">
          <.link navigate={~p"/"} class={["flex items-center gap-2 text-lg font-bold", Theme.header_brand()]}>
            <.icon name="hero-briefcase-solid" class="w-5 h-5" />
            <span>WFE Jobs</span>
          </.link>

          <nav class="flex items-center gap-4">
            <.link
              navigate={~p"/"}
              class={["flex items-center gap-1 text-sm font-medium", Theme.text_muted(), "hover:text-zinc-900 transition-colors"]}
            >
              <.icon name="hero-home" class="w-4 h-4" />
              <span class="hidden sm:inline">Home</span>
            </.link>
          </nav>
        </div>
      </div>
    </header>
    """
  end

  # ── Footer ─────────────────────────────────────────────

  defp app_footer(assigns) do
    ~H"""
    <footer class={["border-t mt-auto", Theme.footer_bg(), Theme.footer_border()]}>
      <div class="max-w-4xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        <div class="flex flex-col sm:flex-row items-center justify-between gap-4">
          <p class={["text-sm", Theme.footer_text()]}>
            © {Date.utc_today().year} WFE Jobs. All rights reserved.
          </p>

          <nav class={["flex gap-4 text-sm", Theme.footer_text()]}>
            <a href="#" class={Theme.footer_link()}>About</a>
            <a href="#" class={Theme.footer_link()}>Privacy</a>
            <a href="#" class={Theme.footer_link()}>Terms</a>
            <a href="#" class={Theme.footer_link()}>Contact</a>
          </nav>
        </div>

        <p class={["text-xs mt-4 text-center", Theme.footer_text()]}>
          Built with Phoenix LiveView
        </p>
      </div>
    </footer>
    """
  end

  # ── Flash ──────────────────────────────────────────────

  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
