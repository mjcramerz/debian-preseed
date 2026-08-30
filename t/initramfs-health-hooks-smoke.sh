#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/initramfs-health-hooks.XXXXXX")
trap 'rm -rf "$TMP_DIR"' EXIT HUP INT TERM

SCRIPTS_ROOT="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/initramfs-tools/scripts"
COMMON_FILE="$SCRIPTS_ROOT/installer-health-common"
CORE_HELPER="$ROOT_DIR/d-i/forky/scripts/late/core.sh"
RUNTIME_ENV="$ROOT_DIR/d-i/forky/hosts/shared/runtime.env"
F2FS_FAMILY="$ROOT_DIR/d-i/forky/scripts/late/f2fs-family.sh"
BTRFS_FAMILY="$ROOT_DIR/d-i/forky/scripts/late/btrfs-family.sh"
GRUB_HELPER="$ROOT_DIR/d-i/forky/scripts/late/grub.sh"
FIRSTBOOT_CLEANUP="$ROOT_DIR/d-i/forky/scripts/firstboot/05-cleanup.sh"
SECONDBOOT_CLEANUP="$ROOT_DIR/d-i/forky/hooks/shared/target/usr/local/libexec/secondboot-cleanup"

TEST_COUNT=6
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

if [ -f "$COMMON_FILE" ] &&
   [ ! -e "$ROOT_DIR/d-i/forky/scripts/initramfs/health-hook" ] &&
   ! grep -q '^DIR_SCRIPTS_INITRAMFS=' "$ROOT_DIR/d-i/forky/repo.env" &&
   ! grep -q 'scripts/initramfs|DIR_SCRIPTS_INITRAMFS' "$ROOT_DIR/d-i/forky/scripts/common/lib.sh"; then
  pass "initramfs health assets live only in the target script tree"
else
  fail "initramfs health assets live only in the target script tree"
fi

syntax_ok=true
for stage in init-top init-premount local-top local-block local-premount local-bottom init-bottom; do
  hook_file="$SCRIPTS_ROOT/$stage/90-installer-health"
  if [ ! -x "$hook_file" ] ||
     ! /bin/sh -n "$hook_file" ||
     [ -n "$(/bin/sh "$hook_file" prereqs)" ]; then
    syntax_ok=false
  fi
done
if /bin/sh -n "$COMMON_FILE" &&
   [ "$syntax_ok" = true ] &&
   ! grep -Riq 'fsck' \
     "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/initramfs-tools" \
     "$F2FS_FAMILY" \
     "$BTRFS_FAMILY" \
     "$RUNTIME_ENV" \
     "$SECONDBOOT_CLEANUP" &&
   grep -q '"fsck.mode=skip"' "$GRUB_HELPER"; then
  pass "custom initramfs payload contains no fsck interceptor while GRUB enforces skip mode"
else
  fail "custom initramfs payload contains no fsck interceptor while GRUB enforces skip mode"
fi

spool_dir="$TMP_DIR/spool"
for stage in init-top init-premount local-top local-block local-premount local-bottom init-bottom; do
  hook_file="$SCRIPTS_ROOT/$stage/90-installer-health"
  INSTALLER_INITRAMFS_HEALTH_COMMON="$COMMON_FILE" \
  INSTALLER_INITRAMFS_HEALTH_SPOOL_DIR="$spool_dir" \
  rootmnt="$TMP_DIR/root" \
  ROOT=/dev/test-root \
  ROOTFSTYPE=auto \
    /bin/sh "$hook_file" /dev/test-root
done
if grep -q '^stage=init-top$' "$spool_dir/01-init-top.log" &&
   grep -q '^stage=init-premount$' "$spool_dir/02-init-premount.log" &&
   grep -q '^stage=local-top$' "$spool_dir/03-local-top.log" &&
   grep -q '^stage=local-block$' "$spool_dir/04-local-block.log" &&
   grep -q '^stage=local-premount$' "$spool_dir/05-local-premount.log" &&
   grep -q '^stage=local-bottom$' "$spool_dir/06-local-bottom.log" &&
   grep -q '^stage=init-bottom$' "$spool_dir/07-init-bottom.log" &&
   [ "$(find "$spool_dir" -maxdepth 1 -type f -name '*.log' | wc -l)" -eq 7 ]; then
  pass "each initramfs-tools stage records a distinct bounded health log"
else
  fail "each initramfs-tools stage records a distinct bounded health log"
fi

no_retry_spool="$TMP_DIR/no-retry-spool"
INSTALLER_INITRAMFS_HEALTH_COMMON="$COMMON_FILE" \
INSTALLER_INITRAMFS_HEALTH_SPOOL_DIR="$no_retry_spool" \
  /bin/sh "$SCRIPTS_ROOT/local-premount/90-installer-health"
if grep -q '^stage=local-block$' "$no_retry_spool/04-local-block.log" &&
   grep -q '^invoked=false$' "$no_retry_spool/04-local-block.log" &&
   grep -q '^reason=root-device-resolved-without-local-block-retry$' "$no_retry_spool/04-local-block.log"; then
  pass "local-premount records when no local-block retry was required"
else
  fail "local-premount records when no local-block retry was required"
fi

block_hook="$SCRIPTS_ROOT/local-block/90-installer-health"
bounded_spool="$TMP_DIR/bounded-spool"
attempt=1
while [ "$attempt" -le 12 ]; do
  INSTALLER_INITRAMFS_HEALTH_COMMON="$COMMON_FILE" \
  INSTALLER_INITRAMFS_HEALTH_SPOOL_DIR="$bounded_spool" \
  INSTALLER_INITRAMFS_HEALTH_LOCAL_BLOCK_LIMIT=4 \
    /bin/sh "$block_hook" "/dev/test${attempt}"
  attempt=$((attempt + 1))
done
if [ "$(grep -c '^stage=local-block$' "$bounded_spool/04-local-block.log")" -eq 4 ] &&
   [ "$(cat "$bounded_spool/.local-block-count")" -eq 4 ]; then
  pass "repeated local-block diagnostics stop at the configured ceiling"
else
  fail "repeated local-block diagnostics stop at the configured ceiling"
fi

if grep -q '^FILE_INITRAMFS_HEALTH_COMMON=' "$RUNTIME_ENV" &&
   grep -q '^FILE_INITRAMFS_HEALTH_INIT_PREMOUNT=' "$RUNTIME_ENV" &&
   grep -q '^FILE_INITRAMFS_HEALTH_LOCAL_BLOCK=' "$RUNTIME_ENV" &&
   [ "$(grep -c 'etc/initramfs-tools/scripts/.*/90-installer-health' "$CORE_HELPER")" -eq 7 ] &&
   grep -q 'etc/initramfs-tools/scripts/installer-health-common' "$CORE_HELPER" &&
   ! grep -q 'update-initramfs\\|90-installer-health' "$FIRSTBOOT_CLEANUP" &&
   grep -q 'stage_target_systemd_unit_enabled secondboot.service system' "$CORE_HELPER" &&
   grep -q 'local-block/90-installer-health' "$SECONDBOOT_CLEANUP" &&
   grep -q 'update-initramfs -u -k all' "$SECONDBOOT_CLEANUP"; then
  pass "late staging installs every hook and automatic secondboot cleanup owns their removal"
else
  fail "late staging installs every hook and automatic secondboot cleanup owns their removal"
fi

[ "$FAIL_COUNT" -eq 0 ]
