#!/bin/bash
# dev-signing-setup.sh — create a STABLE self-signed code-signing identity for Chiva.
#
# Why: ad-hoc signing gives a new cdhash every build, so macOS treats each rebuild
# as a new app and drops the Accessibility (AX) grant. Signing with a stable identity
# keeps the app's designated requirement constant, so the AX grant survives rebuilds.
#
# This uses a DEDICATED keychain with a throwaway, auto-generated password (the standard
# CI pattern) so it never needs your login password and never pops a GUI "allow access"
# prompt. The cert is self-signed and only valid on this machine — it is NOT a real
# Apple Developer identity and cannot notarize or distribute.
#
# Idempotent: re-running reuses the existing cert (so the AX grant is preserved). Pass
# --force to regenerate from scratch (you will have to re-grant AX once afterward).
# After the Divvy2 → Chiva identity cutover, run once with --force to mint "Chiva Dev".
set -euo pipefail

IDENTITY_CN="Chiva Dev"
KC="$HOME/Library/Keychains/chiva-signing.keychain-db"
CFG_DIR="$HOME/.config/chiva"
PW_FILE="$CFG_DIR/signing-kc.pw"
FORCE="${1:-}"

mkdir -p "$CFG_DIR"; chmod 700 "$CFG_DIR"

if [[ "$FORCE" == "--force" ]]; then
  security delete-keychain "$KC" 2>/dev/null || true
  rm -f "$PW_FILE"
fi

# Reuse an existing '$IDENTITY_CN' in ANY keychain on the search list — creating a
# second cert with the same CN would (a) make codesign ambiguous and (b) change the
# designated requirement, breaking the AX grant. Only mint a new one if none exists.
# (find-identity without -v lists untrusted self-signed certs too, which is what we want.)
if [[ "$FORCE" != "--force" ]] && security find-identity 2>/dev/null | grep -q "$IDENTITY_CN"; then
  echo "✓ '$IDENTITY_CN' already present in the keychain search list — reusing it."
  security find-identity 2>/dev/null | grep "$IDENTITY_CN" | sed 's/^/   /'
  echo "  (use --force only on a machine where you want to mint a fresh cert)"
  exit 0
fi

# Throwaway keychain password (not your login password; stored 0600, gitignored).
KCPW="$(openssl rand -hex 24)"
P12PW="$(openssl rand -hex 24)"
umask 077
printf '%s' "$KCPW" > "$PW_FILE"; chmod 600 "$PW_FILE"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/codesign.cnf" <<'CNF'
[req]
distinguished_name = dn
prompt = no
[dn]
CN = Chiva Dev
[codesign_ext]
basicConstraints=critical,CA:false
keyUsage=critical,digitalSignature
extendedKeyUsage=critical,codeSigning
CNF

echo "→ generating self-signed code-signing cert ($IDENTITY_CN)..."
openssl genrsa -out "$TMP/key.pem" 2048 >/dev/null 2>&1
openssl req -x509 -new -key "$TMP/key.pem" -days 3650 \
  -out "$TMP/cert.pem" -config "$TMP/codesign.cnf" -extensions codesign_ext >/dev/null 2>&1
# LibreSSL's default p12 MAC/PBE isn't importable by macOS's Security framework;
# force the legacy SHA1/3DES algorithms it accepts.
openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
  -out "$TMP/identity.p12" -name "$IDENTITY_CN" -passout "pass:$P12PW" \
  -descert -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 >/dev/null 2>&1

echo "→ creating dedicated keychain ${KC}..."
security delete-keychain "$KC" 2>/dev/null || true
security create-keychain -p "$KCPW" "$KC"
security set-keychain-settings "$KC"            # no auto-lock timeout
security unlock-keychain -p "$KCPW" "$KC"
security import "$TMP/identity.p12" -k "$KC" -P "$P12PW" -T /usr/bin/codesign -A
# allow codesign to use the key non-interactively (uses THIS keychain's pw, not login)
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KCPW" "$KC" >/dev/null

# add to the user search list, keeping the existing keychains (handles paths with spaces)
existing=()
while IFS= read -r line; do
  line="${line#"${line%%[![:space:]]*}"}"   # ltrim
  line="${line%\"}"; line="${line#\"}"       # strip surrounding quotes
  [[ -n "$line" ]] && existing+=("$line")
done < <(security list-keychains -d user)
security list-keychains -d user -s "$KC" "${existing[@]}"

echo "→ verifying codesign can use the identity..."
cp /bin/echo "$TMP/signtest"
codesign --force --sign "$IDENTITY_CN" --keychain "$KC" "$TMP/signtest"
codesign -dv "$TMP/signtest" 2>&1 | grep -E "Authority|Signature" || true

echo "✓ done. Identity '$IDENTITY_CN' is ready in $KC."
echo "  Next: scripts/chiva-cutover.sh  (or scripts/build-install.sh)."
echo "  After first install with this identity, grant Accessibility ONCE."
