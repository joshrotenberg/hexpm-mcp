defmodule HexpmMcp.MCP.Tools.DocItem do
  @moduledoc """
  Get full documentation for a specific module or function.
  """

  use MCP.Tool.Simple, name: "doc_item", description: "Get documentation for a module or function"

  argument("name", :string, required: true, description: "Package name on hex.pm")
  argument("module", :string, required: true, description: "Module name (e.g. \"Plug.Conn\")")
  argument("version", :string, description: "Package version (defaults to latest)")

  @impl true
  def call(%{"name" => name, "module" => module} = args, _context) do
    version = Map.get(args, "version")

    case HexpmMcp.get_doc_item(name, module, version) do
      {:ok, content} ->
        {:ok, MCP.Result.text(content)}

      {:error, :not_found} ->
        {:ok, MCP.Result.error("Documentation for #{module} not found in '#{name}'.")}

      {:error, reason} ->
        {:ok, MCP.Result.error("Failed to get doc item: #{inspect(reason)}")}
    end
  end
end
