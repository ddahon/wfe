defmodule Wfe.Repo do
  use Ecto.Repo,
    otp_app: :wfe,
    adapter: Ecto.Adapters.SQLite3
end
