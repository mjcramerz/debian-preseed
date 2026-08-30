#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)

route="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/rsyslog.d/36-zram.conf"
logrotate_policy="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/logrotate.d/zram"
tmpfiles_policy="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/tmpfiles.d/60-zram-writeback.conf"
runtime_env="$ROOT_DIR/d-i/forky/hosts/shared/runtime.env"
zram_script="$ROOT_DIR/d-i/forky/scripts/late/zram-swap.sh"

TEST_COUNT=5
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

printf '1..%s\n' "$TEST_COUNT"

if grep -Fq '$programname == "zram-writeback"' "$route" &&
   grep -Fq '$programname == "zram-device-setup"' "$route" &&
   grep -Fq 'file="/var/log/managed/zram/zram.log"' "$route" &&
   grep -Fq 'set $.managed_security_routed = "on";' "$route" &&
   ! grep -Fq 'zram-writeback.log' "$route"; then
  pass "both managed zram identifiers route into the single zram.log destination"
else
  fail "both managed zram identifiers route into the single zram.log destination"
fi

if grep -Fxq 'd /var/log/managed/zram 0750 root adm -' "$tmpfiles_policy" &&
   grep -Fxq 'f /var/log/managed/zram/zram.log 0640 root adm -' "$tmpfiles_policy" &&
   grep -Fxq 'd /run/zram 0750 root root -' "$tmpfiles_policy" &&
   grep -Fxq 'd /var/lib/zram-writeback 0700 root root -' "$tmpfiles_policy"; then
  pass "tmpfiles pre-creates protected zram runtime, state, and log paths"
else
  fail "tmpfiles pre-creates protected zram runtime, state, and log paths"
fi

if grep -Fxq '/var/log/managed/zram/zram.log' "$logrotate_policy" &&
   grep -Eq '^[[:space:]]*daily$' "$logrotate_policy" &&
   grep -Eq '^[[:space:]]*rotate 4$' "$logrotate_policy" &&
   grep -Eq '^[[:space:]]*maxage 7$' "$logrotate_policy" &&
   grep -Eq '^[[:space:]]*maxsize 8M$' "$logrotate_policy" &&
   grep -Eq '^[[:space:]]*create 0640 root adm$' "$logrotate_policy" &&
   grep -Fq '/usr/lib/rsyslog/rsyslog-rotate' "$logrotate_policy" &&
   ! grep -Fq 'zram-writeback.log' "$logrotate_policy"; then
  pass "zram.log has bounded rsyslog-aware rotation"
else
  fail "zram.log has bounded rsyslog-aware rotation"
fi

verify_line=$(grep -n '^verify_target_zram_staging() {$' "$zram_script" | cut -d: -f1)
call_line=$(grep -n '^[[:space:]]*verify_target_zram_staging$' "$zram_script" | cut -d: -f1)
if grep -Fxq 'FILE_ZRAM_LOGROTATE="/etc/logrotate.d/zram"' "$runtime_env" &&
   grep -q 'etc/logrotate.d/zram' "$zram_script" &&
   grep -q 'normalize_target_tmpfiles_directory_policy' "$zram_script" &&
   grep -q '/usr/bin/systemd-tmpfiles' "$zram_script" &&
   grep -q '/usr/sbin/rsyslogd' "$zram_script" &&
   grep -q -- '-N1' "$zram_script" &&
   grep -q '/usr/sbin/logrotate' "$zram_script" &&
   grep -q -- '--debug' "$zram_script" &&
   [ -n "$verify_line" ] &&
   [ -n "$call_line" ] &&
   [ "$call_line" -lt "$verify_line" ]; then
  pass "installer staging creates and validates the zram logging policy"
else
  fail "installer staging creates and validates the zram logging policy"
fi

if ! grep -R -F -n 'zram-writeback.log' "$ROOT_DIR/d-i/forky" >/dev/null 2>&1 &&
   [ ! -e "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/logrotate.d/zram-writeback" ]; then
  pass "authoritative installer sources no longer reference the obsolete zram-writeback.log"
else
  fail "authoritative installer sources no longer reference the obsolete zram-writeback.log"
fi
