//! Get release details tool

use std::sync::Arc;

use tower_mcp::{
    CallToolResult, ResultExt, Tool, ToolBuilder,
    extract::{Json, State},
};

use crate::state::{AppState, format_number};
use crate::tools::ReleaseInput;

/// Build the `get_release` tool.
pub fn build(state: Arc<AppState>) -> Tool {
    ToolBuilder::new("get_release")
        .title("Get Release")
        .description(
            "Get detailed information about a specific hex.pm package release including \
             version details, requirements (dependencies), publisher, retirement status, \
             build tools, and elixir version requirement.",
        )
        .read_only()
        .idempotent()
        .extractor_handler(
            state,
            |State(state): State<Arc<AppState>>, Json(input): Json<ReleaseInput>| async move {
                let release = state
                    .client
                    .get_release(&input.name, &input.version)
                    .await
                    .tool_context("hex.pm API error")?;

                let mut output = format!("# {} v{}\n\n", input.name, release.version);

                // Retirement (prominent)
                if let Some(retirement) = &release.retirement {
                    let reason = retirement.reason.as_deref().unwrap_or("unknown");
                    output.push_str(&format!("## RETIRED: {}\n\n", reason));
                    if let Some(msg) = &retirement.message {
                        output.push_str(&format!("{}\n\n", msg));
                    }
                }

                // Publisher
                if let Some(publisher) = &release.publisher {
                    output.push_str(&format!("Published by: **{}**\n", publisher.username));
                }

                // Dates
                if let Some(date) = release.inserted_at {
                    output.push_str(&format!("Published: {}\n", date.date_naive()));
                }
                if let Some(date) = release.updated_at {
                    output.push_str(&format!("Updated: {}\n", date.date_naive()));
                }

                // Downloads
                if let Some(downloads) = release.downloads {
                    output.push_str(&format!("Downloads: {}\n", format_number(downloads)));
                }

                // Docs
                if release.has_docs == Some(true) {
                    output.push_str("Docs: available");
                    if let Some(docs_url) = &release.docs_html_url {
                        output.push_str(&format!(" ({})", docs_url));
                    }
                    output.push('\n');
                }

                // Build metadata
                if let Some(meta) = &release.meta {
                    if let Some(elixir) = &meta.elixir {
                        output.push_str(&format!("\n## Elixir\n\n{}\n", elixir));
                    }
                    if let Some(tools) = &meta.build_tools
                        && !tools.is_empty()
                    {
                        output.push_str(&format!("\n## Build Tools\n\n{}\n", tools.join(", ")));
                    }
                }

                // Requirements (dependencies)
                let requirements = release.requirements.unwrap_or_default();
                if requirements.is_empty() {
                    output.push_str("\n## Dependencies\n\nNone\n");
                } else {
                    output.push_str(&format!("\n## Dependencies ({})\n\n", requirements.len()));
                    let mut deps: Vec<_> = requirements.iter().collect();
                    deps.sort_by_key(|(name, _)| *name);
                    for (name, req) in &deps {
                        let optional = if req.optional { " (optional)" } else { "" };
                        output.push_str(&format!(
                            "- **{}** `{}`{}\n",
                            name, req.requirement, optional
                        ));
                    }
                }

                // Links
                if let Some(url) = &release.html_url {
                    output.push_str(&format!("\n## Links\n\n- hex.pm: {}\n", url));
                }

                Ok(CallToolResult::text(output))
            },
        )
        .build()
}
