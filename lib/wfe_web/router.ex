defmodule WfeWeb.Router do
  use WfeWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {WfeWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", WfeWeb do
    pipe_through :browser

    live "/", JobSearchLive, :index
  end

  if Application.compile_env(:wfe, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard",
        metrics: WfeWeb.Telemetry,
        additional_pages: [oban: Oban.LiveDashboard]

      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end

    scope "/admin", WfeWeb do
      pipe_through :browser

      live "/scraping", ScrapingDashboardLive, :index
      live "/scraping/run/:run_id", ScrapingDashboardLive, :run_detail
      live "/scraping/company/:company_id", ScrapingDashboardLive, :company_detail
    end
  end
end
