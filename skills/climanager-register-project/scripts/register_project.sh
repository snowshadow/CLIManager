#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
skill_dir="$(cd "$script_dir/.." && pwd)"

resolve_package_path() {
  if [[ -n "${CLIMANAGER_PACKAGE_PATH:-}" ]]; then
    printf '%s\n' "$CLIMANAGER_PACKAGE_PATH"
    return 0
  fi

  local candidate="$skill_dir"
  while [[ "$candidate" != "/" ]]; do
    if [[ -f "$candidate/Package.swift" && -d "$candidate/Sources/CLIManagerCLI" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
    candidate="$(cd "$candidate/.." && pwd)"
  done

  return 1
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  cat <<'EOF'
Usage:
  register_project.sh --path /absolute/project/path [--name "Project"] [--command "swift run"] [--dry-run]

Environment:
  CLIMANAGER_PACKAGE_PATH   Absolute path to the CLIManager package root
EOF
  exit 0
fi

package_path="$(resolve_package_path || true)"
if [[ -z "$package_path" ]]; then
  echo "Could not locate the CLIManager package. Set CLIMANAGER_PACKAGE_PATH to the repo root." >&2
  exit 1
fi

binary_path="$package_path/.build/debug/CLIManagerCLI"
if [[ -x "$binary_path" ]]; then
  exec "$binary_path" import "$@"
fi

export SWIFT_MODULECACHE_PATH="${SWIFT_MODULECACHE_PATH:-/tmp/cli_manager_swift_module_cache}"
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-/tmp/cli_manager_clang_module_cache}"

exec swift run --package-path "$package_path" CLIManagerCLI import "$@"
