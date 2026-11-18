#!/bin/zsh
# Release derlemesi (Apple Silicon + Intel) → ad-hoc imza → Uygulamalar kısayollu .dmg
# Kullanım: scripts/build-dmg.sh   Çıktı: build/Etodo-<sürüm>.dmg
set -euo pipefail
cd "$(dirname "$0")/.."

xcodegen -q
xcodebuild -scheme Etodo -configuration Release -derivedDataPath build/rel \
  -destination 'generic/platform=macOS' ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
  build -quiet

app=build/rel/Build/Products/Release/Etodo.app
version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$app/Contents/Info.plist")
# Hep aynı sertifikayla imzalanırsa macOS güncellemeden sonra da "aynı uygulama" der; izinler korunur.
# Sertifika: scripts/make-signing-cert.sh (bir kez). Yoksa geçici (ad-hoc) imza.
identity="Etodo - Melih Bugra Karasin"
if security find-certificate -c "$identity" >/dev/null 2>&1; then
  codesign --force --deep -s "$identity" "$app"
elif [[ -n "${ETODO_REQUIRE_CERT:-}" ]]; then
  echo "İmza sertifikası yok: önce scripts/make-signing-cert.sh çalıştır." >&2; exit 1
else
  echo "Uyarı: sertifika yok, geçici imza kullanılıyor." >&2
  codesign --force --deep -s - "$app"
fi
codesign --verify --deep --strict "$app"

stage=$(mktemp -d)
trap 'rm -rf "$stage" "$stage.rw.dmg"' EXIT
cp -R "$app" "$stage/"
ln -s /Applications "$stage/Uygulamalar"

mkdir "$stage/.background"
cp scripts/dmg-background.tiff "$stage/.background/background.tiff"
chflags hidden "$stage/.background"

dmg=build/Etodo-$version.dmg
rw=$stage.rw.dmg
rm -f "$dmg" "$rw"
hdiutil create -volname "Etodo" -srcfolder "$stage" -fs HFS+ -format UDRW -ov "$rw" >/dev/null
mnt=$(hdiutil attach "$rw" -nobrowse -noautoopen | awk -F'\t' '/\/Volumes\//{print $NF}')
# Aynı adlı başka bir disk açıksa bu "Etodo 1" olarak bağlanır; AppleScript gerçek adı kullanmalı.
volname=${mnt:t}
# Pencere düzeni (arka plan, simge yerleri) Finder'a AppleScript ile verilir; izin yoksa düz pencereyle devam edilir.
osascript <<OSA || echo "Uyarı: Finder pencere düzeni uygulanamadı (Otomasyon izni?)." >&2
tell application "Finder"
  tell disk "$volname"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 800, 528}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 112
    set text size of opts to 13
    set background picture of opts to file ".background:background.tiff"
    set position of item "Etodo.app" of container window to {150, 170}
    set position of item "Uygulamalar" of container window to {450, 170}
    -- Gizli dosyaları gösteren Mac'lerde de görünmesin diye pencere dışına.
    try
      set position of item ".background" of container window to {150, 700}
    end try
    update without registering applications
    delay 1
    close
    open
    delay 1
    close
  end tell
  delay 2
  tell disk "$volname"
  end tell
end tell
OSA
sync
hdiutil detach "$mnt" -quiet
hdiutil convert "$rw" -format UDZO -imagekey zlib-level=9 -o "$dmg" >/dev/null
rm -f "$rw"
echo "$dmg"
