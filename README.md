# hexpm-mcp

MCP server for querying [hex.pm](https://hex.pm) and [hexdocs.pm](https://hexdocs.pm) -- the Elixir/Erlang package registry and documentation hosting.

Built with [Anubis MCP](https://hex.pm/packages/anubis_mcp) + [Bandit](https://hex.pm/packages/bandit) in Elixir.

## Features

- 15 tools for searching, inspecting, comparing, and auditing hex.pm packages
- 3 resources for structured package data access
- 5 guided analysis prompts
- HexDocs browsing (module listing, doc search, full module docs)
- OSV.dev vulnerability checking
- ETS-based response caching with configurable TTL
- Dual transport: stdio (Claude Code/Desktop) and StreamableHTTP (remote)
- Public Elixir API usable from iex

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

## Usage

### Claude Code (stdio)

Add to your project's `.mcp.json`:

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

### Remote (StreamableHTTP)

A hosted instance is available at:

```
https://hexpm-mcp.fly.dev/mcp
```

### iex

The public API is available directly from iex without the MCP server:

```elixir
$ MIX_ENV=test iex -S mix

iex> HexpmMcp.get_info("phoenix")
{:ok, %{name: "phoenix", description: "Peace of mind from prototype to production", ...}}

iex> HexpmMcp.health_check("req")
{:ok, %{name: "req", maintenance: %{status: "Active", ...}, ...}}

iex> HexpmMcp.compare_packages(["plug", "bandit"])
{:ok, [%{name: "plug", downloads_all: 156_000_000, ...}, ...]}

iex> HexpmMcp.search_docs("phoenix", "Router")
{:ok, [%{"title" => "Phoenix.Router", "type" => "module", ...}]}
```

All 19 API functions return `{:ok, structured_map}` or `{:error, reason}`.

## API Functions

```elixir
# Search and lookup
HexpmMcp.search(query, opts \\ [])
HexpmMcp.get_info(name)
HexpmMcp.get_downloads(name)
HexpmMcp.get_owners(name)
HexpmMcp.get_versions(name)
HexpmMcp.get_reverse_dependencies(name)

# Version-specific
HexpmMcp.get_release(name, version \\ nil)
HexpmMcp.get_dependencies(name, version \\ nil)
HexpmMcp.get_features(name, version \\ nil)

# Analysis
HexpmMcp.compare_packages(names)
HexpmMcp.health_check(name)
HexpmMcp.audit_dependencies(name, version \\ nil)
HexpmMcp.find_alternatives(name)
HexpmMcp.dependency_tree(name, version \\ nil, opts \\ [])

# Documentation
HexpmMcp.get_readme(name, version \\ nil)
HexpmMcp.get_docs(name, version \\ nil)
HexpmMcp.get_doc_item(name, module, version \\ nil)
HexpmMcp.search_docs(name, query, version \\ nil)
```

## Development

```bash
# Install dependencies
mix deps.get

# Run tests
mix test

# Check formatting, warnings, types
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
