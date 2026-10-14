#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

rm -rf out
mkdir -p out/LightTodo.app/Contents/{MacOS,Resources} out/LightTodo.iconset

for size in 16 32 128 256 512; do
  sips -z "$size" "$size" icon.png --out "out/LightTodo.iconset/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z "$double" "$double" icon.png --out "out/LightTodo.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns out/LightTodo.iconset -o out/LightTodo.app/Contents/Resources/LightTodo.icns

SDK=$(xcrun --sdk macosx --show-sdk-path)
COMPILE_LOG=out/swiftc.log
: > "$COMPILE_LOG"
for arch in arm64 x86_64; do
  if ! xcrun swiftc -swift-version 5 -O -sdk "$SDK" -target "$arch-apple-macosx12.0" -framework AppKit -framework UniformTypeIdentifiers LightTodo.swift -o "out/LightTodo-$arch" 2>>"$COMPILE_LOG"; then
    echo "----- swiftc error log -----" >&2
    cat "$COMPILE_LOG" >&2
    echo "----- end log -----" >&2
    error_text=$(grep "error:" "$COMPILE_LOG" | head -n 20 | tr '\n' '|' | sed 's/,/ /g')
    echo "::error file=LightTodo.swift::swiftc $arch: $error_text" >&2
    if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
      {
        echo "## Swift compile errors ($arch)"
        echo '```'
        grep "error:" "$COMPILE_LOG" | head -n 20 || true
        echo '```'
      } >> "$GITHUB_STEP_SUMMARY"
    fi
    exit 1
  fi
done
lipo -create out/LightTodo-arm64 out/LightTodo-x86_64 -output out/LightTodo.app/Contents/MacOS/LightTodo

cat > out/LightTodo.app/Contents/Info.plist <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>LightTodo</string>
<key>CFBundleIdentifier</key><string>local.lighttodo.native</string>
<key>CFBundleName</key><string>LightTodo</string>
<key>CFBundleDisplayName</key><string>轻量待办</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.4.0</string>
<key>CFBundleVersion</key><string>5</string>
<key>CFBundleIconFile</key><string>LightTodo.icns</string>
<key>LSMinimumSystemVersion</key><string>12.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST

codesign --force --sign - out/LightTodo.app
codesign --verify --strict --verbose=2 out/LightTodo.app
file out/LightTodo.app/Contents/MacOS/LightTodo

mkdir -p out/verification
out/LightTodo.app/Contents/MacOS/LightTodo --self-test "$PWD/out/verification"

mkdir -p out/package
ditto out/LightTodo.app out/package/LightTodo.app
cp README.txt out/package/README.txt
ditto -c -k --sequesterRsrc --keepParent out/package out/LightTodo-mac-universal.zip
shasum -a 256 out/LightTodo-mac-universal.zip > out/SHA256.txt
