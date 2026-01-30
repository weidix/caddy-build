#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLUGINS_FILE="${PLUGINS_FILE:-$ROOT_DIR/plugins.txt}"
BIN_DIR="${BIN_DIR:-$ROOT_DIR/bin}"
STATE_DIR="${STATE_DIR:-$ROOT_DIR/state}"
DEFAULT_VERSION_FILE="$STATE_DIR/caddy-version.txt"
VERSION_FILE="${VERSION_FILE:-$DEFAULT_VERSION_FILE}"
OUTPUT_NAME="${OUTPUT_NAME:-caddy}"
OUTPUT_VARIANT="${OUTPUT_VARIANT:-}"
OUTPUT_VERSIONED_NAME="${OUTPUT_VERSIONED_NAME:-}"
KEEP_BINARY="${KEEP_BINARY:-0}"

mkdir -p "$BIN_DIR" "$STATE_DIR"

if ! command -v xcaddy >/dev/null 2>&1; then
  echo "xcaddy not found. Install with:"
  echo "  go install github.com/caddyserver/xcaddy/cmd/xcaddy@latest"
  exit 1
fi

if [ ! -f "$PLUGINS_FILE" ]; then
  echo "Plugins file not found: $PLUGINS_FILE"
  exit 1
fi

read_plugins() {
  local line trimmed
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%%#*}"
    trimmed="$(echo "$line" | xargs)"
    [ -z "$trimmed" ] && continue
    echo "$trimmed"
  done < "$PLUGINS_FILE"
}

plugins=()
with_args=()
while IFS= read -r plugin; do
  plugins+=("$plugin")
  with_args+=(--with "$plugin")
done < <(read_plugins)

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

target_version="${CADDY_VERSION:-latest}"
record_version="$target_version"

if [ "$target_version" = "latest" ]; then
  resolved_version="$(get_latest_version || true)"
  if [ -n "$resolved_version" ]; then
    target_version="$resolved_version"
    record_version="$resolved_version"
  fi
fi

echo "Building Caddy version: $target_version"
echo "Plugins:"
for p in "${plugins[@]}"; do
  echo "  $p"
done

versioned_suffix=""
if [ -n "$OUTPUT_VARIANT" ]; then
  versioned_suffix="-$OUTPUT_VARIANT"
fi
versioned_name="${OUTPUT_VERSIONED_NAME:-caddy-$record_version$versioned_suffix}"
archive_name="$versioned_name.tar.gz"

build_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$build_dir"
}
trap cleanup EXIT

output_path="$build_dir/$OUTPUT_NAME"
xcaddy build "$target_version" --output "$output_path" "${with_args[@]}"

echo "$record_version" > "$VERSION_FILE"

tar -czf "$BIN_DIR/$archive_name" -C "$build_dir" "$OUTPUT_NAME"

if [ "$KEEP_BINARY" = "1" ] || [ "$KEEP_BINARY" = "true" ]; then
  install -m 0755 "$output_path" "$BIN_DIR/$versioned_name"
fi

echo "Build complete: $BIN_DIR/$archive_name"
