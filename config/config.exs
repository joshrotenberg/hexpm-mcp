import Config

config :hexpm_mcp,
  port: 8765,
  rate_limit_ms: 1000,
  cache_ttl: 300,
  docs_cache_ttl: 3600

config :logger, :default_handler, level: :info

import_config "#{config_env()}.exs"
