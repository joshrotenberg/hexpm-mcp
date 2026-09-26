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

  # The native listener binds only the MCP endpoint, so report its full URL.
  defp log_endpoint(opts) do
    if Keyword.fetch!(opts, :transport) == :http do
      Logger.info("MCP endpoint: http://localhost:#{port(opts)}/mcp")
    end
  end

  defp transport_children(opts) do
    case Keyword.fetch!(opts, :transport) do
      :stdio ->
        [
          {HexpmMcp.MCP.StdioLifecycle, runtime: HexpmMcp.MCP.Server.runtime()}
        ]

      :http ->
        [
          {Snodo.Transport.StreamableHTTP.Server,
           runtime: HexpmMcp.MCP.Server.runtime(),
           ip: {0, 0, 0, 0},
           port: port(opts),
           allowed_origin_hosts: allowed_origin_hosts()}
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

  defp allowed_origin_hosts do
    Application.get_env(
      :hexpm_mcp,
      :allowed_origin_hosts,
      ["127.0.0.1", "localhost", "::1", "hexpm-mcp.fly.dev"]
    )
  end
end
