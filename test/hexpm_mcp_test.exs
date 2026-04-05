defmodule HexpmMcpTest do
  use ExUnit.Case

  import HexpmMcp.Test.Fixtures

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
    test "returns structured results", %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/packages", fn conn ->
        respond_json(conn, 200, [
          package_json("phoenix", description: "Web framework", downloads_all: 1_000_000),
          package_json("phoenix_live_view", description: "Rich UIs")
        ])
      end)

      assert {:ok, results} = HexpmMcp.search("phoenix")
      assert length(results) == 2

      first = hd(results)
      assert first.name == "phoenix"
      assert first.description == "Web framework"
      assert first.downloads_all == 1_000_000
      assert first.url == "https://hex.pm/packages/phoenix"
    end

    test "returns empty list when no results", %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/packages", fn conn ->
        respond_json(conn, 200, [])
      end)

      assert {:ok, []} = HexpmMcp.search("nonexistent_package_xyz")
    end
  end

  describe "get_info/1" do
    test "returns structured package info", %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/packages/plug", fn conn ->
        respond_json(
          conn,
          200,
          package_json("plug",
            description: "Composable modules",
            licenses: ["Apache-2.0"],
            downloads_all: 156_000_000
          )
        )
      end)

      assert {:ok, info} = HexpmMcp.get_info("plug")
      assert info.name == "plug"
      assert info.description == "Composable modules"
      assert info.downloads.all == 156_000_000
      assert info.licenses == ["Apache-2.0"]
      assert info.hex_url == "https://hex.pm/packages/plug"
      assert info.docs_url == "https://hexdocs.pm/plug/"
      assert info.elixir_requirement == "~> 1.14"
    end

    test "returns not_found for missing package", %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/packages/nope", fn conn ->
        Plug.Conn.resp(conn, 404, "")
      end)

      assert {:error, :not_found} = HexpmMcp.get_info("nope")
    end
  end

  describe "get_downloads/1" do
    test "returns download stats", %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/packages/jason", fn conn ->
        respond_json(
          conn,
          200,
          package_json("jason",
            downloads_all: 197_000_000,
            downloads_recent: 4_000_000,
            downloads_week: 350_000,
            downloads_day: 50_000
          )
        )
      end)

      assert {:ok, dl} = HexpmMcp.get_downloads("jason")
      assert dl.name == "jason"
      assert dl.all == 197_000_000
      assert dl.recent == 4_000_000
      assert dl.week == 350_000
      assert dl.day == 50_000
    end
  end

  describe "get_owners/1" do
    test "returns owner list", %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/packages/plug/owners", fn conn ->
        respond_json(conn, 200, [
          owner_json("josevalim"),
          owner_json("ericmj", email: "eric@example.com")
        ])
      end)

      assert {:ok, owners} = HexpmMcp.get_owners("plug")
      assert length(owners) == 2
      assert hd(owners).username == "josevalim"
    end
  end

  describe "get_versions/1" do
    test "returns versions with retirement info", %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/packages/plug", fn conn ->
        respond_json(
          conn,
          200,
          package_json("plug",
            retirements: %{
              "0.9.0" => %{"reason" => "security", "message" => "CVE-2024-1234"}
            }
          )
        )
      end)

      assert {:ok, data} = HexpmMcp.get_versions("plug")
      assert data.name == "plug"
      assert length(data.versions) == 2

      retired = Enum.find(data.versions, &(&1.version == "0.9.0"))
      assert retired.retired.reason == "security"
      assert retired.retired.message == "CVE-2024-1234"

      current = Enum.find(data.versions, &(&1.version == "1.0.0"))
      assert current.retired == nil
    end
  end

  describe "get_reverse_dependencies/1" do
    test "returns dependents", %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/packages/jason/reverse_dependencies", fn conn ->
        respond_json(conn, 200, [
          package_json("phoenix", description: "Web framework"),
          package_json("ecto", description: "Database toolkit")
        ])
      end)

      assert {:ok, data} = HexpmMcp.get_reverse_dependencies("jason")
      assert data.name == "jason"
      assert length(data.dependents) == 2
      assert hd(data.dependents).name == "phoenix"
    end
  end

  describe "get_release/2" do
    test "returns release details with explicit version", %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/packages/plug/releases/1.15.0", fn conn ->
        respond_json(
          conn,
          200,
          release_json("1.15.0",
            publisher: "josevalim",
            requirements: %{
              "mime" => %{"requirement" => "~> 2.0", "optional" => false},
              "plug_crypto" => %{"requirement" => "~> 2.1", "optional" => false}
            }
          )
        )
      end)

      assert {:ok, rel} = HexpmMcp.get_release("plug", "1.15.0")
      assert rel.name == "plug"
      assert rel.version == "1.15.0"
      assert rel.publisher == "josevalim"
      assert length(rel.dependencies) == 2
      assert rel.retired == nil
    end

    test "resolves latest version when nil", %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/packages/plug", fn conn ->
        respond_json(conn, 200, package_json("plug", stable_version: "1.19.1"))
      end)

      Bypass.expect_once(bypass, "GET", "/packages/plug/releases/1.19.1", fn conn ->
        respond_json(conn, 200, release_json("1.19.1"))
      end)

      assert {:ok, rel} = HexpmMcp.get_release("plug")
      assert rel.version == "1.19.1"
    end

    test "includes retirement info", %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/packages/old_pkg/releases/0.1.0", fn conn ->
        respond_json(
          conn,
          200,
          release_json("0.1.0",
            retirement: %{"reason" => "deprecated", "message" => "Use new_pkg instead"}
          )
        )
      end)

      assert {:ok, rel} = HexpmMcp.get_release("old_pkg", "0.1.0")
      assert rel.retired.reason == "deprecated"
      assert rel.retired.message == "Use new_pkg instead"
    end
  end

  describe "get_dependencies/2" do
    test "returns sorted dependency list", %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/packages/req/releases/0.5.0", fn conn ->
        respond_json(
          conn,
          200,
          release_json("0.5.0",
            requirements: %{
              "mime" => %{"requirement" => "~> 2.0", "optional" => false},
              "finch" => %{"requirement" => "~> 0.17", "optional" => false},
              "jason" => %{"requirement" => "~> 1.0", "optional" => true}
            }
          )
        )
      end)

      assert {:ok, data} = HexpmMcp.get_dependencies("req", "0.5.0")
      assert data.name == "req"
      assert data.version == "0.5.0"
      assert length(data.dependencies) == 3

      # Sorted alphabetically
      names = Enum.map(data.dependencies, & &1.name)
      assert names == ["finch", "jason", "mime"]

      # Optional flag preserved
      jason = Enum.find(data.dependencies, &(&1.name == "jason"))
      assert jason.optional == true
    end

    test "returns empty list when no deps", %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/packages/simple/releases/1.0.0", fn conn ->
        respond_json(conn, 200, release_json("1.0.0", requirements: %{}))
      end)

      assert {:ok, data} = HexpmMcp.get_dependencies("simple", "1.0.0")
      assert data.dependencies == []
    end
  end

  describe "get_features/2" do
    test "returns optional deps and extra metadata", %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/packages/req/releases/0.5.0", fn conn ->
        respond_json(
          conn,
          200,
          release_json("0.5.0",
            requirements: %{
              "finch" => %{"requirement" => "~> 0.17", "optional" => false},
              "jason" => %{"requirement" => "~> 1.0", "optional" => true},
              "brotli" => %{"requirement" => "~> 0.3", "optional" => true}
            }
          )
        )
      end)

      assert {:ok, data} = HexpmMcp.get_features("req", "0.5.0")
      assert length(data.optional_deps) == 2
      names = Enum.map(data.optional_deps, & &1.name)
      assert "jason" in names
      assert "brotli" in names
    end
  end

  describe "compare_packages/1" do
    test "returns comparison data for multiple packages", %{bypass: bypass} do
      Bypass.stub(bypass, "GET", "/packages/plug", fn conn ->
        respond_json(conn, 200, package_json("plug", downloads_all: 100_000))
      end)

      Bypass.stub(bypass, "GET", "/packages/plug/releases/1.0.0", fn conn ->
        respond_json(
          conn,
          200,
          release_json("1.0.0",
            requirements: %{"mime" => %{"requirement" => "~> 2.0", "optional" => false}}
          )
        )
      end)

      Bypass.stub(bypass, "GET", "/packages/bandit", fn conn ->
        respond_json(conn, 200, package_json("bandit", downloads_all: 50_000))
      end)

      Bypass.stub(bypass, "GET", "/packages/bandit/releases/1.0.0", fn conn ->
        respond_json(conn, 200, release_json("1.0.0", requirements: %{}))
      end)

      assert {:ok, packages} = HexpmMcp.compare_packages(["plug", "bandit"])
      assert length(packages) == 2

      plug = Enum.find(packages, &(&1.name == "plug"))
      assert plug.downloads_all == 100_000
      assert plug.dep_count == 1
    end

    test "rejects fewer than 2 packages" do
      assert {:error, :too_few_packages} = HexpmMcp.compare_packages(["solo"])
    end

    test "rejects more than 5 packages" do
      names = Enum.map(1..6, &"pkg_#{&1}")
      assert {:error, :too_many_packages} = HexpmMcp.compare_packages(names)
    end
  end

  describe "health_check/1" do
    test "returns structured health report", %{bypass: bypass} do
      Bypass.stub(bypass, "GET", "/packages/req", fn conn ->
        respond_json(
          conn,
          200,
          package_json("req",
            downloads_all: 11_000_000,
            downloads_recent: 1_600_000,
            inserted_at: "2022-01-01T00:00:00Z",
            updated_at: "2026-02-01T00:00:00Z"
          )
        )
      end)

      Bypass.stub(bypass, "GET", "/packages/req/owners", fn conn ->
        respond_json(conn, 200, [owner_json("wojtekmach")])
      end)

      Bypass.stub(bypass, "GET", "/packages/req/releases/1.0.0", fn conn ->
        respond_json(
          conn,
          200,
          release_json("1.0.0",
            requirements: %{
              "finch" => %{"requirement" => "~> 0.17", "optional" => false},
              "jason" => %{"requirement" => "~> 1.0", "optional" => true}
            }
          )
        )
      end)

      assert {:ok, health} = HexpmMcp.health_check("req")
      assert health.name == "req"
      assert health.maintenance.status == "Active"
      assert health.popularity.all == 11_000_000
      assert health.quality.has_docs == true
      assert health.quality.required_deps == 1
      assert health.quality.optional_deps == 1
      assert health.risk.owner_count == 1
      assert health.risk.retired_count == 0
      assert health.links[:hex_url] == "https://hex.pm/packages/req"
    end

    test "returns not_found for missing package", %{bypass: bypass} do
      Bypass.stub(bypass, "GET", "/packages/nope", fn conn ->
        Plug.Conn.resp(conn, 404, "")
      end)

      Bypass.stub(bypass, "GET", "/packages/nope/owners", fn conn ->
        Plug.Conn.resp(conn, 404, "")
      end)

      assert {:error, :not_found} = HexpmMcp.health_check("nope")
    end
  end

  describe "audit_dependencies/2" do
    test "returns audit results", %{bypass: bypass} do
      # Package with one dep
      Bypass.stub(bypass, "GET", "/packages/myapp/releases/1.0.0", fn conn ->
        respond_json(
          conn,
          200,
          release_json("1.0.0",
            requirements: %{
              "jason" => %{"requirement" => "~> 1.0", "optional" => false}
            }
          )
        )
      end)

      # Jason package info
      Bypass.stub(bypass, "GET", "/packages/jason", fn conn ->
        respond_json(conn, 200, package_json("jason"))
      end)

      # Jason owners (single maintainer)
      Bypass.stub(bypass, "GET", "/packages/jason/owners", fn conn ->
        respond_json(conn, 200, [owner_json("michalmuskala")])
      end)

      assert {:ok, audit} = HexpmMcp.audit_dependencies("myapp", "1.0.0")
      assert audit.total_checked == 1

      jason_result = hd(audit.results)
      assert jason_result.name == "jason"
      assert "single maintainer" in jason_result.issues
    end

    test "returns empty audit for no deps", %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/packages/nodeps/releases/1.0.0", fn conn ->
        respond_json(conn, 200, release_json("1.0.0", requirements: %{}))
      end)

      assert {:ok, audit} = HexpmMcp.audit_dependencies("nodeps", "1.0.0")
      assert audit.total_checked == 0
      assert audit.results == []
    end
  end
end
