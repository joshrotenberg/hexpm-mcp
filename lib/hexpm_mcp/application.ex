defmodule HexpmMcp.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    transport = parse_transport()

    children =
      [
        HexpmMcp.Cache
      ] ++ transport_children(transport)

    opts = [strategy: :one_for_one, name: HexpmMcp.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp transport_children(:stdio) do
    [{HexpmMcp.MCP.Server, transport: :stdio}]
  end

  defp transport_children(:http) do
    port = Application.get_env(:hexpm_mcp, :port, 8765)

    [
      {HexpmMcp.MCP.Server, transport: :streamable_http},
      {Bandit, plug: HexpmMcp.MCP.Router, port: port, scheme: :http}
    ]
  end

  defp transport_children(:none), do: []

  defp parse_transport do
    # Config override (for test env)
    case Application.get_env(:hexpm_mcp, :transport) do
      :none -> :none
      _ -> parse_argv()
    end
  end

  defp parse_argv do
    case System.argv() do
      ["--transport", "stdio" | _] -> :stdio
      ["--transport", "http" | _] -> :http
      _ -> :http
    end
  end
end
