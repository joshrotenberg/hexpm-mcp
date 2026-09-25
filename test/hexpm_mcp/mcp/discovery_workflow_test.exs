defmodule HexpmMcp.MCP.DiscoveryWorkflowTest do
  use ExUnit.Case

  alias HexpmMcp.Cache
  alias HexpmMcp.MCP.Server
  alias HexpmMcp.Types.Package

  @capabilities %{"elicitation" => %{"form" => %{}}}

  setup do
    previous = Application.fetch_env(:hexpm_mcp, :hex_api_url)
    previous_ttl = Application.fetch_env(:hexpm_mcp, :cache_ttl)
    Application.put_env(:hexpm_mcp, :hex_api_url, "http://127.0.0.1:1")
    Application.put_env(:hexpm_mcp, :cache_ttl, 300)
    Cache.clear()

    on_exit(fn ->
      Cache.clear()

      case previous do
        {:ok, value} -> Application.put_env(:hexpm_mcp, :hex_api_url, value)
        :error -> Application.delete_env(:hexpm_mcp, :hex_api_url)
      end

      case previous_ttl do
        {:ok, value} -> Application.put_env(:hexpm_mcp, :cache_ttl, value)
        :error -> Application.delete_env(:hexpm_mcp, :cache_ttl)
      end
    end)

    :ok
  end

  test "prompt and resource completions use the same bounded, cached name search" do
    seed("ec", ["ecto_sql", "ecto", "unrelated", "ecto"])

    for ref <- [
          %{"type" => "ref/prompt", "name" => "analyze_package"},
          %{"type" => "ref/prompt", "name" => "package_review"},
          %{"type" => "ref/resource", "uri" => "hex://{name}/info"}
        ] do
      assert %{"result" => %{"completion" => completion}} = complete(ref, "name", "ec")
      assert completion == %{"values" => ["ecto", "ecto_sql"], "hasMore" => false}
    end
  end

  test "a full upstream page does not pretend to establish the global total" do
    seed("ec", Enum.map(1..100, &"ecto_#{&1}"))
    ref = %{"type" => "ref/prompt", "name" => "analyze_package"}
    assert %{"result" => %{"completion" => completion}} = complete(ref, "name", "ec")
    assert length(completion["values"]) == 100
    assert completion["hasMore"]
    refute Map.has_key?(completion, "total")
  end

  test "typing guards do not call Hex and upstream errors are not fake empty successes" do
    ref = %{"type" => "ref/prompt", "name" => "analyze_package"}

    for prefix <- ["", "e", "name:ecto", "ec*", "ec\n", String.duplicate("a", 65)] do
      assert %{"result" => %{"completion" => %{"values" => []}}} =
               complete(ref, "name", prefix)
    end

    Cache.put({:search, "ec", [sort: "name", page: 1]}, {:error, :rate_limited})
    assert %{"error" => %{"code" => -32_603}} = complete(ref, "name", "ec")
  end

  test "catalog pages retain cache hints and cursors cannot cross list methods" do
    assert %{"result" => %{"tools" => tools, "nextCursor" => cursor} = result} =
             dispatch("tools/list", %{})

    assert length(tools) == 8
    assert result["ttlMs"] == 60_000
    assert result["cacheScope"] == "public"

    assert %{"error" => %{"code" => -32_602}} =
             dispatch("prompts/list", %{"cursor" => cursor})

    assert %{"result" => next} = dispatch("tools/list", %{"cursor" => cursor})
    assert Map.take(next, ["ttlMs", "cacheScope"]) == Map.take(result, ["ttlMs", "cacheScope"])
    assert MapSet.disjoint?(MapSet.new(tools), MapSet.new(next["tools"]))
  end

  test "review asks for a focus, validates a fresh retry, and returns a read-only plan" do
    params = %{"name" => "package_review", "arguments" => %{"name" => "ecto"}}

    assert %{"result" => %{"resultType" => "input_required"} = pending} =
             dispatch("prompts/get", params)

    refute Map.has_key?(pending, "requestState")
    assert get_in(pending, ["inputRequests", "review_focus", "method"]) == "elicitation/create"

    retry = Map.put(params, "inputResponses", answer("security"))

    assert %{"result" => %{"resultType" => "complete", "messages" => [message]}} =
             dispatch("prompts/get", retry, id: "fresh-retry")

    assert message["content"]["text"] =~ "security review"
    assert message["content"]["text"] =~ "hex://ecto/info"
    assert message["content"]["text"] =~ "not a security assurance"

    assert %{"error" => %{"code" => -32_602}} =
             dispatch("prompts/get", Map.put(params, "inputResponses", answer("publish")))
  end

  test "review handles missing, declined, cancelled input and hosts without elicitation" do
    params = %{"name" => "package_review", "arguments" => %{"name" => "ecto"}}
    assert %{"error" => error} = dispatch("prompts/get", params, client_capabilities: %{})
    assert error["code"] == -32_021

    assert %{"result" => %{"resultType" => "input_required"}} =
             dispatch("prompts/get", Map.put(params, "inputResponses", %{}))

    for action <- ["decline", "cancel"] do
      responses = %{"review_focus" => %{"action" => action}}

      assert %{"result" => %{"messages" => [message]}} =
               dispatch("prompts/get", Map.put(params, "inputResponses", responses))

      assert message["content"]["text"] =~ "No analysis or package changes"
    end

    explicit = put_in(params, ["arguments", "focus"], "quality")

    assert %{"result" => %{"resultType" => "complete"}} =
             dispatch("prompts/get", explicit, client_capabilities: %{})

    assert %{"error" => %{"code" => -32_602}} =
             dispatch("prompts/get", put_in(explicit, ["arguments", "focus"], "anything"))
  end

  test "focus completion is local and prefix filtered" do
    assert %{"result" => %{"completion" => %{"values" => ["security"]}}} =
             complete(%{"type" => "ref/prompt", "name" => "package_review"}, "focus", "sec")
  end

  defp answer(focus),
    do: %{"review_focus" => %{"action" => "accept", "content" => %{"focus" => focus}}}

  defp seed(prefix, names) do
    Cache.put(
      {:search, prefix, [sort: "name", page: 1]},
      {:ok, Enum.map(names, &%Package{name: &1})}
    )
  end

  defp complete(ref, argument, value) do
    dispatch("completion/complete", %{
      "ref" => ref,
      "argument" => %{"name" => argument, "value" => value}
    })
  end

  defp dispatch(method, params, opts \\ []) do
    {:ok, result} =
      Snodo.Test.dispatch(
        Server.runtime(),
        Keyword.merge(
          [
            protocol: "2026-07-28",
            method: method,
            params: params,
            client_capabilities: @capabilities
          ],
          opts
        )
      )

    result
  end
end
