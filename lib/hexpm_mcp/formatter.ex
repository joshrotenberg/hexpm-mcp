defmodule HexpmMcp.Formatter do
  @moduledoc """
  Shared formatting helpers for tool output.

  Each `format_*` function takes structured data from `HexpmMcp` API functions
  and returns a markdown string suitable for MCP tool responses.
  """

  # ---------------------------------------------------------------------------
  # Primitives
  # ---------------------------------------------------------------------------

  @doc """
  Format a number with K/M suffix for readability.

      iex> HexpmMcp.Formatter.format_number(1_234_567)
      "1.2M"

      iex> HexpmMcp.Formatter.format_number(45_678)
      "45.7K"

      iex> HexpmMcp.Formatter.format_number(999)
      "999"
  """
  def format_number(n) when is_integer(n) and n >= 1_000_000 do
    "#{Float.round(n / 1_000_000, 1)}M"
  end

  def format_number(n) when is_integer(n) and n >= 1_000 do
    "#{Float.round(n / 1_000, 1)}K"
  end

  def format_number(n) when is_integer(n), do: "#{n}"
  def format_number(nil), do: "0"

  @doc """
  Format a date string to a short date (YYYY-MM-DD).
  """
  def format_date(nil), do: "unknown"

  def format_date(date_string) when is_binary(date_string) do
    case String.split(date_string, "T") do
      [date | _] -> date
      _ -> date_string
    end
  end

  @doc """
  Build a markdown table from headers and rows.
  """
  def markdown_table(headers, rows) do
    widths =
      Enum.map(0..(length(headers) - 1), fn i ->
        col_values = [Enum.at(headers, i) | Enum.map(rows, &Enum.at(&1, i, ""))]
        col_values |> Enum.map(&String.length/1) |> Enum.max()
      end)

    header_line =
      headers
      |> Enum.with_index()
      |> Enum.map_join(" | ", fn {h, i} -> String.pad_trailing(h, Enum.at(widths, i)) end)

    separator =
      widths
      |> Enum.map_join(" | ", fn w -> String.duplicate("-", w) end)

    data_lines =
      Enum.map(rows, fn row ->
        row
        |> Enum.with_index()
        |> Enum.map_join(" | ", fn {cell, i} -> String.pad_trailing(cell, Enum.at(widths, i)) end)
      end)

    Enum.join(
      ["| #{header_line} |", "| #{separator} |" | Enum.map(data_lines, &"| #{&1} |")],
      "\n"
    )
  end

  @doc """
  Format a list of items as a markdown bullet list.
  """
  def bullet_list(items) do
    Enum.map_join(items, "\n", &"- #{&1}")
  end

  defp format_retirement_badge(nil), do: ""

  defp format_retirement_badge(retired) do
    suffix =
      if retired.message,
        do: " - #{retired.reason}: #{retired.message}",
        else: " - #{retired.reason}"

    " [RETIRED#{suffix}]"
  end

  # ---------------------------------------------------------------------------
  # Tool-specific formatters
  # ---------------------------------------------------------------------------

  @doc """
  Format search results as markdown.
  """
  def format_search_results(query, results) do
    if results == [] do
      "No packages found matching '#{query}'."
    else
      header = "# Search Results for '#{query}'\n\nFound #{length(results)} packages:\n\n"

      entries =
        Enum.map_join(results, "\n\n", fn r ->
          """
          ## #{r.name} (v#{r.version || "?"})
          #{r.description}
          - Downloads: #{format_number(r.downloads_all)} all-time, #{format_number(r.downloads_recent)} recent
          - #{r.url}\
          """
        end)

      header <> entries
    end
  end

  @doc """
  Format package info as markdown.
  """
  def format_package_info(info) do
    sections = [
      "# #{info.name}",
      info.description,
      "",
      "## Version Info",
      "- Latest stable: #{info.latest_stable_version || "none"}",
      "- Latest: #{info.latest_version || "none"}",
      "",
      "## Downloads",
      "- All-time: #{format_number(info.downloads.all)}",
      "- Recent (90 days): #{format_number(info.downloads.recent)}",
      "- This week: #{format_number(info.downloads.week)}",
      "- Today: #{format_number(info.downloads.day)}",
      "",
      "## Metadata",
      "- Created: #{format_date(info.inserted_at)}",
      "- Updated: #{format_date(info.updated_at)}",
      "- Licenses: #{Enum.join(info.licenses, ", ")}",
      "- Build tools: #{Enum.join(info.build_tools, ", ")}"
    ]

    sections =
      if info.elixir_requirement do
        sections ++ ["- Elixir requirement: #{info.elixir_requirement}"]
      else
        sections
      end

    sections =
      if info.docs_url do
        sections ++ ["", "## Links", "- Docs: #{info.docs_url}"]
      else
        sections ++ ["", "## Links"]
      end

    sections = sections ++ ["- hex.pm: #{info.hex_url}"]

    sections =
      Enum.reduce(info.links, sections, fn {label, url}, acc ->
        acc ++ ["- #{label}: #{url}"]
      end)

    Enum.join(sections, "\n")
  end

  @doc """
  Format versions list as markdown.
  """
  def format_versions(data) do
    header = "# Versions of #{data.name}\n\n"

    entries =
      Enum.map_join(data.versions, "\n", fn v ->
        date = format_date(v.inserted_at)
        has_docs = if v.has_docs, do: "docs", else: "no docs"
        retired = format_retirement_badge(v.retired)
        "- **#{v.version}** (#{date}) [#{has_docs}]#{retired}"
      end)

    header <> entries
  end

  @doc """
  Format release info as markdown.
  """
  def format_release(data) do
    retired_banner = format_retired_banner(data.retired)

    details = [
      "",
      "## Details",
      "- Publisher: #{data.publisher}",
      "- Published: #{format_date(data.inserted_at)}",
      "- Updated: #{format_date(data.updated_at)}",
      "- Downloads: #{format_number(data.downloads)}",
      "- Docs: #{if data.has_docs, do: "available", else: "not available"}",
      "- Build tools: #{Enum.join(data.build_tools, ", ")}"
    ]

    details =
      if data.elixir_requirement,
        do: details ++ ["- Elixir requirement: #{data.elixir_requirement}"],
        else: details

    deps_section = format_deps_section(data.dependencies)

    (["# #{data.name} v#{data.version}"] ++ retired_banner ++ details ++ deps_section)
    |> Enum.join("\n")
  end

  defp format_retired_banner(nil), do: []

  defp format_retired_banner(retired) do
    msg = if retired.message, do: ": #{retired.message}", else: ""
    ["", "> **RETIRED** (#{retired.reason}#{msg})"]
  end

  defp format_deps_section([]), do: ["", "## Dependencies", "None"]

  defp format_deps_section(deps) do
    dep_lines =
      Enum.map_join(deps, "\n", fn dep ->
        optional = if dep.optional, do: " (optional)", else: ""
        "  - #{dep.name}: #{dep.requirement}#{optional}"
      end)

    ["", "## Dependencies (#{length(deps)})", dep_lines]
  end

  @doc """
  Format features as markdown.
  """
  def format_features(data) do
    sections = ["# Features for #{data.name} v#{data.version}"]

    sections =
      if data.optional_deps != [] do
        items =
          Enum.map_join(data.optional_deps, "\n", fn dep ->
            "- #{dep.name}: #{dep.requirement}"
          end)

        sections ++ ["", "## Optional Dependencies", items]
      else
        sections ++ ["", "No optional dependencies."]
      end

    sections =
      if map_size(data.extra_metadata) > 0 do
        items =
          Enum.map_join(data.extra_metadata, "\n", fn {key, value} ->
            "- #{key}: #{inspect(value)}"
          end)

        sections ++ ["", "## Extra Metadata", items]
      else
        sections
      end

    Enum.join(sections, "\n")
  end

  @doc """
  Format dependencies as markdown.
  """
  def format_dependencies(data) do
    count = length(data.dependencies)
    header = "# Dependencies for #{data.name} v#{data.version}\n\nTotal: #{count} dependencies\n"

    case data.dependencies do
      [] -> header <> "\nNo dependencies."
      deps -> header <> "\n" <> format_dep_list(deps)
    end
  end

  defp format_dep_list(deps) do
    Enum.map_join(deps, "\n", fn dep ->
      optional = if dep.optional, do: " (optional)", else: ""
      "- #{dep.name}: #{dep.requirement}#{optional}"
    end)
  end

  @doc """
  Format reverse dependencies as markdown.
  """
  def format_reverse_dependencies(data) do
    header =
      "# Packages depending on #{data.name}\n\nFound #{length(data.dependents)} dependents:\n\n"

    if data.dependents == [] do
      header <> "No packages depend on #{data.name}."
    else
      entries =
        Enum.map_join(data.dependents, "\n", fn dep ->
          "- **#{dep.name}** (#{format_number(dep.downloads)} downloads) #{dep.description}"
        end)

      header <> entries
    end
  end

  @doc """
  Format download statistics as markdown.
  """
  def format_downloads(data) do
    """
    # Download Statistics for #{data.name}

    - All-time: #{format_number(data.all)}
    - Recent (90 days): #{format_number(data.recent)}
    - This week: #{format_number(data.week)}
    - Today: #{format_number(data.day)}\
    """
  end

  @doc """
  Format owners as markdown.
  """
  def format_owners(name, owners) do
    header = "# Owners of #{name}\n\n"

    entries =
      Enum.map_join(owners, "\n", fn owner ->
        email = if owner.email, do: " (#{owner.email})", else: ""
        "- #{owner.username}#{email}"
      end)

    header <> entries
  end

  @doc """
  Format package comparison as markdown table.
  """
  def format_comparison(packages) do
    headers = ["Metric" | Enum.map(packages, & &1.name)]

    rows = [
      comparison_row("Downloads (all)", packages, &format_number(&1.downloads_all)),
      comparison_row("Downloads (90d)", packages, &format_number(&1.downloads_recent)),
      comparison_row("Latest version", packages, & &1.latest_version),
      comparison_row("Last updated", packages, &format_date(&1.updated_at)),
      comparison_row("License", packages, & &1.licenses),
      comparison_row("Dependencies", packages, &"#{&1.dep_count}")
    ]

    "# Package Comparison\n\n" <> markdown_table(headers, rows)
  end

  defp comparison_row(label, packages, fun) do
    [
      label
      | Enum.map(packages, fn
          %{error: true} -> "N/A"
          pkg -> fun.(pkg)
        end)
    ]
  end

  @doc """
  Format health check as markdown.
  """
  def format_health_check(health) do
    sections = [
      "# Health Check: #{health.name}",
      "",
      format_maintenance_section(health.maintenance),
      format_popularity_section(health.popularity),
      format_quality_section(health.quality),
      format_risk_section(health.risk),
      format_links_section(health.links)
    ]

    Enum.join(sections, "\n")
  end

  defp format_maintenance_section(m) do
    lines = [
      "## Maintenance",
      "- Age: #{m.age}",
      "- Total versions: #{m.total_versions}",
      "- Status: **#{m.status}**"
    ]

    lines =
      if m.days_since_release do
        lines ++ ["- Days since last release: #{m.days_since_release}"]
      else
        lines
      end

    Enum.join(lines, "\n") <> "\n"
  end

  defp format_popularity_section(p) do
    """
    ## Popularity
    - All-time downloads: #{format_number(p.all)}
    - Recent (90 days): #{format_number(p.recent)}
    - Weekly: #{format_number(p.week)}
    """
  end

  defp format_quality_section(q) do
    lines = [
      "## Quality",
      "- Documentation: #{if q.has_docs, do: "available", else: "not available"}",
      "- Licenses: #{Enum.join(q.licenses, ", ")}",
      "- Build tools: #{Enum.join(q.build_tools, ", ")}",
      "- Dependencies: #{q.required_deps} required, #{q.optional_deps} optional"
    ]

    lines =
      if q.elixir_requirement do
        lines ++ ["- Elixir requirement: #{q.elixir_requirement}"]
      else
        lines
      end

    Enum.join(lines, "\n") <> "\n"
  end

  defp format_risk_section(r) do
    owner_warning = if r.owner_count == 1, do: " (single maintainer!)", else: ""

    lines = [
      "## Risk",
      "- Maintainers: #{r.owner_count}#{owner_warning}",
      "- Retired versions: #{r.retired_count}"
    ]

    Enum.join(lines, "\n") <> "\n"
  end

  defp format_links_section(links) do
    base = ["## Links"]

    base =
      if links[:docs_url] do
        base ++ ["- Docs: #{links[:docs_url]}"]
      else
        base
      end

    base = base ++ ["- hex.pm: #{links[:hex_url]}"]

    # Add any extra links (from meta)
    extra =
      links
      |> Map.drop([:docs_url, :hex_url])
      |> Enum.map(fn {label, url} -> "- #{label}: #{url}" end)

    Enum.join(base ++ extra, "\n")
  end

  @doc """
  Format audit results as markdown.
  """
  def format_audit(audit) do
    if audit.total_checked == 0 do
      "#{audit.name} v#{audit.version} has no dependencies to audit."
    else
      header = """
      # Dependency Audit: #{audit.name} v#{audit.version}

      Checked #{audit.total_checked} dependencies. #{audit.total_warnings} warning(s) across #{audit.deps_with_warnings} package(s).
      """

      details = Enum.map_join(audit.results, "\n", &format_audit_dep/1)
      header <> "\n" <> details
    end
  end

  defp format_audit_dep(%{name: name, issues: []}), do: "- **#{name}**: no issues"

  defp format_audit_dep(%{name: name, issues: issues}),
    do: "- **#{name}**: #{Enum.join(issues, "; ")}"

  @doc """
  Format alternatives as markdown.
  """
  def format_alternatives(data) do
    pkg = data.package

    header = """
    # Alternatives to #{pkg.name}

    #{pkg.description}
    - Downloads: #{format_number(pkg.downloads_all)} all-time, #{format_number(pkg.downloads_recent)} recent
    """

    if data.alternatives == [] do
      header <> "\nNo alternative packages found."
    else
      table_headers = ["Package", "Version", "Downloads", "Recent", "Last Release", "Status"]

      rows =
        Enum.map(data.alternatives, fn alt ->
          [
            alt.name,
            alt.version,
            format_number(alt.downloads_all),
            format_number(alt.downloads_recent),
            format_date(alt.updated_at),
            alt.status
          ]
        end)

      table = markdown_table(table_headers, rows)

      details =
        Enum.map_join(data.alternatives, "\n\n", fn alt ->
          """
          ### #{alt.name}
          #{alt.description}
          - License: #{alt.licenses}
          - https://hex.pm/packages/#{alt.name}\
          """
        end)

      header <> "\n## Comparison\n\n" <> table <> "\n\n## Details\n\n" <> details
    end
  end

  @doc """
  Format dependency tree as markdown.
  """
  def format_dependency_tree(data) do
    header =
      "# Dependency Tree: #{data.name} v#{data.version}\n\nTotal unique dependencies: #{data.total_unique_deps}\n\n"

    entries = Enum.map_join(data.tree, "\n", &format_tree_entry/1)
    header <> entries
  end

  defp format_tree_entry(entry) do
    indent = String.duplicate("  ", entry.depth)
    pkg_line = "#{indent}**#{entry.name}** v#{entry.version}"

    case entry.deps do
      [] -> pkg_line
      deps -> pkg_line <> "\n" <> format_tree_deps(deps)
    end
  end

  defp format_tree_deps(deps) do
    Enum.map_join(deps, "\n", fn dep ->
      indent = String.duplicate("  ", dep.depth)
      optional = if dep.optional, do: " (optional)", else: ""
      "#{indent}- #{dep.name}: #{dep.requirement}#{optional}"
    end)
  end

  @doc """
  Format module listing as markdown.
  """
  def format_docs(name, version, modules) do
    v = version || "latest"
    header = "# Documentation for #{name} (#{v})\n\n#{length(modules)} modules:\n\n"

    entries =
      Enum.map_join(modules, "\n", fn mod ->
        type_badge = if mod.type != "module", do: " [#{mod.type}]", else: ""
        doc_preview = if mod.doc != "", do: " -- #{String.slice(mod.doc, 0, 80)}", else: ""
        "- **#{mod.name}**#{type_badge}#{doc_preview}"
      end)

    header <> entries
  end

  @doc """
  Format doc search results as markdown.
  """
  def format_search_docs(name, query, results) do
    header = "# Search Results for '#{query}' in #{name}\n\nFound #{length(results)} results:\n\n"

    entries =
      Enum.map_join(results, "\n\n", fn item ->
        title = item["title"] || "?"
        type = item["type"] || "unknown"
        doc = item["doc"] || ""
        preview = String.slice(doc, 0, 120)

        """
        ### #{title} (#{type})
        #{preview}\
        """
      end)

    header <> entries
  end

  @doc """
  Format mix deps audit results as markdown.
  """
  def format_mix_audit(audit) do
    if audit.total_checked == 0 do
      "No dependencies found to audit."
    else
      header = """
      # Mix Dependencies Audit

      Checked #{audit.total_checked} dependencies. #{audit.total_warnings} warning(s) across #{audit.deps_with_warnings} package(s).
      """

      details = Enum.map_join(audit.results, "\n", &format_mix_audit_dep/1)
      header <> "\n" <> details
    end
  end

  defp format_mix_audit_dep(%{name: name, pinned_version: pinned, issues: []}) do
    "- **#{name}** (`#{pinned}`): no issues"
  end

  defp format_mix_audit_dep(%{name: name, pinned_version: pinned, issues: issues}) do
    "- **#{name}** (`#{pinned}`): #{Enum.join(issues, "; ")}"
  end

  @doc """
  Format upgrade check results as markdown.
  """
  def format_upgrade_check(data) do
    if data.total_checked == 0 do
      "No dependencies found to check."
    else
      header = """
      # Upgrade Check

      Checked #{data.total_checked} dependencies. #{data.upgrades_available} upgrade(s) available.
      """

      details = Enum.map_join(data.results, "\n", &format_upgrade_dep/1)
      header <> "\n" <> details
    end
  end

  defp format_upgrade_dep(%{status: :up_to_date} = dep) do
    "- **#{dep.name}** (`#{dep.pinned_version}`): up to date (#{dep.latest_version})"
  end

  defp format_upgrade_dep(%{status: :error} = dep) do
    "- **#{dep.name}** (`#{dep.pinned_version}`): could not check"
  end

  defp format_upgrade_dep(dep) do
    status_label = status_to_label(dep.status)
    retired = if dep.retired, do: " [RETIRED]", else: ""

    "- **#{dep.name}** (`#{dep.pinned_version}` -> `#{dep.latest_version}`): #{status_label}#{retired}"
  end

  defp status_to_label(:major_upgrade), do: "MAJOR upgrade available"
  defp status_to_label(:minor_upgrade), do: "minor upgrade available"
  defp status_to_label(:patch_upgrade), do: "patch upgrade available"
  defp status_to_label(:unknown), do: "upgrade status unknown"
  defp status_to_label(_), do: "unknown"
end
