//! Compare packages tool

use std::sync::Arc;

use schemars::JsonSchema;
use serde::Deserialize;
use tower_mcp::{
    CallToolResult, Tool, ToolBuilder,
    extract::{Json, State},
};

use crate::state::{AppState, format_number};

/// Input for the compare_packages tool.
#[derive(Debug, Deserialize, JsonSchema)]
struct CompareInput {
    /// Comma-separated list of package names to compare (2-4 packages).
    packages: String,
}

/// Build the `compare_packages` tool.
pub fn build(state: Arc<AppState>) -> Tool {
    ToolBuilder::new("compare_packages")
        .title("Compare Packages")
        .description(
            "Compare 2-4 hex.pm packages side by side. Provide a comma-separated \
             list of package names. Compares downloads, latest version, last updated, \
             license, number of dependencies, and retirement status.",
        )
        .read_only()
        .idempotent()
        .extractor_handler(
            state,
            |State(state): State<Arc<AppState>>, Json(input): Json<CompareInput>| async move {
                let names: Vec<&str> = input
                    .packages
                    .split(',')
                    .map(|s| s.trim())
                    .filter(|s| !s.is_empty())
                    .collect();

                if names.len() < 2 {
                    return Ok(CallToolResult::text(
                        "Please provide at least 2 package names to compare (comma-separated).",
                    ));
                }
                if names.len() > 4 {
                    return Ok(CallToolResult::text(
                        "Please provide at most 4 package names to compare.",
                    ));
                }

                // Fetch all packages
                let mut packages = Vec::new();
                for name in &names {
                    match state.client.get_package(name).await {
                        Ok(pkg) => packages.push(Ok(pkg)),
                        Err(e) => packages.push(Err(format!("{e}"))),
                    }
                }

                // Build table header
                let mut header = "| Metric |".to_string();
                let mut separator = "|--------|".to_string();
                for name in &names {
                    header.push_str(&format!(" {} |", name));
                    separator.push_str("--------|");
                }

                let mut output = format!("# Package Comparison\n\n{}\n{}\n", header, separator);

                // Downloads (all-time)
                let mut row = "| Downloads (all-time) |".to_string();
                for result in &packages {
                    match result {
                        Ok(pkg) => {
                            let val = pkg
                                .downloads
                                .as_ref()
                                .and_then(|d| d.all)
                                .map(format_number)
                                .unwrap_or_else(|| "N/A".to_string());
                            row.push_str(&format!(" {} |", val));
                        }
                        Err(e) => row.push_str(&format!(" error: {} |", e)),
                    }
                }
                output.push_str(&format!("{}\n", row));

                // Downloads (recent)
                let mut row = "| Downloads (90 days) |".to_string();
                for result in &packages {
                    match result {
                        Ok(pkg) => {
                            let val = pkg
                                .downloads
                                .as_ref()
                                .and_then(|d| d.recent)
                                .map(format_number)
                                .unwrap_or_else(|| "N/A".to_string());
                            row.push_str(&format!(" {} |", val));
                        }
                        Err(e) => row.push_str(&format!(" error: {} |", e)),
                    }
                }
                output.push_str(&format!("{}\n", row));

                // Latest version
                let mut row = "| Latest version |".to_string();
                for result in &packages {
                    match result {
                        Ok(pkg) => {
                            let val = pkg
                                .latest_stable_version
                                .as_deref()
                                .or(pkg.latest_version.as_deref())
                                .unwrap_or("N/A");
                            row.push_str(&format!(" {} |", val));
                        }
                        Err(e) => row.push_str(&format!(" error: {} |", e)),
                    }
                }
                output.push_str(&format!("{}\n", row));

                // Last updated
                let mut row = "| Last updated |".to_string();
                for result in &packages {
                    match result {
                        Ok(pkg) => {
                            let val = pkg
                                .updated_at
                                .map(|d| d.date_naive().to_string())
                                .unwrap_or_else(|| "N/A".to_string());
                            row.push_str(&format!(" {} |", val));
                        }
                        Err(e) => row.push_str(&format!(" error: {} |", e)),
                    }
                }
                output.push_str(&format!("{}\n", row));

                // License
                let mut row = "| License |".to_string();
                for result in &packages {
                    match result {
                        Ok(pkg) => {
                            let val = pkg
                                .meta
                                .as_ref()
                                .and_then(|m| m.licenses.as_ref())
                                .map(|l| l.join(", "))
                                .unwrap_or_else(|| "N/A".to_string());
                            row.push_str(&format!(" {} |", val));
                        }
                        Err(e) => row.push_str(&format!(" error: {} |", e)),
                    }
                }
                output.push_str(&format!("{}\n", row));

                // Number of deps (from latest release)
                let mut row = "| Dependencies |".to_string();
                for (i, result) in packages.iter().enumerate() {
                    match result {
                        Ok(pkg) => {
                            let version = pkg
                                .latest_stable_version
                                .as_deref()
                                .or(pkg.latest_version.as_deref());
                            if let Some(ver) = version {
                                match state.client.get_release(names[i], ver).await {
                                    Ok(release) => {
                                        let count =
                                            release.requirements.as_ref().map_or(0, |r| r.len());
                                        row.push_str(&format!(" {} |", count));
                                    }
                                    Err(_) => row.push_str(" N/A |"),
                                }
                            } else {
                                row.push_str(" N/A |");
                            }
                        }
                        Err(e) => row.push_str(&format!(" error: {} |", e)),
                    }
                }
                output.push_str(&format!("{}\n", row));

                // Retirement status
                let mut row = "| Retired |".to_string();
                for result in &packages {
                    match result {
                        Ok(pkg) => {
                            let retired = pkg.retirements.as_ref().is_some_and(|r| !r.is_empty());
                            let val = if retired { "Yes (some versions)" } else { "No" };
                            row.push_str(&format!(" {} |", val));
                        }
                        Err(e) => row.push_str(&format!(" error: {} |", e)),
                    }
                }
                output.push_str(&format!("{}\n", row));

                Ok(CallToolResult::text(output))
            },
        )
        .build()
}
