defmodule HexpmMcp.Application do
  @moduledoc false

  use Application

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
      :none ->
        {:serve, [transport: :none, port: nil]}

      _ ->
        case Cheer.run(HexpmMcp.CLI, HexpmMcp.CLI.argv(), prog: "hexpm_mcp") do
          {:serve, opts} -> {:serve, opts}
          # Cheer already printed help or version.
          :ok -> :handled
          # Cheer already printed the usage error.
          {:error, :usage} -> :usage_error
        end
    end
  end

  defp start_supervisor(opts) do
    children = [HexpmMcp.Cache] ++ transport_children(opts)

    Supervisor.start_link(children, strategy: :one_for_one, name: HexpmMcp.Supervisor)
  end

  defp transport_children(opts) do
    case Keyword.fetch!(opts, :transport) do
      :stdio ->
        [{HexpmMcp.MCP.Server, transport: :stdio}]

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
