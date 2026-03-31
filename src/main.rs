use std::sync::Arc;
use std::time::Duration;

use clap::{Parser, ValueEnum};
use hexpm_mcp::state::AppState;
use tower_mcp::{McpRouter, StdioTransport};

#[derive(Debug, Clone, Copy, ValueEnum)]
enum Transport {
    Stdio,
}

#[derive(Parser, Debug)]
#[command(name = "hexpm-mcp")]
#[command(about = "MCP server for querying hex.pm - the Elixir/Erlang package registry", long_about = None)]
struct Args {
    /// Transport to use
    #[arg(short, long, default_value = "stdio")]
    transport: Transport,

    /// Rate limit interval between hex.pm API calls (in milliseconds)
    #[arg(long, default_value = "1000")]
    rate_limit_ms: u64,

    /// Log level
    #[arg(short, long, default_value = "info")]
    log_level: String,
}

#[tokio::main]
async fn main() -> Result<(), tower_mcp::BoxError> {
    let args = Args::parse();

    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::from_default_env()
                .add_directive(format!("hexpm_mcp={}", args.log_level).parse()?)
                .add_directive(format!("tower_mcp={}", args.log_level).parse()?),
        )
        .with_writer(std::io::stderr)
        .init();

    tracing::info!(
        transport = ?args.transport,
        rate_limit_ms = args.rate_limit_ms,
        "Starting hexpm-mcp server"
    );

    let rate_limit = Duration::from_millis(args.rate_limit_ms);
    let state =
        Arc::new(AppState::new(rate_limit).map_err(|e| format!("Failed to create state: {e}"))?);

    let instructions = "MCP server for querying hex.pm - the Elixir/Erlang package registry.\n\n\
         Available tools:\n\
         - search_packages: Search for packages by name or keywords\n\
         - get_package_info: Get detailed package information\n\
         - get_package_versions: List all versions with retirement info";

    let router = McpRouter::new()
        .server_info("hexpm-mcp", env!("CARGO_PKG_VERSION"))
        .instructions(instructions)
        .tool(hexpm_mcp::tools::search::build(state.clone()))
        .tool(hexpm_mcp::tools::info::build(state.clone()))
        .tool(hexpm_mcp::tools::info::build_versions(state.clone()));

    match args.transport {
        Transport::Stdio => {
            tracing::info!("Serving over stdio");
            StdioTransport::new(router).run().await?;
        }
    }

    Ok(())
}
