defmodule HexpmMcp.ClientTest do
  use ExUnit.Case

  alias HexpmMcp.Client

  setup do
    bypass = Bypass.open()
    Application.put_env(:hexpm_mcp, :hex_api_url, "http://localhost:#{bypass.port}")
    Application.put_env(:hexpm_mcp, :rate_limit_ms, 0)
    Application.put_env(:hexpm_mcp, :cache_ttl, 0)

    on_exit(fn ->
      Application.delete_env(:hexpm_mcp, :hex_api_url)
    end)

    {:ok, bypass: bypass}
  end

  describe "search/2" do
    test "returns parsed packages", %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/packages", fn conn ->
        conn = Plug.Conn.fetch_query_params(conn)
        assert conn.query_params["search"] == "phoenix"

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          Jason.encode!([
            %{
              "name" => "phoenix",
              "latest_version" => "1.7.0",
              "latest_stable_version" => "1.7.0",
              "meta" => %{"description" => "Web framework"},
              "downloads" => %{"all" => 1000},
              "releases" => [],
              "retirements" => %{}
            }
          ])
        )
      end)

      assert {:ok, [pkg]} = Client.search("phoenix")
      assert pkg.name == "phoenix"
      assert pkg.latest_version == "1.7.0"
    end

    test "returns not_found for 404", %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/packages", fn conn ->
        Plug.Conn.resp(conn, 404, "")
      end)

      assert {:error, :not_found} = Client.search("nonexistent")
    end
  end

  describe "get_package/1" do
    test "returns parsed package", %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/packages/plug", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          Jason.encode!(%{
            "name" => "plug",
            "latest_version" => "1.15.0",
            "latest_stable_version" => "1.15.0",
            "meta" => %{"description" => "Composable modules"},
            "downloads" => %{"all" => 50_000},
            "releases" => [],
            "retirements" => %{}
          })
        )
      end)

      assert {:ok, pkg} = Client.get_package("plug")
      assert pkg.name == "plug"
    end
  end

  describe "get_release/2" do
    test "returns parsed release", %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/packages/plug/releases/1.15.0", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          Jason.encode!(%{
            "version" => "1.15.0",
            "has_docs" => true,
            "downloads" => 1234,
            "requirements" => %{
              "mime" => %{"requirement" => "~> 2.0", "optional" => false}
            },
            "meta" => %{"build_tools" => ["mix"]},
            "publisher" => %{"username" => "josevalim"}
          })
        )
      end)

      assert {:ok, rel} = Client.get_release("plug", "1.15.0")
      assert rel.version == "1.15.0"
      assert rel.has_docs == true
      assert map_size(rel.requirements) == 1
    end
  end

  describe "get_owners/1" do
    test "returns parsed owners", %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/packages/plug/owners", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          Jason.encode!([
            %{"username" => "josevalim", "email" => "jose@example.com"}
          ])
        )
      end)

      assert {:ok, [owner]} = Client.get_owners("plug")
      assert owner.username == "josevalim"
    end
  end
end
