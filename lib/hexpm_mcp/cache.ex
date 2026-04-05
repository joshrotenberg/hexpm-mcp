defmodule HexpmMcp.Cache do
  @moduledoc """
  ETS-based response cache with configurable TTL and periodic sweeping.
  """

  use GenServer

  @table __MODULE__
  @sweep_interval :timer.seconds(60)

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Fetch a cached value or compute it.

  Returns the cached value if present and not expired, otherwise calls `fun`
  and caches the result.
  """
  def fetch(key, ttl \\ nil, fun) do
    ttl = ttl || default_ttl()

    if ttl == 0 do
      fun.()
    else
      case lookup(key) do
        {:ok, value} ->
          value

        :miss ->
          value = fun.()
          put(key, value)
          value
      end
    end
  end

  @doc """
  Look up a cached value by key.
  """
  def lookup(key) do
    ttl = default_ttl()

    case :ets.lookup(@table, key) do
      [{^key, value, inserted_at}] ->
        if ttl > 0 and not expired?(inserted_at, ttl) do
          {:ok, value}
        else
          :ets.delete(@table, key)
          :miss
        end

      [] ->
        :miss
    end
  rescue
    ArgumentError -> :miss
  end

  @doc """
  Store a value in the cache.
  """
  def put(key, value) do
    :ets.insert(@table, {key, value, System.monotonic_time(:second)})
    :ok
  rescue
    ArgumentError -> :ok
  end

  @doc """
  Clear all cached entries.
  """
  def clear do
    :ets.delete_all_objects(@table)
    :ok
  rescue
    ArgumentError -> :ok
  end

  # GenServer callbacks

  @impl true
  def init(_opts) do
    table = :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    schedule_sweep()
    {:ok, %{table: table}}
  end

  @impl true
  def handle_info(:sweep, state) do
    sweep()
    schedule_sweep()
    {:noreply, state}
  end

  defp sweep do
    ttl = default_ttl()
    now = System.monotonic_time(:second)

    :ets.foldl(
      fn {key, _value, inserted_at}, acc ->
        if expired?(inserted_at, ttl, now), do: :ets.delete(@table, key)
        acc
      end,
      :ok,
      @table
    )
  rescue
    ArgumentError -> :ok
  end

  defp expired?(inserted_at, ttl, now \\ System.monotonic_time(:second)) do
    now - inserted_at > ttl
  end

  defp schedule_sweep do
    Process.send_after(self(), :sweep, @sweep_interval)
  end

  defp default_ttl do
    Application.get_env(:hexpm_mcp, :cache_ttl, 300)
  end
end
