#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT HUP INT TERM

if [ ! -x /usr/sbin/logrotate ]; then
  printf '1..0 # SKIP logrotate is not installed\n'
  exit 0
fi

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

test_user=$(id -un)
test_group=$(id -gn)
test_conf_dir="$TMP_DIR/etc/logrotate.d"
test_root="$TMP_DIR/root"
test_state="$TMP_DIR/logrotate.state"
mkdir -p "$test_conf_dir" "$test_root/var/log" "$test_root/var/lib/labwc-notifications/security"

for policy in "$ROOT_DIR"/d-i/forky/hooks/shared/target/etc/logrotate.d/*; do
  sed \
    -e "s/^[[:space:]]*su root adm$/\tsu ${test_user} ${test_group}/" \
    -e "s/^[[:space:]]*su root logreader$/\tsu ${test_user} ${test_group}/" \
    -e "s/^[[:space:]]*create 0640 root adm$/\tcreate 0640 ${test_user} ${test_group}/" \
    -e "s/^[[:space:]]*create 0640 root logreader$/\tcreate 0640 ${test_user} ${test_group}/" \
    -e 's|/usr/lib/rsyslog/rsyslog-rotate|/bin/true|' \
    -e 's|/usr/bin/fail2ban-client flushlogs.*|/bin/true|' \
    -e "s|/var/log|${test_root}/var/log|g" \
    -e "s|/var/lib/labwc-notifications|${test_root}/var/lib/labwc-notifications|g" \
    "$policy" >"$test_conf_dir/${policy##*/}"
done

sed \
  "s|^include /etc/logrotate.d$|include ${test_conf_dir}|" \
  "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/logrotate.conf" \
  >"$TMP_DIR/etc/logrotate.conf"

log_paths='
var/log/syslog
var/log/mail.log
var/log/kern.log
var/log/user.log
var/log/cron.log
var/log/daemon.log
var/log/messages
var/log/managed/audit/kernel-audit.log
var/log/managed/auth/auth.log
var/log/managed/hardware/usb.log
var/log/managed/apparmor/apparmor.log
var/log/managed/storage/storage.log
var/log/managed/zram/zram.log
var/log/managed/nftables/firewall.log
var/log/managed/fuzzel/menu.log
var/log/managed/fuzzel/actions.log
var/log/managed/fail2ban/fail2ban.log
var/log/managed/lynis/scan.log
var/log/managed/lynis/lynis.log
var/log/managed/lynis/lynis-report.dat
var/log/managed/rkhunter/scan.log
var/log/managed/rkhunter/rkhunter.log
var/log/managed/chkrootkit/scan.log
var/log/managed/debsecan/scan.log
var/log/managed/debsums/scan.log
var/log/managed/spectre-meltdown-checker/scan.log
var/log/managed/fwupd/security-scan.log
var/log/managed/clamav/scan.log
var/lib/labwc-notifications/security/auth.signal
var/lib/labwc-notifications/security/usb.signal
var/lib/labwc-notifications/security/storage.signal
'

for relative_path in $log_paths; do
  mkdir -p "$test_root/${relative_path%/*}"
  printf 'first rotation payload for %s\n' "$relative_path" >"$test_root/$relative_path"
done

if /usr/sbin/logrotate \
  --debug \
  --state "$test_state" \
  "$TMP_DIR/etc/logrotate.conf" \
  >"$TMP_DIR/debug.out" 2>&1; then
  pass "managed logrotate configuration passes the native parser"
else
  cat "$TMP_DIR/debug.out"
  fail "managed logrotate configuration passes the native parser"
fi

if /usr/sbin/logrotate \
  --force \
  --state "$test_state" \
  "$TMP_DIR/etc/logrotate.conf"; then
  first_archive_count=$(
    find "$test_root/var" -type f |
      grep -Ec -- '-[0-9]{8}-[0-9]{6}$' || true
  )
  active_mode_ok=true
  for relative_path in $log_paths; do
    [ "$(stat -c %a "$test_root/$relative_path")" = 640 ] ||
      active_mode_ok=false
  done
  if [ "$first_archive_count" -eq 31 ] &&
     [ "$active_mode_ok" = true ]; then
    pass "first rotation creates unique timestamped archives and reopens 0640 active files"
  else
    fail "first rotation creates unique timestamped archives and reopens 0640 active files"
  fi
else
  fail "first rotation creates unique timestamped archives and reopens 0640 active files"
fi

sleep 1
for relative_path in $log_paths; do
  printf 'second rotation payload for %s\n' "$relative_path" >>"$test_root/$relative_path"
done

if /usr/sbin/logrotate \
  --force \
  --state "$test_state" \
  "$TMP_DIR/etc/logrotate.conf"; then
  newest_archive_count=$(
    find "$test_root/var" -type f |
      grep -Ec -- '-[0-9]{8}-[0-9]{6}$' || true
  )
  compressed_archive_count=$(
    find "$test_root/var" -type f |
      grep -Ec -- '-[0-9]{8}-[0-9]{6}\.gz$' || true
  )
  if [ "$newest_archive_count" -eq 31 ] &&
     [ "$compressed_archive_count" -eq 31 ]; then
    pass "second rotation compresses the older generation and keeps the newest archive readable"
  else
    fail "second rotation compresses the older generation and keeps the newest archive readable"
  fi
else
  fail "second rotation compresses the older generation and keeps the newest archive readable"
fi

if find "$test_root/var" -type f |
   grep -Eq -- '-[0-9]{8}-[0-9]{6}(\.gz)?$' &&
   [ "$(find "$test_root/var" -type f | wc -l)" -eq 93 ]; then
  pass "two rotation cycles retain active, newest, and compressed prior generations without collisions"
else
  fail "two rotation cycles retain active, newest, and compressed prior generations without collisions"
fi

[ "$FAIL_COUNT" -eq 0 ]
