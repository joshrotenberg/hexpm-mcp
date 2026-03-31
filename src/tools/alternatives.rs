//! Find alternatives tool

use std::sync::Arc;

use chrono::Utc;
use tower_mcp::{
    CallToolResult, ResultExt, Tool, ToolBuilder,
    extract::{Json, State},
};

use crate::state::{AppState, format_number};
use crate::tools::PackageInput;

/// Build the `find_alternatives` tool.
pub fn build(state: Arc<AppState>) -> Tool {
    ToolBuilder::new("find_alternatives")
        .title("Find Alternatives")
        .description(
            "Find and compare alternative packages for a given hex.pm package. \
             Searches for packages with similar descriptions/keywords and compares \
             downloads, maintenance status, and health indicators.",
        )
        .read_only()
        .idempotent()
        .extractor_handler(
            state,
            |State(state): State<Arc<AppState>>, Json(input): Json<PackageInput>| async move {
                // 1. Get the source package info
                let pkg = state
                    .client
                    .get_package(&input.name)
                    .await
                    .tool_context("hex.pm API error")?;

                // 2. Build search query from package name and description keywords
                let search_terms = build_search_terms(&input.name, &pkg.meta);

                // 3. Search for similar packages
                let candidates = state
                    .client
                    .search_packages(&search_terms, None, Some("recent_downloads"))
                    .await
                    .tool_context("hex.pm API error")?;

                // Filter out the source package itself
                let alternatives: Vec<_> = candidates
                    .iter()
                    .filter(|c| c.name != input.name)
                    .take(10)
                    .collect();

                if alternatives.is_empty() {
                    return Ok(CallToolResult::text(format!(
                        "# Alternatives to {}\n\nNo alternative packages found.",
                        input.name
                    )));
                }

                let now = Utc::now();
                let mut output = format!("# Alternatives to {}\n\n", input.name);

                // Source package summary
                output.push_str("## Source Package\n\n");
                output.push_str(&format!("**{}**", input.name));
                if let Some(meta) = &pkg.meta
                    && let Some(desc) = &meta.description
                {
                    output.push_str(&format!(" - {}", desc.trim()));
                }
                output.push('\n');
                if let Some(downloads) = &pkg.downloads {
                    if let Some(all) = downloads.all {
                        output.push_str(&format!("Downloads: {} total", format_number(all)));
                    }
                    if let Some(recent) = downloads.recent {
                        output.push_str(&format!(" | {} recent", format_number(recent)));
                    }
                    output.push('\n');
                }
                output.push('\n');

                // Comparison table
                output.push_str("## Alternatives\n\n");
                output.push_str(
                    "| Package | Version | Downloads | Recent | Last Release | Status |\n",
                );
                output.push_str(
                    "|---------|---------|-----------|--------|--------------|--------|\n",
                );

                for alt in &alternatives {
                    let version = alt
                        .latest_stable_version
                        .as_deref()
                        .or(alt.latest_version.as_deref())
                        .unwrap_or("?");

                    let all_dl = alt
                        .downloads
                        .as_ref()
                        .and_then(|d| d.all)
                        .map(format_number)
                        .unwrap_or_else(|| "-".to_string());

                    let recent_dl = alt
                        .downloads
                        .as_ref()
                        .and_then(|d| d.recent)
                        .map(format_number)
                        .unwrap_or_else(|| "-".to_string());

                    let releases = alt.releases.as_deref().unwrap_or_default();
                    let last_release = releases
                        .first()
                        .and_then(|r| r.inserted_at)
                        .map(|d| d.date_naive().to_string())
                        .unwrap_or_else(|| "-".to_string());

                    let days_since = releases
                        .first()
                        .and_then(|r| r.inserted_at)
                        .map(|d| (now - d).num_days());

                    let status = match days_since {
                        Some(d) if d <= 90 => "Active",
                        Some(d) if d <= 365 => "Aging",
                        Some(d) if d <= 730 => "Stale",
                        Some(_) => "Unmaintained",
                        None => "Unknown",
                    };

                    output.push_str(&format!(
                        "| {} | {} | {} | {} | {} | {} |\n",
                        alt.name, version, all_dl, recent_dl, last_release, status
                    ));
                }

                // Details for each alternative
                output.push_str("\n## Details\n\n");
                for alt in &alternatives {
                    output.push_str(&format!("### {}\n\n", alt.name));
                    if let Some(meta) = &alt.meta
                        && let Some(desc) = &meta.description
                    {
                        output.push_str(&format!("{}\n\n", desc.trim()));
                    }

                    if let Some(meta) = &alt.meta
                        && let Some(licenses) = &meta.licenses
                        && !licenses.is_empty()
                    {
                        output.push_str(&format!("- **License**: {}\n", licenses.join(", ")));
                    }

                    if let Some(docs_url) = &alt.docs_html_url {
                        output.push_str(&format!("- **Docs**: {}\n", docs_url));
                    }
                    if let Some(html_url) = &alt.html_url {
                        output.push_str(&format!("- **hex.pm**: {}\n", html_url));
                    }

                    output.push('\n');
                }

                Ok(CallToolResult::text(output))
            },
        )
        .build()
}

/// Build search terms from the package name and its description.
///
/// Extracts meaningful keywords from the description, falling back to the
/// package name itself.
fn build_search_terms(name: &str, meta: &Option<crate::types::PackageMeta>) -> String {
    if let Some(meta) = meta
        && let Some(desc) = &meta.description
    {
        // Use the first few meaningful words from the description
        let stop_words = [
            "a", "an", "the", "and", "or", "for", "to", "in", "of", "is", "it", "with", "that",
            "this", "from", "by", "on", "at", "as", "be", "are", "was", "has", "have", "not",
            "but", "its", "your", "you", "can", "all", "will", "do", "if", "my", "so", "no", "up",
            "out",
        ];

        let keywords: Vec<&str> = desc
            .split_whitespace()
            .filter(|w| {
                let lower = w.to_lowercase();
                let cleaned: String = lower.chars().filter(|c| c.is_alphanumeric()).collect();
                cleaned.len() > 2 && !stop_words.contains(&cleaned.as_str())
            })
            .take(3)
            .collect();

        if keywords.is_empty() {
            name.to_string()
        } else {
            keywords.join(" ")
        }
    } else {
        name.to_string()
    }
}
