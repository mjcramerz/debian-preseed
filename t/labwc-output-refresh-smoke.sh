#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
SCRIPT="${ROOT_DIR}/d-i/forky/hooks/role/desktop/target/usr/local/libexec/labwc-output-refresh"
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/labwc-output-refresh.XXXXXX")
BIN_DIR="${TMP_DIR}/bin"
HOME_DIR="${TMP_DIR}/home"
RUNTIME_DIR="${TMP_DIR}/runtime"
STATE_FILE="${TMP_DIR}/wlr-randr.state"
NEXT_STATE_FILE="${TMP_DIR}/wlr-randr.next"
TRANSITION_MARKER="${TMP_DIR}/wlr-randr.transitioned"
FAILURE_MARKER="${TMP_DIR}/wlr-randr.failed"
LOG_FILE="${TMP_DIR}/wlr-randr.log"
ACTION_LOG="${TMP_DIR}/actions.log"
WLOPM_LOG="${TMP_DIR}/wlopm.log"
STDOUT_FILE="${TMP_DIR}/stdout.log"
STDERR_FILE="${TMP_DIR}/stderr.log"
FUZZEL_HOLDER_PID=

TEST_COUNT=21
TEST_INDEX=0

cleanup() {
  if [ -n "$FUZZEL_HOLDER_PID" ]; then
    if [ -r "$RUNTIME_DIR/labwc-fuzzel.pid" ]; then
      fuzzel_pid=$(cat "$RUNTIME_DIR/labwc-fuzzel.pid" 2>/dev/null || true)
      case "$fuzzel_pid" in
        ''|*[!0-9]*) ;;
        *) kill "$fuzzel_pid" >/dev/null 2>&1 || true ;;
      esac
    fi
    kill "$FUZZEL_HOLDER_PID" >/dev/null 2>&1 || true
    wait "$FUZZEL_HOLDER_PID" 2>/dev/null || true
  fi
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT HUP INT TERM

pass() {
  TEST_INDEX=$((TEST_INDEX + 1))
  printf 'ok %s - %s\n' "$TEST_INDEX" "$1"
}

fail() {
  TEST_INDEX=$((TEST_INDEX + 1))
  printf 'not ok %s - %s\n' "$TEST_INDEX" "$1"
  exit 1
}

install -d -m 0700 "$BIN_DIR" "$HOME_DIR/.config/waybar" "$RUNTIME_DIR"
: >"$HOME_DIR/.config/waybar/config"
: >"$HOME_DIR/.config/waybar/style.css"

cat >"${BIN_DIR}/wlr-randr" <<'EOF'
#!/bin/sh
set -eu
if [ "$#" -eq 0 ]; then
  cat "$WLR_RANDR_STATE"
  exit 0
fi
printf '%s\n' "$*" >>"$WLR_RANDR_LOG"
case "${WLR_RANDR_FAILURE_MODE:-}" in
  busy-once)
    if [ ! -e "$WLR_RANDR_FAILURE_MARKER" ]; then
      : >"$WLR_RANDR_FAILURE_MARKER"
      printf 'eDP-1: Atomic commit failed: Device or resource busy\n' >&2
      exit 1
    fi
    ;;
  busy-always)
    printf 'eDP-1: Atomic commit failed: Device or resource busy\n' >&2
    exit 1
    ;;
  disappear-once)
    if [ ! -e "$WLR_RANDR_FAILURE_MARKER" ]; then
      : >"$WLR_RANDR_FAILURE_MARKER"
      cp "$WLR_RANDR_NEXT_STATE" "$WLR_RANDR_STATE"
      printf 'output is not available\n' >&2
      exit 1
    fi
    ;;
esac
if [ -n "${WLR_RANDR_NEXT_STATE:-}" ] &&
   [ -r "$WLR_RANDR_NEXT_STATE" ] &&
   [ ! -e "$WLR_RANDR_TRANSITION_MARKER" ]; then
  cp "$WLR_RANDR_NEXT_STATE" "$WLR_RANDR_STATE"
  : >"$WLR_RANDR_TRANSITION_MARKER"
fi
EOF
chmod 0700 "${BIN_DIR}/wlr-randr"

cat >"${BIN_DIR}/wlopm" <<'EOF'
#!/bin/sh
set -eu
printf '%s\n' "$*" >>"$WLOPM_LOG"
EOF
chmod 0700 "${BIN_DIR}/wlopm"

cat >"${BIN_DIR}/fuzzel-holder" <<'EOF'
#!/bin/sh
set -eu
exec 9>"${XDG_RUNTIME_DIR:?}/labwc-fuzzel.lock"
/usr/bin/flock -n 9
sleep 30 &
fuzzel_pid=$!
printf '%s\n' "$fuzzel_pid" >"${XDG_RUNTIME_DIR}/labwc-fuzzel.pid"
wait "$fuzzel_pid" 2>/dev/null || true
rm -f -- "${XDG_RUNTIME_DIR}/labwc-fuzzel.pid"
EOF
chmod 0700 "${BIN_DIR}/fuzzel-holder"

cat >"${BIN_DIR}/systemctl" <<'EOF'
#!/bin/sh
set -eu
case "$*" in
  '--user --quiet is-active labwc-session.target')
    [ "${SYSTEMCTL_SESSION_ACTIVE:-true}" = true ]
    ;;
  '--user --quiet is-active waybar.service')
    [ "${SYSTEMCTL_WAYBAR_ACTIVE:-false}" = true ]
    ;;
  '--user --no-block restart waybar.service')
    printf 'systemctl %s\n' "$*" >>"$ACTION_LOG"
    [ "${SYSTEMCTL_WAYBAR_RESTART_OK:-false}" = true ]
    ;;
  '--user --no-block start waybar.service')
    printf 'systemctl %s\n' "$*" >>"$ACTION_LOG"
    [ "${SYSTEMCTL_WAYBAR_START_OK:-false}" = true ]
    ;;
  '--user --no-block restart crystal-dock.service')
    printf 'systemctl %s\n' "$*" >>"$ACTION_LOG"
    ;;
  *)
    exit 1
    ;;
esac
EOF
chmod 0700 "${BIN_DIR}/systemctl"

write_state() {
  cat >"$STATE_FILE"
}

write_next_state() {
  cat >"$NEXT_STATE_FILE"
}

run_refresh() {
  : >"$LOG_FILE"
  : >"$ACTION_LOG"
  : >"$WLOPM_LOG"
  : >"$STDOUT_FILE"
  : >"$STDERR_FILE"
  rm -f "$TRANSITION_MARKER" "$FAILURE_MARKER"

  PATH="${BIN_DIR}:$PATH" \
  HOME="$HOME_DIR" \
  XDG_RUNTIME_DIR="$RUNTIME_DIR" \
  ACTION_LOG="$ACTION_LOG" \
  SYSTEMCTL_SESSION_ACTIVE="${SYSTEMCTL_SESSION_ACTIVE:-true}" \
  SYSTEMCTL_WAYBAR_ACTIVE="${SYSTEMCTL_WAYBAR_ACTIVE:-false}" \
  SYSTEMCTL_WAYBAR_RESTART_OK="${SYSTEMCTL_WAYBAR_RESTART_OK:-false}" \
  SYSTEMCTL_WAYBAR_START_OK="${SYSTEMCTL_WAYBAR_START_OK:-false}" \
  WAYLAND_DISPLAY="wayland-1" \
  WLOPM_LOG="$WLOPM_LOG" \
  WLR_RANDR_LOG="$LOG_FILE" \
  WLR_RANDR_FAILURE_MARKER="$FAILURE_MARKER" \
  WLR_RANDR_FAILURE_MODE="${WLR_RANDR_FAILURE_MODE:-}" \
  WLR_RANDR_NEXT_STATE="${WLR_RANDR_NEXT_STATE:-}" \
  WLR_RANDR_STATE="$STATE_FILE" \
  WLR_RANDR_TRANSITION_MARKER="$TRANSITION_MARKER" \
  LABWC_ENABLE_WAYBAR="${LABWC_ENABLE_WAYBAR:-true}" \
  LABWC_OUTPUT_EXTERNAL_PREFERRED_WIDTH="${LABWC_OUTPUT_EXTERNAL_PREFERRED_WIDTH-}" \
  LABWC_OUTPUT_EXTERNAL_PREFERRED_HEIGHT="${LABWC_OUTPUT_EXTERNAL_PREFERRED_HEIGHT-}" \
  LABWC_OUTPUT_EXTERNAL_PREFERRED_REFRESH_HZ="${LABWC_OUTPUT_EXTERNAL_PREFERRED_REFRESH_HZ-}" \
  LABWC_OUTPUT_EXTERNAL_SCALE="${LABWC_OUTPUT_EXTERNAL_SCALE:-1}" \
  LABWC_OUTPUT_FALLBACK_REFRESH_HZ="${LABWC_OUTPUT_FALLBACK_REFRESH_HZ:-60}" \
  LABWC_OUTPUT_INTERNAL_PREFERRED_WIDTH="${LABWC_OUTPUT_INTERNAL_PREFERRED_WIDTH-}" \
  LABWC_OUTPUT_INTERNAL_PREFERRED_HEIGHT="${LABWC_OUTPUT_INTERNAL_PREFERRED_HEIGHT-}" \
  LABWC_OUTPUT_INTERNAL_PREFERRED_REFRESH_HZ="${LABWC_OUTPUT_INTERNAL_PREFERRED_REFRESH_HZ-}" \
  LABWC_OUTPUT_INTERNAL_PREFIXES="eDP LVDS DSI" \
  LABWC_OUTPUT_INTERNAL_REFRESH_DELAY_SECONDS="${LABWC_OUTPUT_INTERNAL_REFRESH_DELAY_SECONDS:-0}" \
  LABWC_OUTPUT_INTERNAL_SCALE="${LABWC_OUTPUT_INTERNAL_SCALE:-1}" \
  LABWC_OUTPUT_POLICY="${LABWC_OUTPUT_POLICY:-external-only}" \
  LABWC_OUTPUT_SCALE="1" \
    perl "$SCRIPT" "$@" >"$STDOUT_FILE" 2>"$STDERR_FILE"
}

start_fuzzel_holder() {
  rm -f -- "$RUNTIME_DIR/labwc-fuzzel.pid"
  XDG_RUNTIME_DIR="$RUNTIME_DIR" "${BIN_DIR}/fuzzel-holder" &
  FUZZEL_HOLDER_PID=$!
  holder_wait=0
  while [ "$holder_wait" -lt 50 ]; do
    [ -r "$RUNTIME_DIR/labwc-fuzzel.pid" ] && return 0
    sleep 0.02
    holder_wait=$((holder_wait + 1))
  done
  return 1
}

printf '1..%s\n' "$TEST_COUNT"

write_state <<'EOF'
HDMI-A-1 "External"
  Enabled: yes
  Modes:
    1920x1080 px, 120.000000 Hz
    3840x2160 px, 60.000000 Hz (preferred)
eDP-1 "Internal"
  Enabled: yes
  Modes:
    1920x1200 px, 60.000000 Hz (preferred)
DP-1 "Secondary"
  Enabled: yes
  Modes:
    2560x1440 px, 60.000000 Hz (preferred)
EOF
run_refresh
if grep -F -q -- '--output HDMI-A-1 --on --mode 3840x2160@60.000000Hz --scale 1 --pos 0,0' "$LOG_FILE" &&
   grep -F -q -- '--output eDP-1 --off' "$LOG_FILE" &&
   grep -F -q -- '--output DP-1 --off' "$LOG_FILE"; then
  pass "HDMI overrides internal and non-HDMI outputs while using the connector preferred mode"
else
  fail "HDMI overrides internal and non-HDMI outputs while using the connector preferred mode"
fi

write_state <<'EOF'
HDMI-A-1 "External"
  Enabled: yes
  Modes:
    3840x2160 px, 30.000000 Hz (preferred)
    2560x1440 px, 59.951000 Hz
    1920x1080 px, 120.000000 Hz
EOF
LABWC_OUTPUT_FALLBACK_REFRESH_HZ=60 run_refresh
if grep -F -q -- '--output HDMI-A-1 --on --mode 2560x1440@59.951000Hz --scale 1 --pos 0,0' "$LOG_FILE"; then
  pass "preferred external modes below the fallback refresh yield to the largest mode that meets the refresh floor"
else
  fail "preferred external modes below the fallback refresh yield to the largest mode that meets the refresh floor"
fi

write_state <<'EOF'
HDMI-A-1 "External"
  Enabled: yes
  Modes:
    1920x1080 px, 120.000000 Hz
    3840x2160 px, 60.000000 Hz (preferred)
EOF
: >"$LOG_FILE"
PATH="${BIN_DIR}:$PATH" \
HOME="$HOME_DIR" \
XDG_RUNTIME_DIR="$RUNTIME_DIR" \
ACTION_LOG="$ACTION_LOG" \
WAYLAND_DISPLAY="wayland-1" \
WLOPM_LOG="$WLOPM_LOG" \
WLR_RANDR_LOG="$LOG_FILE" \
WLR_RANDR_STATE="$STATE_FILE" \
LABWC_OUTPUT_INTERNAL_PREFIXES="eDP LVDS DSI" \
LABWC_OUTPUT_POLICY="external-only" \
LABWC_OUTPUT_SCALE="1" \
LABWC_OUTPUT_EXTERNAL_SCALE="1" \
LABWC_OUTPUT_EXTERNAL_PREFERRED_WIDTH="1920" \
LABWC_OUTPUT_EXTERNAL_PREFERRED_HEIGHT="1080" \
LABWC_OUTPUT_EXTERNAL_PREFERRED_REFRESH_HZ="120" \
  perl "$SCRIPT"
if grep -F -q -- '--output HDMI-A-1 --on --mode 1920x1080@120.000000Hz --scale 1 --pos 0,0' "$LOG_FILE"; then
  pass "configured external output mode remains opt-in"
else
  fail "configured external output mode remains opt-in"
fi

write_state <<'EOF'
eDP-1 "Internal"
  Enabled: yes
  Modes:
    1920x1080 px, 120.000000 Hz
    1920x1080 px, 60.000000 Hz (preferred)
EOF
LABWC_OUTPUT_INTERNAL_PREFERRED_WIDTH=1920 \
LABWC_OUTPUT_INTERNAL_PREFERRED_HEIGHT=1080 \
LABWC_OUTPUT_INTERNAL_PREFERRED_REFRESH_HZ=60 \
LABWC_OUTPUT_EXTERNAL_PREFERRED_WIDTH=1920 \
LABWC_OUTPUT_EXTERNAL_PREFERRED_HEIGHT=1080 \
LABWC_OUTPUT_EXTERNAL_PREFERRED_REFRESH_HZ=120 \
run_refresh
if grep -F -q -- '--output eDP-1 --on --mode 1920x1080@60.000000Hz --scale 1 --pos 0,0' "$LOG_FILE" &&
   ! grep -F -q -- '1920x1080@120.000000Hz' "$LOG_FILE"; then
  pass "internal outputs use the internal preferred refresh instead of the external preference"
else
  fail "internal outputs use the internal preferred refresh instead of the external preference"
fi

write_state <<'EOF'
eDP-1 "Internal"
  Enabled: yes
  Modes:
    1366x768 px, 60.000000 Hz (preferred)
HDMI-A-1 "External"
  Enabled: yes
  Modes:
    1920x1080 px, 120.000000 Hz
    3840x2160 px, 60.000000 Hz (preferred)
EOF
LABWC_OUTPUT_POLICY=auto \
LABWC_OUTPUT_INTERNAL_PREFERRED_WIDTH=1920 \
LABWC_OUTPUT_INTERNAL_PREFERRED_HEIGHT=1080 \
LABWC_OUTPUT_INTERNAL_PREFERRED_REFRESH_HZ=60 \
LABWC_OUTPUT_EXTERNAL_PREFERRED_WIDTH=1920 \
LABWC_OUTPUT_EXTERNAL_PREFERRED_HEIGHT=1080 \
LABWC_OUTPUT_EXTERNAL_PREFERRED_REFRESH_HZ=120 \
LABWC_OUTPUT_EXTERNAL_SCALE=1 \
run_refresh
if grep -F -q -- '--output HDMI-A-1 --on --mode 1920x1080@120.000000Hz --scale 1 --pos 0,0' "$LOG_FILE" &&
   grep -F -q -- '--output eDP-1 --off' "$LOG_FILE" &&
   ! grep -F -q -- '--output eDP-1 --on' "$LOG_FILE"; then
  pass "HDMI overrides the laptop internal panel under auto policy"
else
  fail "HDMI overrides the laptop internal panel under auto policy"
fi

write_state <<'EOF'
eDP-1 "Internal"
  Enabled: yes
  Modes:
    1366x768 px, 60.000000 Hz (preferred)
DP-1 "External"
  Enabled: yes
  Modes:
    1920x1080 px, 120.000000 Hz (preferred)
EOF
LABWC_OUTPUT_POLICY=auto \
LABWC_OUTPUT_INTERNAL_PREFERRED_WIDTH=1366 \
LABWC_OUTPUT_INTERNAL_PREFERRED_HEIGHT=768 \
LABWC_OUTPUT_INTERNAL_PREFERRED_REFRESH_HZ=60 \
LABWC_OUTPUT_EXTERNAL_PREFERRED_WIDTH=1920 \
LABWC_OUTPUT_EXTERNAL_PREFERRED_HEIGHT=1080 \
LABWC_OUTPUT_EXTERNAL_PREFERRED_REFRESH_HZ=120 \
run_refresh
if grep -F -q -- '--output eDP-1 --on --mode 1366x768@60.000000Hz --scale 1 --pos 0,0' "$LOG_FILE" &&
   grep -F -q -- '--output DP-1 --on --mode 1920x1080@120.000000Hz --scale 1 --pos 1366,0' "$LOG_FILE" &&
   ! grep -F -q -- '--off' "$LOG_FILE"; then
  pass "auto extension remains available when no HDMI connector is present"
else
  fail "auto extension remains available when no HDMI connector is present"
fi

write_state <<'EOF'
DP-1 "Primary external"
  Enabled: yes
  Modes:
    1920x1080 px, 120.000000 Hz (preferred)
HDMI-A-1 "Secondary external"
  Enabled: yes
  Modes:
    1920x1080 px, 60.000000 Hz (preferred)
EOF
LABWC_OUTPUT_POLICY=auto \
LABWC_OUTPUT_EXTERNAL_PREFERRED_WIDTH=1920 \
LABWC_OUTPUT_EXTERNAL_PREFERRED_HEIGHT=1080 \
LABWC_OUTPUT_EXTERNAL_PREFERRED_REFRESH_HZ=120 \
LABWC_OUTPUT_EXTERNAL_SCALE=1 \
run_refresh
if grep -F -q -- '--output HDMI-A-1 --on --mode 1920x1080@60.000000Hz --scale 1 --pos 0,0' "$LOG_FILE" &&
   grep -F -q -- '--output DP-1 --off' "$LOG_FILE" &&
   ! grep -F -q -- '--output DP-1 --on' "$LOG_FILE"; then
  pass "HDMI overrides non-HDMI external outputs on stationary systems"
else
  fail "HDMI overrides non-HDMI external outputs on stationary systems"
fi

write_state <<'EOF'
HDMI-A-1 "External"
  Enabled: yes
  Modes:
    2560x1440 px, 144.000000 Hz
    2560x1440 px, 60.000000 Hz
    1920x1080 px, 120.000000 Hz
EOF
LABWC_OUTPUT_FALLBACK_REFRESH_HZ=60 run_refresh
if grep -F -q -- '--output HDMI-A-1 --on --mode 2560x1440@60.000000Hz --scale 1 --pos 0,0' "$LOG_FILE"; then
  pass "largest fallback mode prefers the configured fallback refresh"
else
  fail "largest fallback mode prefers the configured fallback refresh"
fi

write_state <<'EOF'
eDP-1 "Internal"
  Enabled: yes
  Modes:
    1920x1200 px, 60.000000 Hz (preferred)
EOF
SYSTEMCTL_WAYBAR_START_OK=true \
run_refresh
if grep -Fxq 'systemctl --user --no-block start waybar.service' "$ACTION_LOG" &&
   grep -F -q -- 'systemctl --user --no-block restart crystal-dock.service' "$ACTION_LOG"; then
  pass "stored topology changes still restart session chrome after unplug auto-reconfiguration"
else
  fail "stored topology changes still restart session chrome after unplug auto-reconfiguration"
fi

write_state <<'EOF'
HDMI-A-1 "External"
  Enabled: yes
  Modes:
    1920x1080 px, 60.000000 Hz (preferred)
eDP-1 "Internal"
  Enabled: yes
  Modes:
    1920x1200 px, 60.000000 Hz (preferred)
EOF
write_next_state <<'EOF'
HDMI-A-1 "External"
  Enabled: yes
  Modes:
    1920x1080 px, 60.000000 Hz (preferred)
EOF
WLR_RANDR_NEXT_STATE="$NEXT_STATE_FILE" \
SYSTEMCTL_WAYBAR_START_OK=true \
run_refresh
if grep -Fxq 'systemctl --user --no-block start waybar.service' "$ACTION_LOG" &&
   grep -F -q -- 'systemctl --user --no-block restart crystal-dock.service' "$ACTION_LOG"; then
  pass "topology changes restart the running session chrome coherently"
else
  fail "topology changes restart the running session chrome coherently"
fi

write_state <<'EOF'
HDMI-A-1 "External"
  Enabled: yes
  Modes:
    1920x1080 px, 60.000000 Hz (preferred)
eDP-1 "Internal"
  Enabled: yes
  Modes:
    1920x1200 px, 60.000000 Hz (preferred)
EOF
write_next_state <<'EOF'
eDP-1 "Internal"
  Enabled: yes
  Modes:
    1920x1200 px, 60.000000 Hz (preferred)
EOF
WLR_RANDR_NEXT_STATE="$NEXT_STATE_FILE" \
SYSTEMCTL_WAYBAR_START_OK=true \
run_refresh
if grep -Fxq 'systemctl --user --no-block start waybar.service' "$ACTION_LOG" &&
   grep -F -q -- 'systemctl --user --no-block restart crystal-dock.service' "$ACTION_LOG"; then
  pass "topology changes restore missing Waybar and Crystal Dock session chrome"
else
  fail "topology changes restore missing Waybar and Crystal Dock session chrome"
fi

write_state <<'EOF'
eDP-1 "Internal"
  Enabled: yes
  Modes:
    1920x1200 px, 60.000000 Hz (preferred)
EOF
run_refresh
if [ ! -s "$ACTION_LOG" ]; then
  pass "unchanged topology avoids unnecessary waybar and dock restarts"
else
  fail "unchanged topology avoids unnecessary waybar and dock restarts"
fi

write_state <<'EOF'
HDMI-A-1 "External"
  Enabled: yes
  Modes:
    1920x1080 px, 60.000000 Hz (preferred)
eDP-1 "Internal"
  Enabled: yes
  Modes:
    1920x1200 px, 60.000000 Hz (preferred)
EOF
write_next_state <<'EOF'
HDMI-A-1 "External"
  Enabled: yes
  Modes:
    1920x1080 px, 60.000000 Hz (preferred)
EOF
WLR_RANDR_NEXT_STATE="$NEXT_STATE_FILE" \
SYSTEMCTL_WAYBAR_ACTIVE=true \
SYSTEMCTL_WAYBAR_RESTART_OK=true \
run_refresh
if grep -Fxq 'systemctl --user --no-block restart waybar.service' "$ACTION_LOG" &&
   ! grep -Eq '^pkill .*waybar$|^waybar ' "$ACTION_LOG" &&
   grep -F -q -- 'systemctl --user --no-block restart crystal-dock.service' "$ACTION_LOG"; then
  pass "topology changes restart the systemd-owned multi-output Waybar without duplicates"
else
  fail "topology changes restart the systemd-owned multi-output Waybar without duplicates"
fi

write_state <<'EOF'
HDMI-A-1 "External"
  Enabled: yes
  Modes:
    1920x1080 px, 60.000000 Hz (preferred)
eDP-1 "Internal"
  Enabled: yes
  Modes:
    1920x1200 px, 60.000000 Hz (preferred)
EOF
write_next_state <<'EOF'
eDP-1 "Internal"
  Enabled: yes
  Modes:
    1920x1200 px, 60.000000 Hz (preferred)
EOF
WLR_RANDR_NEXT_STATE="$NEXT_STATE_FILE" \
SYSTEMCTL_WAYBAR_START_OK=true \
run_refresh
if grep -Fxq 'systemctl --user --no-block start waybar.service' "$ACTION_LOG" &&
   ! grep -Eq '^pkill .*waybar$|^waybar ' "$ACTION_LOG" &&
   grep -F -q -- 'systemctl --user --no-block restart crystal-dock.service' "$ACTION_LOG"; then
  pass "topology changes restore a stopped systemd-owned Waybar through its service"
else
  fail "topology changes restore a stopped systemd-owned Waybar through its service"
fi

run_refresh --dpms-off
if [ "$(cat "$WLOPM_LOG")" = "--off *" ] &&
   [ ! -s "$LOG_FILE" ] &&
   [ ! -s "$ACTION_LOG" ]; then
  pass "DPMS off only powers down outputs without reconfiguring topology"
else
  fail "DPMS off only powers down outputs without reconfiguring topology"
fi

SYSTEMCTL_WAYBAR_START_OK=true \
run_refresh --dpms-on
if [ "$(cat "$WLOPM_LOG")" = "--on *" ] &&
   [ ! -s "$LOG_FILE" ] &&
   grep -Fxq 'systemctl --user --no-block start waybar.service' "$ACTION_LOG"; then
  pass "DPMS resume powers up outputs and restores a missing Waybar without reconfiguring topology"
else
  fail "DPMS resume powers up outputs and restores a missing Waybar without reconfiguring topology"
fi

start_fuzzel_holder
fuzzel_pid=$(cat "$RUNTIME_DIR/labwc-fuzzel.pid")
SYSTEMCTL_WAYBAR_ACTIVE=true \
SYSTEMCTL_WAYBAR_RESTART_OK=true \
run_refresh --dpms-on
if [ "$(cat "$WLOPM_LOG")" = "--on *" ] &&
   grep -Fxq 'systemctl --user --no-block restart waybar.service' "$ACTION_LOG" &&
   kill -0 "$fuzzel_pid" >/dev/null 2>&1; then
  pass "DPMS resume keeps an active Fuzzel process running while refreshing output chrome"
else
  fail "DPMS resume keeps an active Fuzzel process running while refreshing output chrome"
fi

rm -f -- \
  "$RUNTIME_DIR/labwc/output-idle-topology.state" \
  "$RUNTIME_DIR/labwc/output-idle-topology.restore"
write_state <<'EOF'
eDP-1 "Internal"
  Enabled: yes
  Modes:
    1920x1200 px, 60.000000 Hz (current, preferred)
  Position: 0,0
  Transform: normal
  Scale: 1.250000
  Logical size: 1536x960
HDMI-A-1 "External"
  Enabled: yes
  Modes:
    1920x1080 px, 60.000000 Hz (current, preferred)
  Position: 1536,0
  Transform: 90
  Scale: 1.000000
  Logical size: 1080x1920
EOF
run_refresh --dpms-off
write_state <<'EOF'
eDP-1 "Internal"
  Enabled: yes
  Modes:
    1920x1200 px, 60.000000 Hz (current, preferred)
  Position: 0,0
  Transform: normal
  Scale: 1.000000
  Logical size: 1920x1200
HDMI-A-1 "External"
  Enabled: yes
  Modes:
    1920x1080 px, 60.000000 Hz (current, preferred)
  Position: 0,0
  Transform: normal
  Scale: 1.000000
  Logical size: 1920x1080
EOF
write_next_state <<'EOF'
eDP-1 "Internal"
  Enabled: yes
  Modes:
    1920x1200 px, 60.000000 Hz (current, preferred)
  Position: 0,0
  Transform: normal
  Scale: 1.250000
  Logical size: 1536x960
HDMI-A-1 "External"
  Enabled: yes
  Modes:
    1920x1080 px, 60.000000 Hz (current, preferred)
  Position: 1536,0
  Transform: 90
  Scale: 1.000000
  Logical size: 1080x1920
EOF
SYSTEMCTL_WAYBAR_START_OK=true \
WLR_RANDR_NEXT_STATE="$NEXT_STATE_FILE" \
run_refresh --dpms-on
if [ "$(cat "$WLOPM_LOG")" = "--on *" ] &&
   grep -F -q -- '--output eDP-1 --on --mode 1920x1200@60.000000Hz --scale 1.250000 --transform normal --pos 0,0' "$LOG_FILE" &&
   grep -F -q -- '--output HDMI-A-1 --on --mode 1920x1080@60.000000Hz --scale 1.000000 --transform 90 --pos 1536,0' "$LOG_FILE" &&
   [ ! -e "$RUNTIME_DIR/labwc/output-idle-topology.state" ] &&
   [ ! -e "$RUNTIME_DIR/labwc/output-idle-topology.restore" ]; then
  pass "DPMS resume restores the saved mode, scale, position, transform, and logical geometry"
else
  fail "DPMS resume restores the saved mode, scale, position, transform, and logical geometry"
fi

write_state <<'EOF'
eDP-1 "Internal"
  Enabled: yes
  Modes:
    1920x1200 px, 60.000000 Hz (preferred)
EOF
WLR_RANDR_FAILURE_MODE=busy-once run_refresh
if [ "$(grep -Fc -- '--output eDP-1 --on --mode 1920x1200@60.000000Hz --scale 1 --pos 0,0' "$LOG_FILE")" -eq 2 ] &&
   [ ! -s "$STDOUT_FILE" ] &&
   [ ! -s "$STDERR_FILE" ]; then
  pass "an atomic-commit EBUSY is retried once without leaking diagnostics"
else
  fail "an atomic-commit EBUSY is retried once without leaking diagnostics"
fi

write_state <<'EOF'
eDP-1 "Internal"
  Enabled: yes
  Modes:
    1920x1200 px, 60.000000 Hz (preferred)
EOF
: >"$NEXT_STATE_FILE"
WLR_RANDR_FAILURE_MODE=disappear-once \
WLR_RANDR_NEXT_STATE="$NEXT_STATE_FILE" \
run_refresh
if [ "$(grep -Fc -- '--output eDP-1 --on --mode 1920x1200@60.000000Hz --scale 1 --pos 0,0' "$LOG_FILE")" -eq 1 ] &&
   [ ! -s "$STDOUT_FILE" ] &&
   [ ! -s "$STDERR_FILE" ]; then
  pass "a connector disappearing during refresh becomes a quiet no-op"
else
  fail "a connector disappearing during refresh becomes a quiet no-op"
fi

write_state <<'EOF'
eDP-1 "Internal"
  Enabled: yes
  Modes:
    1920x1200 px, 60.000000 Hz (preferred)
EOF
SYSTEMCTL_SESSION_ACTIVE=false run_refresh
if [ ! -s "$LOG_FILE" ] &&
   [ ! -s "$WLOPM_LOG" ] &&
   [ ! -s "$ACTION_LOG" ] &&
   [ ! -s "$STDOUT_FILE" ] &&
   [ ! -s "$STDERR_FILE" ]; then
  pass "output refresh exits quietly after Labwc session teardown begins"
else
  fail "output refresh exits quietly after Labwc session teardown begins"
fi
