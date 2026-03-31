//! Integration tests that hit the real hex.pm API.
//!
//! Gated behind the `integration` feature so they don't run in CI by default.
//! Run with: `cargo test --test hex_api --features integration`

#![cfg(feature = "integration")]

use std::time::Duration;

use hexpm_mcp::client::HexClient;

fn live_client() -> HexClient {
    HexClient::new("hexpm-mcp-integration-tests", Duration::from_secs(1)).unwrap()
}

#[tokio::test]
async fn search_phoenix_returns_results() {
    let client = live_client();
    let results = client
        .search_packages("phoenix", None, Some("downloads"))
        .await
        .unwrap();
    assert!(
        !results.is_empty(),
        "search for 'phoenix' should return results"
    );
    assert!(
        results.iter().any(|p| p.name.contains("phoenix")),
        "results should include phoenix-related packages"
    );
}

#[tokio::test]
async fn get_phoenix_package_info() {
    let client = live_client();
    let pkg = client.get_package("phoenix").await.unwrap();
    assert_eq!(pkg.name, "phoenix");
    assert!(pkg.latest_version.is_some());
    assert!(pkg.meta.is_some());
    let meta = pkg.meta.unwrap();
    assert!(meta.description.is_some());
}

#[tokio::test]
async fn get_specific_release() {
    let client = live_client();
    let release = client.get_release("phoenix", "1.7.0").await.unwrap();
    assert_eq!(release.version, "1.7.0");
    assert!(release.requirements.is_some());
}

#[tokio::test]
async fn get_package_owners() {
    let client = live_client();
    let owners = client.get_owners("phoenix").await.unwrap();
    assert!(!owners.is_empty(), "phoenix should have at least one owner");
    assert!(
        owners.iter().any(|o| !o.username.is_empty()),
        "owners should have usernames"
    );
}

#[tokio::test]
async fn nonexistent_package_returns_not_found() {
    let client = live_client();
    let result = client
        .get_package("this_package_surely_does_not_exist_xyz_123")
        .await;
    assert!(
        matches!(result, Err(hexpm_mcp::client::Error::NotFound(_))),
        "expected NotFound error, got: {result:?}"
    );
}
