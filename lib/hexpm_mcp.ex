defmodule HexpmMcp do
  @moduledoc """
  Public API for querying hex.pm and hexdocs.pm.

  All functions return `{:ok, result}` or `{:error, reason}` and are designed
  to be used from iex, other Elixir code, or as the backend for MCP tools.

  ## Examples

      iex> HexpmMcp.search("phoenix")
      {:ok, [%{name: "phoenix", version: "1.8.5", ...}, ...]}

      iex> HexpmMcp.get_info("plug")
      {:ok, %{name: "plug", description: "...", downloads: %{all: 50000, ...}, ...}}

      iex> HexpmMcp.health_check("req")
      {:ok, %{name: "req", maintenance: %{status: "Active", ...}, ...}}
  """

  alias HexpmMcp.{Client, HexDocs, OSV}

  @stop_words ~w(a an the and or but in on at to for of is it that this with from by as are was be)

  # ---------------------------------------------------------------------------
  # Simple lookups
  # ---------------------------------------------------------------------------

  @doc """
  Search for packages on hex.pm by name/keywords.
  """
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
  """
  def get_info(name) do
    case Client.get_package(name) do
      {:ok, pkg} ->
        info = %{
          name: pkg.name,
          description: get_in(pkg.meta, ["description"]) || "No description",
          latest_stable_version: pkg.latest_stable_version,
          latest_version: pkg.latest_version,
          downloads: %{
            all: pkg.downloads["all"] || 0,
            recent: pkg.downloads["recent"] || 0,
            week: pkg.downloads["week"] || 0,
            day: pkg.downloads["day"] || 0
          },
          licenses: get_in(pkg.meta, ["licenses"]) || [],
          build_tools: get_in(pkg.meta, ["build_tools"]) || [],
          elixir_requirement: get_in(pkg.meta, ["elixir"]),
          inserted_at: pkg.inserted_at,
          updated_at: pkg.updated_at,
          docs_url: pkg.docs_html_url,
          hex_url: "https://hex.pm/packages/#{pkg.name}",
          links: get_in(pkg.meta, ["links"]) || %{}
        }

        {:ok, info}

      error ->
        error
    end
  end

  @doc """
  Get download statistics for a hex.pm package.
  """
  def get_downloads(name) do
    case Client.get_package(name) do
      {:ok, pkg} ->
        {:ok,
         %{
           name: pkg.name,
           all: pkg.downloads["all"] || 0,
           recent: pkg.downloads["recent"] || 0,
           week: pkg.downloads["week"] || 0,
           day: pkg.downloads["day"] || 0
         }}

      error ->
        error
    end
  end

  @doc """
  Get the owners/maintainers of a hex.pm package.
  """
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
  """
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
  """
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
  """
  def get_release(name, version \\ nil) do
    with {:ok, version} <- resolve_version(name, version),
         {:ok, rel} <- Client.get_release(name, version) do
      build_tools = get_in(rel.meta, ["build_tools"]) || []
      elixir_req = get_in(rel.meta, ["elixir"])
      reqs = rel.requirements || %{}

      deps =
        reqs
        |> Enum.sort_by(fn {dep_name, _} -> dep_name end)
        |> Enum.map(fn {dep_name, info} ->
          %{
            name: dep_name,
            requirement: info["requirement"] || "any",
            optional: info["optional"] || false
          }
        end)

      {:ok,
       %{
         name: name,
         version: rel.version,
         publisher: rel.publisher["username"] || "unknown",
         inserted_at: rel.inserted_at,
         updated_at: rel.updated_at,
         downloads: rel.downloads || 0,
         has_docs: rel.has_docs || false,
         build_tools: build_tools,
         elixir_requirement: elixir_req,
         dependencies: deps,
         retired:
           if(rel.retirement,
             do: %{
               reason: rel.retirement["reason"] || "unknown",
               message: rel.retirement["message"]
             },
             else: nil
           )
       }}
    end
  end

  @doc """
  Get the dependencies of a package version.

  If `version` is nil, resolves to the latest stable version.
  """
  def get_dependencies(name, version \\ nil) do
    with {:ok, version} <- resolve_version(name, version),
         {:ok, rel} <- Client.get_release(name, version) do
      reqs = rel.requirements || %{}

      deps =
        reqs
        |> Enum.sort_by(fn {dep_name, _} -> dep_name end)
        |> Enum.map(fn {dep_name, info} ->
          %{
            name: dep_name,
            requirement: info["requirement"] || "any",
            optional: info["optional"] || false
          }
        end)

      {:ok, %{name: name, version: version, dependencies: deps}}
    end
  end

  @doc """
  Get optional features/extras for a package release.

  If `version` is nil, resolves to the latest stable version.
  """
  def get_features(name, version \\ nil) do
    with {:ok, version} <- resolve_version(name, version),
         {:ok, rel} <- Client.get_release(name, version) do
      reqs = rel.requirements || %{}

      optional_deps =
        reqs
        |> Enum.filter(fn {_, info} -> info["optional"] end)
        |> Enum.map(fn {dep_name, info} ->
          %{name: dep_name, requirement: info["requirement"] || "any"}
        end)

      extra_metadata = get_in(rel.meta, ["extra"]) || %{}

      {:ok,
       %{
         name: name,
         version: version,
         optional_deps: optional_deps,
         extra_metadata: extra_metadata
       }}
    end
  end

  # ---------------------------------------------------------------------------
  # Composite / analytical
  # ---------------------------------------------------------------------------

  @doc """
  Compare 2-5 hex.pm packages side by side.

  Accepts a list of package name strings.
  """
  def compare_packages(names) when is_list(names) do
    cond do
      length(names) < 2 -> {:error, :too_few_packages}
      length(names) > 5 -> {:error, :too_many_packages}
      true -> do_compare(names)
    end
  end

  defp do_compare(names) do
    results =
      names
      |> Task.async_stream(
        fn name ->
          case Client.get_package(name) do
            {:ok, pkg} ->
              version = pkg.latest_stable_version || pkg.latest_version

              dep_count =
                case Client.get_release(name, version) do
                  {:ok, rel} -> map_size(rel.requirements || %{})
                  _ -> 0
                end

              {name,
               {:ok,
                %{
                  name: pkg.name,
                  downloads_all: pkg.downloads["all"] || 0,
                  downloads_recent: pkg.downloads["recent"] || 0,
                  latest_version: pkg.latest_stable_version || pkg.latest_version || "?",
                  updated_at: pkg.updated_at,
                  licenses: (get_in(pkg.meta, ["licenses"]) || []) |> Enum.join(", "),
                  dep_count: dep_count
                }}}

            error ->
              {name, error}
          end
        end,
        timeout: 30_000
      )
      |> Enum.map(fn {:ok, result} -> result end)

    packages =
      Enum.map(results, fn
        {_name, {:ok, data}} -> data
        {name, _error} -> %{name: name, error: true}
      end)

    {:ok, packages}
  end

  @doc """
  Comprehensive health check for a hex.pm package.
  """
  def health_check(name) do
    tasks = %{
      package: Task.async(fn -> Client.get_package(name) end),
      owners: Task.async(fn -> Client.get_owners(name) end)
    }

    pkg_result = Task.await(tasks.package, 30_000)
    owners_result = Task.await(tasks.owners, 30_000)

    case pkg_result do
      {:ok, pkg} ->
        owners =
          case owners_result do
            {:ok, o} -> o
            _ -> []
          end

        version = pkg.latest_stable_version || pkg.latest_version

        release =
          case if(version, do: Client.get_release(name, version), else: {:error, :no_version}) do
            {:ok, r} -> r
            _ -> nil
          end

        now = DateTime.utc_now()

        {:ok,
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
         }}

      error ->
        error
    end
  end

  @doc """
  Audit a package's dependencies for risks.

  Checks each dependency for retired versions, stale packages,
  single-owner packages, and known vulnerabilities via OSV.dev.
  """
  def audit_dependencies(name, version \\ nil) do
    with {:ok, version} <- resolve_version(name, version),
         {:ok, rel} <- Client.get_release(name, version) do
      reqs = rel.requirements || %{}

      if map_size(reqs) == 0 do
        {:ok,
         %{
           name: name,
           version: version,
           total_checked: 0,
           total_warnings: 0,
           deps_with_warnings: 0,
           results: []
         }}
      else
        audit_results =
          reqs
          |> Map.keys()
          |> Task.async_stream(fn dep_name -> {dep_name, audit_dep(dep_name)} end,
            timeout: 30_000
          )
          |> Enum.map(fn {:ok, result} -> result end)
          |> Enum.sort_by(fn {dep_name, _} -> dep_name end)

        total = length(audit_results)
        with_warnings = Enum.count(audit_results, fn {_, issues} -> issues != [] end)
        total_warnings = Enum.sum(Enum.map(audit_results, fn {_, issues} -> length(issues) end))

        results =
          Enum.map(audit_results, fn {dep_name, issues} ->
            %{name: dep_name, issues: issues}
          end)

        {:ok,
         %{
           name: name,
           version: version,
           total_checked: total,
           total_warnings: total_warnings,
           deps_with_warnings: with_warnings,
           results: results
         }}
      end
    end
  end

  @doc """
  Find and compare alternative packages for a given hex.pm package.
  """
  def find_alternatives(name) do
    case Client.get_package(name) do
      {:ok, pkg} ->
        keywords = extract_keywords(pkg)

        alternatives =
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
          |> Enum.reject(&(&1.name == name))
          |> Enum.sort_by(fn p -> -(p.downloads["recent"] || 0) end)
          |> Enum.take(10)
          |> Enum.map(fn alt ->
            %{
              name: alt.name,
              version: alt.latest_stable_version || alt.latest_version || "?",
              downloads_all: alt.downloads["all"] || 0,
              downloads_recent: alt.downloads["recent"] || 0,
              updated_at: alt.updated_at,
              status: maintenance_status(alt.updated_at),
              description: get_in(alt.meta, ["description"]) || "",
              licenses: (get_in(alt.meta, ["licenses"]) || []) |> Enum.join(", ")
            }
          end)

        package = %{
          name: pkg.name,
          description: get_in(pkg.meta, ["description"]) || "",
          downloads_all: pkg.downloads["all"] || 0,
          downloads_recent: pkg.downloads["recent"] || 0
        }

        {:ok, %{package: package, alternatives: alternatives}}

      error ->
        error
    end
  end

  @doc """
  Get the full transitive dependency tree for a package (BFS, max depth 5).
  """
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
  """
  def get_readme(name, version \\ nil), do: HexDocs.get_readme(name, version)

  @doc """
  Get the module listing for a package's documentation.
  """
  def get_docs(name, version \\ nil), do: HexDocs.get_modules(name, version)

  @doc """
  Get full documentation for a specific module or function.
  """
  def get_doc_item(name, module, version \\ nil), do: HexDocs.get_doc_item(name, module, version)

  @doc """
  Search within a package's documentation by name.
  """
  def search_docs(name, query, version \\ nil), do: HexDocs.search_docs(name, query, version)

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

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
