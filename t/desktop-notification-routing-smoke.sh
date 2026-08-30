#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
HEALTH_NOTIFIER="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-health-notify"
ROOT_NOTIFIER="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/sbin/labwc-notify"
MANAGED_APP="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-managed-app"
MANAGED_APP_PROFILES="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/lib/python3.14/dist-packages/labwc_managed_app/profiles.py"
MANAGED_APP_SANDBOX="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/lib/python3.14/dist-packages/labwc_managed_app/sandbox.py"
NOTIFICATION_SERVICE_UNIT="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/systemd/user/labwc-health-notify.service"
NOTIFICATION_PATH_UNIT="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/systemd/user/labwc-health-notify.path"
AUTOSTART="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-autostart"
MAKO_CONFIG="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/mako/config"
TMPFILES_CONFIG="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/tmpfiles.d/60-security-logs.conf"
APPARMOR_PROFILE="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/managed-desktop-wrappers"
DBUS_BROKER_SCRIPT="$ROOT_DIR/d-i/forky/scripts/late/dbus-broker.sh"
DESKTOP_COMPONENTS="$ROOT_DIR/d-i/forky/scripts/desktop/components.sh"
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/desktop-notification-routing.XXXXXX")
trap 'rm -rf -- "$TMP_DIR"' EXIT HUP INT TERM
RUNTIME_DIR="$TMP_DIR/runtime"
WAYLAND_DISPLAY_NAME=wayland-0
WAYLAND_SOCKET="$RUNTIME_DIR/$WAYLAND_DISPLAY_NAME"

TEST_COUNT=6
TEST_INDEX=0
FAIL_COUNT=0

install -d -m 0700 "$RUNTIME_DIR"
python3 - "$WAYLAND_SOCKET" <<'PY'
import socket
import sys

wayland_socket = socket.socket(socket.AF_UNIX)
wayland_socket.bind(sys.argv[1])
wayland_socket.close()
PY

pass() {
  TEST_INDEX=$((TEST_INDEX + 1))
  printf 'ok %s - %s\n' "$TEST_INDEX" "$1"
}

fail() {
  TEST_INDEX=$((TEST_INDEX + 1))
  FAIL_COUNT=$((FAIL_COUNT + 1))
  printf 'not ok %s - %s\n' "$TEST_INDEX" "$1"
}

run_notifier() {
  NOTIFY_LOG="$notify_log" \
  NOTIFY_SEND="$notify_send" \
  MAIL="$TMP_DIR/missing-mailbox" \
  HOME="$TMP_DIR/home" \
  XDG_STATE_HOME="$TMP_DIR/state" \
  SYSTEM_EVENT_DIR="$system_event_dir" \
  SYSTEM_SEEN_DIR="$system_seen_dir" \
  SYSTEM_EVENT_OWNER_UID="$test_uid" \
  TIMESHIFT_EVENT_DIR="$TMP_DIR/missing-timeshift" \
  UNATTENDED_EVENT_DIR="$TMP_DIR/missing-unattended" \
  SECURITY_SIGNAL_DIR="$TMP_DIR/missing-security" \
  MEMINFO_FILE="$TMP_DIR/missing-meminfo" \
  POWER_SUPPLY_DIR="$TMP_DIR/missing-power-supply" \
  REBOOT_REQUIRED_FILE="$TMP_DIR/missing-reboot-required" \
  LABWC_SESSION_OWNER=desktop \
  XDG_SESSION_TYPE=wayland \
  XDG_RUNTIME_DIR="$RUNTIME_DIR" \
  WAYLAND_DISPLAY="$WAYLAND_DISPLAY_NAME" \
  DBUS_SESSION_BUS_ADDRESS="unix:path=$TMP_DIR/fake-bus" \
    /bin/sh "$HEALTH_NOTIFIER"
}

printf '1..%s\n' "$TEST_COUNT"

tuta_dbus_names=$(sed -n '/^TUTA_DBUS_NAMES = (/,/^)/p' "$MANAGED_APP_PROFILES")
if grep -Fq '"fr.emersion.mako.service:org.freedesktop.Notifications"' "$DBUS_BROKER_SCRIPT" &&
   grep -Fq 'NOTIFICATIONS_DBUS_NAME = "org.freedesktop.Notifications"' "$MANAGED_APP_PROFILES" &&
   grep -Fq 'f"--talk={NOTIFICATIONS_DBUS_NAME}"' "$MANAGED_APP_SANDBOX" &&
   ! printf '%s\n' "$tuta_dbus_names" | grep -Fq 'org.freedesktop.Notifications' &&
   grep -Fxq 'PathChanged=/var/lib/labwc-notifications/system' "$NOTIFICATION_PATH_UNIT" &&
   grep -Fxq 'StartLimitIntervalSec=10s' "$NOTIFICATION_SERVICE_UNIT" &&
   grep -Fxq 'StartLimitBurst=5' "$NOTIFICATION_SERVICE_UNIT" &&
   grep -Fxq 'Requisite=labwc-session.target' "$NOTIFICATION_SERVICE_UNIT" &&
   grep -Fxq 'PartOf=labwc-session.target' "$NOTIFICATION_SERVICE_UNIT" &&
   ! grep -Fq 'ExecStartPre=' "$NOTIFICATION_SERVICE_UNIT" &&
   ! grep -Fq 'ExecCondition=' "$NOTIFICATION_SERVICE_UNIT" &&
   grep -Fxq 'ExecStart=/usr/local/bin/labwc-health-notify --coalesce-seconds 10' "$NOTIFICATION_SERVICE_UNIT" &&
   grep -Fxq 'TimeoutStartSec=30s' "$NOTIFICATION_SERVICE_UNIT" &&
   grep -Fxq 'TimeoutStopSec=5s' "$NOTIFICATION_SERVICE_UNIT" &&
   grep -Fqx 'trap cancel_coalescing HUP INT TERM' "$HEALTH_NOTIFIER" &&
   grep -Fqx '[ -S "$wayland_socket" ] || exit 0' "$HEALTH_NOTIFIER" &&
   ! grep -Fq 'labwc-session-child' "$NOTIFICATION_SERVICE_UNIT" "$DESKTOP_COMPONENTS" &&
   [ ! -e "$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/libexec/labwc-session-child" ] &&
   grep -Fq 'start labwc-health-notify.path' "$AUTOSTART" &&
   grep -Fq 'start labwc-health-notify.timer' "$AUTOSTART" &&
   ! grep -Fq 'start labwc-health-notify.service' "$AUTOSTART" &&
   grep -Fxq 'd /var/lib/labwc-notifications/system 2750 root logreader -' "$TMPFILES_CONFIG" &&
   grep -Fxq '  /usr/local/sbin/labwc-notify rix,' "$APPARMOR_PROFILE" &&
   grep -Fq 'usr/local/sbin/labwc-notify /usr/local/sbin/labwc-notify 0755' "$DESKTOP_COMPONENTS" &&
   grep -Fxq '[app-name="System Maintenance" category=x-labwc.maintenance]' "$MAKO_CONFIG"; then
  pass "Mako activation, filtered sandbox notifications, and privileged queue wiring are staged"
else
  fail "Mako activation, filtered sandbox notifications, and privileged queue wiring are staged"
fi

if /bin/sh -n "$HEALTH_NOTIFIER" &&
   /bin/sh -n "$ROOT_NOTIFIER" &&
   PYTHONPYCACHEPREFIX="$TMP_DIR/pycache" python3 -m py_compile "$MANAGED_APP"; then
  pass "notification routing helpers parse successfully"
else
  fail "notification routing helpers parse successfully"
fi

cancel_stdout="$TMP_DIR/cancel.stdout"
cancel_stderr="$TMP_DIR/cancel.stderr"
cancel_ok=true
HOME="$TMP_DIR/home" \
XDG_STATE_HOME="$TMP_DIR/state" \
NOTIFY_SEND=/bin/true \
LABWC_SESSION_OWNER=desktop \
XDG_SESSION_TYPE=wayland \
XDG_RUNTIME_DIR="$RUNTIME_DIR" \
WAYLAND_DISPLAY="$WAYLAND_DISPLAY_NAME" \
DBUS_SESSION_BUS_ADDRESS="unix:path=$TMP_DIR/fake-bus" \
  /bin/sh "$HEALTH_NOTIFIER" --coalesce-seconds 60 >"$cancel_stdout" 2>"$cancel_stderr" &
notifier_pid=$!
/usr/bin/sleep 0.1
if ! kill -TERM "$notifier_pid" ||
   ! wait "$notifier_pid" ||
   [ -s "$cancel_stdout" ] ||
   [ -s "$cancel_stderr" ]; then
  cancel_ok=false
fi

child_notifier="$TMP_DIR/labwc-health-notify-child-first"
fake_sleep="$TMP_DIR/coalesce-sleep"
sleep_pid_file="$TMP_DIR/coalesce-sleep.pid"
sed "s#/usr/bin/sleep#${fake_sleep}#g" "$HEALTH_NOTIFIER" >"$child_notifier"
chmod 0755 "$child_notifier"
cat >"$fake_sleep" <<'EOF'
#!/bin/sh
set -eu
printf '%s\n' "$$" >"$SLEEP_PID_FILE"
trap 'exit 143' TERM
while :; do
  :
done
EOF
chmod 0755 "$fake_sleep"

: >"$cancel_stdout"
: >"$cancel_stderr"
HOME="$TMP_DIR/home" \
XDG_STATE_HOME="$TMP_DIR/state" \
SLEEP_PID_FILE="$sleep_pid_file" \
NOTIFY_SEND=/bin/true \
LABWC_SESSION_OWNER=desktop \
XDG_SESSION_TYPE=wayland \
XDG_RUNTIME_DIR="$RUNTIME_DIR" \
WAYLAND_DISPLAY="$WAYLAND_DISPLAY_NAME" \
DBUS_SESSION_BUS_ADDRESS="unix:path=$TMP_DIR/fake-bus" \
  /bin/sh "$child_notifier" --coalesce-seconds 60 >"$cancel_stdout" 2>"$cancel_stderr" &
notifier_pid=$!
wait_attempt=1
while [ ! -s "$sleep_pid_file" ] && [ "$wait_attempt" -le 50 ]; do
  /usr/bin/sleep 0.02
  wait_attempt=$((wait_attempt + 1))
done
sleep_pid=$(cat "$sleep_pid_file" 2>/dev/null || true)
case "$sleep_pid" in
  ''|*[!0-9]*) cancel_ok=false ;;
  *)
    if ! kill -TERM "$sleep_pid" ||
       ! wait "$notifier_pid" ||
       [ -s "$cancel_stdout" ] ||
       [ -s "$cancel_stderr" ]; then
      cancel_ok=false
    fi
    ;;
esac

if [ "$cancel_ok" = true ]; then
  pass "session teardown cancels notifier coalescing cleanly for parent-first and child-first signals"
else
  fail "session teardown cancels notifier coalescing cleanly for parent-first and child-first signals"
fi

notify_log="$TMP_DIR/notify.log"
notify_send="$TMP_DIR/notify-send"
system_event_dir="$TMP_DIR/system"
system_seen_dir="$TMP_DIR/system-seen"
test_uid=$(id -u)
mkdir -p "$TMP_DIR/home" "$TMP_DIR/state" "$system_event_dir"
chmod 0755 "$system_event_dir"
cat >"$notify_send" <<'EOF'
#!/bin/sh
set -eu
separator_seen=false
for argument in "$@"; do
  [ "$argument" = -- ] || continue
  separator_seen=true
  break
done
[ "$separator_seen" = true ] || exit 64
printf '%s\n' "$*" >>"$NOTIFY_LOG"
EOF
chmod 0755 "$notify_send"

trusted_event="$system_event_dir/0000000001-0000000001-0001.event"
printf '%s\n' \
  'System Maintenance|critical|dialog-error|x-labwc.maintenance|0|Maintenance failed|A privileged maintenance job failed.' \
  >"$trusted_event"
chmod 0640 "$trusted_event"

run_notifier
run_notifier
if [ "$(grep -Fc 'Maintenance failed' "$notify_log" || true)" -eq 1 ] &&
   [ -f "$system_seen_dir/0000000001-0000000001-0001.event.seen" ]; then
  pass "trusted privileged events reach notify-send once and receive a seen marker"
else
  fail "trusted privileged events reach notify-send once and receive a seen marker"
fi

unsafe_event="$system_event_dir/0000000001-0000000001-0002.event"
printf '%s\n' \
  'System Maintenance|critical|dialog-error|x-labwc.maintenance|0|Unsafe event|This file is writable.' \
  >"$unsafe_event"
chmod 0666 "$unsafe_event"

malformed_event="$system_event_dir/0000000001-0000000001-0003.event"
printf '%s\n' \
  'System Maintenance|critical|dialog-error|x-labwc.maintenance|0|Malformed event|This body has an extra|separator.' \
  >"$malformed_event"
chmod 0640 "$malformed_event"

run_notifier
if [ "$(grep -Fc 'Unsafe event' "$notify_log" || true)" -eq 0 ] &&
   [ ! -e "$system_seen_dir/0000000001-0000000001-0002.event.seen" ] &&
   [ "$(grep -Fc 'Malformed event' "$notify_log" || true)" -eq 0 ] &&
   [ ! -e "$system_seen_dir/0000000001-0000000001-0003.event.seen" ]; then
  pass "writable and malformed privileged event files are rejected before desktop delivery"
else
  fail "writable and malformed privileged event files are rejected before desktop delivery"
fi

root_event_dir_literal="EVENT_DIR=\"\${EVENT_ROOT}/system\""
if grep -Fxq "$root_event_dir_literal" "$ROOT_NOTIFIER" &&
   grep -Fq 'labwc-notify requires root privileges' "$ROOT_NOTIFIER" &&
   ! grep -Fq 'DBUS_SESSION_BUS_ADDRESS' "$ROOT_NOTIFIER" &&
   grep -Fq 'validate_queue ||' "$ROOT_NOTIFIER"; then
  pass "root and sudo producers use the durable queue instead of the desktop bus"
else
  fail "root and sudo producers use the durable queue instead of the desktop bus"
fi

[ "$FAIL_COUNT" -eq 0 ]
