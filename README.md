# hexpm-mcp

[![CI](https://github.com/joshrotenberg/hexpm-mcp/actions/workflows/ci.yml/badge.svg)](https://github.com/joshrotenberg/hexpm-mcp/actions/workflows/ci.yml)
[![Deploy](https://github.com/joshrotenberg/hexpm-mcp/actions/workflows/deploy.yml/badge.svg)](https://github.com/joshrotenberg/hexpm-mcp/actions/workflows/deploy.yml)

MCP server for querying [hex.pm](https://hex.pm) and [hexdocs.pm](https://hexdocs.pm) -- the Elixir/Erlang package registry and documentation hosting.

Built with [Anubis MCP](https://hex.pm/packages/anubis_mcp) + [Bandit](https://hex.pm/packages/bandit) in Elixir.

## Deployed Instance

A public instance is running on Fly.io and available for any MCP client:

```
https://hexpm-mcp.fly.dev/mcp
```

Add to Claude Desktop `claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "hexpm": {
      "type": "http",
      "url": "https://hexpm-mcp.fly.dev/mcp"
    }
  }
}
```

Or in a project `.mcp.json` for Claude Code:

```json
{
  "mcpServers": {
    "hexpm": {
      "type": "http",
      "url": "https://hexpm-mcp.fly.dev/mcp"
    }
  }
}
```

## Features

- 17 tools for searching, inspecting, comparing, and auditing hex.pm packages
- 3 URI-template resources for structured package data access
- 5 guided analysis prompts
- HexDocs browsing (module listing, doc search, full module docs)
- OSV.dev vulnerability checking
- Mix.exs dependency auditing and upgrade checking
- ETS-based response caching with configurable TTL
- Dual transport: stdio (Claude Code/Desktop) and StreamableHTTP (remote)
- Public Elixir API usable directly from iex

## Tools

### Package information
| Tool | Description |
|------|-------------|
| `search` | Search packages by name/keywords with sorting and pagination |
| `info` | Package metadata, description, links, download stats |
| `versions` | Version history with retirement status |
| `release` | Release details, publisher, dependencies, build tools |
| `features` | Optional dependencies and extra metadata |
| `dependencies` | Dependency list for a version |
| `reverse` | Packages that depend on a given package |
| `downloads` | Download statistics (all-time, recent, weekly, daily) |
| `owners` | Package maintainers |
| `readme` | README content as markdown |

### Documentation browsing
| Tool | Description |
|------|-------------|
| `docs` | Module listing (table of contents) from hexdocs.pm |
| `doc_item` | Full documentation for a specific module |
| `search_docs` | Search within a package's documentation |

### Analysis
| Tool | Description |
|------|-------------|
| `compare` | Side-by-side comparison of 2-5 packages |
| `health` | Maintenance, popularity, quality, and risk assessment |
| `audit` | Dependency risk audit (retired versions, staleness, bus factor, CVEs) |
| `alternatives` | Find and compare similar packages |
| `dep_tree` | Recursive dependency tree (BFS, max depth 5) |

### Mix.exs analysis
| Tool | Description |
|------|-------------|
| `audit_mix_deps` | Audit a deps list for staleness, retirement, CVEs, and bus factor |
| `upgrade_check` | Check which deps have newer versions, flag breaking changes |

## Example Output

### Health check

```
# Health Check: req

## Maintenance
- Age: 4 years ago
- Total versions: 52
- Status: **Active**
- Days since last release: 57

## Popularity
- All-time downloads: 11.5M
- Recent (90 days): 1.6M
- Weekly: 141.5K

## Quality
- Documentation: available
- Licenses: Apache-2.0
- Dependencies: 3 required, 4 optional
- Elixir requirement: ~> 1.14

## Risk
- Maintainers: 1 (single maintainer!)
- Retired versions: 0
```

### Package comparison

```
# Package Comparison

| Metric          | req        | httpoison  | finch      |
| --------------- | ---------- | ---------- | ---------- |
| Downloads (all) | 11.5M      | 129.2M     | 54.1M      |
| Downloads (90d) | 1.6M       | 1.6M       | 2.4M       |
| Latest version  | 0.5.17     | 2.3.0      | 0.21.0     |
| Last updated    | 2026-02-07 | 2025-11-14 | 2026-01-22 |
| License         | Apache-2.0 | MIT        | MIT        |
| Dependencies    | 7          | 1          | 5          |
```

### Dependency audit

```
# Dependency Audit: phoenix v1.8.5

Checked 10 dependencies. 8 warning(s) across 7 package(s).

- **bandit**: 1 retired version(s)
- **jason**: single maintainer
- **plug**: 2 retired version(s); 3 known vulnerability(ies)
- **telemetry**: no issues
```

## Usage

### Claude Code (stdio, local)

For local development, run from source:

```json
{
  "mcpServers": {
    "hexpm": {
      "command": "mix",
      "args": ["run", "--no-halt", "--", "--transport", "stdio"],
      "cwd": "/path/to/hexpm-mcp"
    }
  }
}
```

### iex

The public API is available directly from iex without the MCP server:

```elixir
$ MIX_ENV=test iex -S mix

iex> HexpmMcp.get_info("phoenix")
{:ok, %{
  name: "phoenix",
  description: "Peace of mind from prototype to production",
  downloads: %{all: 148_100_000, recent: 2_600_000, week: 223_000, day: 13_000},
  licenses: ["MIT"],
  latest_stable_version: "1.8.5",
  ...
}}

iex> HexpmMcp.health_check("req")
{:ok, %{
  name: "req",
  maintenance: %{status: "Active", age: "4 years ago", days_since_release: 57},
  popularity: %{all: 11_500_000, recent: 1_600_000, week: 141_000},
  quality: %{has_docs: true, licenses: ["Apache-2.0"], required_deps: 3, optional_deps: 4},
  risk: %{owner_count: 1, retired_count: 0},
  ...
}}

iex> HexpmMcp.compare_packages(["plug", "bandit"])
{:ok, [
  %{name: "plug", downloads_all: 156_000_000, dep_count: 3, ...},
  %{name: "bandit", downloads_all: 9_900_000, dep_count: 5, ...}
]}

iex> HexpmMcp.audit_mix_deps(~s({:phoenix, "~> 1.7"}, {:jason, "~> 1.0"}))
{:ok, %{total_checked: 2, total_warnings: 1, results: [...]}}
```

## API Reference

All 21 functions return `{:ok, structured_map}` or `{:error, reason}`.

```elixir
# Search and lookup
HexpmMcp.search(query, opts \\ [])
HexpmMcp.get_info(name)
HexpmMcp.get_downloads(name)
HexpmMcp.get_owners(name)
HexpmMcp.get_versions(name)
HexpmMcp.get_reverse_dependencies(name)

# Version-specific (pass nil for latest)
HexpmMcp.get_release(name, version \\ nil)
HexpmMcp.get_dependencies(name, version \\ nil)
HexpmMcp.get_features(name, version \\ nil)

# Composite analysis
HexpmMcp.compare_packages(names)
HexpmMcp.health_check(name)
HexpmMcp.audit_dependencies(name, version \\ nil)
HexpmMcp.find_alternatives(name)
HexpmMcp.dependency_tree(name, version \\ nil, opts \\ [])

# Mix.exs analysis
HexpmMcp.audit_mix_deps(deps_string)
HexpmMcp.upgrade_check(deps_string)

# HexDocs browsing
HexpmMcp.get_readme(name, version \\ nil)
HexpmMcp.get_docs(name, version \\ nil)
HexpmMcp.get_doc_item(name, module, version \\ nil)
HexpmMcp.search_docs(name, query, version \\ nil)
```

## Architecture

```
iex / Elixir code                 MCP clients
        |                              |
   HexpmMcp (public API)         MCP Tools (thin wrappers)
   returns {:ok, map}                  |
        |                         calls HexpmMcp API
   Client / HexDocs / OSV        then Formatter -> markdown
   (internal, HTTP clients)      then Response.text()
```

- **`HexpmMcp`** -- 21 public functions returning structured maps, usable from iex
- **`HexpmMcp.Formatter`** -- markdown formatting for MCP tool output
- **`HexpmMcp.Client`** -- Req-based hex.pm API client with rate limiting
- **`HexpmMcp.HexDocs`** -- hexdocs.pm browsing (sidebar data parsing, HTML-to-markdown)
- **`HexpmMcp.OSV`** -- OSV.dev vulnerability database client
- **`HexpmMcp.Cache`** -- ETS-based response cache with TTL and periodic sweeping
- **MCP Tools** -- thin wrappers calling the public API, registered via Anubis Server Components

## Development

```bash
# Install dependencies
mix deps.get

# Run tests
mix test

# Full CI check
mix format --check-formatted
mix compile --warnings-as-errors
mix credo --strict
mix dialyzer

# Run locally (HTTP on port 8765)
mix run --no-halt

# Run locally (stdio for MCP clients)
mix run --no-halt -- --transport stdio
```

## License

MIT
