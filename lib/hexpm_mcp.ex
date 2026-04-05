defmodule HexpmMcp do
  @moduledoc """
  Public API for querying hex.pm and hexdocs.pm.

  All functions return `{:ok, result}` or `{:error, reason}` and are designed
  to be used from iex, other Elixir code, or as the backend for MCP tools.

  ## Quick Start

      iex> HexpmMcp.search("json")
      {:ok, [%{name: "jason", version: "1.4.4", downloads_all: 197_000_000, ...}, ...]}

      iex> HexpmMcp.get_info("plug")
      {:ok, %{name: "plug", description: "Composable modules for web applications",
              downloads: %{all: 156_000_000, recent: 3_100_000, week: 250_000, day: 35_000},
              licenses: ["Apache-2.0"], latest_stable_version: "1.19.1", ...}}

      iex> HexpmMcp.health_check("req")
      {:ok, %{name: "req",
              maintenance: %{status: "Active", age: "4 years ago", days_since_release: 57, total_versions: 52},
              popularity: %{all: 11_500_000, recent: 1_600_000, week: 141_000},
              quality: %{has_docs: true, licenses: ["Apache-2.0"], required_deps: 3, optional_deps: 4},
              risk: %{owner_count: 1, retired_count: 0},
              links: %{...}}}

  ## Function Groups

  ### Simple lookups
  `search/2`, `get_info/1`, `get_downloads/1`, `get_owners/1`, `get_versions/1`,
  `get_reverse_dependencies/1`

  ### Version-resolving lookups
  `get_release/2`, `get_dependencies/2`, `get_features/2` -- pass `nil` for version
  to automatically resolve to the latest stable version.

  ### Composite analysis
  `compare_packages/1`, `health_check/1`, `audit_dependencies/2`,
  `find_alternatives/1`, `dependency_tree/3` -- these make multiple API calls
  in parallel and return aggregated results.

  ### HexDocs browsing
  `get_readme/2`, `get_docs/2`, `get_doc_item/3`, `search_docs/3`

  ## Error Values

  All functions return `{:error, reason}` on failure. Common reasons:

  - `:not_found` -- package or version does not exist on hex.pm
  - `:rate_limited` -- hex.pm API rate limit exceeded
  - `:too_few_packages` / `:too_many_packages` -- invalid input to `compare_packages/1`
  - `{:api_error, status, body}` -- unexpected HTTP status from hex.pm
  - `{:request_failed, reason}` -- network error
  """

  alias HexpmMcp.{Client, HexDocs, OSV}

  @stop_words ~w(a an the and or but in on at to for of is it that this with from by as are was be)

  # ---------------------------------------------------------------------------
  # Simple lookups
  # ---------------------------------------------------------------------------

  @typedoc "Common error reasons from hex.pm API calls."
  @type error ::
          :not_found | :rate_limited | {:api_error, integer(), any()} | {:request_failed, any()}

  @doc """
  Search for packages on hex.pm by name/keywords.

  ## Options

  - `:sort` -- sort order: `"name"`, `"recent_downloads"`, `"total_downloads"`,
    `"inserted_at"`, `"updated_at"`
  - `:page` -- page number (1-indexed, 100 results per page)

  ## Examples

      iex> HexpmMcp.search("json")
      {:ok, [%{name: "jason", version: "1.4.4", description: "A blazing fast JSON parser...",
               downloads_all: 197_000_000, downloads_recent: 4_000_000,
               url: "https://hex.pm/packages/jason"}, ...]}

      iex> HexpmMcp.search("http client", sort: "recent_downloads", page: 1)
      {:ok, [%{name: "req", ...}, %{name: "finch", ...}, ...]}

  """
  @spec search(String.t(), keyword()) :: {:ok, [map()]} | {:error, error()}
  def search(query, opts \\ []) do
    case Client.search(query, opts) do
      {:ok, packages} ->
        results =
          Enum.map(packages, fn pkg ->
            %{
              name: pkg.name,
              version: pkg.latest_stable_version || pkg.latest_version,
              description: get_in(pkg.meta, ["description"]) || "",
              downloads_all: pkg.downloads["all"] || 0,
              downloads_recent: pkg.downloads["recent"] || 0,
              url: "https://hex.pm/packages/#{pkg.name}"
            }
          end)

        {:ok, results}

      error ->
        error
    end
  end

  @doc """
  Get detailed information about a hex.pm package.

  Returns metadata, download stats, licenses, links, and version info.

  ## Examples

      iex> HexpmMcp.get_info("plug")
      {:ok, %{
        name: "plug",
        description: "Composable modules for web applications",
        latest_stable_version: "1.19.1",
        latest_version: "1.19.1",
        downloads: %{all: 156_000_000, recent: 3_100_000, week: 250_000, day: 35_000},
        licenses: ["Apache-2.0"],
        build_tools: ["mix"],
        elixir_requirement: "~> 1.14",
        inserted_at: "2013-12-31T...",
        updated_at: "2025-12-09T...",
        docs_url: "https://hexdocs.pm/plug/",
        hex_url: "https://hex.pm/packages/plug",
        links: %{"GitHub" => "https://github.com/elixir-plug/plug"}
      }}

      iex> HexpmMcp.get_info("nonexistent")
      {:error, :not_found}

  """
  @spec get_info(String.t()) :: {:ok, map()} | {:error, error()}
  def get_info(name) do
    with {:ok, pkg} <- Client.get_package(name) do
      {:ok, package_to_info(pkg)}
    end
  end

  defp package_to_info(pkg) do
    %{
      name: pkg.name,
      description: meta(pkg, "description") || "No description",
      latest_stable_version: pkg.latest_stable_version,
      latest_version: pkg.latest_version,
      downloads: extract_downloads(pkg.downloads),
      licenses: meta(pkg, "licenses") || [],
      build_tools: meta(pkg, "build_tools") || [],
      elixir_requirement: meta(pkg, "elixir"),
      inserted_at: pkg.inserted_at,
      updated_at: pkg.updated_at,
      docs_url: pkg.docs_html_url,
      hex_url: "https://hex.pm/packages/#{pkg.name}",
      links: meta(pkg, "links") || %{}
    }
  end

  @doc """
  Get download statistics for a hex.pm package.

  ## Examples

      iex> HexpmMcp.get_downloads("phoenix")
      {:ok, %{name: "phoenix", all: 148_000_000, recent: 2_600_000, week: 223_000, day: 13_000}}

  """
  @spec get_downloads(String.t()) :: {:ok, map()} | {:error, error()}
  def get_downloads(name) do
    with {:ok, pkg} <- Client.get_package(name) do
      {:ok, Map.put(extract_downloads(pkg.downloads), :name, pkg.name)}
    end
  end

  @doc """
  Get the owners/maintainers of a hex.pm package.

  ## Examples

      iex> HexpmMcp.get_owners("phoenix")
      {:ok, [%{username: "josevalim", email: "jose@example.com"}, ...]}

  """
  @spec get_owners(String.t()) :: {:ok, [map()]} | {:error, error()}
  def get_owners(name) do
    case Client.get_owners(name) do
      {:ok, owners} ->
        {:ok, Enum.map(owners, fn o -> %{username: o.username, email: o.email} end)}

      error ->
        error
    end
  end

  @doc """
  List all versions of a hex.pm package with retirement status.

  ## Examples

      iex> HexpmMcp.get_versions("plug")
      {:ok, %{name: "plug", versions: [
        %{version: "1.19.1", inserted_at: "2025-12-09T...", has_docs: true, retired: nil},
        %{version: "1.14.0", inserted_at: "2023-03-15T...", has_docs: true,
          retired: %{reason: "security", message: "CVE-2024-..."}},
        ...
      ]}}

  """
  @spec get_versions(String.t()) :: {:ok, map()} | {:error, error()}
  def get_versions(name) do
    case Client.get_package(name) do
      {:ok, pkg} ->
        retirements = pkg.retirements || %{}

        versions =
          Enum.map(pkg.releases || [], fn rel ->
            version = rel["version"]
            retirement = Map.get(retirements, version)

            %{
              version: version,
              inserted_at: rel["inserted_at"],
              has_docs: rel["has_docs"] || false,
              retired:
                if(retirement,
                  do: %{
                    reason: retirement["reason"] || "unknown",
                    message: retirement["message"]
                  },
                  else: nil
                )
            }
          end)

        {:ok, %{name: pkg.name, versions: versions}}

      error ->
        error
    end
  end

  @doc """
  Find packages that depend on a given hex.pm package.

  ## Examples

      iex> HexpmMcp.get_reverse_dependencies("jason")
      {:ok, %{name: "jason", dependents: [
        %{name: "phoenix", downloads: 148_000_000, description: "Peace of mind from prototype to production"},
        %{name: "ecto", downloads: 95_000_000, description: "A toolkit for data mapping..."},
        ...
      ]}}

  """
  @spec get_reverse_dependencies(String.t()) :: {:ok, map()} | {:error, error()}
  def get_reverse_dependencies(name) do
    case Client.get_reverse_dependencies(name) do
      {:ok, packages} ->
        dependents =
          Enum.map(packages, fn pkg ->
            %{
              name: pkg.name,
              downloads: pkg.downloads["all"] || 0,
              description:
                case get_in(pkg.meta, ["description"]) || "" do
                  "" -> ""
                  desc -> desc |> String.split("\n", parts: 2) |> hd()
                end
            }
          end)

        {:ok, %{name: name, dependents: dependents}}

      error ->
        error
    end
  end

  # ---------------------------------------------------------------------------
  # Version-resolving lookups
  # ---------------------------------------------------------------------------

  @doc """
  Get detailed information about a specific release.

  If `version` is nil, resolves to the latest stable version.

  ## Examples

      iex> HexpmMcp.get_release("plug", "1.19.1")
      {:ok, %{
        name: "plug", version: "1.19.1", publisher: "josevalim",
        inserted_at: "2025-12-09T...", updated_at: "2025-12-09T...",
        downloads: 500_000, has_docs: true,
        build_tools: ["mix"], elixir_requirement: "~> 1.14",
        dependencies: [
          %{name: "mime", requirement: "~> 2.0", optional: false},
          %{name: "plug_crypto", requirement: "~> 2.1", optional: false}
        ],
        retired: nil
      }}

      # Resolves to latest stable when version is nil
      iex> HexpmMcp.get_release("plug")
      {:ok, %{name: "plug", version: "1.19.1", ...}}

  """
  @spec get_release(String.t(), String.t() | nil) :: {:ok, map()} | {:error, error()}
  def get_release(name, version \\ nil) do
    with {:ok, version} <- resolve_version(name, version),
         {:ok, rel} <- Client.get_release(name, version) do
      {:ok, release_to_map(name, rel)}
    end
  end

  defp release_to_map(name, rel) do
    %{
      name: name,
      version: rel.version,
      publisher: rel.publisher["username"] || "unknown",
      inserted_at: rel.inserted_at,
      updated_at: rel.updated_at,
      downloads: rel.downloads || 0,
      has_docs: rel.has_docs || false,
      build_tools: get_in(rel.meta, ["build_tools"]) || [],
      elixir_requirement: get_in(rel.meta, ["elixir"]),
      dependencies: parse_requirements(rel.requirements),
      retired: parse_retirement(rel.retirement)
    }
  end

  @doc """
  Get the dependencies of a package version.

  If `version` is nil, resolves to the latest stable version.

  ## Examples

      iex> HexpmMcp.get_dependencies("req")
      {:ok, %{name: "req", version: "0.5.17", dependencies: [
        %{name: "finch", requirement: "~> 0.17", optional: false},
        %{name: "jason", requirement: "~> 1.0", optional: true},
        %{name: "mime", requirement: "~> 2.0 or ~> 1.0", optional: false},
        ...
      ]}}

      iex> HexpmMcp.get_dependencies("plug", "1.19.1")
      {:ok, %{name: "plug", version: "1.19.1", dependencies: [...]}}

  """
  @spec get_dependencies(String.t(), String.t() | nil) :: {:ok, map()} | {:error, error()}
  def get_dependencies(name, version \\ nil) do
    with {:ok, version} <- resolve_version(name, version),
         {:ok, rel} <- Client.get_release(name, version) do
      {:ok, %{name: name, version: version, dependencies: parse_requirements(rel.requirements)}}
    end
  end

  @doc """
  Get optional features/extras for a package release.

  If `version` is nil, resolves to the latest stable version.

  ## Examples

      iex> HexpmMcp.get_features("req")
      {:ok, %{
        name: "req", version: "0.5.17",
        optional_deps: [
          %{name: "brotli", requirement: "~> 0.3.1"},
          %{name: "jason", requirement: "~> 1.0"},
          ...
        ],
        extra_metadata: %{}
      }}

  """
  @spec get_features(String.t(), String.t() | nil) :: {:ok, map()} | {:error, error()}
  def get_features(name, version \\ nil) do
    with {:ok, version} <- resolve_version(name, version),
         {:ok, rel} <- Client.get_release(name, version) do
      optional_deps =
        parse_requirements(rel.requirements)
        |> Enum.filter(& &1.optional)
        |> Enum.map(&Map.take(&1, [:name, :requirement]))

      {:ok,
       %{
         name: name,
         version: version,
         optional_deps: optional_deps,
         extra_metadata: get_in(rel.meta, ["extra"]) || %{}
       }}
    end
  end

  # ---------------------------------------------------------------------------
  # Composite / analytical
  # ---------------------------------------------------------------------------

  @doc """
  Compare 2-5 hex.pm packages side by side.

  Fetches package info and dependency counts in parallel for each package.

  ## Examples

      iex> HexpmMcp.compare_packages(["plug", "bandit", "cowboy"])
      {:ok, [
        %{name: "plug", downloads_all: 156_000_000, downloads_recent: 3_100_000,
          latest_version: "1.19.1", updated_at: "2025-12-09T...",
          licenses: "Apache-2.0", dep_count: 3},
        %{name: "bandit", downloads_all: 9_900_000, ...},
        %{name: "cowboy", downloads_all: 78_000_000, ...}
      ]}

      iex> HexpmMcp.compare_packages(["only_one"])
      {:error, :too_few_packages}

  """
  @spec compare_packages([String.t()]) ::
          {:ok, [map()]} | {:error, :too_few_packages | :too_many_packages}
  def compare_packages(names) when is_list(names) do
    cond do
      length(names) < 2 -> {:error, :too_few_packages}
      length(names) > 5 -> {:error, :too_many_packages}
      true -> do_compare(names)
    end
  end

  defp do_compare(names) do
    packages =
      names
      |> Task.async_stream(&enrich_for_comparison/1, timeout: 30_000)
      |> Enum.map(fn {:ok, result} -> result end)

    {:ok, packages}
  end

  defp enrich_for_comparison(name) do
    case Client.get_package(name) do
      {:ok, pkg} ->
        version = pkg.latest_stable_version || pkg.latest_version
        dep_count = count_deps(name, version)

        %{
          name: pkg.name,
          downloads_all: pkg.downloads["all"] || 0,
          downloads_recent: pkg.downloads["recent"] || 0,
          latest_version: pkg.latest_stable_version || pkg.latest_version || "?",
          updated_at: pkg.updated_at,
          licenses: (meta(pkg, "licenses") || []) |> Enum.join(", "),
          dep_count: dep_count
        }

      _ ->
        %{name: name, error: true}
    end
  end

  defp count_deps(name, version) do
    case Client.get_release(name, version) do
      {:ok, rel} -> map_size(rel.requirements || %{})
      _ -> 0
    end
  end

  @doc """
  Comprehensive health check for a hex.pm package.

  Fetches package info, owners, and latest release in parallel, then computes
  maintenance status, popularity metrics, quality indicators, and risk factors.

  ## Examples

      iex> HexpmMcp.health_check("req")
      {:ok, %{
        name: "req",
        maintenance: %{
          age: "4 years ago",
          total_versions: 52,
          status: "Active",        # Active (<90d), Recent (<1y), Aging (<2y), Stale (2y+)
          days_since_release: 57
        },
        popularity: %{all: 11_500_000, recent: 1_600_000, week: 141_000},
        quality: %{
          has_docs: true,
          licenses: ["Apache-2.0"],
          build_tools: ["mix"],
          elixir_requirement: "~> 1.14",
          required_deps: 3,
          optional_deps: 4
        },
        risk: %{
          owner_count: 1,          # 1 = "single maintainer" warning
          retired_count: 0
        },
        links: %{
          hex_url: "https://hex.pm/packages/req",
          docs_url: "https://hexdocs.pm/req/",
          "GitHub" => "https://github.com/wojtekmach/req"
        }
      }}

  """
  @spec health_check(String.t()) :: {:ok, map()} | {:error, error()}
  def health_check(name) do
    tasks = %{
      package: Task.async(fn -> Client.get_package(name) end),
      owners: Task.async(fn -> Client.get_owners(name) end)
    }

    with {:ok, pkg} <- Task.await(tasks.package, 30_000) do
      owners = unwrap_or(Task.await(tasks.owners, 30_000), [])
      release = fetch_latest_release(pkg)
      {:ok, build_health_report(pkg, owners, release)}
    end
  end

  defp fetch_latest_release(pkg) do
    version = pkg.latest_stable_version || pkg.latest_version

    case if(version, do: Client.get_release(pkg.name, version), else: {:error, :no_version}) do
      {:ok, r} -> r
      _ -> nil
    end
  end

  defp build_health_report(pkg, owners, release) do
    now = DateTime.utc_now()

    %{
      name: pkg.name,
      maintenance: build_maintenance(pkg, now),
      popularity: %{
        all: pkg.downloads["all"] || 0,
        recent: pkg.downloads["recent"] || 0,
        week: pkg.downloads["week"] || 0
      },
      quality: build_quality(pkg, release),
      risk: %{
        owner_count: length(owners),
        retired_count: map_size(pkg.retirements || %{})
      },
      links: build_links(pkg)
    }
  end

  defp unwrap_or({:ok, value}, _default), do: value
  defp unwrap_or(_, default), do: default

  @doc """
  Audit a package's dependencies for risks.

  Checks each dependency in parallel for:
  - Retired versions
  - Stale packages (no release in 2+ years)
  - Single-maintainer packages (bus factor risk)
  - Known vulnerabilities via OSV.dev

  ## Examples

      iex> HexpmMcp.audit_dependencies("phoenix")
      {:ok, %{
        name: "phoenix", version: "1.8.5",
        total_checked: 10, total_warnings: 8, deps_with_warnings: 7,
        results: [
          %{name: "jason", issues: ["single maintainer"]},
          %{name: "plug", issues: ["2 retired version(s)", "3 known vulnerability(ies)"]},
          %{name: "telemetry", issues: []},
          ...
        ]
      }}

      iex> HexpmMcp.audit_dependencies("phoenix", "1.7.0")
      {:ok, %{name: "phoenix", version: "1.7.0", ...}}

  """
  @spec audit_dependencies(String.t(), String.t() | nil) :: {:ok, map()} | {:error, error()}
  def audit_dependencies(name, version \\ nil) do
    with {:ok, version} <- resolve_version(name, version),
         {:ok, rel} <- Client.get_release(name, version) do
      reqs = rel.requirements || %{}

      {:ok, run_audit(name, version, reqs)}
    end
  end

  @doc """
  Find and compare alternative packages for a given hex.pm package.

  Extracts keywords from the package description, searches for similar packages,
  deduplicates, and returns the top 10 sorted by recent downloads.

  ## Examples

      iex> HexpmMcp.find_alternatives("httpoison")
      {:ok, %{
        package: %{name: "httpoison", description: "HTTP client for Elixir",
                   downloads_all: 42_000_000, downloads_recent: 500_000},
        alternatives: [
          %{name: "req", version: "0.5.17", downloads_all: 11_500_000,
            downloads_recent: 1_600_000, updated_at: "2026-02-07T...",
            status: "Active", description: "Req is a batteries-included HTTP client...",
            licenses: "Apache-2.0"},
          %{name: "finch", ...},
          ...
        ]
      }}

  """
  @spec find_alternatives(String.t()) :: {:ok, map()} | {:error, error()}
  def find_alternatives(name) do
    with {:ok, pkg} <- Client.get_package(name) do
      alternatives = search_similar(name, extract_keywords(pkg))
      {:ok, %{package: package_summary(pkg), alternatives: alternatives}}
    end
  end

  defp search_similar(exclude_name, keywords) do
    keywords
    |> Task.async_stream(
      fn kw ->
        case Client.search(kw, sort: "recent_downloads") do
          {:ok, packages} -> packages
          _ -> []
        end
      end,
      timeout: 30_000
    )
    |> Enum.flat_map(fn {:ok, packages} -> packages end)
    |> Enum.uniq_by(& &1.name)
    |> Enum.reject(&(&1.name == exclude_name))
    |> Enum.sort_by(fn p -> -(p.downloads["recent"] || 0) end)
    |> Enum.take(10)
    |> Enum.map(&package_to_alternative/1)
  end

  defp package_to_alternative(pkg) do
    %{
      name: pkg.name,
      version: pkg.latest_stable_version || pkg.latest_version || "?",
      downloads_all: pkg.downloads["all"] || 0,
      downloads_recent: pkg.downloads["recent"] || 0,
      updated_at: pkg.updated_at,
      status: maintenance_status(pkg.updated_at),
      description: meta(pkg, "description") || "",
      licenses: (meta(pkg, "licenses") || []) |> Enum.join(", ")
    }
  end

  defp package_summary(pkg) do
    %{
      name: pkg.name,
      description: meta(pkg, "description") || "",
      downloads_all: pkg.downloads["all"] || 0,
      downloads_recent: pkg.downloads["recent"] || 0
    }
  end

  @doc """
  Get the full transitive dependency tree for a package (BFS, max depth 5).

  Traverses dependencies breadth-first, resolving each to its latest version.
  Deduplicates by package name (each package appears once in the tree).

  ## Options

  - `:max_depth` -- maximum depth to traverse (default 5, capped at 5)

  ## Examples

      iex> HexpmMcp.dependency_tree("req", nil, max_depth: 2)
      {:ok, %{
        name: "req", version: "0.5.17", total_unique_deps: 8,
        tree: [
          %{name: "req", version: "0.5.17", depth: 0, deps: [
            %{name: "finch", requirement: "~> 0.17", optional: false, depth: 1},
            %{name: "mime", requirement: "~> 2.0 or ~> 1.0", optional: false, depth: 1},
            ...
          ]},
          %{name: "finch", version: "0.21.0", depth: 1, deps: [...]},
          ...
        ]
      }}

  """
  @spec dependency_tree(String.t(), String.t() | nil, keyword()) ::
          {:ok, map()} | {:error, error()}
  def dependency_tree(name, version \\ nil, opts \\ []) do
    max_depth = min(Keyword.get(opts, :max_depth, 5), 5)

    with {:ok, version} <- resolve_version(name, version) do
      tree = build_tree(name, version, max_depth)

      total_unique_deps =
        tree
        |> Enum.flat_map(fn entry -> Enum.map(entry.deps, & &1.name) end)
        |> Enum.uniq()
        |> length()

      {:ok,
       %{
         name: name,
         version: version,
         total_unique_deps: total_unique_deps,
         tree: tree
       }}
    end
  end

  # ---------------------------------------------------------------------------
  # HexDocs passthrough
  # ---------------------------------------------------------------------------

  @doc """
  Get the README content for a package as markdown.

  Fetches the README from hexdocs.pm and converts HTML to markdown.

  ## Examples

      iex> HexpmMcp.get_readme("req")
      {:ok, "# Req\\n\\nReq is a batteries-included HTTP client for Elixir.\\n\\n..."}

      iex> HexpmMcp.get_readme("req", "0.5.0")
      {:ok, "# Req\\n\\n..."}

  """
  @spec get_readme(String.t(), String.t() | nil) :: {:ok, String.t()} | {:error, error()}
  def get_readme(name, version \\ nil), do: HexDocs.get_readme(name, version)

  @doc """
  Get the module listing for a package's documentation.

  Parses the hexdocs.pm sidebar data to extract all modules, behaviours,
  and protocols with their function/type counts.

  ## Examples

      iex> HexpmMcp.get_docs("plug")
      {:ok, [
        %{name: "Plug", type: "module", doc: "Types: 1, Callbacks: 2, Functions: 2"},
        %{name: "Plug.Conn", type: "module", doc: "Types: 22, Functions: 52"},
        %{name: "Plug.Router", type: "module", doc: "Functions: 12"},
        ...
      ]}

  """
  @spec get_docs(String.t(), String.t() | nil) :: {:ok, [map()]} | {:error, error()}
  def get_docs(name, version \\ nil), do: HexDocs.get_modules(name, version)

  @doc """
  Get full documentation for a specific module or function.

  Fetches the module's hexdocs.pm page and converts it to markdown.

  ## Examples

      iex> HexpmMcp.get_doc_item("plug", "Plug.Conn")
      {:ok, "# Plug.Conn\\n\\nThe Plug connection.\\n\\n..."}

      iex> HexpmMcp.get_doc_item("plug", "Plug.Conn", "1.19.1")
      {:ok, "# Plug.Conn\\n\\n..."}

  """
  @spec get_doc_item(String.t(), String.t(), String.t() | nil) ::
          {:ok, String.t()} | {:error, error()}
  def get_doc_item(name, module, version \\ nil), do: HexDocs.get_doc_item(name, module, version)

  @doc """
  Search within a package's documentation by name.

  Searches module names and doc snippets in the hexdocs.pm sidebar data.
  Returns up to 20 matching items.

  ## Examples

      iex> HexpmMcp.search_docs("phoenix", "Router")
      {:ok, [
        %{"title" => "Phoenix.Router", "type" => "module", "doc" => "Reflection: 3, Functions: 21"},
        %{"title" => "Phoenix.Router.NoRouteError", "type" => "module", "doc" => ""},
        ...
      ]}

  """
  @spec search_docs(String.t(), String.t(), String.t() | nil) ::
          {:ok, [map()]} | {:error, error()}
  def search_docs(name, query, version \\ nil), do: HexDocs.search_docs(name, query, version)

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp meta(pkg, key), do: get_in(pkg.meta, [key])

  defp parse_requirements(nil), do: []

  defp parse_requirements(reqs) do
    reqs
    |> Enum.sort_by(fn {dep_name, _} -> dep_name end)
    |> Enum.map(fn {dep_name, info} ->
      %{
        name: dep_name,
        requirement: info["requirement"] || "any",
        optional: info["optional"] || false
      }
    end)
  end

  defp parse_retirement(nil), do: nil

  defp parse_retirement(retirement) do
    %{reason: retirement["reason"] || "unknown", message: retirement["message"]}
  end

  defp extract_downloads(downloads) do
    %{
      all: downloads["all"] || 0,
      recent: downloads["recent"] || 0,
      week: downloads["week"] || 0,
      day: downloads["day"] || 0
    }
  end

  defp resolve_version(_name, version) when is_binary(version), do: {:ok, version}

  defp resolve_version(name, nil) do
    case Client.get_package(name) do
      {:ok, pkg} -> {:ok, pkg.latest_stable_version || pkg.latest_version}
      error -> error
    end
  end

  defp maintenance_status(updated_at) do
    case days_since(updated_at) do
      nil -> "Unknown"
      days -> status_from_days(days)
    end
  end

  defp status_from_days(days) do
    cond do
      days < 90 -> "Active"
      days < 365 -> "Recent"
      days < 730 -> "Aging"
      true -> "Stale"
    end
  end

  defp days_since(nil), do: nil
  defp days_since(date_str), do: days_since(date_str, DateTime.utc_now())

  defp days_since(nil, _now), do: nil

  defp days_since(date_str, now) do
    case DateTime.from_iso8601(date_str) do
      {:ok, dt, _} -> DateTime.diff(now, dt, :day)
      _ -> nil
    end
  end

  defp format_age(nil, _now), do: "unknown"

  defp format_age(date_str, now) do
    case days_since(date_str, now) do
      nil ->
        "unknown"

      days ->
        years = div(days, 365)
        if years > 0, do: "#{years} years ago", else: "#{days} days ago"
    end
  end

  defp build_maintenance(pkg, now) do
    total_versions = length(pkg.releases || [])
    days = days_since(pkg.updated_at, now)

    %{
      age: format_age(pkg.inserted_at, now),
      total_versions: total_versions,
      status: if(days, do: status_from_days(days), else: "Unknown"),
      days_since_release: days
    }
  end

  defp build_quality(pkg, release) do
    base = %{
      has_docs: pkg.docs_html_url != nil,
      licenses: get_in(pkg.meta, ["licenses"]) || [],
      build_tools: get_in(pkg.meta, ["build_tools"]) || []
    }

    if release do
      reqs = release.requirements || %{}
      required = Enum.count(reqs, fn {_, info} -> not (info["optional"] || false) end)
      optional = Enum.count(reqs, fn {_, info} -> info["optional"] || false end)

      Map.merge(base, %{
        elixir_requirement: get_in(release.meta, ["elixir"]),
        required_deps: required,
        optional_deps: optional
      })
    else
      Map.merge(base, %{elixir_requirement: nil, required_deps: 0, optional_deps: 0})
    end
  end

  defp build_links(pkg) do
    base = %{hex_url: "https://hex.pm/packages/#{pkg.name}"}

    base =
      if pkg.docs_html_url do
        Map.put(base, :docs_url, pkg.docs_html_url)
      else
        base
      end

    meta_links = get_in(pkg.meta, ["links"]) || %{}
    Map.merge(base, meta_links |> Enum.into(%{}, fn {k, v} -> {k, v} end))
  end

  defp run_audit(name, version, reqs) when map_size(reqs) == 0 do
    %{
      name: name,
      version: version,
      total_checked: 0,
      total_warnings: 0,
      deps_with_warnings: 0,
      results: []
    }
  end

  defp run_audit(name, version, reqs) do
    results =
      reqs
      |> Map.keys()
      |> Task.async_stream(fn dep_name -> {dep_name, audit_dep(dep_name)} end, timeout: 30_000)
      |> Enum.map(fn {:ok, result} -> result end)
      |> Enum.sort_by(fn {dep_name, _} -> dep_name end)

    total_warnings = Enum.sum(Enum.map(results, fn {_, issues} -> length(issues) end))

    %{
      name: name,
      version: version,
      total_checked: length(results),
      total_warnings: total_warnings,
      deps_with_warnings: Enum.count(results, fn {_, issues} -> issues != [] end),
      results: Enum.map(results, fn {dep_name, issues} -> %{name: dep_name, issues: issues} end)
    }
  end

  defp audit_dep(dep_name) do
    pkg_result = Client.get_package(dep_name)
    owners_result = Client.get_owners(dep_name)
    vuln_result = OSV.query(dep_name)

    check_package(pkg_result) ++ check_owners(owners_result) ++ check_vulns(vuln_result)
  end

  defp check_package({:ok, pkg}) do
    retirement_issues = check_retirements(pkg.retirements || %{})
    staleness_issues = check_staleness(pkg.updated_at)
    retirement_issues ++ staleness_issues
  end

  defp check_package(_), do: ["could not fetch package info"]

  defp check_retirements(retirements) do
    count = map_size(retirements)
    if count > 0, do: ["#{count} retired version(s)"], else: []
  end

  defp check_staleness(updated_at) do
    case days_since(updated_at) do
      nil -> []
      days when days > 730 -> ["stale (last release #{Float.round(days / 365, 1)} years ago)"]
      _ -> []
    end
  end

  defp check_owners({:ok, [_single]}), do: ["single maintainer"]
  defp check_owners(_), do: []

  defp check_vulns({:ok, vulns}) when vulns != [] do
    ["#{length(vulns)} known vulnerability(ies)"]
  end

  defp check_vulns(_), do: []

  defp extract_keywords(pkg) do
    desc = get_in(pkg.meta, ["description"]) || ""

    desc
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9\s]/, "")
    |> String.split()
    |> Enum.reject(&(&1 in @stop_words or String.length(&1) < 3))
    |> Enum.take(3)
  end

  defp build_tree(name, version, max_depth) do
    queue = :queue.from_list([{name, version, 0}])
    visited = MapSet.new([name])
    do_bfs(queue, visited, max_depth, [])
  end

  defp do_bfs(queue, visited, max_depth, acc) do
    case :queue.out(queue) do
      {:empty, _} ->
        Enum.reverse(acc)

      {{:value, {name, version, depth}}, rest_queue} ->
        deps = fetch_deps(name, version, depth)
        entry = %{name: name, version: version, depth: depth, deps: deps}
        acc = [entry | acc]

        if depth < max_depth do
          {new_queue, new_visited} = enqueue_new_deps(deps, rest_queue, visited, depth)
          do_bfs(new_queue, new_visited, max_depth, acc)
        else
          do_bfs(rest_queue, visited, max_depth, acc)
        end
    end
  end

  defp fetch_deps(name, version, depth) do
    case Client.get_release(name, version) do
      {:ok, rel} ->
        Enum.map(rel.requirements || %{}, fn {dep_name, info} ->
          %{
            name: dep_name,
            requirement: info["requirement"] || "any",
            optional: info["optional"] || false,
            depth: depth + 1
          }
        end)

      _ ->
        []
    end
  end

  defp enqueue_new_deps(deps, queue, visited, depth) do
    Enum.reduce(deps, {queue, visited}, fn dep, {q, v} ->
      if MapSet.member?(v, dep.name) do
        {q, v}
      else
        dep_version = resolve_dep_version(dep.name)

        {
          :queue.in({dep.name, dep_version, depth + 1}, q),
          MapSet.put(v, dep.name)
        }
      end
    end)
  end

  defp resolve_dep_version(name) do
    case Client.get_package(name) do
      {:ok, pkg} -> pkg.latest_stable_version || pkg.latest_version || "0.0.0"
      _ -> "0.0.0"
    end
  end
end
