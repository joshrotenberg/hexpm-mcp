---
name: hexpm
description: Use when choosing, adding, upgrading or auditing Elixir or Erlang dependencies from Hex, or when writing code against a Hex package's API. Check health, advisories and releases, and read HexDocs for the version the project locks, through the hexpm MCP tools instead of recalling them.
---

# Hex dependencies with hexpm

The hexpm MCP server answers from hex.pm, HexDocs, OSV.dev and the Elixir
Toolbox at call time. Versions, release dates, owners, advisories and APIs all
change after training, so prefer the tools over memory for each of them.

## Before adding or recommending a dependency

1. `health` for maintenance status, release cadence, downloads, owner count and
   retired versions.
2. `audit_mix_deps` with that one dependency line, such as `{:req, "~> 0.6"}`,
   for the package's own advisories. `health` does not query OSV, and `audit`
   checks the package's dependencies rather than the package.
3. `audit` when the package brings in dependencies the project does not
   already have.
4. When the result is weak (stale, one owner, open advisories), look wider with
   `alternatives` or `toolbox_search`, then `compare` two to five candidates.

Report what the tools returned, with versions and dates, not a verdict alone.

## Upgrading

1. `upgrade_check` with the deps list from `mix.exs`. It flags major-version
   jumps.
2. For each upgrade, `release` and `dependencies` for the target version, and
   `versions` for the releases in between.
3. `audit_mix_deps` on the updated list before reporting the upgrade done.

## Writing code against a package

Read the API for the version in `mix.lock` instead of recalling it. Function
names, arities and options change between releases.

1. `docs` with that version for the module list.
2. `search_docs` to find a module or function by name.
3. `doc_item` for a module's full documentation.

## Auditing a project

`audit_mix_deps`, then `upgrade_check`, each with the deps list from `mix.exs`.

`audit_mix_deps` counts every advisory filed against a package, whatever the
version. Before calling a dependency vulnerable, check that the version in
`mix.lock` falls inside the advisory's affected range.
