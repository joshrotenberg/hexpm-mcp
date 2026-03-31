//! Package health check composite tool

use std::sync::Arc;

use chrono::Utc;
use tower_mcp::{
    CallToolResult, ResultExt, Tool, ToolBuilder,
    extract::{Json, State},
};

use crate::state::{AppState, format_number};
use crate::tools::PackageInput;

/// Build the `package_health_check` tool.
pub fn build(state: Arc<AppState>) -> Tool {
    ToolBuilder::new("package_health_check")
        .title("Package Health Check")
        .description(
            "Comprehensive health check for a hex.pm package. Combines package info, latest \
             release, downloads, and owners into a single report covering maintenance, \
             popularity, quality, and risk. Answers: \"should I use this package?\"",
        )
        .read_only()
        .idempotent()
        .extractor_handler(
            state,
            |State(state): State<Arc<AppState>>, Json(input): Json<PackageInput>| async move {
                // 1. Get package info (metadata, downloads, releases, retirements)
                let pkg = state
                    .client
                    .get_package(&input.name)
                    .await
                    .tool_context("hex.pm API error")?;

                let releases = pkg.releases.as_deref().unwrap_or_default();
                let retirements = pkg.retirements.clone().unwrap_or_default();

                let latest_version = pkg
                    .latest_stable_version
                    .as_deref()
                    .or(pkg.latest_version.as_deref());

                // 2. Get owners
                let owners = state
                    .client
                    .get_owners(&input.name)
                    .await
                    .tool_context("hex.pm API error")?;

                // 3. Get latest release details (if available)
                let latest_release = if let Some(version) = latest_version {
                    state.client.get_release(&input.name, version).await.ok()
                } else {
                    None
                };

                // -- Compute derived metrics --
                let now = Utc::now();

                let age_days = pkg.inserted_at.map(|d| (now - d).num_days());
                let days_since_update = pkg.updated_at.map(|d| (now - d).num_days());

                // Last release date from the first release in the list (most recent)
                let last_release_date = releases.first().and_then(|r| r.inserted_at);
                let days_since_release = last_release_date.map(|d| (now - d).num_days());

                // Release cadence
                let total_versions = releases.len();
                let cadence = if total_versions > 1 {
                    let first = releases.last().and_then(|r| r.inserted_at);
                    let latest = releases.first().and_then(|r| r.inserted_at);
                    match (first, latest) {
                        (Some(f), Some(l)) => {
                            let span = (l - f).num_days();
                            Some(span / (total_versions as i64 - 1))
                        }
                        _ => None,
                    }
                } else {
                    None
                };

                let retired_count = retirements.len();

                // -- Format output --
                let version_str = latest_version.unwrap_or("unknown");
                let mut output = format!("# Health Check: {} v{}\n\n", input.name, version_str);

                // Description
                if let Some(meta) = &pkg.meta
                    && let Some(desc) = &meta.description
                {
                    output.push_str(&format!("> {}\n\n", desc.trim()));
                }

                // Maintenance
                output.push_str("## Maintenance\n\n");
                if let Some(days) = age_days {
                    let age_str = if days > 365 {
                        format!("{:.1} years", days as f64 / 365.0)
                    } else {
                        format!("{} days", days)
                    };
                    output.push_str(&format!("- **Age**: {}\n", age_str));
                }
                output.push_str(&format!("- **Total versions**: {}\n", total_versions));
                if let Some(c) = cadence {
                    output.push_str(&format!("- **Avg release cadence**: {} days\n", c));
                }
                if let Some(days) = days_since_release {
                    let freshness = if days <= 30 {
                        "Active (released within 30 days)"
                    } else if days <= 90 {
                        "Recent (released within 90 days)"
                    } else if days <= 365 {
                        "Aging (no release in 3-12 months)"
                    } else {
                        "Stale (no release in over a year)"
                    };
                    output.push_str(&format!("- **Status**: {}\n", freshness));
                    if let Some(date) = last_release_date {
                        output.push_str(&format!(
                            "- **Last release**: {} ({} days ago)\n",
                            date.date_naive(),
                            days
                        ));
                    }
                } else if let Some(days) = days_since_update {
                    output.push_str(&format!("- **Last updated**: {} days ago\n", days));
                }

                // Popularity
                output.push_str("\n## Popularity\n\n");
                if let Some(downloads) = &pkg.downloads {
                    if let Some(all) = downloads.all {
                        output
                            .push_str(&format!("- **Total downloads**: {}\n", format_number(all)));
                    }
                    if let Some(recent) = downloads.recent {
                        output.push_str(&format!(
                            "- **Recent downloads (90 days)**: {}\n",
                            format_number(recent)
                        ));
                    }
                    if let Some(week) = downloads.week {
                        output.push_str(&format!(
                            "- **Weekly downloads**: {}\n",
                            format_number(week)
                        ));
                    }
                }

                // Quality
                output.push_str("\n## Quality\n\n");
                let has_docs = latest_release
                    .as_ref()
                    .and_then(|r| r.has_docs)
                    .unwrap_or(false);
                output.push_str(&format!(
                    "- **Documentation**: {}\n",
                    if has_docs {
                        "Published"
                    } else {
                        "Not published"
                    }
                ));

                if let Some(meta) = &pkg.meta {
                    if let Some(licenses) = &meta.licenses
                        && !licenses.is_empty()
                    {
                        output.push_str(&format!("- **License**: {}\n", licenses.join(", ")));
                    } else {
                        output.push_str("- **License**: Not specified\n");
                    }

                    if let Some(tools) = &meta.build_tools
                        && !tools.is_empty()
                    {
                        output.push_str(&format!("- **Build tools**: {}\n", tools.join(", ")));
                    }

                    if let Some(elixir) = &meta.elixir {
                        output.push_str(&format!("- **Elixir requirement**: {}\n", elixir));
                    }
                }

                // Dependencies from latest release
                if let Some(release) = &latest_release {
                    let reqs = release.requirements.as_ref();
                    let dep_count = reqs.map(|r| r.len()).unwrap_or(0);
                    let optional_count = reqs
                        .map(|r| r.values().filter(|v| v.optional).count())
                        .unwrap_or(0);
                    let required_count = dep_count - optional_count;
                    output.push_str(&format!(
                        "- **Required dependencies**: {}\n",
                        required_count
                    ));
                    if optional_count > 0 {
                        output.push_str(&format!(
                            "- **Optional dependencies**: {}\n",
                            optional_count
                        ));
                    }
                }

                // Risk
                output.push_str("\n## Risk\n\n");
                output.push_str(&format!("- **Maintainers**: {}\n", owners.len()));
                if owners.len() <= 1 {
                    output.push_str("  - Warning: single maintainer (bus factor risk)\n");
                }
                if retired_count > 0 {
                    output.push_str(&format!(
                        "- **Retired versions**: {} (run `get_package_versions` for details)\n",
                        retired_count
                    ));
                } else {
                    output.push_str("- **Retired versions**: None\n");
                }

                // Links
                let has_links = pkg.docs_html_url.is_some()
                    || pkg.html_url.is_some()
                    || pkg.meta.as_ref().and_then(|m| m.links.as_ref()).is_some();
                if has_links {
                    output.push_str("\n## Links\n\n");
                    if let Some(docs_url) = &pkg.docs_html_url {
                        output.push_str(&format!("- **Documentation**: {}\n", docs_url));
                    }
                    if let Some(html_url) = &pkg.html_url {
                        output.push_str(&format!("- **hex.pm**: {}\n", html_url));
                    }
                    if let Some(meta) = &pkg.meta
                        && let Some(links) = &meta.links
                    {
                        for (label, url) in links {
                            output.push_str(&format!("- **{}**: {}\n", label, url));
                        }
                    }
                }

                Ok(CallToolResult::text(output))
            },
        )
        .build()
}
