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
codesign --force --deep -s - "$app"
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
# Pencere düzeni (arka plan, simge yerleri) Finder'a AppleScript ile verilir; izin yoksa düz pencereyle devam edilir.
osascript <<OSA || echo "Uyarı: Finder pencere düzeni uygulanamadı (Otomasyon izni?)." >&2
tell application "Finder"
  tell disk "Etodo"
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
  tell disk "Etodo"
  end tell
end tell
OSA
sync
hdiutil detach "$mnt" -quiet
hdiutil convert "$rw" -format UDZO -imagekey zlib-level=9 -o "$dmg" >/dev/null
rm -f "$rw"
echo "$dmg"
