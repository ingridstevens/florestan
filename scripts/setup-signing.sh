#!/bin/zsh
# One-time: creates a local code-signing certificate, "Florestan Local Signing", in your login keychain.
# Signing every build with the same certificate lets macOS remember Florestan's permissions
# (Full Disk Access, controlling Music) across updates. macOS asks for your password once to trust it.
set -euo pipefail
NAME="Florestan Local Signing"

if security find-identity -v -p codesigning | grep -q "$NAME"; then
    echo "\"$NAME\" is already set up."
    exit 0
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
cat > "$WORK/cert.cnf" <<CNF
[req]
distinguished_name = dn
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
CNF

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$WORK/key.pem" -out "$WORK/cert.pem" -config "$WORK/cert.cnf" -extensions ext 2>/dev/null
PASS=$(openssl rand -hex 16)
openssl pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" -name "$NAME" \
    -out "$WORK/identity.p12" -passout "pass:$PASS" 2>/dev/null

security import "$WORK/identity.p12" -k ~/Library/Keychains/login.keychain-db -P "$PASS" -T /usr/bin/codesign >/dev/null
echo "Trusting the certificate for code signing (macOS will ask for your password)…"
security add-trusted-cert -r trustRoot -p codeSign -k ~/Library/Keychains/login.keychain-db "$WORK/cert.pem"

security find-identity -v -p codesigning | grep "$NAME" && echo "Done. Rebuild with ./scripts/build-app.sh."
