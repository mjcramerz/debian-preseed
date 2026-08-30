#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)

TEST_COUNT=15
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

TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/desktop-template-render.XXXXXX")
TARGET_ROOT="${TMP_ROOT}/target-root"
TMP_ENV_DIR="${TMP_ROOT}/tmp-env"
mkdir -p "$TARGET_ROOT" "$TMP_ENV_DIR"

trap 'rm -rf -- "$TMP_ROOT"' EXIT

INSTALLER_SOURCE_ROOT="$ROOT_DIR/d-i/forky"
INSTALLER_TARGET_DIR="$TARGET_ROOT"
export INSTALLER_SOURCE_ROOT INSTALLER_TARGET_DIR TMP_ENV_DIR
INSTALLER_REPO_ENV_READY=1
DIR_HOOKS_ROLE_DESKTOP=hooks/role/desktop
DIR_HOOKS_SHARED_TARGET=hooks/shared/target
INSTALLER_HOST_FAMILY=btrfs
DESKTOP_TEMPLATE_TEST_QEMU=0

# shellcheck disable=SC1090
. "$ROOT_DIR/d-i/forky/scripts/common/lib.sh"
# shellcheck disable=SC1090
. "$ROOT_DIR/d-i/forky/scripts/common/target.sh"
# shellcheck disable=SC1090
. "$ROOT_DIR/d-i/forky/scripts/late/target-assets.sh"
# shellcheck disable=SC1090
. "$ROOT_DIR/d-i/forky/scripts/desktop/detect.sh"
# shellcheck disable=SC1090
. "$ROOT_DIR/d-i/forky/scripts/desktop/labwc.sh"
# shellcheck disable=SC1090
. "$ROOT_DIR/d-i/forky/scripts/desktop/components.sh"

installer_append_log_category() {
  return 0
}

fetch_hook() {
  src=$1
  dest=$2
  install -d -m 0755 "$(dirname "$dest")"
  cp "${INSTALLER_SOURCE_ROOT%/}/${src}" "$dest"
}

installer_selected_class_reference_is_selected() {
  case "${1:-}" in
    addon/qemu)
      [ "${DESKTOP_TEMPLATE_TEST_QEMU:-0}" = 1 ]
      ;;
    addon/nvidia|addon/nvidia-legacy)
      [ "${DESKTOP_TEMPLATE_TEST_NVIDIA_SELECTED:-0}" = 1 ]
      ;;
    *)
      return 1
      ;;
  esac
}

installer_selected_class_for_purpose() {
  case "${1:-}" in
    gpu)
      printf '%s\n' "${DESKTOP_TEMPLATE_TEST_GPU_CLASS:-}"
      ;;
    *)
      return 1
      ;;
  esac
}

installer_nvidia_gpu_detected() {
  [ "${DESKTOP_TEMPLATE_TEST_NVIDIA_DETECTED:-0}" = 1 ]
}

global_session_env="$TARGET_ROOT/etc/environment.d/90-labwc-session.conf"
labwc_env="$TARGET_ROOT/etc/skel/.config/labwc/environment"
labwc_wayland_env="$TARGET_ROOT/etc/skel/.config/labwc/environment.d/10-wayland.env"
labwc_rc="$TARGET_ROOT/etc/skel/.config/labwc/rc.xml"
waybar_config="$TARGET_ROOT/etc/skel/.config/waybar/config"
waybar_style="$TARGET_ROOT/etc/skel/.config/waybar/style.css"
greeter_css="$TARGET_ROOT/etc/greetd/gtkgreet.css"
foot_config="$TARGET_ROOT/etc/skel/.config/foot/foot.ini"
kitty_config="$TARGET_ROOT/etc/skel/.config/kitty/kitty.conf"
launcher_sync="$TARGET_ROOT/usr/local/bin/labwc-sync-application-launchers"
telpoll_config="$TARGET_ROOT/etc/telpoll/telpoll.conf"

DESKTOP_TEMPLATE_TEST_GPU_CLASS=intel-uhd
DESKTOP_TEMPLATE_TEST_NVIDIA_SELECTED=0
DESKTOP_TEMPLATE_TEST_NVIDIA_DETECTED=0
LABWC_MANAGED_APP_DEFAULT_EXEC="/usr/local/bin/labwc-managed-app nvidia"
desktop_resolve_acceleration_availability
desktop_resolve_managed_app_default_exec
intel_default_exec=$LABWC_MANAGED_APP_DEFAULT_EXEC

DESKTOP_TEMPLATE_TEST_GPU_CLASS=generic
LABWC_MANAGED_APP_DEFAULT_EXEC="/usr/local/bin/labwc-managed-app nvidia"
desktop_resolve_acceleration_availability
desktop_resolve_managed_app_default_exec
neutral_default_exec=$LABWC_MANAGED_APP_DEFAULT_EXEC

DESKTOP_TEMPLATE_TEST_NVIDIA_SELECTED=1
DESKTOP_TEMPLATE_TEST_NVIDIA_DETECTED=1
LABWC_MANAGED_APP_DEFAULT_EXEC="/usr/local/bin/labwc-managed-app nvidia"
desktop_resolve_acceleration_availability
desktop_resolve_managed_app_default_exec
nvidia_default_exec=$LABWC_MANAGED_APP_DEFAULT_EXEC

DESKTOP_TEMPLATE_TEST_GPU_CLASS=intel-uhd
DESKTOP_TEMPLATE_TEST_NVIDIA_SELECTED=0
DESKTOP_TEMPLATE_TEST_NVIDIA_DETECTED=0
LABWC_MANAGED_APP_DEFAULT_EXEC="/usr/local/bin/labwc-managed-app nvidia"
desktop_resolve_acceleration_availability
desktop_resolve_managed_app_default_exec

if [ "$intel_default_exec" = "/usr/local/bin/labwc-managed-app intel" ] &&
   [ "$neutral_default_exec" = "/usr/local/bin/labwc-managed-app launch" ] &&
   [ "$nvidia_default_exec" = "/usr/local/bin/labwc-managed-app nvidia" ] &&
   [ "$LABWC_MANAGED_APP_DEFAULT_EXEC" = "/usr/local/bin/labwc-managed-app intel" ]; then
  pass "managed default launchers resolve NVIDIA preferences to selected accelerator availability"
else
  fail "managed default launchers resolve NVIDIA preferences to selected accelerator availability"
fi

desktop_render_role_target_template \
  usr/local/bin/labwc-sync-application-launchers \
  /usr/local/bin/labwc-sync-application-launchers \
  0755 \
  LABWC_MANAGED_APP_DEFAULT_EXEC "$LABWC_MANAGED_APP_DEFAULT_EXEC"

if [ -x "$launcher_sync" ] &&
   ! grep -q '__INSTALLER_' "$launcher_sync" &&
   grep -q '^MANAGED_APP_DEFAULT_EXEC = "/usr/local/bin/labwc-managed-app intel"$' "$launcher_sync" &&
   python3 -m py_compile "$launcher_sync"; then
  pass "managed launcher synchronizer renders the profile-owned default Exec command"
else
  fail "managed launcher synchronizer renders the profile-owned default Exec command"
fi

DESKTOP_TEMPLATE_TEST_GPU_CLASS=generic
DESKTOP_TEMPLATE_TEST_NVIDIA_SELECTED=1
DESKTOP_TEMPLATE_TEST_NVIDIA_DETECTED=1
LABWC_MANAGED_APP_DEFAULT_EXEC="/usr/local/bin/labwc-managed-app nvidia"
desktop_resolve_acceleration_availability
desktop_resolve_managed_app_default_exec
desktop_render_waybar_config

if [ -r "$waybar_config" ] &&
   jq empty "$waybar_config" &&
   jq -e 'all(.[]; .["custom/app-tuta"]["on-click"] == "/usr/local/bin/labwc-managed-app nvidia tutanota")' "$waybar_config" >/dev/null &&
   jq -e 'all(.[]; .["custom/app-sleek"]["on-click"] == "/usr/local/bin/labwc-managed-app nvidia sleek")' "$waybar_config" >/dev/null; then
  pass "Waybar renders NVIDIA application actions only for selected and detected NVIDIA hardware"
else
  fail "Waybar renders NVIDIA application actions only for selected and detected NVIDIA hardware"
fi

DESKTOP_TEMPLATE_TEST_GPU_CLASS=intel-uhd
DESKTOP_TEMPLATE_TEST_NVIDIA_SELECTED=0
DESKTOP_TEMPLATE_TEST_NVIDIA_DETECTED=0
LABWC_MANAGED_APP_DEFAULT_EXEC="/usr/local/bin/labwc-managed-app nvidia"
desktop_resolve_acceleration_availability
desktop_resolve_managed_app_default_exec

if (
  desktop_validate_managed_app_default_exec \
    LABWC_MANAGED_APP_DEFAULT_EXEC \
    "/usr/bin/env python3"
) >/dev/null 2>&1; then
  fail "managed app default Exec validation rejects non-wrapper commands"
else
  pass "managed app default Exec validation rejects non-wrapper commands"
fi

unset LABWC_GSK_RENDERER
desktop_render_labwc_environment_assets

if [ ! -e "$global_session_env" ] &&
   [ -r "$labwc_env" ] &&
   [ -r "$labwc_wayland_env" ] &&
   ! grep -q '__INSTALLER_' "$labwc_env" &&
   ! grep -q '__INSTALLER_' "$labwc_wayland_env" &&
   grep -q '^GSK_RENDERER=opengl$' "$labwc_env" &&
   grep -q '^GSK_RENDERER=opengl$' "$labwc_wayland_env" &&
   grep -q '^ANGLE_DEFAULT_PLATFORM=gl$' "$labwc_env" &&
   grep -q '^ANGLE_DEFAULT_PLATFORM=gl$' "$labwc_wayland_env" &&
   grep -q '^WGPU_BACKEND=gl$' "$labwc_env" &&
   grep -q '^WGPU_BACKEND=gl$' "$labwc_wayland_env" &&
   grep -q '^SDL_RENDER_DRIVER=opengl$' "$labwc_env" &&
   grep -q '^SDL_RENDER_DRIVER=opengl$' "$labwc_wayland_env" &&
   grep -q '^QT_WAYLAND_DISABLE_WINDOWDECORATION=1$' "$labwc_env" &&
   grep -q '^QT_WAYLAND_DISABLE_WINDOWDECORATION=1$' "$labwc_wayland_env" &&
   grep -q '^GTK_CSD=0$' "$labwc_env" &&
   grep -q '^GTK_CSD=0$' "$labwc_wayland_env"; then
  pass "Labwc environment assets render the managed OpenGL default when GSK_RENDERER is unset"
else
  fail "Labwc environment assets render the managed OpenGL default when GSK_RENDERER is unset"
fi

LABWC_GSK_RENDERER=ngl
desktop_render_labwc_environment_assets

if [ ! -e "$global_session_env" ] &&
   grep -q '^GSK_RENDERER=ngl$' "$labwc_env" &&
   grep -q '^GSK_RENDERER=ngl$' "$labwc_wayland_env" &&
   ! grep -q '__INSTALLER_' "$labwc_env" &&
   ! grep -q '__INSTALLER_' "$labwc_wayland_env"; then
  pass "Labwc environment assets render the optional GSK_RENDERER line when requested"
else
  fail "Labwc environment assets render the optional GSK_RENDERER line when requested"
fi

desktop_render_labwc_rc_xml

if [ -r "$labwc_rc" ] &&
   ! grep -q '__INSTALLER_' "$labwc_rc" &&
   ! grep -q 'xwaylandPersistence' "$labwc_rc" &&
   ! grep -q 'xwaylandPersistence' "$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/share/labwc-greeter/rc.xml" &&
   grep -q '<autoEnableOutputs>no</autoEnableOutputs>' "$labwc_rc" &&
   grep -q '<number>4</number>' "$labwc_rc" &&
   grep -q '<name>1</name>' "$labwc_rc" &&
   grep -q '<name>4</name>' "$labwc_rc" &&
   grep -q '<action name="GoToDesktop" to="4" />' "$labwc_rc"; then
  pass "Labwc rc.xml resolves workspace block placeholders before install-time validation"
else
  fail "Labwc rc.xml resolves workspace block placeholders before install-time validation"
fi

DESKTOP_TEMPLATE_TEST_QEMU=0
desktop_render_waybar_config

if [ -r "$waybar_config" ] &&
   jq empty "$waybar_config" &&
   ! grep -q '__INSTALLER_' "$waybar_config" &&
   grep -q '"expand-left": true' "$waybar_config" &&
   grep -q '"expand": true' "$waybar_config" &&
   grep -q '"sort-by-app-id": true' "$waybar_config" &&
   grep -q '"tooltip-format": "{title}"' "$waybar_config" &&
   jq -e 'all(.[]; .["wlr/taskbar"]["on-click"] == "minimize-raise" and .["wlr/taskbar"]["on-click-middle"] == "close" and .["wlr/taskbar"]["on-click-right"] == "minimize-raise")' "$waybar_config" >/dev/null &&
   grep -q '"modules-left": \["custom/launcher", "ext/workspaces", "custom/wayscriber", "group/apps", "wlr/taskbar"\],' "$waybar_config" &&
   grep -q '"modules-right": \["pulseaudio", "custom/backlight", "battery", "disk", "cpu", "memory", "tray", "group/quick-controls", "custom/lock", "custom/power"\],' "$waybar_config" &&
   grep -q '"modules-right": \["pulseaudio", "custom/backlight", "battery", "disk", "cpu", "memory", "tray", "group/quick-controls-internal", "custom/lock", "custom/power"\],' "$waybar_config" &&
   jq -e 'type == "array" and length == 2 and .[0].name == "internal" and .[1].name == "external"' "$waybar_config" >/dev/null &&
   jq -e 'any(.[0].output[]; . == "eDP-1") and any(.[0].output[]; . == "LVDS-1") and any(.[0].output[]; . == "DSI-1")' "$waybar_config" >/dev/null &&
   jq -e 'any(.[1].output[]; . == "!eDP-1") and any(.[1].output[]; . == "!LVDS-1") and any(.[1].output[]; . == "!DSI-1") and .[1].output[-1] == "*"' "$waybar_config" >/dev/null &&
   jq -e 'all(.[]; .["group/apps"] == {"orientation":"inherit","drawer":{"transition-duration":250,"transition-left-to-right":true,"click-to-reveal":true},"modules":["custom/apps","custom/app-terminal","custom/app-files","custom/app-tuta","custom/app-notes","custom/app-sleek"]})' "$waybar_config" >/dev/null &&
   jq -e 'all(.[]; (has("custom/tasks") | not))' "$waybar_config" >/dev/null &&
   jq -e 'all(.[]; .["custom/wayscriber"] == {"format":"","tooltip":true,"tooltip-format":"Wayscriber","on-click":"labwc-wayscriber-toggle"})' "$waybar_config" >/dev/null &&
   jq -e 'all(.[]; .["custom/apps"] == {"format":"","tooltip":true,"tooltip-format":"Applications"})' "$waybar_config" >/dev/null &&
   jq -e 'all(.[]; .["custom/app-terminal"] == {"format":"","tooltip":true,"tooltip-format":"Foot","on-click":"labwc-terminal"})' "$waybar_config" >/dev/null &&
   jq -e 'all(.[]; .["custom/app-files"] == {"format":"","tooltip":true,"tooltip-format":"Thunar","on-click":"thunar"})' "$waybar_config" >/dev/null &&
   jq --arg command "${LABWC_MANAGED_APP_DEFAULT_EXEC} tutanota" -e 'all(.[]; .["custom/app-tuta"] == {"format":"","tooltip":true,"tooltip-format":"Tuta Mail","on-click":$command})' "$waybar_config" >/dev/null &&
   jq -e 'all(.[]; .["custom/app-notes"] == {"format":"","tooltip":true,"tooltip-format":"FeatherPad","on-click":"featherpad"})' "$waybar_config" >/dev/null &&
   jq --arg command "${LABWC_MANAGED_APP_DEFAULT_EXEC} sleek" -e 'all(.[]; .["custom/app-sleek"] == {"format":"","tooltip":true,"tooltip-format":"Sleek","on-click":$command})' "$waybar_config" >/dev/null &&
   jq -e 'all(.[]; .battery.interval == 5 and .battery["format-plugged"] == "🔌 {capacity}%" and .battery["format-not-charging"] == "🔌 {capacity}%")' "$waybar_config" >/dev/null &&
   jq -e 'all(.[]; .["group/quick-controls"] == {"orientation":"inherit","drawer":{"transition-duration":300,"transition-left-to-right":false,"click-to-reveal":true},"modules":["custom/system","network","custom/bluetooth","custom/keyboard","custom/screenshot"]})' "$waybar_config" >/dev/null &&
   jq -e '.[0].["group/quick-controls-internal"] == {"orientation":"inherit","drawer":{"transition-duration":300,"transition-left-to-right":false,"click-to-reveal":true},"modules":["custom/system","network","custom/bluetooth","custom/keyboard","custom/screenshot"]} and (.[1] | has("group/quick-controls-internal") | not)' "$waybar_config" >/dev/null &&
   jq -e 'all(.[]; .["custom/system"] == {"format":"","tooltip":true,"tooltip-format":"System controls"})' "$waybar_config" >/dev/null &&
   ! grep -q '"image#app-' "$waybar_config" &&
   ! grep -q '"custom/files"' "$waybar_config" &&
   ! grep -q '"custom/terminal"' "$waybar_config" &&
   ! grep -q '"custom/dnd"' "$waybar_config" &&
   ! grep -q '"custom/sandbox-menu"' "$waybar_config" &&
   ! grep -q '"custom/sandbox-state"' "$waybar_config"; then
  pass "Waybar config renders the requested pre-lock controls without retired modules"
else
  fail "Waybar config renders the requested pre-lock controls without retired modules"
fi

DESKTOP_TEMPLATE_TEST_QEMU=1
desktop_render_waybar_config

if [ -r "$waybar_config" ] &&
   jq empty "$waybar_config" &&
   ! grep -q '__INSTALLER_' "$waybar_config" &&
   grep -q '"expand-left": true' "$waybar_config" &&
   grep -q '"expand": true' "$waybar_config" &&
   grep -q '"sort-by-app-id": true' "$waybar_config" &&
   grep -q '"tooltip-format": "{title}"' "$waybar_config" &&
   jq -e 'all(.[]; .["wlr/taskbar"]["on-click"] == "minimize-raise" and .["wlr/taskbar"]["on-click-middle"] == "close" and .["wlr/taskbar"]["on-click-right"] == "minimize-raise")' "$waybar_config" >/dev/null &&
   grep -q '"modules-left": \["custom/launcher", "ext/workspaces", "custom/wayscriber", "group/apps", "wlr/taskbar"\],' "$waybar_config" &&
   grep -q '"modules-right": \["pulseaudio", "custom/backlight", "battery", "disk", "cpu", "memory", "tray", "group/quick-controls", "custom/lock", "custom/power"\],' "$waybar_config" &&
   grep -q '"modules-right": \["pulseaudio", "custom/backlight", "battery", "disk", "cpu", "memory", "tray", "group/quick-controls-internal", "custom/lock", "custom/power"\],' "$waybar_config" &&
   jq -e 'type == "array" and length == 2 and .[0].name == "internal" and .[1].name == "external"' "$waybar_config" >/dev/null &&
   jq -e 'any(.[0].output[]; . == "eDP-1") and any(.[0].output[]; . == "LVDS-1") and any(.[0].output[]; . == "DSI-1")' "$waybar_config" >/dev/null &&
   jq -e 'any(.[1].output[]; . == "!eDP-1") and any(.[1].output[]; . == "!LVDS-1") and any(.[1].output[]; . == "!DSI-1") and .[1].output[-1] == "*"' "$waybar_config" >/dev/null &&
   jq -e 'all(.[]; .["group/apps"] == {"orientation":"inherit","drawer":{"transition-duration":250,"transition-left-to-right":true,"click-to-reveal":true},"modules":["custom/apps","custom/app-terminal","custom/app-files","custom/app-tuta","custom/app-notes","custom/app-sleek"]})' "$waybar_config" >/dev/null &&
   jq -e 'all(.[]; (has("custom/tasks") | not))' "$waybar_config" >/dev/null &&
   jq -e 'all(.[]; .["custom/wayscriber"] == {"format":"","tooltip":true,"tooltip-format":"Wayscriber","on-click":"labwc-wayscriber-toggle"})' "$waybar_config" >/dev/null &&
   jq -e 'all(.[]; .["custom/apps"] == {"format":"","tooltip":true,"tooltip-format":"Applications"})' "$waybar_config" >/dev/null &&
   jq -e 'all(.[]; .["custom/app-terminal"] == {"format":"","tooltip":true,"tooltip-format":"Foot","on-click":"labwc-terminal"})' "$waybar_config" >/dev/null &&
   jq -e 'all(.[]; .["custom/app-files"] == {"format":"","tooltip":true,"tooltip-format":"Thunar","on-click":"thunar"})' "$waybar_config" >/dev/null &&
   jq --arg command "${LABWC_MANAGED_APP_DEFAULT_EXEC} tutanota" -e 'all(.[]; .["custom/app-tuta"] == {"format":"","tooltip":true,"tooltip-format":"Tuta Mail","on-click":$command})' "$waybar_config" >/dev/null &&
   jq -e 'all(.[]; .["custom/app-notes"] == {"format":"","tooltip":true,"tooltip-format":"FeatherPad","on-click":"featherpad"})' "$waybar_config" >/dev/null &&
   jq --arg command "${LABWC_MANAGED_APP_DEFAULT_EXEC} sleek" -e 'all(.[]; .["custom/app-sleek"] == {"format":"","tooltip":true,"tooltip-format":"Sleek","on-click":$command})' "$waybar_config" >/dev/null &&
   jq -e 'all(.[]; .battery.interval == 5 and .battery["format-plugged"] == "🔌 {capacity}%" and .battery["format-not-charging"] == "🔌 {capacity}%")' "$waybar_config" >/dev/null &&
   jq -e 'all(.[]; .["group/quick-controls"] == {"orientation":"inherit","drawer":{"transition-duration":300,"transition-left-to-right":false,"click-to-reveal":true},"modules":["custom/system","network","custom/bluetooth","custom/keyboard","custom/screenshot"]})' "$waybar_config" >/dev/null &&
   jq -e '.[0].["group/quick-controls-internal"] == {"orientation":"inherit","drawer":{"transition-duration":300,"transition-left-to-right":false,"click-to-reveal":true},"modules":["custom/system","network","custom/bluetooth","custom/keyboard","custom/screenshot"]} and (.[1] | has("group/quick-controls-internal") | not)' "$waybar_config" >/dev/null &&
   jq -e 'all(.[]; .["custom/system"] == {"format":"","tooltip":true,"tooltip-format":"System controls"})' "$waybar_config" >/dev/null &&
   ! grep -q '"image#app-' "$waybar_config" &&
   ! grep -q '"custom/files"' "$waybar_config" &&
   ! grep -q '"custom/terminal"' "$waybar_config" &&
   ! grep -q '"custom/dnd"' "$waybar_config" &&
   ! grep -q '"custom/sandbox-menu"' "$waybar_config" &&
   ! grep -q '"custom/sandbox-state"' "$waybar_config"; then
  pass "qemu selection no longer changes the Waybar module set"
else
  fail "qemu selection no longer changes the Waybar module set"
fi

LABWC_OUTPUT_INTERNAL_PREFIXES="Panel eDP"
desktop_render_waybar_config

if [ -r "$waybar_config" ] &&
   jq empty "$waybar_config" &&
   jq -e 'any(.[0].output[]; . == "Panel-1") and any(.[0].output[]; . == "Panel1") and any(.[0].output[]; . == "eDP-1")' "$waybar_config" >/dev/null &&
   jq -e 'any(.[1].output[]; . == "!Panel-1") and any(.[1].output[]; . == "!Panel1") and any(.[1].output[]; . == "!eDP-1") and .[1].output[-1] == "*"' "$waybar_config" >/dev/null &&
   jq -e '.[0].["group/quick-controls-internal"].drawer["click-to-reveal"] == true and .[0].["group/quick-controls-internal"].modules[0] == "custom/system"' "$waybar_config" >/dev/null &&
   jq -e '.[1].["group/quick-controls"].drawer == {"transition-duration":300,"transition-left-to-right":false,"click-to-reveal":true} and .[1].["group/quick-controls"].modules == ["custom/system","network","custom/bluetooth","custom/keyboard","custom/screenshot"] and .[1].["custom/system"] == {"format":"","tooltip":true,"tooltip-format":"System controls"}' "$waybar_config" >/dev/null; then
  pass "Waybar output selectors follow the detected internal-prefix contract"
else
  fail "Waybar output selectors follow the detected internal-prefix contract"
fi
unset LABWC_OUTPUT_INTERNAL_PREFIXES

desktop_render_waybar_style

if [ -r "$waybar_style" ] &&
   ! grep -q '__INSTALLER_' "$waybar_style" &&
   grep -q '^  min-width: 52px;$' "$waybar_style" &&
   grep -q '^  padding: 0 11px;$' "$waybar_style" &&
   grep -q '^#taskbar {$' "$waybar_style" &&
   grep -q '^  min-width: 0;$' "$waybar_style" &&
   grep -q '^  padding: 0 4px;$' "$waybar_style" &&
   grep -q '^#apps {$' "$waybar_style" &&
   grep -A2 '^#apps {$' "$waybar_style" | grep -q '^  background: transparent;$' &&
   grep -q '^#custom-apps {$' "$waybar_style" &&
   grep -A5 '^#custom-apps {$' "$waybar_style" | grep -q '^  min-width: 28px;$' &&
   grep -A5 '^#custom-apps {$' "$waybar_style" | grep -q '^  padding: 0 7px;$' &&
   grep -A5 '^#custom-apps {$' "$waybar_style" | grep -q '^  color: @royalpurple;$' &&
   ! grep -q '^#custom-tasks' "$waybar_style" &&
   grep -q '^#custom-wayscriber {$' "$waybar_style" &&
   grep -A5 '^#custom-wayscriber {$' "$waybar_style" | grep -q '^  color: @marineblue;$' &&
   grep -q '^#custom-app-terminal,$' "$waybar_style" &&
   grep -q '^#custom-app-files,$' "$waybar_style" &&
   grep -q '^#custom-app-tuta,$' "$waybar_style" &&
   grep -q '^#custom-app-notes,$' "$waybar_style" &&
   grep -q '^#custom-app-sleek {$' "$waybar_style" &&
   grep -A10 '^#custom-app-terminal,$' "$waybar_style" | grep -q '^  min-width: 28px;$' &&
   grep -A10 '^#custom-app-terminal,$' "$waybar_style" | grep -q '^  font-weight: 900;$' &&
   ! grep -q '^#image' "$waybar_style" &&
   grep -A8 '^#quick-controls,$' "$waybar_style" | grep -q '^  background: @panel_alt;$' &&
   grep -A8 '^#quick-controls,$' "$waybar_style" | grep -q '^  border: 1px solid @border;$' &&
   grep -A8 '^#quick-controls,$' "$waybar_style" | grep -q '^  border-radius: 999px;$' &&
   grep -A8 '^#quick-controls,$' "$waybar_style" | grep -q '^  margin: 5px 1px;$' &&
   ! grep -q '^#quick-controls:hover,$' "$waybar_style" &&
   ! grep -q '^#quick-controls-internal:hover {$' "$waybar_style" &&
   grep -q '^#quick-controls-internal {$' "$waybar_style" &&
   grep -q '^#quick-controls #custom-system,$' "$waybar_style" &&
   grep -q '^#quick-controls #network,$' "$waybar_style" &&
   grep -A19 '^#quick-controls #custom-system,$' "$waybar_style" | grep -q '^  min-width: 28px;$' &&
   grep -A19 '^#quick-controls #custom-system,$' "$waybar_style" | grep -q '^  margin: 0;$' &&
   grep -A19 '^#quick-controls #custom-system,$' "$waybar_style" | grep -q '^  border: 1px solid transparent;$' &&
   grep -A19 '^#quick-controls #custom-system,$' "$waybar_style" | grep -q '^  border-radius: 999px;$' &&
   grep -A19 '^#quick-controls #custom-system,$' "$waybar_style" | grep -q '^  background: transparent;$' &&
   grep -A19 '^#quick-controls #custom-system,$' "$waybar_style" | grep -q '^  font-size: 15px;$' &&
   grep -q '^#quick-controls #custom-system:hover,$' "$waybar_style" &&
   grep -q '^#quick-controls #network:hover,$' "$waybar_style" &&
   grep -q '^#quick-controls #custom-bluetooth:hover,$' "$waybar_style" &&
   grep -q '^#quick-controls-internal #custom-screenshot:hover {$' "$waybar_style" &&
   grep -A13 '^#quick-controls #custom-system:hover,$' "$waybar_style" | grep -q '^  background: @panel_hover;$' &&
   grep -A13 '^#quick-controls #custom-system:hover,$' "$waybar_style" | grep -q '^  border-color: @border;$' &&
   grep -q '^window#waybar.internal #pulseaudio,$' "$waybar_style" &&
   grep -A12 '^window#waybar.internal #pulseaudio,$' "$waybar_style" | grep -q '^  padding-left: 4px;$' &&
   grep -A7 '^window#waybar.internal #pulseaudio,$' "$waybar_style" | grep -q '^  min-width: 46px;$' &&
   grep -A6 '^window#waybar.internal #quick-controls-internal {$' "$waybar_style" | grep -q '^  padding-left: 1px;$' &&
   grep -A6 '^window#waybar.internal #quick-controls-internal {$' "$waybar_style" | grep -q '^  padding-right: 1px;$' &&
   grep -A9 '^window#waybar.internal #quick-controls-internal #custom-system,$' "$waybar_style" | grep -q '^  min-width: 22px;$' &&
   ! grep -q '^window#waybar.internal #quick-controls-internal #custom-system {$' "$waybar_style" &&
   grep -A5 '^window#waybar.internal #custom-lock,$' "$waybar_style" | grep -q '^  min-width: 24px;$' &&
   grep -q '^#custom-system {$' "$waybar_style" &&
   grep -A5 '^#custom-system {$' "$waybar_style" | grep -q '^  color: @amber;$' &&
   grep -A5 '^#custom-system {$' "$waybar_style" | grep -Fq '  font-family: "Font Awesome 6 Free", "Font Awesome 5 Free", "Noto Sans Symbols 2", "Symbola";' &&
   grep -A7 '^#custom-lock {$' "$waybar_style" | grep -q '^  background: rgba(203, 213, 225, 0.14);$' &&
   grep -A7 '^#custom-lock {$' "$waybar_style" | grep -q '^  border-color: rgba(203, 213, 225, 0.46);$' &&
   grep -A7 '^#custom-lock {$' "$waybar_style" | grep -q '^  color: #d8dee9;$'; then
  pass "Waybar style renders compact launcher and shrinkable taskbar controls"
else
  fail "Waybar style renders compact launcher and shrinkable taskbar controls"
fi

desktop_render_gtkgreet_css

if [ -r "$greeter_css" ] &&
   ! grep -q '__INSTALLER_' "$greeter_css" &&
   grep -q '^  font-size: 104px;$' "$greeter_css" &&
   grep -q '^box#body entry#input-field {$' "$greeter_css" &&
   grep -q '^  font-size: 20px;$' "$greeter_css" &&
   grep -q '^box#body combobox#command-selector {$' "$greeter_css" &&
   grep -q '^box#body button {$' "$greeter_css" &&
   grep -q '^  background-color: #374151;$' "$greeter_css" &&
   grep -q '^box#body button.suggested-action {$' "$greeter_css" &&
   grep -q '^  background-color: #1d4ed8;$' "$greeter_css"; then
  pass "gtkgreet style renders larger login controls and a prominent clock"
else
  fail "gtkgreet style renders larger login controls and a prominent clock"
fi

LABWC_TERMINAL_FONT_FAMILY="JetBrains Mono"
LABWC_TERMINAL_FONT_SIZE="13"
desktop_render_terminal_configs

if [ -r "$foot_config" ] &&
   [ -r "$kitty_config" ] &&
   ! grep -q '__INSTALLER_' "$foot_config" &&
   ! grep -q '__INSTALLER_' "$kitty_config" &&
   grep -q '^font=JetBrains Mono:size=13$' "$foot_config" &&
   grep -q '^font_family JetBrains Mono$' "$kitty_config" &&
   grep -q '^font_size 13$' "$kitty_config"; then
  pass "Foot and Kitty render the profile-owned terminal font family and size"
else
  fail "Foot and Kitty render the profile-owned terminal font family and size"
fi

. "$ROOT_DIR/d-i/forky/hosts/profiles/override/f2fs-de-cbook.env"
desktop_render_qt6ct_config
qt6ct_skel="$TARGET_ROOT/etc/skel/.config/qt6ct/qt6ct.conf"
qt6ct_xdg="$TARGET_ROOT/etc/xdg/qt6ct/qt6ct.conf"

if [ -r "$qt6ct_skel" ] &&
   [ -r "$qt6ct_xdg" ] &&
   ! grep -q '__INSTALLER_' "$qt6ct_skel" &&
   ! grep -q '__INSTALLER_' "$qt6ct_xdg" &&
   grep -q '^icon_theme=Papirus-Dark$' "$qt6ct_skel" &&
   grep -q '^icon_theme=Papirus-Dark$' "$qt6ct_xdg" &&
   grep -q '^fixed="Noto Sans Mono,10,-1,5,50,0,0,0,0,0"$' "$qt6ct_skel" &&
   grep -q '^general="Noto Sans,9,-1,5,50,0,0,0,0,0"$' "$qt6ct_skel"; then
  pass "f2fs-de-cbook renders compact Qt fonts and the managed Papirus theme"
else
  fail "f2fs-de-cbook renders compact Qt fonts and the managed Papirus theme"
fi

unset TELPOLL_ENABLED
desktop_resolve_telpoll_policy
desktop_render_telpoll_config
telpoll_default_ok=false
if [ "$TELPOLL_ENABLED" = false ] &&
   grep -Fqx 'TELPOLL_ENABLED=false' "$telpoll_config" &&
   grep -Fqx 'TELPOLL_OWNERSHIP_CONFLICT_BACKOFF_SECONDS=900' "$telpoll_config" &&
   ! grep -q '__INSTALLER_' "$telpoll_config"; then
  telpoll_default_ok=true
fi

TELPOLL_ENABLED=true
desktop_render_telpoll_config
desktop_profile_count=0
telpoll_owner_count=0
telpoll_owner=
for profile in $(find "$ROOT_DIR/d-i/forky/hosts/profiles" -type f -name '*.env' -print | sort); do
  grep -Fqx 'LABWC_DESKTOP_ENABLE="true"' "$profile" || continue
  desktop_profile_count=$((desktop_profile_count + 1))
  if grep -q '^TELPOLL_ENABLED=' "$profile"; then
    telpoll_owner_count=$((telpoll_owner_count + 1))
    telpoll_owner=$profile
  fi
done

if [ "$telpoll_default_ok" = true ] &&
   grep -Fqx 'TELPOLL_ENABLED=true' "$telpoll_config" &&
   [ "$desktop_profile_count" -eq 13 ] &&
   [ "$telpoll_owner_count" -eq 1 ] &&
   [ "$telpoll_owner" = "$ROOT_DIR/d-i/forky/hosts/profiles/override/btrfs-de-main.env" ] &&
   grep -Fq 'etc/telpoll/telpoll.conf.tmpl' "$ROOT_DIR/d-i/forky/scripts/desktop/components.sh" &&
   ! grep -Fq 'desktop_stage_role_asset etc/telpoll/telpoll.conf ' "$ROOT_DIR/d-i/forky/scripts/desktop/components.sh" &&
   ! grep -Eq '^[[:space:]]+telpoll[.]service[[:space:]]+\\$' "$ROOT_DIR/d-i/forky/scripts/desktop/components.sh" &&
   grep -Fqx '  if [ "$TELPOLL_ENABLED" = true ]; then' "$ROOT_DIR/d-i/forky/scripts/desktop/components.sh" &&
   grep -Fqx '    desktop_stage_user_unit_wanted_by telpoll.service labwc-session.target' "$ROOT_DIR/d-i/forky/scripts/desktop/components.sh" &&
   ! (TELPOLL_ENABLED=yes; desktop_resolve_telpoll_policy) >/dev/null 2>&1; then
  pass "telpoll defaults off, is enabled only by btrfs-de-main, and renders conditional ownership policy"
else
  fail "telpoll defaults off, is enabled only by btrfs-de-main, and renders conditional ownership policy"
fi

[ "$FAIL_COUNT" -eq 0 ]
