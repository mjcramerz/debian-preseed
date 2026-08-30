#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/timeshift-grub-smoke.XXXXXX")
trap 'rm -rf -- "$TMP_DIR"' EXIT HUP INT TERM

TEST_COUNT=13
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

run_class_case() {
  runtime_name=$1
  classes_raw=$2
  case_dir="$ROOT_DIR/.tmp-timeshift-class-$runtime_name.$$"
  mkdir -p "$case_dir"
  if (
    set -eu
    INSTALLER_SOURCE_ROOT="$ROOT_DIR/d-i/forky"
    INSTALLER_RUNTIME_DIR="$case_dir"
    export INSTALLER_SOURCE_ROOT INSTALLER_RUNTIME_DIR
    # shellcheck disable=SC1090
    . "$ROOT_DIR/d-i/forky/scripts/common/lib.sh"
    installer_auto_class_tokens() { return 0; }
    installer_cmdline_value() {
      case "$1" in
        auto-install/classes|classes)
          printf '%s\n' "$classes_raw"
          ;;
      esac
    }
    installer_debconf_value() { return 1; }
    installer_write_context "$ROOT_DIR/d-i/forky" >/dev/null
  ); then
    rm -rf "$case_dir"
    return 0
  fi
  rm -rf "$case_dir"
  return 1
}

timeshift_perl_compat="$TMP_DIR/perl-compat"
timeshift_module_root="$ROOT_DIR/d-i/forky/hooks/shared/target/usr/local/lib/perl5/site_perl/timeshift-managed"
timeshift_perl_modules='
TimeshiftManaged/CLI.pm
TimeshiftManaged/Command.pm
TimeshiftManaged/Config.pm
TimeshiftManaged/EventQueue.pm
TimeshiftManaged/GrubRefresh.pm
TimeshiftManaged/Logger.pm
TimeshiftManaged/Snapshot.pm
'

timeshift_prepare_perl_compat() {
  mkdir -p \
    "$timeshift_perl_compat/MooX" \
    "$timeshift_perl_compat/Types"

  cat >"$timeshift_perl_compat/MooX/StrictConstructor.pm" <<'EOF'
package MooX::StrictConstructor;
use strict;
use warnings;
sub import { return; }
1;
EOF

  cat >"$timeshift_perl_compat/MooX/TypeTiny.pm" <<'EOF'
package MooX::TypeTiny;
use strict;
use warnings;
sub import { return; }
1;
EOF

  cat >"$timeshift_perl_compat/Types/Standard.pm" <<'EOF'
package Types::Standard;
use strict;
use warnings;
sub import {
    my ($class, @symbols) = @_;
    my $caller = caller;
    no strict "refs";
    for my $symbol (@symbols) {
        *{"${caller}::$symbol"} = sub { return sub { 1 }; };
    }
    return;
}
1;
EOF

  cat >"$timeshift_perl_compat/MooX/Options.pm" <<'EOF'
package MooX::Options;
use strict;
use warnings;
sub import {
    my ($class, @ignored) = @_;
    my $caller = caller;
    no strict "refs";
    *{"${caller}::option"} = sub {
        my ($name, %args) = @_;
        my $has = *{"${caller}::has"}{CODE};
        $has or die "Moo has() is unavailable for $caller\n";
        return $has->($name, %args);
    };
    *{"${caller}::new_with_options"} = sub {
        my ($target, %args) = @_;
        return $target->new(%args, help => 0);
    };
    return;
}
1;
EOF
}

timeshift_class="$ROOT_DIR/d-i/forky/classes/class-addon/timeshift.cfg"
if grep -Eq '^d-i pkgsel/include string timeshift$' "$timeshift_class"; then
  pass "timeshift addon fragment installs the Forky Timeshift package"
else
  fail "timeshift addon fragment installs the Forky Timeshift package"
fi

addons_cfg="$ROOT_DIR/d-i/forky/classes/configs/addons.cfg"
common_lib="$ROOT_DIR/d-i/forky/scripts/common/lib.sh"
if grep -q '^Name: timeshift$' "$addons_cfg" &&
   grep -q '^AllowedHardwareClasses: disk/nvme, disk/vm$' "$addons_cfg" &&
   grep -q 'allowed_hardware_classes=$(installer_class_meta_value' "$common_lib" &&
   grep -q 'selected class ${group_name}/${class_name} is only allowed with one of:' "$common_lib"; then
  pass "timeshift addon is restricted to Btrfs-root storage classes and enforced by class resolution"
else
  fail "timeshift addon is restricted to Btrfs-root storage classes and enforced by class resolution"
fi

if run_class_case allow 'lab,desktop,standard,dhcp,amd64,intel,generic,nvme,timeshift'; then
  pass "timeshift addon is accepted for the Btrfs NVMe class"
else
  fail "timeshift addon is accepted for the Btrfs NVMe class"
fi

if run_class_case deny 'lab,desktop,standard,dhcp,amd64,intel,generic,emmc,timeshift'; then
  fail "timeshift addon is rejected for the F2FS eMMC class"
else
  pass "timeshift addon is rejected for the F2FS eMMC class"
fi

runtime_env="$ROOT_DIR/d-i/forky/hosts/shared/runtime.env"
if grep -q '^FILE_TIMESHIFT_CONFIG=' "$runtime_env" &&
   grep -q '^FILE_TIMESHIFT_SNAPSHOT_HELPER=' "$runtime_env" &&
   grep -q '^FILE_TIMESHIFT_NOTIFY_SHIM=' "$runtime_env" &&
   grep -q '^FILE_TIMESHIFT_GRUB_REFRESH_HOOK=' "$runtime_env" &&
   grep -q '^FILE_GRUB_BTRFS_CONFIG=' "$runtime_env" &&
   grep -q '^FILE_GRUB_BTRFS_REFRESH_HELPER=' "$runtime_env" &&
   grep -q '^FILE_GRUB_BTRFS_REFRESH_PATH=' "$runtime_env"; then
  pass "runtime env exports the managed Timeshift and GRUB snapshot asset paths"
else
  fail "runtime env exports the managed Timeshift and GRUB snapshot asset paths"
fi

timeshift_config="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/timeshift/timeshift.json.tmpl"
if grep -q '"btrfs_mode" : "true"' "$timeshift_config" &&
   grep -q '"parent_device_uuid" : "__INSTALLER_TIMESHIFT_PARENT_DEVICE_UUID__"' "$timeshift_config" &&
   grep -q '"include_btrfs_home_for_backup" : "false"' "$timeshift_config" &&
   grep -q '"include_btrfs_home_for_restore" : "false"' "$timeshift_config" &&
   grep -q '"schedule_monthly" : "false"' "$timeshift_config" &&
   grep -q '"schedule_weekly" : "false"' "$timeshift_config" &&
   grep -q '"schedule_daily" : "false"' "$timeshift_config" &&
   grep -q '"count_daily" : "24"' "$timeshift_config" &&
   grep -q '"count_weekly" : "4"' "$timeshift_config" &&
   grep -q '"count_monthly" : "2"' "$timeshift_config" &&
   grep -q '"date_format" : "%Y-%m-%d %H:%M:%S"' "$timeshift_config" &&
   jq -e '
     .btrfs_mode == "true" and
     .include_btrfs_home_for_backup == "false" and
     .include_btrfs_home_for_restore == "false" and
     .date_format == "%Y-%m-%d %H:%M:%S"
   ' "$timeshift_config" >/dev/null; then
  pass "Timeshift config template encodes the managed retention policy"
else
  fail "Timeshift config template encodes the managed retention policy"
fi

snapshot_helper="$ROOT_DIR/d-i/forky/hooks/shared/target/usr/local/libexec/timeshift-managed-snapshot"
notification_shim="$ROOT_DIR/d-i/forky/hooks/shared/target/usr/local/libexec/timeshift-managed/notify-send"
grub_refresh_hook="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/timeshift/backup-hooks.d/90-grub-btrfs-refresh"
grub_refresh_helper="$ROOT_DIR/d-i/forky/hooks/shared/target/usr/local/libexec/grub-btrfs-refresh"
timeshift_prepare_perl_compat
timeshift_perl_syntax=true
for timeshift_module in $timeshift_perl_modules; do
  if [ ! -r "$timeshift_module_root/$timeshift_module" ] ||
     ! PERL5LIB="$timeshift_perl_compat:$timeshift_module_root" \
       perl -c "$timeshift_module_root/$timeshift_module" >/dev/null 2>&1; then
    timeshift_perl_syntax=false
  fi
done
if [ -x "$snapshot_helper" ] &&
   [ -x "$grub_refresh_helper" ] &&
   [ "$timeshift_perl_syntax" = true ] &&
   PERL5LIB="$timeshift_perl_compat:$timeshift_module_root" \
     perl -c "$snapshot_helper" >/dev/null 2>&1 &&
   PERL5LIB="$timeshift_perl_compat:$timeshift_module_root" \
     perl -c "$grub_refresh_helper" >/dev/null 2>&1 &&
   /bin/sh -n "$notification_shim" &&
   /bin/sh -n "$grub_refresh_hook" &&
   grep -Fqx '#!/usr/bin/perl' "$snapshot_helper" &&
   grep -Fqx '#!/usr/bin/perl' "$grub_refresh_helper" &&
   grep -Fqx 'use TimeshiftManaged::CLI;' "$snapshot_helper" &&
   grep -Fqx 'use TimeshiftManaged::CLI;' "$grub_refresh_helper" &&
   grep -Fqx 'package TimeshiftManaged::Snapshot;' "$timeshift_module_root/TimeshiftManaged/Snapshot.pm" &&
   grep -Fqx 'package TimeshiftManaged::GrubRefresh;' "$timeshift_module_root/TimeshiftManaged/GrubRefresh.pm" &&
   grep -Fq 'system { $argv[0] } @argv;' "$timeshift_module_root/TimeshiftManaged/Command.pm"; then
  pass "managed Timeshift and GRUB helpers are executable Perl entrypoints with syntax-checked modules"
else
  fail "managed Timeshift and GRUB helpers are executable Perl entrypoints with syntax-checked modules"
fi

snapshot_case="$TMP_DIR/snapshot-events"
snapshot_event_root="$snapshot_case/events"
snapshot_lock="$snapshot_case/lock/timeshift.lock"
snapshot_mock="$snapshot_case/timeshift"
snapshot_log="$snapshot_case/timeshift.log"
mkdir -p "$snapshot_case"
cat >"$snapshot_mock" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"$MOCK_TIMESHIFT_LOG"
exit "${MOCK_TIMESHIFT_STATUS:-0}"
EOF
chmod 0755 "$snapshot_mock"
current_uid=$(id -u)
current_gid=$(id -g)
snapshot_success=false
snapshot_failure_status=0
snapshot_notification_failure=false
if MOCK_TIMESHIFT_LOG="$snapshot_log" \
   MOCK_TIMESHIFT_STATUS=0 \
   TIMESHIFT_BINARY="$snapshot_mock" \
   TIMESHIFT_EVENT_ROOT="$snapshot_event_root" \
   TIMESHIFT_EVENT_OWNER_UID="$current_uid" \
   TIMESHIFT_EVENT_OWNER_GID="$current_gid" \
   TIMESHIFT_LOCK_FILE="$snapshot_lock" \
   TIMESHIFT_LOCK_TIMEOUT_SECONDS=2 \
   PERL5LIB="$timeshift_perl_compat" \
     "$snapshot_helper" daily; then
  snapshot_success=true
fi
if MOCK_TIMESHIFT_LOG="$snapshot_log" \
   MOCK_TIMESHIFT_STATUS=7 \
   TIMESHIFT_BINARY="$snapshot_mock" \
   TIMESHIFT_EVENT_ROOT="$snapshot_event_root" \
   TIMESHIFT_EVENT_OWNER_UID="$current_uid" \
   TIMESHIFT_EVENT_OWNER_GID="$current_gid" \
   TIMESHIFT_LOCK_FILE="$snapshot_lock" \
   TIMESHIFT_LOCK_TIMEOUT_SECONDS=2 \
   PERL5LIB="$timeshift_perl_compat" \
     "$snapshot_helper" weekly; then
  snapshot_failure_status=0
else
  snapshot_failure_status=$?
fi
snapshot_bad_event_root="$snapshot_case/not-a-directory"
: >"$snapshot_bad_event_root"
if MOCK_TIMESHIFT_LOG="$snapshot_log" \
   MOCK_TIMESHIFT_STATUS=0 \
   TIMESHIFT_BINARY="$snapshot_mock" \
   TIMESHIFT_EVENT_ROOT="$snapshot_bad_event_root" \
   TIMESHIFT_EVENT_OWNER_UID="$current_uid" \
   TIMESHIFT_EVENT_OWNER_GID="$current_gid" \
   TIMESHIFT_LOCK_FILE="$snapshot_lock" \
   TIMESHIFT_LOCK_TIMEOUT_SECONDS=2 \
   PERL5LIB="$timeshift_perl_compat" \
     "$snapshot_helper" monthly >/dev/null 2>&1; then
  snapshot_notification_failure=true
fi
if [ "$snapshot_success" = true ] &&
   [ "$snapshot_failure_status" -eq 7 ] &&
   [ "$snapshot_notification_failure" = true ] &&
   [ "$(grep -R -h '^started|daily|-$' "$snapshot_event_root/timeshift" 2>/dev/null | wc -l)" -eq 1 ] &&
   [ "$(grep -R -h '^completed|daily|-$' "$snapshot_event_root/timeshift" 2>/dev/null | wc -l)" -eq 1 ] &&
   [ "$(grep -R -h '^started|weekly|-$' "$snapshot_event_root/timeshift" 2>/dev/null | wc -l)" -eq 1 ] &&
   [ "$(grep -R -h '^failed|weekly|7$' "$snapshot_event_root/timeshift" 2>/dev/null | wc -l)" -eq 1 ] &&
   [ "$(wc -l <"$snapshot_log" | tr -d '[:space:]')" -eq 3 ]; then
  pass "Timeshift Perl helper serializes runs, emits lifecycle events, preserves failures, and tolerates notification outages"
else
  fail "Timeshift Perl helper serializes runs, emits lifecycle events, preserves failures, and tolerates notification outages"
fi

hook_case="$TMP_DIR/grub-refresh-hook"
hook_bin="$hook_case/bin"
hook_log="$hook_case/systemctl.log"
hook_error_log="$hook_case/hook.err"
mkdir -p "$hook_bin"
cat >"$hook_bin/systemctl" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"$HOOK_SYSTEMCTL_LOG"
exit "${HOOK_SYSTEMCTL_STATUS:-0}"
EOF
chmod 0755 "$hook_bin/systemctl"

hook_success=false
hook_failure_tolerated=false
if PATH="$hook_bin:$PATH" \
   HOOK_SYSTEMCTL_LOG="$hook_log" \
   TS_SNAPSHOT_PATH=/run/timeshift/123/backup/timeshift-btrfs/snapshots/2026-07-26_12-00-00 \
     /bin/sh "$grub_refresh_hook"; then
  hook_success=true
fi
if PATH="$hook_bin:$PATH" \
   HOOK_SYSTEMCTL_LOG="$hook_log" \
   HOOK_SYSTEMCTL_STATUS=7 \
   TS_SNAPSHOT_PATH=/run/timeshift/124/backup/timeshift-btrfs/snapshots/2026-07-26_15-00-00 \
     /bin/sh "$grub_refresh_hook" 2>"$hook_error_log"; then
  hook_failure_tolerated=true
fi
if [ "$hook_success" = true ] &&
   [ "$hook_failure_tolerated" = true ] &&
   [ "$(grep -Fxc -- '--no-block start grub-btrfs-refresh.service' "$hook_log")" -eq 2 ] &&
   grep -q 'failed to queue GRUB snapshot refresh' "$hook_error_log"; then
  pass "Timeshift post-snapshot hook queues GRUB refreshes without failing completed snapshots"
else
  fail "Timeshift post-snapshot hook queues GRUB refreshes without failing completed snapshots"
fi

grub_refresh_path="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/systemd/system/grub-btrfs-refresh.path"
grub_refresh_service="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/systemd/system/grub-btrfs-refresh.service"
grub_btrfs_config="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/default/grub-btrfs/config.tmpl"
if grep -q '^PathExistsGlob=/run/timeshift/\*/backup/timeshift-btrfs/snapshots$' "$grub_refresh_path" &&
   grep -q '^PrivateMounts=yes$' "$grub_refresh_service" &&
   grep -q '^RuntimeDirectory=grub-btrfs-refresh$' "$grub_refresh_service" &&
   grep -q '^TimeoutStartSec=10m$' "$grub_refresh_service" &&
   grep -q '^Environment=SKIP_MOK_SIGNING=1$' "$grub_refresh_service" &&
   grep -q '^ExecStart=/usr/local/libexec/grub-btrfs-refresh --wait$' "$grub_refresh_service" &&
   grep -q '^GRUB_BTRFS_STATE_DIR="/run/grub-btrfs-refresh"$' "$grub_btrfs_config"; then
  pass "GRUB snapshot refresh is driven by a Timeshift-aware path and wait-capable service"
else
  fail "GRUB snapshot refresh is driven by a Timeshift-aware path and wait-capable service"
fi

daily_timer="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/systemd/system/timeshift-daily.timer"
weekly_timer="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/systemd/system/timeshift-weekly.timer"
monthly_timer="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/systemd/system/timeshift-monthly.timer"
daily_service="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/systemd/system/timeshift-daily.service"
weekly_service="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/systemd/system/timeshift-weekly.service"
monthly_service="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/systemd/system/timeshift-monthly.service"
if grep -q '^OnCalendar=\*-\*-\* 00,03,06,09,12,15,18,21:00:00$' "$daily_timer" &&
   grep -q '^OnCalendar=Sun,Wed \*-\*-\* 03:00:00$' "$weekly_timer" &&
   grep -q '^OnCalendar=\*-\*-01 04:00:00$' "$monthly_timer" &&
   [ "$(grep -l '^TimeoutStartSec=6h$' "$daily_service" "$weekly_service" "$monthly_service" | wc -l)" -eq 3 ] &&
   [ "$(grep -l '^IOSchedulingPriority=7$' "$daily_service" "$weekly_service" "$monthly_service" | wc -l)" -eq 3 ] &&
   [ "$(grep -l '^UMask=0077$' "$daily_service" "$weekly_service" "$monthly_service" | wc -l)" -eq 3 ]; then
  pass "managed Timeshift timers and services encode bounded serialized snapshot scheduling"
else
  fail "managed Timeshift timers and services encode bounded serialized snapshot scheduling"
fi

btrfs_family="$ROOT_DIR/d-i/forky/scripts/late/btrfs-family.sh"
fstab_file="$TMP_DIR/fstab"
cat >"$fstab_file" <<'EOF'
# Installer-generated target filesystem policy.
UUID=boot /boot ext4 defaults 0 2
UUID=root / btrfs rw,relatime,ssd,subvolid=256,subvol=/@ 0 0
EOF
# shellcheck disable=SC1090
. "$btrfs_family"
if [ "$(btrfs_family_fstab_record_for_mount "$fstab_file" /)" = \
     "btrfs rw,relatime,ssd,subvolid=256,subvol=/@" ] &&
   ! btrfs_family_fstab_record_for_mount "$fstab_file" relative-target >/dev/null 2>&1 &&
   ! btrfs_family_fstab_record_for_mount "$TMP_DIR/missing-fstab" / >/dev/null 2>&1; then
  pass "Btrfs late hook validates the installed root fstab contract without findmnt"
else
  fail "Btrfs late hook validates the installed root fstab contract without findmnt"
fi

if grep -q 'configure_target_timeshift()' "$btrfs_family" &&
   grep -q 'configure_target_timeshift_btrfs_layout()' "$btrfs_family" &&
   grep -q 'btrfs_family_fstab_record_for_mount /target/etc/fstab /' "$btrfs_family" &&
   grep -q 'blkid -s TYPE -o value "$timeshift_root_device"' "$btrfs_family" &&
   ! grep -q 'findmnt .*--target /target' "$btrfs_family" &&
   grep -q 'btrfs subvolume set-default 5 /target' "$btrfs_family" &&
   grep -q 'TIMESHIFT_PARENT_DEVICE_UUID=' "$btrfs_family" &&
   grep -q 'load_target_btrfs_optional_package_state()' "$btrfs_family" &&
   grep -q 'TARGET_HAS_BTRFSMAINTENANCE_PACKAGE=0' "$btrfs_family" &&
   grep -q 'btrfs_stage_shared_target_asset()' "$btrfs_family" &&
   grep -q 'btrfs_stage_timeshift_managed_perl_modules' "$btrfs_family" &&
   grep -q 'usr/local/libexec/timeshift-managed-snapshot "${FILE_TIMESHIFT_SNAPSHOT_HELPER}" 0755' "$btrfs_family" &&
   grep -q 'usr/local/libexec/timeshift-managed/notify-send "${FILE_TIMESHIFT_NOTIFY_SHIM}" 0755' "$btrfs_family" &&
   grep -q 'backup-hooks.d/90-grub-btrfs-refresh "${FILE_TIMESHIFT_GRUB_REFRESH_HOOK}" 0755' "$btrfs_family" &&
   grep -q 'usr/local/libexec/grub-btrfs-refresh "${FILE_GRUB_BTRFS_REFRESH_HELPER}" 0755' "$btrfs_family" &&
   grep -q 'grub-btrfs-refresh.path' "$btrfs_family" &&
   grep -q 'stage_target_systemd_unit_enabled "$unit" system' "$btrfs_family" &&
   grep -q 'run_in_target "prime managed GRUB BTRFS snapshot menu" "${FILE_GRUB_BTRFS_REFRESH_HELPER}"' "$btrfs_family"; then
  pass "Btrfs late hook stages, enables, verifies, and primes the Timeshift snapshot integration"
else
  fail "Btrfs late hook stages, enables, verifies, and primes the Timeshift snapshot integration"
fi

[ "$FAIL_COUNT" -eq 0 ]
