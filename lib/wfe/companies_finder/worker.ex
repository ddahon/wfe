defmodule Wfe.CompaniesFinder.Worker do
  @moduledoc """
  GenServer that runs company discovery on a schedule.

  By default, runs every 24 hours. Can also be triggered manually.
  """

  use GenServer
  require Logger

  alias Wfe.CompaniesFinder.Finder

  @default_interval :timer.hours(24)

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Trigger a discovery run immediately (async).
  """
  def run_now do
    GenServer.cast(__MODULE__, :run)
  end

  @doc """
  Trigger a discovery run and wait for completion (sync).
  """
  def run_sync(timeout \\ :infinity) do
    GenServer.call(__MODULE__, :run_sync, timeout)
  end

  @doc """
  Get the current worker status.
  """
  def status do
    GenServer.call(__MODULE__, :status)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    interval = Keyword.get(opts, :interval, @default_interval)
    run_on_start = Keyword.get(opts, :run_on_start, false)

    state = %{
      interval: interval,
      status: :idle,
      last_run_at: nil,
      last_result: nil,
      next_run_at: nil
    }

    state =
      if run_on_start do
        send(self(), :run)
        %{state | status: :scheduled}
      else
        schedule_run(state)
      end

    {:ok, state}
  end

  @impl true
  def handle_cast(:run, state) do
    {:noreply, do_run(state)}
  end

  @impl true
  def handle_call(:run_sync, _from, state) do
    new_state = do_run(state)
    {:reply, new_state.last_result, new_state}
  end

  @impl true
  def handle_call(:status, _from, state) do
    {:reply, Map.take(state, [:status, :last_run_at, :last_result, :next_run_at]), state}
  end

  @impl true
  def handle_info(:run, state) do
    {:noreply, do_run(state)}
  end

  @impl true
  def handle_info(:scheduled_run, state) do
    {:noreply, do_run(state)}
  end

  defp do_run(state) do
    Logger.info("Company discovery worker starting...")

    state = %{state | status: :running}

    result =
      try do
        Finder.discover_all()
      rescue
        e ->
          Logger.error("Company discovery crashed: #{Exception.message(e)}")
          Logger.error(Exception.format(:error, e, __STACKTRACE__))
          {:error, Exception.message(e)}
      end

    state
    |> Map.merge(%{
      status: :idle,
      last_run_at: DateTime.utc_now(),
      last_result: result
    })
    |> schedule_run()
  end

  defp schedule_run(state) do
    next_run_at = DateTime.utc_now() |> DateTime.add(state.interval, :millisecond)
    Process.send_after(self(), :scheduled_run, state.interval)
    %{state | next_run_at: next_run_at}
  end
end
