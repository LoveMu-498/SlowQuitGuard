#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
mkdir -p "$ROOT_DIR/.build/tmp" "$ROOT_DIR/.build/ModuleCache" "$ROOT_DIR/build/logs"
export TMPDIR="$ROOT_DIR/.build/tmp/"
export CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$ROOT_DIR/.build/ModuleCache"
xcrun swift test --package-path "$ROOT_DIR" --scratch-path "$ROOT_DIR/.build" \
  --cache-path "$ROOT_DIR/.build/cache" --config-path "$ROOT_DIR/.build/config" \
  --security-path "$ROOT_DIR/.build/security" -j 4 "$@" 2>&1 | tee "$ROOT_DIR/build/logs/tests.log"
