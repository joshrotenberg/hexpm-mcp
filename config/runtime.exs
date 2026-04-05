import Config

if config_env() == :prod do
  config :hexpm_mcp,
    port: String.to_integer(System.get_env("HEXPM_MCP_PORT", "8765")),
    cache_ttl: String.to_integer(System.get_env("HEXPM_MCP_CACHE_TTL", "300")),
    docs_cache_ttl: String.to_integer(System.get_env("HEXPM_MCP_DOCS_CACHE_TTL", "3600"))
end
