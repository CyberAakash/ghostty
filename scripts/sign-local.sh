#!/bin/bash
# Re-signs a locally built Ghostty.app with a stable, self-signed identity.
#
# Why: `zig build` signs ad hoc, and an ad hoc signature changes on every build. macOS ties
# privacy grants (Accessibility, Automation, ...) to the signature, so every rebuilt app looked
# like a new app and lost them. A fixed certificate gives every build the same identity.
#
# The certificate lives in its own keychain (~/.config/ghostty-signing), not your login keychain,
# and is only good for signing local builds. After the first run, grant the app its permissions
# once more; later rebuilds signed with this script keep them.
#
#   scripts/sign-local.sh zig-out/Ghostty.app            # sign in place
#   scripts/sign-local.sh zig-out/Ghostty.app --install  # sign, then copy to /Applications
set -euo pipefail

APP="${1:?usage: sign-local.sh path/to/Ghostty.app [--install]}"
DIR="$HOME/.config/ghostty-signing"
KEYCHAIN="$DIR/ghostty-signing.keychain-db"
PASSWORD="ghostty-local"   # protects nothing but a local-only signing key
NAME="Ghostty Local Signing"

setup() {
    mkdir -p "$DIR" && chmod 700 "$DIR"
    local work; work="$(mktemp -d)"
    cat > "$work/cert.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
subjectKeyIdentifier = hash
CNF
    openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$work/cert.cnf" \
        -keyout "$work/key.pem" -out "$work/cert.pem" 2>/dev/null
    openssl pkcs12 -export -inkey "$work/key.pem" -in "$work/cert.pem" \
        -out "$work/id.p12" -passout "pass:$PASSWORD"
    security create-keychain -p "$PASSWORD" "$KEYCHAIN"
    security set-keychain-settings "$KEYCHAIN"
    security unlock-keychain -p "$PASSWORD" "$KEYCHAIN"
    security import "$work/id.p12" -k "$KEYCHAIN" -P "$PASSWORD" -T /usr/bin/codesign >/dev/null
    security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$PASSWORD" "$KEYCHAIN" >/dev/null 2>&1
    rm -rf "$work"
    chmod 600 "$KEYCHAIN"
}

[ -f "$KEYCHAIN" ] || setup
security unlock-keychain -p "$PASSWORD" "$KEYCHAIN"

# codesign only uses identities macOS trusts, and trust needs your approval (a password prompt),
# so it cannot be granted from a script. Do it once, then re-run this script.
if ! security find-identity -v -p codesigning "$KEYCHAIN" | grep -q "$NAME"; then
    security find-certificate -c "$NAME" -p "$KEYCHAIN" > "$DIR/cert.pem"
    cat >&2 <<MSG
The signing certificate is not trusted yet. Run this once (it asks for your password), then re-run:

  security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$DIR/cert.pem"

MSG
    exit 1
fi

# codesign only finds the identity while its keychain is on the search list, so add it for the
# duration of this script and put your list back exactly as it was, even if signing fails.
ORIGINAL_KEYCHAINS=()
while IFS= read -r line; do ORIGINAL_KEYCHAINS+=("$(echo "$line" | tr -d '" ')"); done < <(security list-keychains -d user)
restore_keychains() { security list-keychains -d user -s "${ORIGINAL_KEYCHAINS[@]}"; }
trap restore_keychains EXIT
security list-keychains -d user -s "$KEYCHAIN" "${ORIGINAL_KEYCHAINS[@]}"

sign() {
    codesign --force --options runtime --timestamp=none --sign "$NAME" "$@"
}

# Keep the entitlements the build gave the app.
ENTITLEMENTS="$(mktemp)"
trap 'rm -f "$ENTITLEMENTS"; restore_keychains' EXIT
codesign -d --entitlements :- "$APP" 2>/dev/null > "$ENTITLEMENTS"

# Inside out: nested code first (deepest paths first), then the app.
while IFS= read -r nested; do
    sign --preserve-metadata=entitlements "$nested"
done < <(find "$APP/Contents" \( -name "*.xpc" -o -name "*.app" -o -name "*.framework" -o -name "Autoupdate" -o -name "*.dylib" \) -print \
    | awk '{ print length($0) " " $0 }' | sort -rn | cut -d' ' -f2-)

sign --entitlements "$ENTITLEMENTS" "$APP"

codesign --verify --deep --strict "$APP"
echo "signed: $(codesign -dr - "$APP" 2>&1 | grep -o 'certificate leaf.*' | head -1)"

if [ "${2:-}" = "--install" ]; then
    rm -rf /Applications/Ghostty.app
    cp -R "$APP" /Applications/Ghostty.app
    echo "installed to /Applications/Ghostty.app"
fi
