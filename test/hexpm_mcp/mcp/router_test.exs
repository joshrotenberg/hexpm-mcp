defmodule HexpmMcp.MCP.RouterTest do
  use ExUnit.Case, async: true

  import Plug.Test
  import Plug.Conn

  alias HexpmMcp.MCP.Router

  describe "unmatched paths" do
    test "the root says where the MCP endpoint actually is" do
      conn = Router.call(conn(:get, "/"), [])

      assert conn.status == 404
      assert conn.resp_body =~ "/mcp"
    end

    test "any other path does the same" do
      conn = Router.call(conn(:post, "/rpc"), [])

      assert conn.status == 404
      assert conn.resp_body =~ "/mcp"
    end
  end

  describe "/mcp" do
    test "is handed to the MCP transport rather than falling through to 404" do
      # The test env starts no MCP server (transport: :none), so the transport
      # raises looking up its session config. Raising from inside Anubis is the
      # assertion: the request reached the transport instead of our 404 clause.
      assert_raise ArgumentError, fn -> Router.call(conn(:get, "/mcp"), []) end
    end
  end
end
