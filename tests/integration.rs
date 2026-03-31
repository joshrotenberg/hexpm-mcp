//! MCP integration tests using tower-mcp's TestClient + wiremock.

use std::sync::Arc;

use hexpm_mcp::state::AppState;
use serde_json::json;
use tower_mcp::{McpRouter, TestClient};
use wiremock::matchers::{method, path};
use wiremock::{Mock, MockServer, ResponseTemplate};

fn test_state(server: &MockServer) -> Arc<AppState> {
    Arc::new(AppState::with_base_url(&server.uri()).expect("failed to create test state"))
}

fn test_router(state: Arc<AppState>) -> McpRouter {
    McpRouter::new()
        .server_info("hexpm-mcp", "0.1.0")
        .tool(hexpm_mcp::tools::search::build(state.clone()))
        .tool(hexpm_mcp::tools::info::build(state.clone()))
        .tool(hexpm_mcp::tools::info::build_versions(state.clone()))
        .tool(hexpm_mcp::tools::release::build(state.clone()))
        .tool(hexpm_mcp::tools::dependencies::build(state.clone()))
        .tool(hexpm_mcp::tools::reverse::build(state.clone()))
        .tool(hexpm_mcp::tools::downloads::build(state.clone()))
        .tool(hexpm_mcp::tools::owners::build(state.clone()))
        .tool(hexpm_mcp::tools::compare::build(state.clone()))
        .tool(hexpm_mcp::tools::health::build(state.clone()))
        .tool(hexpm_mcp::tools::audit::build(state.clone()))
        .tool(hexpm_mcp::tools::alternatives::build(state.clone()))
}

async fn initialized_client(server: &MockServer) -> TestClient {
    let state = test_state(server);
    let router = test_router(state);
    let mut client = TestClient::from_router(router);
    client.initialize().await;
    client
}

// ── Mock data ─────────────────────────────────────────────────────────────

fn phoenix_package_json() -> serde_json::Value {
    json!({
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
    })
}

async fn mount_get_package(server: &MockServer) {
    Mock::given(method("GET"))
        .and(path("/packages/phoenix"))
        .respond_with(ResponseTemplate::new(200).set_body_json(phoenix_package_json()))
        .mount(server)
        .await;
}

// ── Tests ─────────────────────────────────────────────────────────────────

#[tokio::test]
async fn server_initializes() {
    let server = MockServer::start().await;
    let _client = initialized_client(&server).await;
}

#[tokio::test]
async fn tool_get_package_info() {
    let server = MockServer::start().await;
    mount_get_package(&server).await;

    let mut client = initialized_client(&server).await;
    let result = client
        .call_tool("get_package_info", json!({"name": "phoenix"}))
        .await;

    assert!(!result.is_error);
    let text = result.all_text();
    assert!(text.contains("phoenix"));
    assert!(text.contains("1.8.5"));
}

#[tokio::test]
async fn tool_search_packages() {
    let server = MockServer::start().await;

    let body = json!([
        {
            "name": "phoenix",
            "meta": {
                "description": "Peace of mind from prototype to production"
            },
            "downloads": {"all": 1000000, "recent": 50000},
            "latest_version": "1.8.5"
        },
        {
            "name": "phoenix_html",
            "meta": {
                "description": "Phoenix.HTML functions for working with HTML"
            },
            "downloads": {"all": 800000, "recent": 40000},
            "latest_version": "4.2.0"
        }
    ]);

    Mock::given(method("GET"))
        .and(path("/packages"))
        .respond_with(ResponseTemplate::new(200).set_body_json(&body))
        .mount(&server)
        .await;

    let mut client = initialized_client(&server).await;
    let result = client
        .call_tool("search_packages", json!({"query": "phoenix"}))
        .await;

    assert!(!result.is_error);
    let text = result.all_text();
    assert!(text.contains("phoenix"));
}

#[tokio::test]
async fn tool_get_downloads() {
    let server = MockServer::start().await;
    mount_get_package(&server).await;

    let mut client = initialized_client(&server).await;
    let result = client
        .call_tool("get_downloads", json!({"name": "phoenix"}))
        .await;

    assert!(!result.is_error);
    let text = result.all_text();
    assert!(text.contains("phoenix"));
}

#[tokio::test]
async fn tool_get_owners() {
    let server = MockServer::start().await;

    Mock::given(method("GET"))
        .and(path("/packages/phoenix/owners"))
        .respond_with(ResponseTemplate::new(200).set_body_json(json!([
            {"username": "chrismccord", "email": "chris@example.com"}
        ])))
        .mount(&server)
        .await;

    let mut client = initialized_client(&server).await;
    let result = client
        .call_tool("get_owners", json!({"name": "phoenix"}))
        .await;

    assert!(!result.is_error);
    let text = result.all_text();
    assert!(text.contains("chrismccord"));
}
