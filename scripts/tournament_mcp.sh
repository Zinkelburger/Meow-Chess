#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ ! -x build/tournament-cli/bundle/bin/tournament_mcp ]]; then
  echo 'Build first: scripts/ci.sh with -- dart build cli --target=tools/tournament_mcp.dart --output=build/tournament-cli' >&2
  exit 1
fi
exec build/tournament-cli/bundle/bin/tournament_mcp --root "${1:-$PWD/artifacts/mcp-events}"
