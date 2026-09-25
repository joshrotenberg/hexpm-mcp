defmodule HexpmMcp.MCP.ApplicationAcceptanceTest do
  use ExUnit.Case

  alias HexpmMcp.Cache
  alias HexpmMcp.MCP.Server
  alias HexpmMcp.Types.Package
  alias MCP.Transport.Stdio
  alias MCP.Transport.StreamableHTTP.Server, as: HTTPServer

  @protocol "2026-07-28"
  @fixture_config [
    cache_ttl: 300,
    docs_cache_ttl: 300,
    hex_api_url: "http://127.0.0.1:1",
    hexdocs_url: "http://127.0.0.1:1",
    toolbox_url: "http://127.0.0.1:1",
    osv_url: "http://127.0.0.1:1"
  ]

  setup do
    previous =
      for {key, _value} <- @fixture_config, do: {key, Application.fetch_env(:hexpm_mcp, key)}

    Application.put_all_env(hexpm_mcp: @fixture_config)
    Cache.clear()

    on_exit(fn ->
      Cache.clear()

      for {key, value} <- previous do
        case value do
          {:ok, value} -> Application.put_env(:hexpm_mcp, key, value)
          :error -> Application.delete_env(:hexpm_mcp, key)
        end
      end
    end)

    package = %Package{
      name: "boundary_fixture",
      latest_version: "1.2.3",
      latest_stable_version: "1.2.3",
      meta: %{"description" => "Boundary fixture", "licenses" => ["Apache-2.0"]},
      downloads: %{"all" => 42},
      inserted_at: "2026-01-01T00:00:00Z",
      updated_at: "2026-09-01T00:00:00Z"
    }

    Cache.put({:package, "boundary_fixture"}, {:ok, package})
    Cache.put({:package, "missing_fixture"}, {:error, :not_found})

    Cache.put(
      {:modules, "boundary_fixture", nil},
      {:ok, [%{name: "Fixture", type: :module, doc: "Docs"}]}
    )

    Cache.put({:modules, "empty_fixture", nil}, {:ok, []})
    Cache.put({:readme, "boundary_fixture", nil}, {:ok, "# Fixture README"})
    Cache.put({:toolbox_groups}, {:ok, [%{slug: "web", name: "Web", categories: []}]})
    Cache.put({:toolbox_category, "web", "frameworks", []}, {:ok, [%{name: "boundary_fixture"}]})

    runtime = Server.runtime()
    {:ok, listener} = start_supervised({HTTPServer, runtime: runtime, port: 0})
    {{127, 0, 0, 1}, port, "/mcp"} = HTTPServer.address(listener)
    %{runtime: runtime, port: port}
  end

  test "all resource payloads cross direct, stdio, and HTTP boundaries", context do
    resources = [
      {"hex://boundary_fixture/info", "application/json",
       %{"name" => "boundary_fixture", "inserted_at" => "2026-01-01T00:00:00Z"}},
      {"hex://boundary_fixture/docs", "application/json",
       [%{"name" => "Fixture", "type" => "module", "doc" => "Docs"}]},
      {"hex://boundary_fixture/readme", "text/markdown", "# Fixture README"},
      {"toolbox://groups", "application/json",
       %{"groups" => [%{"slug" => "web", "name" => "Web", "categories" => []}]}},
      {"toolbox://web/frameworks", "application/json",
       %{"projects" => [%{"name" => "boundary_fixture"}]}}
    ]

    for transport <- [:direct, :stdio, :http], {uri, mime_type, expected} <- resources do
      response = dispatch(context, transport, "resources/read", %{"uri" => uri})
      assert %{"result" => %{"resultType" => "complete", "contents" => [content]}} = response
      assert content["uri"] == uri
      assert content["mimeType"] == mime_type

      payload =
        if mime_type == "application/json",
          do: JSON.decode!(content["text"]),
          else: content["text"]

      if is_map(expected) do
        assert Map.take(payload, Map.keys(expected)) == expected
      else
        assert payload == expected
      end
    end
  end

  test "tool domain failures are results while invalid arguments are protocol errors", context do
    for transport <- [:direct, :stdio, :http] do
      for {name, args} <- [
            {"info", %{"name" => "missing_fixture"}},
            {"compare", %{"packages" => "only_one"}},
            {"compare", %{"packages" => "a,b,c,d,e,f"}},
            {"audit_mix_deps", %{"deps" => "not a dependency declaration"}},
            {"upgrade_check", %{"deps" => "not a dependency declaration"}}
          ] do
        assert %{"result" => %{"isError" => true, "resultType" => "complete"}} =
                 dispatch(context, transport, "tools/call", %{"name" => name, "arguments" => args})
      end

      for args <- [%{}, %{"name" => 42}] do
        assert %{"error" => %{"code" => -32_602}} =
                 dispatch(context, transport, "tools/call", %{
                   "name" => "info",
                   "arguments" => args
                 })
      end
    end
  end

  test "successful domain results and empty listings stay successful", context do
    for transport <- [:direct, :stdio, :http],
        {name, args, expected} <- [
          {"info", %{"name" => "boundary_fixture"}, "boundary_fixture"},
          {"docs", %{"name" => "empty_fixture"}, "No modules found"}
        ] do
      assert %{"result" => result} =
               dispatch(context, transport, "tools/call", %{"name" => name, "arguments" => args})

      refute result["isError"]
      assert [%{"text" => text}] = result["content"]
      assert text =~ expected
    end
  end

  test "template lookalikes fail before invoking the domain", context do
    for uri <- [
          "hex://boundary_fixture//info",
          "hex://boundary_fixture/info/",
          "hex://boundary_fixture:80/info"
        ] do
      assert %{"error" => %{"code" => -32_602}} =
               dispatch(context, :direct, "resources/read", %{"uri" => uri})
    end
  end

  test "a missing resource uses the protocol not-found error", context do
    for transport <- [:direct, :stdio, :http] do
      assert %{
               "error" => %{"code" => -32_602, "data" => %{"uri" => "hex://missing_fixture/info"}}
             } =
               dispatch(context, transport, "resources/read", %{
                 "uri" => "hex://missing_fixture/info"
               })
    end
  end

  # Literal metadata is intentional: MCP.Test supplies these fields, while a
  # real client must send them. The same envelope exercises each boundary.
  defp dispatch(context, transport, method, params) do
    raw = %{
      "jsonrpc" => "2.0",
      "id" => 1,
      "method" => method,
      "params" =>
        Map.put(params, "_meta", %{
          "io.modelcontextprotocol/protocolVersion" => @protocol,
          "io.modelcontextprotocol/clientCapabilities" => %{}
        })
    }

    run(context, transport, raw)
  end

  defp run(context, :direct, raw) do
    {:ok, response} =
      MCP.Server.dispatch(context.runtime, raw, %MCP.Transport.Context{transport: :direct})

    response
  end

  defp run(context, :stdio, raw) do
    {:ok, input} = StringIO.open(JSON.encode!(raw) <> "\n")
    {:ok, output} = StringIO.open("")

    try do
      :ok = Stdio.serve(context.runtime, input: input, output: output)
      {_input, response} = StringIO.contents(output)
      JSON.decode!(String.trim(response))
    after
      StringIO.close(input)
      StringIO.close(output)
    end
  end

  defp run(context, :http, raw) do
    body = JSON.encode!(raw)
    name = raw["params"]["name"] || raw["params"]["uri"]

    headers = [
      {"Host", "localhost"},
      {"Content-Type", "application/json"},
      {"Accept", "application/json, text/event-stream"},
      {"MCP-Protocol-Version", @protocol},
      {"Mcp-Method", raw["method"]},
      {"Mcp-Name", name},
      {"Content-Length", Integer.to_string(byte_size(body))}
    ]

    lines = Enum.map(headers, fn {key, value} -> [key, ": ", value, "\r\n"] end)
    {:ok, socket} = :gen_tcp.connect({127, 0, 0, 1}, context.port, [:binary, active: false])

    try do
      :ok = :gen_tcp.send(socket, ["POST /mcp HTTP/1.1\r\n", lines, "\r\n", body])
      [head, body] = :binary.split(recv_all(socket, ""), "\r\n\r\n")
      response = JSON.decode!(body)
      assert_http_envelope(head, response)
      response
    after
      :gen_tcp.close(socket)
    end
  end

  defp assert_http_envelope(head, response) do
    [status_line | header_lines] = String.split(head, "\r\n")
    ["HTTP/1.1", status | _reason] = String.split(status_line, " ")

    # This suite exercises only successful results and invalid-params errors.
    assert status == if(Map.has_key?(response, "error"), do: "400", else: "200")

    headers =
      Map.new(header_lines, fn line ->
        [name, value] = String.split(line, ":", parts: 2)
        {String.downcase(name), String.trim(value)}
      end)

    assert headers["content-type"] == "application/json"
    refute Map.has_key?(headers, "mcp-session-id")
  end

  defp recv_all(socket, received) do
    case :gen_tcp.recv(socket, 0, 2_000) do
      {:ok, chunk} -> recv_all(socket, received <> chunk)
      {:error, :closed} -> received
    end
  end
end
