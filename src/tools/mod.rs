//! MCP tool definitions for hexpm-mcp.
//!
//! Each tool module exposes a `build(state: Arc<AppState>) -> Tool` function.

pub mod dependencies;
pub mod info;
pub mod release;
pub mod reverse;
pub mod search;

use schemars::JsonSchema;
use serde::Deserialize;

/// Common input for tools that operate on a single package.
#[derive(Debug, Deserialize, JsonSchema)]
pub struct PackageInput {
    /// Package name on hex.pm.
    pub name: String,
}

/// Common input for tools that operate on a specific release.
#[derive(Debug, Deserialize, JsonSchema)]
pub struct ReleaseInput {
    /// Package name on hex.pm.
    pub name: String,
    /// Release version (e.g. "1.8.5").
    pub version: String,
}

/// Common input for tools that accept an optional version.
#[derive(Debug, Deserialize, JsonSchema)]
pub struct PackageVersionInput {
    /// Package name on hex.pm.
    pub name: String,
    /// Optional version. Uses latest if not specified.
    #[serde(default)]
    pub version: Option<String>,
}

/// Common input for search operations.
#[derive(Debug, Deserialize, JsonSchema)]
pub struct SearchInput {
    /// Search query string.
    pub query: String,
    /// Page number (1-indexed).
    #[serde(default)]
    pub page: Option<u32>,
    /// Sort order: "name", "recent_downloads", "total_downloads", "inserted_at", "updated_at".
    #[serde(default)]
    pub sort: Option<String>,
}
