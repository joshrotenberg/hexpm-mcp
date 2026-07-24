defmodule HexpmMcp.MCP.StdioLifecycleTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias HexpmMcp.MCP.StdioLifecycle

  # The clean-stop branch calls System.halt/1, which would take the test run
  # down with it, so it is covered by the binary smoke test rather than here.
  # What is testable is that everything else is left alone.

  describe "handle_info/2" do
    test "ignores a transport that died abnormally, leaving it to the supervisor" do
      state = %{server: HexpmMcp.MCP.Server}
      down = {:DOWN, make_ref(), :process, self(), :killed}

      assert StdioLifecycle.handle_info(down, state) == {:noreply, state}
    end

    test "ignores an exit reason that is neither normal nor shutdown" do
      state = %{server: HexpmMcp.MCP.Server}
      down = {:DOWN, make_ref(), :process, self(), {:error, :badarg}}

      assert StdioLifecycle.handle_info(down, state) == {:noreply, state}
    end

    test "ignores unrelated messages" do
      state = %{server: HexpmMcp.MCP.Server}

      assert StdioLifecycle.handle_info(:tick, state) == {:noreply, state}
    end
  end

  describe "handle_continue/2" do
    test "warns and carries on when no stdio transport is registered" do
      state = %{server: __MODULE__.NoSuchServer}

      log =
        capture_log(fn ->
          assert StdioLifecycle.handle_continue(:monitor, state) == {:noreply, state}
        end)

      assert log =~ "stdio transport not registered"
    end

    test "monitors the transport when one is registered" do
      # Stand in for the Anubis transport under the name it would register.
      name = Anubis.Server.Registry.transport_name(__MODULE__.FakeServer, :stdio)
      pid = spawn(fn -> Process.sleep(:infinity) end)
      true = Process.register(pid, name)
      on_exit(fn -> if Process.alive?(pid), do: Process.exit(pid, :kill) end)

      state = %{server: __MODULE__.FakeServer}

      assert StdioLifecycle.handle_continue(:monitor, state) == {:noreply, state}

      # A monitor is in place, so killing the stand-in delivers :DOWN here.
      Process.exit(pid, :kill)
      assert_receive {:DOWN, _ref, :process, ^pid, :killed}
    end
  end
end
