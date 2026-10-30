#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
APP_NAME="SlowQuitGuard"
APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
BUNDLE_ID="org.slowquitguard.SlowQuitGuard"
MODE="run"
CONFIGURATION="debug"
STAGED="false"

for argument in "$@"; do
  case "$argument" in
    run|--build-only|--debug|--logs|--telemetry|--verify) MODE="$argument" ;;
    --release) CONFIGURATION="release" ;;
    --staged) STAGED="true" ;;
    *) echo "用法：$0 [run|--build-only|--debug|--logs|--telemetry|--verify] [--release] [--staged]" >&2; exit 2 ;;
  esac
done

DIST_DIR="$ROOT_DIR/dist"
if [[ "$STAGED" == "true" ]]; then
  [[ "$MODE" == "--build-only" ]] || { echo "--staged 只用于另存构建，不启动 App。" >&2; exit 2; }
  APP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT_DIR/Resources/Info.plist")"
  DIST_DIR="$ROOT_DIR/dist/versions/$APP_VERSION"
  APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
fi

mkdir -p "$ROOT_DIR/.build/tmp" "$ROOT_DIR/.build/ModuleCache" "$ROOT_DIR/build/logs" "$DIST_DIR"
export TMPDIR="$ROOT_DIR/.build/tmp/"
export CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$ROOT_DIR/.build/ModuleCache"

# Only stop this project's executable; an installed copy or another project is
# not a target for this script.
while IFS= read -r process_id; do
  process_path="$(ps -ww -p "$process_id" -o comm= 2>/dev/null || true)"
  if [[ "$process_path" == "$APP_BUNDLE/Contents/MacOS/$APP_NAME" ]]; then
    if [[ "$MODE" == "--build-only" ]]; then
      echo "请先退出本目录中的 $APP_NAME，再重新编译。" >&2
      exit 1
    fi
    kill "$process_id"
  fi
done < <(pgrep -x "$APP_NAME" || true)

SWIFT_ARGS=(--package-path "$ROOT_DIR" --scratch-path "$ROOT_DIR/.build"
  --cache-path "$ROOT_DIR/.build/cache" --config-path "$ROOT_DIR/.build/config"
  --security-path "$ROOT_DIR/.build/security" -c "$CONFIGURATION" -j 4)

xcrun swift build "${SWIFT_ARGS[@]}" 2>&1 | tee "$ROOT_DIR/build/logs/build-$CONFIGURATION.log"
BIN_DIR="$(xcrun swift build "${SWIFT_ARGS[@]}" --show-bin-path)"

if [[ -f "$APP_BUNDLE/Contents/Info.plist" ]]; then
  existing_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_BUNDLE/Contents/Info.plist")"
  [[ "$existing_id" == "$BUNDLE_ID" ]] || { echo "目标目录属于其他 App，已停止。" >&2; exit 1; }
elif [[ -e "$APP_BUNDLE" ]]; then
  echo "目标 App 目录无法识别，已停止。" >&2
  exit 1
fi

mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp "$BIN_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "$ROOT_DIR/Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
mkdir -p "$APP_BUNDLE/Contents/Resources/Sounds"
for cue in softRise softTap lowDouble; do
  cp "$ROOT_DIR/Resources/Sounds/$cue.wav" "$APP_BUNDLE/Contents/Resources/Sounds/$cue.wav"
done

ICON_SET="$ROOT_DIR/.build/SlowQuitGuard.iconset"
xcrun swift -module-cache-path "$ROOT_DIR/.build/ModuleCache" "$ROOT_DIR/script/generate_icon.swift" "$ICON_SET"
/usr/bin/iconutil -c icns "$ICON_SET" -o "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
/usr/bin/codesign --force --sign - --timestamp=none --options runtime "$APP_BUNDLE"
/usr/bin/codesign --verify --deep --strict "$APP_BUNDLE"
/usr/bin/plutil -lint "$APP_BUNDLE/Contents/Info.plist"

case "$MODE" in
  --build-only)
    /usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$DIST_DIR/$APP_NAME.zip"
    echo "已编译：$APP_BUNDLE"
    ;;
  run) /usr/bin/open "$APP_BUNDLE" ;;
  --debug) /usr/bin/lldb -- "$APP_BUNDLE/Contents/MacOS/$APP_NAME" ;;
  --logs)
    /usr/bin/open "$APP_BUNDLE"
    /usr/bin/log stream --info --style compact --predicate 'process == "SlowQuitGuard"'
    ;;
  --telemetry)
    /usr/bin/open "$APP_BUNDLE"
    /usr/bin/log stream --info --style compact --predicate 'subsystem == "org.slowquitguard.SlowQuitGuard"'
    ;;
  --verify)
    /usr/bin/open "$APP_BUNDLE"
    sleep 1
    /usr/bin/pgrep -x "$APP_NAME"
    ;;
esac
