defmodule HexpmMcp.Test.Fixtures do
  @moduledoc """
  Shared test fixtures for hex.pm API responses.
  """

  def package_json(name, opts \\ []) do
    %{
      "name" => name,
      "latest_version" => Keyword.get(opts, :version, "1.0.0"),
      "latest_stable_version" => Keyword.get(opts, :stable_version, "1.0.0"),
      "html_url" => "https://hex.pm/packages/#{name}",
      "docs_html_url" => "https://hexdocs.pm/#{name}/",
      "inserted_at" => Keyword.get(opts, :inserted_at, "2020-01-01T00:00:00Z"),
      "updated_at" => Keyword.get(opts, :updated_at, "2025-01-01T00:00:00Z"),
      "meta" => %{
        "description" => Keyword.get(opts, :description, "A test package"),
        "licenses" => Keyword.get(opts, :licenses, ["MIT"]),
        "links" => Keyword.get(opts, :links, %{"GitHub" => "https://github.com/test/#{name}"}),
        "build_tools" => Keyword.get(opts, :build_tools, ["mix"]),
        "elixir" => Keyword.get(opts, :elixir, "~> 1.14")
      },
      "downloads" => %{
        "all" => Keyword.get(opts, :downloads_all, 100_000),
        "recent" => Keyword.get(opts, :downloads_recent, 10_000),
        "week" => Keyword.get(opts, :downloads_week, 2_000),
        "day" => Keyword.get(opts, :downloads_day, 300)
      },
      "releases" =>
        Keyword.get(opts, :releases, [
          %{
            "version" => "1.0.0",
            "inserted_at" => "2025-01-01T00:00:00Z",
            "has_docs" => true
          },
          %{
            "version" => "0.9.0",
            "inserted_at" => "2024-06-01T00:00:00Z",
            "has_docs" => true
          }
        ]),
      "retirements" => Keyword.get(opts, :retirements, %{})
    }
  end

  def release_json(version, opts \\ []) do
    %{
      "version" => version,
      "has_docs" => Keyword.get(opts, :has_docs, true),
      "downloads" => Keyword.get(opts, :downloads, 5_000),
      "inserted_at" => Keyword.get(opts, :inserted_at, "2025-01-01T00:00:00Z"),
      "updated_at" => Keyword.get(opts, :updated_at, "2025-01-01T00:00:00Z"),
      "publisher" => %{"username" => Keyword.get(opts, :publisher, "testuser")},
      "meta" => %{
        "build_tools" => Keyword.get(opts, :build_tools, ["mix"]),
        "elixir" => Keyword.get(opts, :elixir, "~> 1.14")
      },
      "requirements" => Keyword.get(opts, :requirements, %{}),
      "retirement" => Keyword.get(opts, :retirement, nil)
    }
  end

  def owner_json(username, opts \\ []) do
    %{
      "username" => username,
      "email" => Keyword.get(opts, :email, "#{username}@example.com"),
      "url" => "https://hex.pm/users/#{username}"
    }
  end

  def respond_json(conn, status, body) do
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.resp(status, Jason.encode!(body))
  end
end
