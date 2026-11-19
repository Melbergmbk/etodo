#!/bin/zsh
# Yeni sürüm yayınlar: .dmg derler, Sparkle appcast'ini imzalar, GitHub Release açar.
# Önce project.yml'de CURRENT_PROJECT_VERSION (ve yeni sürümse MARKETING_VERSION) artırılıp commit'lenmiş ve push'lanmış olmalı.
# Geliştirme döneminde aynı sürümü yenilemek için: ETODO_REPLACE=1 scripts/release.sh
#   (MARKETING_VERSION aynı kalır; yalnız CURRENT_PROJECT_VERSION artar, eski yayın silinip yerine yenisi konur.)
# İmza anahtarı ve kod imzalama sertifikası yalnız bu Mac'in Anahtar Zinciri'nde.
set -euo pipefail
cd "$(dirname "$0")/.."
repo=Melbergmbk/etodo

[[ -z "$(git status --porcelain)" ]] || { echo "Kaydedilmemiş değişiklik var; önce commit'le."; exit 1; }
git fetch -q origin main
[[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] || { echo "main GitHub'daki ile aynı değil; önce push'la."; exit 1; }

# Sparkle sürümleri CFBundleVersion (CURRENT_PROJECT_VERSION) ile karşılaştırır; artmazsa güncelleme kimseye görünmez.
build_no=$(awk '/CURRENT_PROJECT_VERSION:/{gsub(/"/,"",$2); print $2; exit}' project.yml)
last_tag=$(gh release list --repo "$repo" --limit 1 --json tagName --jq '.[0].tagName // ""')
if [[ -n "$last_tag" ]]; then
  git fetch -q origin "refs/tags/${last_tag}:refs/tags/${last_tag}"
  last_no=$(git show "${last_tag}:project.yml" | awk '/CURRENT_PROJECT_VERSION:/{gsub(/"/,"",$2); print $2; exit}')
  (( build_no > last_no )) || { echo "CURRENT_PROJECT_VERSION ($build_no) son sürümden ($last_tag: $last_no) büyük olmalı."; exit 1; }
fi

ETODO_REQUIRE_CERT=1 scripts/build-dmg.sh >/dev/null
dmg=$(ls -t build/Etodo-*.dmg | head -1)
version=${${dmg:t:r}#Etodo-}
tag=v$version
replace=
if gh release view "$tag" --repo "$repo" >/dev/null 2>&1; then
  [[ "${ETODO_REPLACE:-}" == 1 ]] || { echo "$tag zaten yayınlanmış; sürümü artır ya da ETODO_REPLACE=1 ile aynı sürümü yenile."; exit 1; }
  replace=1
fi

feed=$(mktemp -d)
stable_dir=$(mktemp -d)
trap 'rm -rf "$feed" "$stable_dir"' EXIT
cp "$dmg" "$feed/"
build/rel/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast \
  --download-url-prefix "https://github.com/$repo/releases/download/$tag/" "$feed"

# README'deki sabit indirme bağlantısı için sürümsüz adlı bir kopya da yüklenir.
cp "$dmg" "$stable_dir/Etodo.dmg"

# Aynı sürüm yenileniyorsa eski yayın ve etiketi kaldırılır (kısa aralıkta "en son" bir önceki yayına düşer; zararsız).
if [[ -n "$replace" ]]; then
  gh release delete "$tag" --repo "$repo" --cleanup-tag --yes
  git tag -d "$tag" >/dev/null 2>&1 || true
fi

# Etiketi GitHub kendisi oluşturur; gh başarısız olursa yerelde yarım etiket kalmaz.
gh release create "$tag" "$dmg" "$stable_dir/Etodo.dmg" "$feed/appcast.xml" --repo "$repo" \
  --target "$(git rev-parse HEAD)" --title "Etodo $version" \
  --notes "Kurulum için: https://github.com/$repo#kurulum"
git fetch -q origin "refs/tags/${tag}:refs/tags/${tag}"
echo "Yayınlandı: https://github.com/$repo/releases/tag/$tag"
