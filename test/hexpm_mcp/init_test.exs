defmodule HexpmMcp.InitTest do
  use ExUnit.Case, async: true

  alias HexpmMcp.Init

  @moduletag :tmp_dir

  @version Mix.Project.config()[:version]

  setup %{tmp_dir: tmp} do
    binary = Path.join(tmp, "hexpm_mcp")
    File.write!(binary, "#!/bin/sh\necho fake\n")

    env = %{
      home: Path.join(tmp, "home"),
      xdg_data_home: nil,
      bin_path: nil,
      find_executable: fn name ->
        Map.get(%{"claude" => "/hosts/claude", "codex" => "/hosts/codex"}, name)
      end
    }

    %{dir: Path.join(tmp, "mkt"), binary: binary, env: env}
  end

  describe "planning" do
    test "a dry run lists files and commands and touches nothing", ctx do
      report = install(ctx, %{dry_run: true}, runner(%{}))

      assert report.status == "planned"
      refute File.exists?(ctx.dir)
      refute_received {:ran, _, _}

      for file <- [
            ".hexpm-mcp-install.json",
            "plugins/hexpm/.mcp.json",
            "plugins/hexpm/.claude-plugin/plugin.json",
            "plugins/hexpm/skills/hexpm/SKILL.md",
            ".claude-plugin/marketplace.json",
            ".agents/plugins/marketplace.json"
          ] do
        assert file in report.files
      end

      assert "claude plugin install hexpm@hexpm-local --scope user --json" in report.commands
      assert "codex plugin add hexpm@hexpm-local --json" in report.commands
    end

    test "the install dir comes from --install-dir, then XDG_DATA_HOME, then HOME", ctx do
      dir = fn args, env ->
        Init.install(Map.merge(%{dry_run: true, binary: ctx.binary}, args), env: env).install_dir
      end

      assert dir.(%{install_dir: "/m"}, ctx.env) == "/m"
      assert dir.(%{}, %{ctx.env | xdg_data_home: "/xdg"}) == "/xdg/hexpm_mcp"
      # The XDG spec says a relative value is ignored.
      assert dir.(%{}, %{ctx.env | xdg_data_home: "rel"}) ==
               Path.join(ctx.env.home, ".local/share/hexpm_mcp")

      assert dir.(%{}, ctx.env) == Path.join(ctx.env.home, ".local/share/hexpm_mcp")
    end

    test "the running Burrito binary is used when --binary is absent", ctx do
      report =
        Init.install(%{dry_run: true, install_dir: ctx.dir},
          env: %{ctx.env | bin_path: ctx.binary}
        )

      assert report.status == "planned"
      assert report.binary.source == ctx.binary
    end

    test "without a standalone binary or --binary, init is not ready", ctx do
      report = Init.install(%{dry_run: true, install_dir: ctx.dir}, env: ctx.env)

      assert report.status == "not_ready"
      assert Enum.any?(report.issues, &(&1 =~ "--binary"))
    end

    test "a non-empty directory without the marker is refused", ctx do
      File.mkdir_p!(ctx.dir)
      File.write!(Path.join(ctx.dir, "notes.txt"), "mine")

      report = install(ctx, %{dry_run: true}, runner(%{}))

      assert report.status == "not_ready"
      assert Enum.any?(report.issues, &(&1 =~ ".hexpm-mcp-install.json"))
    end

    test "both skips a host that is not installed; a named host must exist", ctx do
      env = %{ctx.env | find_executable: fn name -> if name == "claude", do: "/hosts/claude" end}

      both = Init.install(%{dry_run: true, binary: ctx.binary, install_dir: ctx.dir}, env: env)
      assert both.status == "planned"
      assert Enum.map(both.hosts, & &1.name) == ["claude"]
      assert both.skipped_hosts == ["codex"]

      codex =
        Init.install(%{dry_run: true, binary: ctx.binary, install_dir: ctx.dir, host: "codex"},
          env: env
        )

      assert codex.status == "not_ready"
      assert Enum.any?(codex.issues, &(&1 =~ "--codex-bin"))
    end
  end

  describe "installing" do
    test "a first install writes the marketplace and registers with both hosts", ctx do
      report = install(ctx, %{}, runner(fresh_hosts()))

      assert report.status == "installed"

      assert steps(report) == [
               {"claude plugin marketplace list --json", "ok"},
               {"claude plugin marketplace add #{ctx.dir} --scope user --json", "ok"},
               {"claude plugin marketplace update hexpm-local --json", "skipped"},
               {"claude plugin list --json", "ok"},
               {"claude plugin install hexpm@hexpm-local --scope user --json", "ok"},
               {"claude plugin update hexpm@hexpm-local --scope user --json", "skipped"},
               {"codex plugin marketplace list --json", "ok"},
               {"codex plugin marketplace add #{ctx.dir} --json", "ok"},
               {"codex plugin add hexpm@hexpm-local --json", "ok"}
             ]

      installed = Path.join(ctx.dir, "bin/hexpm_mcp")
      assert File.read!(installed) == File.read!(ctx.binary)
      assert Bitwise.band(File.stat!(installed).mode, 0o777) == 0o755

      assert read_json(ctx.dir, "plugins/hexpm/.mcp.json") == %{
               "mcpServers" => %{
                 "hexpm" => %{
                   "type" => "stdio",
                   "command" => installed,
                   "args" => ["--transport", "stdio"]
                 }
               }
             }

      for manifest <- [".claude-plugin/plugin.json", ".codex-plugin/plugin.json"] do
        assert read_json(ctx.dir, "plugins/hexpm/#{manifest}")["version"] == @version
      end

      assert [%{"name" => "hexpm", "version" => @version, "source" => "./plugins/hexpm"}] =
               read_json(ctx.dir, ".claude-plugin/marketplace.json")["plugins"]

      assert [%{"source" => %{"path" => "./plugins/hexpm"}}] =
               read_json(ctx.dir, ".agents/plugins/marketplace.json")["plugins"]

      assert read_json(ctx.dir, ".hexpm-mcp-install.json")["managed_by"] == "hexpm_mcp"
    end

    test "a hand-configured hexpm server is reported, and the plugin's own is not", ctx do
      report = install(ctx, %{}, runner(fresh_hosts()))

      assert report.existing_servers == [
               %{host: "claude", name: "hexpm", target: "https://hexpm-mcp.fly.dev/mcp (HTTP)"},
               %{host: "codex", name: "hex", target: "/opt/bin/hexpm_mcp --transport stdio"}
             ]
    end

    test "a re-run refreshes the marketplace and updates the plugin", ctx do
      install(ctx, %{}, runner(fresh_hosts()))
      flush()

      registered = %{
        {"claude", ~w(plugin marketplace list)} =>
          {JSON.encode!([%{"name" => "hexpm-local", "source" => "directory", "path" => ctx.dir}]),
           0},
        {"claude", ~w(plugin list --json)} =>
          {JSON.encode!([%{"id" => "hexpm@hexpm-local", "scope" => "user"}]), 0},
        {"codex", ~w(plugin marketplace list)} =>
          {JSON.encode!(%{"marketplaces" => [%{"name" => "hexpm-local", "root" => ctx.dir}]}), 0}
      }

      report = install(ctx, %{}, runner(registered))

      assert report.status == "installed"

      assert steps(report) == [
               {"claude plugin marketplace list --json", "ok"},
               {"claude plugin marketplace add #{ctx.dir} --scope user --json", "skipped"},
               {"claude plugin marketplace update hexpm-local --json", "ok"},
               {"claude plugin list --json", "ok"},
               {"claude plugin install hexpm@hexpm-local --scope user --json", "skipped"},
               {"claude plugin update hexpm@hexpm-local --scope user --json", "ok"},
               {"codex plugin marketplace list --json", "ok"},
               {"codex plugin marketplace add #{ctx.dir} --json", "skipped"},
               {"codex plugin add hexpm@hexpm-local --json", "ok"}
             ]
    end

    test "a re-run drops plugin files a newer release no longer ships", ctx do
      install(ctx, %{}, runner(fresh_hosts()))
      stale = Path.join(ctx.dir, "plugins/hexpm/skills/retired/SKILL.md")
      File.mkdir_p!(Path.dirname(stale))
      File.write!(stale, "old")

      install(ctx, %{}, runner(fresh_hosts()))

      refute File.exists?(stale)
    end

    test "hexpm-local registered at another path stops init before installing", ctx do
      elsewhere = %{
        {"claude", ~w(plugin marketplace list)} =>
          {JSON.encode!([
             %{"name" => "hexpm-local", "source" => "directory", "path" => "/somewhere/else"}
           ]), 0}
      }

      report = install(ctx, %{}, runner(elsewhere))

      assert report.status == "partial_install"
      assert report.error =~ "/somewhere/else"
      assert steps(report) == [{"claude plugin marketplace list --json", "failed"}]
    end

    test "a failing host command stops the run and names the step", ctx do
      failing =
        Map.put(
          fresh_hosts(),
          {"claude", ~w(plugin install hexpm@hexpm-local)},
          {"no network", 1}
        )

      report = install(ctx, %{}, runner(failing))

      assert report.status == "partial_install"
      assert report.error =~ "claude plugin install hexpm@hexpm-local"
      assert report.error =~ "no network"

      assert List.last(steps(report)) ==
               {"claude plugin install hexpm@hexpm-local --scope user --json", "failed"}

      refute Enum.any?(steps(report), fn {command, _} -> command =~ "codex" end)
    end
  end

  describe "reporting" do
    test "claude mcp list lines parse to name and target" do
      output = """
      Checking MCP server health...

      hexpm: https://hexpm-mcp.fly.dev/mcp (HTTP) - ✔ Connected
      plugin:hexpm:hexpm: /x/bin/hexpm_mcp --transport stdio - ✔ Connected
      github: npx -y github-mcp - ✔ Connected
      """

      assert Init.parse_claude_servers(output) == [
               %{name: "hexpm", target: "https://hexpm-mcp.fly.dev/mcp (HTTP)"}
             ]
    end

    test "the JSON report is one document", ctx do
      report = install(ctx, %{dry_run: true}, runner(%{}))

      assert %{"status" => "planned", "version" => @version} =
               JSON.decode!(Init.render(report, "json"))
    end

    test "the text report names the status and each command", ctx do
      text =
        ctx
        |> install(%{dry_run: true}, runner(%{}))
        |> Init.render("text")
        |> IO.iodata_to_binary()

      assert text =~ "init: planned"
      assert text =~ "claude plugin marketplace list --json"
      assert text =~ "Dry run"
    end
  end

  defp install(ctx, args, runner) do
    Init.install(Map.merge(%{binary: ctx.binary, install_dir: ctx.dir}, args),
      env: ctx.env,
      runner: runner
    )
  end

  # Canned host output keyed by host and the first three arguments. Anything
  # unlisted succeeds with an empty JSON object.
  defp runner(responses) do
    test = self()

    fn exe, args ->
      host = Path.basename(exe)
      send(test, {:ran, host, args})
      Map.get(responses, {host, Enum.take(args, 3)}, {"{}", 0})
    end
  end

  defp fresh_hosts do
    %{
      {"claude", ~w(plugin marketplace list)} => {"[]", 0},
      {"claude", ~w(plugin list --json)} => {"[]", 0},
      {"claude", ~w(mcp list)} =>
        {"""
         hexpm: https://hexpm-mcp.fly.dev/mcp (HTTP) - ✔ Connected
         other: npx other - ✔ Connected
         """, 0},
      {"codex", ~w(plugin marketplace list)} => {~s({"marketplaces": []}), 0},
      {"codex", ~w(mcp list --json)} =>
        {JSON.encode!([
           %{
             "name" => "hex",
             "transport" => %{
               "command" => "/opt/bin/hexpm_mcp",
               "args" => ["--transport", "stdio"]
             }
           },
           %{"name" => "docs", "transport" => %{"url" => "https://example.com/mcp"}}
         ]), 0}
    }
  end

  defp steps(report), do: Enum.map(report.steps, &{&1.command, &1.result})

  defp read_json(dir, path), do: dir |> Path.join(path) |> File.read!() |> JSON.decode!()

  defp flush do
    receive do
      {:ran, _, _} -> flush()
    after
      0 -> :ok
    end
  end
end
