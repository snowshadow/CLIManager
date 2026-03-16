#!/usr/bin/env bash
set -euo pipefail

APP_NAME="CLIManagerApp"
BUNDLE_ID="local.alfred.CLIManagerApp"
MIN_MACOS="13.0"
INSTALL_DIR="${HOME}/Applications"
APP_DIR="${INSTALL_DIR}/${APP_NAME}.app"
ICON_SOURCE="assets/AppIcon.icns"
OPEN_AFTER=false

usage() {
  cat <<USAGE
Usage: $(basename "$0") [--open]

Options:
  --open   Open app after install/update
  -h, --help  Show this help
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --open)
      OPEN_AFTER=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "$PROJECT_ROOT"

echo "[1/4] Building ${APP_NAME} and CLIManagerCLI (release)..."
swift build -c release --product "${APP_NAME}"
swift build -c release --product CLIManagerCLI

echo "[2/4] Preparing app bundle..."
mkdir -p "${APP_DIR}/Contents/MacOS" "${APP_DIR}/Contents/Resources"
cp ".build/release/${APP_NAME}" "${APP_DIR}/Contents/MacOS/${APP_NAME}"
cp ".build/release/CLIManagerCLI" "${APP_DIR}/Contents/MacOS/CLIManagerCLI"
chmod +x "${APP_DIR}/Contents/MacOS/${APP_NAME}"
chmod +x "${APP_DIR}/Contents/MacOS/CLIManagerCLI"

echo "[3/4] Writing Info.plist..."
cat > "${APP_DIR}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>${APP_NAME}</string>
  <key>CFBundleDisplayName</key><string>${APP_NAME}</string>
  <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleExecutable</key><string>${APP_NAME}</string>
  <key>LSMinimumSystemVersion</key><string>${MIN_MACOS}</string>
</dict>
</plist>
PLIST

if [[ -f "${ICON_SOURCE}" ]]; then
  cp "${ICON_SOURCE}" "${APP_DIR}/Contents/Resources/AppIcon.icns"
  /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "${APP_DIR}/Contents/Info.plist" >/dev/null 2>&1 || \
    /usr/libexec/PlistBuddy -c "Set :CFBundleIconFile AppIcon" "${APP_DIR}/Contents/Info.plist"
fi

/usr/bin/touch "${APP_DIR}"

echo "[4/4] Installed: ${APP_DIR}"

if [[ "$OPEN_AFTER" == true ]]; then
  echo "Opening app..."
  open -a "${APP_DIR}"
fi

echo "Done."
