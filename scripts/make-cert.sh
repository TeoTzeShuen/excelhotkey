#!/bin/sh
# One-time: create a self-signed code-signing identity in the login keychain so every rebuild
# has the same signature and macOS keeps the Accessibility permission across rebuilds.
set -eu
NAME="ExcelHotkey Local Signing"

if security find-certificate -c "$NAME" >/dev/null 2>&1; then
  echo "Identity '$NAME' already exists."
  exit 0
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cat >"$tmp/cert.conf" <<EOF
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
EOF

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$tmp/cert.conf" \
  -keyout "$tmp/key.pem" -out "$tmp/cert.pem" 2>/dev/null
# -legacy: macOS `security` cannot read OpenSSL 3's default PKCS#12 encryption.
legacy=""
openssl pkcs12 -help 2>&1 | grep -q -- -legacy && legacy="-legacy"
openssl pkcs12 -export $legacy -inkey "$tmp/key.pem" -in "$tmp/cert.pem" \
  -name "$NAME" -passout pass:excelhotkey -out "$tmp/id.p12"
security import "$tmp/id.p12" -k "$HOME/Library/Keychains/login.keychain-db" \
  -P excelhotkey -T /usr/bin/codesign
echo "Created identity '$NAME'."
