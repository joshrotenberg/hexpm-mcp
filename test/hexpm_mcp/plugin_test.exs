defmodule HexpmMcp.PluginTest do
  use ExUnit.Case, async: true

  alias HexpmMcp.MCP.Server

  # Read through the application's priv dir, which is what a release ships.
  @root Path.join(:code.priv_dir(:hexpm_mcp), "plugin/hexpm")

  test "both manifests name the plugin and leave the version to init" do
    for manifest <- [".claude-plugin/plugin.json", ".codex-plugin/plugin.json"] do
      decoded = @root |> Path.join(manifest) |> File.read!() |> JSON.decode!()

      assert decoded["name"] == "hexpm"
      refute Map.has_key?(decoded, "version")
    end

    codex = @root |> Path.join(".codex-plugin/plugin.json") |> File.read!() |> JSON.decode!()
    assert File.dir?(Path.join(@root, codex["skills"]))
  end

  test "the skill names itself and every tool it names is served" do
    ["", frontmatter, body] =
      @root
      |> Path.join("skills/hexpm/SKILL.md")
      |> File.read!()
      |> String.split("---\n", parts: 3)

    assert frontmatter =~ ~r/^name: hexpm$/m
    assert frontmatter =~ ~r/^description: \S/m

    named =
      ~r/`([a-z][a-z_]*)`/
      |> Regex.scan(body, capture: :all_but_first)
      |> List.flatten()
      |> Enum.uniq()

    assert {:ok, %{"result" => %{"tools" => tools}}} =
             Snodo.Test.dispatch(Server.runtime(),
               protocol: "2026-07-28",
               method: "tools/list",
               params: %{}
             )

    assert named != []
    assert named -- Enum.map(tools, & &1["name"]) == []
  end

  test "the hook runs the bundled script after edits" do
    hooks = @root |> Path.join("hooks/hooks.json") |> File.read!() |> JSON.decode!()

    assert [%{"matcher" => "Edit|Write|MultiEdit", "hooks" => [hook]}] =
             hooks["hooks"]["PostToolUse"]

    assert hook["command"] =~ "${CLAUDE_PLUGIN_ROOT}/hooks/mix-deps.sh"
  end

  test "the hook adds context after an edit to mix.exs or mix.lock" do
    for path <- ["/app/mix.exs", "/app/apps/web/mix.lock", ~S(C:\app\mix.exs)] do
      {output, 0} = run_hook(path)

      assert %{"hookSpecificOutput" => specific} = JSON.decode!(output)
      assert specific["hookEventName"] == "PostToolUse"
      assert specific["additionalContext"] =~ "audit_mix_deps"
    end
  end

  test "the hook prints nothing for other files" do
    for path <- ["/app/lib/mix_tasks.ex", "/app/mix.exs.orig", "/app/notmix.exs"] do
      assert run_hook(path) == {"", 0}
    end
  end

  defp run_hook(path) do
    payload =
      JSON.encode!(%{
        "hook_event_name" => "PostToolUse",
        "tool_name" => "Edit",
        "tool_input" => %{"file_path" => path}
      })

    script = Path.join(@root, "hooks/mix-deps.sh")
    System.cmd("sh", ["-c", ~S(printf '%s' "$1" | sh "$2"), "sh", payload, script])
  end
end
