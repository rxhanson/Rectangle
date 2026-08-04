#!/bin/bash
# chiva-cutover.sh — one-shot Divvy2 → Chiva identity cutover.
#
# 1) Mint/reuse "Chiva Dev" signing identity
# 2) Build a transitional old-ID binary (com.perg593.divvy2) with --unregister-login
# 3) Install to ~/Applications/Divvy2 and unregister old login services
# 4) Prefs export/import belt-and-suspenders (in-app IdentityMigration is authoritative)
# 5) Build+install real Chiva to /Applications/Chiva.app
# 6) Remove old Divvy2 apps
set -euo pipefail
cd "$(dirname "$0")/.."

IDENTITY="${IDENTITY:-Chiva Dev}"
CONFIG="${CONFIG:-Release}"
OLD_DEST="$HOME/Applications/Divvy2"
NEW_DEST="/Applications"
DD_CUTOVER="/tmp/chiva-cutover-dd"
LOG_CUTOVER="/tmp/chiva-cutover-build.log"
PW_FILE="$HOME/.config/chiva/signing-kc.pw"
KC="$HOME/Library/Keychains/chiva-signing.keychain-db"

sign_tree() {
  local target="$1"
  sign() { codesign --force --timestamp=none --sign "$IDENTITY" "$1"; }
  local SPK="$target/Contents/Frameworks/Sparkle.framework/Versions/B"
  for n in "$SPK"/XPCServices/*.xpc "$SPK"/Autoupdate "$SPK"/Updater.app; do [[ -e "$n" ]] && sign "$n"; done
  for fw in "$target"/Contents/Frameworks/*.framework; do [[ -e "$fw" ]] && sign "$fw"; done
  local LI
  for LI in "$target"/Contents/Library/LoginItems/*.app; do
    [[ -e "$LI" ]] && sign "$LI"
  done
  sign "$target"
  codesign --verify --deep --strict "$target"
}

echo "→ ensuring signing identity..."
scripts/dev-signing-setup.sh
[[ -f "$PW_FILE" && -f "$KC" ]] && security unlock-keychain -p "$(cat "$PW_FILE")" "$KC" 2>/dev/null || true

echo "→ quitting Chiva..."
osascript -e 'quit app "Chiva"' 2>/dev/null || true
pkill -x "Chiva" 2>/dev/null || true
sleep 1

echo "→ transitional old-ID build (com.perg593.divvy2) for login unregister..."
xcodebuild -project Rectangle.xcodeproj -scheme Rectangle -configuration "$CONFIG" \
  -derivedDataPath "$DD_CUTOVER" \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$IDENTITY" DEVELOPMENT_TEAM="" \
  CODE_SIGNING_REQUIRED=YES CODE_SIGNING_ALLOWED=YES \
  PRODUCT_BUNDLE_IDENTIFIER=com.perg593.divvy2 \
  build > "$LOG_CUTOVER" 2>&1 \
  || { echo "✗ transitional build failed — see $LOG_CUTOVER" >&2; tail -40 "$LOG_CUTOVER"; exit 1; }

TRANS_APP="$DD_CUTOVER/Build/Products/$CONFIG/Chiva.app"
# Rewrite Info.plist IDs (global PRODUCT_BUNDLE_IDENTIFIER may also affect login item).
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier com.perg593.divvy2' "$TRANS_APP/Contents/Info.plist"
for LI_PLIST in "$TRANS_APP"/Contents/Library/LoginItems/*/Contents/Info.plist; do
  [[ -e "$LI_PLIST" ]] || continue
  /usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier com.perg593.divvy2.RectangleLauncher' "$LI_PLIST"
done
sign_tree "$TRANS_APP"

mkdir -p "$OLD_DEST"
rm -rf "$OLD_DEST/Chiva.app"
ditto "$TRANS_APP" "$OLD_DEST/Chiva.app"
codesign --verify --deep --strict "$OLD_DEST/Chiva.app"

echo "→ unregistering old login services..."
if "$OLD_DEST/Chiva.app/Contents/MacOS/Chiva" --unregister-login; then
  echo "  ✓ --unregister-login exited 0"
else
  echo "⚠ --unregister-login failed." >&2
  echo "  Manually remove Chiva/Divvy2 from System Settings ▸ General ▸ Login Items," >&2
  echo "  then re-run, or continue if already clear." >&2
fi

echo "→ prefs belt-and-suspenders (defaults export/import)..."
OLD_PLIST="$HOME/Library/Preferences/com.perg593.divvy2.plist"
NEW_PLIST="$HOME/Library/Preferences/com.perg593.chiva.plist"
if [[ -f "$OLD_PLIST" && ! -f "$NEW_PLIST" ]]; then
  TMP=$(mktemp)
  defaults export com.perg593.divvy2 "$TMP"
  # Remap custom layouts key inside the exported plist if present
  if plutil -extract 'com.perg593.divvy2.customLayouts' raw "$TMP" >/dev/null 2>&1; then
    # Convert to XML, rename key via python
    plutil -convert xml1 "$TMP"
    python3 - "$TMP" <<'PY'
import sys, plistlib
path = sys.argv[1]
with open(path, 'rb') as f:
    d = plistlib.load(f)
old_k = 'com.perg593.divvy2.customLayouts'
new_k = 'com.perg593.chiva.customLayouts'
if old_k in d and new_k not in d:
    d[new_k] = d.pop(old_k)
elif old_k in d:
    d.pop(old_k)
with open(path, 'wb') as f:
    plistlib.dump(d, f)
PY
  fi
  defaults import com.perg593.chiva "$TMP"
  rm -f "$TMP"
  echo "  ✓ imported prefs into com.perg593.chiva"
else
  echo "  (skip: no old plist or new already exists — in-app migration will handle)"
fi

echo "→ building & installing real Chiva identity to ${NEW_DEST}..."
SKIP_LAUNCH=1 scripts/build-install.sh

echo "→ removing old Divvy2 apps..."
rm -rf "$OLD_DEST/Chiva.app" "$OLD_DEST/Divvy2SpikeHelper.app"
rmdir "$OLD_DEST" 2>/dev/null || true

LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
"$LSREGISTER" -u "$OLD_DEST/Chiva.app" 2>/dev/null || true
"$LSREGISTER" -f "$NEW_DEST/Chiva.app" 2>/dev/null || true

echo "→ launching /Applications/Chiva.app..."
open "$NEW_DEST/Chiva.app"

echo ""
echo "✓ cutover complete."
echo "  Next:"
echo "  1. System Settings ▸ Privacy & Security ▸ Accessibility ▸ enable /Applications/Chiva.app"
echo "  2. Remove any stale Accessibility entry for ~/Applications/Divvy2/Chiva.app"
echo "  3. If Launch at Login was on, the new app re-registers itself on launch when prefs migrate"
