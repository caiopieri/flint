#!/usr/bin/env bash
# Builds the web runtime (web/) and copies the bundle into the iOS app resources.
# Run standalone, or automatically as an Xcode pre-build phase.
set -euo pipefail

# Make node/npm discoverable from Xcode's sanitized build environment.
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WEB="$ROOT/web"
DEST="$ROOT/ios/Flint/Resources/web"

if ! command -v node >/dev/null 2>&1; then
  echo "warning: node not found — skipping web build, keeping existing bundle in $DEST" >&2
  exit 0
fi

cd "$WEB"
if [ ! -d node_modules ]; then
  echo "[build-web] installing web deps…"
  npm install
fi

echo "[build-web] building bundle…"
npm run build

echo "[build-web] copying bundle → $DEST"
mkdir -p "$DEST"
find "$DEST" -mindepth 1 ! -name ".gitkeep" -delete
cp -R "$WEB/dist/." "$DEST/"
echo "[build-web] done."
