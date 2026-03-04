defmodule WfeWeb.UIComponents do
  @moduledoc """
  Shared UI components used across LiveViews.
  """

  use Phoenix.Component

  # ── Pagination ─────────────────────────────────────────────────────────

  attr :page, :integer, required: true
  attr :total_pages, :integer, required: true
  attr :path_fn, :any, required: true, doc: "1-arity fn: page_number -> path string"

  def pagination(assigns) do
    ~H"""
    <div :if={@total_pages > 1} class="mt-8 flex items-center justify-center gap-4">
      <.link
        :if={@page > 1}
        patch={@path_fn.(@page - 1)}
        class="rounded border border-zinc-300 bg-white px-4 py-2 text-zinc-700 hover:bg-zinc-100 transition-colors"
      >
        ← Previous
      </.link>

      <span class="text-sm text-zinc-600">
        Page {@page} of {@total_pages}
      </span>

      <.link
        :if={@page < @total_pages}
        patch={@path_fn.(@page + 1)}
        class="rounded border border-zinc-300 bg-white px-4 py-2 text-zinc-700 hover:bg-zinc-100 transition-colors"
      >
        Next →
      </.link>
    </div>
    """
  end

  # ── Stat Card ──────────────────────────────────────────────────────────

  @stat_colors %{
    "green" => "text-green-700",
    "red" => "text-red-700",
    "blue" => "text-blue-700",
    "purple" => "text-purple-700"
  }

  attr :label, :string, required: true
  attr :value, :any, required: true
  attr :color, :string, default: nil

  def stat_card(assigns) do
    ~H"""
    <div class="rounded-lg border border-zinc-200 bg-white p-4">
      <dt class="text-sm font-medium text-zinc-500 truncate">{@label}</dt>
      <dd class={["mt-1 text-2xl font-bold tabular-nums", stat_text_color(@color)]}>
        {@value}
      </dd>
    </div>
    """
  end

  defp stat_text_color(nil), do: "text-zinc-900"
  defp stat_text_color(c), do: Map.get(@stat_colors, c, "text-zinc-900")

  # ── Badges ─────────────────────────────────────────────────────────────

  @ats_styles %{
    "greenhouse" => "bg-green-50 text-green-700 border-green-200",
    "lever" => "bg-blue-50 text-blue-700 border-blue-200",
    "ashby" => "bg-purple-50 text-purple-700 border-purple-200",
    "workable" => "bg-yellow-50 text-yellow-700 border-yellow-200",
    "recruitee" => "bg-pink-50 text-pink-700 border-pink-200"
  }

  attr :ats, :string, required: true

  def ats_badge(assigns) do
    ~H"""
    <span class={[
      "inline-flex items-center px-2 py-0.5 rounded border text-xs font-medium",
      ats_style(@ats)
    ]}>
      {String.capitalize(@ats)}
    </span>
    """
  end

  defp ats_style(ats), do: Map.get(@ats_styles, ats, "bg-zinc-50 text-zinc-700 border-zinc-200")

  attr :outcome, :string, required: true

  def outcome_badge(assigns) do
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

  @reason_styles %{
    "ats_hint_remote" => {"bg-green-50 text-green-700 border-green-200", "ATS: Remote"},
    "ats_hint_onsite" => {"bg-red-50 text-red-700 border-red-200", "ATS: On-site"},
    "heuristic_pass" => {"bg-emerald-50 text-emerald-700 border-emerald-200", "Heuristic: Pass"},
    "heuristic_reject" =>
      {"bg-orange-50 text-orange-700 border-orange-200", "Heuristic: Reject"}
  }

  attr :reason, :string, required: true

  def reason_badge(assigns) do
    {style, label} =
      Map.get(@reason_styles, assigns.reason, {"bg-zinc-50 text-zinc-700 border-zinc-200", assigns.reason})

    assigns = assign(assigns, style: style, label: label)

    ~H"""
    <span class={["inline-flex items-center px-2 py-0.5 rounded border text-xs font-medium", @style]}>
      {@label}
    </span>
    """
  end

  # ── Bar / Progress ─────────────────────────────────────────────────────

  @bar_colors %{
    "green" => "bg-green-500",
    "emerald" => "bg-emerald-500",
    "red" => "bg-red-500",
    "orange" => "bg-orange-500",
    "indigo" => "bg-indigo-500"
  }

  attr :label, :string, required: true
  attr :count, :integer, required: true
  attr :total, :integer, required: true
  attr :color, :string, default: "indigo"

  def bar_stat(assigns) do
    pct = if assigns.total > 0, do: assigns.count / assigns.total * 100, else: 0
    assigns = assign(assigns, :pct, pct)

    ~H"""
    <div>
      <div class="flex justify-between text-sm mb-1">
        <span class="text-zinc-700">{@label}</span>
        <span class="font-mono text-zinc-900">{@count}</span>
      </div>
      <div class="w-full bg-zinc-200 rounded-full h-2">
        <div
          class={["h-2 rounded-full", bar_bg(@color)]}
          style={"width: #{Float.round(@pct, 1)}%"}
        >
        </div>
      </div>
    </div>
    """
  end

  defp bar_bg(color), do: Map.get(@bar_colors, color, "bg-zinc-500")

  # ── Pass Rate Inline ───────────────────────────────────────────────────

  attr :rate, :float, required: true
  attr :color, :string, default: "green"

  def pass_rate_bar(assigns) do
    ~H"""
    <div class="flex items-center gap-2">
      <div class="w-16 bg-zinc-200 rounded-full h-1.5">
        <div
          class={["h-1.5 rounded-full", bar_bg(@color)]}
          style={"width: #{Float.round(@rate * 100, 1)}%"}
        >
        </div>
      </div>
      <span class="text-sm tabular-nums text-zinc-700">{format_percent_float(@rate)}</span>
    </div>
    """
  end

  # ── Back Link ──────────────────────────────────────────────────────────

  attr :path, :string, required: true
  attr :label, :string, default: "Back"

  def back_link(assigns) do
    ~H"""
    <.link
      navigate={@path}
      class="inline-flex items-center gap-1 text-sm text-zinc-600 hover:text-zinc-900 mb-4"
    >
      <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
        <path stroke-linecap="round" stroke-linejoin="round" d="M15.75 19.5L8.25 12l7.5-7.5" />
      </svg>
      {@label}
    </.link>
    """
  end

  # ── Empty State ────────────────────────────────────────────────────────

  attr :message, :string, default: "No data found."

  def empty_state(assigns) do
    ~H"""
    <div class="p-8 text-center text-zinc-500">{@message}</div>
    """
  end

  # ── Formatting Helpers ─────────────────────────────────────────────────

  def format_percent_float(rate) when is_float(rate) do
    "#{Float.round(rate * 100, 1)}%"
  end

  def format_percent_float(_), do: "0%"

  def format_percent(num, denom) when is_integer(denom) and denom > 0 do
    "#{Float.round(num / denom * 100, 1)}%"
  end

  def format_percent(_, _), do: "0%"

  def format_datetime(nil), do: "—"

  def format_datetime(%DateTime{} = dt) do
    Calendar.strftime(dt, "%b %d, %H:%M")
  end

  def format_datetime(%NaiveDateTime{} = dt) do
    Calendar.strftime(dt, "%b %d, %H:%M")
  end

  def short_id(nil), do: "—"
  def short_id(uuid) when is_binary(uuid), do: String.slice(uuid, 0, 8)
end
