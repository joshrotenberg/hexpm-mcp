defmodule HexpmMcp.AuditWorkflow.Repo do
  @moduledoc "Application-owned Repo, started only by explicit durable workflow composition."
  use Ecto.Repo, otp_app: :hexpm_mcp, adapter: Ecto.Adapters.SQLite3
end
