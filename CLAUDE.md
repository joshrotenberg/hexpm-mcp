# hexpm-mcp

MCP server for querying hex.pm and hexdocs.pm. Deployed on Fly.io and published
to Hex. The current version is in `.release-please-manifest.json` (0.3.8 at the
time of writing).

Built with snodo in Elixir. The Rust/tower-mcp version is archived on the
`master` branch; `main` is the default branch.

snodo is published on Hex (`snodo` and `snodo_jsv`) and resolved through the
`snodo_dep/3` helper in mix.exs. Setting `SNODO_PATH` points both packages at
one local checkout. The MCP layer moved from anubis_mcp to snodo in #81.

## Architecture

```
lib/
  hexpm_mcp.ex             -- Public API (25 functions returning structured maps)
  hexpm_mcp/
    application.ex         -- OTP app: resolves CLI config, starts cache + transport,
                              or runs init and halts
    client.ex              -- HTTP client for hex.pm API (Req)
    hexdocs.ex             -- HexDocs client: sidebar_items parsing, HTML-to-markdown
    osv.ex                 -- OSV.dev client for vulnerability auditing
    toolbox.ex             -- Elixir Toolbox client: curated discovery (groups, trending, search)
    cache.ex               -- ETS-based response cache with TTL + sweeper
    types.ex               -- Response structs (Package, Release, Owner)
    formatter.ex           -- Markdown formatting (one function per API call)
    cli.ex                 -- Cheer command tree; argv -> server config or init
    cli/init.ex            -- the init subcommand's options
    init.ex                -- hexpm_mcp init: writes the local marketplace and
                              registers it through the claude and codex CLIs

    mcp/
      server.ex            -- Snodo.Server definition (24 tools, 5 resources, 6 prompts)
      stdio_lifecycle.ex   -- stdio task: runs Snodo.Transport.Stdio.serve/2,
                              halts 0 at EOF and 1 on transport failure
      package_completion.ex -- package-name completion for resource and prompt
                              arguments (one cached hex.pm search page)

    mcp/tools/             -- Thin wrappers: call HexpmMcp API -> Formatter -> Snodo.Result
      search.ex, info.ex, versions.ex, release.ex, features.ex,
      dependencies.ex, downloads.ex, owners.ex, readme.ex,
      compare.ex, health.ex, audit.ex, alternatives.ex, dep_tree.ex,
      docs.ex, doc_item.ex, search_docs.ex,
      audit_mix_deps.ex, upgrade_check.ex,
      toolbox_groups.ex, toolbox_group.ex, toolbox_category.ex,
      toolbox_trending.ex, toolbox_search.ex

    mcp/resources/         -- URI resources: hex://{name}/info, /readme, /docs;
                              toolbox://groups, toolbox://{group}/{category}
    mcp/prompts/           -- Guided analysis prompts (6): analyze_package,
                              compare_packages, evaluate_dependencies,
                              recommend_packages, migration_guide, package_review

priv/plugin/hexpm/         -- Claude Code and Codex plugin, embedded by init.ex
  .claude-plugin/plugin.json, .codex-plugin/plugin.json -- no version; init adds it
  skills/hexpm/SKILL.md    -- dependency workflow skill
  hooks/hooks.json, hooks/mix-deps.sh -- PostToolUse hook on mix.exs / mix.lock edits

test/
  test_helper.exs
  hexpm_mcp_test.exs       -- API-level tests (Bypass mocks)
  hexpm_mcp/
    client_test.exs        -- Client HTTP tests (Bypass)
    cache_test.exs         -- Cache TTL/fetch tests
    cli_test.exs           -- argv parsing and config/1
    formatter_test.exs     -- Markdown formatter tests
    hexdocs_test.exs       -- HTML-to-markdown tests
    init_test.exs          -- init planning, written files, host steps (fake runner)
    plugin_test.exs        -- manifests, skill names only served tools, hook script
    toolbox_test.exs       -- Elixir Toolbox client tests (Bypass)
    mcp/
      server_test.exs                 -- discovery, catalogs, argument validation,
                                         HTTP listener per protocol version
      application_acceptance_test.exs -- tools and resources over direct, stdio, and HTTP
      discovery_workflow_test.exs     -- completions, list caching and cursors,
                                         package_review elicitation
      stdio_lifecycle_test.exs        -- the real app over stdio: EOF, drain,
                                         initialize-era negotiation, failure exits
  fixtures/
    mcp_tool_catalog.json  -- expected tools/list catalog (server_test.exs)
  support/
    fixtures.ex            -- Shared test data builders
```

## Design

### Layered architecture

```
iex / Elixir code              MCP clients
       |                            |
  HexpmMcp (public API)       MCP Tools (thin wrappers)
  returns {:ok, map}                |
       |                       HexpmMcp API -> Formatter -> Snodo.Result.text()
  Client / HexDocs / OSV / Toolbox
```

- HexpmMcp: 25 public functions (24 documented + one @doc false helper), usable from iex
- Tools: each is a `Snodo.Tool.Simple` with one `call/2` that calls the API,
  formats, and returns `Snodo.Result.text/1` or `Snodo.Result.error/1`
- Formatter: one format function per API call, takes structured data -> markdown

The snodo runtime is an immutable value, not a process. `Server.runtime/0` is an
ordinary function call that builds it, and the transport child receives it at
startup. `HexpmMcp.Application` starts `HexpmMcp.Cache` plus one transport:

- stdio: `HexpmMcp.MCP.StdioLifecycle`, a temporary task. EOF waits for admitted
  requests, then halts 0; a transport failure prints to stderr and halts 1. A
  consumed stdin cannot be reconnected, so the task is never restarted.
- http: `Snodo.Transport.StreamableHTTP.Server`, snodo's native HTTP/1.1
  listener. It binds `0.0.0.0` on the configured port, serves `/mcp`, and
  checks `Origin` against `allowed_origin_hosts`. Since snodo 0.4.3 it keeps
  connections alive between requests, so the raw-socket helpers in
  `server_test.exs` and `application_acceptance_test.exs`, which read until the
  socket closes, send `Connection: close`.
- none: the test env sets `transport: :none`, so no transport starts and the
  test runner's argv is never parsed as ours.

The server declares three protocol dialects: `Snodo.Protocol.V2026_07_28`,
`V2025_11_25`, and `V2025_06_18`. 2026-07-28 clients use `server/discover`; the
two older versions negotiate through `initialize`. Catalogs use
`pagination: [page_size: 100]` so every list fits on one page, because some
clients (Codex 0.157.1 among them) read only the first page of `tools/list`.
Discovery and the tool, prompt, and resource lists carry 60-second public cache
hints.

Resources declare a `uri_template` (or a fixed `uri` for `toolbox://groups`);
snodo matches the URI and binds its variables before `read/2` runs. Resource
payloads pass through `Snodo.JSONValue.encodable!/1`, which converts atom keys,
structs, and dates into JSON values.

The server installs `Snodo.Schema.Validator.JSV` from `snodo_jsv`. snodo's
default, `Snodo.Schema.Validator.Passthrough`, advertises input schemas but does
not enforce them. With JSV, a `tools/call` with a missing or mistyped argument
returns an `isError` tool result before the handler runs.

The server sends `instructions` (the `@instructions` heredoc in `server.ex`) in
the initialize result and in `server/discover`. A client that defers loading
tool definitions, such as Claude Code with tool search, shows this text in place
of the tool list, so it names the entry tools for each task. It sits in the
client's context for the whole session, so keep it short. Nothing checks the
tool names in it against the catalog.

Completion: the `package_info` resource and the `analyze_package` and
`package_review` prompts complete `name` through `HexpmMcp.MCP.PackageCompletion`.
It fetches one cached hex.pm search page for a `[a-z0-9_]` prefix of 2 to 64
bytes, keeps names that start with the prefix (at most 100), and sets `has_more`
when the upstream page was full.

`package_review` asks for a missing `focus` (quality, security, or upgrade)
through an MRTR form elicitation. A client that cannot answer one, which
includes every 2025-11-25 and 2025-06-18 client, gets a review across all three
focuses unless it passes the `focus` argument.

### HexDocs browsing

HexDocs has no structured API. The approach:
1. Parse `sidebar_items-{hash}.js` (the JS search index) for module listings
2. Fall back to scraping the HTML sidebar if JS unavailable
3. For individual module docs, fetch HTML and convert to markdown (Floki)
4. Strip navigation chrome, extract code language from class attributes
5. Cache aggressively in ETS (docs change only on new releases)

### hex.pm API coverage

We cover every read endpoint in the hex.pm API spec:
- `GET /packages?search=...` -- search
- `GET /packages/{name}` -- info, versions, downloads
- `GET /packages/{name}/releases/{version}` -- release, dependencies, features
- `GET /packages/{name}/owners` -- owners

Note: hex.pm has no reverse_dependencies endpoint (removed in previous version).

## Deployment

Deployed at https://hexpm-mcp.fly.dev/mcp

`fly.toml`: app `hexpm-mcp`, region `sjc`, internal port 8765, `force_https`,
machines auto-stop and auto-start with `min_machines_running = 0`, one
`shared-cpu-1x` VM with 512 MB. The image is built from the Dockerfile with a
plain `mix release` and started with `bin/hexpm_mcp start`, so the transport
defaults to http.

Runtime env, read by `config/runtime.exs` in prod only:
- `HEXPM_MCP_PORT` (default 8765; `--port` overrides it)
- `HEXPM_MCP_CACHE_TTL` (seconds, default 300)
- `HEXPM_MCP_DOCS_CACHE_TTL` (seconds, default 3600)
- `HEXPM_MCP_ALLOWED_ORIGIN_HOSTS` (comma-separated, default
  `127.0.0.1,localhost,::1,hexpm-mcp.fly.dev`)

`fly.toml` sets the first three.

CI/CD pipeline:
1. Push or PR to main -> CI (`ci.yml`): format check, compile with warnings as
   errors, test, `credo --strict`; dialyzer in a separate job
2. Push to main -> release-please creates/updates the release PR
3. Merge release PR -> release-please tags and publishes the GitHub release, and
   `release-please.yml` runs `publish-hex` (`mix hex.publish`), `binaries`
   (`release.yml`), and `deploy` (`deploy.yml`)
4. Deploy verification: MCP protocol check against the deployed URL. A
   2026-07-28 `server/discover` must list `2026-07-28` in `supportedVersions`,
   then a `tools/call` of `search` must return a result. Up to 3 attempts.

`deploy.yml` is a reusable workflow (`workflow_call` + `workflow_dispatch`) holding
the single copy of deploy + verify. The release path (`release-please.yml`) calls it
via `uses:`. The deploy job declares `environment: production`, so each deploy is
recorded under the repo Deployments/Environments view. It runs only in
`joshrotenberg/hexpm-mcp` and needs the `FLY_API_TOKEN` secret; `publish-hex`
needs `HEX_API_KEY`.

Manual deploy: `gh workflow run deploy.yml` (workflow_dispatch; the `url` input
overrides the verification URL)

## Packaging (Burrito + tinfoil)

Tagged releases also publish self-contained binaries for macOS, Linux, and
Windows via `.github/workflows/release.yml`, generated by `mix tinfoil.generate`
from the `:tinfoil` key in mix.exs.

There is exactly one release entry, `hexpm_mcp`, shared by the Fly image and the
binaries. `Tinfoil.Build` runs `mix release` with no name and reads
`burrito_out/<app>_<target>`, so a second release entry would break both. The
Burrito wrap step is therefore gated by `burrito_build?/0`:

- `mix tinfoil.build --target x` or `BURRITO_TARGET=x mix release` -> wrapped
- plain `mix release` (the Dockerfile) -> assembled, no Zig needed

`BURRITO_TARGET` alone is not enough, because mix.exs is evaluated before any
task runs and `tinfoil.build` sets the var in-process. Hence the argv check.

Argument parsing lives in `HexpmMcp.CLI` (Cheer). `HexpmMcp.Application.start/2`
is the real entry point in every mode: Burrito boots the BEAM and never calls a
`main/1`. `System.argv/0` is empty inside a wrapped binary, so argv comes from
`Cheer.argv/0`. The command tree is `parse_only`, consumed via `Cheer.parse/3`,
which validates argv without dispatching a handler. `{:serve, opts}` builds the
supervision tree; `{:init, args}` runs `HexpmMcp.Init.run/1` and halts before
any child starts. With no `--transport`, a standalone binary defaults to stdio
and everything else to http.

All five targets are built on `ubuntu-latest`. darwin is cross-compiled: Zig only
uses the host SDK when linking natively, and Zig 0.15.2 cannot link against the
macOS 26 SDK that `macos-latest` now runs. Because `extra_targets` may not shadow
a builtin name, the darwin entries are `darwin_arm64_cross` /
`darwin_x86_64_cross`; the triples are unchanged so asset names match a native
build.

`release-please.yml` calls `release.yml` directly via `workflow_call`, alongside
`publish-hex` and `deploy`. It cannot be event-triggered: release-please creates
the tag and the release with the default `GITHUB_TOKEN`, and GitHub does not start
workflow runs from events that token creates, so `on: push: tags` and
`on: release: [published]` both sit idle. The caller must also grant
`id-token: write` and `attestations: write`, or the whole file is rejected at
startup with only "workflow file issue" as a diagnostic. `release.yml` also has
a `workflow_dispatch` trigger with a required `tag` input, for rebuilding one
release's binaries.

### Gotchas

- **Burrito caches the unpacked payload by app version**, and `tinfoil.build`
  forces `MIX_ENV=prod`, where Burrito does not re-extract. Rebuilding without
  bumping the version silently runs stale code. Clear it with
  `rm -rf "$(./burrito_out/hexpm_mcp_<target> maintenance directory)"`. The
  first run of a newer version deletes older payloads and says so on stderr
  (`Uninstalled older version (v0.3.6)`), so stdio stays clean.
- **Burrito is held at `~> 1.5.0`.** 1.6.0 boots via `-s elixir start_cli` as
  separate argv tokens, which actually invokes Elixir's CLI; it then claims
  `--version` and `--help` and treats the first remaining argument as a script
  path (`No file named --transport`). 1.5.0 passed `"-s elixir start_cli"` as a
  single token, so Elixir's CLI never ran and plain args reached the app.
  Upstream fix proposed in burrito-elixir/burrito#230 (adds `--no-halt --` after
  `-extra`); 1.6.x also halts the VM after boot, which kills long-running apps.
  If that lands, unpin and the darwin cross-compile becomes optional.
- **The release OTP is pinned exactly** (`otp_version: "28.5.0.6"` in the
  `:tinfoil` ci config). Burrito downloads a prebuilt ERTS for the build host's
  OTP, and its CDN lags OTP patch releases: `"28"` resolved to 28.5.0.7, which
  had no Burrito build, and v0.3.8 shipped without binaries. Move it only to a
  version the CDN has for every target.
- **Zig 0.15.2 cannot link against the macOS 26 SDK.** That is both this dev host
  and `macos-latest`, so darwin binaries cannot be built natively anywhere right
  now. Building in Linux works, which is what CI does. To build one locally, use
  the Docker route rather than the host toolchain.
- **`scripts/install.sh` carries hand-edits** and `mix tinfoil.generate` will
  revert them: an escaped tilde so the default `~/.local/bin` expands (without it
  `mkdir` fails on `$HOME~`), and an ASCII dash in the header. Tracked as
  joshrotenberg/tinfoil#120 and #122.
- **The binaries are unsigned and un-notarized.** A browser download carries
  `com.apple.quarantine` and macOS refuses it; `curl` does not set the attribute,
  so the installer is unaffected. See the README section and
  joshrotenberg/tinfoil#119.

## Plugin and init

`priv/plugin/hexpm` is one plugin directory serving both Claude Code and Codex,
in timon's layout. `hexpm_mcp init` (`HexpmMcp.Init`) installs it, modeled on
`due init` and `canale init`: it writes a local marketplace and registers it
through each host's own CLI. It never edits a host's configuration files.

- The tree is embedded at compile time: `@external_resource` per file, and
  `__mix_recompile__?/0` compares the file listing so an added or removed file
  recompiles too. The binary does not depend on how a release copies the
  dot-directories in `priv/`.
- The committed manifests carry no `version`. init writes the application
  version into both installed manifests and the Claude marketplace entry.
- The skill names tools in backticks, and `plugin_test.exs` fails if one is not
  served. It tells agents that `audit_mix_deps` counts advisories for every
  version; drop that caveat when #98 is fixed.
- The hook is `sh` and `grep` only, and prints nothing for files other than
  `mix.exs` and `mix.lock`.

What init does, in order:

1. Plan. Install dir: `--install-dir`, else `$XDG_DATA_HOME/hexpm_mcp` (ignored
   when relative), else `~/.local/share/hexpm_mcp`. A non-empty directory
   without `.hexpm-mcp-install.json` is refused. Binary: `--binary`, else
   `Burrito.Util.Args.get_bin_path/0`, the launcher's `__BURRITO_BIN_PATH`
   (the outer binary, not the version-keyed payload); under mix without
   `--binary` init refuses. Hosts: `--host both` (the default) takes whichever
   of `claude` and `codex` is on PATH; a host named with `--host` must exist.
2. `--dry-run` stops here: nothing written, no host process started.
3. Write the marker first, then the plugin tree (cleared first, so files a newer
   release drops go too), `plugins/hexpm/.mcp.json` pointing at
   `<dir>/bin/hexpm_mcp --transport stdio`, and both marketplace files. The
   binary is copied through a temp file and rename, so a running server keeps
   its inode.
4. Register:

   | Host | Steps |
   |---|---|
   | claude | `plugin marketplace list --json`; `plugin marketplace add <dir> --scope user` unless registered there, otherwise `plugin marketplace update hexpm-local`; `plugin list --json`; `plugin install hexpm@hexpm-local --scope user`, or `plugin update` when installed |
   | codex | `plugin marketplace list --json`; `plugin marketplace add <dir>` unless registered; `plugin add hexpm@hexpm-local` |

   A `hexpm-local` marketplace registered at another path stops the run, as
   does the first failing step. Earlier steps stay applied.
5. Report MCP servers that look like a hand-configured hexpm entry, from
   `claude mcp list` and `codex mcp list --json`. Report only.

### Gotchas

- **The root command sets `args_conflicts_with_subcommands(true)`.** Cheer
  prints help when a command with subcommands gets none, which would stop
  `hexpm_mcp --transport stdio` from serving.
- **`claude mcp list` has no JSON form and health-checks every server**, about
  5s on this host, so init calls it once, after installing. It prints indented
  warnings under a server defined at more than one scope (`├ Server "hexpm" is
  defined in multiple scopes ...`). The parser takes a name of word characters,
  dots, `@`, dashes and spaces only, so those lines and `plugin:<p>:<s>` entries
  never match.
- **Codex lists a plugin's MCP server under its plain name** (`hexpm`) in
  `codex mcp list`, so the duplicate report drops entries whose target is the
  installed binary.
- **Claude Code keeps an uninstalled plugin's cache** in
  `~/.claude/plugins/cache/hexpm-local`, marked `.orphaned_at`, and removes it
  later on its own.
- **Testing init live.** A darwin Burrito binary cannot be built on this host
  (see Packaging), so run init from a checkout against a released binary:
  `mix run -- init --dry-run --binary /path/to/hexpm_mcp`. A run without
  `--dry-run` changes the user's Claude Code and Codex configuration. Remove it
  with `claude plugin uninstall hexpm@hexpm-local --scope user`,
  `claude plugin marketplace remove hexpm-local`,
  `codex plugin remove hexpm@hexpm-local` and
  `codex plugin marketplace remove hexpm-local`.

## Dependencies

- `snodo` ~> 0.4.3 (Hex, via `snodo_dep/3`) -- MCP server framework. Held to
  one minor version because snodo minors carry breaking changes before 1.0.
- `snodo_jsv` ~> 0.4.3 (Hex, via `snodo_dep/3`, optional) -- JSV-backed JSON
  Schema validation for tool arguments
- `req` ~> 0.6 -- HTTP client
- `floki` ~> 0.37 -- HTML parsing
- `jason` ~> 1.4 -- JSON
- `cheer` ~> 0.2.1 -- CLI framework (argv parsing, help, version)
- `burrito` ~> 1.5.0 (optional) -- single-binary packaging
- `tinfoil` ~> 0.2.22 (runtime: false) -- release workflow generation
- `bypass` + `excoveralls` -- test only
- `credo` + `dialyxir` + `ex_doc` -- dev/test tooling

Local checkouts: `SNODO_PATH` (snodo and snodo_jsv), `CHEER_PATH`, and
`TINFOIL_PATH` each replace the Hex requirement with a path dependency.

## Reference

- hex.pm API spec: https://github.com/hexpm/specifications
- snodo: https://hex.pm/packages/snodo, source https://github.com/joshrotenberg/snodo
- OSV.dev API: https://osv.dev/docs/
- Elixir Toolbox API: https://elixir-toolbox.dev/api (OpenAPI: /api/openapi)
- cratesio-mcp (Rust sibling): ~/Code/github.com/joshrotenberg/cratesio-mcp
