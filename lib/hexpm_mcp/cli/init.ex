defmodule HexpmMcp.CLI.Init do
  @moduledoc """
  The `init` subcommand: install the bundled plugin into Claude Code and Codex.

  Parse-only like the root command. `HexpmMcp.Application` hands the parsed
  arguments to `HexpmMcp.Init.run/1` and halts with its exit code before any
  server starts.
  """

  use Cheer.Command

  command "init" do
    about("Install the Claude Code and Codex plugin")
    parse_only()

    after_help("""
    Writes the plugin and a copy of this binary to a local marketplace, then
    registers it with each host through `claude plugin` and `codex plugin`. Host
    configuration files are never edited directly.

    --dry-run shows the files and host commands without writing anything or
    starting a host. Run init again after upgrading the binary, then reload
    plugins or start a new session in each host.
    """)

    option(:dry_run,
      type: :boolean,
      help: "Show the plan without writing files or starting a host"
    )

    option(:host,
      type: :string,
      choices: ["both", "claude", "codex"],
      default: "both",
      help: "Hosts to configure; both configures whichever are installed"
    )

    option(:install_dir,
      type: :string,
      value_name: "DIR",
      help:
        "Marketplace directory (default: $XDG_DATA_HOME/hexpm_mcp or ~/.local/share/hexpm_mcp)"
    )

    option(:binary,
      type: :string,
      value_name: "PATH",
      help: "hexpm_mcp binary to install (default: the running binary)"
    )

    option(:claude_bin, type: :string, value_name: "PATH", help: "Claude Code executable")
    option(:codex_bin, type: :string, value_name: "PATH", help: "Codex executable")

    option(:output,
      type: :string,
      choices: ["text", "json"],
      default: "text",
      help: "Report format"
    )
  end
end
