#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
SCRIPT="${ROOT_DIR}/d-i/forky/hooks/role/desktop/target/usr/local/libexec/labwc-output-watch"
APPARMOR="${ROOT_DIR}/d-i/forky/hooks/shared/target/etc/apparmor.d/managed-desktop-wrappers"
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/labwc-output-watch.XXXXXX")
BIN_DIR="${TMP_DIR}/bin"
REFRESH_LOG="${TMP_DIR}/refresh.log"
UDEVADM_LOG="${TMP_DIR}/udevadm.log"
WLR_RANDR_COUNT="${TMP_DIR}/wlr-randr.count"
WAYLAND_INFO_COUNT="${TMP_DIR}/wayland-info.count"
trap 'rm -rf "$TMP_DIR"' EXIT HUP INT TERM

mkdir -p "$BIN_DIR"

cat >"${BIN_DIR}/labwc-output-refresh" <<'EOF'
#!/bin/sh
set -eu
case "${1:-}" in
  --idle-topology-active)
    [ "${OUTPUT_IDLE_ACTIVE:-false}" = true ]
    ;;
  --restore-idle-topology)
    printf 'restore\n' >>"${REFRESH_LOG:?}"
    [ "${OUTPUT_IDLE_RESTORE_OK:-false}" = true ]
    ;;
  '')
    printf 'refresh\n' >>"${REFRESH_LOG:?}"
    ;;
  *)
    exit 2
    ;;
esac
EOF
chmod 0755 "${BIN_DIR}/labwc-output-refresh"

cat >"${BIN_DIR}/udevadm" <<'EOF'
#!/bin/sh
set -eu
case "${1:-}" in
  monitor)
    case "${UDEVADM_MONITOR_MODE:-single}" in
      single)
        printf 'UDEV  change /devices/pci0000:00/drm/card0/card0-HDMI-A-1 (drm)\n'
        ;;
      burst)
        printf '%s\n' \
          'KERNEL change /devices/pci0000:00/drm/card0/card0-HDMI-A-1 (drm)' \
          'UDEV  change /devices/pci0000:00/drm/card0/card0-HDMI-A-1 (drm)' \
          'UDEV  add /devices/pci0000:00/drm/card0/card0-DP-1 (drm)'
        ;;
      *)
        exit 2
        ;;
    esac
    ;;
  settle)
    printf 'settle %s\n' "${2:-}" >>"${UDEVADM_LOG:?}"
    ;;
  *)
    exit 2
    ;;
esac
EOF
chmod 0755 "${BIN_DIR}/udevadm"

cat >"${BIN_DIR}/wlr-randr" <<'EOF'
#!/bin/sh
set -eu
count=0
[ ! -r "${WLR_RANDR_COUNT:?}" ] || IFS= read -r count <"$WLR_RANDR_COUNT"
count=$((count + 1))
printf '%s\n' "$count" >"$WLR_RANDR_COUNT"
case "${WLR_RANDR_MODE:-ready-after-three}" in
  error-output)
    printf 'wlr-randr failed before output discovery\n'
    exit 1
    ;;
  disabled-output)
    printf 'HDMI-A-1 "External"\n'
    printf '  Enabled: no\n'
    ;;
  empty)
    ;;
  ready)
    printf 'HDMI-A-1 "External"\n'
    printf '  Enabled: yes\n'
    ;;
  ready-after-three)
    [ "$count" -ge 3 ] || exit 0
    printf 'HDMI-A-1 "External"\n'
    printf '  Enabled: yes\n'
    ;;
  *)
    exit 2
    ;;
esac
EOF
chmod 0755 "${BIN_DIR}/wlr-randr"

cat >"${BIN_DIR}/wayland-info" <<'EOF'
#!/bin/sh
set -eu
count=0
[ ! -r "${WAYLAND_INFO_COUNT:?}" ] || IFS= read -r count <"$WAYLAND_INFO_COUNT"
count=$((count + 1))
printf '%s\n' "$count" >"$WAYLAND_INFO_COUNT"

print_compositor() {
  printf "interface: 'wl_compositor', version:  6, name:  1\n"
}

print_current_output() {
  print_compositor
  printf "interface: 'wl_output', version:  4, name:  2\n"
  printf '\tmode:\n'
  printf '\t\twidth: 1920 px, height: 1080 px, refresh: 60.000 Hz,\n'
  printf '\t\tflags: current preferred\n'
}

case "${WAYLAND_INFO_MODE:-current}" in
  current)
    print_current_output
    ;;
  error-current)
    print_current_output
    exit 1
    ;;
  no-current)
    print_compositor
    printf "interface: 'wl_output', version:  4, name:  2\n"
    printf '\tmode:\n'
    printf '\t\twidth: 1920 px, height: 1080 px, refresh: 60.000 Hz,\n'
    printf '\t\tflags: preferred\n'
    ;;
  none)
    print_compositor
    ;;
  ready-after-refresh)
    if grep -qx 'refresh' "${REFRESH_LOG:?}"; then
      print_current_output
    else
      print_compositor
    fi
    ;;
  *)
    exit 2
    ;;
esac
EOF
chmod 0755 "${BIN_DIR}/wayland-info"

run_watch() {
  : >"$REFRESH_LOG"
  : >"$UDEVADM_LOG"
  PATH="${BIN_DIR}:/usr/bin:/bin" \
  REFRESH_LOG="$REFRESH_LOG" \
  UDEVADM_LOG="$UDEVADM_LOG" \
  UDEVADM_MONITOR_MODE="${UDEVADM_MONITOR_MODE:-single}" \
  WLR_RANDR_COUNT="$WLR_RANDR_COUNT" \
  WAYLAND_INFO_COUNT="$WAYLAND_INFO_COUNT" \
  WLR_RANDR_MODE="${WLR_RANDR_MODE:-ready-after-three}" \
  WAYLAND_INFO_MODE="${WAYLAND_INFO_MODE:-current}" \
  OUTPUT_IDLE_ACTIVE="${OUTPUT_IDLE_ACTIVE:-false}" \
  OUTPUT_IDLE_RESTORE_OK="${OUTPUT_IDLE_RESTORE_OK:-false}" \
  LABWC_OUTPUT_HOTPLUG_DEBOUNCE_SECONDS="${TEST_DEBOUNCE_SECONDS:-0}" \
    /bin/sh "$SCRIPT" "$@"
}

printf '1..12\n'

run_watch
if [ "$(wc -l <"$REFRESH_LOG")" -eq 2 ] &&
   grep -q '^settle --timeout=5$' "$UDEVADM_LOG"; then
  printf 'ok 1 - initial and HDMI hotplug refreshes apply after udev settles\n'
else
  printf 'not ok 1 - initial and HDMI hotplug refreshes apply after udev settles\n'
  exit 1
fi

run_watch --skip-initial-refresh
if [ "$(wc -l <"$REFRESH_LOG")" -eq 1 ] &&
   grep -q '^settle --timeout=5$' "$UDEVADM_LOG"; then
  printf 'ok 2 - skipped initial refresh still applies the HDMI hotplug policy\n'
else
  printf 'not ok 2 - skipped initial refresh still applies the HDMI hotplug policy\n'
  exit 1
fi

UDEVADM_MONITOR_MODE=burst TEST_DEBOUNCE_SECONDS=1 run_watch --skip-initial-refresh
if [ "$(wc -l <"$REFRESH_LOG")" -eq 1 ] &&
   [ "$(wc -l <"$UDEVADM_LOG")" -eq 1 ]; then
  printf 'ok 3 - burst DRM events coalesce into one settled output refresh\n'
else
  printf 'not ok 3 - burst DRM events coalesce into one settled output refresh\n'
  printf '# refresh log:\n'
  sed 's/^/#   /' "$REFRESH_LOG"
  printf '# udev settle log:\n'
  sed 's/^/#   /' "$UDEVADM_LOG"
  exit 1
fi

rm -f -- "$WLR_RANDR_COUNT" "$WAYLAND_INFO_COUNT"
WLR_RANDR_MODE=ready WAYLAND_INFO_MODE=ready-after-refresh run_watch --wait-for-output
if [ "$(cat "$REFRESH_LOG")" = "refresh" ] &&
   [ "$(cat "$WLR_RANDR_COUNT")" -eq 1 ] &&
   [ "$(cat "$WAYLAND_INFO_COUNT")" -eq 2 ]; then
  printf 'ok 4 - readiness repairs an output-management-only head before accepting a client-visible output\n'
else
  printf 'not ok 4 - readiness repairs an output-management-only head before accepting a client-visible output\n'
  exit 1
fi

rm -f -- "$WLR_RANDR_COUNT" "$WAYLAND_INFO_COUNT"
WAYLAND_INFO_MODE=current run_watch --wait-for-output
if [ ! -s "$REFRESH_LOG" ] &&
   [ ! -e "$WLR_RANDR_COUNT" ] &&
   [ "$(cat "$WAYLAND_INFO_COUNT")" -eq 1 ]; then
  printf 'ok 5 - a pre-existing client-visible current mode avoids a duplicate output refresh\n'
else
  printf 'not ok 5 - a pre-existing client-visible current mode avoids a duplicate output refresh\n'
  exit 1
fi

OUTPUT_IDLE_ACTIVE=true \
OUTPUT_IDLE_RESTORE_OK=true \
run_watch --skip-initial-refresh
if [ "$(cat "$REFRESH_LOG")" = "restore" ] &&
   grep -q '^settle --timeout=5$' "$UDEVADM_LOG"; then
  printf 'ok 6 - hotplug during an idle restore retries the saved geometry instead of policy placement\n'
else
  printf 'not ok 6 - hotplug during an idle restore retries the saved geometry instead of policy placement\n'
  exit 1
fi

if grep -Fq 'kill "$pending_refresh_pid"' "$SCRIPT" &&
   grep -Fq 'kill "$debounce_pid"' "$SCRIPT" &&
   grep -Fq "trap 'cancel_debounce; exit 0' HUP INT TERM" "$SCRIPT" &&
   grep -Fq 'printf '\''%s\n'\'' "$refresh_generation" >"$refresh_token"' "$SCRIPT" &&
   [ "$(grep -Fc '[ "$current_refresh_generation" = "$scheduled_refresh_generation" ] || exit 0' "$SCRIPT")" -eq 2 ] &&
   grep -Fq 'kill "$monitor_pid"' "$SCRIPT" &&
   ! grep -Eq '(^|[^[:alnum:]_])(pkill|killall|loginctl|reboot|shutdown|poweroff|halt)([^[:alnum:]_]|$)' "$SCRIPT" &&
   ! grep -Fq 'labwc-session.target' "$SCRIPT"; then
  printf 'ok 7 - output watcher only stops its own worker, debounce, and monitor children\n'
else
  printf 'not ok 7 - output watcher only stops its own worker, debounce, and monitor children\n'
  exit 1
fi

if grep -Fq 'read -r uptime_seconds _ </proc/uptime' "$SCRIPT" &&
   grep -Fq 'output_deadline=$((output_started + 10))' "$SCRIPT" &&
   grep -Fq 'output_remaining=$((output_deadline - output_now))' "$SCRIPT" &&
   grep -Fq '/usr/bin/timeout "$output_remaining" "$wayland_info" 2>/dev/null' "$SCRIPT" &&
   grep -Fq '/usr/bin/timeout "$output_remaining" "$wlr_randr" 2>/dev/null' "$SCRIPT" &&
   grep -Fq '/usr/bin/timeout "$output_remaining" "$readiness_refresh" >/dev/null 2>&1 || true' "$SCRIPT" &&
   grep -Fq 'wayland_snapshot_has_current_output "$wayland_snapshot"' "$SCRIPT" &&
   grep -Fq 'output_snapshot_has_output_head "$output_snapshot"' "$SCRIPT" &&
   ! grep -Fq 'output_snapshot_has_enabled_output' "$SCRIPT" &&
   ! grep -Fq '/usr/bin/timeout 2 "$wlr_randr"' "$SCRIPT" &&
   grep -Fqx '  @{PROC}/uptime r,' "$APPARMOR" &&
   grep -Fqx '  /usr/bin/wayland-info pux,' "$APPARMOR"; then
  printf 'ok 8 - output readiness uses a monotonic deadline, client protocol state, and matching AppArmor access\n'
else
  printf 'not ok 8 - output readiness uses a monotonic deadline, client protocol state, and matching AppArmor access\n'
  exit 1
fi

bounded_script="${TMP_DIR}/labwc-output-watch-bounded"
monotonic_count="${TMP_DIR}/monotonic.count"
cat >"${BIN_DIR}/test-monotonic-seconds" <<'EOF'
#!/bin/sh
set -eu

count_file=${LABWC_OUTPUT_TEST_MONOTONIC_COUNT:?}
count=0
[ ! -r "$count_file" ] || IFS= read -r count <"$count_file"
case "$count" in
  ''|*[!0-9]*) exit 2 ;;
esac
count=$((count + 1))
printf '%s\n' "$count" >"$count_file"
if [ "$count" -le 4 ]; then
  printf '0\n'
else
  printf '1\n'
fi
EOF
chmod 0755 "${BIN_DIR}/test-monotonic-seconds"

# Some test sandboxes expose a frozen /proc/uptime. Keep the production
# monotonic-clock assertion above, but make this deliberately bounded test copy
# advance through a deterministic external counter.
sed \
  -e 's#  IFS=.*read -r uptime_seconds _ </proc/uptime || return 1#  uptime_seconds=$("${LABWC_OUTPUT_TEST_MONOTONIC:?}") || return 1#' \
  -e 's/output_deadline=$((output_started + 10))/output_deadline=$((output_started + 1))/' \
  "$SCRIPT" >"$bounded_script"
chmod 0700 "$bounded_script"
rm -f -- "$WLR_RANDR_COUNT" "$WAYLAND_INFO_COUNT" "$monotonic_count"
if PATH="${BIN_DIR}:/usr/bin:/bin" \
   REFRESH_LOG="$REFRESH_LOG" \
   WLR_RANDR_COUNT="$WLR_RANDR_COUNT" \
   WAYLAND_INFO_COUNT="$WAYLAND_INFO_COUNT" \
   LABWC_OUTPUT_TEST_MONOTONIC="${BIN_DIR}/test-monotonic-seconds" \
   LABWC_OUTPUT_TEST_MONOTONIC_COUNT="$monotonic_count" \
   WLR_RANDR_MODE=empty \
   WAYLAND_INFO_MODE=error-current \
   /bin/sh "$bounded_script" --wait-for-output >/dev/null 2>&1; then
  printf 'not ok 9 - readiness rejects current-mode text from a failed client probe\n'
  exit 1
else
  printf 'ok 9 - readiness rejects current-mode text from a failed client probe\n'
fi

rm -f -- "$WLR_RANDR_COUNT" "$WAYLAND_INFO_COUNT" "$monotonic_count"
: >"$REFRESH_LOG"
if PATH="${BIN_DIR}:/usr/bin:/bin" \
   REFRESH_LOG="$REFRESH_LOG" \
   WLR_RANDR_COUNT="$WLR_RANDR_COUNT" \
   WAYLAND_INFO_COUNT="$WAYLAND_INFO_COUNT" \
   LABWC_OUTPUT_TEST_MONOTONIC="${BIN_DIR}/test-monotonic-seconds" \
   LABWC_OUTPUT_TEST_MONOTONIC_COUNT="$monotonic_count" \
   WLR_RANDR_MODE=ready \
   WAYLAND_INFO_MODE=no-current \
   /bin/sh "$bounded_script" --wait-for-output >/dev/null 2>&1; then
  printf 'not ok 10 - readiness rejects wl_output snapshots without a current mode\n'
  exit 1
else
  if [ "$(cat "$REFRESH_LOG")" = "refresh" ]; then
    printf 'ok 10 - readiness rejects wl_output snapshots without a current mode\n'
  else
    printf 'not ok 10 - readiness rejects wl_output snapshots without a current mode\n'
    exit 1
  fi
fi

rm -f -- "$WLR_RANDR_COUNT" "$WAYLAND_INFO_COUNT"
WLR_RANDR_MODE=disabled-output WAYLAND_INFO_MODE=ready-after-refresh run_watch --wait-for-output
if [ "$(cat "$REFRESH_LOG")" = "refresh" ] &&
   [ "$(cat "$WLR_RANDR_COUNT")" -eq 1 ] &&
   [ "$(cat "$WAYLAND_INFO_COUNT")" -eq 2 ]; then
  printf 'ok 11 - a disabled output-management head is activated before client readiness succeeds\n'
else
  printf 'not ok 11 - a disabled output-management head is activated before client readiness succeeds\n'
  exit 1
fi

rm -f -- "$WLR_RANDR_COUNT" "$WAYLAND_INFO_COUNT" "$monotonic_count"
: >"$REFRESH_LOG"
if PATH="${BIN_DIR}:/usr/bin:/bin" \
   REFRESH_LOG="$REFRESH_LOG" \
   WLR_RANDR_COUNT="$WLR_RANDR_COUNT" \
   WAYLAND_INFO_COUNT="$WAYLAND_INFO_COUNT" \
   LABWC_OUTPUT_TEST_MONOTONIC="${BIN_DIR}/test-monotonic-seconds" \
   LABWC_OUTPUT_TEST_MONOTONIC_COUNT="$monotonic_count" \
   WLR_RANDR_MODE=error-output \
   WAYLAND_INFO_MODE=none \
   /bin/sh "$bounded_script" --wait-for-output >/dev/null 2>&1; then
  printf 'not ok 12 - readiness rejects output text from a failed output-management probe\n'
  exit 1
else
  if [ ! -s "$REFRESH_LOG" ]; then
    printf 'ok 12 - readiness rejects output text from a failed output-management probe\n'
  else
    printf 'not ok 12 - readiness rejects output text from a failed output-management probe\n'
    exit 1
  fi
fi
