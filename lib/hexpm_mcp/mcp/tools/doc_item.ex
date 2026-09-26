defmodule HexpmMcp.MCP.Tools.DocItem do
  @moduledoc """
  Get full documentation for a specific module or function.
  """

  use Snodo.Tool.Simple,
    name: "doc_item",
    description: "Get documentation for a module or function"

  argument("name", :string, required: true, description: "Package name on hex.pm")
  argument("module", :string, required: true, description: "Module name (e.g. \"Plug.Conn\")")
  argument("version", :string, description: "Package version (defaults to latest)")

  @impl true
  def call(%{"name" => name, "module" => module} = args, _context) do
    version = Map.get(args, "version")

    case HexpmMcp.get_doc_item(name, module, version) do
      {:ok, content} ->
        {:ok, Snodo.Result.text(content)}

      {:error, :not_found} ->
        {:ok, Snodo.Result.error("Documentation for #{module} not found in '#{name}'.")}

      {:error, reason} ->
        {:ok, Snodo.Result.error("Failed to get doc item: #{inspect(reason)}")}
    end
  end
end
