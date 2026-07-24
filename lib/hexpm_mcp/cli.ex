defmodule HexpmMcp.CLI do
  @moduledoc """
  Command-line interface for the server.

  `HexpmMcp.Application.start/2` is the real entry point in every mode. Burrito
  boots the BEAM and hands control to the OTP application callback; it never
  calls a `main/1`, and the `main_module` release key is metadata only. So this
  module parses argv and returns the resulting configuration rather than doing
  any work itself, and `start/2` turns that into a supervision tree.

  `Cheer.run/3` is what makes that possible: unlike `Cheer.main/3` it returns
  instead of halting, so the parse result can drive `start/2`.
  """

  use Cheer.Command

  alias Burrito.Util.Args

  # Kept in lockstep with mix.exs and resolved at compile time, matching
  # HexpmMcp.MCP.Server. There is no Mix at runtime in a release.
  @version Mix.Project.config()[:version]

  command "hexpm_mcp" do
    about("MCP server for hex.pm and hexdocs.pm")
    version(@version)

    after_help("""
    The default transport depends on how the server was started: stdio for the
    standalone binary, http otherwise. Pass --transport to be explicit.
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

  @impl Cheer.Command
  def run(args, _raw) do
    {:serve, [transport: transport(args[:transport]), port: args[:port]]}
  end

  @doc """
  argv for the current runtime.

  A Burrito-wrapped binary does not populate `System.argv/0`; arguments arrive
  through `Burrito.Util.Args.argv/0` instead. Getting this wrong fails silently:
  every option falls through to its default and the server looks like it started
  fine while speaking the wrong protocol.

  See joshrotenberg/cheer#131, which would move this shim upstream.
  """
  @spec argv() :: [String.t()]
  def argv do
    if standalone?(), do: Args.argv(), else: System.argv()
  end

  @doc """
  Whether the server is running as a standalone Burrito binary.

  False under `mix run`, `iex -S mix`, and an ordinary assembled release, which
  is what keeps the argv of those tools from being read as our own.
  """
  @spec standalone?() :: boolean()
  def standalone? do
    Code.ensure_loaded?(Burrito.Util) and Burrito.Util.running_standalone?()
  end

  defp transport(nil), do: default_transport()
  defp transport("stdio"), do: :stdio
  defp transport("http"), do: :http

  # A downloaded binary is a local MCP server, so stdio is the useful default
  # there. Everything else keeps the http default the Fly deployment relies on.
  defp default_transport do
    if standalone?(), do: :stdio, else: :http
  end
end
