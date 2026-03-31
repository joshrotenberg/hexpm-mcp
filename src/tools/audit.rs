//! Dependency audit tool

use std::sync::Arc;

use chrono::Utc;
use tower_mcp::{
    CallToolResult, ResultExt, Tool, ToolBuilder,
    extract::{Json, State},
};

use crate::state::AppState;
use crate::tools::PackageVersionInput;

/// Build the `audit_dependencies` tool.
pub fn build(state: Arc<AppState>) -> Tool {
    ToolBuilder::new("audit_dependencies")
        .title("Audit Dependencies")
        .description(
            "Audit a hex.pm package's dependencies for risks. Checks each dependency for \
             retired versions, stale packages (no release in 2+ years), and single-owner \
             packages. Returns a risk report per dependency.",
        )
        .read_only()
        .idempotent()
        .extractor_handler(
            state,
            |State(state): State<Arc<AppState>>,
             Json(input): Json<PackageVersionInput>| async move {
                // Resolve version
                let version = if let Some(v) = &input.version {
                    v.clone()
                } else {
                    let pkg = state
                        .client
                        .get_package(&input.name)
                        .await
                        .tool_context("hex.pm API error")?;
                    pkg.latest_stable_version
                        .or(pkg.latest_version)
                        .unwrap_or_else(|| "latest".to_string())
                };

                // Fetch dependencies for the release
                let deps = state
                    .client
                    .get_dependencies(&input.name, &version)
                    .await
                    .tool_context("hex.pm API error")?;

                if deps.is_empty() {
                    return Ok(CallToolResult::text(format!(
                        "# Dependency Audit: {} v{}\n\nNo dependencies found.",
                        input.name, version
                    )));
                }

                let mut output = format!(
                    "# Dependency Audit: {} v{}\n\n",
                    input.name, version
                );

                let now = Utc::now();
                let mut warnings = 0u32;
                let mut dep_reports = Vec::new();

                for (dep_name, req) in &deps {
                    let mut issues = Vec::new();

                    // Check the dependency package
                    match state.client.get_package(dep_name).await {
                        Ok(dep_pkg) => {
                            // Check for retired versions
                            let retirements = dep_pkg.retirements.as_ref();
                            let retired_count =
                                retirements.map(|r| r.len()).unwrap_or(0);
                            if retired_count > 0 {
                                issues.push(format!(
                                    "Has {} retired version(s)",
                                    retired_count
                                ));
                            }

                            // Check if latest version is retired
                            if let Some(latest) = dep_pkg
                                .latest_stable_version
                                .as_deref()
                                .or(dep_pkg.latest_version.as_deref())
                                && let Some(retirements) = retirements
                                && retirements.contains_key(latest)
                            {
                                let retirement = &retirements[latest];
                                let reason =
                                    retirement.reason.as_deref().unwrap_or("unknown");
                                let msg = retirement
                                    .message
                                    .as_deref()
                                    .map(|m| format!(" - {}", m))
                                    .unwrap_or_default();
                                issues.push(format!(
                                    "Latest version {} is retired ({}{})",
                                    latest, reason, msg
                                ));
                            }

                            // Check staleness (no release in 2+ years)
                            let releases = dep_pkg.releases.as_deref().unwrap_or_default();
                            if let Some(latest_release) = releases.first()
                                && let Some(date) = latest_release.inserted_at
                            {
                                let days = (now - date).num_days();
                                if days > 730 {
                                    issues.push(format!(
                                        "Stale: last release was {:.1} years ago ({})",
                                        days as f64 / 365.0,
                                        date.date_naive()
                                    ));
                                }
                            }

                            // Check for single owner
                            match state.client.get_owners(dep_name).await {
                                Ok(owners) => {
                                    if owners.len() <= 1 {
                                        issues.push(
                                            "Single maintainer (bus factor risk)".to_string(),
                                        );
                                    }
                                }
                                Err(_) => {
                                    issues
                                        .push("Could not fetch owner information".to_string());
                                }
                            }
                        }
                        Err(e) => {
                            issues.push(format!("Could not fetch package info: {}", e));
                        }
                    }

                    let optional_str = if req.optional { " (optional)" } else { "" };
                    warnings += issues.len() as u32;
                    dep_reports.push((dep_name.clone(), req.requirement.clone(), optional_str, issues));
                }

                // Sort by number of issues (most issues first), then by name
                dep_reports.sort_by(|a, b| b.3.len().cmp(&a.3.len()).then(a.0.cmp(&b.0)));

                for (dep_name, requirement, optional_str, issues) in &dep_reports {
                    if issues.is_empty() {
                        output.push_str(&format!(
                            "## {} {}{} -- OK\n\n",
                            dep_name, requirement, optional_str
                        ));
                    } else {
                        output.push_str(&format!(
                            "## {} {}{} -- {} warning(s)\n\n",
                            dep_name,
                            requirement,
                            optional_str,
                            issues.len()
                        ));
                        for issue in issues {
                            output.push_str(&format!("- {}\n", issue));
                        }
                        output.push('\n');
                    }
                }

                // Summary
                output.push_str("## Summary\n\n");
                output.push_str(&format!("- **Dependencies checked**: {}\n", deps.len()));
                output.push_str(&format!("- **Total warnings**: {}\n", warnings));
                let affected = dep_reports.iter().filter(|r| !r.3.is_empty()).count();
                output.push_str(&format!(
                    "- **Dependencies with warnings**: {}\n",
                    affected
                ));

                Ok(CallToolResult::text(output))
            },
        )
        .build()
}
