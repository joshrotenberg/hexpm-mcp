#!/bin/sh
# PostToolUse hook. Reads the hook payload on stdin. When the edited file is
# mix.exs or mix.lock, prints context pointing at the dependency checks;
# otherwise prints nothing. Plain sh and grep, so it adds no dependency.

payload=$(cat)

if printf '%s' "$payload" |
  grep -Eq '"file_path"[[:space:]]*:[[:space:]]*"([^"]*[/\\])?mix\.(exs|lock)"'; then
  cat <<'EOF'
{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"mix.exs or mix.lock changed. If dependencies were added or changed, check them with the hexpm MCP tools: audit_mix_deps for advisories, retirements and maintenance, and upgrade_check for newer releases."}}
EOF
fi
