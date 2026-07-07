defmodule HexpmMcp.Toolbox do
  @moduledoc """
  Client for the Elixir Toolbox API (https://elixir-toolbox.dev).

  Elixir Toolbox is a curated discovery layer over hex.pm: a maintained
  taxonomy of groups and categories, trending packages, and search. The API
  is public, requires no authentication, and returns package objects enriched
  with GitHub/GitLab stats, a popularity score, and health flags.

  Responses are wrapped in a `{"data": ...}` envelope; each function unwraps it
  and returns parsed maps. Results are cached via `HexpmMcp.Cache`.
  """

  alias HexpmMcp.Cache

  @base_url "https://elixir-toolbox.dev/api/v1"
  @user_agent "hexpm-mcp"

  @doc """
  List all groups, each with its categories.
  """
  def groups do
    Cache.fetch({:toolbox_groups}, fn ->
      case get("/groups") do
        {:ok, data} when is_list(data) -> {:ok, Enum.map(data, &parse_group/1)}
        error -> error
      end
    end)
  end

  @doc """
  Get a single group by slug.
  """
  def group(slug) do
    Cache.fetch({:toolbox_group, slug}, fn ->
      case get("/groups/#{slug}") do
        {:ok, data} when is_map(data) -> {:ok, parse_group(data)}
        error -> error
      end
    end)
  end

  @doc """
  List curated projects in a category.

  ## Options

    * `:sort` - result ordering. The API recognizes `"name"` (alphabetical) and
      `"downloads"`, and falls back to popularity order for any other value.
  """
  def category_projects(group, category, opts \\ []) do
    params = maybe_put([], :sort, opts[:sort])

    Cache.fetch({:toolbox_category, group, category, opts}, fn ->
      case get("/groups/#{group}/#{category}/projects", params: params) do
        {:ok, data} when is_list(data) -> {:ok, Enum.map(data, &parse_project/1)}
        error -> error
      end
    end)
  end

  @doc """
  List trending projects.

  ## Options

    * `:limit` - maximum number of projects to return.
  """
  def trending(opts \\ []) do
    params = maybe_put([], :limit, opts[:limit])

    Cache.fetch({:toolbox_trending, opts}, fn ->
      case get("/trending", params: params) do
        {:ok, data} when is_list(data) -> {:ok, Enum.map(data, &parse_project/1)}
        error -> error
      end
    end)
  end

  @doc """
  Search packages by query string.
  """
  def search(query) do
    Cache.fetch({:toolbox_search, query}, fn ->
      case get("/search", params: [q: query]) do
        {:ok, data} when is_list(data) -> {:ok, Enum.map(data, &parse_project/1)}
        error -> error
      end
    end)
  end

  # ---------------------------------------------------------------------------
  # HTTP
  # ---------------------------------------------------------------------------

  defp get(path, opts \\ []) do
    req_opts =
      [
        url: base_url() <> path,
        headers: [{"user-agent", @user_agent}]
      ] ++ opts

    case Req.get(req_opts) do
      {:ok, %Req.Response{status: 200, body: %{"data" => data}}} ->
        {:ok, data}

      {:ok, %Req.Response{status: 200, body: _}} ->
        {:error, :unexpected_response}

      {:ok, %Req.Response{status: 404}} ->
        {:error, :not_found}

      {:ok, %Req.Response{status: 400}} ->
        {:error, :bad_request}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:api_error, status, body}}

      {:error, reason} ->
        {:error, {:request_failed, reason}}
    end
  end

  defp base_url, do: Application.get_env(:hexpm_mcp, :toolbox_url, @base_url)

  # ---------------------------------------------------------------------------
  # Parsing
  # ---------------------------------------------------------------------------

  defp parse_group(data) when is_map(data) do
    %{
      title: data["title"],
      slug: data["slug"],
      categories: Enum.map(data["categories"] || [], &parse_category/1)
    }
  end

  defp parse_category(data) when is_map(data) do
    %{
      name: data["name"],
      description: data["description"],
      slug: data["slug"]
    }
  end

  defp parse_project(data) when is_map(data) do
    %{
      name: data["name"],
      description: data["description"],
      latest_stable_version: data["latest_stable_version"],
      hex_url: data["hex_url"],
      docs_url: data["docs_url"],
      updated_at: data["updated_at"],
      downloads: data["downloads"] || %{},
      github: parse_repo(data["github"]),
      gitlab: parse_repo(data["gitlab"]),
      popularity: data["popularity"],
      health: data["health"] || []
    }
  end

  defp parse_repo(nil), do: nil

  defp parse_repo(repo) when is_map(repo) do
    %{
      name: repo["name"],
      stars: repo["stars"],
      forks: repo["forks"],
      open_issues: repo["open_issues"],
      pushed_at: repo["pushed_at"],
      archived: repo["archived"]
    }
  end

  defp maybe_put(keyword, _key, nil), do: keyword
  defp maybe_put(keyword, key, value), do: Keyword.put(keyword, key, value)
end
