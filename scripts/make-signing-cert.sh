#!/bin/zsh
# Etodo sürümlerini imzalamak için bu Mac'e özel, ücretsiz, kendinden imzalı sertifika oluşturur (bir kez).
# Aynı sertifikayla imzalanan her sürümü macOS "aynı uygulama" sayar; Tam Disk Erişimi gibi izinler güncellemede korunur.
# Özel anahtar yalnız giriş Anahtar Zinciri'ne gider; geçici dosyalar silinir.
set -euo pipefail
name="Etodo - Melih Bugra Karasin"
keychain=~/Library/Keychains/login.keychain-db

if security find-certificate -c "$name" "$keychain" >/dev/null 2>&1; then
  echo "Sertifika zaten var: $name"
  exit 0
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cat > "$tmp/cfg" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $name
[ext]
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
basicConstraints = critical, CA:false
EOF

openssl req -x509 -newkey rsa:2048 -nodes -days 7300 -config "$tmp/cfg" \
  -keyout "$tmp/key.pem" -out "$tmp/cert.pem" 2>/dev/null
pass=$(openssl rand -hex 16)
# -legacy: macOS'un `security` aracı yeni OpenSSL'in varsayılan p12 şifrelemesini okuyamıyor.
openssl pkcs12 -export -legacy -inkey "$tmp/key.pem" -in "$tmp/cert.pem" -name "$name" \
  -out "$tmp/id.p12" -passout "pass:$pass"
security import "$tmp/id.p12" -k "$keychain" -P "$pass" -T /usr/bin/codesign

echo "Tamam: \"$name\" sertifikası Anahtar Zinciri'ne eklendi."
