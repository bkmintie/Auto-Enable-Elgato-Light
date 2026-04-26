#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Auto Enable Elgato Light"
DMG_NAME="AutoEnableElgatoLight"
CONFIGURATION="${CONFIGURATION:-release}"
APP_DIR="$ROOT/.build/$APP_NAME.app"
STAGING_DIR="$ROOT/.build/dmg-staging"
ARTIFACT_DIR="$ROOT/.build/artifacts"
DMG_PATH="$ARTIFACT_DIR/$DMG_NAME.dmg"
VOLUME_NAME="$APP_NAME"

CONFIGURATION="$CONFIGURATION" "$ROOT/scripts/build-app.sh" >/dev/null

rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR" "$ARTIFACT_DIR"
cp -R "$APP_DIR" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

rm -f "$DMG_PATH"
hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

echo "$DMG_PATH"
