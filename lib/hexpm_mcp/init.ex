defmodule HexpmMcp.Init do
  @moduledoc """
  Install the bundled plugin into Claude Code and Codex.

  `install/2` builds a plan, writes a local marketplace holding the plugin and a
  copy of the binary, then registers that marketplace through each host's own
  CLI (`claude plugin ...`, `codex plugin ...`). Host configuration files are
  never edited directly, so install, update and removal stay with the hosts.

  The plugin tree under `priv/plugin/hexpm` is embedded at compile time. The
  binary carries it whatever a release does with `priv`, and the installed
  manifests get the application version, which the committed ones leave out.
  """

  # Burrito is an optional dependency; calls are guarded by Code.ensure_loaded?/1.
  alias Burrito.Util.Args

  @marketplace "hexpm-local"
  @plugin "hexpm"
  @plugin_id "#{@plugin}@#{@marketplace}"
  @marker ".hexpm-mcp-install.json"
  @version Mix.Project.config()[:version]
  @host_timeout 120_000

  @plugin_root Path.expand("../../priv/plugin/hexpm", __DIR__)

  @plugin_paths @plugin_root
                |> Path.join("**")
                |> Path.wildcard(match_dot: true)
                |> Enum.filter(&File.regular?/1)
                |> Enum.sort()

  for path <- @plugin_paths, do: @external_resource(path)

  @manifests [".claude-plugin/plugin.json", ".codex-plugin/plugin.json"]

  # {relative path, contents, mode}. Manifests gain the version on the way in.
  @plugin_files (for path <- @plugin_paths do
                   relative = Path.relative_to(path, @plugin_root)
                   body = File.read!(path)

                   body =
                     if relative in @manifests,
                       do:
                         body |> JSON.decode!() |> Map.put("version", @version) |> JSON.encode!(),
                       else: body

                   mode =
                     if Bitwise.band(File.stat!(path).mode, 0o111) != 0, do: 0o755, else: 0o644

                   {relative, body, mode}
                 end)

  @description @plugin_root
               |> Path.join(".claude-plugin/plugin.json")
               |> File.read!()
               |> JSON.decode!()
               |> Map.fetch!("description")

  # Adding or removing a plugin file changes the listing, not any file this
  # module already tracks, so @external_resource alone would miss it.
  @doc false
  def __mix_recompile__?, do: plugin_paths() != @plugin_paths

  defp plugin_paths do
    @plugin_root
    |> Path.join("**")
    |> Path.wildcard(match_dot: true)
    |> Enum.filter(&File.regular?/1)
    |> Enum.sort()
  end

  @typedoc "Where init looks things up. `system_env/0` reads the real one."
  @type env :: %{
          home: String.t(),
          xdg_data_home: String.t() | nil,
          bin_path: String.t() | nil,
          find_executable: (String.t() -> String.t() | nil)
        }

  @typedoc "Runs a host command, returning its stdout and exit status."
  @type runner :: (String.t(), [String.t()] -> {String.t(), non_neg_integer() | :timeout})

  @doc """
  Run init from parsed `init` arguments, print the report, and return the exit
  status: 0 when planned or installed, 1 otherwise.
  """
  @spec run(map()) :: 0 | 1
  def run(args) do
    report = install(args)
    IO.write(render(report, args[:output] || "text"))
    if report.status in ["planned", "installed"], do: 0, else: 1
  end

  @doc """
  Plan and, unless `:dry_run` is set, apply. Returns the report as a map.

  Options: `:env` (see `t:env/0`) and `:runner` (see `t:runner/0`), both for
  tests.
  """
  @spec install(map(), keyword()) :: map()
  def install(args, opts \\ []) do
    env = Keyword.get_lazy(opts, :env, &system_env/0)
    runner = Keyword.get(opts, :runner, &run_host/2)
    plan = plan(args, env)

    cond do
      plan.issues != [] -> report(plan, "not_ready")
      args[:dry_run] -> report(plan, "planned")
      true -> apply_plan(plan, runner)
    end
  end

  @doc false
  @spec system_env() :: env()
  def system_env do
    %{
      home: System.user_home!(),
      xdg_data_home: System.get_env("XDG_DATA_HOME"),
      bin_path: burrito_bin_path(),
      find_executable: &System.find_executable/1
    }
  end

  # The wrapper binary, not the payload Burrito unpacks into its cache. The
  # cache is keyed by version, so a path into it breaks on the next upgrade.
  defp burrito_bin_path do
    if Code.ensure_loaded?(Args) do
      case Args.get_bin_path() do
        :not_in_burrito -> nil
        path -> path
      end
    end
  end

  # -- Plan --

  defp plan(args, env) do
    dir = install_dir(args, env)
    installed = Path.join([dir, "bin", "hexpm_mcp"])
    {source, binary_issues} = source_binary(args, env)
    {hosts, host_issues, skipped} = hosts(args, env)

    %{
      install_dir: dir,
      source_binary: source,
      installed_binary: installed,
      hosts: hosts,
      skipped_hosts: skipped,
      files: files(dir, installed),
      commands: Enum.flat_map(hosts, &commands(&1, dir)),
      issues: List.wrap(ownership_issue(dir)) ++ binary_issues ++ host_issues
    }
  end

  defp install_dir(%{install_dir: dir}, _env) when is_binary(dir), do: Path.expand(dir)

  defp install_dir(_args, %{xdg_data_home: xdg} = env) when is_binary(xdg) do
    # The XDG spec says to ignore a relative value.
    if Path.type(xdg) == :absolute,
      do: Path.join(xdg, "hexpm_mcp"),
      else: install_dir(%{}, %{env | xdg_data_home: nil})
  end

  defp install_dir(_args, %{home: home}), do: Path.join([home, ".local", "share", "hexpm_mcp"])

  defp source_binary(args, env) do
    case args[:binary] || env.bin_path do
      nil ->
        {nil,
         [
           "init installs the standalone hexpm_mcp binary; run it from that binary or pass --binary PATH"
         ]}

      path ->
        path = Path.expand(path)
        if File.regular?(path), do: {path, []}, else: {path, ["binary not found: #{path}"]}
    end
  end

  # With the default `both`, a host that is not installed is skipped. A host
  # asked for by name must be found.
  defp hosts(args, env) do
    requested = args[:host] || "both"
    names = if requested == "both", do: ["claude", "codex"], else: [requested]

    {found, missing} =
      names
      |> Enum.map(fn name -> {name, executable(name, args, env)} end)
      |> Enum.split_with(fn {_name, exe} -> exe != nil end)

    hosts = Enum.map(found, fn {name, exe} -> %{name: name, executable: exe} end)
    missing = Enum.map(missing, &elem(&1, 0))

    issues =
      cond do
        requested != "both" and missing != [] ->
          ["#{requested} CLI not found; install it or pass --#{requested}-bin"]

        hosts == [] ->
          ["neither claude nor codex was found; install one or pass --claude-bin or --codex-bin"]

        true ->
          []
      end

    {hosts, issues, if(requested == "both", do: missing, else: [])}
  end

  defp executable(name, args, env) do
    override = if name == "claude", do: args[:claude_bin], else: args[:codex_bin]

    cond do
      override == nil ->
        env.find_executable.(name)

      String.contains?(override, "/") ->
        if File.regular?(Path.expand(override)), do: Path.expand(override)

      true ->
        env.find_executable.(override)
    end
  end

  defp ownership_issue(dir) do
    cond do
      not File.exists?(dir) ->
        nil

      not File.dir?(dir) ->
        "#{dir} exists and is not a directory"

      File.ls!(dir) == [] ->
        nil

      managed?(dir) ->
        nil

      true ->
        "#{dir} is not empty and has no #{@marker}; pass --install-dir to use another directory"
    end
  end

  defp managed?(dir) do
    with {:ok, body} <- File.read(Path.join(dir, @marker)),
         {:ok, %{"managed_by" => "hexpm_mcp"}} <- JSON.decode(body) do
      true
    else
      _ -> false
    end
  end

  # The marker comes first, so a run that fails partway leaves a directory the
  # next run recognizes as its own.
  defp files(dir, installed) do
    plugin_dir = Path.join([dir, "plugins", @plugin])

    mcp = %{
      "mcpServers" => %{
        "hexpm" => %{
          "type" => "stdio",
          "command" => installed,
          "args" => ["--transport", "stdio"]
        }
      }
    }

    claude_marketplace = %{
      "name" => @marketplace,
      "owner" => %{"name" => "Josh Rotenberg"},
      "description" => "The hexpm plugin installed by hexpm_mcp init",
      "plugins" => [
        %{
          "name" => @plugin,
          "source" => "./plugins/#{@plugin}",
          "version" => @version,
          "description" => @description
        }
      ]
    }

    codex_marketplace = %{
      "name" => @marketplace,
      "interface" => %{"displayName" => "hexpm local"},
      "plugins" => [
        %{
          "name" => @plugin,
          "source" => %{"source" => "local", "path" => "./plugins/#{@plugin}"},
          "policy" => %{"installation" => "AVAILABLE", "authentication" => "ON_INSTALL"},
          "category" => "Developer Tools"
        }
      ]
    }

    marker = %{"managed_by" => "hexpm_mcp", "format_version" => 1, "version" => @version}

    [{Path.join(dir, @marker), JSON.encode!(marker), 0o644}] ++
      for(
        {relative, body, mode} <- @plugin_files,
        do: {Path.join(plugin_dir, relative), body, mode}
      ) ++
      [
        {Path.join(plugin_dir, ".mcp.json"), JSON.encode!(mcp), 0o644},
        {Path.join(dir, ".claude-plugin/marketplace.json"), JSON.encode!(claude_marketplace),
         0o644},
        {Path.join(dir, ".agents/plugins/marketplace.json"), JSON.encode!(codex_marketplace),
         0o644}
      ]
  end

  defp commands(%{name: "claude", executable: exe}, dir) do
    [
      {:inspect_marketplace, ~w(plugin marketplace list --json)},
      {:add_marketplace, ["plugin", "marketplace", "add", dir, "--scope", "user", "--json"]},
      {:refresh_marketplace, ["plugin", "marketplace", "update", @marketplace, "--json"]},
      {:inspect_plugins, ~w(plugin list --json)},
      {:install, ["plugin", "install", @plugin_id, "--scope", "user", "--json"]},
      {:update, ["plugin", "update", @plugin_id, "--scope", "user", "--json"]}
    ]
    |> Enum.map(fn {action, args} -> command("claude", exe, action, args) end)
  end

  # Codex reads a local marketplace root in place; its `upgrade` is for Git
  # marketplaces only, and `plugin add` refreshes an installed plugin.
  defp commands(%{name: "codex", executable: exe}, dir) do
    [
      {:inspect_marketplace, ~w(plugin marketplace list --json)},
      {:add_marketplace, ["plugin", "marketplace", "add", dir, "--json"]},
      {:install, ["plugin", "add", @plugin_id, "--json"]}
    ]
    |> Enum.map(fn {action, args} -> command("codex", exe, action, args) end)
  end

  defp command(host, exe, action, args),
    do: %{host: host, action: action, executable: exe, args: args}

  # -- Apply --

  defp apply_plan(plan, runner) do
    case materialize(plan) do
      :ok ->
        plan
        |> register(runner)
        |> then(fn {status, steps, error} ->
          plan
          |> report(status)
          |> Map.merge(%{steps: steps, error: error})
          |> Map.put(:existing_servers, existing_servers(plan, runner))
        end)

      {:error, message} ->
        plan |> report("partial_install") |> Map.put(:error, message)
    end
  end

  defp materialize(plan) do
    File.mkdir_p!(plan.install_dir)
    # Clear the plugin tree so a file dropped from a newer release goes too.
    File.rm_rf!(Path.join([plan.install_dir, "plugins", @plugin]))

    for {path, body, mode} <- plan.files, do: atomic_write!(path, body, mode)

    install_binary!(plan.source_binary, plan.installed_binary)
  rescue
    error in [File.Error, File.CopyError, File.RenameError] -> {:error, Exception.message(error)}
  end

  # Write beside the target and rename over it, so a reader never sees a
  # partial file and a running server keeps the inode it started from.
  defp atomic_write!(path, body, mode) do
    File.mkdir_p!(Path.dirname(path))
    tmp = "#{path}.tmp-#{System.unique_integer([:positive])}"
    File.write!(tmp, body)
    File.chmod!(tmp, mode)
    File.rename!(tmp, path)
  end

  defp install_binary!(source, installed) do
    unless same_file?(source, installed) do
      File.mkdir_p!(Path.dirname(installed))
      tmp = "#{installed}.tmp-#{System.unique_integer([:positive])}"
      File.cp!(source, tmp)
      File.chmod!(tmp, 0o755)
      File.rename!(tmp, installed)
    end

    :ok
  end

  defp same_file?(a, b) do
    with {:ok, %{major_device: dev, inode: inode}} <- File.stat(a),
         {:ok, %{major_device: ^dev, inode: ^inode}} <- File.stat(b) do
      true
    else
      _ -> false
    end
  end

  # Returns {status, steps, error}. Each step records what ran or why it was
  # skipped. The first failure stops the run; earlier steps stay applied.
  defp register(plan, runner) do
    plan.commands
    |> Enum.reduce_while({%{}, []}, fn command, {state, steps} ->
      if skip?(command, state) do
        {:cont, {state, [step(command, "skipped") | steps]}}
      else
        run_step(command, plan, runner, state, steps)
      end
    end)
    |> case do
      {:failed, steps, error} -> {"partial_install", Enum.reverse(steps), error}
      {_state, steps} -> {"installed", Enum.reverse(steps), nil}
    end
  end

  defp run_step(command, plan, runner, state, steps) do
    with {:ok, output} <- run_command(command, runner),
         {:ok, state} <- observe(command, output, plan, state) do
      {:cont, {state, [step(command, "ok") | steps]}}
    else
      {:error, message} ->
        {:halt, {:failed, [step(command, "failed") | steps], "#{label(command)}: #{message}"}}
    end
  end

  defp skip?(%{host: host, action: action}, state) do
    registered = get_in(state, [host, :marketplace]) == true
    installed = get_in(state, [host, :plugin]) == true

    case action do
      :add_marketplace -> registered
      :refresh_marketplace -> not registered
      :install -> host == "claude" and installed
      :update -> not installed
      _ -> false
    end
  end

  # stderr is not captured. It reaches the terminal, and stdout stays clean for
  # the --json listings.
  defp run_host(executable, args) do
    task =
      Task.async(fn ->
        try do
          System.cmd(executable, args)
        rescue
          error -> {Exception.message(error), 127}
        end
      end)

    case Task.yield(task, @host_timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, result} -> result
      {:exit, reason} -> {inspect(reason), 1}
      nil -> {"", :timeout}
    end
  end

  defp run_command(command, runner) do
    case runner.(command.executable, command.args) do
      {output, 0} -> {:ok, output}
      {_output, :timeout} -> {:error, "timed out after #{div(@host_timeout, 1000)}s"}
      {output, status} -> {:error, "exited #{status}: #{String.trim(output)}"}
    end
  end

  defp observe(%{action: :inspect_marketplace, host: host}, output, plan, state) do
    with {:ok, present} <- marketplace_registered(host, output, plan.install_dir) do
      {:ok, put_in(state, [Access.key(host, %{}), :marketplace], present)}
    end
  end

  defp observe(%{action: :inspect_plugins, host: host}, output, _plan, state) do
    with {:ok, present} <- plugin_installed(output) do
      {:ok, put_in(state, [Access.key(host, %{}), :plugin], present)}
    end
  end

  defp observe(_command, _output, _plan, state), do: {:ok, state}

  defp marketplace_registered(host, output, dir) do
    with {:ok, decoded} <- decode(output, "marketplace listing"),
         {:ok, entries} <- marketplace_entries(host, decoded) do
      case Enum.filter(entries, &(&1["name"] == @marketplace)) do
        [] -> {:ok, false}
        [entry] -> check_marketplace(host, entry, dir)
        _ -> {:error, "more than one #{@marketplace} marketplace is registered"}
      end
    end
  end

  defp marketplace_entries("claude", list) when is_list(list), do: {:ok, list}
  defp marketplace_entries("codex", %{"marketplaces" => list}) when is_list(list), do: {:ok, list}
  defp marketplace_entries(_host, _decoded), do: {:error, "unrecognized marketplace listing"}

  defp check_marketplace(host, entry, dir) do
    root = if host == "claude", do: entry["path"], else: entry["root"]

    cond do
      host == "claude" and entry["source"] != "directory" ->
        {:error,
         "#{@marketplace} is registered from a #{inspect(entry["source"])} source, not this directory"}

      is_binary(root) and same_file?(root, dir) ->
        {:ok, true}

      true ->
        {:error,
         "#{@marketplace} is registered at #{inspect(root)}; remove it from #{host} or pass --install-dir #{root}"}
    end
  end

  defp plugin_installed(output) do
    case decode(output, "plugin listing") do
      {:ok, list} when is_list(list) ->
        {:ok, Enum.any?(list, &(&1["id"] == @plugin_id and &1["scope"] == "user"))}

      {:ok, _} ->
        {:error, "unrecognized plugin listing"}

      error ->
        error
    end
  end

  defp decode(output, what) do
    case JSON.decode(output) do
      {:ok, decoded} -> {:ok, decoded}
      {:error, _} -> {:error, "#{what} was not JSON"}
    end
  end

  # -- Existing servers --

  # Report-only: a hexpm server configured by hand would give the agent a
  # second copy of every tool. `claude mcp list` has no JSON form and connects
  # to each server it lists, so this runs once, after install.
  defp existing_servers(plan, runner) do
    Enum.flat_map(plan.hosts, fn host ->
      case list_servers(host, runner) do
        {:ok, servers} -> Enum.map(servers, &Map.put(&1, :host, host.name))
        :error -> [%{host: host.name, name: nil, target: "could not list MCP servers"}]
      end
    end)
    |> Enum.reject(&(&1.target =~ plan.installed_binary))
  end

  defp list_servers(%{name: "claude", executable: exe}, runner) do
    case runner.(exe, ["mcp", "list"]) do
      {output, 0} -> {:ok, parse_claude_servers(output)}
      _ -> :error
    end
  end

  defp list_servers(%{name: "codex", executable: exe}, runner) do
    with {output, 0} <- runner.(exe, ["mcp", "list", "--json"]),
         {:ok, list} when is_list(list) <- JSON.decode(output) do
      servers =
        for server <- list,
            target = codex_target(server["transport"]),
            hexpm?(server["name"], target),
            do: %{name: server["name"], target: target}

      {:ok, servers}
    else
      _ -> :error
    end
  end

  # Lines read `name: target - status`. A name cannot hold a colon, so plugin
  # servers (`plugin:<plugin>:<server>: ...`), this one included, never match.
  @doc false
  def parse_claude_servers(output) do
    for line <- String.split(output, "\n"),
        [_, name, target] <- [Regex.run(~r/^([^\s:][^:]*): (.+?)(?: - .*)?$/, line)],
        hexpm?(name, target),
        do: %{name: name, target: target}
  end

  defp codex_target(%{"url" => url}) when is_binary(url), do: url

  defp codex_target(%{"command" => command} = transport) when is_binary(command),
    do: Enum.join([command | transport["args"] || []], " ")

  defp codex_target(_transport), do: ""

  defp hexpm?(name, target), do: "#{name} #{target}" =~ ~r/hexpm/i

  # -- Report --

  defp report(plan, status) do
    %{
      status: status,
      version: @version,
      install_dir: plan.install_dir,
      binary: %{source: plan.source_binary, installed: plan.installed_binary},
      hosts: plan.hosts,
      skipped_hosts: plan.skipped_hosts,
      files:
        Enum.map(plan.files, fn {path, _, _} -> Path.relative_to(path, plan.install_dir) end),
      commands: Enum.map(plan.commands, &command_line/1),
      issues: plan.issues,
      steps: [],
      error: nil,
      existing_servers: []
    }
  end

  defp step(command, result), do: %{command: command_line(command), result: result}

  defp command_line(command),
    do: Enum.join([Path.basename(command.executable) | command.args], " ")

  defp label(command), do: command_line(command)

  @doc false
  def render(report, "json"), do: JSON.encode!(report) <> "\n"

  def render(report, _text) do
    [
      "hexpm_mcp #{report.version} init: #{report.status}\n",
      "Install dir: #{report.install_dir}\n",
      "Binary: #{report.binary.source || "(none)"} -> #{report.binary.installed}\n",
      "Hosts: #{Enum.map_join(report.hosts, ", ", & &1.name)}",
      skipped_line(report.skipped_hosts),
      "\n",
      section("Issues", report.issues),
      section(
        "Commands",
        if(report.steps == [], do: report.commands, else: step_lines(report.steps))
      ),
      if(report.error, do: "Error: #{report.error}\n", else: ""),
      section(
        "MCP servers that look like a hexpm entry configured by hand (the plugin adds its own)",
        Enum.map(report.existing_servers, &"#{&1.host}: #{&1.name}: #{&1.target}")
      ),
      footer(report.status)
    ]
  end

  defp skipped_line([]), do: ""
  defp skipped_line(skipped), do: " (not found, skipped: #{Enum.join(skipped, ", ")})"

  defp section(_title, []), do: ""
  defp section(title, lines), do: ["#{title}:\n", Enum.map(lines, &"  #{&1}\n")]

  defp step_lines(steps), do: Enum.map(steps, &"#{&1.command} [#{&1.result}]")

  defp footer("planned"), do: "Dry run: nothing was written and no host was started.\n"

  defp footer("installed"),
    do: "Reload plugins or start a new session in each host to pick up the plugin.\n"

  defp footer(_status), do: ""
end
