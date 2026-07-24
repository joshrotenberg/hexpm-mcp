defmodule HexpmMcp.MCP.StdioLifecycle do
  @moduledoc """
  Halts the VM cleanly when a stdio client disconnects.

  Anubis stops its stdio transport with `:normal` on EOF, which is the correct
  reading of "the client went away". But the transport is a permanent child, so
  the supervisor restarts it, the new transport reads EOF immediately, and the
  cycle repeats until the restart intensity is exceeded. The supervisor then
  gives up, the application exits, and because releases are built with
  `start_permanent: true` a terminating permanent application takes the node
  down abnormally: exit status 1 and an `erl_crash.dump` on disk.

  An MCP client reads that as the server having crashed on every ordinary
  disconnect. This process monitors the transport and turns the first clean stop
  into `System.halt(0)`, ahead of the restart storm.

  Only an orderly stop is treated this way. A transport that dies for any other
  reason is left to the supervisor, so real failures still restart and still
  surface.
  """

  use GenServer

  alias Anubis.Server.Registry

  require Logger

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    {:ok, %{server: Keyword.get(opts, :server, HexpmMcp.MCP.Server)}, {:continue, :monitor}}
  end

  @impl true
  def handle_continue(:monitor, state) do
    # This process starts after the MCP server, so the transport is already
    # registered. If it somehow is not, there is nothing to watch and no reason
    # to hold up boot.
    case GenServer.whereis(Registry.transport_name(state.server, :stdio)) do
      nil ->
        Logger.warning("stdio transport not registered; client disconnect will not halt cleanly")
        {:noreply, state}

      pid ->
        Process.monitor(pid)
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, _pid, reason}, state)
      when reason in [:normal, :shutdown] do
    System.halt(0)
    {:noreply, state}
  end

  def handle_info({:DOWN, _ref, :process, _pid, _reason}, state) do
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}
end
