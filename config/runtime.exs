import Config

if config_env() == :prod do
  allowed_origin_hosts =
    "HEXPM_MCP_ALLOWED_ORIGIN_HOSTS"
    |> System.get_env("127.0.0.1,localhost,::1,hexpm-mcp.fly.dev")
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)

  config :hexpm_mcp,
    port: String.to_integer(System.get_env("HEXPM_MCP_PORT", "8765")),
    cache_ttl: String.to_integer(System.get_env("HEXPM_MCP_CACHE_TTL", "300")),
    docs_cache_ttl: String.to_integer(System.get_env("HEXPM_MCP_DOCS_CACHE_TTL", "3600")),
    allowed_origin_hosts: allowed_origin_hosts
end
