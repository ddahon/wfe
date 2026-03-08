defmodule WfeWeb.Theme do
  @moduledoc """
  Centralized design tokens for the application.

  Edit the class strings returned by these functions to restyle
  the entire app from a single file. Every value is a plain
  Tailwind CSS class string, so the JIT compiler picks them up
  automatically.
  """

  # ── Page ───────────────────────────────────────────────
  def page_bg, do: "bg-gray-50"

  # ── Text hierarchy ─────────────────────────────────────
  def text_heading, do: "text-zinc-900"
  def text_body, do: "text-zinc-700"
  def text_muted, do: "text-zinc-500"
  def text_faint, do: "text-zinc-400"
  def text_link, do: "text-blue-600"
  def text_error, do: "text-red-600"

  # ── Surfaces & borders ────────────────────────────────
  def surface, do: "bg-white"
  def border, do: "border-zinc-300"
  def border_light, do: "border-zinc-200"
  def divider, do: "divide-zinc-200"

  # ── Primary button ────────────────────────────────────
  def btn_primary do
    "rounded-lg bg-zinc-900 px-5 py-2 text-white font-medium hover:bg-zinc-700 focus:outline-none focus:ring-2 focus:ring-zinc-400 transition-colors"
  end

  # ── Secondary / outline button ────────────────────────
  def btn_secondary do
    "rounded-lg border border-zinc-300 bg-white px-4 py-2 text-zinc-700 hover:bg-zinc-100 focus:outline-none focus:ring-2 focus:ring-zinc-400 transition-colors"
  end

  # ── Ghost / icon button ──────────────────────────────
  def btn_ghost do
    "text-zinc-400 hover:text-zinc-600 transition-colors"
  end

  # ── Text input ───────────────────────────────────────
  def input do
    "rounded-lg border border-zinc-300 bg-white px-4 py-2 text-zinc-900 placeholder-zinc-400 focus:outline-none focus:ring-2 focus:ring-zinc-400 focus:border-zinc-400"
  end

  # ── Select dropdown ──────────────────────────────────
  def select do
    "appearance-none rounded-lg border border-zinc-300 bg-white pl-4 pr-10 py-2 text-sm text-zinc-900 shadow-sm hover:border-zinc-400 focus:outline-none focus:ring-2 focus:ring-zinc-400 focus:border-zinc-400 cursor-pointer transition-colors"
  end

  # ── Filter pills ─────────────────────────────────────
  def pill_active, do: "bg-zinc-900 text-white border-zinc-900"
  def pill_inactive, do: "bg-white text-zinc-700 border-zinc-300 hover:bg-zinc-100"

  # ── Header ───────────────────────────────────────────
  def header_bg, do: "bg-white"
  def header_border, do: "border-zinc-200"
  def header_brand, do: "text-zinc-900"

  # ── Footer ───────────────────────────────────────────
  def footer_bg, do: "bg-zinc-100"
  def footer_text, do: "text-zinc-500"
  def footer_border, do: "border-zinc-200"
  def footer_link, do: "text-zinc-600 hover:text-zinc-900 transition-colors"

  # ── Modal ────────────────────────────────────────────
  def modal_overlay, do: "bg-black/50"
  def modal_surface, do: "bg-white"

  # ── Pagination ───────────────────────────────────────
  def pagination_btn do
    "rounded border border-zinc-300 bg-white px-3 py-2 text-sm text-zinc-700 hover:bg-zinc-100 transition-colors sm:px-4 sm:text-base"
  end

  def pagination_text, do: "text-zinc-600"

  # ── Card ─────────────────────────────────────────────
  def card_border, do: "border-zinc-200"
  def card_surface, do: "bg-white"

  # ── Reset link ───────────────────────────────────────
  def reset_link do
    "inline-flex items-center gap-1 text-sm text-zinc-500 hover:text-zinc-800 transition-colors"
  end
end
