defmodule HexpmMcp.MCP.PackageCompletion do
  @moduledoc """
  Bounded package-name suggestions backed by the application's cached Hex client.

  One search page is fetched for a literal package-name prefix of 2–64 bytes.
  Search results are filtered because Hex searches more than package names.
  A full upstream page is conservatively marked as possibly incomplete; no
  global total is invented and no recursive API pagination happens while typing.
  """

  alias HexpmMcp.Client
  alias MCP.Result

  @spec complete(String.t()) :: {:ok, Result.t()} | {:error, MCP.Error.t()}
  def complete(prefix) do
    if byte_size(prefix) in 2..64 and Regex.match?(~r/\A[a-z0-9_]+\z/, prefix) do
      fetch(prefix)
    else
      {:ok, Result.completion([], has_more: false)}
    end
  end

  defp fetch(prefix) do
    case Client.search(prefix, sort: "name", page: 1) do
      {:ok, packages} ->
        names =
          packages
          |> Enum.map(& &1.name)
          |> Enum.filter(&String.starts_with?(&1, prefix))
          |> Enum.uniq()
          |> Enum.sort()
          |> Enum.take(100)

        {:ok, Result.completion(names, has_more: length(packages) >= 100)}

      {:error, _reason} ->
        {:error, MCP.Error.internal("Package suggestions are temporarily unavailable")}
    end
  end
end
