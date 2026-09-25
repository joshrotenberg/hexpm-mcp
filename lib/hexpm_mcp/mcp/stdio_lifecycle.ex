defmodule HexpmMcp.MCP.StdioLifecycle do
  @moduledoc """
  Serves the CLI's stdio connection and exits with its transport outcome.

  The serving task owns the transport lifecycle through `Stdio.serve/2`,
  which installs its monitor before starting input. Immediate EOF therefore
  cannot race a separately started lifecycle monitor. EOF waits for admitted
  requests to finish before a clean exit.

  Transport failures are reported to stderr and exit with status 1. A consumed
  stdio stream cannot be reconnected by restarting a supervised child.
  """

  use Task, restart: :temporary

  alias MCP.Transport.Stdio

  @spec start_link(keyword()) :: {:ok, pid()}
  def start_link(opts) do
    Task.start_link(__MODULE__, :serve_and_halt, [opts])
  end

  @doc false
  @spec serve_and_halt(keyword()) :: no_return()
  def serve_and_halt(opts) do
    result =
      try do
        runtime = Keyword.fetch!(opts, :runtime)
        Stdio.serve(runtime, Keyword.delete(opts, :runtime))
      catch
        kind, reason -> {:error, Exception.format(kind, reason, __STACKTRACE__)}
      end

    case result do
      :ok ->
        System.halt(0)

      {:error, reason} ->
        message = if is_binary(reason), do: reason, else: inspect(reason)
        IO.puts(:stderr, "hexpm-mcp stdio failed: #{message}")
        System.halt(1)
    end
  end
end
