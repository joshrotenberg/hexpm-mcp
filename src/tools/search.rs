//! Search packages tool

use std::sync::Arc;

use tower_mcp::{
    CallToolResult, ResultExt, Tool, ToolBuilder,
    extract::{Json, State},
};

use crate::state::{AppState, format_number};
use crate::tools::SearchInput;

/// Build the `search_packages` tool.
pub fn build(state: Arc<AppState>) -> Tool {
    ToolBuilder::new("search_packages")
        .title("Search Packages")
        .description(
            "Search for packages on hex.pm. Returns package names, descriptions, \
             download counts, and latest versions.",
        )
        .read_only()
        .idempotent()
        .extractor_handler(
            state,
            |State(state): State<Arc<AppState>>, Json(input): Json<SearchInput>| async move {
                let packages = state
                    .client
                    .search_packages(&input.query, input.page, input.sort.as_deref())
                    .await
                    .tool_context("hex.pm API error")?;

                if packages.is_empty() {
                    return Ok(CallToolResult::text(format!(
                        "No packages found matching '{}'.",
                        input.query
                    )));
                }

                let mut output = format!(
                    "Found {} packages matching '{}':\n\n",
                    packages.len(),
                    input.query
                );

                for (i, pkg) in packages.iter().enumerate() {
                    let version = pkg
                        .latest_stable_version
                        .as_deref()
                        .or(pkg.latest_version.as_deref())
                        .unwrap_or("?");

                    output.push_str(&format!("{}. **{}** v{}\n", i + 1, pkg.name, version));

                    if let Some(meta) = &pkg.meta
                        && let Some(desc) = &meta.description
                    {
                        output.push_str(&format!("   {}\n", desc.trim()));
                    }

                    if let Some(downloads) = &pkg.downloads {
                        let all = downloads.all.map(format_number).unwrap_or_default();
                        let recent = downloads.recent.map(format_number).unwrap_or_default();
                        output.push_str(&format!("   Downloads: {} | Recent: {}\n", all, recent));
                    }

                    output.push('\n');
                }

                Ok(CallToolResult::text(output))
            },
        )
        .build()
}
