#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/nftables-service-staging.XXXXXX")
trap 'rm -rf "$TMP_DIR"' EXIT HUP INT TERM

SECURITY_HELPER="$ROOT_DIR/d-i/forky/scripts/late/security.sh"
SOURCE_ROOT="$ROOT_DIR/d-i/forky/hooks/shared/target"
TARGET_ROOT="$TMP_DIR/target"
STAGE_LOG="$TMP_DIR/stage.log"

TEST_COUNT=4
TEST_INDEX=0
FAIL_COUNT=0

pass() {
  TEST_INDEX=$((TEST_INDEX + 1))
  printf 'ok %s - %s\n' "$TEST_INDEX" "$1"
}

fail() {
  TEST_INDEX=$((TEST_INDEX + 1))
  FAIL_COUNT=$((FAIL_COUNT + 1))
  printf 'not ok %s - %s\n' "$TEST_INDEX" "$1"
}

printf '1..%s\n' "$TEST_COUNT"

installer_fatal() {
  printf 'fatal: %s\n' "$*" >&2
  exit 1
}

# shellcheck disable=SC1090
. "$SECURITY_HELPER"

installer_repo_join_var() {
  [ "$1" = DIR_HOOKS_SHARED_TARGET ] ||
    installer_fatal "unexpected repository root variable: $1"
  printf '%s/%s\n' "$SOURCE_ROOT" "$2"
}

nftables_tailscale_selected() {
  return 0
}

nftables_qemu_selected() {
  return 1
}

runtime_apply_ssh_from_cmdline() {
  SSH_PORT=${SSH_PORT:-45000}
}

stage_target_asset() {
  source_path=$1
  target_path=$2
  mode=$3
  target_host_path="${TARGET_ROOT}${target_path}"

  install -d -m 0755 "$(dirname "$target_host_path")"
  install -m "$mode" "$source_path" "$target_host_path"
  printf 'stage %s\n' "${target_path##*/}" >>"$STAGE_LOG"
}

render_target_asset_with_placeholder_map() {
  source_path=$1
  target_path=$2
  mode=$3
  map_func=$4
  target_host_path="${TARGET_ROOT}${target_path}"
  map_path="$TMP_DIR/placeholder-map"

  stage_target_asset "$source_path" "$target_path" "$mode"
  "$map_func" >"$map_path"
  python3 - "$target_host_path" "$map_path" <<'PY'
from pathlib import Path
import re
import sys

target_path = Path(sys.argv[1])
map_path = Path(sys.argv[2])
text = target_path.read_text(encoding="utf-8")
for raw_line in map_path.read_text(encoding="utf-8").splitlines():
    if not raw_line:
        continue
    name, value = raw_line.split("=", 1)
    text = text.replace(f"__INSTALLER_{name}__", value)
unresolved = sorted(set(re.findall(r"__[A-Z0-9_]+__", text)))
if unresolved:
    raise SystemExit("unresolved placeholders: " + ", ".join(unresolved))
target_path.write_text(text, encoding="utf-8")
PY
  printf 'render %s %s\n' "${target_path##*/}" "$map_func" >>"$STAGE_LOG"
}

MANAGED_NETWORK_ETHERNET_IFACE=managed-eth0
MANAGED_NETWORK_WIFI_IFACE=managed-wifi0
TAILSCALE_INTERFACE=tailscale0
TAILSCALE_UDP_PORT=41641
TAILSCALE_RUN_SSH_SERVER=true

stage_target_nftables_service_assets prometheus
prometheus_target="$TARGET_ROOT/etc/nftables/services/prometheus.yml"
if [ -r "$prometheus_target" ] &&
   ! grep -q '__INSTALLER_' "$prometheus_target" &&
   grep -q 'managed-eth0' "$prometheus_target" &&
   grep -q 'managed-wifi0' "$prometheus_target" &&
   grep -q '^render prometheus[.]yml nftables_interface_placeholder_map$' "$STAGE_LOG"; then
  pass "generic service overlays render managed interface placeholders"
else
  fail "generic service overlays render managed interface placeholders"
fi

stage_target_nftables_service_assets tailscale
tailscale_target="$TARGET_ROOT/etc/nftables/services/tailscale.yml"
if [ -r "$tailscale_target" ] &&
   ! grep -q '__INSTALLER_' "$tailscale_target" &&
   grep -q 'managed-eth0' "$tailscale_target" &&
   grep -q 'managed-wifi0' "$tailscale_target" &&
   grep -q 'tailscale0' "$tailscale_target" &&
   grep -q '^render tailscale[.]yml nftables_tailscale_service_placeholder_map$' "$STAGE_LOG"; then
  pass "selected Tailscale overlay composes managed-interface and Tailscale maps"
else
  fail "selected Tailscale overlay composes managed-interface and Tailscale maps"
fi

stage_target_nftables_service_assets wazuh-agent
if [ -r "$TARGET_ROOT/etc/nftables/services/wazuh-agent.yml" ] &&
   [ "$(tail -n 1 "$STAGE_LOG")" = "render wazuh-agent.yml nftables_interface_placeholder_map" ]; then
  pass "service staging continues past Tailscale to the next overlay"
else
  fail "service staging continues past Tailscale to the next overlay"
fi

SSH_SERVER_ENABLED=true
SSH_PORT=45000
nftables_qemu_selected() {
  return 0
}
stage_target_nftables_all_service_assets
service_count=$(find "$TARGET_ROOT/etc/nftables/services" -maxdepth 1 -type f -name '*.yml' | wc -l)
if [ "$service_count" -eq 46 ] &&
   ! rg -n '__INSTALLER_[A-Z0-9_]+__' "$TARGET_ROOT/etc/nftables/services" >/dev/null 2>&1; then
  pass "full service staging renders all 46 overlays without unresolved placeholders"
else
  fail "full service staging renders all 46 overlays without unresolved placeholders"
fi

[ "$FAIL_COUNT" -eq 0 ]
