defmodule HexpmMcp.FormatterTest do
  use ExUnit.Case, async: true

  alias HexpmMcp.Formatter

  describe "format_number/1" do
    test "formats millions" do
      assert Formatter.format_number(1_234_567) == "1.2M"
      assert Formatter.format_number(5_000_000) == "5.0M"
    end

    test "formats thousands" do
      assert Formatter.format_number(45_678) == "45.7K"
      assert Formatter.format_number(1_000) == "1.0K"
    end

    test "formats small numbers" do
      assert Formatter.format_number(999) == "999"
      assert Formatter.format_number(0) == "0"
    end

    test "formats nil" do
      assert Formatter.format_number(nil) == "0"
    end
  end

  describe "format_date/1" do
    test "extracts date from ISO string" do
      assert Formatter.format_date("2024-01-15T12:30:00Z") == "2024-01-15"
    end

    test "handles nil" do
      assert Formatter.format_date(nil) == "unknown"
    end
  end

  describe "markdown_table/2 and bullet_list/1" do
    test "builds a markdown table" do
      headers = ["Name", "Value"]
      rows = [["foo", "1"], ["bar", "2"]]

      result = Formatter.markdown_table(headers, rows)
      assert result =~ "| Name"
      assert result =~ "| foo"
      assert result =~ "| bar"
    end

    test "builds a bullet list" do
      assert Formatter.bullet_list(["one", "two"]) == "- one\n- two"
    end
  end

  describe "format_search_results/2" do
    test "formats results with header and entries" do
      results = [
        %{
          name: "jason",
          version: "1.4.4",
          description: "JSON parser",
          downloads_all: 197_000_000,
          downloads_recent: 4_000_000,
          url: "https://hex.pm/packages/jason"
        }
      ]

      out = Formatter.format_search_results("json", results)
      assert out =~ "# Search Results for 'json'"
      assert out =~ "## jason (v1.4.4)"
      assert out =~ "197.0M all-time"
      assert out =~ "https://hex.pm/packages/jason"
    end

    test "handles no results" do
      assert Formatter.format_search_results("nope", []) == "No packages found matching 'nope'."
    end
  end

  describe "format_package_info/1" do
    test "formats full info including links and elixir requirement" do
      info = %{
        name: "plug",
        description: "Composable modules",
        latest_stable_version: "1.19.1",
        latest_version: "1.19.1",
        downloads: %{all: 156_000_000, recent: 3_100_000, week: 250_000, day: 35_000},
        licenses: ["Apache-2.0"],
        build_tools: ["mix"],
        elixir_requirement: "~> 1.14",
        inserted_at: "2014-01-01T00:00:00Z",
        updated_at: "2025-12-09T00:00:00Z",
        docs_url: "https://hexdocs.pm/plug/",
        hex_url: "https://hex.pm/packages/plug",
        links: %{"GitHub" => "https://github.com/elixir-plug/plug"}
      }

      out = Formatter.format_package_info(info)
      assert out =~ "# plug"
      assert out =~ "- Latest stable: 1.19.1"
      assert out =~ "- All-time: 156.0M"
      assert out =~ "- Licenses: Apache-2.0"
      assert out =~ "- Elixir requirement: ~> 1.14"
      assert out =~ "- Docs: https://hexdocs.pm/plug/"
      assert out =~ "- GitHub: https://github.com/elixir-plug/plug"
    end

    test "omits optional sections when absent" do
      info = %{
        name: "tiny",
        description: "d",
        latest_stable_version: nil,
        latest_version: nil,
        downloads: %{all: 0, recent: 0, week: 0, day: 0},
        licenses: [],
        build_tools: [],
        elixir_requirement: nil,
        inserted_at: nil,
        updated_at: nil,
        docs_url: nil,
        hex_url: "https://hex.pm/packages/tiny",
        links: %{}
      }

      out = Formatter.format_package_info(info)
      assert out =~ "- Latest stable: none"
      refute out =~ "Elixir requirement"
      refute out =~ "Docs:"
    end
  end

  describe "format_versions/1" do
    test "formats versions with docs and retirement badges" do
      data = %{
        name: "plug",
        versions: [
          %{version: "1.0.0", inserted_at: "2024-01-01T00:00:00Z", has_docs: true, retired: nil},
          %{
            version: "0.9.0",
            inserted_at: "2023-01-01T00:00:00Z",
            has_docs: false,
            retired: %{reason: "security", message: "CVE-1"}
          }
        ]
      }

      out = Formatter.format_versions(data)
      assert out =~ "# Versions of plug"
      assert out =~ "**1.0.0** (2024-01-01) [docs]"
      assert out =~ "**0.9.0** (2023-01-01) [no docs] [RETIRED - security: CVE-1]"
    end
  end

  describe "format_release/1" do
    test "formats release with dependencies" do
      data = %{
        name: "plug",
        version: "1.15.0",
        publisher: "josevalim",
        inserted_at: "2024-01-01T00:00:00Z",
        updated_at: "2024-01-02T00:00:00Z",
        downloads: 1_000_000,
        has_docs: true,
        build_tools: ["mix"],
        elixir_requirement: "~> 1.14",
        dependencies: [%{name: "mime", requirement: "~> 2.0", optional: false}],
        retired: nil
      }

      out = Formatter.format_release(data)
      assert out =~ "# plug v1.15.0"
      assert out =~ "- Publisher: josevalim"
      assert out =~ "## Dependencies (1)"
      assert out =~ "mime: ~> 2.0"
      refute out =~ "RETIRED"
    end

    test "formats retired release with no deps" do
      data = %{
        name: "old",
        version: "0.1.0",
        publisher: "x",
        inserted_at: nil,
        updated_at: nil,
        downloads: 0,
        has_docs: false,
        build_tools: [],
        elixir_requirement: nil,
        dependencies: [],
        retired: %{reason: "deprecated", message: "use new"}
      }

      out = Formatter.format_release(data)
      assert out =~ "> **RETIRED** (deprecated: use new)"
      assert out =~ "## Dependencies\nNone"
    end
  end

  describe "format_features/1" do
    test "formats optional deps and extra metadata" do
      data = %{
        name: "phoenix",
        version: "1.7.0",
        optional_deps: [%{name: "jason", requirement: "~> 1.0"}],
        extra_metadata: %{"foo" => "bar"}
      }

      out = Formatter.format_features(data)
      assert out =~ "# Features for phoenix v1.7.0"
      assert out =~ "## Optional Dependencies"
      assert out =~ "jason: ~> 1.0"
      assert out =~ "## Extra Metadata"
    end

    test "handles no optional deps" do
      data = %{name: "x", version: "1.0.0", optional_deps: [], extra_metadata: %{}}
      out = Formatter.format_features(data)
      assert out =~ "No optional dependencies."
    end
  end

  describe "format_dependencies/1" do
    test "formats dependency list" do
      data = %{
        name: "req",
        version: "0.5.0",
        dependencies: [%{name: "finch", requirement: "~> 0.17", optional: false}]
      }

      out = Formatter.format_dependencies(data)
      assert out =~ "# Dependencies for req v0.5.0"
      assert out =~ "Total: 1 dependencies"
      assert out =~ "- finch: ~> 0.17"
    end

    test "handles no dependencies" do
      data = %{name: "x", version: "1.0.0", dependencies: []}
      assert Formatter.format_dependencies(data) =~ "No dependencies."
    end
  end

  describe "format_downloads/1 and format_owners/2" do
    test "formats download stats" do
      data = %{name: "jason", all: 197_000_000, recent: 4_000_000, week: 350_000, day: 50_000}
      out = Formatter.format_downloads(data)
      assert out =~ "# Download Statistics for jason"
      assert out =~ "- All-time: 197.0M"
    end

    test "formats owners with and without email" do
      out = Formatter.format_owners("plug", [%{username: "jose", email: "j@x.com"}, %{username: "eric", email: nil}])
      assert out =~ "# Owners of plug"
      assert out =~ "- jose (j@x.com)"
      assert out =~ "- eric"
    end
  end

  describe "format_comparison/1" do
    test "formats a comparison table, handling error packages" do
      packages = [
        %{
          name: "req",
          downloads_all: 11_500_000,
          downloads_recent: 1_600_000,
          latest_version: "0.5.0",
          updated_at: "2026-01-01T00:00:00Z",
          licenses: "Apache-2.0",
          dep_count: 7
        },
        %{name: "broken", error: true}
      ]

      out = Formatter.format_comparison(packages)
      assert out =~ "# Package Comparison"
      assert out =~ "Downloads (all)"
      assert out =~ "11.5M"
      assert out =~ "N/A"
    end
  end

  describe "format_health_check/1" do
    test "formats all sections with single-maintainer warning" do
      health = %{
        name: "req",
        maintenance: %{age: "4 years ago", total_versions: 52, status: "Active", days_since_release: 30},
        popularity: %{all: 11_500_000, recent: 1_600_000, week: 141_000},
        quality: %{
          has_docs: true,
          licenses: ["Apache-2.0"],
          build_tools: ["mix"],
          required_deps: 3,
          optional_deps: 4,
          elixir_requirement: "~> 1.14"
        },
        risk: %{owner_count: 1, retired_count: 0},
        links: %{docs_url: "https://hexdocs.pm/req/", hex_url: "https://hex.pm/packages/req"}
      }

      out = Formatter.format_health_check(health)
      assert out =~ "# Health Check: req"
      assert out =~ "## Maintenance"
      assert out =~ "- Status: **Active**"
      assert out =~ "- Days since last release: 30"
      assert out =~ "## Popularity"
      assert out =~ "## Quality"
      assert out =~ "- Maintainers: 1 (single maintainer!)"
      assert out =~ "- Docs: https://hexdocs.pm/req/"
    end
  end

  describe "format_audit/1" do
    test "formats audit with and without issues" do
      audit = %{
        name: "phoenix",
        version: "1.8.0",
        total_checked: 2,
        total_warnings: 1,
        deps_with_warnings: 1,
        results: [
          %{name: "plug", issues: ["2 retired versions"]},
          %{name: "jason", issues: []}
        ]
      }

      out = Formatter.format_audit(audit)
      assert out =~ "# Dependency Audit: phoenix v1.8.0"
      assert out =~ "- **plug**: 2 retired versions"
      assert out =~ "- **jason**: no issues"
    end

    test "handles no dependencies" do
      audit = %{name: "x", version: "1.0.0", total_checked: 0, total_warnings: 0, deps_with_warnings: 0, results: []}
      assert Formatter.format_audit(audit) =~ "no dependencies to audit"
    end
  end

  describe "format_alternatives/1" do
    test "formats alternatives with comparison table" do
      data = %{
        package: %{name: "poison", description: "JSON", downloads_all: 50_000_000, downloads_recent: 500_000},
        alternatives: [
          %{
            name: "jason",
            version: "1.4.4",
            downloads_all: 197_000_000,
            downloads_recent: 4_000_000,
            updated_at: "2024-01-01T00:00:00Z",
            status: "active",
            description: "Fast JSON",
            licenses: "Apache-2.0"
          }
        ]
      }

      out = Formatter.format_alternatives(data)
      assert out =~ "# Alternatives to poison"
      assert out =~ "## Comparison"
      assert out =~ "### jason"
      assert out =~ "https://hex.pm/packages/jason"
    end

    test "handles no alternatives" do
      data = %{package: %{name: "x", description: "d", downloads_all: 0, downloads_recent: 0}, alternatives: []}
      assert Formatter.format_alternatives(data) =~ "No alternative packages found."
    end
  end

  describe "format_dependency_tree/1" do
    test "formats a nested tree" do
      data = %{
        name: "phoenix",
        version: "1.7.0",
        total_unique_deps: 2,
        tree: [
          %{
            name: "phoenix",
            version: "1.7.0",
            depth: 0,
            deps: [%{name: "plug", requirement: "~> 1.14", optional: false, depth: 1}]
          }
        ]
      }

      out = Formatter.format_dependency_tree(data)
      assert out =~ "# Dependency Tree: phoenix v1.7.0"
      assert out =~ "Total unique dependencies: 2"
      assert out =~ "**phoenix** v1.7.0"
      assert out =~ "- plug: ~> 1.14"
    end
  end

  describe "format_docs/3 and format_search_docs/3" do
    test "formats module listing with type and doc preview" do
      modules = [
        %{name: "Plug.Conn", type: "module", doc: "The connection."},
        %{name: "Plug.Test", type: "behaviour", doc: ""}
      ]

      out = Formatter.format_docs("plug", "1.15.0", modules)
      assert out =~ "# Documentation for plug (1.15.0)"
      assert out =~ "**Plug.Conn** -- The connection."
      assert out =~ "**Plug.Test** [behaviour]"
    end

    test "format_docs defaults version label to latest" do
      assert Formatter.format_docs("plug", nil, []) =~ "(latest)"
    end

    test "formats doc search results from string-keyed maps" do
      results = [%{"title" => "Plug.Conn", "type" => "module", "doc" => "Conn docs"}]
      out = Formatter.format_search_docs("plug", "conn", results)
      assert out =~ "# Search Results for 'conn' in plug"
      assert out =~ "### Plug.Conn (module)"
    end
  end

  describe "format_mix_audit/1" do
    test "formats mix audit with pinned versions" do
      audit = %{
        total_checked: 2,
        total_warnings: 1,
        deps_with_warnings: 1,
        results: [
          %{name: "plug", pinned_version: "~> 1.14", issues: ["CVE"]},
          %{name: "jason", pinned_version: "~> 1.0", issues: []}
        ]
      }

      out = Formatter.format_mix_audit(audit)
      assert out =~ "# Mix Dependencies Audit"
      assert out =~ "- **plug** (`~> 1.14`): CVE"
      assert out =~ "- **jason** (`~> 1.0`): no issues"
    end

    test "handles no deps" do
      audit = %{total_checked: 0, total_warnings: 0, deps_with_warnings: 0, results: []}
      assert Formatter.format_mix_audit(audit) =~ "No dependencies found to audit."
    end
  end

  describe "format_upgrade_check/1" do
    test "formats upgrade statuses including up-to-date, error, and bumps" do
      data = %{
        total_checked: 4,
        upgrades_available: 2,
        results: [
          %{name: "jason", pinned_version: "~> 1.0", latest_version: "1.0.0", status: :up_to_date, retired: false},
          %{name: "plug", pinned_version: "~> 1.14", latest_version: "1.19.1", status: :minor_upgrade, retired: false},
          %{name: "ecto", pinned_version: "~> 2.0", latest_version: "3.0.0", status: :major_upgrade, retired: true},
          %{name: "gone", pinned_version: "~> 1.0", latest_version: nil, status: :error, retired: false}
        ]
      }

      out = Formatter.format_upgrade_check(data)
      assert out =~ "# Upgrade Check"
      assert out =~ "- **jason** (`~> 1.0`): up to date (1.0.0)"
      assert out =~ "- **plug** (`~> 1.14` -> `1.19.1`): minor upgrade available"
      assert out =~ "- **ecto** (`~> 2.0` -> `3.0.0`): MAJOR upgrade available [RETIRED]"
      assert out =~ "- **gone** (`~> 1.0`): could not check"
    end

    test "handles no deps" do
      data = %{total_checked: 0, upgrades_available: 0, results: []}
      assert Formatter.format_upgrade_check(data) =~ "No dependencies found to check."
    end
  end
end
