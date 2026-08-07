#!/usr/bin/env bash
set -euo pipefail

# Release a new version of CLIManager
# Usage: scripts/release.sh [major|minor|patch|X.Y.Z]
#   - major / minor / patch: bump that component from the latest git tag
#   - X.Y.Z: use exactly this version
#   - default: patch bump

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "$PROJECT_ROOT"

latest_tag=$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || echo "0.0.0")
echo "Current version: v${latest_tag}"

bump="${1:-patch}"

if [[ "${bump}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    new_version="${bump}"
else
    IFS='.' read -r major minor patch <<< "${latest_tag}"
    case "${bump}" in
        major) new_version="$((major + 1)).0.0" ;;
        minor) new_version="${major}.$((minor + 1)).0" ;;
        patch) new_version="${major}.${minor}.$((patch + 1))" ;;
        *) echo "Invalid bump level: ${bump} (use major|minor|patch|X.Y.Z)" >&2; exit 1 ;;
    esac
fi

echo "Next version:    v${new_version}"
echo ""

# 1. Verify clean build
echo "[1/4] Building and testing..."
swift build 2>&1 | tail -1
swift test 2>&1 | tail -1

# 2. Commit any pending changes
if ! git diff-index --quiet HEAD --; then
    echo "[2/4] Staging and committing changes..."
    git add -A
    git commit -m "chore: prepare v${new_version} release
Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
fi

# 3. Tag and push
echo "[3/4] Tagging v${new_version} and pushing..."
git tag "v${new_version}"
git push origin main --tags

# 4. Wait for CI release
echo "[4/4] Waiting for GitHub release..."
echo "Release: https://github.com/snowshadow/CLIManager/releases/tag/v${new_version}"
echo "CI:      https://github.com/snowshadow/CLIManager/actions"
echo ""
echo "Done. CI will build and publish the release automatically."
