#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_DIR="${BIN_DIR:-$ROOT_DIR/bin}"
STATE_DIR="${STATE_DIR:-$ROOT_DIR/state}"
DEFAULT_VERSION_FILE="$STATE_DIR/caddy-version.txt"
VERSION_FILE="${VERSION_FILE:-$DEFAULT_VERSION_FILE}"
BUILD_SCRIPT="$ROOT_DIR/scripts/build.sh"

mkdir -p "$STATE_DIR" "$BIN_DIR"

if [ ! -x "$BUILD_SCRIPT" ]; then
  echo "Build script not found or not executable: $BUILD_SCRIPT"
  exit 1
fi

write_output() {
  if [ -n "${GITHUB_OUTPUT:-}" ]; then
    echo "$1" >> "$GITHUB_OUTPUT"
  fi
}

get_latest_version() {
  local api_url="https://api.github.com/repos/caddyserver/caddy/releases/latest"
  local auth_header=()
  if [ -n "${GITHUB_TOKEN:-}" ]; then
    auth_header=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
  fi

  curl -fsSL "${auth_header[@]}" "$api_url" \
    | sed -n 's/^[[:space:]]*"tag_name":[[:space:]]*"\([^"]\+\)".*/\1/p' \
    | head -n 1
}

latest_version="$(get_latest_version)"
if [ -z "$latest_version" ]; then
  echo "Unable to determine latest Caddy version."
  exit 1
fi
write_output "latest_version=$latest_version"

check_release="${CHECK_RELEASE:-}"
if [ "$check_release" = "1" ] || [ "$check_release" = "true" ]; then
  repo="${GITHUB_REPOSITORY:-${REPO_SLUG:-}}"
  if [ -z "$repo" ]; then
    echo "CHECK_RELEASE enabled but repository is not set (GITHUB_REPOSITORY or REPO_SLUG)."
    exit 1
  fi
  auth_header=()
  if [ -n "${GITHUB_TOKEN:-}" ]; then
    auth_header=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
  fi
  if curl -fsSL "${auth_header[@]}" \
    "https://api.github.com/repos/$repo/releases/tags/$latest_version" >/dev/null; then
    echo "Release $latest_version already exists in $repo. Skip build."
    write_output "build_performed=false"
    exit 0
  fi
fi

current_version=""
if [ -f "$VERSION_FILE" ]; then
  current_version="$(cat "$VERSION_FILE" | tr -d '[:space:]')"
fi

output_name="${OUTPUT_NAME:-caddy}"
output_path="$BIN_DIR/$output_name"

if [ "$current_version" = "$latest_version" ] && [ -x "$output_path" ]; then
  echo "Caddy is up to date ($latest_version). No build needed."
  write_output "build_performed=false"
  exit 0
fi

echo "Caddy update detected: $current_version -> $latest_version"

CADDY_VERSION="$latest_version" \
OUTPUT_NAME="${OUTPUT_NAME:-}" \
OUTPUT_VARIANT="${OUTPUT_VARIANT:-}" \
OUTPUT_VERSIONED_NAME="${OUTPUT_VERSIONED_NAME:-}" \
VERSION_FILE="$VERSION_FILE" \
"$BUILD_SCRIPT"
echo "Updated version record: $VERSION_FILE"
write_output "build_performed=true"
