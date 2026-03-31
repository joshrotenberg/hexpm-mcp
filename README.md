# hexpm-mcp

[![CI](https://github.com/joshrotenberg/hexpm-mcp/actions/workflows/ci.yml/badge.svg)](https://github.com/joshrotenberg/hexpm-mcp/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/license-MIT%2FApache--2.0-blue.svg)](https://github.com/joshrotenberg/hexpm-mcp#license)
[![MSRV](https://img.shields.io/badge/MSRV-1.90-blue.svg)](https://github.com/joshrotenberg/hexpm-mcp)

[MCP](https://modelcontextprotocol.io) server for querying [hex.pm](https://hex.pm) -- the Elixir/Erlang package registry. Built with [tower-mcp](https://github.com/joshrotenberg/tower-mcp).

Gives your AI agent access to package search, dependency analysis, download stats, health checks, and audit tools -- everything it needs to make informed decisions about Elixir and Erlang dependencies.

## Quick start

### Install from crates.io

```bash
cargo install hexpm-mcp
```

### Build from source

```bash
git clone https://github.com/joshrotenberg/hexpm-mcp
cd hexpm-mcp
cargo install --path .
```

## MCP client configuration

### Claude Code (stdio)

```json
{
  "mcpServers": {
    "hexpm-mcp": {
      "command": "hexpm-mcp"
    }
  }
}
```

### Claude Desktop

Add to `claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "hexpm-mcp": {
      "command": "hexpm-mcp"
    }
  }
}
```

## What's included

### Tools (12)

| Tool | Description |
|------|-------------|
| `search_packages` | Search for packages by name or keywords |
| `get_package_info` | Detailed package metadata (description, licenses, links, stats) |
| `get_package_versions` | Version history with docs status, publish date, and retirement info |
| `get_release` | Detailed release info including deps, publisher, retirement, and build tools |
| `get_dependencies` | Dependencies for a package version (defaults to latest) |
| `get_reverse_dependencies` | Packages that depend on a given package |
| `get_downloads` | Download statistics (all-time, recent, weekly, daily) |
| `get_owners` | Package owners and maintainers |
| `compare_packages` | Compare 2-4 packages side by side |
| `package_health_check` | Comprehensive health report (maintenance, popularity, quality, risk) |
| `audit_dependencies` | Check deps for retired versions, stale packages, and single-owner risk |
| `find_alternatives` | Find and compare alternative packages |

## Usage examples

Ask your AI agent questions like:

- "Search hex.pm for JSON parsing libraries"
- "What are the dependencies of phoenix 1.7.20?"
- "Compare ecto and amnesia side by side"
- "Run a health check on the plug package"
- "Audit the dependencies of phoenix for any risks"
- "Find alternatives to httpoison"

## Configuration

```
hexpm-mcp [OPTIONS]

Options:
  -t, --transport <TRANSPORT>        Transport to use [default: stdio]
      --rate-limit-ms <RATE_LIMIT>   Rate limit interval in ms [default: 1000]
  -l, --log-level <LOG_LEVEL>        Log level [default: info]
  -h, --help                         Print help
```

The rate limiter controls how frequently the server calls the hex.pm API. The default of 1 request per second is a safe default for public API usage.

## License

MIT OR Apache-2.0
