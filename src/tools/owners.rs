//! Get package owners tool

use std::sync::Arc;

use tower_mcp::{
    CallToolResult, ResultExt, Tool, ToolBuilder,
    extract::{Json, State},
};

use crate::state::AppState;
use crate::tools::PackageInput;

/// Build the `get_owners` tool.
pub fn build(state: Arc<AppState>) -> Tool {
    ToolBuilder::new("get_owners")
        .title("Get Owners")
        .description(
            "Get the list of owners/maintainers for a hex.pm package \
             with their usernames and email addresses.",
        )
        .read_only()
        .idempotent()
        .extractor_handler(
            state,
            |State(state): State<Arc<AppState>>, Json(input): Json<PackageInput>| async move {
                let owners = state
                    .client
                    .get_owners(&input.name)
                    .await
                    .tool_context("hex.pm API error")?;

                if owners.is_empty() {
                    return Ok(CallToolResult::text(format!(
                        "No owners found for '{}'.",
                        input.name
                    )));
                }

                let mut output = format!(
                    "# {} - {} owner{}\n\n",
                    input.name,
                    owners.len(),
                    if owners.len() == 1 { "" } else { "s" }
                );

                for owner in &owners {
                    output.push_str(&format!("- **{}**", owner.username));
                    if let Some(email) = &owner.email {
                        output.push_str(&format!(" ({})", email));
                    }
                    output.push('\n');
                }

                Ok(CallToolResult::text(output))
            },
        )
        .build()
}
