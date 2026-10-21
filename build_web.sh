#!/bin/sh
# H79: the browser build for Vercel -> web/ (index.html + wasm + pck). Single-threaded, so no COOP/COEP headers. Commit web/ and push.
set -e
ROOT="$(cd "$(dirname "$0")" && pwd)"
GODOT="${GODOT:-godot}"
mkdir -p "$ROOT/web"
"$GODOT" --headless --path "$ROOT" --import
"$GODOT" --headless --path "$ROOT" --export-release "Web" "$ROOT/web/index.html"
[ -f "$ROOT/web/index.pck" ] || { echo "Export produced no pck."; exit 1; }
echo "Built $ROOT/web"
