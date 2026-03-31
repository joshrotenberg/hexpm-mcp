//! Response types for the hex.pm API.

use std::collections::HashMap;

use chrono::{DateTime, Utc};
use serde::Deserialize;

/// A hex.pm package.
#[derive(Debug, Deserialize)]
pub struct Package {
    /// Package name.
    pub name: String,
    /// API URL for this package.
    #[serde(default)]
    pub url: Option<String>,
    /// Web URL for this package.
    #[serde(default)]
    pub html_url: Option<String>,
    /// Documentation URL.
    #[serde(default)]
    pub docs_html_url: Option<String>,
    /// Latest release version.
    #[serde(default)]
    pub latest_version: Option<String>,
    /// Latest stable release version.
    #[serde(default)]
    pub latest_stable_version: Option<String>,
    /// Package metadata (description, licenses, links, build tools).
    #[serde(default)]
    pub meta: Option<PackageMeta>,
    /// Download statistics.
    #[serde(default)]
    pub downloads: Option<DownloadStats>,
    /// List of releases (summary form when fetched with the package).
    #[serde(default)]
    pub releases: Option<Vec<Release>>,
    /// List of owners.
    #[serde(default)]
    pub owners: Option<Vec<Owner>>,
    /// Retired versions.
    #[serde(default)]
    pub retirements: Option<HashMap<String, Retirement>>,
    /// When the package was first published.
    #[serde(default)]
    pub inserted_at: Option<DateTime<Utc>>,
    /// When the package was last updated.
    #[serde(default)]
    pub updated_at: Option<DateTime<Utc>>,
    /// Repository name (e.g. "hexpm").
    #[serde(default)]
    pub repository: Option<String>,
}

/// Package metadata from the `meta` field.
#[derive(Debug, Deserialize)]
pub struct PackageMeta {
    /// Package description.
    #[serde(default)]
    pub description: Option<String>,
    /// License identifiers.
    #[serde(default)]
    pub licenses: Option<Vec<String>>,
    /// Related links (e.g. GitHub, docs).
    #[serde(default)]
    pub links: Option<HashMap<String, String>>,
    /// Build tools (mix, rebar3, erlang.mk).
    #[serde(default)]
    pub build_tools: Option<Vec<String>>,
    /// Required Elixir version.
    #[serde(default)]
    pub elixir: Option<String>,
    /// OTP application name.
    #[serde(default)]
    pub app: Option<String>,
}

/// Download statistics for a package.
#[derive(Debug, Deserialize)]
pub struct DownloadStats {
    /// All-time downloads.
    #[serde(default)]
    pub all: Option<u64>,
    /// Downloads today.
    #[serde(default)]
    pub day: Option<u64>,
    /// Downloads this week.
    #[serde(default)]
    pub week: Option<u64>,
    /// Downloads in the last 90 days.
    #[serde(default)]
    pub recent: Option<u64>,
}

/// A package release (version).
#[derive(Debug, Deserialize)]
pub struct Release {
    /// Version string.
    pub version: String,
    /// Whether docs have been published.
    #[serde(default)]
    pub has_docs: Option<bool>,
    /// API URL for this release.
    #[serde(default)]
    pub url: Option<String>,
    /// Web URL for this release.
    #[serde(default)]
    pub html_url: Option<String>,
    /// Documentation URL for this version.
    #[serde(default)]
    pub docs_html_url: Option<String>,
    /// Download count for this release.
    #[serde(default)]
    pub downloads: Option<u64>,
    /// When this release was published.
    #[serde(default)]
    pub inserted_at: Option<DateTime<Utc>>,
    /// When this release was last updated.
    #[serde(default)]
    pub updated_at: Option<DateTime<Utc>>,
    /// Release publisher.
    #[serde(default)]
    pub publisher: Option<Publisher>,
    /// Release metadata (elixir version, build tools).
    #[serde(default)]
    pub meta: Option<PackageMeta>,
    /// Dependencies (requirements) for this release.
    #[serde(default)]
    pub requirements: Option<HashMap<String, Requirement>>,
    /// Retirement info (null if not retired).
    #[serde(default)]
    pub retirement: Option<Retirement>,
    /// SHA-256 checksum.
    #[serde(default)]
    pub checksum: Option<String>,
}

/// A dependency requirement.
#[derive(Debug, Deserialize)]
pub struct Requirement {
    /// Version requirement string (e.g. "~> 1.0").
    pub requirement: String,
    /// Whether this dependency is optional.
    #[serde(default)]
    pub optional: bool,
    /// OTP application name.
    #[serde(default)]
    pub app: Option<String>,
}

/// A package owner/maintainer.
#[derive(Debug, Deserialize)]
pub struct Owner {
    /// Username.
    pub username: String,
    /// Email address.
    #[serde(default)]
    pub email: Option<String>,
    /// API URL for this user.
    #[serde(default)]
    pub url: Option<String>,
}

/// A release publisher.
#[derive(Debug, Deserialize)]
pub struct Publisher {
    /// Username.
    pub username: String,
    /// API URL for this user.
    #[serde(default)]
    pub url: Option<String>,
}

/// Retirement information for a release.
#[derive(Debug, Deserialize)]
pub struct Retirement {
    /// Retirement reason (deprecated, renamed, security, invalid, other).
    #[serde(default)]
    pub reason: Option<String>,
    /// Optional message explaining the retirement.
    #[serde(default)]
    pub message: Option<String>,
}

/// Paginated list of packages (used by reverse dependencies).
#[derive(Debug, Deserialize)]
pub struct PackagesPage {
    /// List of packages.
    #[serde(default)]
    pub packages: Option<Vec<Package>>,
}
