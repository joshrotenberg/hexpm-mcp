defmodule HexpmMcp.CLITest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias HexpmMcp.CLI

  defp parse(argv), do: Cheer.parse(CLI, argv, prog: "hexpm_mcp")

  describe "parsing" do
    test "no arguments is valid and carries no options" do
      assert {:ok, CLI, args} = parse([])
      assert args[:transport] == nil
      assert args[:port] == nil
    end

    test "accepts both transports by long and short name" do
      assert {:ok, CLI, %{transport: "stdio"}} = parse(["--transport", "stdio"])
      assert {:ok, CLI, %{transport: "http"}} = parse(["-t", "http"])
    end

    test "coerces the port to an integer" do
      assert {:ok, CLI, %{port: 9000}} = parse(["--port", "9000"])
      assert {:ok, CLI, %{port: 9000}} = parse(["-p", "9000"])
    end

    test "rejects a transport outside the declared choices" do
      output = capture_io(fn -> assert parse(["--transport", "bogus"]) == {:error, :usage} end)

      assert output =~ "stdio"
      assert output =~ "http"
    end

    test "rejects a non-integer port" do
      capture_io(fn -> assert parse(["--port", "http"]) == {:error, :usage} end)
    end

    test "--version reports the application version, not Elixir's" do
      output = capture_io(fn -> assert parse(["--version"]) == :handled end)

      assert output =~ "hexpm_mcp"
      assert output =~ Mix.Project.config()[:version]
    end

    test "--help is handled without dispatching" do
      output = capture_io(fn -> assert parse(["--help"]) == :handled end)

      assert output =~ "--transport"
      assert output =~ "--port"
    end
  end

  describe "config/1" do
    test "maps transport strings to atoms" do
      assert CLI.config(%{transport: "stdio"})[:transport] == :stdio
      assert CLI.config(%{transport: "http"})[:transport] == :http
    end

    test "defaults to http when not running as a standalone binary" do
      # The test suite is never a Burrito binary, so this is the mix/release
      # default. The standalone default is :stdio.
      assert CLI.config(%{})[:transport] == :http
    end

    test "passes the port through, leaving nil to app config" do
      assert CLI.config(%{port: 9000})[:port] == 9000
      assert CLI.config(%{})[:port] == nil
    end
  end
end
