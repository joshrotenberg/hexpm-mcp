defmodule HexpmMcp.Types do
  @moduledoc """
  Response structs for hex.pm API data.
  """

  defmodule Package do
    @moduledoc false
    defstruct [
      :name,
      :url,
      :html_url,
      :docs_html_url,
      :latest_version,
      :latest_stable_version,
      :inserted_at,
      :updated_at,
      :repository,
      meta: %{},
      downloads: %{},
      releases: [],
      owners: [],
      retirements: %{}
    ]
  end

  defmodule Release do
    @moduledoc false
    defstruct [
      :version,
      :url,
      :html_url,
      :docs_html_url,
      :has_docs,
      :downloads,
      :inserted_at,
      :updated_at,
      :checksum,
      publisher: %{},
      meta: %{},
      requirements: %{},
      retirement: nil
    ]
  end

  defmodule Owner do
    @moduledoc false
    defstruct [:username, :email, :url]
  end

  @doc """
  Parse a package response from the hex.pm API.
  """
  def parse_package(data) when is_map(data) do
    %Package{
      name: data["name"],
      url: data["url"],
      html_url: data["html_url"],
      docs_html_url: data["docs_html_url"],
      latest_version: data["latest_version"],
      latest_stable_version: data["latest_stable_version"],
      inserted_at: data["inserted_at"],
      updated_at: data["updated_at"],
      repository: data["repository"],
      meta: data["meta"] || %{},
      downloads: data["downloads"] || %{},
      releases: data["releases"] || [],
      owners: parse_owners(data["owners"] || []),
      retirements: data["retirements"] || %{}
    }
  end

  @doc """
  Parse a release response from the hex.pm API.
  """
  def parse_release(data) when is_map(data) do
    %Release{
      version: data["version"],
      url: data["url"],
      html_url: data["html_url"],
      docs_html_url: data["docs_html_url"],
      has_docs: data["has_docs"],
      downloads: data["downloads"],
      inserted_at: data["inserted_at"],
      updated_at: data["updated_at"],
      checksum: data["checksum"],
      publisher: data["publisher"] || %{},
      meta: data["meta"] || %{},
      requirements: data["requirements"] || %{},
      retirement: data["retirement"]
    }
  end

  @doc """
  Parse a list of owners from the hex.pm API.
  """
  def parse_owners(owners) when is_list(owners) do
    Enum.map(owners, fn o ->
      %Owner{
        username: o["username"],
        email: o["email"],
        url: o["url"]
      }
    end)
  end
end
