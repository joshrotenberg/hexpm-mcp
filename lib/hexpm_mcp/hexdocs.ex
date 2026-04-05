defmodule HexpmMcp.HexDocs do
  @moduledoc """
  Client for fetching and parsing hexdocs.pm content.

  HexDocs has no structured API. This module:
  1. Fetches the search-data JSON (used by the docs JS search)
  2. Falls back to scraping the sidebar HTML for module listings
  3. Converts individual module pages from HTML to markdown
  """

  alias HexpmMcp.Cache

  @base_url "https://hexdocs.pm"

  @doc """
  Get the README content for a package, converted to markdown.
  """
  def get_readme(name, version \\ nil) do
    url = docs_url(name, version, "readme.html")

    Cache.fetch({:readme, name, version}, docs_ttl(), fn ->
      case fetch_html(url) do
        {:ok, html} -> {:ok, html_to_markdown(html)}
        error -> error
      end
    end)
  end

  @doc """
  Get the module listing for a package (table of contents).
  """
  def get_modules(name, version \\ nil) do
    Cache.fetch({:modules, name, version}, docs_ttl(), fn ->
      case fetch_search_data(name, version) do
        {:ok, data} -> {:ok, parse_module_list(data)}
        {:error, _} -> fetch_sidebar_modules(name, version)
      end
    end)
  end

  defp parse_module_list(data) do
    data
    |> Enum.filter(fn item -> item["type"] in ["module", "behaviour", "protocol"] end)
    |> Enum.map(fn item ->
      %{name: item["title"], type: item["type"], doc: item["doc"] || ""}
    end)
    |> Enum.sort_by(& &1.name)
  end

  @doc """
  Get documentation for a specific module or function.
  """
  def get_doc_item(name, module, version \\ nil) do
    path = String.replace(module, ".", "/")

    Cache.fetch({:doc_item, name, module, version}, docs_ttl(), fn ->
      with {:error, _} <- fetch_doc_page(name, version, "#{module}.html") do
        fetch_doc_page(name, version, "#{path}.html")
      end
    end)
  end

  defp fetch_doc_page(name, version, page) do
    case fetch_html(docs_url(name, version, page)) do
      {:ok, html} -> {:ok, html_to_markdown(html)}
      error -> error
    end
  end

  @doc """
  Search within a package's documentation by name.
  """
  def search_docs(name, query, version \\ nil) do
    case fetch_search_data(name, version) do
      {:ok, data} ->
        query_down = String.downcase(query)

        results =
          data
          |> Enum.filter(fn item ->
            title = String.downcase(item["title"] || "")
            doc = String.downcase(item["doc"] || "")
            String.contains?(title, query_down) or String.contains?(doc, query_down)
          end)
          |> Enum.take(20)

        {:ok, results}

      error ->
        error
    end
  end

  # Fetch structured module/function data from the sidebar_items JS file.
  # HexDocs embeds all search data in a `sidebar_items-{hash}.js` file
  # that assigns to `sidebarNodes`. We parse out the JSON.
  defp fetch_search_data(name, version) do
    url = docs_url(name, version, "api-reference.html")

    with {:ok, html} <- fetch_html(url),
         {:ok, sidebar_url} <- extract_sidebar_url(html, name, version),
         {:ok, nodes} <- fetch_sidebar_nodes(sidebar_url) do
      {:ok, flatten_sidebar_nodes(nodes)}
    end
  end

  defp extract_sidebar_url(html, name, version) do
    case Floki.parse_document(html) do
      {:ok, doc} -> find_sidebar_script(doc, name, version)
      _ -> :error
    end
  end

  defp find_sidebar_script(doc, name, version) do
    doc
    |> Floki.find("script[src]")
    |> Enum.find_value(:error, fn {_, attrs, _} ->
      src = get_attr(attrs, "src")
      if String.contains?(src, "sidebar_items"), do: {:ok, absolute_url(src, name, version)}
    end)
  end

  defp absolute_url(src, name, version) do
    if String.starts_with?(src, "http"), do: src, else: docs_url(name, version, src)
  end

  defp fetch_sidebar_nodes(url) do
    case Req.get(url: url, headers: [{"user-agent", "hexpm-mcp"}]) do
      {:ok, %Req.Response{status: 200, body: body}} when is_binary(body) ->
        # Body is: sidebarNodes={...JSON...}
        json_str = String.replace(body, ~r/^sidebarNodes=/, "")

        case Jason.decode(json_str) do
          {:ok, data} -> {:ok, data}
          _ -> {:error, :search_data_unavailable}
        end

      _ ->
        {:error, :search_data_unavailable}
    end
  end

  # Flatten the sidebar nodes structure into a list of items with title/type/doc
  defp flatten_sidebar_nodes(data) when is_map(data) do
    modules = Map.get(data, "modules", [])
    extras = Map.get(data, "extras", [])

    module_items =
      Enum.map(modules, fn mod ->
        %{
          "title" => mod["title"] || mod["id"],
          "type" => classify_module(mod),
          "doc" => extract_node_doc(mod)
        }
      end)

    extra_items =
      Enum.map(extras, fn extra ->
        %{
          "title" => extra["title"] || extra["id"],
          "type" => "extra",
          "doc" => ""
        }
      end)

    module_items ++ extra_items
  end

  defp flatten_sidebar_nodes(_), do: []

  defp classify_module(%{"group" => "Behaviours"}), do: "behaviour"
  defp classify_module(%{"group" => "Protocols"}), do: "protocol"
  defp classify_module(_), do: "module"

  defp extract_node_doc(%{"nodeGroups" => groups}) when is_list(groups) do
    Enum.map_join(groups, ", ", fn g -> "#{g["name"]}: #{length(g["nodes"] || [])}" end)
  end

  defp extract_node_doc(_), do: ""

  defp get_attr(attrs, attr_name) do
    case List.keyfind(attrs, attr_name, 0) do
      {_, value} -> value
      nil -> ""
    end
  end

  defp fetch_sidebar_modules(name, version) do
    url = docs_url(name, version, "api-reference.html")

    with {:ok, html} <- fetch_html(url),
         {:ok, doc} <- Floki.parse_document(html) do
      modules =
        doc
        |> Floki.find("#modules .summary-row a, section.details-list .summary-row a")
        |> Enum.map(fn node ->
          %{
            name: Floki.text(node) |> String.trim(),
            type: "module",
            doc: ""
          }
        end)
        |> Enum.reject(fn m -> m.name == "" end)
        |> Enum.uniq_by(& &1.name)

      {:ok, modules}
    else
      _ -> {:error, :parse_failed}
    end
  end

  defp fetch_html(url) do
    case Req.get(url: url, headers: [{"user-agent", "hexpm-mcp"}]) do
      {:ok, %Req.Response{status: 200, body: body}} when is_binary(body) ->
        {:ok, body}

      {:ok, %Req.Response{status: 404}} ->
        {:error, :not_found}

      {:ok, %Req.Response{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, {:request_failed, reason}}
    end
  end

  @doc """
  Convert HTML content to a simplified markdown representation.
  """
  def html_to_markdown(html) when is_binary(html) do
    case Floki.parse_document(html) do
      {:ok, doc} ->
        # Try to find the main content area
        content =
          case Floki.find(doc, "#content .content-inner, .main-content, article") do
            [node | _] -> node
            [] -> doc
          end

        node_to_markdown(content)
        |> String.trim()

      _ ->
        # If parsing fails, strip tags as fallback
        html
        |> String.replace(~r/<[^>]+>/, " ")
        |> String.replace(~r/\s+/, " ")
        |> String.trim()
    end
  end

  defp node_to_markdown(nodes) when is_list(nodes) do
    Enum.map_join(nodes, "", &node_to_markdown/1)
  end

  defp node_to_markdown(text) when is_binary(text), do: text

  defp node_to_markdown({tag, _attrs, children}) when tag in ["h1"] do
    "\n# #{node_to_markdown(children) |> String.trim()}\n\n"
  end

  defp node_to_markdown({tag, _attrs, children}) when tag in ["h2"] do
    "\n## #{node_to_markdown(children) |> String.trim()}\n\n"
  end

  defp node_to_markdown({tag, _attrs, children}) when tag in ["h3"] do
    "\n### #{node_to_markdown(children) |> String.trim()}\n\n"
  end

  defp node_to_markdown({"p", _attrs, children}) do
    "#{node_to_markdown(children) |> String.trim()}\n\n"
  end

  defp node_to_markdown({"pre", _attrs, children}) do
    code = node_to_markdown(children) |> String.trim()
    "\n```\n#{code}\n```\n\n"
  end

  defp node_to_markdown({"code", _attrs, children}) do
    "`#{node_to_markdown(children)}`"
  end

  defp node_to_markdown({"strong", _attrs, children}) do
    "**#{node_to_markdown(children)}**"
  end

  defp node_to_markdown({"em", _attrs, children}) do
    "*#{node_to_markdown(children)}*"
  end

  defp node_to_markdown({"a", attrs, children}) do
    href = get_attr(attrs, "href")
    text = node_to_markdown(children)
    "[#{text}](#{href})"
  end

  defp node_to_markdown({"ul", _attrs, children}) do
    node_to_markdown(children) <> "\n"
  end

  defp node_to_markdown({"ol", _attrs, children}) do
    node_to_markdown(children) <> "\n"
  end

  defp node_to_markdown({"li", _attrs, children}) do
    "- #{node_to_markdown(children) |> String.trim()}\n"
  end

  defp node_to_markdown({"br", _attrs, _children}), do: "\n"

  defp node_to_markdown({"script", _attrs, _children}), do: ""
  defp node_to_markdown({"style", _attrs, _children}), do: ""

  defp node_to_markdown({_tag, _attrs, children}) do
    node_to_markdown(children)
  end

  defp node_to_markdown(_), do: ""

  # Build a hexdocs URL. When version is nil, omit it (hexdocs serves latest at /pkg/page.html).
  # When version is set, include it: /pkg/version/page.html
  defp docs_url(name, nil, page), do: "#{base_url()}/#{name}/#{page}"
  defp docs_url(name, version, page), do: "#{base_url()}/#{name}/#{version}/#{page}"

  defp base_url, do: Application.get_env(:hexpm_mcp, :hexdocs_url, @base_url)

  defp docs_ttl, do: Application.get_env(:hexpm_mcp, :docs_cache_ttl, 3600)
end
