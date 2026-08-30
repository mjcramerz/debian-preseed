#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
GREETER_SESSION="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-greeter-session.tmpl"
POWER_ACTION="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/sbin/greetd-power-action"
GREETD_VT_UNIT="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/systemd/system/greetd.service.d/20-labwc-vt.conf"
LOGIND_OVERRIDE="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/systemd/logind.conf.d/override.conf"
DESKTOP_COMPONENTS="$ROOT_DIR/d-i/forky/scripts/desktop/components.sh"
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/desktop-recovery-console.XXXXXX")
trap 'rm -rf -- "$TMP_DIR"' EXIT HUP INT TERM

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

if ! grep -Eq 'key="C-A-F[2-6]"|greetd-power-action tty[2-6]' "$GREETER_SESSION"; then
  pass "the greeter does not intercept Ctrl+Alt+F2 through Ctrl+Alt+F6"
else
  fail "the greeter does not intercept Ctrl+Alt+F2 through Ctrl+Alt+F6"
fi

if /bin/sh -n "$GREETER_SESSION" &&
   /bin/sh -n "$POWER_ACTION"; then
  pass "the greeter session and power helper remain valid POSIX shell"
else
  fail "the greeter session and power helper remain valid POSIX shell"
fi

invalid_action_output="$TMP_DIR/invalid-action.out"
if /bin/sh "$POWER_ACTION" tty2 >"$invalid_action_output" 2>&1; then
  invalid_action_status=0
else
  invalid_action_status=$?
fi
if [ "$invalid_action_status" -eq 64 ] &&
   grep -Fxq 'usage: greetd-power-action {poweroff|reboot}' "$invalid_action_output" &&
   ! grep -Eq 'SwitchTo|tty[2-6]' "$POWER_ACTION"; then
  pass "the greeter helper retains only explicit power actions"
else
  fail "the greeter helper retains only explicit power actions"
fi

if grep -Fxq 'Conflicts=getty@tty1.service' "$GREETD_VT_UNIT" &&
   ! grep -Eq 'getty@tty[2-6]' "$GREETD_VT_UNIT" &&
   grep -Fq 'etc/systemd/system/greetd.service.d/20-labwc-vt.conf' "$DESKTOP_COMPONENTS"; then
  pass "greetd is staged as the tty1 owner only"
else
  fail "greetd is staged as the tty1 owner only"
fi

if grep -Fxq 'SyslogIdentifier=greetd-labwc' "$GREETD_VT_UNIT" &&
   grep -Fxq 'StandardOutput=journal' "$GREETD_VT_UNIT" &&
   grep -Fxq 'StandardError=journal' "$GREETD_VT_UNIT" &&
   ! grep -Fq 'journal+console' "$GREETD_VT_UNIT"; then
  pass "greetd and Labwc diagnostics stay in the journal instead of tty1"
else
  fail "greetd and Labwc diagnostics stay in the journal instead of tty1"
fi

if ! rg -n -- \
  'getty@tty[2-6]|autovt@tty[2-6]|systemd\.getty_auto' \
  "$ROOT_DIR/d-i/forky" >/dev/null &&
   grep -Fxq 'NAutoVTs=6' "$LOGIND_OVERRIDE" &&
   grep -Fxq 'ReserveVT=6' "$LOGIND_OVERRIDE"; then
  pass "logind provides tty2 through tty6 without per-VT unit or kernel overrides"
else
  fail "logind provides tty2 through tty6 without per-VT unit or kernel overrides"
fi

[ "$FAIL_COUNT" -eq 0 ]
