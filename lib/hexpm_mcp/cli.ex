defmodule HexpmMcp.CLI do
  @moduledoc """
  Command-line interface for the server.

  The OTP application callback is the real entry point in every mode. Burrito
  boots the BEAM and hands control to the OTP application callback; it never
  calls a `main/1`, and the `main_module` release key is metadata only. So this
  module turns argv into configuration and lets `start/2` build the supervision
  tree from it.

  `Cheer.parse/3` is what makes that shape work. Unlike `Cheer.run/3` it
  resolves and validates argv without invoking a command handler, which is the
  right fit when arguments configure a long-running process rather than driving
  a unit of work.
  """

  use Cheer.Command

  # Kept in lockstep with mix.exs and resolved at compile time, matching
  # HexpmMcp.MCP.Server. There is no Mix at runtime in a release.
  @version Mix.Project.config()[:version]

  command "hexpm_mcp" do
    about("MCP server for hex.pm and hexdocs.pm")
    version(@version)
    parse_only()

    after_help("""
    The default transport depends on how the server was started: stdio for the
    standalone binary, http otherwise. Pass --transport to be explicit.

    The http transport serves MCP at /mcp, e.g. http://localhost:8765/mcp.
    """)

    option(:transport,
      type: :string,
      short: :t,
      choices: ["stdio", "http"],
      help: "Transport to serve on"
    )

    option(:port,
      type: :integer,
      short: :p,
      help: "Port for the http transport (default: 8765)"
    )
  end

  @doc """
  Resolve argv into the server configuration.

  Returns `{:serve, opts}` to start, `:handled` when Cheer already printed help
  or version, and `:usage_error` when it already printed a usage error.

  argv comes from `Cheer.argv/0` because a Burrito-wrapped binary does not
  populate `System.argv/0`; its arguments arrive through
  `Burrito.Util.Args.argv/0` instead. Reading the wrong one fails silently:
  every option falls through to its default and the server looks like it
  started fine while speaking the wrong protocol.
  """
  @spec parse() :: {:serve, keyword()} | :handled | :usage_error
  def parse do
    case Cheer.parse(__MODULE__, Cheer.argv(), prog: "hexpm_mcp") do
      {:ok, __MODULE__, args} -> {:serve, config(args)}
      :handled -> :handled
      {:error, :usage} -> :usage_error
    end
  end

  @doc """
  Turn parsed arguments into server configuration.

  A `nil` transport resolves to the runtime's default, and a `nil` port defers
  to app config, which `runtime.exs` populates from `HEXPM_MCP_PORT` in prod.
  """
  @spec config(map()) :: keyword()
  def config(args) do
    [transport: transport(args[:transport]), port: args[:port]]
  end

  defp transport(nil), do: default_transport()
  defp transport("stdio"), do: :stdio
  defp transport("http"), do: :http

  # A downloaded binary is a local MCP server, so stdio is the useful default
  # there. Everything else keeps the http default the Fly deployment relies on.
  defp default_transport do
    if standalone?(), do: :stdio, else: :http
  end

  # False under `mix run`, `iex -S mix`, and an ordinary assembled release,
  # which is what keeps those tools' argv from being read as our own.
  defp standalone? do
    Code.ensure_loaded?(Burrito.Util) and Burrito.Util.running_standalone?()
  end
end
