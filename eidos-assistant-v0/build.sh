#!/bin/bash
set -e

echo "Building Eidos Assistant..."
swift build -c release 2>&1 | grep -E "(Build complete|error:)"

APP="build/Eidos Assistant.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp .build/release/EidosAssistant "$APP/Contents/MacOS/Eidos Assistant"
cp Sources/EidosAssistant/Info.plist "$APP/Contents/Info.plist"
[ -f /tmp/AppIcon.icns ] && cp /tmp/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Install to /Applications
echo "Installing to /Applications..."
pkill -f "Eidos Assistant" 2>/dev/null || true
sleep 0.5
cp -R "$APP" "/Applications/Eidos Assistant.app"

echo "Done. Opening..."
open "/Applications/Eidos Assistant.app"
