#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/finish-install-normalize-smoke.XXXXXX")
TARGET_ROOT="$TMP_DIR/target"
ENV_DIR="$TMP_DIR/env"
STUB_BIN="$TMP_DIR/bin"
TEST_COUNT=9
TEST_INDEX=0
FAIL_COUNT=0
trap 'rm -rf "$TMP_DIR"' EXIT HUP INT TERM

pass() {
  TEST_INDEX=$((TEST_INDEX + 1))
  printf 'ok %s - %s\n' "$TEST_INDEX" "$1"
}

fail() {
  TEST_INDEX=$((TEST_INDEX + 1))
  FAIL_COUNT=$((FAIL_COUNT + 1))
  printf 'not ok %s - %s\n' "$TEST_INDEX" "$1"
}

assert_mode() {
  expected=$1
  path=$2
  [ "$(stat -c %a "$path")" = "$expected" ]
}

printf '1..%s\n' "$TEST_COUNT"

install -d -m 0755 \
  "$TARGET_ROOT/etc/systemd/system/tailscaled.service.d" \
  "$TARGET_ROOT/etc/systemd/system/crowdsec-firewall-bouncer.service.d" \
  "$TARGET_ROOT/home/desktop/.config" \
  "$TARGET_ROOT/home/desktop/bin" \
  "$TARGET_ROOT/usr/bin" \
  "$TARGET_ROOT/usr/local/sbin" \
  "$TARGET_ROOT/data/run" \
  "$TARGET_ROOT/dev/shm" \
  "$TARGET_ROOT/tmp" \
  "$TARGET_ROOT/var/cache" \
  "$TARGET_ROOT/var/lib/apt/lists" \
  "$TARGET_ROOT/var/lib/systemd/coredump" \
  "$TARGET_ROOT/var/log" \
  "$TARGET_ROOT/var/tmp" \
  "$TARGET_ROOT/var/lib/dpkg" \
  "$STUB_BIN" \
  "$ENV_DIR"

cat >"$TARGET_ROOT/etc/systemd/system/tailscale-managed-bootstrap.service" <<'EOF_UNIT'
[Unit]
Description=Managed Tailscale bootstrap
EOF_UNIT
cat >"$TARGET_ROOT/etc/systemd/system/managed-syncthing.service" <<'EOF_UNIT'
[Unit]
Description=Managed Syncthing
EOF_UNIT
cat >"$TARGET_ROOT/etc/systemd/system/crowdsec-firstboot.service" <<'EOF_UNIT'
[Unit]
Description=CrowdSec first boot
EOF_UNIT
cat >"$TARGET_ROOT/etc/systemd/system/secondboot.service" <<'EOF_UNIT'
[Unit]
Description=Manual installer cleanup
EOF_UNIT
cat >"$TARGET_ROOT/etc/systemd/system/tailscaled.service.d/override.conf" <<'EOF_UNIT'
[Service]
NoNewPrivileges=true
EOF_UNIT
cat >"$TARGET_ROOT/etc/systemd/system/crowdsec-firewall-bouncer.service.d/override.conf" <<'EOF_UNIT'
[Unit]
After=nftables.service crowdsec.service
EOF_UNIT
cat >"$TARGET_ROOT/usr/local/sbin/managed-network" <<'EOF_HELPER'
#!/bin/sh
exit 0
EOF_HELPER
cat >"$TARGET_ROOT/usr/bin/unshare" <<'EOF_UNSHARE'
#!/bin/sh
printf 'real-unshare\n'
EOF_UNSHARE
cat >"$TARGET_ROOT/usr/bin/dpkg-divert" <<'EOF_DPKG_DIVERT'
#!/bin/sh
exit 1
EOF_DPKG_DIVERT
cat >"$STUB_BIN/chroot" <<'EOF_CHROOT'
#!/bin/sh
set -eu

root=$1
shift
[ "${1:-}" = /usr/bin/dpkg-divert ] || exit 90
shift

action=
path=
divert=
while [ "$#" -gt 0 ]; do
  case "$1" in
    --list|--add|--remove)
      action=${1#--}
      path=${2:-}
      shift 2
      ;;
    --divert)
      divert=${2:-}
      shift 2
      ;;
    --quiet|--local|--rename)
      shift
      ;;
    *)
      exit 91
      ;;
  esac
done

state="$root/var/lib/dpkg/preseed-test-unshare-diversion"
case "$action" in
  list)
    [ -r "$state" ] && cat "$state"
    ;;
  add)
    [ -n "$path" ] && [ -n "$divert" ]
    mv "$root$path" "$root$divert"
    printf 'local diversion of %s to %s\n' "$path" "$divert" >"$state"
    ;;
  remove)
    [ -n "$path" ] && [ -n "$divert" ] && [ -r "$state" ]
    mv "$root$divert" "$root$path"
    rm -f "$state"
    ;;
  *)
    exit 92
    ;;
esac
EOF_CHROOT

chmod 0700 \
  "$TARGET_ROOT/etc/systemd" \
  "$TARGET_ROOT/etc/systemd/system" \
  "$TARGET_ROOT/etc/systemd/system/tailscaled.service.d" \
  "$TARGET_ROOT/etc/systemd/system/crowdsec-firewall-bouncer.service.d"
chmod 0600 \
  "$TARGET_ROOT/etc/systemd/system/tailscale-managed-bootstrap.service" \
  "$TARGET_ROOT/etc/systemd/system/managed-syncthing.service" \
  "$TARGET_ROOT/etc/systemd/system/crowdsec-firstboot.service" \
  "$TARGET_ROOT/etc/systemd/system/secondboot.service" \
  "$TARGET_ROOT/etc/systemd/system/tailscaled.service.d/override.conf" \
  "$TARGET_ROOT/etc/systemd/system/crowdsec-firewall-bouncer.service.d/override.conf" \
  "$TARGET_ROOT/usr/local/sbin/managed-network"
chmod 0755 \
  "$TARGET_ROOT/usr/bin/unshare" \
  "$TARGET_ROOT/usr/bin/dpkg-divert" \
  "$STUB_BIN/chroot"

printf '[Default Applications]\n' >"$TARGET_ROOT/home/desktop/.config/mimeapps.list"
printf '#!/bin/sh\nexit 0\n' >"$TARGET_ROOT/home/desktop/bin/tool"
printf '# group-only execute must not be promoted\n' >"$TARGET_ROOT/home/desktop/bin/group-tool"
chmod 0775 "$TARGET_ROOT/home/desktop" "$TARGET_ROOT/home/desktop/.config" "$TARGET_ROOT/home/desktop/bin"
chmod 0664 "$TARGET_ROOT/home/desktop/.config/mimeapps.list"
chmod 0755 "$TARGET_ROOT/home/desktop/bin/tool"
chmod 0010 "$TARGET_ROOT/home/desktop/bin/group-tool"

cat >"$TARGET_ROOT/etc/fstab" <<'EOF_FSTAB'
tmpfs /tmp tmpfs rw,nosuid,nodev,noexec,mode=1777 0 0
tmpfs /dev/shm tmpfs rw,nosuid,nodev,noexec,mode=1777 0 0
tmpfs /var/log tmpfs rw,nosuid,nodev,noexec,mode=0755 0 0
tmpfs /var/cache tmpfs rw,nosuid,nodev,noexec,mode=0755 0 0
tmpfs /var/lib/apt/lists tmpfs rw,nosuid,nodev,noexec,mode=0755 0 0
tmpfs /var/lib/systemd/coredump tmpfs rw,nosuid,nodev,noexec,mode=0755 0 0
tmpfs /data/run tmpfs rw,nosuid,nodev,noexec,mode=0755 0 0
EOF_FSTAB

for volatile_dir in \
  "$TARGET_ROOT/data/run" \
  "$TARGET_ROOT/dev/shm" \
  "$TARGET_ROOT/tmp" \
  "$TARGET_ROOT/var/cache" \
  "$TARGET_ROOT/var/lib/apt/lists" \
  "$TARGET_ROOT/var/lib/systemd/coredump" \
  "$TARGET_ROOT/var/log" \
  "$TARGET_ROOT/var/tmp"
do
  printf 'stale installer content\n' >"$volatile_dir/stale"
done

cat >"$ENV_DIR/host.env" <<EOF_ENV
DIR_TMP="/tmp"
DIR_VAR_TMP="/var/tmp"
DIR_VAR_LOG="/var/log"
DIR_VAR_CACHE="/var/cache"
DIR_APT_LISTS="/var/lib/apt/lists"
DIR_DEV_SHM="/dev/shm"
DIR_DATA_RUN="/data/run"
DIR_SYSTEMD_COREDUMP="/var/lib/systemd/coredump"
TMPFS_VAR_LOG="true"
TMPFS_VAR_CACHE="true"
TMPFS_VAR_LIB_APT_LISTS="true"
TMPFS_DEV_SHM="true"
TMPFS_DATA_RUN="true"
TMPFS_SYSTEMD_COREDUMP="true"
EOF_ENV

cat >"$ENV_DIR/account.env" <<'EOF_ENV'
ACCOUNT_HOME="/home/desktop"
EOF_ENV

cat >"$ENV_DIR/runtime.env" <<'EOF_ENV'
# Runtime overrides are intentionally empty for this smoke.
EOF_ENV

TEMPORARY_UNSHARE_HOOK="$ROOT_DIR/d-i/forky/hooks/shared/pre-pkgsel.d/89temporary-unshare.sh"
if PATH="$STUB_BIN:/usr/bin:/bin" \
   INSTALLER_TARGET_DIR="$TARGET_ROOT" \
   /bin/sh "$TEMPORARY_UNSHARE_HOOK" >/dev/null 2>&1 &&
   [ -x "$TARGET_ROOT/usr/bin/unshare.installer-real" ] &&
   grep -Fqx '# INSTALLER_TEMPORARY_FAKE_UNSHARE_V1' "$TARGET_ROOT/usr/bin/unshare" &&
   "$TARGET_ROOT/usr/bin/unshare" --user --map-root-user /bin/false &&
   [ -r "$TARGET_ROOT/var/lib/installer-state/temporary-unshare-shim" ]; then
  pass "pre-pkgsel hook diverts the real unshare binary and installs the temporary success-only shim"
else
  fail "pre-pkgsel hook diverts the real unshare binary and installs the temporary success-only shim"
fi

FINISH_HOOK="$ROOT_DIR/d-i/forky/hooks/shared/finish-install.d/99-normalize-finish"
if PATH="$STUB_BIN:/usr/bin:/bin" \
   INSTALLER_TARGET_DIR="$TARGET_ROOT" \
   INSTALLER_ENV_DIR="$ENV_DIR" \
   INSTALLER_ASSUME_TARGET_MOUNTED=1 \
   /bin/sh "$FINISH_HOOK" >/dev/null 2>&1; then
  pass "finish-install normalizer runs successfully against a synthetic target"
else
  fail "finish-install normalizer runs successfully against a synthetic target"
fi

if assert_mode 755 "$TARGET_ROOT/etc/systemd" &&
   assert_mode 755 "$TARGET_ROOT/etc/systemd/system" &&
   assert_mode 755 "$TARGET_ROOT/etc/systemd/system/tailscaled.service.d" &&
   assert_mode 755 "$TARGET_ROOT/etc/systemd/system/crowdsec-firewall-bouncer.service.d"; then
  pass "finish-install normalizer restores staged systemd unit ancestors and drop-in directories to 0755"
else
  fail "finish-install normalizer restores staged systemd unit ancestors and drop-in directories to 0755"
fi

if assert_mode 644 "$TARGET_ROOT/etc/systemd/system/tailscale-managed-bootstrap.service" &&
   assert_mode 644 "$TARGET_ROOT/etc/systemd/system/managed-syncthing.service" &&
   assert_mode 644 "$TARGET_ROOT/etc/systemd/system/crowdsec-firstboot.service" &&
   assert_mode 644 "$TARGET_ROOT/etc/systemd/system/secondboot.service" &&
   assert_mode 644 "$TARGET_ROOT/etc/systemd/system/tailscaled.service.d/override.conf" &&
   assert_mode 644 "$TARGET_ROOT/etc/systemd/system/crowdsec-firewall-bouncer.service.d/override.conf"; then
  pass "finish-install normalizer restores staged systemd unit files and drop-ins to 0644"
else
  fail "finish-install normalizer restores staged systemd unit files and drop-ins to 0644"
fi

if assert_mode 755 "$TARGET_ROOT/usr/local/sbin/managed-network"; then
  pass "finish-install normalizer restores managed helper scripts to 0755"
else
  fail "finish-install normalizer restores managed helper scripts to 0755"
fi

if assert_mode 700 "$TARGET_ROOT/home/desktop" &&
   assert_mode 700 "$TARGET_ROOT/home/desktop/.config" &&
   assert_mode 700 "$TARGET_ROOT/home/desktop/bin" &&
   assert_mode 600 "$TARGET_ROOT/home/desktop/.config/mimeapps.list" &&
   assert_mode 700 "$TARGET_ROOT/home/desktop/bin/tool" &&
   assert_mode 600 "$TARGET_ROOT/home/desktop/bin/group-tool"; then
  pass "finish-install normalizer makes account directories private and preserves only owner executability"
else
  fail "finish-install normalizer makes account directories private and preserves only owner executability"
fi

volatile_dirs_empty=true
for volatile_dir in \
  "$TARGET_ROOT/data/run" \
  "$TARGET_ROOT/dev/shm" \
  "$TARGET_ROOT/tmp" \
  "$TARGET_ROOT/var/cache" \
  "$TARGET_ROOT/var/lib/apt/lists" \
  "$TARGET_ROOT/var/lib/systemd/coredump" \
  "$TARGET_ROOT/var/log" \
  "$TARGET_ROOT/var/tmp"
do
  [ -z "$(find "$volatile_dir" -mindepth 1 -maxdepth 1 -print -quit)" ] ||
    volatile_dirs_empty=false
done
if [ "$volatile_dirs_empty" = true ] &&
   assert_mode 1777 "$TARGET_ROOT/tmp" &&
   assert_mode 1777 "$TARGET_ROOT/var/tmp" &&
   assert_mode 1777 "$TARGET_ROOT/dev/shm"; then
  pass "finish-install normalizer empties every target tmpfs backing directory plus var-tmp"
else
  fail "finish-install normalizer empties every target tmpfs backing directory plus var-tmp"
fi

restored_unshare_output=$("$TARGET_ROOT/usr/bin/unshare" 2>/dev/null || true)
if [ "$restored_unshare_output" = real-unshare ] &&
   [ ! -e "$TARGET_ROOT/usr/bin/unshare.installer-real" ] &&
   [ ! -e "$TARGET_ROOT/var/lib/installer-state/temporary-unshare-shim" ] &&
   [ ! -e "$TARGET_ROOT/var/lib/dpkg/preseed-test-unshare-diversion" ]; then
  pass "finish-install normalizer removes the fake unshare shim and restores the diverted real binary"
else
  fail "finish-install normalizer removes the fake unshare shim and restores the diverted real binary"
fi

mv "$TARGET_ROOT/usr/bin/unshare" "$TARGET_ROOT/usr/bin/unshare.installer-real"
printf '%s\n' INSTALLER_TEMPORARY_FAKE_UNSHARE_V1 \
  >"$TARGET_ROOT/var/lib/installer-state/temporary-unshare-shim"
printf 'local diversion of %s to %s\n' \
  /usr/bin/unshare \
  /usr/bin/unshare.installer-real \
  >"$TARGET_ROOT/var/lib/dpkg/preseed-test-unshare-diversion"
if PATH="$STUB_BIN:/usr/bin:/bin" \
   INSTALLER_TARGET_DIR="$TARGET_ROOT" \
   INSTALLER_ENV_DIR="$ENV_DIR" \
   INSTALLER_ASSUME_TARGET_MOUNTED=1 \
   /bin/sh "$FINISH_HOOK" >/dev/null 2>&1 &&
   [ "$("$TARGET_ROOT/usr/bin/unshare" 2>/dev/null || true)" = real-unshare ] &&
   [ ! -e "$TARGET_ROOT/usr/bin/unshare.installer-real" ] &&
   [ ! -e "$TARGET_ROOT/var/lib/installer-state/temporary-unshare-shim" ]; then
  pass "finish-install normalizer recovers when an earlier cleanup removed the shim before restoring the diversion"
else
  fail "finish-install normalizer recovers when an earlier cleanup removed the shim before restoring the diversion"
fi

[ "$FAIL_COUNT" -eq 0 ]
