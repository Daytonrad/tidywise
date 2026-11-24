#!/bin/zsh
# Builds Tidywise.app. Needs only the Command Line Tools, not Xcode.
#
#   app/build.sh             build into app/build/
#   app/build.sh --install   also copy it to ~/Applications and start it (uses the `tidywise` from ./install.sh)
#   app/build.sh --release   also make app/dist/Tidywise.zip: the app with the Python part inside,
#                            ready to download and run without building anything
set -euo pipefail

DIR="${0:A:h}"
cd "$DIR"
BUILD="$DIR/build"
APP="$BUILD/Tidywise.app"
VERSION=$(grep -m1 '^version' ../pyproject.toml | sed -E 's/.*"(.*)".*/\1/')

echo "→ Compiling"
swift build -c release 2>&1 | grep -E "error|warning: |Compiling|Build complete" || true
BIN="$(swift build -c release --show-bin-path)/TidywiseApp"
[[ -x "$BIN" ]] || { echo "Build failed"; exit 1; }

echo "→ Icon"
mkdir -p "$BUILD"
if [[ ! -f "$BUILD/AppIcon.icns" || scripts/make_icon.swift -nt "$BUILD/AppIcon.icns" ]]; then
  ICONSET="$BUILD/AppIcon.iconset"
  rm -rf "$ICONSET" && mkdir -p "$ICONSET"
  swift scripts/make_icon.swift "$BUILD/icon_1024.png"
  for s in 16 32 128 256 512; do
    sips -z $s $s "$BUILD/icon_1024.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    sips -z $((s*2)) $((s*2)) "$BUILD/icon_1024.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$BUILD/AppIcon.icns"
fi

echo "→ App bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Tidywise"
# Remove debug information: it contains the full paths of the source files on the Mac that built the app
# (including the user name). The app does not need it to run.
strip -S -x "$APP/Contents/MacOS/Tidywise" 2>/dev/null
cp "$BUILD/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Tidywise</string>
    <key>CFBundleDisplayName</key><string>Tidywise</string>
    <key>CFBundleIdentifier</key><string>local.tidywise.app</string>
    <key>CFBundleExecutable</key><string>Tidywise</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>$(date +%Y%m%d%H%M)</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSDownloadsFolderUsageDescription</key><string>Tidywise sorts loose files from the folders you chose into topic folders.</string>
    <key>NSDocumentsFolderUsageDescription</key><string>Tidywise sorts loose files from the folders you chose into topic folders.</string>
    <key>NSDesktopFolderUsageDescription</key><string>Tidywise sorts loose files from the folders you chose into topic folders.</string>
</dict>
</plist>
PLIST
codesign --force --sign - "$APP" >/dev/null 2>&1
echo "✓ $APP"

if [[ "${1:-}" == "--install" ]]; then
  mkdir -p "$HOME/Applications"
  pkill -x Tidywise 2>/dev/null && sleep 1 || true
  rm -rf "$HOME/Applications/Tidywise.app"
  cp -R "$APP" "$HOME/Applications/Tidywise.app"
  open "$HOME/Applications/Tidywise.app"
  echo "✓ installed: ~/Applications/Tidywise.app"
fi

if [[ "${1:-}" == "--release" ]]; then
  echo "→ Download package"
  DIST="$DIR/dist"
  REL="$DIST/Tidywise.app"
  PYDIR="$REL/Contents/Resources/python"
  rm -rf "$DIST" && mkdir -p "$DIST"
  cp -R "$APP" "$REL"
  mkdir -p "$PYDIR"
  # The Python part goes inside the app; the app finds a Python on the Mac and runs it from there.
  rsync -a --exclude __pycache__ ../tidywise "$PYDIR/"
  # pypdf (pure Python, BSD licence) reads the text of PDFs. Taken from the project's Python environment.
  SITE=$(../.venv/bin/python -c 'import os, pypdf; print(os.path.dirname(os.path.dirname(pypdf.__file__)))')
  rsync -a --exclude __pycache__ "$SITE/pypdf" "$PYDIR/"
  find "$SITE" -maxdepth 3 -path "*pypdf-*" -iname "LICENSE*" -exec cp {} "$PYDIR/pypdf/LICENSE" \; -quit
  [[ -f "$PYDIR/pypdf/LICENSE" ]] || { echo "pypdf licence file not found"; exit 1; }
  codesign --force --deep --sign - "$REL" >/dev/null 2>&1
  # Without extended attributes and resource forks: nothing from this Mac travels along in the download.
  xattr -cr "$REL"
  (cd "$DIST" && ditto -c -k --norsrc --noextattr --keepParent Tidywise.app Tidywise.zip)
  # Never publish a package that names the person or Mac it was built on.
  if unzip -p "$DIST/Tidywise.zip" | LC_ALL=C grep -a -q -e "$HOME" -e "$(id -un)"; then
    echo "✗ The package still contains this Mac's user name or home path – not publishing it."; rm -f "$DIST/Tidywise.zip"; exit 1
  fi
  echo "✓ $DIST/Tidywise.zip ($(du -h "$DIST/Tidywise.zip" | cut -f1 | tr -d ' '), version $VERSION, $(uname -m))"
fi
