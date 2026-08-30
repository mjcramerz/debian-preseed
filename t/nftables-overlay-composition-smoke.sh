#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/nftables-overlay-composition-smoke.XXXXXX")
trap 'rm -rf "$TMP_DIR"' EXIT HUP INT TERM

TEST_COUNT=5
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

GENERATOR="$ROOT_DIR/d-i/forky/hooks/shared/target/usr/local/sbin/nft-policy-generate.py"
PROFILE_SRC="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/nftables/profiles/desktop.yml"
QEMU_OVERLAY_SRC="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/nftables/services/qemu.yml"
QBITTORRENT_OVERLAY_SRC="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/nftables/services/qbittorrent.yml"
TAILSCALE_OVERLAY_SRC="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/nftables/services/tailscale.yml"
SYNCTHING_OVERLAY_SRC="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/nftables/services/syncthing.yml"
GITLAB_OVERLAY_SRC="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/nftables/services/gitlab-runner.yml"
SSH_OVERLAY_SRC="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/nftables/services/ssh-server.yml"

render_yaml() {
  src=$1
  dst=$2
  python3 - "$src" "$dst" <<'PY'
from pathlib import Path
import sys

src = Path(sys.argv[1])
dst = Path(sys.argv[2])
text = src.read_text(encoding="utf-8")
replacements = {
    "__INSTALLER_MANAGED_NETWORK_ETHERNET_IFACE__": "managed-eth0",
    "__INSTALLER_MANAGED_NETWORK_WIFI_IFACE__": "managed-wifi0",
    "__INSTALLER_TAILSCALE_UDP_PORT__": "41641",
    "__INSTALLER_TAILSCALE_RUN_SSH_SERVER__": "true",
    "__INSTALLER_NFTABLES_TAILSCALE_ALLOW_IPV4__": '["100.64.0.0/10"]',
    "__INSTALLER_NFTABLES_TAILSCALE_ALLOW_IPV6__": '["fd7a:115c:a1e0::/48"]',
    "__INSTALLER_NFTABLES_TAILSCALE_ALLOW_INTERFACES__": '["tailscale0"]',
    "__INSTALLER_SYNCTHING_TCP_PORT__": "35000",
    "__INSTALLER_NFTABLES_SYNCTHING_ALLOW_IPV4__": '["100.64.0.0/10"]',
    "__INSTALLER_NFTABLES_SYNCTHING_ALLOW_IPV6__": '["fd7a:115c:a1e0::/48"]',
    "__INSTALLER_NFTABLES_SYNCTHING_ALLOW_INTERFACES__": '["tailscale0"]',
    "__INSTALLER_NFTABLES_QEMU_ALLOW_INTERFACES__": '["incusbr0"]',
    "__INSTALLER_SSH_PORT__": "45000",
    "__INSTALLER_NFTABLES_SSH_ALLOW_IPV4__": '["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16", "10.8.0.0/24"]',
    "__INSTALLER_NFTABLES_SSH_ALLOW_IPV6__": '["fc00::/7", "fe80::/10", "fd00:8::/64"]',
    "__INSTALLER_NFTABLES_SSH_ALLOW_INTERFACES__": '["eth0", "en*", "managed-eth0", "wlan0", "wl*", "managed-wifi0", "wg0"]',
}
for old, new in replacements.items():
    text = text.replace(old, new)
dst.write_text(text, encoding="utf-8")
PY
}

run_overlay_case() {
  case_name=$1
  expect_filter_1=$2
  expect_filter_2=$3
  shift 3

  case_dir="$TMP_DIR/$case_name"
  mkdir -p "$case_dir"
  render_yaml "$PROFILE_SRC" "$case_dir/profile.yml"

  set -- "$@"
  rendered_overlays=
  for overlay_src in "$@"; do
    overlay_dst="$case_dir/$(basename "$overlay_src")"
    render_yaml "$overlay_src" "$overlay_dst"
    rendered_overlays="${rendered_overlays:+$rendered_overlays }$overlay_dst"
  done

  set -- python3 "$GENERATOR" --profile "$case_dir/profile.yml"
  for overlay_dst in $rendered_overlays; do
    set -- "$@" --overlay "$overlay_dst"
  done
  set -- "$@" --target-root "$case_dir/root" --write --summary

  if "$@" >"$case_dir/out" 2>"$case_dir/err" &&
     [ -r "$case_dir/root/etc/nftables.conf" ] &&
     [ -r "$case_dir/root/etc/nftables.d/20-filter.nft" ] &&
     [ -r "$case_dir/root/etc/nftables.d/30-nat.nft" ] &&
     grep -q "$expect_filter_1" "$case_dir/root/etc/nftables.d/20-filter.nft" &&
     grep -q "$expect_filter_2" "$case_dir/root/etc/nftables.d/20-filter.nft" &&
     grep -q 'masquerade' "$case_dir/root/etc/nftables.d/30-nat.nft"; then
    return 0
  fi
  return 1
}

if grep -q '^  applies_to_profiles:$' "$QEMU_OVERLAY_SRC" &&
   grep -q '^  - desktop$' "$QEMU_OVERLAY_SRC"; then
  pass "qemu nftables overlay is explicitly scoped to desktop profiles"
else
  fail "qemu nftables overlay is explicitly scoped to desktop profiles"
fi

if run_overlay_case \
  qemu_tailscale_syncthing \
  'service qemu_guest_dhcp_v4 inbound' \
  'service tailscale_udp inbound' \
  "$QEMU_OVERLAY_SRC" \
  "$QBITTORRENT_OVERLAY_SRC" \
  "$TAILSCALE_OVERLAY_SRC" \
  "$SYNCTHING_OVERLAY_SRC" &&
  grep -q 'tcp dport { 80, 443 }' "$TMP_DIR/qemu_tailscale_syncthing/root/etc/nftables.d/20-filter.nft" &&
  grep -q 'udp dport 3478' "$TMP_DIR/qemu_tailscale_syncthing/root/etc/nftables.d/20-filter.nft" &&
  grep -q 'udp sport 41641' "$TMP_DIR/qemu_tailscale_syncthing/root/etc/nftables.d/20-filter.nft" &&
  ! grep -q 'qemu_incus_api_ui' "$TMP_DIR/qemu_tailscale_syncthing/root/etc/nftables.d/20-filter.nft" &&
  ! grep -q 'tcp dport 8443' "$TMP_DIR/qemu_tailscale_syncthing/root/etc/nftables.d/20-filter.nft" &&
  grep -q 'service qbittorrent_incoming inbound' "$TMP_DIR/qemu_tailscale_syncthing/root/etc/nftables.d/20-filter.nft" &&
  grep -q 'tcp dport 50309' "$TMP_DIR/qemu_tailscale_syncthing/root/etc/nftables.d/20-filter.nft" &&
  grep -q 'udp dport 50309' "$TMP_DIR/qemu_tailscale_syncthing/root/etc/nftables.d/20-filter.nft" &&
  grep -q 'service syncthing_sync_tcp inbound' "$TMP_DIR/qemu_tailscale_syncthing/root/etc/nftables.d/20-filter.nft" &&
  grep -q 'iifname "incusbr0"' "$TMP_DIR/qemu_tailscale_syncthing/root/etc/nftables.d/20-filter.nft" &&
  grep -q 'iifname "tailscale0"' "$TMP_DIR/qemu_tailscale_syncthing/root/etc/nftables.d/20-filter.nft"; then
  pass "generator composes qemu, qBittorrent, tailscale, and syncthing overlays without rule conflicts"
else
  fail "generator composes qemu, qBittorrent, tailscale, and syncthing overlays without rule conflicts"
fi

if run_overlay_case \
  qemu_gitlab_runner \
  'forward qemu_guest_outbound' \
  'container outbound podman' \
  "$QEMU_OVERLAY_SRC" \
  "$GITLAB_OVERLAY_SRC"; then
  pass "generator composes qemu and gitlab-runner overlays with forwarding and NAT enabled"
else
  fail "generator composes qemu and gitlab-runner overlays with forwarding and NAT enabled"
fi

if run_overlay_case \
  qemu_tailscale_syncthing_gitlab \
  'service qemu_guest_dns_tcp inbound' \
  'service tailscale_udp inbound' \
  "$QEMU_OVERLAY_SRC" \
  "$TAILSCALE_OVERLAY_SRC" \
  "$SYNCTHING_OVERLAY_SRC" \
  "$GITLAB_OVERLAY_SRC" &&
  grep -q 'container outbound podman' "$TMP_DIR/qemu_tailscale_syncthing_gitlab/root/etc/nftables.d/20-filter.nft" &&
  grep -q 'service syncthing_sync_tcp outbound' "$TMP_DIR/qemu_tailscale_syncthing_gitlab/root/etc/nftables.d/20-filter.nft"; then
  pass "generator survives combined qemu, tailscale, syncthing, and gitlab-runner overlays together"
else
  fail "generator survives combined qemu, tailscale, syncthing, and gitlab-runner overlays together"
fi

if run_overlay_case \
  qemu_tailscale_syncthing_ssh \
  'service ssh_server inbound' \
  'service qemu_guest_dhcp_v4 inbound' \
  "$QEMU_OVERLAY_SRC" \
  "$TAILSCALE_OVERLAY_SRC" \
  "$SYNCTHING_OVERLAY_SRC" \
  "$SSH_OVERLAY_SRC" &&
  ! grep -q 'qemu_incus_api_ui' "$TMP_DIR/qemu_tailscale_syncthing_ssh/root/etc/nftables.d/20-filter.nft" &&
  ! grep -q 'tcp dport 8443' "$TMP_DIR/qemu_tailscale_syncthing_ssh/root/etc/nftables.d/20-filter.nft" &&
  grep -q 'tcp dport 45000' "$TMP_DIR/qemu_tailscale_syncthing_ssh/root/etc/nftables.d/20-filter.nft" &&
  grep -q 'iifname "tailscale0"' "$TMP_DIR/qemu_tailscale_syncthing_ssh/root/etc/nftables.d/20-filter.nft" &&
  grep -q 'iifname "incusbr0"' "$TMP_DIR/qemu_tailscale_syncthing_ssh/root/etc/nftables.d/20-filter.nft"; then
  pass "generator composes qemu, tailscale, syncthing, and ssh overlays without conflicts"
else
  fail "generator composes qemu, tailscale, syncthing, and ssh overlays without conflicts"
fi

[ "$FAIL_COUNT" -eq 0 ]
