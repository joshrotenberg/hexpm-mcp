//! Get dependencies tool

use std::sync::Arc;

use tower_mcp::{
    CallToolResult, ResultExt, Tool, ToolBuilder,
    extract::{Json, State},
};

use crate::state::AppState;
use crate::tools::PackageVersionInput;

/// Build the `get_dependencies` tool.
pub fn build(state: Arc<AppState>) -> Tool {
    ToolBuilder::new("get_dependencies")
        .title("Get Dependencies")
        .description(
            "Get the dependencies (requirements) of a hex.pm package. \
             Optionally specify a version; defaults to the latest version.",
        )
        .read_only()
        .idempotent()
        .extractor_handler(
            state,
            |State(state): State<Arc<AppState>>,
             Json(input): Json<PackageVersionInput>| async move {
                // Resolve version: use provided or fetch latest
                let version = match input.version {
                    Some(v) => v,
                    None => {
                        let pkg = state
                            .client
                            .get_package(&input.name)
                            .await
                            .tool_context("hex.pm API error")?;
                        pkg.latest_stable_version
                            .or(pkg.latest_version)
                            .unwrap_or_else(|| "latest".to_string())
                    }
                };

                let deps = state
                    .client
                    .get_dependencies(&input.name, &version)
                    .await
                    .tool_context("hex.pm API error")?;

                if deps.is_empty() {
                    return Ok(CallToolResult::text(format!(
                        "# {} v{}\n\nNo dependencies.",
                        input.name, version
                    )));
                }

                let mut output = format!(
                    "# {} v{} - {} dependencies\n\n",
                    input.name,
                    version,
                    deps.len()
                );

                let mut deps: Vec<_> = deps.iter().collect();
                deps.sort_by_key(|(name, _)| *name);

                for (name, req) in &deps {
                    let optional = if req.optional { " (optional)" } else { "" };
                    output.push_str(&format!(
                        "- **{}** `{}`{}\n",
                        name, req.requirement, optional
                    ));
                }

                Ok(CallToolResult::text(output))
            },
        )
        .build()
}
