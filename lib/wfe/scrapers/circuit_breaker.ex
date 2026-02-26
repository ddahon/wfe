defmodule Wfe.Scrapers.CircuitBreaker do
  @moduledoc """
  Tracks consecutive failures per ATS. After `@threshold` failures,
  pauses the corresponding Oban queue for `@cooldown_ms`, then
  auto-resumes. Resumes all queues on application start (crash recovery).
  """
  use GenServer
  require Logger

  @threshold 3
  @cooldown_ms :timer.minutes(15)
  @queues ~w(greenhouse lever ashby)a

  # --- Client ---

  def start_link(_), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  def record_success(ats), do: GenServer.cast(__MODULE__, {:success, ats})
  def record_failure(ats), do: GenServer.cast(__MODULE__, {:failure, ats})

  # --- Server ---

  @impl true
  def init(_) do
    # Resume any paused queues on boot (in case app crashed while paused)
    Process.send_after(self(), :resume_all, 2_000)
    {:ok, %{}}
  end

  @impl true
  def handle_cast({:success, ats}, state) do
    {:noreply, Map.delete(state, ats)}
  end

  @impl true
  def handle_cast({:failure, ats}, state) do
    failures = Map.get(state, ats, 0) + 1

    if failures >= @threshold do
      Logger.warning(
        "[CircuitBreaker] #{ats}: #{failures} consecutive failures — pausing queue for #{div(@cooldown_ms, 60_000)}min"
      )

      Oban.pause_queue(queue: String.to_existing_atom(ats))
      Process.send_after(self(), {:resume, ats}, @cooldown_ms)
      {:noreply, Map.delete(state, ats)}
    else
      Logger.info("[CircuitBreaker] #{ats}: failure #{failures}/#{@threshold}")
      {:noreply, Map.put(state, ats, failures)}
    end
  end

  @impl true
  def handle_info({:resume, ats}, state) do
    Logger.info("[CircuitBreaker] #{ats}: cooldown over — resuming queue")
    Oban.resume_queue(queue: String.to_existing_atom(ats))
    {:noreply, state}
  end

  @impl true
  def handle_info(:resume_all, state) do
    Enum.each(@queues, &Oban.resume_queue(queue: &1))
    {:noreply, state}
  end
end
