# Opt-in durable package audits

`HexpmMcp.AuditWorkflow` composes the existing application with SQLite-backed
Tasks and task-status subscriptions. The normal application still starts without
a Repo, migrations or a Tasks runner and retains its 24-tool catalog. Only the
explicit workflow runtime adds `durable_package_audit` (25 tools), preserving
the existing six prompts, resources, completion handlers and eight-item pages.

## Offline walkthrough

From the application checkout:

```sh
ERL_FLAGS='+S 4:4' mix run --no-start examples/durable_package_audit.exs --check
```

Omit `--check` to print the resulting advisory report. The example seeds a
fictional release with no dependencies and calls the real
`HexpmMcp.audit_dependencies/2` domain path. All service URLs point to loopback
port 1, so an accidental cache miss cannot contact public Hex, HexDocs, Toolbox
or OSV services. This does not make claims about any real package's security.

An example-owned executor pauses **after computing the report but before storing
the terminal result**. The walkthrough stops the worker/runner and Repo, opens
the same SQLite file, recovers the original descriptor, recomputes the report,
and observes working/completed status notifications. Reconnecting yields the
current completed status. The temporary database is removed after verification.
This tests a runner/Repo process restart, not an operating-system crash or full
VM power loss.

## Explicit application composition

The public facade never starts itself. Provision a local writable database
directory and explicitly own or supervise the Repo and runner:

```elixir
alias HexpmMcp.AuditWorkflow

{:ok, repo} = AuditWorkflow.start_repo("/absolute/existing/directory/audit.sqlite3")

# Provisioning step, not a request or implicit boot-time migration.
migration = AuditWorkflow.migrate!()
true = migration in [:ok, :already_up]

store = AuditWorkflow.store()
{:ok, runner} = AuditWorkflow.start_runner(store)
runtime = AuditWorkflow.runtime(store, runner)

# Pass runtime to an application-owned authenticated transport.
# Stop runner before repo on a planned shutdown.
```

`start_repo/1` starts the named `HexpmMcp.AuditWorkflow.Repo` with a single
connection, WAL, foreign keys and a bounded busy timeout. `store/0` verifies the
Tasks migration and constructs the tenant-scoped adapter. `start_runner/2`
accepts explicit runner options; defaults enable recovery, a ten-second lease,
three-second heartbeat and one-second reaping. Startup drains expired task rows
before starting recovery. Migrations and all of these lifecycle calls belong to
the application, not the protocol core or default server startup.

This is single-host file-backed SQLite, not a distributed queue or a shared
network-filesystem deployment. Preserve the SQLite database and its WAL correctly
when backing up. Abrupt loss of a live runner may require lease expiry before a
new runner can recover its work. Recovery is at least once: the descriptor's
task/idempotency key remains stable but its upstream observations may change.
The supplied executor only reads registry/advisory data; it does not publish,
install, upgrade or modify dependencies.

## Request and authentication contract

The client must use the current protocol and advertise
`io.modelcontextprotocol/tasks` in its extension capabilities. The tool requires
exactly `name` and `version`, for example:

```json
{"name":"durable_package_audit","arguments":{"name":"jason","version":"1.4.5"}}
```

Names are bounded Hex package names; versions must parse as exact semantic
versions, not `latest` or requirements such as `~> 1.4`. The public tool schema
and application admission/executor all validate input. Invalid requests cannot
create a persisted descriptor before validation. Clients without Tasks support
receive the extension's missing-capability error.

Every workflow request needs trusted auth shaped as
`%{"tenant" => "verified-tenant-id"}` in `MCP.Context.auth`. Missing or blank
tenants are rejected. Tool arguments, JSON `_meta` and unchecked headers never
select a tenant. Get, update, cancellation and subscription reads use the same
store authorization boundary; another tenant cannot read or cancel the task.
This isolates tenants, not separate principals within the same tenant.

Authenticated HTTP acceptance uses the optional `mcp_ex_plug` integration with
Bandit. A test-owned authentication Plug verifies an ephemeral bearer credential,
then sets `Plug.Conn.assign(conn, :mcp_auth, %{"tenant" => verified_tenant})`
before calling `MCP.Transport.Plug`. It checks unauthenticated rejection,
cross-tenant denial, real SSE delivery and disconnect cleanup. Those Plug and
Bandit dependencies are currently **development/test only**; this is not a
production authentication policy, OAuth implementation or default HTTP-server
switch. A deployment choosing Plug must explicitly include/runtime-configure
the integration and its real authentication and authorization policy. The
default native HTTP/stdio bindings do not currently inject trusted tenant auth.

Before exposing this workflow to untrusted workloads, add application-owned
per-tenant admission/rate limits, task and storage quotas, and worker-concurrency
limits. The Tasks runner here has no global live-worker quota. Limiting the
ordinary request executor is not a durable-job concurrency limit. The source's
32-ID cap bounds an accepted stream, **not** the extension's earlier
authorization reads over the raw requested filter.

## Status streams and report retention

Creation returns a task ID. `tasks/get` is the authoritative report/status read.
To observe that task, call `subscriptions/listen` with
`{"notifications":{"taskIds":["task-id"]}}`.

The application source accepts up to 32 IDs and derives events from freshly
authorized SQLite snapshots, emitting the initial snapshot and then changed
revisions. It keeps one pending pull, no accumulating event queue, and does not
poll while the transport is applying backpressure. Separate callback processes
per pull are supported. It does not use instrumentation as guaranteed pubsub.

Intermediate transitions may coalesce. Opening a stream after completion still
returns the current completed snapshot. A disconnected/reconnecting client must
treat this as current-state observation, not event replay or exactly-once
delivery. Streams finish after every accepted task becomes terminal or is
removed/inaccessible. Cancelling a subscription stops its source; it does not
cancel the durable task. Use `tasks/cancel` for that. Portable Plug detects stream
disconnects on writes/keepalives, so cleanup latency follows that policy.

Tasks and reports use a **one-hour creation-based TTL**, not permanent archival
storage. Expiry is cleanup-driven. The startup/periodic reaper removes expired
aggregates, after which active streams finish and lookups report unknown tasks.
The current SQLite adapter does not enforce expiry at every get/claim, so an
exact expiry boundary can race a reaper pass. Do not use the TTL as an
exact-deadline authorization guarantee. A production audit archive needs its own
retention/export policy.

## What a completed audit means

Completion means the domain function produced a report, **not** that the package
is safe. The persisted JSON report includes the exact requested release, stable
idempotency key, collection start/end times, observed issue summaries, source
descriptions and explicit limitations:

- Only direct dependency names are checked; no resolved lockfile graph is audited.
- OSV queries are package-name based, not matched to installed dependency versions.
- Existing domain behavior can turn unavailable owners/OSV data into no warning.
- Registry data may be cached. Raw upstream responses and advisory IDs are not retained.
- Observations are not an atomic upstream snapshot, and recovery can observe newer data.

Warnings, including known vulnerabilities, are successful report contents rather
than task failures. Failure means the report could not be produced. Production
decisions should review these limitations and the underlying sources.

## Deterministic acceptance

```sh
ERL_FLAGS='+S 4:4' MIX_ENV=test mix test test/audit_workflow_test.exs
```

The tests exercise the real audit path against loopback Hex/OSV stubs containing
a single-maintainer warning and a fictional vulnerability. They cover exact
admission, stable recovery across repeated Repo opens, persisted final results,
tenant isolation, task cancellation, source close/rotating callers, expiry
cleanup, initial/terminal/reconnect statuses, and authenticated HTTP/SSE through
Plug/Bandit. They do not query or certify public packages.
