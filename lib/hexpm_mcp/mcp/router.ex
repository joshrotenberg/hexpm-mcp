defmodule HexpmMcp.MCP.Router do
  @moduledoc """
  Plug router for the HTTP transport.
  """

  use Plug.Builder

  alias Anubis.Server.Transport.StreamableHTTP

  plug(:route)

  defp route(%{path_info: ["mcp" | _]} = conn, _opts) do
    opts = StreamableHTTP.Plug.init(server: HexpmMcp.MCP.Server)
    StreamableHTTP.Plug.call(conn, opts)
  end

  defp route(conn, _opts) do
    Plug.Conn.send_resp(conn, 404, "not found")
  end
end
