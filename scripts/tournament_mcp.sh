#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Compatibility entry point; the checked-in MCP configuration uses Dart directly.
exec dart scripts/tournament_mcp.dart "$@"
