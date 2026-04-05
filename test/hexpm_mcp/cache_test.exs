defmodule HexpmMcp.CacheTest do
  use ExUnit.Case, async: false

  alias HexpmMcp.Cache

  setup do
    # Enable caching for these tests (test config sets TTL to 0)
    prev_ttl = Application.get_env(:hexpm_mcp, :cache_ttl, 0)
    Application.put_env(:hexpm_mcp, :cache_ttl, 300)
    Cache.clear()

    on_exit(fn ->
      Application.put_env(:hexpm_mcp, :cache_ttl, prev_ttl)
      Cache.clear()
    end)

    :ok
  end

  describe "put/2 and lookup/1" do
    test "stores and retrieves a value" do
      Cache.put(:test_key, "hello")
      assert {:ok, "hello"} = Cache.lookup(:test_key)
    end

    test "returns :miss for unknown keys" do
      assert :miss = Cache.lookup(:unknown_key)
    end

    test "stores complex values" do
      value = %{name: "test", data: [1, 2, 3]}
      Cache.put({:complex, "key"}, value)
      assert {:ok, ^value} = Cache.lookup({:complex, "key"})
    end
  end

  describe "fetch/3" do
    test "calls function on cache miss" do
      result =
        Cache.fetch(:fetch_test, 300, fn ->
          {:ok, "computed"}
        end)

      assert result == {:ok, "computed"}
    end

    test "returns cached value on hit" do
      counter = :counters.new(1, [])

      fun = fn ->
        :counters.add(counter, 1, 1)
        {:ok, "computed"}
      end

      # First call computes
      Cache.fetch(:counter_test, 300, fun)
      assert :counters.get(counter, 1) == 1

      # Second call returns cached
      result = Cache.fetch(:counter_test, 300, fun)
      assert result == {:ok, "computed"}
      assert :counters.get(counter, 1) == 1
    end

    test "bypasses cache when TTL is 0" do
      counter = :counters.new(1, [])

      fun = fn ->
        :counters.add(counter, 1, 1)
        {:ok, "computed"}
      end

      Cache.fetch(:zero_ttl, 0, fun)
      Cache.fetch(:zero_ttl, 0, fun)
      assert :counters.get(counter, 1) == 2
    end
  end

  describe "clear/0" do
    test "removes all entries" do
      Cache.put(:a, 1)
      Cache.put(:b, 2)
      Cache.clear()
      assert :miss = Cache.lookup(:a)
      assert :miss = Cache.lookup(:b)
    end
  end
end
