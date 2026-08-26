#!/usr/bin/env bash
# Build both executables and wrap them in a .app bundle.
#
# A bundle is not optional here: UNUserNotificationCenter needs a bundle identifier,
# LSUIElement is what keeps the app out of the Dock, SMAppService needs something signed
# to register as a login item, and the `kurura` CLI finds its own version by walking up
# from Contents/MacOS to the enclosing Info.plist.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="Kurura Isaha"
BIN_NAME="KururaIsaha"
CLI_NAME="kurura"
BUNDLE_ID="com.local.kururaisaha"
CONFIG="release"

# One source of truth for the version. The app reads it back out of its own Info.plist at
# runtime, so it is never written down twice.
VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION" 2>/dev/null || true)"
[ -n "$VERSION" ] || { echo "no VERSION file at $ROOT/VERSION" >&2; exit 1; }
case "$VERSION" in
  [0-9]*.[0-9]*.[0-9]*) ;;
  *) echo "VERSION must look like MAJOR.MINOR.PATCH (got '$VERSION')" >&2; exit 1 ;;
esac

echo "==> Testing"
swift test --package-path "$ROOT" 2>&1 | tail -3

echo "==> Building ($CONFIG)"
swift build -c "$CONFIG" --package-path "$ROOT"

BIN_DIR="$(swift build -c "$CONFIG" --package-path "$ROOT" --show-bin-path)"
APP_BIN="$BIN_DIR/$BIN_NAME"
CLI_BIN="$BIN_DIR/$CLI_NAME"
[ -x "$APP_BIN" ] || { echo "build produced no app executable at $APP_BIN" >&2; exit 1; }
[ -x "$CLI_BIN" ] || { echo "build produced no cli executable at $CLI_BIN" >&2; exit 1; }

DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"

# Only ever clear a path that is our own freshly-derived bundle path.
case "$APP" in
  "$ROOT"/dist/*.app) [ -d "$APP" ] && rm -rf "$APP" ;;
  *) echo "refusing to clear unexpected path: $APP" >&2; exit 1 ;;
esac

echo "==> Assembling $APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$APP_BIN" "$APP/Contents/MacOS/$BIN_NAME"
cp "$CLI_BIN" "$APP/Contents/MacOS/$CLI_NAME"

# The icon is drawn from source by the app itself rather than committed as a binary blob,
# so it stays diffable and can never drift from the palette the app draws with.
echo "==> Drawing the icon"
ICONSET="$DIST/$APP_NAME.iconset"
case "$ICONSET" in
  "$ROOT"/dist/*.iconset) [ -d "$ICONSET" ] && rm -rf "$ICONSET" ;;
  *) echo "refusing to clear unexpected path: $ICONSET" >&2; exit 1 ;;
esac
"$APP_BIN" --render-icon "$ICONSET" > /dev/null
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleExecutable</key><string>$BIN_NAME</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleName</key><string>$BIN_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSSupportsAutomaticTermination</key><false/>
    <key>NSSupportsSuddenTermination</key><false/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> Signing (ad-hoc)"
codesign --force --sign - --identifier "$BUNDLE_ID" "$APP/Contents/MacOS/$CLI_NAME"
codesign --force --sign - --identifier "$BUNDLE_ID" "$APP"
codesign --verify --deep --strict "$APP" && echo "    signature OK"

echo
echo "Built: $APP"
echo
echo "Run it:  open \"$APP\""
echo "CLI:     \"$APP/Contents/MacOS/$CLI_NAME\" --help"
echo
echo "For Start at Login and the kurura command to stick, move it somewhere permanent:"
echo "  cp -R \"$APP\" /Applications/"
echo "then use Settings → Terminal → Install to put kurura on your PATH."
