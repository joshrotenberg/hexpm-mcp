defmodule HexpmMcp.MCP.StdioLifecycleTest do
  use ExUnit.Case, async: true

  @moduletag :tmp_dir

  @application """
  System.argv(["--transport", "stdio"])
  {:ok, _applications} = Application.ensure_all_started(:hexpm_mcp)
  Process.sleep(:infinity)
  """

  test "the actual application exits cleanly when stdin is already at EOF", %{tmp_dir: dir} do
    assert {0, "", ""} = subprocess(dir, "", @application)
  end

  test "the actual application drains a literal discovery request before EOF", %{tmp_dir: dir} do
    request = %{
      "jsonrpc" => "2.0",
      "id" => "eof-discover",
      "method" => "server/discover",
      "params" => %{
        "_meta" => %{
          "io.modelcontextprotocol/protocolVersion" => "2026-07-28",
          "io.modelcontextprotocol/clientCapabilities" => %{}
        }
      }
    }

    assert {0, output, ""} = subprocess(dir, JSON.encode!(request) <> "\n", @application)
    assert [line] = String.split(output, "\n", trim: true)

    assert %{"id" => "eof-discover", "jsonrpc" => "2.0", "result" => result} =
             JSON.decode!(line)

    assert result["supportedVersions"] == ["2026-07-28", "2025-11-25", "2025-06-18"]
    assert get_in(result, ["_meta", "io.modelcontextprotocol/serverInfo", "name"]) == "hexpm-mcp"
  end

  # A client waits for this result before its next message, so the input holds
  # initialize alone.
  test "the actual application negotiates an initialize-era version over stdio", %{
    tmp_dir: dir
  } do
    request = %{
      "jsonrpc" => "2.0",
      "id" => "legacy-initialize",
      "method" => "initialize",
      "params" => %{
        "protocolVersion" => "2025-06-18",
        "capabilities" => %{},
        "clientInfo" => %{"name" => "initialize-era", "version" => "1"}
      }
    }

    assert {0, output, ""} = subprocess(dir, JSON.encode!(request) <> "\n", @application)
    assert [line] = String.split(output, "\n", trim: true)

    assert %{"id" => "legacy-initialize", "result" => result} = JSON.decode!(line)
    assert result["protocolVersion"] == "2025-06-18"
    assert result["serverInfo"]["name"] == "hexpm-mcp"
  end

  test "a transport startup failure reports stderr and exits nonzero", %{tmp_dir: dir} do
    program = """
    true = Process.register(self(), :occupied_stdio)
    runtime = HexpmMcp.MCP.Server.runtime()

    {:ok, _supervisor} =
      Supervisor.start_link(
        [{HexpmMcp.MCP.StdioLifecycle, runtime: runtime, name: :occupied_stdio}],
        strategy: :one_for_one
      )

    Process.sleep(:infinity)
    """

    assert {1, "", errors} = subprocess(dir, "", program)
    assert errors =~ "hexpm-mcp stdio failed:"
    assert errors =~ "already_started"
  end

  test "a serving exception also exits nonzero instead of leaving the supervisor running", %{
    tmp_dir: dir
  } do
    program = """
    {:ok, _supervisor} =
      Supervisor.start_link(
        [{HexpmMcp.MCP.StdioLifecycle, runtime: :invalid_runtime}],
        strategy: :one_for_one
      )

    Process.sleep(:infinity)
    """

    assert {1, "", errors} = subprocess(dir, "", program)
    assert errors =~ "hexpm-mcp stdio failed:"
    assert errors =~ "FunctionClauseError"
  end

  defp subprocess(dir, input, program) do
    input_path = Path.join(dir, "stdin")
    error_path = Path.join(dir, "stderr")
    File.write!(input_path, input)

    shell = System.find_executable("sh") || flunk("sh executable was not found")
    elixir = System.find_executable("elixir") || flunk("elixir executable was not found")
    code_paths = Enum.flat_map(:code.get_path(), &["-pa", List.to_string(&1)])

    command = ~S(input=$1; errors=$2; shift 2; exec "$@" < "$input" 2> "$errors")

    args =
      ["-c", command, "hexpm-stdio-test", input_path, error_path, elixir, "--erl", "+S 2:2"] ++
        code_paths ++ ["-e", program]

    port =
      Port.open({:spawn_executable, shell}, [
        :binary,
        :exit_status,
        :use_stdio,
        :eof,
        {:args, args}
      ])

    try do
      deadline = System.monotonic_time(:millisecond) + 15_000
      {status, output} = receive_exit(port, deadline, [])
      {status, output, File.read!(error_path)}
    after
      close_subprocess(port)
    end
  end

  defp receive_exit(port, deadline, output) do
    remaining = max(deadline - System.monotonic_time(:millisecond), 0)

    receive do
      {^port, {:data, data}} ->
        receive_exit(port, deadline, [data | output])

      {^port, :eof} ->
        receive_exit(port, deadline, output)

      {^port, {:exit_status, status}} ->
        {status, output |> Enum.reverse() |> IO.iodata_to_binary()}
    after
      remaining -> flunk("stdio subprocess did not exit after EOF")
    end
  end

  defp close_subprocess(port) do
    case Port.info(port, :os_pid) do
      {:os_pid, pid} ->
        System.cmd("kill", ["-TERM", Integer.to_string(pid)], stderr_to_stdout: true)
        Port.close(port)

      nil ->
        :ok
    end
  end
end
