import Config

config :hexpm_mcp,
  rate_limit_ms: 0,
  cache_ttl: 0,
  docs_cache_ttl: 0,
  transport: :none

config :logger, :default_handler, level: :warning
