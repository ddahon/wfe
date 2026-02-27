# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :wfe,
  ecto_repos: [Wfe.Repo],
  generators: [timestamp_type: :utc_datetime]

config :wfe, :generators, binary_id: true

config :wfe, Wfe.Repo,
  migration_primary_key: [type: :binary_id],
  migration_foreign_key: [type: :binary_id]

# Configure the endpoint
config :wfe, WfeWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: WfeWeb.ErrorHTML, json: WfeWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Wfe.PubSub,
  live_view: [signing_salt: "P25ADg3X"]

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :wfe, Wfe.Mailer, adapter: Swoosh.Adapters.Local

config :wfe, :companies_finder,
  # Run every 24 hours
  interval: :timer.hours(24),
  # Don't run on application start (set to true for production)
  run_on_start: false

# config/prod.exs
config :wfe, :companies_finder, run_on_start: true

config :wfe, Oban,
  # Required for SQLite
  engine: Oban.Engines.Lite,
  repo: Wfe.Repo,
  queues: [
    default: 5,
    # One job at a time per ATS
    greenhouse: 1,
    lever: 1,
    ashby: 1
  ],
  plugins: [
    {Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 7},
    {Oban.Plugins.Cron,
     crontab: [
       # Run orchestrator every 6 hours
       {"0 */6 * * *", Wfe.Workers.ScrapeOrchestrator}
     ]}
  ]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  wfe: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.12",
  wfe: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
