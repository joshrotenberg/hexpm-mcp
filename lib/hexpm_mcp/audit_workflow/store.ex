defmodule HexpmMcp.AuditWorkflow.Store do
  @moduledoc "Authenticated tenant admission around the public SQLite Tasks store contract."
  @behaviour MCP.Extensions.Tasks.Store

  alias MCP.Context
  alias MCP.Extensions.Tasks.Store.SQLite

  @doc "Only trusted transport auth identifies the tenant; absent/blank tenants are rejected."
  def authenticated?(%Context{auth: %{"tenant" => tenant}}),
    do: is_binary(tenant) and String.trim(tenant) != ""

  def authenticated?(_context), do: false

  @doc false
  def scope(%Context{auth: %{"tenant" => tenant}}), do: %{"tenant" => tenant}

  @impl true
  def authorize(config, context, action) do
    if authenticated?(context),
      do: SQLite.authorize(config, context, action),
      else: {:error, :unauthorized}
  end

  @impl true
  defdelegate create(config, task, work, access), to: SQLite
  @impl true
  defdelegate get(config, id, access), to: SQLite
  @impl true
  defdelegate worker_snapshot(config, id, lease), to: SQLite
  @impl true
  defdelegate claim(config, id, owner, lease_ms), to: SQLite
  @impl true
  defdelegate claim_next(config, owner, lease_ms), to: SQLite
  @impl true
  defdelegate renew(config, lease, lease_ms), to: SQLite
  @impl true
  defdelegate release(config, lease), to: SQLite
  @impl true
  defdelegate reap(config), to: SQLite
  @impl true
  defdelegate transition(config, id, revision, event, authority), to: SQLite
end
