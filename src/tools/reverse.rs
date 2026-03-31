//! Get reverse dependencies tool

use std::sync::Arc;

use tower_mcp::{
    CallToolResult, ResultExt, Tool, ToolBuilder,
    extract::{Json, State},
};

use crate::state::{AppState, format_number};
use crate::tools::PackageInput;

/// Build the `get_reverse_dependencies` tool.
pub fn build(state: Arc<AppState>) -> Tool {
    ToolBuilder::new("get_reverse_dependencies")
        .title("Get Reverse Dependencies")
        .description(
            "Find packages that depend on a given hex.pm package, \
             with download counts.",
        )
        .read_only()
        .idempotent()
        .extractor_handler(
            state,
            |State(state): State<Arc<AppState>>, Json(input): Json<PackageInput>| async move {
                let page = state
                    .client
                    .get_reverse_dependencies(&input.name, None)
                    .await
                    .tool_context("hex.pm API error")?;

                let packages = page.packages.unwrap_or_default();

                if packages.is_empty() {
                    return Ok(CallToolResult::text(format!(
                        "No packages depend on '{}'.",
                        input.name
                    )));
                }

                let mut output = format!(
                    "# Packages that depend on {} ({} found)\n\n",
                    input.name,
                    packages.len()
                );

                for pkg in &packages {
                    let downloads = pkg
                        .downloads
                        .as_ref()
                        .and_then(|d| d.all)
                        .map(|n| format!(" ({}  downloads)", format_number(n)))
                        .unwrap_or_default();

                    let desc = pkg
                        .meta
                        .as_ref()
                        .and_then(|m| m.description.as_deref())
                        .unwrap_or("");

                    if desc.is_empty() {
                        output.push_str(&format!("- **{}**{}\n", pkg.name, downloads));
                    } else {
                        output.push_str(&format!(
                            "- **{}**{} - {}\n",
                            pkg.name,
                            downloads,
                            desc.lines().next().unwrap_or("")
                        ));
                    }
                }

                Ok(CallToolResult::text(output))
            },
        )
        .build()
}
