defmodule HexpmMcp.Client do
  @moduledoc """
  HTTP client for the hex.pm API.

  Wraps Req with rate limiting, user-agent headers, and response parsing.
  """

  alias HexpmMcp.{Cache, Types}

  @base_url "https://hex.pm/api"
  @user_agent "hexpm-mcp"

  @doc """
  Search for packages by query string.
  """
  def search(query, opts \\ []) do
    params =
      [search: query]
      |> maybe_put(:page, opts[:page])
      |> maybe_put(:sort, opts[:sort])

    Cache.fetch({:search, query, opts}, fn ->
      case get("/packages", params: params) do
        {:ok, packages} when is_list(packages) ->
          {:ok, Enum.map(packages, &Types.parse_package/1)}

        error ->
          error
      end
    end)
  end

  @doc """
  Get detailed package information.
  """
  def get_package(name) do
    Cache.fetch({:package, name}, fn ->
      case get("/packages/#{name}") do
        {:ok, data} -> {:ok, Types.parse_package(data)}
        error -> error
      end
    end)
  end

  @doc """
  Get a specific release of a package.
  """
  def get_release(name, version) do
    Cache.fetch({:release, name, version}, fn ->
      case get("/packages/#{name}/releases/#{version}") do
        {:ok, data} -> {:ok, Types.parse_release(data)}
        error -> error
      end
    end)
  end

  @doc """
  Get the owners of a package.
  """
  def get_owners(name) do
    Cache.fetch({:owners, name}, fn ->
      case get("/packages/#{name}/owners") do
        {:ok, data} when is_list(data) -> {:ok, Types.parse_owners(data)}
        error -> error
      end
    end)
  end

  @doc """
  Make a GET request to the hex.pm API.
  """
  def get(path, opts \\ []) do
    rate_limit()

    url = base_url() <> path

    req_opts =
      [
        url: url,
        headers: [{"user-agent", @user_agent}]
      ] ++ opts

    case Req.get(req_opts) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %Req.Response{status: 404}} ->
        {:error, :not_found}

      {:ok, %Req.Response{status: 429}} ->
        {:error, :rate_limited}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:api_error, status, body}}

      {:error, reason} ->
        {:error, {:request_failed, reason}}
    end
  end

  defp rate_limit do
    ms = Application.get_env(:hexpm_mcp, :rate_limit_ms, 1000)
    if ms > 0, do: Process.sleep(ms)
  end

  defp base_url do
    Application.get_env(:hexpm_mcp, :hex_api_url, @base_url)
  end

  defp maybe_put(keyword, _key, nil), do: keyword
  defp maybe_put(keyword, key, value), do: Keyword.put(keyword, key, value)
end
