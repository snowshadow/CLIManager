#!/usr/bin/env bash
set -euo pipefail

APP_NAME="CLIManagerApp"
BUNDLE_ID="local.alfred.CLIManagerApp"
MIN_MACOS="13.0"
VERSION="${VERSION:-$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || echo '1.0.0')}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DIST_DIR="${PROJECT_ROOT}/dist"
APP_DIR="${DIST_DIR}/${APP_NAME}.app"
DMG_PATH="${DIST_DIR}/${APP_NAME}-v${VERSION}.dmg"
ICON_SOURCE="${PROJECT_ROOT}/assets/AppIcon.icns"

cd "$PROJECT_ROOT"

echo "[1/5] Cleaning dist..."
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

echo "[2/5] Building ${APP_NAME} and CLIManagerCLI (release)..."
swift build -c release --product "${APP_NAME}"
swift build -c release --product CLIManagerCLI

echo "[3/5] Preparing app bundle..."
mkdir -p "${APP_DIR}/Contents/MacOS" "${APP_DIR}/Contents/Resources" "${APP_DIR}/Contents/Frameworks"
cp ".build/release/${APP_NAME}" "${APP_DIR}/Contents/MacOS/${APP_NAME}"
cp ".build/release/CLIManagerCLI" "${APP_DIR}/Contents/MacOS/CLIManagerCLI"
cp -R ".build/release/Sparkle.framework" "${APP_DIR}/Contents/Frameworks/Sparkle.framework"
chmod +x "${APP_DIR}/Contents/MacOS/${APP_NAME}"
chmod +x "${APP_DIR}/Contents/MacOS/CLIManagerCLI"

# Ensure Sparkle.framework can be found at runtime
install_name_tool -add_rpath "@executable_path/../Frameworks" "${APP_DIR}/Contents/MacOS/${APP_NAME}"

echo "[4/5] Writing Info.plist..."
cat > "${APP_DIR}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>${APP_NAME}</string>
  <key>CFBundleDisplayName</key><string>${APP_NAME}</string>
  <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleExecutable</key><string>${APP_NAME}</string>
  <key>LSMinimumSystemVersion</key><string>${MIN_MACOS}</string>
  <key>SUEnableInstallerLauncherService</key><true/>
  <key>SUFeedURL</key><string>https://github.com/alfredxia/CLIManager/releases/latest/download/appcast.xml</string>
</dict>
</plist>
PLIST

if [[ -f "${ICON_SOURCE}" ]]; then
  cp "${ICON_SOURCE}" "${APP_DIR}/Contents/Resources/AppIcon.icns"
  /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "${APP_DIR}/Contents/Info.plist" >/dev/null 2>&1 || \
    /usr/libexec/PlistBuddy -c "Set :CFBundleIconFile AppIcon" "${APP_DIR}/Contents/Info.plist"
fi

/usr/bin/touch "${APP_DIR}"

echo "[5/5] Creating DMG..."
hdiutil create -volname "${APP_NAME}" -srcfolder "${APP_DIR}" -ov -format UDZO "${DMG_PATH}"

echo "DMG created: ${DMG_PATH}"
