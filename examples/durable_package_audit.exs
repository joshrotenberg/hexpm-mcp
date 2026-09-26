# Run from hexpm-mcp, with no public network access:
#   ERL_FLAGS='+S 4:4' mix run --no-start examples/durable_package_audit.exs [--check]
#
# Explicitly starts/migrates an application-owned SQLite Repo and task runner.
# A fixture-only executor pauses after the real domain audit, before committing
# its report. Stopping/reopening Repo+runner recovers the immutable descriptor.
# This is a process/Repo restart demonstration, not a full VM power-loss test.
# The temporary database is removed after verifying the persisted final report.

Application.put_env(:hexpm_mcp, :transport, :none)
Application.put_env(:hexpm_mcp, :cache_ttl, 3_600)

for service <- [:hex_api_url, :hexdocs_url, :toolbox_url, :osv_url] do
  Application.put_env(:hexpm_mcp, service, "http://127.0.0.1:1")
end

{:ok, _applications} = Application.ensure_all_started(:hexpm_mcp)

defmodule DurablePackageAuditExample.Executor do
  @moduledoc false
  @behaviour Snodo.Extensions.Tasks.WorkExecutor

  @impl true
  def execute(work, cancellation, owner) do
    result = HexpmMcp.AuditWorkflow.Executor.execute(work, cancellation, nil)
    send(owner, {:report_ready, work, self()})

    receive do
      :commit -> result
    after
      10_000 -> raise "example did not finish or restart the pending report"
    end
  end
end

defmodule DurablePackageAuditExample do
  @moduledoc false

  alias HexpmMcp.AuditWorkflow
  alias HexpmMcp.AuditWorkflow.Repo
  alias Snodo.Extensions.Tasks
  alias Snodo.Extensions.Tasks.Work
  alias Snodo.Subscription

  def run(mode) do
    directory =
      Path.join(System.tmp_dir!(), "hexpm-durable-example-#{System.unique_integer([:positive])}")

    File.mkdir!(directory)
    database = Path.join(directory, "audit.sqlite3")

    # A seeded, fictional release with no dependencies exercises the real
    # audit_dependencies/2 path without calling Hex or OSV. Richer dependency and
    # vulnerability fixtures are covered with local HTTP stubs in the tests.
    release = %HexpmMcp.Types.Release{version: "1.0.0", requirements: %{}}
    :ok = HexpmMcp.Cache.put({:release, "offline_example", "1.0.0"}, {:ok, release})

    try do
      first_repo = open_repo(database)
      :ok = AuditWorkflow.migrate!()
      first_store = AuditWorkflow.store()
      first_runner = open_runner(first_store)
      runtime = AuditWorkflow.runtime(first_store, first_runner)

      {:ok, %{"result" => %{"resultType" => "task", "taskId" => id}}} =
        dispatch(runtime, "tools/call", %{
          "name" => "durable_package_audit",
          "arguments" => %{"name" => "offline_example", "version" => "1.0.0"}
        })

      {original, first_worker} = ready()
      {subscription, puller, monitor} = listen(runtime, id)
      "working" = status(subscription, puller)
      close(subscription, puller, monitor)
      ref = Process.monitor(first_worker)
      GenServer.stop(first_runner)

      receive do
        {:DOWN, ^ref, :process, ^first_worker, _reason} -> :ok
      after
        2_000 -> raise "old task worker survived runner shutdown"
      end

      GenServer.stop(first_repo)

      open_repo(database)
      store = AuditWorkflow.store()
      runner = open_runner(store)
      recovered_runtime = AuditWorkflow.runtime(store, runner)
      {recovered, second_worker} = ready()
      true = Work.to_map(original) == Work.to_map(recovered)
      ^id = recovered.idempotency_key
      {stream, worker, ref} = listen(recovered_runtime, id)
      "working" = status(stream, worker)
      send(second_worker, :commit)
      "completed" = status(stream, worker)
      :ok = Subscription.continue(worker)

      receive do
        {:mcp_subscription, ^worker, :closed} -> :ok
      after
        2_000 -> raise "terminal stream did not close"
      end

      close(stream, worker, ref)

      {:ok, %{"result" => %{"status" => "completed", "result" => result}}} =
        dispatch(recovered_runtime, "tasks/get", %{"taskId" => id})

      %{"idempotencyKey" => ^id, "observations" => %{"total_checked" => 0}} =
        result["structuredContent"]

      true = result["structuredContent"]["limitations"] != []

      # Reconnect re-emits the current terminal status, not historical events.
      {reconnected, final_worker, final_ref} = listen(recovered_runtime, id)
      "completed" = status(reconnected, final_worker)
      close(reconnected, final_worker, final_ref)

      case mode do
        :check ->
          IO.puts(
            "durable_package_audit: ok (offline, SQLite recovery, working/completed/reconnect)"
          )

        :walkthrough ->
          IO.puts(Jason.encode!(result["structuredContent"], pretty: true))
      end
    after
      stop(Process.whereis(DurablePackageAuditExample.Runner))
      stop(Process.whereis(Repo))
      File.rm_rf!(directory)
    end
  end

  defp open_repo(database) do
    {:ok, repo} = AuditWorkflow.start_repo(database)
    Process.unlink(repo)
    repo
  end

  defp open_runner(store) do
    {:ok, runner} =
      AuditWorkflow.start_runner(store,
        name: DurablePackageAuditExample.Runner,
        executor: {DurablePackageAuditExample.Executor, self()}
      )

    Process.unlink(runner)
    runner
  end

  defp ready do
    receive do
      {:report_ready, work, worker} -> {work, worker}
    after
      3_000 -> raise "durable domain execution did not produce the offline report"
    end
  end

  defp dispatch(runtime, method, params) do
    Snodo.Test.dispatch(runtime,
      protocol: "2026-07-28",
      method: method,
      params: params,
      client_capabilities: %{"extensions" => %{Tasks.id() => %{}}},
      transport_metadata: %{auth: %{"tenant" => "offline-example-tenant"}}
    )
  end

  defp listen(runtime, id) do
    {:stream, subscription} =
      dispatch(runtime, "subscriptions/listen", %{"notifications" => %{"taskIds" => [id]}})

    {:ok, %{"method" => "notifications/subscriptions/acknowledged"}} =
      Subscription.acknowledgement(subscription)

    {worker, monitor} = Subscription.start_worker(subscription, self())
    {subscription, worker, monitor}
  end

  defp status(subscription, worker) do
    :ok = Subscription.continue(worker)

    receive do
      {:mcp_subscription, ^worker, {:ok, event}} ->
        {:ok, %{"method" => "notifications/tasks", "params" => params}} =
          Subscription.notification(subscription, event)

        params["status"]
    after
      3_000 -> raise "status subscription produced no event"
    end
  end

  defp close(subscription, worker, monitor) do
    :ok = Subscription.close(subscription, :complete)
    :ok = Subscription.stop_worker(worker, monitor)
  end

  defp stop(nil), do: :ok
  defp stop(pid), do: if(Process.alive?(pid), do: GenServer.stop(pid))
end

case System.argv() do
  [] -> DurablePackageAuditExample.run(:walkthrough)
  ["--check"] -> DurablePackageAuditExample.run(:check)
  _other -> raise "usage: mix run --no-start examples/durable_package_audit.exs [--check]"
end
