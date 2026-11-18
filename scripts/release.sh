#!/bin/zsh
# Yeni sürüm yayınlar: .dmg derler, Sparkle appcast'ini imzalar, GitHub Release açar.
# Önce project.yml'de MARKETING_VERSION ve CURRENT_PROJECT_VERSION artırılıp commit'lenmiş olmalı.
# İmza anahtarı yalnız bu Mac'in Anahtar Zinciri'nde (generate_keys ile oluşturuldu).
set -euo pipefail
cd "$(dirname "$0")/.."
repo=Melbergmbk/etodo

[[ -z "$(git status --porcelain)" ]] || { echo "Kaydedilmemiş değişiklik var; önce commit'le."; exit 1; }
dmg=$(scripts/build-dmg.sh | tail -1)
version=${${dmg:t:r}#Etodo-}
tag=v$version
git rev-parse -q --verify "refs/tags/$tag" >/dev/null && { echo "$tag zaten var; sürümü artır."; exit 1; }

feed=$(mktemp -d)
trap 'rm -rf "$feed"' EXIT
cp "$dmg" "$feed/"
build/dd/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast \
  --download-url-prefix "https://github.com/$repo/releases/download/$tag/" "$feed"

# README'deki sabit indirme bağlantısı için sürümsüz adlı bir kopya da yüklenir.
stable=$(mktemp -d)/Etodo.dmg
cp "$dmg" "$stable"

git tag "$tag"
git push origin "$tag"
gh release create "$tag" "$dmg" "$stable" "$feed/appcast.xml" --repo "$repo" --title "Etodo $version" \
  --notes "Kurulum için: https://github.com/$repo#kurulum"
echo "Yayınlandı: https://github.com/$repo/releases/tag/$tag"
