defmodule HexpmMcp.AuditWorkflow do
  @moduledoc """
  Opt-in, single-host durable package audits. Nothing here is started or migrated
  by `HexpmMcp.Application`; the ordinary 24-tool server is unchanged.

  Call `start_repo/1`, explicitly `migrate!/0` once during provisioning, then
  `store/0`, `start_runner/2` and `runtime/2`. The caller owns and supervises the
  returned processes. Stop the runner before stopping its Repo. Restarting both
  against the same WAL SQLite file recovers unfinished, unexpired work at least
  once, with its original task ID and exact package/version descriptor.

  The transport must supply trusted `context.auth = %{"tenant" => nonempty_string}`.
  Request arguments and `_meta` cannot select a tenant. This is tenant isolation,
  not authentication: an application must authenticate before constructing auth.

  A completed task means an advisory report was produced, not that a package is
  safe. The report persists observations and their collection window, source
  descriptions and limitations; it does not preserve raw upstream responses.
  Recovery may observe newer registry/advisory data. Work is read-only and makes
  no publishing or dependency modification calls.

  Subscriptions emit authorized current SQLite snapshots, then changed revisions.
  Intermediate states can coalesce; reconnect returns the latest state, including
  an already-terminal state. This is neither event replay nor durable pubsub.
  Streams finish after every accepted task is terminal, expired or inaccessible.
  Expiry is cleanup-driven: startup drains expired rows before recovery, then a
  periodic reaper removes them. This is not an exact-deadline authorization check;
  reads/claims can race expiry between reaper passes. Reports share the one-hour
  creation-based task TTL and are not a permanent audit archive.

  This composition does not supply deployment authentication, per-tenant task
  quotas, a global worker-concurrency limit or raw request admission quotas. The
  32-ID source cap bounds accepted streams, not the Tasks extension's earlier
  filter-authorization reads. Add those application admission controls before
  exposing this opt-in workflow to untrusted workloads. Authenticated HTTP is
  exercised through the optional Plug/Bandit development/test integration; the
  default native listener has no trusted auth injection seam.
  """

  alias HexpmMcp.AuditWorkflow.{Executor, Repo, Source, Store, Tool}
  alias HexpmMcp.MCP.Server
  alias Snodo.Extensions.Tasks
  alias Snodo.Extensions.Tasks.Runner
  alias Snodo.Extensions.Tasks.Store, as: TaskStore
  alias Snodo.Extensions.Tasks.Store.SQLite
  alias Snodo.Extensions.Tasks.Store.SQLite.Migration
  alias Snodo.Server.Runtime

  @migration_version 2_026_091_401

  @doc "Starts the application-owned Repo. Requires an explicit file path, not :memory:."
  def start_repo(database) when is_binary(database) and database != ":memory:" do
    Repo.start_link(
      database: Path.expand(database),
      pool_size: 1,
      journal_mode: :wal,
      foreign_keys: :on,
      busy_timeout: 2_000,
      default_transaction_mode: :deferred,
      log: false
    )
  end

  @doc "Explicit provisioning operation; never invoked by startup or runtime/2."
  def migrate!, do: Ecto.Migrator.up(Repo, @migration_version, Migration, log: false)

  @doc "Builds an authenticated store reference and verifies the installed schema."
  def store do
    config = SQLite.new!(repo: Repo, scope: &Store.scope/1, timeout: 2_000)
    :ok = SQLite.check_schema(config)
    {Store, config}
  end

  @doc "Starts a recoverable runner. Options are explicit application-owned runner policy."
  def start_runner(store, opts \\ []) do
    opts =
      Keyword.merge(
        [
          executor: {Executor, nil},
          recover: true,
          reap_interval_ms: 1_000,
          lease_ms: 10_000,
          heartbeat_ms: 3_000,
          recovery_interval_ms: 100
        ],
        opts
      )

    with :ok <- reap_expired(store) do
      Runner.start_link(Keyword.put(opts, :store, store))
    end
  end

  @doc "Composes the ordinary server catalog with one explicitly required-task tool."
  def runtime(store, runner) do
    base = Server.runtime()

    Runtime.new(
      router: Snodo.Router.register_tool(base.router, Tool),
      protocols: [Snodo.Protocol.V2026_07_28],
      server_info: Map.put(base.server_info, "name", "hexpm-mcp-durable-audit"),
      capabilities: Map.put(base.capabilities, "extensions", %{Tasks.id() => %{}}),
      schema_validator: base.schema_validator,
      instructions: base.instructions,
      pagination: [page_size: 8],
      discovery_cache: base.discovery_cache,
      tools_cache: base.tools_cache,
      prompts_cache: base.prompts_cache,
      resources_cache: base.resources_cache,
      extensions: [
        {Tasks,
         store: store,
         runner: runner,
         task_support: %{Tool.name() => &Tool.task_policy/2},
         ttl_ms: 3_600_000,
         poll_interval_ms: 100}
      ],
      subscription_source: {Source, %{store: store, poll_interval_ms: 100}}
    )
  end

  defp reap_expired(store) do
    case TaskStore.reap(store) do
      {:ok, []} -> :ok
      {:ok, [_id | _remaining]} -> reap_expired(store)
      {:error, _reason} = error -> error
    end
  end
end
