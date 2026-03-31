//! HTTP client for the hex.pm API.
//!
//! Async client for the hex.pm REST API, built on reqwest with built-in
//! rate limiting.

use std::collections::HashMap;
use std::sync::Arc;
use std::time::Duration;

use serde::de::DeserializeOwned;
use tokio::sync::Mutex;
use tokio::time::Instant;

use crate::types::{Package, PackagesPage, Release};

// ── Error ──────────────────────────────────────────────────────────────────

/// Errors returned by the hex.pm API client.
#[derive(Debug, thiserror::Error)]
pub enum Error {
    /// HTTP transport error.
    #[error("HTTP error: {0}")]
    Http(#[from] reqwest::Error),

    /// Resource not found (404).
    #[error("not found: {0}")]
    NotFound(String),

    /// Permission denied (403).
    #[error("permission denied")]
    PermissionDenied,

    /// Too many requests (429).
    #[error("rate limited")]
    RateLimited,

    /// Generic API error with status code.
    #[error("API error ({status}): {message}")]
    Api { status: u16, message: String },
}

// ── Client ─────────────────────────────────────────────────────────────────

/// Async client for the hex.pm REST API.
///
/// Includes built-in rate limiting to be a good citizen of the hex.pm API.
pub struct HexClient {
    http: reqwest::Client,
    base_url: String,
    rate_limit: Duration,
    last_request: Arc<Mutex<Option<Instant>>>,
}

impl HexClient {
    /// Create a new client with the given user agent and rate limit.
    pub fn new(user_agent: &str, rate_limit: Duration) -> Result<Self, Error> {
        Self::with_base_url(user_agent, rate_limit, "https://hex.pm/api")
    }

    /// Create a new client with a custom base URL (for testing).
    pub fn with_base_url(
        user_agent: &str,
        rate_limit: Duration,
        base_url: &str,
    ) -> Result<Self, Error> {
        let http = reqwest::Client::builder().user_agent(user_agent).build()?;
        Ok(Self {
            http,
            base_url: base_url.trim_end_matches('/').to_string(),
            rate_limit,
            last_request: Arc::new(Mutex::new(None)),
        })
    }

    // ── Rate limiting ──────────────────────────────────────────────────

    /// Enforce rate limiting between requests.
    async fn throttle(&self) {
        let mut last = self.last_request.lock().await;
        if let Some(last_time) = *last {
            let elapsed = last_time.elapsed();
            if elapsed < self.rate_limit {
                tokio::time::sleep(self.rate_limit - elapsed).await;
            }
        }
        *last = Some(Instant::now());
    }

    // ── HTTP helpers ───────────────────────────────────────────────────

    /// Send a GET request and check the response status.
    async fn send(&self, path: &str) -> Result<reqwest::Response, Error> {
        self.throttle().await;
        let url = format!("{}{}", self.base_url, path);
        let resp = self.http.get(&url).send().await?;
        Self::check_status(resp, path).await
    }

    /// Send a GET request with query parameters.
    async fn send_query(
        &self,
        path: &str,
        query: &[(String, String)],
    ) -> Result<reqwest::Response, Error> {
        self.throttle().await;
        let url = format!("{}{}", self.base_url, path);
        let resp = self.http.get(&url).query(query).send().await?;
        Self::check_status(resp, path).await
    }

    /// Map non-success HTTP status codes to typed errors.
    async fn check_status(resp: reqwest::Response, path: &str) -> Result<reqwest::Response, Error> {
        let status = resp.status();
        if status.is_success() {
            Ok(resp)
        } else if status == reqwest::StatusCode::NOT_FOUND {
            Err(Error::NotFound(path.to_string()))
        } else if status == reqwest::StatusCode::FORBIDDEN {
            Err(Error::PermissionDenied)
        } else if status == reqwest::StatusCode::TOO_MANY_REQUESTS {
            Err(Error::RateLimited)
        } else {
            let text = resp.text().await.unwrap_or_default();
            Err(Error::Api {
                status: status.as_u16(),
                message: text,
            })
        }
    }

    /// GET a JSON resource.
    async fn get_json<T: DeserializeOwned>(&self, path: &str) -> Result<T, Error> {
        let resp = self.send(path).await?;
        Ok(resp.json().await?)
    }

    /// GET a JSON resource with query parameters.
    async fn get_json_query<T: DeserializeOwned>(
        &self,
        path: &str,
        query: &[(String, String)],
    ) -> Result<T, Error> {
        let resp = self.send_query(path, query).await?;
        Ok(resp.json().await?)
    }

    // ── Public API methods ─────────────────────────────────────────────

    /// Search for packages.
    pub async fn search_packages(
        &self,
        query: &str,
        page: Option<u32>,
        sort: Option<&str>,
    ) -> Result<Vec<Package>, Error> {
        let mut params = vec![("search".to_string(), query.to_string())];
        if let Some(page) = page {
            params.push(("page".to_string(), page.to_string()));
        }
        if let Some(sort) = sort {
            params.push(("sort".to_string(), sort.to_string()));
        }
        self.get_json_query::<Vec<Package>>("/packages", &params)
            .await
    }

    /// Get a package by name.
    pub async fn get_package(&self, name: &str) -> Result<Package, Error> {
        self.get_json(&format!("/packages/{name}")).await
    }

    /// Get all releases for a package.
    pub async fn get_releases(&self, name: &str) -> Result<Vec<Release>, Error> {
        let pkg: Package = self.get_package(name).await?;
        Ok(pkg.releases.unwrap_or_default())
    }

    /// Get a specific release.
    pub async fn get_release(&self, name: &str, version: &str) -> Result<Release, Error> {
        self.get_json(&format!("/packages/{name}/releases/{version}"))
            .await
    }

    /// Get the dependencies for a specific release.
    pub async fn get_dependencies(
        &self,
        name: &str,
        version: &str,
    ) -> Result<HashMap<String, crate::types::Requirement>, Error> {
        let release = self.get_release(name, version).await?;
        Ok(release.requirements.unwrap_or_default())
    }

    /// Get reverse dependencies (packages that depend on this one).
    pub async fn get_reverse_dependencies(
        &self,
        name: &str,
        page: Option<u32>,
    ) -> Result<PackagesPage, Error> {
        let mut params = vec![];
        if let Some(page) = page {
            params.push(("page".to_string(), page.to_string()));
        }
        self.get_json_query(&format!("/packages/{name}/reverse_dependencies"), &params)
            .await
    }

    /// Get owners for a package.
    pub async fn get_owners(&self, name: &str) -> Result<Vec<crate::types::Owner>, Error> {
        self.get_json(&format!("/packages/{name}/owners")).await
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use wiremock::matchers::{method, path};
    use wiremock::{Mock, MockServer, ResponseTemplate};

    #[tokio::test]
    async fn test_get_package() {
        let mock_server = MockServer::start().await;

        let body = serde_json::json!({
            "name": "phoenix",
            "url": "https://hex.pm/api/packages/phoenix",
            "html_url": "https://hex.pm/packages/phoenix",
            "docs_html_url": "https://hexdocs.pm/phoenix",
            "meta": {
                "description": "Peace of mind from prototype to production",
                "licenses": ["MIT"],
                "links": {"GitHub": "https://github.com/phoenixframework/phoenix"},
                "build_tools": ["mix"]
            },
            "downloads": {
                "all": 1000000,
                "day": 500,
                "week": 3500,
                "recent": 50000
            },
            "releases": [
                {
                    "version": "1.8.5",
                    "has_docs": true,
                    "inserted_at": "2026-03-05T15:22:23.915693Z"
                }
            ],
            "latest_version": "1.8.5",
            "latest_stable_version": "1.8.5",
            "inserted_at": "2014-08-01T00:00:00.000000Z",
            "updated_at": "2026-03-05T15:22:30.844867Z"
        });

        Mock::given(method("GET"))
            .and(path("/packages/phoenix"))
            .respond_with(ResponseTemplate::new(200).set_body_json(&body))
            .mount(&mock_server)
            .await;

        let client =
            HexClient::with_base_url("test-agent", Duration::from_millis(0), &mock_server.uri())
                .unwrap();

        let pkg = client.get_package("phoenix").await.unwrap();
        assert_eq!(pkg.name, "phoenix");
        assert_eq!(pkg.latest_version.as_deref(), Some("1.8.5"));
    }

    #[tokio::test]
    async fn test_get_release() {
        let mock_server = MockServer::start().await;

        let body = serde_json::json!({
            "version": "1.8.5",
            "has_docs": true,
            "inserted_at": "2026-03-05T15:22:23.915693Z",
            "updated_at": "2026-03-05T15:22:30.844867Z",
            "url": "https://hex.pm/api/packages/phoenix/releases/1.8.5",
            "html_url": "https://hex.pm/packages/phoenix/1.8.5",
            "docs_html_url": "https://hexdocs.pm/phoenix/1.8.5/",
            "retirement": null,
            "downloads": 171341,
            "publisher": {
                "username": "steffend",
                "url": "https://hex.pm/api/users/steffend"
            },
            "meta": {
                "elixir": "~> 1.15",
                "app": "phoenix",
                "build_tools": ["mix"]
            },
            "requirements": {
                "plug": {
                    "requirement": "~> 1.14",
                    "optional": false,
                    "app": "plug"
                }
            }
        });

        Mock::given(method("GET"))
            .and(path("/packages/phoenix/releases/1.8.5"))
            .respond_with(ResponseTemplate::new(200).set_body_json(&body))
            .mount(&mock_server)
            .await;

        let client =
            HexClient::with_base_url("test-agent", Duration::from_millis(0), &mock_server.uri())
                .unwrap();

        let release = client.get_release("phoenix", "1.8.5").await.unwrap();
        assert_eq!(release.version, "1.8.5");
        assert_eq!(release.has_docs, Some(true));
        assert!(release.requirements.unwrap().contains_key("plug"));
    }

    #[tokio::test]
    async fn test_not_found() {
        let mock_server = MockServer::start().await;

        Mock::given(method("GET"))
            .and(path("/packages/nonexistent"))
            .respond_with(ResponseTemplate::new(404))
            .mount(&mock_server)
            .await;

        let client =
            HexClient::with_base_url("test-agent", Duration::from_millis(0), &mock_server.uri())
                .unwrap();

        let result = client.get_package("nonexistent").await;
        assert!(matches!(result, Err(Error::NotFound(_))));
    }
}
