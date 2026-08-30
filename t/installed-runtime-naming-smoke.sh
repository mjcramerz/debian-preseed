#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/installed-runtime-naming.XXXXXX")
trap 'rm -rf "$TMP_DIR"' EXIT HUP INT TERM

HOOK_ROOT="$ROOT_DIR/d-i/forky/hooks"
FIRSTBOOT_ROOT="$ROOT_DIR/d-i/forky/scripts/firstboot"
COMMON_LIB="$ROOT_DIR/d-i/forky/scripts/common/lib.sh"
RUNTIME_ENV="$ROOT_DIR/d-i/forky/hosts/shared/runtime.env"
CORE_HELPER="$ROOT_DIR/d-i/forky/scripts/late/core.sh"
FINISH_HOOK="$ROOT_DIR/d-i/forky/hooks/shared/finish-install.d/99-normalize-finish"
VIRT_HELPER="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/libexec/incus-host-managed"
DESKTOP_COMPONENTS="$ROOT_DIR/d-i/forky/scripts/desktop/components.sh"
MANAGED_NETWORK_HELPER="$ROOT_DIR/d-i/forky/hooks/shared/target/usr/local/libexec/managed-network-run"
NETWORK_SCRIPT="$ROOT_DIR/d-i/forky/scripts/late/network.sh"
NETWORK_GENERATOR="$ROOT_DIR/d-i/forky/scripts/late/managed-network-generate.pl"
SECURITY_HELPER="$ROOT_DIR/d-i/forky/scripts/late/security.sh"
HOST_PROFILE_ROOT="$ROOT_DIR/d-i/forky/hosts/profiles"
NFT_SERVICE_ROOT="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/nftables/services"
FORBIDDEN_TERM=preseed

TEST_COUNT=8
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

if [ -z "$(find "$HOOK_ROOT" -path '*/target/*' -iname "*${FORBIDDEN_TERM}*" -print -quit)" ]; then
  pass "installed target filenames use the neutral installer namespace"
else
  fail "installed target filenames use the neutral installer namespace"
fi

target_content_matches=$(rg --hidden -n -i "$FORBIDDEN_TERM" "$HOOK_ROOT" | rg '/target/' || true)
if [ -z "$target_content_matches" ]; then
  pass "installed target file contents contain no forbidden installer-source terminology"
else
  fail "installed target file contents contain no forbidden installer-source terminology"
  printf '%s\n' "$target_content_matches"
fi

if ! rg -n -i "$FORBIDDEN_TERM" "$FIRSTBOOT_ROOT" >/dev/null 2>&1 &&
   grep -q '^DIR_INSTALLER_STATE="/var/lib/installer-state"$' "$RUNTIME_ENV" &&
   grep -q '^FILE_INITRAMFS_HEALTH_COMMON="${DIR_INITRAMFS_SCRIPTS}/installer-health-common"$' "$RUNTIME_ENV"; then
  pass "staged firstboot scripts and runtime paths use installer-state naming"
else
  fail "staged firstboot scripts and runtime paths use installer-state naming"
fi

if ! rg --hidden -n -i '(/var/lib/preseed|preseed-initramfs-health|preseed-health-common|90-preseed-health|unshare[.]preseed-real|PRESEED_TEMPORARY_FAKE_UNSHARE_V1|preseed[.]log)' \
     "$ROOT_DIR/d-i/forky" >/dev/null 2>&1 &&
   grep -q 'etc/initramfs-tools/scripts/installer-health-common' "$CORE_HELPER" &&
   grep -q 'TARGET_LOG_FILE="${TARGET}/var/lib/installer-state/installer.log"' "$FINISH_HOOK"; then
  pass "target generators cannot recreate legacy installed paths or filenames"
else
  fail "target generators cannot recreate legacy installed paths or filenames"
fi

sanitized_log="$TMP_DIR/sanitized.log"
# shellcheck disable=SC1090
. "$COMMON_LIB"
printf 'PreSeed preseed PRESEED token=secret\n' |
  installer_redact_log_stream >"$sanitized_log"
if ! grep -qi "$FORBIDDEN_TERM" "$sanitized_log" &&
   grep -q 'installer installer installer token=REDACTED' "$sanitized_log" &&
   grep -q '^  seed_input_option=pre$' "$VIRT_HELPER" &&
   grep -q '^  seed_input_option="${seed_input_option}seed"$' "$VIRT_HELPER" &&
   grep -q 'admin init "--${seed_input_option}"' "$VIRT_HELPER"; then
  pass "persisted logs are sanitized and Incus behavior avoids storing the forbidden literal"
else
  fail "persisted logs are sanitized and Incus behavior avoids storing the forbidden literal"
fi

if ! grep -q 'key#PRESEED_' "$DESKTOP_COMPONENTS" &&
   ! grep -q 'MANAGED_NETWORK_ETHERNET_IFACE must match MANAGED_NETWORK_ETHERNET_IFACE' "$MANAGED_NETWORK_HELPER" &&
   ! grep -q 'MANAGED_NETWORK_WIFI_IFACE must match MANAGED_NETWORK_WIFI_IFACE' "$MANAGED_NETWORK_HELPER"; then
  pass "neutral managed-network keys have no dead legacy aliases or tautological validation"
else
  fail "neutral managed-network keys have no dead legacy aliases or tautological validation"
fi

profile_mismatches="$TMP_DIR/profile-mismatches"
find "$HOST_PROFILE_ROOT" -type f -name '*.env' -print | sort |
  while IFS= read -r profile_path || [ -n "$profile_path" ]; do
    if grep -q '^MANAGED_NETWORK_ETHERNET_IFACE=' "$profile_path" ||
       grep -q '^MANAGED_NETWORK_WIFI_IFACE=' "$profile_path"; then
      grep -q '^MANAGED_NETWORK_ETHERNET_IFACE="managed-eth0"$' "$profile_path" &&
        grep -q '^MANAGED_NETWORK_WIFI_IFACE="managed-wifi0"$' "$profile_path" ||
        printf '%s\n' "$profile_path"
    fi
  done >"$profile_mismatches"
if ! rg -n 'preeth0|prewifi0' "$ROOT_DIR/d-i/forky" "$ROOT_DIR/README.md" >/dev/null 2>&1 &&
   [ ! -s "$profile_mismatches" ] &&
   grep -q 'target_ethernet_iface=${MANAGED_NETWORK_ETHERNET_IFACE:-managed-eth0}' "$NETWORK_SCRIPT" &&
   grep -q 'target_wifi_iface=${MANAGED_NETWORK_WIFI_IFACE:-managed-wifi0}' "$NETWORK_SCRIPT" &&
   grep -q "MANAGED_NETWORK_ETHERNET_IFACE      => 'managed-eth0'" "$NETWORK_GENERATOR" &&
   grep -q "MANAGED_NETWORK_WIFI_IFACE          => 'managed-wifi0'" "$NETWORK_GENERATOR"; then
  pass "managed interface names are neutral and consistent without rewriting captured host logs"
else
  fail "managed interface names are neutral and consistent without rewriting captured host logs"
  cat "$profile_mismatches"
fi

nft_service_mismatches="$TMP_DIR/nft-service-mismatches"
for service_path in "$NFT_SERVICE_ROOT"/*.yml; do
  if grep -Eq '^[[:space:]]+- (eth0|en[*])$' "$service_path" &&
     ! grep -q '__INSTALLER_MANAGED_NETWORK_ETHERNET_IFACE__' "$service_path"; then
    printf '%s: ethernet\n' "$service_path"
  fi
  if grep -Eq '^[[:space:]]+- (wlan0|wl[*])$' "$service_path" &&
     ! grep -q '__INSTALLER_MANAGED_NETWORK_WIFI_IFACE__' "$service_path"; then
    printf '%s: wifi\n' "$service_path"
  fi
done >"$nft_service_mismatches"
if [ ! -s "$nft_service_mismatches" ] &&
   grep -q 'managed-eth0' "$SECURITY_HELPER" &&
   grep -q 'managed-wifi0' "$SECURITY_HELPER"; then
  pass "nftables service overlays include deterministic managed interfaces"
else
  fail "nftables service overlays include deterministic managed interfaces"
  cat "$nft_service_mismatches"
fi

[ "$FAIL_COUNT" -eq 0 ]
