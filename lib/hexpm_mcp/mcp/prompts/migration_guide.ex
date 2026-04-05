defmodule HexpmMcp.MCP.Prompts.MigrationGuide do
  @moduledoc "Guide for migrating from one hex.pm package to another"

  use Anubis.Server.Component, type: :prompt

  alias Anubis.Server.Response

  schema do
    field(:from, :string, required: true, description: "Package to migrate from")
    field(:to, :string, required: true, description: "Package to migrate to")
  end

  @impl true
  def get_messages(%{from: from, to: to}, frame) do
    response =
      Response.prompt()
      |> Response.user_message("""
      Help me migrate from the hex.pm package "#{from}" to "#{to}".

      Use get_package_info and get_package_docs on both packages to understand their APIs.
      Use compare_packages to see how they differ in stats and health.

      Provide:
      - Why migrate: Key differences and advantages of the target package
      - API mapping: How concepts/functions map between the two
      - Breaking changes: What will need to change in existing code
      - Migration steps: Ordered list of changes to make
      - Testing strategy: How to verify the migration works
      """)

    {:reply, response, frame}
  end
end
