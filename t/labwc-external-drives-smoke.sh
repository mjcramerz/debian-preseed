#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/labwc-external-drives.XXXXXX")
trap 'rm -rf "$TMP_DIR"' EXIT HUP INT TERM

TEST_COUNT=11
TEST_INDEX=0

pass() {
  TEST_INDEX=$((TEST_INDEX + 1))
  printf 'ok %s - %s\n' "$TEST_INDEX" "$1"
}

fail() {
  TEST_INDEX=$((TEST_INDEX + 1))
  printf 'not ok %s - %s\n' "$TEST_INDEX" "$1"
  exit 1
}

desktop_cfg="$ROOT_DIR/d-i/forky/classes/class-select/role/desktop.cfg"
maintenance_menu="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-maintenance-menu"
drive_helper="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-external-drives"
components="$ROOT_DIR/d-i/forky/scripts/desktop/components.sh"
desktop_verify="$ROOT_DIR/d-i/forky/scripts/desktop/verify.sh"
udev_rules="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/udev/rules.d/90-udisks-behavior.rules"
polkit_rules="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/polkit-1/rules.d/50-usb-policy.rules"
tmpfiles_rules="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/tmpfiles.d/25-desktop-media-runtime.conf"
apparmor_profile="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/managed-desktop-wrappers"
external_drive_apparmor_block="$TMP_DIR/managed-labwc-external-drives.apparmor"

sed -n \
  '/^profile managed-labwc-external-drives /,/^}/p' \
  "$apparmor_profile" >"$external_drive_apparmor_block"

printf '1..%s\n' "$TEST_COUNT"

if grep -Eq '(^|[[:space:]])thunar/forky([[:space:]]|$)' "$desktop_cfg" &&
   grep -Eq '(^|[[:space:]])udisks2([[:space:]]|$)' "$desktop_cfg" &&
   grep -Eq '(^|[[:space:]])eject([[:space:]]|$)' "$desktop_cfg" &&
   grep -Fq "'Manage External Drives'" "$maintenance_menu"; then
  pass "desktop selects Forky Thunar and exposes the UDisks drive action"
else
  fail "desktop selects Forky Thunar and exposes the UDisks drive action"
fi

if grep -q 'ENV{DEVTYPE}=="disk".*ENV{UDISKS_CAN_POWER_OFF}="1"' "$udev_rules" &&
   ! grep -q 'ENV{DEVTYPE}=="partition".*ENV{UDISKS_CAN_POWER_OFF}="1"' "$udev_rules" &&
   grep -q 'ENV{UDISKS_AUTO}="0"' "$udev_rules" &&
   grep -q 'ENV{UDISKS_FILESYSTEM_SHARED}="0"' "$udev_rules" &&
   grep -q '"org.freedesktop.udisks2.filesystem-mount": true' "$polkit_rules" &&
   grep -q '"org.freedesktop.udisks2.filesystem-unmount-others": true' "$polkit_rules" &&
   grep -q '"org.freedesktop.udisks2.eject-media": true' "$polkit_rules" &&
   grep -q '"org.freedesktop.udisks2.power-off-drive": true' "$polkit_rules" &&
   ! grep -q '"org.freedesktop.udisks2.filesystem-unmount": true' "$polkit_rules" &&
   ! grep -q '"org.freedesktop.udisks2.drive-eject": true' "$polkit_rules" &&
   ! grep -Eq 'filesystem-unmount(-others)?|drive-eject|UDISKS_(AUTO|FILESYSTEM_SHARED)' \
     "$desktop_verify" &&
   grep -q '^d __INSTALLER_DIR_RUN_MEDIA__/__INSTALLER_ACCOUNT_USERNAME__ 0750 __INSTALLER_ACCOUNT_USERNAME__ usbmedia -$' "$tmpfiles_rules"; then
  pass "udev, polkit, and tmpfiles use real UDisks2 actions while target verification stays metadata-only"
else
  fail "udev, polkit, or tmpfiles retain invalid UDisks2 action policy"
fi

if grep -q '^MAX_RECORDS=128$' "$drive_helper" &&
   grep -q '^SYNC_TIMEOUT_SECONDS=120$' "$drive_helper" &&
   grep -q '^UDISKS_TIMEOUT_SECONDS=120$' "$drive_helper" &&
   grep -q '^UDISKS_KILL_AFTER_SECONDS=5$' "$drive_helper" &&
   grep -q '^UNMOUNT_CONFIRM_ATTEMPTS=30$' "$drive_helper" &&
   grep -q '^MOUNTINFO_FILE=/proc/self/mountinfo$' "$drive_helper" &&
   grep -q '^sync_volume_filesystem() {$' "$drive_helper" &&
   grep -q '^run_udisksctl() {$' "$drive_helper" &&
   grep -q '^wait_until_unmounted() {$' "$drive_helper" &&
   grep -Fq 'sync --file-system -- "$mountpoint"' "$drive_helper" &&
   grep -Fq 'flock --exclusive --nonblock 9' "$drive_helper" &&
   grep -Fq "run_udisksctl mount --block-device \"\$device\"" "$drive_helper" &&
   grep -Fq "run_udisksctl unmount --block-device \"\$device\"" "$drive_helper" &&
   grep -Fq "run_udisksctl power-off --block-device \"\$disk_device\"" "$drive_helper" &&
   ! grep -Eq 'output=\$\(udisksctl (mount|unmount|power-off)' "$drive_helper" &&
   grep -q 'was not force-unmounted' "$drive_helper" &&
   ! grep -q -- '--force' "$drive_helper" &&
   ! grep -Eq '(^|[[:space:]])umount([[:space:]]|$)|(^|[[:space:]])eject([[:space:]]|$)|--lazy' "$drive_helper" &&
   ! grep -Eq '(^|[[:space:]])eval([[:space:]]|$)|/bin/sh -c' "$drive_helper"; then
  pass "external-drive helper bounds sync and unmount confirmation without unsafe fallbacks"
else
  fail "external-drive helper bounds sync and unmount confirmation without unsafe fallbacks"
fi

if grep -q 'usr/local/bin/labwc-external-drives /usr/local/bin/labwc-external-drives 0755' "$components" &&
   grep -q '/usr/local/bin/labwc-external-drives' "$desktop_verify" &&
   grep -Fq '/usr/bin/{awk,flock,gawk,id,mawk,mktemp,nawk,rm,rmdir,sleep,sync,timeout} rix,' "$external_drive_apparmor_block" &&
   grep -Fq '/usr/bin/{lsblk,notify-send,udevadm,udisksctl} rix,' "$external_drive_apparmor_block" &&
   ! grep -Eq '[pP][uU]x,' "$external_drive_apparmor_block" &&
   grep -Fq 'signal (send) set=(kill term) peer=managed-labwc-external-drives,' "$external_drive_apparmor_block" &&
   grep -Fq '@{PROC}/@{pid}/mountinfo r,' "$external_drive_apparmor_block" &&
   grep -Fq '/run/udev/data/b[0-9]*:[0-9]* r,' "$external_drive_apparmor_block" &&
   grep -Fq '/{media,mnt,run/media}/** r,' "$external_drive_apparmor_block" &&
   grep -Fq 'peer=(name=org.freedesktop.Notifications),' "$external_drive_apparmor_block" &&
   grep -Fq 'peer=(name=org.freedesktop.UDisks2),' "$external_drive_apparmor_block" &&
   grep -Fq 'owner /run/user/[0-9]*/labwc-external-drives.lock rwk,' "$external_drive_apparmor_block" &&
   /bin/sh -n "$drive_helper" &&
   /bin/sh -n "$maintenance_menu"; then
  pass "desktop staging and AppArmor include the serialized drive helper runtime"
else
  fail "desktop staging or AppArmor omits the serialized drive helper runtime"
fi

run_thunar_version_case() (
  mock_version=$1
  expected_result=$2

  # components.sh contains function definitions only. Replace its target
  # helpers so this check compares controlled Debian version strings without
  # inspecting the development host's installed package database.
  . "$components"
  capture_in_target() {
    case "$1" in
      'read installed Thunar package status')
        printf '%s\n' 'install ok installed'
        ;;
      'read installed Thunar package version')
        printf '%s\n' "$mock_version"
        ;;
      *)
        return 1
        ;;
    esac
  }
  test_in_target() {
    "$@" >/dev/null 2>&1
  }
  installer_fatal() {
    return 1
  }
  desktop_log() {
    :
  }

  actual_result=fail
  if desktop_require_safe_thunar_eject_version; then
    actual_result=pass
  fi
  [ "$actual_result" = "$expected_result" ]
)

if grep -q '^desktop_require_safe_thunar_eject_version() {$' "$components" &&
   grep -q '^  desktop_thunar_minimum_version=4.20.9$' "$components" &&
   grep -q '^  desktop_require_safe_thunar_eject_version$' "$components" &&
   run_thunar_version_case 4.19.3-1 fail &&
   run_thunar_version_case 4.20.8-1 fail &&
   run_thunar_version_case 4.20.9-1+b1 pass &&
   run_thunar_version_case 'invalid version' fail; then
  pass "desktop installation rejects Thunar builds that predate the external-drive eject crash fixes"
else
  fail "desktop installation accepts a Thunar build with known external-drive eject crashes"
fi

harness="$TMP_DIR/harness"
bin_dir="$harness/bin"
dev_root="$harness/dev"
runtime_dir="$harness/runtime"
responses="$harness/responses"
state_one="$harness/mount-sdb1"
state_two="$harness/mount-sdb2"
mountinfo_file="$harness/mountinfo"
udisks_log="$harness/udisks.log"
sync_log="$harness/sync.log"
events_log="$harness/events.log"
mount_one='/run/media/test/F2FS MEDIA'
mount_two='/run/media/test/EXT4'
mkdir -p "$bin_dir" "$dev_root" "$runtime_dir"
touch "$dev_root/sdb" "$dev_root/sdb1" "$dev_root/sdb2"

write_mountinfo() {
  : >"$mountinfo_file"

  mountpoint=$(cat "$state_one")
  if [ -n "$mountpoint" ]; then
    case "$mountpoint" in
      "$mount_one") encoded_mountpoint='/run/media/test/F2FS\040MEDIA' ;;
      *) fail "test harness received an unknown F2FS mount point" ;;
    esac
    printf '31 24 8:17 / %s rw,nosuid,nodev,relatime - f2fs %s rw\n' \
      "$encoded_mountpoint" \
      "$dev_root/sdb1" >>"$mountinfo_file"
  fi

  mountpoint=$(cat "$state_two")
  if [ -n "$mountpoint" ]; then
    case "$mountpoint" in
      "$mount_two") encoded_mountpoint='/run/media/test/EXT4' ;;
      *) fail "test harness received an unknown ext4 mount point" ;;
    esac
    printf '32 24 8:18 / %s rw,nosuid,nodev,relatime - ext4 %s rw\n' \
      "$encoded_mountpoint" \
      "$dev_root/sdb2" >>"$mountinfo_file"
  fi
}

reset_mounted_state() {
  printf '%s\n' "$mount_one" >"$state_one"
  printf '%s\n' "$mount_two" >"$state_two"
  write_mountinfo
  : >"$udisks_log"
  : >"$sync_log"
  : >"$events_log"
}

reset_mounted_state

cat >"$bin_dir/id" <<'EOF'
#!/bin/sh
[ "${1:-}" = -u ] && { printf '%s\n' 1000; exit 0; }
exec /usr/bin/id "$@"
EOF

cat >"$bin_dir/udevadm" <<'EOF'
#!/bin/sh
exit 0
EOF

cat >"$bin_dir/lsblk" <<'EOF'
#!/bin/sh
set -eu

last_argument=
for current_argument in "$@"; do
  last_argument=$current_argument
done

disk="${DRIVE_DEV_ROOT:?}/sdb"
volume_one="${DRIVE_DEV_ROOT:?}/sdb1"
volume_two="${DRIVE_DEV_ROOT:?}/sdb2"
mountpoint_one=$(cat "${DRIVE_STATE_ONE:?}")
mountpoint_two=$(cat "${DRIVE_STATE_TWO:?}")

case "$mountpoint_one" in
  '') mountpoints_one= ;;
  "${DRIVE_MOUNT_ONE:?}") mountpoints_one='/run/media/test/F2FS\x20MEDIA' ;;
  *) exit 1 ;;
esac
case "$mountpoint_two" in
  '') mountpoints_two= ;;
  "${DRIVE_MOUNT_TWO:?}") mountpoints_two='/run/media/test/EXT4' ;;
  *) exit 1 ;;
esac

case "$*" in
  *'--output MAJ:MIN,TYPE,TRAN'*)
    case "$last_argument" in
      "$disk") printf '%s\n' '8:16 disk usb' ;;
      "$volume_one") printf '%s\n' '8:17 part usb' ;;
      "$volume_two") printf '%s\n' '8:18 part usb' ;;
      *) exit 1 ;;
    esac
    ;;
  *'--output FSTYPE'*)
    case "$last_argument" in
      "$volume_one") printf '%s\n' f2fs ;;
      "$volume_two") printf '%s\n' ext4 ;;
      *) exit 1 ;;
    esac
    ;;
  *'--output PATH,TYPE,FSTYPE,LABEL,MODEL,SIZE,TRAN,RM,HOTPLUG,MOUNTPOINTS,PKNAME,MAJ:MIN'*)
    printf 'PATH="%s" TYPE="disk" FSTYPE="" LABEL="" MODEL="Test\\x20USB" SIZE="64000000000" TRAN="usb" RM="0" HOTPLUG="1" MOUNTPOINTS="" PKNAME="" MAJ:MIN="8:16"\n' "$disk"
    printf 'PATH="%s" TYPE="part" FSTYPE="f2fs" LABEL="F2FS\\x20MEDIA" MODEL="" SIZE="32000000000" TRAN="usb" RM="0" HOTPLUG="1" MOUNTPOINTS="%s" PKNAME="sdb" MAJ:MIN="8:17"\n' "$volume_one" "$mountpoints_one"
    printf 'PATH="%s" TYPE="part" FSTYPE="ext4" LABEL="EXT4" MODEL="" SIZE="31900000000" TRAN="usb" RM="0" HOTPLUG="1" MOUNTPOINTS="%s" PKNAME="sdb" MAJ:MIN="8:18"\n' "$volume_two" "$mountpoints_two"
    ;;
  *)
    printf 'unsupported mock lsblk invocation: %s\n' "$*" >&2
    exit 1
    ;;
esac
EOF

cat >"$bin_dir/labwc-fuzzel" <<'EOF'
#!/bin/sh
set -eu
cat >/dev/null
response=$(sed -n '1p' "${FUZZEL_RESPONSES:?}")
sed '1d' "$FUZZEL_RESPONSES" >"${FUZZEL_RESPONSES}.next"
mv "${FUZZEL_RESPONSES}.next" "$FUZZEL_RESPONSES"
printf '%s\n' "$response"
EOF

cat >"$bin_dir/sync" <<'EOF'
#!/bin/sh
set -eu

last_argument=
for current_argument in "$@"; do
  last_argument=$current_argument
done

printf '%s\n' "$*" >>"${SYNC_LOG:?}"
printf 'sync %s\n' "$*" >>"${EVENTS_LOG:?}"
if [ -n "${SYNC_FAIL_MOUNTPOINT:-}" ] &&
   [ "$last_argument" = "$SYNC_FAIL_MOUNTPOINT" ]
then
  printf '%s\n' 'mock sync failure' >&2
  exit 74
fi
EOF

cat >"$bin_dir/udisksctl" <<'EOF'
#!/bin/sh
set -eu

encode_mountpoint() {
  case "$1" in
    "${DRIVE_MOUNT_ONE:?}") printf '%s\n' '/run/media/test/F2FS\040MEDIA' ;;
    "${DRIVE_MOUNT_TWO:?}") printf '%s\n' '/run/media/test/EXT4' ;;
    *) return 1 ;;
  esac
}

refresh_mountinfo() {
  : >"${DRIVE_MOUNTINFO:?}"

  mountpoint=$(cat "${DRIVE_STATE_ONE:?}")
  if [ -n "$mountpoint" ]; then
    encoded_mountpoint=$(encode_mountpoint "$mountpoint")
    printf '31 24 8:17 / %s rw,nosuid,nodev,relatime - f2fs %s rw\n' \
      "$encoded_mountpoint" \
      "${DRIVE_DEV_ROOT:?}/sdb1" >>"$DRIVE_MOUNTINFO"
  fi

  mountpoint=$(cat "${DRIVE_STATE_TWO:?}")
  if [ -n "$mountpoint" ]; then
    encoded_mountpoint=$(encode_mountpoint "$mountpoint")
    printf '32 24 8:18 / %s rw,nosuid,nodev,relatime - ext4 %s rw\n' \
      "$encoded_mountpoint" \
      "${DRIVE_DEV_ROOT:?}/sdb2" >>"$DRIVE_MOUNTINFO"
  fi
}

device=
for current_argument in "$@"; do
  device=$current_argument
done

printf '%s\n' "$*" >>"${UDISKS_LOG:?}"
printf 'udisks %s\n' "$*" >>"${EVENTS_LOG:?}"
if [ -n "${UDISKS_HANG_ACTION:-}" ] &&
   [ "${1:-}" = "$UDISKS_HANG_ACTION" ] &&
   [ -n "${UDISKS_HANG_DEVICE:-}" ] &&
   [ "$device" = "$UDISKS_HANG_DEVICE" ]
then
  while :; do :; done
fi
case "${1:-}" in
  mount)
    case "$device" in
      "${DRIVE_DEV_ROOT:?}/sdb1")
        printf '%s\n' "${DRIVE_MOUNT_ONE:?}" >"${DRIVE_STATE_ONE:?}"
        ;;
      "${DRIVE_DEV_ROOT:?}/sdb2")
        printf '%s\n' "${DRIVE_MOUNT_TWO:?}" >"${DRIVE_STATE_TWO:?}"
        ;;
      *) exit 1 ;;
    esac
    refresh_mountinfo
    printf '%s\n' "Mounted $device"
    ;;
  unmount)
    if [ -n "${UDISKS_FAIL_UNMOUNT_DEVICE:-}" ] &&
       [ "$device" = "$UDISKS_FAIL_UNMOUNT_DEVICE" ]
    then
      printf '%s\n' 'mock busy filesystem' >&2
      exit 32
    fi
    if [ -z "${UDISKS_STICKY_UNMOUNT_DEVICE:-}" ] ||
       [ "$device" != "$UDISKS_STICKY_UNMOUNT_DEVICE" ]
    then
      case "$device" in
        "${DRIVE_DEV_ROOT:?}/sdb1") : >"${DRIVE_STATE_ONE:?}" ;;
        "${DRIVE_DEV_ROOT:?}/sdb2") : >"${DRIVE_STATE_TWO:?}" ;;
        *) exit 1 ;;
      esac
      refresh_mountinfo
    fi
    printf '%s\n' "Unmounted $device"
    ;;
  power-off)
    [ "$device" = "${DRIVE_DEV_ROOT:?}/sdb" ] || exit 1
    : >"${DRIVE_STATE_ONE:?}"
    : >"${DRIVE_STATE_TWO:?}"
    refresh_mountinfo
    printf '%s\n' "Powered off $device"
    ;;
  *)
    exit 1
    ;;
esac
EOF
chmod 0755 "$bin_dir"/*

rendered_helper="$harness/labwc-external-drives"
sed \
  -e "s|^PATH=/usr/local/bin:/usr/bin:/bin$|PATH=$bin_dir:/usr/bin:/bin|" \
  -e "s|^DEV_ROOT=/dev$|DEV_ROOT=$dev_root|" \
  -e "s|^MOUNTINFO_FILE=/proc/self/mountinfo$|MOUNTINFO_FILE=$mountinfo_file|" \
  -e 's/^UDISKS_TIMEOUT_SECONDS=120$/UDISKS_TIMEOUT_SECONDS=1/' \
  -e 's/^UDISKS_KILL_AFTER_SECONDS=5$/UDISKS_KILL_AFTER_SECONDS=1/' \
  -e 's/^UNMOUNT_CONFIRM_ATTEMPTS=30$/UNMOUNT_CONFIRM_ATTEMPTS=2/' \
  -e 's/^UNMOUNT_CONFIRM_INTERVAL_SECONDS=1$/UNMOUNT_CONFIRM_INTERVAL_SECONDS=0/' \
  -e "s/\\[ -b \"\\\$device\" \\]/[ -e \"\\\$device\" ]/" \
  -e "s/\\[ -b \"\\\$disk_device\" \\]/[ -e \"\\\$disk_device\" ]/" \
  -e 's#^\[ -S /run/dbus/system_bus_socket \] ||$#true ||#' \
  "$drive_helper" >"$rendered_helper"
chmod 0755 "$rendered_helper"

SYNC_FAIL_MOUNTPOINT=
UDISKS_FAIL_UNMOUNT_DEVICE=
UDISKS_HANG_ACTION=
UDISKS_HANG_DEVICE=
UDISKS_STICKY_UNMOUNT_DEVICE=

run_helper() {
  DRIVE_DEV_ROOT="$dev_root" \
  DRIVE_STATE_ONE="$state_one" \
  DRIVE_STATE_TWO="$state_two" \
  DRIVE_MOUNTINFO="$mountinfo_file" \
  DRIVE_MOUNT_ONE="$mount_one" \
  DRIVE_MOUNT_TWO="$mount_two" \
  EVENTS_LOG="$events_log" \
  FUZZEL_RESPONSES="$responses" \
  SYNC_FAIL_MOUNTPOINT="$SYNC_FAIL_MOUNTPOINT" \
  SYNC_LOG="$sync_log" \
  UDISKS_FAIL_UNMOUNT_DEVICE="$UDISKS_FAIL_UNMOUNT_DEVICE" \
  UDISKS_HANG_ACTION="$UDISKS_HANG_ACTION" \
  UDISKS_HANG_DEVICE="$UDISKS_HANG_DEVICE" \
  UDISKS_LOG="$udisks_log" \
  UDISKS_STICKY_UNMOUNT_DEVICE="$UDISKS_STICKY_UNMOUNT_DEVICE" \
  XDG_RUNTIME_DIR="$runtime_dir" \
  /bin/sh "$rendered_helper"
}

cat >"$responses" <<'EOF'
002
Unmount Volume
002
Mount Volume
001
Safely Power Off Drive
Sync, unmount volumes, and power off
999
EOF

if run_helper &&
   [ "$(cat "$udisks_log")" = "unmount --block-device $dev_root/sdb1
mount --block-device $dev_root/sdb1
unmount --block-device $dev_root/sdb1
unmount --block-device $dev_root/sdb2
power-off --block-device $dev_root/sdb" ] &&
   [ "$(cat "$events_log")" = "sync --file-system -- $mount_one
udisks unmount --block-device $dev_root/sdb1
udisks mount --block-device $dev_root/sdb1
sync --file-system -- $mount_one
sync --file-system -- $mount_two
udisks unmount --block-device $dev_root/sdb1
udisks unmount --block-device $dev_root/sdb2
udisks power-off --block-device $dev_root/sdb" ] &&
   [ ! -s "$state_one" ] &&
   [ ! -s "$state_two" ]; then
  pass "F2FS and ext4 volumes sync, unmount, confirm, and power off in order"
else
  fail "F2FS and ext4 volumes sync, unmount, confirm, and power off in order"
fi

reset_mounted_state
cat >"$responses" <<'EOF'
001
Safely Power Off Drive
Sync, unmount volumes, and power off
999
EOF
SYNC_FAIL_MOUNTPOINT=$mount_two
sync_failure_log="$harness/sync-failure.log"

if run_helper >"$sync_failure_log" 2>&1 &&
   [ ! -s "$udisks_log" ] &&
   [ "$(wc -l <"$sync_log" | tr -d ' ')" -eq 2 ] &&
   [ "$(cat "$state_one")" = "$mount_one" ] &&
   [ "$(cat "$state_two")" = "$mount_two" ] &&
   grep -q 'mock sync failure' "$sync_failure_log"; then
  pass "a filesystem sync failure leaves every child mounted and powered"
else
  fail "a filesystem sync failure leaves every child mounted and powered"
fi
SYNC_FAIL_MOUNTPOINT=

reset_mounted_state
cat >"$responses" <<'EOF'
001
Safely Power Off Drive
Sync, unmount volumes, and power off
999
EOF
UDISKS_FAIL_UNMOUNT_DEVICE="$dev_root/sdb1"
busy_log="$harness/busy.log"

if run_helper >"$busy_log" 2>&1 &&
   [ "$(cat "$udisks_log")" = "unmount --block-device $dev_root/sdb1" ] &&
   [ "$(cat "$state_one")" = "$mount_one" ] &&
   [ "$(cat "$state_two")" = "$mount_two" ] &&
   grep -q "^unmount --block-device $dev_root/sdb1$" "$udisks_log" &&
   ! grep -q '^power-off ' "$udisks_log" &&
   grep -q 'mock busy filesystem' "$busy_log"; then
  pass "a busy volume remains mounted and blocks whole-drive power-off"
else
  fail "a busy volume remains mounted and blocks whole-drive power-off"
fi
UDISKS_FAIL_UNMOUNT_DEVICE=

reset_mounted_state
cat >"$responses" <<'EOF'
003
Unmount Volume
999
EOF
UDISKS_HANG_ACTION=unmount
UDISKS_HANG_DEVICE="$dev_root/sdb2"
udisks_timeout_log="$harness/udisks-timeout.log"

if run_helper >"$udisks_timeout_log" 2>&1 &&
   [ "$(cat "$udisks_log")" = "unmount --block-device $dev_root/sdb2" ] &&
   [ "$(cat "$sync_log")" = "--file-system -- $mount_two" ] &&
   [ "$(cat "$state_two")" = "$mount_two" ] &&
   ! grep -q '^power-off ' "$udisks_log"; then
  pass "a timed-out ext4 UDisks request leaves the volume mounted and powered"
else
  fail "a timed-out ext4 UDisks request does not fail safely"
fi
UDISKS_HANG_ACTION=
UDISKS_HANG_DEVICE=

reset_mounted_state
cat >"$responses" <<'EOF'
001
Safely Power Off Drive
Sync, unmount volumes, and power off
999
EOF
UDISKS_STICKY_UNMOUNT_DEVICE="$dev_root/sdb1"
timeout_log="$harness/unmount-timeout.log"

if run_helper >"$timeout_log" 2>&1 &&
   [ "$(cat "$udisks_log")" = "unmount --block-device $dev_root/sdb1" ] &&
   [ "$(cat "$state_one")" = "$mount_one" ] &&
   [ "$(cat "$state_two")" = "$mount_two" ] &&
   ! grep -q "^unmount --block-device $dev_root/sdb2$" "$udisks_log" &&
   ! grep -q '^power-off ' "$udisks_log" &&
   grep -q 'timed out waiting for external volume to unmount' "$timeout_log"; then
  pass "an unmount confirmation timeout leaves the whole drive powered"
else
  fail "an unmount confirmation timeout leaves the whole drive powered"
fi
UDISKS_STICKY_UNMOUNT_DEVICE=

reset_mounted_state
cat >"$responses" <<'EOF'
999
EOF
lock_ready="$harness/lock.ready"
rm -f -- "$lock_ready"
(
  exec 8>"$runtime_dir/labwc-external-drives.lock"
  flock --exclusive 8
  : >"$lock_ready"
  sleep 10
) &
locker_pid=$!
attempt=0
while [ ! -e "$lock_ready" ] && [ "$attempt" -lt 100 ]; do
  sleep 0.02
  attempt=$((attempt + 1))
done
if [ ! -e "$lock_ready" ]; then
  kill "$locker_pid" 2>/dev/null || true
  wait "$locker_pid" 2>/dev/null || true
  fail "test harness could not acquire the external-drive lock"
fi

lock_status=0
run_helper >"$harness/locked.log" 2>&1 || lock_status=$?
kill "$locker_pid" 2>/dev/null || true
wait "$locker_pid" 2>/dev/null || true

if [ "$lock_status" -eq 0 ] &&
   [ ! -s "$events_log" ] &&
   [ "$(cat "$state_one")" = "$mount_one" ] &&
   [ "$(cat "$state_two")" = "$mount_two" ]; then
  pass "the per-user lock prevents overlapping external-drive operations"
else
  fail "the per-user lock prevents overlapping external-drive operations"
fi
