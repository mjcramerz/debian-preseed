#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
SCRIPT="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-greeter-output"
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/labwc-greeter-output.XXXXXX")
WATCHER_PID=
MONITOR_PID=

cleanup() {
  [ -z "$WATCHER_PID" ] || kill "$WATCHER_PID" >/dev/null 2>&1 || true
  [ -z "$MONITOR_PID" ] || kill "$MONITOR_PID" >/dev/null 2>&1 || true
  [ -z "$WATCHER_PID" ] || wait "$WATCHER_PID" 2>/dev/null || true
  [ -z "$MONITOR_PID" ] || wait "$MONITOR_PID" 2>/dev/null || true
  rm -rf -- "$TMP_DIR"
}
trap cleanup EXIT HUP INT TERM

mkdir -p "$TMP_DIR/bin" "$TMP_DIR/state"

cat >"$TMP_DIR/bin/wlr-randr" <<'EOF'
#!/bin/sh
set -eu
if [ "$#" -eq 0 ]; then
  cat "$WLR_RANDR_STATE"
  exit 0
fi
printf '%s\n' "$*" >>"$WLR_RANDR_LOG"
if [ "${WLR_RANDR_FAIL_OFF:-0}" = 1 ] && [ "${3:-}" = "--off" ]; then
  exit 1
fi
if [ "${WLR_RANDR_FAIL_MODE:-0}" = 1 ]; then
  case " $* " in
    *" --mode "*) exit 1 ;;
  esac
fi
EOF
chmod 0755 "$TMP_DIR/bin/wlr-randr"

run_case() {
  state_file=$1
  log_file=$2

  PATH="$TMP_DIR/bin:/usr/bin:/bin" \
  XDG_STATE_HOME="$TMP_DIR/state" \
  WLR_RANDR_STATE="$state_file" \
  WLR_RANDR_LOG="$log_file" \
  LABWC_OUTPUT_INTERNAL_PREFIXES="eDP LVDS DSI" \
  LABWC_OUTPUT_EXTERNAL_PREFERRED_WIDTH="1920" \
  LABWC_OUTPUT_EXTERNAL_PREFERRED_HEIGHT="1080" \
  LABWC_OUTPUT_EXTERNAL_PREFERRED_REFRESH_HZ="120" \
  LABWC_GREETER_INTERNAL_SCALE="1" \
  LABWC_GREETER_EXTERNAL_SCALE="1" \
    perl "$SCRIPT" --configure
}

external_state="$TMP_DIR/external.state"
external_log="$TMP_DIR/external.log"
cat >"$external_state" <<'EOF'
eDP-1 "Internal panel"
  1920x1080 px, 60.000000 Hz (current, preferred)
DP-1 "DisplayPort monitor"
  2560x1440 px, 60.000000 Hz (current, preferred)
HDMI-A-1 "External monitor"
  1920x1080 px, 120.000000 Hz (current, preferred)
EOF

if [ "$(run_case "$external_state" "$external_log")" = external ] &&
   grep -q '^--output HDMI-A-1 --on --mode 1920x1080@120.000000Hz --scale 1 --pos 0,0$' "$external_log" &&
   grep -q '^--output eDP-1 --off$' "$external_log" &&
   grep -q '^--output DP-1 --off$' "$external_log"; then
  printf 'ok 1 - HDMI uses the fixed external greeter mode at scale 1\n'
else
  printf 'not ok 1 - HDMI uses the fixed external greeter mode at scale 1\n'
  exit 1
fi

internal_state="$TMP_DIR/internal.state"
internal_log="$TMP_DIR/internal.log"
cat >"$internal_state" <<'EOF'
eDP-1 "Internal panel"
  1920x1080 px, 60.000000 Hz (current, preferred)
EOF

if [ "$(run_case "$internal_state" "$internal_log")" = internal ] &&
   grep -q '^--output eDP-1 --on --scale 1 --pos 0,0$' "$internal_log" &&
   ! grep -q -- '--off' "$internal_log"; then
  printf 'ok 2 - internal output remains available when no external monitor exists\n'
else
  printf 'not ok 2 - internal output remains available when no external monitor exists\n'
  exit 1
fi

displayport_state="$TMP_DIR/displayport.state"
displayport_log="$TMP_DIR/displayport.log"
cat >"$displayport_state" <<'EOF'
eDP-1 "Internal panel"
  1920x1080 px, 60.000000 Hz (current, preferred)
DP-1 "DisplayPort monitor"
  1920x1080 px, 60.000000 Hz
  2560x1440 px, 60.000000 Hz (current, preferred)
EOF

if [ "$(run_case "$displayport_state" "$displayport_log")" = external ] &&
   grep -q '^--output DP-1 --on --mode 1920x1080@60.000000Hz --scale 1 --pos 0,0$' "$displayport_log" &&
   grep -q '^--output eDP-1 --off$' "$displayport_log"; then
  printf 'ok 3 - DisplayPort falls back to the available fixed external refresh\n'
else
  printf 'not ok 3 - DisplayPort falls back to the available fixed external refresh\n'
  exit 1
fi

invalid_state="$TMP_DIR/invalid.state"
invalid_log="$TMP_DIR/invalid.log"
cat >"$invalid_state" <<'EOF'
HDMI-A-1;touch-/tmp/unsafe "Invalid monitor"
  1920x1080 px, 60.000000 Hz (current, preferred)
EOF

if ! run_case "$invalid_state" "$invalid_log" >/dev/null 2>&1; then
  printf 'ok 4 - unsafe output names fail closed\n'
else
  printf 'not ok 4 - unsafe output names fail closed\n'
  exit 1
fi

failed_disable_log="$TMP_DIR/failed-disable.log"
if ! WLR_RANDR_FAIL_OFF=1 run_case "$external_state" "$failed_disable_log" >/dev/null 2>&1; then
  printf 'ok 5 - failure to disable a non-selected output fails closed\n'
else
  printf 'not ok 5 - failure to disable a non-selected output fails closed\n'
  exit 1
fi

mode_fallback_log="$TMP_DIR/mode-fallback.log"
if [ "$(WLR_RANDR_FAIL_MODE=1 run_case "$external_state" "$mode_fallback_log")" = external ] &&
   grep -q '^--output HDMI-A-1 --on --mode 1920x1080@120.000000Hz --scale 1 --pos 0,0$' "$mode_fallback_log" &&
   grep -q '^--output HDMI-A-1 --on --scale 1 --pos 0,0$' "$mode_fallback_log"; then
  printf 'ok 6 - unsupported fixed modes retry with the connector preferred mode\n'
else
  printf 'not ok 6 - unsupported fixed modes retry with the connector preferred mode\n'
  exit 1
fi

monitor_pid_file="$TMP_DIR/monitor.pid"
monitor_term_file="$TMP_DIR/monitor.term"
cat >"$TMP_DIR/bin/udevadm" <<'EOF'
#!/bin/sh
set -eu
[ "${1:-}" = monitor ] || exit 2
printf '%s\n' "$$" >"${MONITOR_PID_FILE:?}"
trap 'printf "term\n" >"${MONITOR_TERM_FILE:?}"; exit 0' HUP INT TERM
while :; do
  sleep 1
done
EOF
chmod 0755 "$TMP_DIR/bin/udevadm"

PATH="$TMP_DIR/bin:/usr/bin:/bin" \
XDG_STATE_HOME="$TMP_DIR/state" \
MONITOR_PID_FILE="$monitor_pid_file" \
MONITOR_TERM_FILE="$monitor_term_file" \
  perl "$SCRIPT" --watch &
WATCHER_PID=$!

watch_wait=0
while [ "$watch_wait" -lt 100 ] && [ ! -r "$monitor_pid_file" ]; do
  sleep 0.05
  watch_wait=$((watch_wait + 1))
done
[ -r "$monitor_pid_file" ] && IFS= read -r MONITOR_PID <"$monitor_pid_file"

kill -TERM "$WATCHER_PID"
wait "$WATCHER_PID"
WATCHER_PID=

if [ -n "$MONITOR_PID" ] &&
   [ -r "$monitor_term_file" ] &&
   ! kill -0 "$MONITOR_PID" >/dev/null 2>&1; then
  MONITOR_PID=
  printf 'ok 7 - greeter watcher termination also reaps its udev monitor child\n'
else
  printf 'not ok 7 - greeter watcher termination also reaps its udev monitor child\n'
  exit 1
fi

orphan_parent="$TMP_DIR/orphan-parent"
orphan_watcher_pid_file="$TMP_DIR/orphan-watcher.pid"
orphan_monitor_pid_file="$TMP_DIR/orphan-monitor.pid"
orphan_monitor_term_file="$TMP_DIR/orphan-monitor.term"
cat >"$orphan_parent" <<'EOF'
#!/bin/sh
set -eu

LABWC_GREETER_OWNER_PID=$$ perl "$SCRIPT" --watch &
watcher_pid=$!
printf '%s\n' "$watcher_pid" >"$WATCHER_PID_FILE"

wait_ticks=100
while [ "$wait_ticks" -gt 0 ] && [ ! -r "$MONITOR_PID_FILE" ]; do
  sleep 0.05
  wait_ticks=$((wait_ticks - 1))
done
[ -r "$MONITOR_PID_FILE" ]
EOF
chmod 0755 "$orphan_parent"

PATH="$TMP_DIR/bin:/usr/bin:/bin" \
SCRIPT="$SCRIPT" \
WATCHER_PID_FILE="$orphan_watcher_pid_file" \
MONITOR_PID_FILE="$orphan_monitor_pid_file" \
MONITOR_TERM_FILE="$orphan_monitor_term_file" \
  /bin/sh "$orphan_parent"

IFS= read -r orphan_watcher_pid <"$orphan_watcher_pid_file"
IFS= read -r orphan_monitor_pid <"$orphan_monitor_pid_file"
WATCHER_PID=$orphan_watcher_pid
MONITOR_PID=$orphan_monitor_pid
orphan_wait=0
while [ "$orphan_wait" -lt 100 ] &&
      { kill -0 "$orphan_watcher_pid" >/dev/null 2>&1 ||
        kill -0 "$orphan_monitor_pid" >/dev/null 2>&1; }; do
  sleep 0.05
  orphan_wait=$((orphan_wait + 1))
done

if [ -r "$orphan_monitor_term_file" ] &&
   ! kill -0 "$orphan_watcher_pid" >/dev/null 2>&1 &&
   ! kill -0 "$orphan_monitor_pid" >/dev/null 2>&1; then
  WATCHER_PID=
  MONITOR_PID=
  printf 'ok 8 - greeter watcher exits and reaps its monitor when the owning greeter client disappears\n'
else
  printf 'not ok 8 - greeter watcher exits and reaps its monitor when the owning greeter client disappears\n'
  exit 1
fi
