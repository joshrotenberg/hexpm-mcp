//! Get download stats tool

use std::sync::Arc;

use tower_mcp::{
    CallToolResult, ResultExt, Tool, ToolBuilder,
    extract::{Json, State},
};

use crate::state::{AppState, format_number};
use crate::tools::PackageInput;

/// Build the `get_downloads` tool.
pub fn build(state: Arc<AppState>) -> Tool {
    ToolBuilder::new("get_downloads")
        .title("Get Downloads")
        .description(
            "Get download statistics for a hex.pm package including \
             all-time, recent (90 days), weekly, and daily counts.",
        )
        .read_only()
        .idempotent()
        .extractor_handler(
            state,
            |State(state): State<Arc<AppState>>, Json(input): Json<PackageInput>| async move {
                let pkg = state
                    .client
                    .get_package(&input.name)
                    .await
                    .tool_context("hex.pm API error")?;

                let mut output = format!("# {} - Download Stats\n\n", pkg.name);

                if let Some(downloads) = &pkg.downloads {
                    if let Some(all) = downloads.all {
                        output.push_str(&format!("- All-time: {}\n", format_number(all)));
                    }
                    if let Some(recent) = downloads.recent {
                        output
                            .push_str(&format!("- Recent (90 days): {}\n", format_number(recent)));
                    }
                    if let Some(week) = downloads.week {
                        output.push_str(&format!("- This week: {}\n", format_number(week)));
                    }
                    if let Some(day) = downloads.day {
                        output.push_str(&format!("- Today: {}\n", format_number(day)));
                    }
                } else {
                    output.push_str("No download statistics available.\n");
                }

                Ok(CallToolResult::text(output))
            },
        )
        .build()
}
