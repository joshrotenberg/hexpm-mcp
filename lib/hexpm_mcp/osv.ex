defmodule HexpmMcp.OSV do
  @moduledoc """
  Client for querying the OSV.dev vulnerability database.
  """

  @osv_url "https://api.osv.dev/v1/query"

  @doc """
  Query OSV.dev for vulnerabilities affecting a hex package.
  """
  def query(package_name) do
    body = %{
      "package" => %{
        "name" => package_name,
        "ecosystem" => "Hex"
      }
    }

    case Req.post(url: osv_url(), json: body) do
      {:ok, %Req.Response{status: 200, body: %{"vulns" => vulns}}} when is_list(vulns) ->
        {:ok, vulns}

      {:ok, %Req.Response{status: 200, body: _}} ->
        {:ok, []}

      {:ok, %Req.Response{status: status}} ->
        {:error, {:osv_error, status}}

      {:error, reason} ->
        {:error, {:request_failed, reason}}
    end
  end

  @doc """
  Query OSV.dev for vulnerabilities affecting a specific version.
  """
  def query_version(package_name, version) do
    body = %{
      "package" => %{
        "name" => package_name,
        "ecosystem" => "Hex"
      },
      "version" => version
    }

    case Req.post(url: osv_url(), json: body) do
      {:ok, %Req.Response{status: 200, body: %{"vulns" => vulns}}} when is_list(vulns) ->
        {:ok, vulns}

      {:ok, %Req.Response{status: 200, body: _}} ->
        {:ok, []}

      {:ok, %Req.Response{status: status}} ->
        {:error, {:osv_error, status}}

      {:error, reason} ->
        {:error, {:request_failed, reason}}
    end
  end

  defp osv_url, do: Application.get_env(:hexpm_mcp, :osv_url, @osv_url)
end
