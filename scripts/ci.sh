#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
# This workstation shares the bounded job runner with Chess Auto Prep. A runner
# failure is fatal; never retry outside containment. Other machines can set their
# own runner, or use the standard Flutter commands documented in README.
runner=${MEOW_JOB_RUNNER:-../Chess-Auto-Prep/scripts/ci.sh}
if [[ ! -x "$runner" ]]; then
  echo 'Set MEOW_JOB_RUNNER to the shared bounded ci.sh runner.' >&2
  exit 2
fi
local_deps="$HOME/.local/share/meow-build-deps/usr/lib64/pkgconfig"
if [[ -d "$local_deps" ]]; then
  export PKG_CONFIG_PATH="$local_deps${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
fi
case "${1:-test}" in
  analyze) exec "$runner" with -- flutter analyze lib test integration_test tools ;;
  lint) python3 scripts/lint.py ;;
  status) exec "$runner" status ;;
  test) shift || true; exec "$runner" with -- flutter test --concurrency=2 "$@" ;;
  integration) exec "$runner" with --headless -- flutter test integration_test -d linux ;;
  recovery) exec "$runner" with -- python3 scripts/verify_recovery.py ;;
  exports) exec "$runner" with -- "${MEOW_PYTHON:-python3}" scripts/check_exports.py ;;
  build) exec "$runner" with -- flutter build linux --release ;;
  with) shift; exec "$runner" with "$@" ;;
  *) echo 'Usage: scripts/ci.sh analyze|lint|test [paths]|integration|recovery|exports|build|status|with -- COMMAND' >&2; exit 2 ;;
esac
