#!/bin/zsh
set -euo pipefail
name="HyprOSX Local Signing"
if security find-identity -p codesigning | grep -q "\"$name\""; then
    print "\"$name\" already exists"
    exit 0
fi
ssl="${OPENSSL:-openssl}"
legacy=()
"$ssl" version | grep -q '^OpenSSL 3' && legacy=(-legacy)
work="$(mktemp -d)"
trap 'rm -f "$work/key.pem" "$work/cert.pem" "$work/identity.p12"; rmdir "$work"' EXIT
"$ssl" req -x509 -newkey rsa:2048 -nodes -days 3650 -keyout "$work/key.pem" -out "$work/cert.pem" -subj "/CN=$name" \
    -addext "basicConstraints=critical,CA:false" -addext "keyUsage=critical,digitalSignature" -addext "extendedKeyUsage=critical,codeSigning"
password="$("$ssl" rand -hex 16)"
"$ssl" pkcs12 -export $legacy -inkey "$work/key.pem" -in "$work/cert.pem" -name "$name" -out "$work/identity.p12" -passout "pass:$password"
security import "$work/identity.p12" -k "$HOME/Library/Keychains/login.keychain-db" -P "$password" -T /usr/bin/codesign
security find-identity -p codesigning | grep "\"$name\""
