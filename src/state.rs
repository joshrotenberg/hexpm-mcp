//! Shared application state for the MCP server.

use std::time::Duration;

use crate::client::{Error, HexClient};

/// Shared state for the hexpm-mcp server.
pub struct AppState {
    /// hex.pm API client.
    pub client: HexClient,
}

impl AppState {
    /// Create a new `AppState` with the given rate limit.
    pub fn new(rate_limit: Duration) -> Result<Self, Error> {
        let client = HexClient::new("hexpm-mcp", rate_limit)?;
        Ok(Self { client })
    }

    /// Create a new `AppState` with a custom base URL (for testing).
    pub fn with_base_url(base_url: &str) -> Result<Self, Error> {
        let client = HexClient::with_base_url("hexpm-mcp", Duration::ZERO, base_url)?;
        Ok(Self { client })
    }
}

/// Format a large number for display (e.g. 1_234_567 -> "1.2M").
pub fn format_number(n: u64) -> String {
    if n >= 1_000_000 {
        format!("{:.1}M", n as f64 / 1_000_000.0)
    } else if n >= 1_000 {
        format!("{:.1}K", n as f64 / 1_000.0)
    } else {
        n.to_string()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_format_number() {
        assert_eq!(format_number(0), "0");
        assert_eq!(format_number(999), "999");
        assert_eq!(format_number(1_000), "1.0K");
        assert_eq!(format_number(1_500), "1.5K");
        assert_eq!(format_number(999_999), "1000.0K");
        assert_eq!(format_number(1_000_000), "1.0M");
        assert_eq!(format_number(1_500_000), "1.5M");
    }
}
