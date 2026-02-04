#!/bin/ash
set -eu
umask 022

CONF="/etc/caddy/build.conf"
REPO_SLUG="${CADDY_BUILD_REPO:-weidix/caddy-build}"
PROMPT_IN="/dev/stdin"; [ -r /dev/tty ] && [ -w /dev/tty ] && PROMPT_IN="/dev/tty"
p(){ # msg def
  local msg="$1" def="${2:-}" ans=""
  [ -n "$def" ] && printf "%s [默认:%s]: " "$msg" "$def" >&2 || printf "%s: " "$msg" >&2
  IFS= read -r ans <"$PROMPT_IN" || ans=""
  [ -z "${ans:-}" ] && ans="$def"
  printf "%s" "$ans"
}
yn(){ local a; a="$(p "$1 (y/n)" "${2:-y}")"; case "$a" in y|Y|yes|YES) return 0;; *) return 1;; esac; }

[ "$(id -u)" = 0 ] || { echo "root 运行" >&2; exit 1; }
apk add --no-cache ca-certificates curl tar >/dev/null

arch() {
  case "$(uname -m)" in
    x86_64) echo amd64;;
    aarch64) echo arm64;;
    armv7*|armv7l) echo armv7;;
    armv6*|armv6l) echo armv6;;
    *) echo unknown;;
  esac
}
A="$(arch)"; [ "$A" = unknown ] && { echo "不支持架构: $(uname -m)" >&2; exit 1; }
if [ "$A" != "amd64" ]; then
  echo "当前仅提供 amd64 预编译包（检测到: $A）。请自行编译或在 CI 中增加对应架构。" >&2
  exit 1
fi

CADDY_BIN="/usr/bin/caddy"
installed_ver=""
[ -x "$CADDY_BIN" ] && installed_ver="$("$CADDY_BIN" version 2>/dev/null | awk '{print $1}' || true)"

echo "已安装版本: ${installed_ver:-none}" >&2
mode="$(p "操作: i=安装/更新  u=卸载  q=退出" "i")"
case "$mode" in
  q|Q) exit 0 ;;
  u|U)
    rc-service caddy stop >/dev/null 2>&1 || true
    rc-update del caddy default >/dev/null 2>&1 || true
    rm -f /etc/init.d/caddy /etc/conf.d/caddy
    rm -f "$CADDY_BIN"
    echo "卸载完成" >&2
    exit 0
    ;;
  i|I|"") ;;
  *) echo "无效选择" >&2; exit 1 ;;
esac

DEFAULT_VER=""   # 空=最新
DEFAULT_VARIANT="musl"

VER="$DEFAULT_VER"
VARIANT="${CADDY_VARIANT:-}"

if [ -f "$CONF" ]; then
  # shellcheck disable=SC1090
  . "$CONF" || true
  if yn "发现上次配置，复用版本/类型" "y"; then
    : # 已从 CONF 读取
  else
    VER="$DEFAULT_VER"
    VARIANT="${CADDY_VARIANT:-}"
  fi
fi

VER="$(p "版本号(空=最新)" "${VER:-}")"
variant_default="${VARIANT:-$DEFAULT_VARIANT}"
VARIANT="$(p "二进制类型(musl/glibc)" "$variant_default")"
case "$VARIANT" in
  musl|glibc) ;;
  *) echo "无效类型: $VARIANT" >&2; exit 1 ;;
esac

mkdir -p /etc/caddy
cat > "$CONF" <<EOF
VER="${VER}"
VARIANT="${VARIANT}"
EOF

get_latest_tag() {
  local loc
  loc="$(curl -fsSLI "https://github.com/$REPO_SLUG/releases/latest" \
    | awk -F': ' 'tolower($1)=="location"{print $2}' \
    | tail -n 1 | tr -d '\r')"
  [ -n "$loc" ] || return 1
  printf "%s" "${loc##*/}"
}

tag=""
if [ -n "$VER" ]; then
  tag="$VER"
else
  tag="$(get_latest_tag || true)"
  VER="$tag"
fi

[ -n "$tag" ] || { echo "无法获取版本信息" >&2; exit 1; }

asset_versioned="caddy-$tag-$VARIANT.tar.gz"
asset_url="https://github.com/$REPO_SLUG/releases/download/$tag/$asset_versioned"

[ -n "$asset_url" ] || { echo "未找到下载资源: $asset_versioned" >&2; exit 1; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
out="$tmp/caddy.dl"

echo "下载: $asset_url" >&2
curl -fL --retry 3 --retry-delay 1 --connect-timeout 10 -o "$out" "$asset_url"

if tar -tzf "$out" >/dev/null 2>&1; then
  tar -xzf "$out" -C "$tmp"
  [ -f "$tmp/caddy" ] || { echo "包里没找到 caddy" >&2; exit 1; }
  rc-service caddy stop >/dev/null 2>&1 || true
  install -m 0755 "$tmp/caddy" "$CADDY_BIN"
else
  echo "下载内容不对(不是 tar.gz)。前200字节：" >&2
  head -c 200 "$out" >&2; echo >&2
  exit 1
fi

new_ver="$("$CADDY_BIN" version 2>/dev/null | awk '{print $1}' || true)"
echo "已安装/更新: $CADDY_BIN 版本: ${new_ver:-unknown}" >&2

# OpenRC（写一次即可，后续更新只换二进制也行）
if yn "安装/更新 OpenRC 服务" "y"; then
  addgroup -S caddy >/dev/null 2>&1 || true
  if ! id caddy >/dev/null 2>&1; then
    adduser -S -D -s /sbin/nologin -G caddy -h /var/lib/caddy caddy >/dev/null 2>&1 || true
  fi

  mkdir -p /etc/caddy /var/lib/caddy /var/log/caddy
  chown -R caddy:caddy /var/lib/caddy /var/log/caddy

  [ -f /etc/caddy/Caddyfile ] || cat > /etc/caddy/Caddyfile <<'EOF'
{
}
:80 {
  respond "ok"
}
EOF

  cat > /etc/conf.d/caddy <<EOF
CADDY_BIN="/usr/bin/caddy"
CADDYFILE="/etc/caddy/Caddyfile"
CADDY_ADAPTER="caddyfile"
CADDY_USER="caddy"
CADDY_GROUP="caddy"
CADDY_LOG_DIR="/var/log/caddy"
EOF

  cat > /etc/init.d/caddy <<'EOF'
#!/sbin/openrc-run
name="caddy"
description="Caddy web server"
command="${CADDY_BIN:-/usr/bin/caddy}"
command_user="${CADDY_USER:-caddy}:${CADDY_GROUP:-caddy}"
pidfile="/run/caddy.pid"
command_background="yes"
output_log="${CADDY_LOG_DIR:-/var/log/caddy}/caddy.log"
error_log="${CADDY_LOG_DIR:-/var/log/caddy}/caddy.err"

depend() { need net; after firewall; }

start_pre() {
  checkpath -d -o "${CADDY_USER:-caddy}:${CADDY_GROUP:-caddy}" -m 0750 /var/lib/caddy
  checkpath -d -o "${CADDY_USER:-caddy}:${CADDY_GROUP:-caddy}" -m 0750 "${CADDY_LOG_DIR:-/var/log/caddy}"
}

start() {
  export HOME=/var/lib/caddy
  export XDG_DATA_HOME=/var/lib/caddy
  export XDG_CONFIG_HOME=/var/lib/caddy
  ebegin "Starting ${name}"
  start-stop-daemon --start --background \
    --user "${CADDY_USER:-caddy}" --group "${CADDY_GROUP:-caddy}" \
    --make-pidfile --pidfile "${pidfile}" \
    --stdout "${output_log}" --stderr "${error_log}" \
    --exec "${command}" -- \
    run --config "${CADDYFILE:-/etc/caddy/Caddyfile}" --adapter "${CADDY_ADAPTER:-caddyfile}"
  eend $?
}

stop() {
  ebegin "Stopping ${name}"
  start-stop-daemon --stop --pidfile "${pidfile}"
  eend $?
}
EOF
  chmod +x /etc/init.d/caddy

  rc-update add caddy default >/dev/null 2>&1 || true
  rc-service caddy restart || true
fi
