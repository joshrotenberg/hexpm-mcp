defmodule HexpmMcp.Application do
  @moduledoc false

  use Application

  require Logger

  # start/2 halts on --help, --version, and usage errors, so it does not always
  # return. That is intended for a CLI entry point, not a defect.
  @dialyzer {:nowarn_function, start: 2}

  @impl true
  def start(_type, _args) do
    case resolve_config() do
      {:serve, opts} -> start_supervisor(opts)
      :handled -> System.halt(0)
      :usage_error -> System.halt(2)
    end
  end

  # The :transport config override exists for the test env, which must not have
  # its own argv parsed as ours.
  defp resolve_config do
    case Application.get_env(:hexpm_mcp, :transport) do
      :none -> {:serve, [transport: :none, port: nil]}
      _ -> HexpmMcp.CLI.parse()
    end
  end

  defp start_supervisor(opts) do
    children = [HexpmMcp.Cache] ++ transport_children(opts)

    with {:ok, pid} <-
           Supervisor.start_link(children, strategy: :one_for_one, name: HexpmMcp.Supervisor) do
      log_endpoint(opts)
      {:ok, pid}
    end
  end

  # Bandit's own startup line reports the bind address but not the path, and the
  # server only answers on /mcp. Clients that guess the root get a 404, so say
  # where it is. Logging goes to stderr, so this is safe in stdio mode too, but
  # there is no endpoint to report there.
  defp log_endpoint(opts) do
    if Keyword.fetch!(opts, :transport) == :http do
      Logger.info("MCP endpoint: http://localhost:#{port(opts)}/mcp")
    end
  end

  defp transport_children(opts) do
    case Keyword.fetch!(opts, :transport) do
      :stdio ->
        # StdioLifecycle must come after the server so the transport it watches
        # is already registered.
        [
          {HexpmMcp.MCP.Server, transport: :stdio},
          HexpmMcp.MCP.StdioLifecycle
        ]

      :http ->
        [
          {HexpmMcp.MCP.Server, transport: :streamable_http},
          {Bandit, plug: HexpmMcp.MCP.Router, port: port(opts), scheme: :http}
        ]

      :none ->
        []
    end
  end

  # --port wins when given; otherwise fall back to app config, which runtime.exs
  # populates from HEXPM_MCP_PORT in prod.
  defp port(opts) do
    Keyword.get(opts, :port) || Application.get_env(:hexpm_mcp, :port, 8765)
  end
end
