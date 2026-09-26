defmodule HexpmMcp.MCP.ServerTest do
  use ExUnit.Case, async: true

  alias HexpmMcp.MCP.Resources.PackageInfo
  alias HexpmMcp.MCP.Resources.ToolboxCategory
  alias HexpmMcp.MCP.Server
  alias Snodo.Protocol.V2026_07_28, as: Protocol
  alias Snodo.Transport.StreamableHTTP.Server, as: HTTPServer

  @protocol "2026-07-28"

  @tool_names ~w(
    alternatives audit audit_mix_deps compare dep_tree dependencies doc_item docs downloads
    features health info owners readme release search search_docs toolbox_category toolbox_group
    toolbox_groups toolbox_search toolbox_trending upgrade_check versions
  )

  @prompt_names ~w(
    analyze_package compare_packages evaluate_dependencies migration_guide package_review recommend_packages
  )

  test "discovers the application identity and all component capabilities" do
    assert {:ok, %{"result" => result}} = dispatch("server/discover")

    assert result["supportedVersions"] == [@protocol]

    assert result["capabilities"] == %{
             "completions" => %{},
             "prompts" => %{},
             "resources" => %{},
             "tools" => %{}
           }

    assert get_in(result, ["_meta", "io.modelcontextprotocol/serverInfo"]) == %{
             "name" => "hexpm-mcp",
             "version" => Mix.Project.config()[:version]
           }
  end

  test "lists all tools with their public JSON schemas" do
    tools = tools_pages(%{}, [])

    assert Enum.map(tools, & &1["name"]) == Enum.sort(@tool_names)

    search = Enum.find(tools, &(&1["name"] == "search"))
    assert search["inputSchema"]["required"] == ["query"]
    assert get_in(search, ["inputSchema", "properties", "page", "type"]) == "integer"

    # Captured from the raw definitions before adopting Snodo.Tool.Simple.
    expected =
      "test/fixtures/mcp_tool_catalog.json"
      |> File.read!()
      |> JSON.decode!()

    assert Enum.map(tools, &Map.take(&1, ["name", "description", "inputSchema"])) == expected
  end

  test "validates tool argument shape before invoking domain code" do
    assert {:ok, %{"result" => %{"isError" => true}}} =
             dispatch("tools/call", %{"name" => "search", "arguments" => %{}})

    assert {:ok, %{"result" => %{"isError" => true}}} =
             dispatch("tools/call", %{
               "name" => "search",
               "arguments" => %{"query" => "ecto", "page" => "one"}
             })
  end

  test "lists and renders prompts through the final protocol" do
    assert {:ok, %{"result" => %{"prompts" => prompts}}} = dispatch("prompts/list")
    assert Enum.map(prompts, & &1["name"]) == Enum.sort(@prompt_names)

    assert {:ok, %{"result" => result}} =
             dispatch("prompts/get", %{
               "name" => "analyze_package",
               "arguments" => %{"name" => "ecto"}
             })

    assert get_in(result, ["messages", Access.at(0), "role"]) == "user"

    assert get_in(result, ["messages", Access.at(0), "content", "text"]) =~
             ~s(package "ecto")
  end

  test "separates static resources from templates with generated variable bindings" do
    assert {:ok, %{"result" => %{"resources" => resources}}} = dispatch("resources/list")
    assert Enum.map(resources, & &1["uri"]) == ["toolbox://groups"]

    assert {:ok, %{"result" => %{"resourceTemplates" => templates}}} =
             dispatch("resources/templates/list")

    assert Enum.map(templates, & &1["uriTemplate"]) ==
             Enum.sort([
               "hex://{name}/docs",
               "hex://{name}/info",
               "hex://{name}/readme",
               "toolbox://{group}/{category}"
             ])

    assert PackageInfo.matches?("hex://ecto/info") == {:ok, %{"name" => "ecto"}}

    assert ToolboxCategory.matches?("toolbox://web/frameworks") ==
             {:ok, %{"group" => "web", "category" => "frameworks"}}

    refute PackageInfo.matches?("hex://ecto/info?unexpected=true")
    refute ToolboxCategory.matches?("https://web/frameworks")
  end

  test "serves discovery through the native Streamable HTTP listener" do
    {:ok, server} = start_supervised({HTTPServer, runtime: Server.runtime(), port: 0})
    {{127, 0, 0, 1}, port, "/mcp"} = HTTPServer.address(server)

    raw = request("http-discover", "server/discover")
    response = post(port, raw)

    assert response.status == 200

    assert get_in(JSON.decode!(response.body), ["result", "supportedVersions"]) == [@protocol]
  end

  defp dispatch(method, params \\ %{}) do
    Snodo.Test.dispatch(Server.runtime(),
      protocol: @protocol,
      method: method,
      params: params
    )
  end

  defp tools_pages(params, previous) do
    assert {:ok, %{"result" => %{"tools" => tools} = result}} = dispatch("tools/list", params)
    assert length(tools) == 8

    case Map.fetch(result, "nextCursor") do
      {:ok, cursor} -> tools_pages(%{"cursor" => cursor}, previous ++ tools)
      :error -> previous ++ tools
    end
  end

  defp request(id, method, params \\ %{}) do
    metadata = %{
      Protocol.protocol_version_key() => @protocol,
      Protocol.client_capabilities_key() => %{}
    }

    %{
      "jsonrpc" => "2.0",
      "id" => id,
      "method" => method,
      "params" => Map.put(params, "_meta", metadata)
    }
  end

  defp post(port, raw) do
    body = JSON.encode!(raw)

    headers = [
      {"Content-Type", "application/json"},
      {"Accept", "application/json, text/event-stream"},
      {"MCP-Protocol-Version", @protocol},
      {"Mcp-Method", raw["method"]},
      {"Content-Length", Integer.to_string(byte_size(body))}
    ]

    lines = Enum.map(headers, fn {name, value} -> [name, ": ", value, "\r\n"] end)
    encoded = ["POST /mcp HTTP/1.1\r\n", lines, "\r\n", body]

    {:ok, socket} = :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, active: false])
    :ok = :gen_tcp.send(socket, encoded)
    parse_response(recv_all(socket, ""))
  end

  defp recv_all(socket, acc) do
    case :gen_tcp.recv(socket, 0, 2_000) do
      {:ok, chunk} -> recv_all(socket, acc <> chunk)
      {:error, :closed} -> acc
    end
  end

  defp parse_response(response) do
    [head, body] = :binary.split(response, "\r\n\r\n")
    [status_line | _headers] = :binary.split(head, "\r\n", [:global])
    ["HTTP/1.1", status | _reason] = String.split(status_line, " ")
    %{status: String.to_integer(status), body: body}
  end
end
