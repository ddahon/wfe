defmodule Wfe.Repo do
  use Ecto.Repo,
    otp_app: :wfe,
    adapter: Ecto.Adapters.SQLite3

  def configure_sqlite(conn) do
    # WAL mode: readers don't block writers (critical since scraping writes
    # while the web UI reads)
    Exqlite.Sqlite3.execute(conn, "PRAGMA journal_mode = WAL")

    # NORMAL is safe with WAL and much faster than FULL
    Exqlite.Sqlite3.execute(conn, "PRAGMA synchronous = NORMAL")

    # Memory-mapped I/O — 256MB cap. Big wins on repeated scans.
    Exqlite.Sqlite3.execute(conn, "PRAGMA mmap_size = 268435456")

    # Negative = KB. 64MB page cache per connection.
    Exqlite.Sqlite3.execute(conn, "PRAGMA cache_size = -64000")

    # Temp sorts (if any) stay in memory
    Exqlite.Sqlite3.execute(conn, "PRAGMA temp_store = MEMORY")

    # Enforce FK constraints (off by default in SQLite!)
    Exqlite.Sqlite3.execute(conn, "PRAGMA foreign_keys = ON")

    :ok
  end
end
