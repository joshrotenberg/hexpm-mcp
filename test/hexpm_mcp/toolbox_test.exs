defmodule HexpmMcp.ToolboxTest do
  use ExUnit.Case

  alias HexpmMcp.Toolbox

  setup do
    bypass = Bypass.open()
    Application.put_env(:hexpm_mcp, :toolbox_url, "http://localhost:#{bypass.port}")
    Application.put_env(:hexpm_mcp, :cache_ttl, 0)

    on_exit(fn ->
      Application.delete_env(:hexpm_mcp, :toolbox_url)
    end)

    {:ok, bypass: bypass}
  end

  defp json(conn, status, body) do
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.resp(status, Jason.encode!(body))
  end

  defp project(name, overrides \\ %{}) do
    Map.merge(
      %{
        "name" => name,
        "description" => "#{name} description",
        "latest_stable_version" => "1.0.0",
        "hex_url" => "https://hex.pm/packages/#{name}",
        "docs_url" => "https://#{name}.hexdocs.pm/",
        "updated_at" => "2026-01-01T00:00:00Z",
        "downloads" => %{"all" => 1000, "recent" => 500, "week" => 50, "day" => 5},
        "github" => %{
          "name" => "owner/#{name}",
          "stars" => 42,
          "forks" => 3,
          "open_issues" => 1,
          "pushed_at" => "2026-01-01T00:00:00Z",
          "archived" => false
        },
        "popularity" => 12.5,
        "health" => ["recently_committed"]
      },
      overrides
    )
  end

  describe "groups/0" do
    test "unwraps the data envelope and parses categories", %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/groups", fn conn ->
        json(conn, 200, %{
          "data" => [
            %{
              "title" => "Web",
              "slug" => "web",
              "categories" => [
                %{
                  "name" => "Frameworks",
                  "description" => "Web frameworks",
                  "slug" => "frameworks"
                }
              ]
            }
          ]
        })
      end)

      assert {:ok, [group]} = Toolbox.groups()
      assert group.slug == "web"
      assert [category] = group.categories
      assert category.slug == "frameworks"
      assert category.name == "Frameworks"
    end
  end

  describe "group/1" do
    test "parses a single group", %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/groups/web", fn conn ->
        json(conn, 200, %{
          "data" => %{"title" => "Web", "slug" => "web", "categories" => []}
        })
      end)

      assert {:ok, %{slug: "web", categories: []}} = Toolbox.group("web")
    end

    test "returns :not_found on 404", %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/groups/nope", fn conn ->
        json(conn, 404, %{"error" => "not found"})
      end)

      assert {:error, :not_found} = Toolbox.group("nope")
    end
  end

  describe "category_projects/3" do
    test "parses projects and forwards the sort param", %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/groups/web/frameworks/projects", fn conn ->
        conn = Plug.Conn.fetch_query_params(conn)
        assert conn.query_params["sort"] == "downloads"
        json(conn, 200, %{"data" => [project("phoenix")]})
      end)

      assert {:ok, [p]} = Toolbox.category_projects("web", "frameworks", sort: "downloads")
      assert p.name == "phoenix"
      assert p.popularity == 12.5
      assert p.github.stars == 42
      assert p.health == ["recently_committed"]
    end

    test "omits the sort param when not given", %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/groups/web/frameworks/projects", fn conn ->
        conn = Plug.Conn.fetch_query_params(conn)
        refute Map.has_key?(conn.query_params, "sort")
        json(conn, 200, %{"data" => []})
      end)

      assert {:ok, []} = Toolbox.category_projects("web", "frameworks")
    end
  end

  describe "trending/1" do
    test "forwards the limit param", %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/trending", fn conn ->
        conn = Plug.Conn.fetch_query_params(conn)
        assert conn.query_params["limit"] == "5"
        json(conn, 200, %{"data" => [project("req_llm", %{"gitlab" => nil})]})
      end)

      assert {:ok, [p]} = Toolbox.trending(limit: 5)
      assert p.name == "req_llm"
      assert p.gitlab == nil
    end
  end

  describe "search/1" do
    test "forwards the query and parses results", %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/search", fn conn ->
        conn = Plug.Conn.fetch_query_params(conn)
        assert conn.query_params["q"] == "phoenix"
        json(conn, 200, %{"data" => [project("phoenix", %{"github" => nil, "gitlab" => nil})]})
      end)

      assert {:ok, [p]} = Toolbox.search("phoenix")
      assert p.name == "phoenix"
      assert p.github == nil
    end

    test "returns :bad_request on 400", %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/search", fn conn ->
        json(conn, 400, %{"error" => "bad query"})
      end)

      assert {:error, :bad_request} = Toolbox.search("")
    end
  end
end
