#!/usr/bin/env bash
# One-time setup: install web deps, build the web bundle, generate the Xcode project.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "error: xcodegen not found. Install it: brew install xcodegen" >&2
  exit 1
fi

"$SCRIPT_DIR/build-web.sh"

echo "[bootstrap] generating design tokens…"
node "$SCRIPT_DIR/gen-tokens.mjs"

echo "[bootstrap] generating Xcode project…"
cd "$ROOT/ios"
xcodegen generate

echo "[bootstrap] done. Open ios/Flint.xcodeproj in Xcode, or run: make build"
