defmodule HexpmMcp.MCP.Prompts.MigrationGuide do
  @moduledoc "Guide for migrating from one hex.pm package to another"

  use MCP.Prompt.Simple,
    name: "migration_guide",
    description: "Guide a migration from one hex.pm package to another"

  argument("from", description: "Package to migrate from", required: true)
  argument("to", description: "Package to migrate to", required: true)

  @impl true
  def render(%{"from" => from, "to" => to}, _context) do
    {:ok,
     """
     Help me migrate from the hex.pm package "#{from}" to "#{to}".

     Use `info` and `docs` on both packages to understand their APIs.
     Use `compare` to see how they differ in stats and health.

     Provide:
     - Why migrate: Key differences and advantages of the target package
     - API mapping: How concepts/functions map between the two
     - Breaking changes: What will need to change in existing code
     - Migration steps: Ordered list of changes to make
     - Testing strategy: How to verify the migration works
     """}
  end
end
