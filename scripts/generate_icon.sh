#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ASSETS_DIR="${PROJECT_ROOT}/assets"
ICONSET_DIR="${ASSETS_DIR}/AppIcon.iconset"
MASTER_PNG="${ASSETS_DIR}/AppIcon-1024.png"
ICNS_FILE="${ASSETS_DIR}/AppIcon.icns"

mkdir -p "${ASSETS_DIR}"
rm -rf "${ICONSET_DIR}"
mkdir -p "${ICONSET_DIR}"

swift - <<'SWIFT' "${MASTER_PNG}"
import AppKit
import Foundation

let outPath = CommandLine.arguments[1]
let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size)

image.lockFocus()

let rect = NSRect(origin: .zero, size: size)
let background = NSBezierPath(roundedRect: rect.insetBy(dx: 24, dy: 24), xRadius: 210, yRadius: 210)
let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.10, green: 0.36, blue: 0.93, alpha: 1.0),
    NSColor(calibratedRed: 0.07, green: 0.60, blue: 0.83, alpha: 1.0)
])!
gradient.draw(in: background, angle: -35)

let glow = NSBezierPath(ovalIn: NSRect(x: 150, y: 570, width: 720, height: 340))
NSColor(calibratedWhite: 1.0, alpha: 0.10).setFill()
glow.fill()

let panel = NSBezierPath(roundedRect: NSRect(x: 190, y: 220, width: 644, height: 520), xRadius: 52, yRadius: 52)
NSColor(calibratedWhite: 1.0, alpha: 0.14).setFill()
panel.fill()

let lineColor = NSColor(calibratedWhite: 1.0, alpha: 0.9)
lineColor.setStroke()

let stroke = NSBezierPath()
stroke.lineWidth = 40
stroke.lineCapStyle = .round
stroke.move(to: NSPoint(x: 300, y: 630))
stroke.line(to: NSPoint(x: 300, y: 320))
stroke.move(to: NSPoint(x: 300, y: 630))
stroke.line(to: NSPoint(x: 530, y: 510))
stroke.move(to: NSPoint(x: 300, y: 320))
stroke.line(to: NSPoint(x: 530, y: 440))
stroke.stroke()

let bar = NSBezierPath(roundedRect: NSRect(x: 560, y: 360, width: 210, height: 36), xRadius: 18, yRadius: 18)
lineColor.setFill()
bar.fill()

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fputs("Failed to generate PNG\n", stderr)
    exit(1)
}

try png.write(to: URL(fileURLWithPath: outPath), options: .atomic)
SWIFT

sizes=(16 32 64 128 256 512)
for size in "${sizes[@]}"; do
  sips -z "$size" "$size" "${MASTER_PNG}" --out "${ICONSET_DIR}/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z "$double" "$double" "${MASTER_PNG}" --out "${ICONSET_DIR}/icon_${size}x${size}@2x.png" >/dev/null
done

iconutil -c icns "${ICONSET_DIR}" -o "${ICNS_FILE}"
echo "Generated ${ICNS_FILE}"
