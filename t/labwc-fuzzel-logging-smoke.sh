#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT HUP INT TERM

route="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/rsyslog.d/41-fuzzel.conf"
rotation="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/logrotate.d/fuzzel"
tmpfiles="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/tmpfiles.d/60-security-logs.conf"
components="$ROOT_DIR/d-i/forky/scripts/desktop/components.sh"
computer_management="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-computer-management"
adb_menu="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-adb-menu"
fuzzel_wrapper="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-fuzzel"
writer="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-fuzzel-log"

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

if [ -x "$writer" ] &&
   grep -Fq 'file="/var/log/managed/fuzzel/menu.log"' "$route" &&
   grep -Fq 'file="/var/log/managed/fuzzel/actions.log"' "$route" &&
   grep -Fqx '/var/log/managed/fuzzel/menu.log' "$rotation" &&
   grep -Fqx '/var/log/managed/fuzzel/actions.log' "$rotation" &&
   grep -Fqx 'd /var/log/managed/fuzzel 0750 root adm -' "$tmpfiles" &&
   grep -Fqx 'f /var/log/managed/fuzzel/menu.log 0640 root adm -' "$tmpfiles" &&
   grep -Fqx 'f /var/log/managed/fuzzel/actions.log 0640 root adm -' "$tmpfiles"; then
  pass "Fuzzel log destinations are protected and routed by rsyslog"
else
  fail "Fuzzel log destinations are protected and routed by rsyslog"
fi

if grep -Fq 'etc/rsyslog.d/41-fuzzel.conf' "$components" &&
   grep -Fq 'etc/logrotate.d/fuzzel' "$components" &&
   grep -Fq 'usr/local/bin/labwc-fuzzel-log' "$components" &&
   grep -Fq 'fuzzel_menu=/var/log/managed/fuzzel/menu.log' "$components"; then
  pass "desktop staging installs the Fuzzel log writer and retention policy"
else
  fail "desktop staging installs the Fuzzel log writer and retention policy"
fi

# The quoted snippets below intentionally match literal shell source.
# shellcheck disable=SC2016
if grep -Fqx 'LABWC_FUZZEL_LOG_SCOPE=computer-management' "$computer_management" &&
   grep -Fq 'log_computer_management_action "$command_name" 0' "$computer_management" &&
   grep -Fq 'log_computer_management_action "$command_name" "$command_status"' "$computer_management" &&
   grep -Fqx 'LABWC_FUZZEL_LOG_SCOPE=android-debug-bridge' "$adb_menu" &&
   grep -Fq 'log_adb_action "$1" "$action_status"' "$adb_menu" &&
   grep -Fq 'fatal_log_scope=${managed_log_scope:-${LABWC_FUZZEL_LOG_SCOPE:-}}' "$fuzzel_wrapper" &&
   grep -Fq '"source=${fatal_log_scope}"' "$fuzzel_wrapper" &&
   grep -Fq '"source=$managed_log_scope"' "$fuzzel_wrapper" &&
   grep -Fq "selection_value=\${selection_value#' '}" "$fuzzel_wrapper" &&
   grep -Fq 'log_managed_menu_selection listed "$raw_selection"' "$fuzzel_wrapper" &&
   grep -Fq 'log_managed_menu_selection custom-input redacted' "$fuzzel_wrapper"; then
  pass "Computer Management and ADB emit bounded menu and action events"
else
  fail "Computer Management and ADB emit bounded menu and action events"
fi

mock_lib="$TMP_DIR/lib"
mkdir -p "$mock_lib/Sys"
cat >"$mock_lib/Sys/Syslog.pm" <<'EOF'
package Sys::Syslog;
use strict;
use warnings;
use Exporter qw(import);
our @EXPORT_OK = qw(openlog syslog closelog LOG_INFO LOG_USER);
our %EXPORT_TAGS = (standard => \@EXPORT_OK, macros => \@EXPORT_OK);
sub LOG_INFO () { 6 }
sub LOG_USER () { 8 }
sub _append {
    open my $handle, '>>', $ENV{FUZZEL_LOG_CAPTURE}
        or die "open capture: $!\n";
    print {$handle} $_[0], "\n"
        or die "write capture: $!\n";
    close $handle
        or die "close capture: $!\n";
    return 1;
}
sub openlog { return _append("openlog $_[0]"); }
sub syslog { return _append("syslog $_[2]"); }
sub closelog { return 1; }
1;
EOF
capture="$TMP_DIR/capture.log"
if PERL5LIB="$mock_lib" \
   FUZZEL_LOG_CAPTURE="$capture" \
   "$writer" \
     menu \
     selected \
     'selection=Hardware & Peripherals' \
     "$(printf 'custom=unsafe\nrecord')" &&
   grep -Fqx 'openlog labwc-fuzzel-menu' "$capture" &&
   grep -Fqx 'syslog event=selected selection=Hardware_&_Peripherals custom=unsafe_record' "$capture"; then
  pass "Fuzzel log writer bounds and normalizes user-originated fields"
else
  fail "Fuzzel log writer bounds and normalizes user-originated fields"
fi

[ "$FAIL_COUNT" -eq 0 ]
