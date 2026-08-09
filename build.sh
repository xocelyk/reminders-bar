#!/bin/zsh
# Builds RemindersBar.app into dist/ and (with --install) copies it to /Applications.
# Compiles with plain swiftc — no Xcode or SwiftPM required, just Command Line Tools.
set -euo pipefail
cd "$(dirname "$0")"

APP="dist/RemindersBar.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

swiftc -O -parse-as-library \
    -target arm64-apple-macos14.0 \
    Sources/RemindersBar/*.swift \
    -o "$APP/Contents/MacOS/RemindersBar"

cp Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
codesign --force --sign - "$APP"

echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
    osascript -e 'quit app "RemindersBar"' 2>/dev/null || true
    rm -rf /Applications/RemindersBar.app
    cp -R "$APP" /Applications/RemindersBar.app
    echo "Installed to /Applications/RemindersBar.app"
fi
