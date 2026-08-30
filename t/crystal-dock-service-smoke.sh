#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
SERVICE="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/systemd/user/crystal-dock.service"
SESSION="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-session.tmpl"
AUTOSTART="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-autostart"
RC_XML="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/labwc/rc.xml.tmpl"
MENU_XML="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/labwc/menu.xml"
MANAGEMENT="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-computer-management"
COMPONENTS="$ROOT_DIR/d-i/forky/scripts/desktop/components.sh"

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

if [ ! -e "$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-dock" ] &&
   [ ! -e "$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/libexec/labwc-dock" ] &&
   ! grep -Fq 'usr/local/bin/labwc-dock' "$COMPONENTS" &&
   ! grep -Fq 'usr/local/libexec/labwc-dock' "$COMPONENTS"; then
  pass "obsolete Crystal Dock wrapper entrypoints are absent"
else
  fail "obsolete Crystal Dock wrapper entrypoints are absent"
fi

if grep -Fxq 'ConditionEnvironment=LABWC_SESSION_OWNER=desktop' "$SERVICE" &&
   grep -Fxq 'ConditionEnvironment=XDG_SESSION_TYPE=wayland' "$SERVICE" &&
   grep -Fxq 'ConditionFileIsExecutable=/usr/bin/crystal-dock' "$SERVICE" &&
   grep -Fxq 'ExecStartPre=/usr/local/bin/labwc-sync-application-launchers %u %h' "$SERVICE" &&
   grep -Fxq 'ExecStart=/usr/bin/crystal-dock' "$SERVICE" &&
   grep -Fxq 'Environment=QT_QPA_PLATFORM=wayland' "$SERVICE" &&
   grep -Fxq 'Environment=GDK_DISABLE=vulkan' "$SERVICE" &&
   grep -Fxq 'Environment=QSG_RHI_BACKEND=opengl' "$SERVICE" &&
   grep -Fxq 'KillMode=process' "$SERVICE" &&
   grep -Fxq 'StandardOutput=null' "$SERVICE" &&
   grep -Fxq 'StandardError=null' "$SERVICE" &&
   ! grep -Eq 'ExecStart=.*/(labwc-dock|sh)([[:space:]]|$)' "$SERVICE" &&
   ! grep -Eq 'XDG_(CONFIG|CACHE|DATA|STATE)_HOME=' "$SERVICE" &&
   ! grep -Eq 'ozone-platform=x11|XDG_SESSION_TYPE=x11|QT_QPA_PLATFORM=xcb' "$SERVICE"; then
  pass "Crystal Dock is a direct Wayland-only user service with Vulkan-disabled child defaults"
else
  fail "Crystal Dock is a direct Wayland-only user service with Vulkan-disabled child defaults"
fi

if ! grep -R -Fq -- 'LABWC_ENABLE_CRYSTAL_DOCK' \
     "$ROOT_DIR/d-i/forky/hooks/role/desktop/target" \
     "$ROOT_DIR/d-i/forky/scripts/desktop" \
     "$ROOT_DIR/d-i/forky/hosts/profiles" &&
   ! grep -Fxq 'ConditionPathExists=%h/.config/crystal-dock/labwc/panel_1.conf' "$SERVICE" &&
   grep -Fq '[ -n "${WAYLAND_DISPLAY:-}" ]' "$SERVICE" &&
   grep -Fq '/usr/bin/systemctl --user --quiet is-active labwc-session.target' "$SERVICE"; then
  pass "Crystal Dock always uses the active Labwc session and staged XDG defaults"
else
  fail "Crystal Dock always uses the active Labwc session and staged XDG defaults"
fi

restart_command='/usr/bin/systemctl --user --no-block restart crystal-dock.service'
if grep -Fq "command=\"$restart_command\"" "$RC_XML" &&
   grep -Fq "command=\"$restart_command\"" "$MENU_XML" &&
   grep -Fq 'run_command systemctl --user --no-block restart crystal-dock.service' "$MANAGEMENT"; then
  pass "all dock restart actions address the user service directly"
else
  fail "all dock restart actions address the user service directly"
fi

if [ "$TEST_INDEX" -ne "$TEST_COUNT" ]; then
  printf 'not ok - planned %s tests but executed %s\n' "$TEST_COUNT" "$TEST_INDEX"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

[ "$FAIL_COUNT" -eq 0 ]
