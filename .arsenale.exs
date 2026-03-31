%{
  preamble_files: ["CLAUDE.md"],
  validation_commands: [
    "cargo fmt --all -- --check",
    "cargo clippy --all-targets --all-features -- -D warnings",
    "cargo test --all-features"
  ]
}
