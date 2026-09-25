defmodule HexpmMcp.AuditWorkflowTest.ObservedExecutor do
  @moduledoc false
  @behaviour MCP.Extensions.Tasks.WorkExecutor
  alias HexpmMcp.AuditWorkflow.Executor

  @impl true
  def execute(work, cancellation, owner) do
    send(owner, {:audit_worker, work, self()})
    result = Executor.execute(work, cancellation, nil)
    send(owner, {:audit_ready, self()})

    receive do
      :commit -> result
    after
      5_000 -> raise "test did not release the computed report"
    end
  end
end

defmodule HexpmMcp.AuditWorkflowTest.Endpoint do
  @moduledoc false
  @behaviour Plug
  alias MCP.Transport.Plug, as: MCPPlug
  alias Plug.Conn

  @impl true
  def init(opts) do
    {tokens, opts} = Keyword.pop!(opts, :tokens)
    {tokens, MCPPlug.init(opts)}
  end

  @impl true
  def call(conn, {tokens, transport}) do
    with ["Bearer " <> supplied] <- Conn.get_req_header(conn, "authorization"),
         {_, tenant} <-
           Enum.find(tokens, fn {token, _tenant} ->
             Plug.Crypto.secure_compare(token, supplied)
           end) do
      conn
      |> Conn.assign(:mcp_auth, %{"tenant" => tenant})
      |> MCPPlug.call(transport)
    else
      _unauthenticated -> conn |> Conn.send_resp(401, "") |> Conn.halt()
    end
  end
end

defmodule HexpmMcp.AuditWorkflowTest.TrackedSource do
  @moduledoc false
  @behaviour MCP.Subscription.Source
  alias HexpmMcp.AuditWorkflow.Source

  @impl true
  def open(filter, context, options) do
    with {:ok, accepted, handle} <- Source.open(filter, context, options) do
      send(options.observer, {:audit_source, handle})
      {:ok, accepted, handle}
    end
  end

  @impl true
  defdelegate next(handle, options), to: Source
  @impl true
  defdelegate close(handle, reason, options), to: Source
end

defmodule HexpmMcp.AuditWorkflowTest do
  use ExUnit.Case, async: false

  import HexpmMcp.Test.Fixtures

  alias HexpmMcp.AuditWorkflow
  alias HexpmMcp.AuditWorkflow.{Executor, Repo, Source, Tool}
  alias HexpmMcp.AuditWorkflowTest.ObservedExecutor
  alias HexpmMcp.MCP.Server
  alias MCP.Extensions.Tasks
  alias MCP.Extensions.Tasks.Store
  alias MCP.Extensions.Tasks.Work
  alias MCP.Protocol.V2026_07_28
  alias MCP.Subscription

  setup do
    directory = Path.join(System.tmp_dir!(), "hexpm-audit-#{System.unique_integer([:positive])}")
    File.mkdir!(directory)
    database = Path.join(directory, "audit.sqlite3")
    old_env = Application.get_all_env(:hexpm_mcp)
    bypass = Bypass.open()
    Application.put_env(:hexpm_mcp, :hex_api_url, "http://localhost:#{bypass.port}")
    Application.put_env(:hexpm_mcp, :osv_url, "http://localhost:#{bypass.port}/osv")
    Application.put_env(:hexpm_mcp, :rate_limit_ms, 0)
    Application.put_env(:hexpm_mcp, :cache_ttl, 0)
    HexpmMcp.Cache.clear()

    on_exit(fn ->
      stop(Process.whereis(Repo))
      HexpmMcp.Cache.clear()

      for key <- [:hex_api_url, :osv_url, :rate_limit_ms, :cache_ttl] do
        case Keyword.fetch(old_env, key) do
          {:ok, value} -> Application.put_env(:hexpm_mcp, key, value)
          :error -> Application.delete_env(:hexpm_mcp, key)
        end
      end

      File.rm_rf!(directory)
    end)

    repo = open_repo(database)
    assert AuditWorkflow.migrate!() == :ok
    {:ok, database: database, repo: repo, store: AuditWorkflow.store(), bypass: bypass}
  end

  test "default catalog/startup stay unchanged and explicit runtime preserves application features",
       ctx do
    runner = runner(ctx.store)
    base = Server.runtime()
    runtime = AuditWorkflow.runtime(ctx.store, runner)
    assert map_size(base.router.tools) == 24
    refute Map.has_key?(base.router.tools, Tool.name())
    refute Map.has_key?(base.capabilities, "extensions")
    assert map_size(runtime.router.tools) == 25
    assert runtime.router.prompts == base.router.prompts
    assert map_size(runtime.router.prompts) == 6
    assert runtime.router.resources == base.router.resources
    assert runtime.pagination == base.pagination
    assert runtime.schema_validator == base.schema_validator

    children = Supervisor.which_children(HexpmMcp.Supervisor)
    refute Enum.any?(children, fn {id, _, _, _} -> id == Repo end)
  end

  test "invalid arguments and forged tenant metadata never create a durable descriptor", ctx do
    runtime = AuditWorkflow.runtime(ctx.store, runner(ctx.store))

    for args <- [
          %{},
          %{"name" => "jason"},
          %{"name" => "../jason", "version" => "1.0.0"},
          %{"name" => "jason\n", "version" => "1.0.0"},
          %{"name" => "jason", "version" => "latest"},
          %{"name" => "jason", "version" => "~> 1.0"},
          %{"name" => "jason", "version" => 1},
          %{"name" => "jason", "version" => "1.0.0", "tenant" => "other"}
        ] do
      assert {:ok, %{"error" => %{"code" => -32_602}}} =
               dispatch(runtime, "tools/call", %{"name" => Tool.name(), "arguments" => args})
    end

    for auth <- [nil, %{}, %{"tenant" => ""}, %{"tenant" => " "}] do
      assert {:ok, %{"error" => %{"code" => -32_003}}} =
               dispatch(runtime, "tools/call", call_params(%{"tenant" => "forged"}), auth)
    end

    assert :empty = Store.claim_next(ctx.store, "admission-check", 1_000)

    assert {:ok, %{"error" => %{"code" => -32_021}}} =
             MCP.Test.dispatch(runtime,
               protocol: "2026-07-28",
               method: "tools/call",
               params: call_params(),
               transport_metadata: %{auth: %{"tenant" => "team-a"}}
             )
  end

  test "real domain report persists warnings and streams initial plus terminal snapshots", ctx do
    owner = self()
    expect_domain(ctx.bypass, owner)
    runtime = AuditWorkflow.runtime(ctx.store, runner(ctx.store))
    id = create(runtime)
    assert_receive {:release_request, release_worker}, 2_000
    {subscription, puller, monitor} = listen(runtime, id)
    assert notification(subscription, puller)["status"] == "working"
    :ok = Subscription.continue(puller)
    send(release_worker, :respond)
    event = receive_event(puller)
    {:ok, notice} = Subscription.notification(subscription, event)
    assert notice["method"] == "notifications/tasks"
    assert notice["params"]["status"] == "completed"
    assert notice["params"]["taskId"] == id
    :ok = Subscription.continue(puller)
    assert_receive {:mcp_subscription, ^puller, :closed}, 2_000
    close(subscription, puller, monitor)

    report = get_report(runtime, id)
    assert report["requestedRelease"] == %{"name" => "audit_target", "version" => "1.0.0"}
    assert report["idempotencyKey"] == id
    assert report["observations"]["total_checked"] == 1
    assert report["observations"]["total_warnings"] == 2
    assert [%{"name" => "audit_dep", "issues" => issues}] = report["observations"]["results"]
    assert "single maintainer" in issues
    assert "1 known vulnerability(ies)" in issues
    assert length(report["limitations"]) >= 6
    assert Enum.any?(report["limitations"], &String.contains?(&1, "not a safe-package verdict"))
    assert {:ok, _, _} = DateTime.from_iso8601(report["collectionFinishedAt"])

    # A new stream gets the authoritative completed snapshot without replaying working.
    {reconnected, worker, ref} = listen(runtime, id)
    assert notification(reconnected, worker)["status"] == "completed"
    :ok = Subscription.continue(worker)
    assert_receive {:mcp_subscription, ^worker, :closed}, 2_000
    close(reconnected, worker, ref)
  end

  test "Repo and runner restart recover original exact work and persist a completed report",
       ctx do
    expect_domain(ctx.bypass, self(), :auto)
    first_runner = runner(ctx.store, executor: {ObservedExecutor, self()})
    first_runtime = AuditWorkflow.runtime(ctx.store, first_runner)
    id = create(first_runtime)
    assert_receive {:audit_worker, first_work, first_worker}, 2_000
    assert_receive {:audit_ready, ^first_worker}, 2_000
    worker_monitor = Process.monitor(first_worker)
    {:ok, access} = Store.authorize(ctx.store, context("team-a"), {:get, id})
    {:ok, before_restart} = Store.get(ctx.store, id, access)
    assert before_restart.task.status == :working
    stop(first_runner)
    assert_receive {:DOWN, ^worker_monitor, :process, ^first_worker, _reason}, 2_000
    stop(ctx.repo)

    open_repo(ctx.database)
    store = AuditWorkflow.store()
    second_runner = runner(store, executor: {ObservedExecutor, self()})
    runtime = AuditWorkflow.runtime(store, second_runner)
    assert_receive {:audit_worker, recovered_work, second_worker}, 2_000
    assert Work.to_map(recovered_work) == Work.to_map(first_work)
    assert recovered_work.idempotency_key == id
    assert_receive {:audit_ready, ^second_worker}, 2_000
    {subscription, puller, monitor} = listen(runtime, id)
    assert notification(subscription, puller)["status"] == "working"
    :ok = Subscription.continue(puller)
    send(second_worker, :commit)
    event = receive_event(puller)
    {:ok, notice} = Subscription.notification(subscription, event)
    assert notice["params"]["status"] == "completed"
    close(subscription, puller, monitor)
    report = get_report(runtime, id)
    stop(second_runner)
    stop(Process.whereis(Repo))

    open_repo(ctx.database)
    reopened_store = AuditWorkflow.store()
    {:ok, access} = Store.authorize(reopened_store, context("team-a"), {:get, id})
    assert {:ok, snapshot} = Store.get(reopened_store, id, access)
    assert snapshot.task.status == :completed
    assert snapshot.task.result["structuredContent"] == report
    assert :empty = Store.claim_next(reopened_store, "terminal-not-recoverable", 1_000)
  end

  test "tenant scope excludes get, cancel, direct source reads and forged metadata", ctx do
    expect_domain(ctx.bypass, self())
    runtime = AuditWorkflow.runtime(ctx.store, runner(ctx.store))
    id = create(runtime)
    assert_receive {:release_request, request}, 2_000

    for method <- ["tasks/get", "tasks/cancel"] do
      assert {:ok, %{"error" => error}} =
               dispatch(runtime, method, %{"taskId" => id, "_meta" => %{"tenant" => "team-a"}}, %{
                 "tenant" => "team-b"
               })

      assert error["code"] == -32_602
    end

    source_opts = %{store: ctx.store, poll_interval_ms: 10}
    assert {:ok, _, handle} = Source.open(%{"taskIds" => [id]}, context("team-b"), source_opts)
    assert :closed = Source.next(handle, source_opts)
    assert {:error, :unauthorized} = Store.authorize(ctx.store, context(nil), {:get, id})
    send(request, :respond)
    {subscription, puller, monitor} = listen(runtime, id)
    terminal_status(subscription, puller)
    close(subscription, puller, monitor)
  end

  test "task cancellation stops the real worker and emits a terminal cancelled snapshot", ctx do
    expect_domain(ctx.bypass, self(), :auto)

    runtime =
      AuditWorkflow.runtime(ctx.store, runner(ctx.store, executor: {ObservedExecutor, self()}))

    id = create(runtime)
    assert_receive {:audit_worker, _work, worker}, 2_000
    ref = Process.monitor(worker)
    assert_receive {:audit_ready, ^worker}, 2_000
    {subscription, puller, monitor} = listen(runtime, id)
    assert notification(subscription, puller)["status"] == "working"
    :ok = Subscription.continue(puller)

    assert {:ok, %{"result" => %{"resultType" => "complete"}}} =
             dispatch(runtime, "tasks/cancel", %{"taskId" => id})

    assert_receive {:DOWN, ^ref, :process, ^worker, _reason}, 2_000
    event = receive_event(puller)
    {:ok, notice} = Subscription.notification(subscription, event)
    assert notice["params"]["status"] == "cancelled"
    close(subscription, puller, monitor)
    assert {:ok, %{"result" => result}} = dispatch(runtime, "tasks/get", %{"taskId" => id})
    refute Map.has_key?(result, "result")
  end

  test "source bounds, cancelled blocked pull cleanup and missing snapshot completion", ctx do
    opts = %{store: ctx.store, poll_interval_ms: 10}

    for ids <- [[], Enum.map(1..33, &Integer.to_string/1)] do
      assert {:error, %MCP.Error{code: -32_602}} =
               Source.open(%{"taskIds" => ids}, context("team-a"), opts)
    end

    assert {:ok, _, absent} = Source.open(%{"taskIds" => ["missing"]}, context("team-a"), opts)
    assert :closed = Source.next(absent, opts)

    expect_domain(ctx.bypass, self(), :auto)

    runtime =
      AuditWorkflow.runtime(ctx.store, runner(ctx.store, executor: {ObservedExecutor, self()}))

    id = create(runtime)
    assert_receive {:audit_ready, _worker}, 2_000
    {subscription, puller, monitor} = listen(runtime, id)
    assert notification(subscription, puller)["status"] == "working"
    :ok = Subscription.continue(puller)
    :ok = Subscription.close(subscription, :cancelled)
    assert_receive {:mcp_subscription, ^puller, :closed}, 2_000
    :ok = Subscription.stop_worker(puller, monitor)

    assert {:ok, %{"result" => %{"status" => "working"}}} =
             dispatch(runtime, "tasks/get", %{"taskId" => id})

    dispatch(runtime, "tasks/cancel", %{"taskId" => id})
  end

  test "executor rejects changed descriptor types and cancellation before calling upstream" do
    cancellation = MCP.Cancellation.new()
    work = Work.new!("id", "other", %{})
    assert {:failed, %{"code" => -32_602}, _} = Executor.execute(work, cancellation, nil)
    MCP.Cancellation.cancel(cancellation)
    {:ok, work} = Work.tool_call("id", Tool.name(), call_params()["arguments"])
    assert {:failed, %{"code" => -32_603}, _} = Executor.execute(work, cancellation, nil)
  end

  test "explicit startup and periodic reaping remove expired snapshots and finish their streams",
       ctx do
    insert_expired(ctx.store, "expired-before-start")
    opts = %{store: ctx.store, poll_interval_ms: 10}

    {:ok, _, initial} =
      Source.open(%{"taskIds" => ["expired-before-start"]}, context("team-a"), opts)

    assert {:ok, _working} = Source.next(initial, opts)
    runner(ctx.store, recover: false)
    assert :closed = Source.next(initial, opts)
    {:ok, access} = Store.authorize(ctx.store, context("team-a"), {:get, "expired-before-start"})
    assert :not_found = Store.get(ctx.store, "expired-before-start", access)

    insert_expired(ctx.store, "expired-after-start")

    {:ok, _, later} =
      Source.open(%{"taskIds" => ["expired-after-start"]}, context("team-a"), opts)

    waiting =
      Task.async(fn ->
        case Source.next(later, opts) do
          {:ok, _working} -> Source.next(later, opts)
          :closed -> :closed
        end
      end)

    assert :closed = Task.await(waiting, 2_000)
    {:ok, access} = Store.authorize(ctx.store, context("team-a"), {:get, "expired-after-start"})
    assert :not_found = Store.get(ctx.store, "expired-after-start", access)
  end

  defp insert_expired(store, id) do
    task =
      MCP.Extensions.Tasks.Task.new!(
        id: id,
        created_at: DateTime.utc_now() |> DateTime.add(-60, :second) |> DateTime.to_iso8601(),
        ttl_ms: 1
      )

    work = Work.new!(id, "expired-fixture-never-executed", %{})
    {:ok, access} = Store.authorize(store, context("team-a"), {:create, id})
    assert {:ok, _snapshot} = Store.create(store, task, work, access)
  end

  test "source allows a fresh callback process per pull and explicit close",
       ctx do
    expect_domain(ctx.bypass, self(), :auto)

    runtime =
      AuditWorkflow.runtime(ctx.store, runner(ctx.store, executor: {ObservedExecutor, self()}))

    id = create(runtime)
    assert_receive {:audit_ready, worker}, 2_000
    opts = %{store: ctx.store, poll_interval_ms: 10}
    {:ok, _, source} = Source.open(%{"taskIds" => [id]}, context("team-a"), opts)
    assert {:ok, _working} = Task.async(fn -> Source.next(source, opts) end) |> Task.await()
    assert Process.alive?(source)
    next = Task.async(fn -> Source.next(source, opts) end)
    send(worker, :commit)
    assert {:ok, event} = Task.await(next, 2_000)
    assert event.payload.status == :completed
    assert :closed = Task.async(fn -> Source.next(source, opts) end) |> Task.await()

    {:ok, _, waiting_source} = Source.open(%{"taskIds" => [id]}, context("team-a"), opts)
    Source.close(waiting_source, :cancelled, opts)
    assert :closed = Source.next(waiting_source, opts)
  end

  test "authenticated Plug/Bandit HTTP streams SQLite statuses, isolates tenants and closes on disconnect",
       ctx do
    expect_domain(ctx.bypass, self(), :auto)

    runtime =
      AuditWorkflow.runtime(ctx.store, runner(ctx.store, executor: {ObservedExecutor, self()}))

    runtime = %{
      runtime
      | subscription_source: %MCP.Subscription.Source.Config{
          module: HexpmMcp.AuditWorkflowTest.TrackedSource,
          options: %{store: ctx.store, poll_interval_ms: 10, observer: self()}
        }
    }

    token_a = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
    token_b = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
    executor = start_supervised!({MCP.Server.Executor, max_concurrency: 4, max_queue: 8})

    listener =
      start_supervised!(
        {Bandit,
         plug:
           {HexpmMcp.AuditWorkflowTest.Endpoint,
            runtime: runtime,
            executor: executor,
            subscription_keepalive_ms: 50,
            tokens: [{token_a, "team-a"}, {token_b, "team-b"}]},
         ip: {127, 0, 0, 1},
         port: 0,
         startup_log: false}
      )

    {:ok, {_ip, port}} = ThousandIsland.listener_info(listener)
    url = "http://127.0.0.1:#{port}/mcp"
    assert %{status: 401} = http(url, nil, "tools/call", call_params())
    assert %{status: 401} = http(url, "bad-token", "tools/call", call_params())

    assert %{status: 200, body: %{"result" => %{"resultType" => "task", "taskId" => id}}} =
             http(url, token_a, "tools/call", call_params(%{"tenant" => "team-b"}))

    assert_receive {:audit_ready, audit_worker}, 2_000

    assert %{status: 400, body: %{"error" => %{"code" => -32_602}}} =
             http(url, token_b, "tasks/get", %{"taskId" => id})

    # Req decodes HTTP chunks, but does not interpret or synthesize MCP events.
    owner = self()

    stream =
      Task.async(fn ->
        http(url, token_a, "subscriptions/listen", %{"notifications" => %{"taskIds" => [id]}},
          into: fn {:data, data}, {request, response} ->
            send(owner, {:audit_sse, data})
            {:cont, {request, response}}
          end
        )
      end)

    assert_receive {:audit_source, source}, 2_000
    source_monitor = Process.monitor(source)
    first = receive_sse_until(~s("status":"working"))
    assert first =~ "notifications/subscriptions/acknowledged"
    assert first =~ "notifications/tasks"
    send(audit_worker, :commit)
    remainder = receive_sse_until(~s("resultType":"complete"))
    assert %{status: 200} = Task.await(stream, 2_000)
    assert_receive {:DOWN, ^source_monitor, :process, ^source, _}, 2_000
    messages = sse_messages(first <> drain_sse(remainder))

    assert Enum.map(messages, &(&1["method"] || "response")) == [
             "notifications/subscriptions/acknowledged",
             "notifications/tasks",
             "notifications/tasks",
             "response"
           ]

    assert Enum.map(
             Enum.filter(messages, &(&1["method"] == "notifications/tasks")),
             & &1["params"]["status"]
           ) ==
             ["working", "completed"]

    assert List.last(messages)["id"] == 44

    assert %{status: 200, body: %{"result" => %{"status" => "completed", "result" => report}}} =
             http(url, token_a, "tasks/get", %{"taskId" => id})

    assert report["structuredContent"]["observations"]["total_warnings"] == 2

    # A second task remains working when just its subscription socket disconnects.
    assert %{body: %{"result" => %{"taskId" => second_id}}} =
             http(url, token_a, "tools/call", call_params())

    assert_receive {:audit_ready, second_worker}, 2_000
    socket = subscribe_socket(port, token_a, second_id)
    assert_receive {:audit_source, second_source}, 2_000
    second_monitor = Process.monitor(second_source)
    assert read_socket_until(socket, "\"status\":\"working\"") =~ "notifications/tasks"
    :ok = :gen_tcp.close(socket)
    assert_receive {:DOWN, ^second_monitor, :process, ^second_source, _}, 2_000

    assert %{body: %{"result" => %{"status" => "working"}}} =
             http(url, token_a, "tasks/get", %{"taskId" => second_id})

    assert %{body: %{"result" => %{"resultType" => "complete"}}} =
             http(url, token_a, "tasks/cancel", %{"taskId" => second_id})

    refute Process.alive?(second_worker)
  end

  defp http(url, token, method, params, opts \\ []) do
    headers = http_headers(token, method, params)

    Req.post!(
      url,
      [json: wire_request(method, params), headers: headers, retry: false, receive_timeout: 4_000] ++
        opts
    )
  end

  defp http_headers(token, method, params) do
    name = params["name"] || params["taskId"]

    [
      {"content-type", "application/json"},
      {"accept", "application/json, text/event-stream"},
      {"mcp-protocol-version", "2026-07-28"},
      {"mcp-method", method}
    ]
    |> then(fn headers ->
      if token, do: [{"authorization", "Bearer " <> token} | headers], else: headers
    end)
    |> then(fn headers -> if name, do: [{"mcp-name", name} | headers], else: headers end)
  end

  defp wire_request(method, params) do
    metadata = V2026_07_28.request_metadata(%{"extensions" => %{Tasks.id() => %{}}})

    %{
      "jsonrpc" => "2.0",
      "id" => 44,
      "method" => method,
      "params" => Map.update(params, "_meta", metadata, &Map.merge(&1, metadata))
    }
  end

  defp receive_sse_until(expected, accumulated \\ "") do
    if String.contains?(accumulated, expected) do
      accumulated
    else
      assert_receive {:audit_sse, data}, 3_000
      receive_sse_until(expected, accumulated <> data)
    end
  end

  defp sse_messages(stream) do
    stream
    |> String.split("\n")
    |> Enum.filter(&String.starts_with?(&1, "data: "))
    |> Enum.map(fn "data: " <> json -> Jason.decode!(json) end)
  end

  defp drain_sse(accumulated) do
    receive do
      {:audit_sse, data} -> drain_sse(accumulated <> data)
    after
      0 -> accumulated
    end
  end

  defp subscribe_socket(port, token, id) do
    params = %{"notifications" => %{"taskIds" => [id]}}
    body = Jason.encode!(wire_request("subscriptions/listen", params))
    {:ok, socket} = :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, active: false], 2_000)

    headers =
      http_headers(token, "subscriptions/listen", params)
      |> Enum.map(fn {key, value} -> [key, ": ", value, "\r\n"] end)

    :ok =
      :gen_tcp.send(socket, [
        "POST /mcp HTTP/1.1\r\nHost: localhost\r\n",
        headers,
        "Content-Length: ",
        Integer.to_string(byte_size(body)),
        "\r\n\r\n",
        body
      ])

    socket
  end

  defp read_socket_until(socket, expected, accumulated \\ "") do
    if String.contains?(accumulated, expected) do
      accumulated
    else
      assert {:ok, chunk} = :gen_tcp.recv(socket, 0, 2_000)
      read_socket_until(socket, expected, accumulated <> chunk)
    end
  end

  defp expect_domain(bypass, owner, mode \\ :held) do
    Bypass.expect(bypass, "GET", "/packages/audit_target/releases/1.0.0", fn conn ->
      send(owner, {:release_request, self()})

      if mode == :held do
        receive do
          :respond -> :ok
        after
          5_000 -> raise "test did not release the domain request"
        end
      end

      respond_json(conn, 200, release_json("1.0.0", requirements: %{"audit_dep" => %{}}))
    end)

    Bypass.expect(bypass, "GET", "/packages/audit_dep", fn conn ->
      respond_json(
        conn,
        200,
        package_json("audit_dep", updated_at: DateTime.utc_now() |> DateTime.to_iso8601())
      )
    end)

    Bypass.expect(bypass, "GET", "/packages/audit_dep/owners", fn conn ->
      respond_json(conn, 200, [owner_json("fixture-owner")])
    end)

    Bypass.expect(bypass, "POST", "/osv", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)

      assert Jason.decode!(body) == %{
               "package" => %{"name" => "audit_dep", "ecosystem" => "Hex"}
             }

      respond_json(conn, 200, %{"vulns" => [%{"id" => "OFFLINE-FIXTURE-ONLY"}]})
    end)
  end

  defp open_repo(database) do
    {:ok, repo} = AuditWorkflow.start_repo(database)
    Process.unlink(repo)
    repo
  end

  defp runner(store, opts \\ []) do
    {:ok, runner} = AuditWorkflow.start_runner(store, opts)
    Process.unlink(runner)
    on_exit(fn -> stop(runner) end)
    runner
  end

  defp stop(nil), do: :ok
  defp stop(pid), do: if(Process.alive?(pid), do: GenServer.stop(pid))

  defp call_params(metadata \\ %{}) do
    %{
      "name" => Tool.name(),
      "arguments" => %{"name" => "audit_target", "version" => "1.0.0"},
      "_meta" => metadata
    }
  end

  defp dispatch(runtime, method, params, auth \\ %{"tenant" => "team-a"}) do
    MCP.Test.dispatch(runtime,
      protocol: "2026-07-28",
      method: method,
      params: params,
      client_capabilities: %{"extensions" => %{Tasks.id() => %{}}},
      transport_metadata: %{auth: auth}
    )
  end

  defp create(runtime) do
    assert {:ok, %{"result" => %{"resultType" => "task", "taskId" => id}}} =
             dispatch(runtime, "tools/call", call_params())

    id
  end

  defp listen(runtime, id) do
    assert {:stream, subscription} =
             dispatch(runtime, "subscriptions/listen", %{"notifications" => %{"taskIds" => [id]}})

    assert {:ok, %{"method" => "notifications/subscriptions/acknowledged"}} =
             Subscription.acknowledgement(subscription)

    {puller, monitor} = Subscription.start_worker(subscription, self())
    {subscription, puller, monitor}
  end

  defp notification(subscription, puller) do
    :ok = Subscription.continue(puller)
    event = receive_event(puller)
    assert {:ok, notification} = Subscription.notification(subscription, event)
    notification["params"]
  end

  defp receive_event(puller) do
    assert_receive {:mcp_subscription, ^puller, {:ok, event}}, 3_000
    event
  end

  defp terminal_status(subscription, puller) do
    case notification(subscription, puller)["status"] do
      "working" -> terminal_status(subscription, puller)
      terminal when terminal in ["completed", "failed", "cancelled"] -> terminal
    end
  end

  defp get_report(runtime, id) do
    assert {:ok, %{"result" => %{"status" => "completed", "result" => result}}} =
             dispatch(runtime, "tasks/get", %{"taskId" => id})

    assert result["resultType"] == "complete"
    refute result["isError"]
    result["structuredContent"]
  end

  defp close(subscription, puller, monitor) do
    :ok = Subscription.stop_worker(puller, monitor)
    :ok = Subscription.close(subscription, :complete)
  end

  defp context(tenant) do
    %MCP.Context{
      protocol_version: "2026-07-28",
      protocol: MCP.Protocol.V2026_07_28,
      transport: %MCP.Transport.Context{transport: :direct},
      auth: if(tenant, do: %{"tenant" => tenant})
    }
  end
end
