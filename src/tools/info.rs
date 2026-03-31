//! Get package info tool

use std::sync::Arc;

use tower_mcp::{
    CallToolResult, ResultExt, Tool, ToolBuilder,
    extract::{Json, State},
};

use crate::state::{AppState, format_number};
use crate::tools::PackageInput;

/// Build the `get_package_info` tool.
pub fn build(state: Arc<AppState>) -> Tool {
    ToolBuilder::new("get_package_info")
        .title("Get Package Info")
        .description(
            "Get detailed information about a hex.pm package including description, \
             licenses, download stats, latest version, links, and docs URL.",
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

                let mut output = format!("# {}\n\n", pkg.name);

                if let Some(meta) = &pkg.meta
                    && let Some(desc) = &meta.description
                {
                    output.push_str(&format!("{}\n\n", desc.trim()));
                }

                // Versions
                output.push_str("## Versions\n\n");
                if let Some(latest) = &pkg.latest_stable_version {
                    output.push_str(&format!("- Latest Stable: **{}**\n", latest));
                }
                if let Some(latest) = &pkg.latest_version
                    && pkg.latest_version != pkg.latest_stable_version
                {
                    output.push_str(&format!("- Latest: **{}**\n", latest));
                }

                // Downloads
                if let Some(downloads) = &pkg.downloads {
                    output.push_str("\n## Downloads\n\n");
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
                }

                // Dates
                if pkg.inserted_at.is_some() || pkg.updated_at.is_some() {
                    output.push_str("\n## Dates\n\n");
                    if let Some(created) = pkg.inserted_at {
                        output.push_str(&format!("- Created: {}\n", created.date_naive()));
                    }
                    if let Some(updated) = pkg.updated_at {
                        output.push_str(&format!("- Updated: {}\n", updated.date_naive()));
                    }
                }

                // Links
                if let Some(docs_url) = &pkg.docs_html_url {
                    output.push_str(&format!("\n## Links\n\n- Documentation: {}\n", docs_url));
                }
                if let Some(html_url) = &pkg.html_url {
                    output.push_str(&format!("- hex.pm: {}\n", html_url));
                }
                if let Some(meta) = &pkg.meta
                    && let Some(links) = &meta.links
                {
                    for (label, url) in links {
                        output.push_str(&format!("- {}: {}\n", label, url));
                    }
                }

                // Licenses
                if let Some(meta) = &pkg.meta {
                    if let Some(licenses) = &meta.licenses
                        && !licenses.is_empty()
                    {
                        output.push_str(&format!("\n## Licenses\n\n{}\n", licenses.join(", ")));
                    }

                    // Build tools
                    if let Some(tools) = &meta.build_tools
                        && !tools.is_empty()
                    {
                        output.push_str(&format!("\n## Build Tools\n\n{}\n", tools.join(", ")));
                    }

                    // Elixir version
                    if let Some(elixir) = &meta.elixir {
                        output.push_str(&format!("\n## Elixir\n\n{}\n", elixir));
                    }
                }

                Ok(CallToolResult::text(output))
            },
        )
        .build()
}

/// Build the `get_package_versions` tool.
pub fn build_versions(state: Arc<AppState>) -> Tool {
    ToolBuilder::new("get_package_versions")
        .title("Get Package Versions")
        .description(
            "List all versions of a hex.pm package with docs status, \
             publish date, and retirement information.",
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

                let releases = pkg.releases.unwrap_or_default();
                let retirements = pkg.retirements.unwrap_or_default();

                if releases.is_empty() {
                    return Ok(CallToolResult::text(format!(
                        "No versions found for '{}'.",
                        input.name
                    )));
                }

                let mut output = format!("# {} - {} versions\n\n", input.name, releases.len());

                for release in &releases {
                    let docs_icon = if release.has_docs == Some(true) {
                        "[docs]"
                    } else {
                        ""
                    };

                    let date = release
                        .inserted_at
                        .map(|d| d.date_naive().to_string())
                        .unwrap_or_default();

                    let retirement_info = retirements.get(&release.version);

                    if let Some(retirement) = retirement_info {
                        let reason = retirement.reason.as_deref().unwrap_or("unknown");
                        let msg = retirement
                            .message
                            .as_deref()
                            .map(|m| format!(" - {}", m))
                            .unwrap_or_default();
                        output.push_str(&format!(
                            "- **{}** {} {} [RETIRED: {}{}]\n",
                            release.version, date, docs_icon, reason, msg
                        ));
                    } else {
                        output.push_str(&format!(
                            "- **{}** {} {}\n",
                            release.version, date, docs_icon
                        ));
                    }
                }

                Ok(CallToolResult::text(output))
            },
        )
        .build()
}
