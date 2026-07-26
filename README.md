# hexpm-mcp

[![CI](https://github.com/joshrotenberg/hexpm-mcp/actions/workflows/ci.yml/badge.svg)](https://github.com/joshrotenberg/hexpm-mcp/actions/workflows/ci.yml)
[![Hex.pm](https://img.shields.io/hexpm/v/hexpm_mcp.svg)](https://hex.pm/packages/hexpm_mcp)
[![Docs](https://img.shields.io/badge/hexdocs-docs-purple.svg)](https://hexdocs.pm/hexpm_mcp)
![Elixir](https://img.shields.io/badge/Elixir-1.17%2B-blueviolet)
![OTP](https://img.shields.io/badge/OTP-28-blue)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](https://opensource.org/licenses/MIT)

MCP server for querying [hex.pm](https://hex.pm) and [hexdocs.pm](https://hexdocs.pm) -- the Elixir/Erlang package registry and documentation hosting.

Built with [Anubis MCP](https://hex.pm/packages/anubis_mcp) + [Bandit](https://hex.pm/packages/bandit) in Elixir.

## Quick Start

A public instance is running at `https://hexpm-mcp.fly.dev/mcp`. Add it to your MCP client config (Claude Desktop, Claude Code, or any MCP client):

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

## Installation

Three ways to get it, depending on how you want to use it.

### Standalone binary (recommended)

A self-contained binary for macOS, Linux, and Windows. It bundles the Erlang
runtime, so no Elixir toolchain is required.

```sh
curl -fsSL https://raw.githubusercontent.com/joshrotenberg/hexpm-mcp/main/scripts/install.sh | sh
```

The installer resolves the latest release, picks the asset for your OS and
architecture, verifies its sha256, and installs to `~/.local/bin`. It will tell
you if that directory is not on your `PATH`.

To choose a different directory or pin a version, pass the flags through `sh`:

```sh
curl -fsSL https://raw.githubusercontent.com/joshrotenberg/hexpm-mcp/main/scripts/install.sh | sh -s -- --install-dir /usr/local/bin
curl -fsSL https://raw.githubusercontent.com/joshrotenberg/hexpm-mcp/main/scripts/install.sh | sh -s -- --version v0.3.6
```

Windows uses the PowerShell equivalent:

```powershell
iex (irm https://raw.githubusercontent.com/joshrotenberg/hexpm-mcp/main/scripts/install.ps1)
```

Every [release](https://github.com/joshrotenberg/hexpm-mcp/releases) also
attaches the archives and a combined `checksums-sha256.txt` if you would rather
install by hand.

Verify it works:

```sh
hexpm_mcp --version
```

See [Usage](#usage) for the MCP client config, and
[macOS: "Apple could not verify hexpm_mcp"](#macos-apple-could-not-verify-hexpm_mcp)
if Gatekeeper blocks a browser-downloaded copy.

### As an Elixir library

For the public API from iex or your own code, without running an MCP server:

```elixir
def deps do
  [{:hexpm_mcp, "~> 0.3"}]
end
```

### From source

```sh
git clone https://github.com/joshrotenberg/hexpm-mcp.git
cd hexpm-mcp
mix deps.get
```

## Features

- 24 tools for searching, inspecting, comparing, auditing, and discovering hex.pm packages
- 5 resources for structured package and discovery data access
- 5 guided analysis prompts
- HexDocs browsing (module listing, doc search, full module docs)
- Curated package discovery via Elixir Toolbox (groups, trending, enriched search)
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

### Discovery (Elixir Toolbox)

Curated discovery via the [Elixir Toolbox](https://elixir-toolbox.dev) API. Project results carry GitHub/GitLab stats, a popularity score, and health signals not exposed by the raw hex.pm API.

| Tool | Description |
|------|-------------|
| `toolbox_groups` | Browse the curated taxonomy of groups and categories |
| `toolbox_group` | List the categories in a single group |
| `toolbox_category` | Curated projects in a category (sortable by name or downloads) |
| `toolbox_trending` | Trending Elixir packages |
| `toolbox_search` | Search packages with popularity and health signals |

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

### Standalone binary (stdio)

Once [installed](#standalone-binary-recommended):

```json
{
  "mcpServers": {
    "hexpm": {
      "command": "hexpm_mcp",
      "args": ["--transport", "stdio"]
    }
  }
}
```

The binary defaults to stdio, so `args` can be omitted. Run `hexpm_mcp --help`
for the full option list.

To serve over HTTP instead, pass `--transport http`. MCP is served at `/mcp`:

```sh
hexpm_mcp --transport http --port 1234
# MCP endpoint: http://localhost:1234/mcp
```

#### macOS: "Apple could not verify hexpm_mcp"

The binaries are not code-signed or notarized. macOS attaches a quarantine
attribute to anything downloaded by a browser, and refuses to run an unsigned
executable carrying it:

> **"hexpm_mcp" Not Opened.** Apple could not verify "hexpm_mcp" is free of
> malware that may harm your Mac or compromise your privacy.

Choose **Done**, not Move to Trash, then clear the attribute:

```sh
xattr -d com.apple.quarantine /path/to/hexpm_mcp
```

The System Settings route works too: Privacy & Security, then **Open Anyway**
next to the blocked-binary notice.

The installer above is unaffected, because `curl` does not set the quarantine
attribute. Only browser downloads do, so installing with `curl` or `wget` avoids
this entirely. If you do download the tarball in a browser, extract it with
`tar -xzf` from a terminal rather than double-clicking, since Archive Utility
propagates the attribute to the extracted files.

### From source (stdio)

To run from a checkout, e.g. for development:

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

The public API is available directly from iex without the MCP server, either
via the [Hex dependency](#as-an-elixir-library) or straight from a checkout:

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

Every function returns `{:ok, structured_map}` or `{:error, reason}`.

```elixir
# Search and lookup
HexpmMcp.search(query, opts \\ [])
HexpmMcp.get_info(name)
HexpmMcp.get_downloads(name)
HexpmMcp.get_owners(name)
HexpmMcp.get_versions(name)

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

# Elixir Toolbox (curated discovery)
HexpmMcp.toolbox_groups()
HexpmMcp.toolbox_group(group)
HexpmMcp.toolbox_category(group, category, opts \\ [])
HexpmMcp.toolbox_trending(opts \\ [])
HexpmMcp.toolbox_search(query)
```

## Architecture

```
iex / Elixir code                 MCP clients
        |                              |
   HexpmMcp (public API)         MCP Tools (thin wrappers)
   returns {:ok, map}                  |
        |                         calls HexpmMcp API
   Client / HexDocs / OSV /      then Formatter -> markdown
   Toolbox (internal clients)    then Response.text()
```

- **`HexpmMcp`** -- 25 public functions returning structured maps, usable from iex
- **`HexpmMcp.Formatter`** -- markdown formatting for MCP tool output
- **`HexpmMcp.Client`** -- Req-based hex.pm API client with rate limiting
- **`HexpmMcp.HexDocs`** -- hexdocs.pm browsing (sidebar data parsing, HTML-to-markdown)
- **`HexpmMcp.OSV`** -- OSV.dev vulnerability database client
- **`HexpmMcp.Toolbox`** -- Elixir Toolbox client for curated package discovery
- **`HexpmMcp.Cache`** -- ETS-based response cache with TTL and periodic sweeping
- **`HexpmMcp.CLI`** -- Cheer command tree; turns argv into the server's configuration
- **`HexpmMcp.MCP.StdioLifecycle`** -- exits 0 when a stdio client disconnects
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
