#!/bin/bash
# build-install.sh — build Chiva, sign with the STABLE "Chiva Dev" identity,
# and install to /Applications/Chiva.app (verified replace).
#
# Run scripts/dev-signing-setup.sh once first to create the identity.
# For the Divvy2 → Chiva cutover (login unregister + prefs + old path cleanup),
# prefer scripts/chiva-cutover.sh which invokes this after transitional cleanup.
#
# Env overrides: IDENTITY (default "Chiva Dev"), CONFIG (default Release), DEST.
set -euo pipefail
cd "$(dirname "$0")/.."

IDENTITY="${IDENTITY:-Chiva Dev}"
CONFIG="${CONFIG:-Release}"
DEST="${DEST:-/Applications}"
DD="/tmp/chiva-dd"
LOG="/tmp/chiva-build.log"
PW_FILE="$HOME/.config/chiva/signing-kc.pw"
KC="$HOME/Library/Keychains/chiva-signing.keychain-db"

# If the identity lives in the dedicated dev keychain, unlock it (no-op for login keychain).
[[ -f "$PW_FILE" && -f "$KC" ]] && security unlock-keychain -p "$(cat "$PW_FILE")" "$KC" 2>/dev/null || true

if ! security find-identity 2>/dev/null | grep -q "$IDENTITY"; then
  echo "✗ signing identity '$IDENTITY' not found — run scripts/dev-signing-setup.sh first." >&2
  exit 1
fi

echo "→ building ($CONFIG)..."
xcodebuild -project Rectangle.xcodeproj -scheme Rectangle -configuration "$CONFIG" \
  -derivedDataPath "$DD" \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$IDENTITY" DEVELOPMENT_TEAM="" \
  CODE_SIGNING_REQUIRED=YES CODE_SIGNING_ALLOWED=YES build \
  > "$LOG" 2>&1 || { echo "✗ build failed — see $LOG" >&2; tail -20 "$LOG"; exit 1; }

PRODUCTS="$DD/Build/Products/$CONFIG"
APP="$PRODUCTS/Chiva.app"

resign_app() {
  local target="$1"
  echo "→ re-signing nested code + app with '$IDENTITY'..."
  # NOTE: no --options runtime. Hardened runtime turns on Library Validation, which
  # rejects the embedded Sparkle.framework (self-signed identity has no Team ID).
  sign() { codesign --force --timestamp=none --sign "$IDENTITY" "$1"; }
  local SPK="$target/Contents/Frameworks/Sparkle.framework/Versions/B"
  for n in "$SPK"/XPCServices/*.xpc "$SPK"/Autoupdate "$SPK"/Updater.app; do [[ -e "$n" ]] && sign "$n"; done
  for fw in "$target"/Contents/Frameworks/*.framework; do [[ -e "$fw" ]] && sign "$fw"; done
  # Embedded login item
  local LI
  for LI in "$target"/Contents/Library/LoginItems/*.app; do
    [[ -e "$LI" ]] && sign "$LI"
  done
  sign "$target"
  codesign --verify --deep --strict "$target" && echo "  ✓ signature valid ($target)"
  codesign -dv "$target" 2>&1 | grep -iE "Authority|Identifier=" | sed 's/^/  /'
}

resign_app "$APP"

echo "→ installing to $DEST/Chiva.app (verified replace)..."
osascript -e 'quit app "Chiva"' 2>/dev/null || true
pkill -x "Chiva" 2>/dev/null || true; sleep 1
mkdir -p "$DEST"
rm -rf "$DEST/Chiva.app"
ditto "$APP" "$DEST/Chiva.app"
codesign --verify --deep --strict "$DEST/Chiva.app"

BID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$DEST/Chiva.app/Contents/Info.plist")
NAME=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$DEST/Chiva.app/Contents/Info.plist" 2>/dev/null || true)
SCHEME=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleURLTypes:0:CFBundleURLSchemes:0' "$DEST/Chiva.app/Contents/Info.plist" 2>/dev/null || true)
echo "  CFBundleIdentifier=$BID"
echo "  CFBundleDisplayName=$NAME"
echo "  URLScheme=$SCHEME"
[[ "$BID" == "com.perg593.chiva" ]] || { echo "✗ unexpected bundle id: $BID" >&2; exit 1; }
[[ "$SCHEME" == "chiva" ]] || { echo "✗ unexpected URL scheme: $SCHEME" >&2; exit 1; }

# Embedded launcher id
LAUNCHER_PLIST="$DEST/Chiva.app/Contents/Library/LoginItems/RectangleLauncher.app/Contents/Info.plist"
if [[ -f "$LAUNCHER_PLIST" ]]; then
  LBID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$LAUNCHER_PLIST")
  echo "  launcher CFBundleIdentifier=$LBID"
  [[ "$LBID" == "com.perg593.chiva.launcher" ]] || { echo "✗ unexpected launcher id: $LBID" >&2; exit 1; }
fi

LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
"$LSREGISTER" -f "$DEST/Chiva.app" 2>/dev/null || true

if [[ "${SKIP_LAUNCH:-}" != "1" ]]; then
  echo "→ launching..."
  open "$DEST/Chiva.app"
fi
echo "✓ installed $DEST/Chiva.app"
echo "  Grant Accessibility once if needed:"
echo "  System Settings ▸ Privacy & Security ▸ Accessibility ▸ + ▸ $DEST/Chiva.app"
echo "  Remove any stale entry for ~/Applications/Divvy2/Chiva.app."
