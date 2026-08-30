#!/bin/sh
# This smoke test intentionally matches literal shell expansions in source.
# shellcheck disable=SC2016
set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
SESSION="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-session.tmpl"
GREETER_SESSION="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-greeter-session.tmpl"
AUTOSTART="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-autostart"
GREETER_CLIENT="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/libexec/labwc-greeter-client"
LABWC_WAYLAND_ENVIRONMENT="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/labwc/environment.d/10-wayland.env.tmpl"
OUTPUT_WATCH="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/libexec/labwc-output-watch"
OUTPUT_WATCH_UNIT="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/systemd/user/labwc-output-watch.service"
PAM_GREETD="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/pam.d/greetd"
GREETD_SERVICE_DROPIN="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/systemd/system/greetd.service.d/20-labwc-vt.conf"
SESSION_TARGET="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/systemd/user/labwc-session.target"
COMPOSITOR_UNIT="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/systemd/user/labwc-compositor.service"
USER_MANAGER_SEATD_DROPIN="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/systemd/system/user@.service.d/20-labwc-seatd.conf"
PORTAL_DROPIN_ROOT="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/systemd/user"
APPARMOR="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/managed-desktop-wrappers"
DBUS_USER_HARDENING_TEMPLATE="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/systemd/user/dbus-broker.service.d/10-broker-hardening.conf.tmpl"
LEGACY_DBUS_USER_HARDENING_TEMPLATE="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/systemd/user/dbus-broker.service.d/10-broker-hardening.conf.tmpl"
DESKTOP_COMPONENTS="$ROOT_DIR/d-i/forky/scripts/desktop/components.sh"
DBUS_LATE="$ROOT_DIR/d-i/forky/scripts/late/dbus-broker.sh"
RUNTIME_ENV="$ROOT_DIR/d-i/forky/hosts/shared/runtime.env"
FIRSTBOOT_VALIDATION="$ROOT_DIR/d-i/forky/scripts/firstboot/04-validation.sh"
x11_environment_names='DISPLAY XAUTHORITY WLR_XWAYLAND XWAYLAND XWAYLAND_PATH XWAYLAND_NO_GLAMOR XWAYLAND_FORCE_SCALE XWAYLAND_RESTART_DELAY _XWAYLAND_GLOBAL_OUTPUT_SCALE WINDOWID SESSION_MANAGER DESKTOP_STARTUP_ID'

tests=0
failures=0

pass() {
  tests=$((tests + 1))
  printf 'ok %s - %s\n' "$tests" "$1"
}

fail() {
  tests=$((tests + 1))
  failures=$((failures + 1))
  printf 'not ok %s - %s\n' "$tests" "$1"
}

profile_block() {
  profile_name=$1
  awk -v profile_name="$profile_name" '
    $1 == "profile" && $2 == profile_name { show = 1 }
    show { print }
    show && $0 == "}" { exit }
  ' "$APPARMOR"
}

if sh -n "$SESSION" &&
   sh -n "$GREETER_SESSION" &&
   sh -n "$AUTOSTART" &&
   sh -n "$GREETER_CLIENT" &&
   sh -n "$OUTPUT_WATCH"; then
  pass "Labwc session environment wrappers are valid POSIX shell"
else
  fail "Labwc session environment wrappers are valid POSIX shell"
fi

if grep -Fqx 'session    required   pam_systemd.so class=user type=wayland desktop=labwc' "$PAM_GREETD" &&
   ! grep -Fqx 'session    optional   pam_systemd.so class=user type=wayland desktop=labwc' "$PAM_GREETD"; then
  pass "greetd refuses a desktop login when pam_systemd cannot establish the user runtime"
else
  fail "greetd refuses a desktop login when pam_systemd cannot establish the user runtime"
fi

if grep -Fqx 'export LABWC_SESSION_OWNER=greeter' "$GREETER_SESSION" &&
   grep -Fqx 'export LABWC_UPDATE_ACTIVATION_ENV=0' "$GREETER_SESSION" &&
   grep -Fqx 'export ANGLE_DEFAULT_PLATFORM=gl' "$GREETER_SESSION" &&
   grep -Fqx 'export WGPU_BACKEND=gl' "$GREETER_SESSION" &&
   grep -Fqx 'export SDL_RENDER_DRIVER=opengl' "$GREETER_SESSION" &&
   grep -Fq 'VK_DRIVER_FILES' "$GREETER_SESSION" &&
   grep -Fqx 'export GTK_USE_PORTAL=0' "$GREETER_SESSION" &&
   grep -Fqx 'export GIO_USE_PORTALS=0' "$GREETER_SESSION" &&
   ! grep -Fq 'import-environment' "$GREETER_SESSION" &&
   ! grep -Fq 'dbus-update-activation-environment' "$GREETER_SESSION"; then
  pass "the isolated greeter disables GTK and GIO portal requests without updating its user manager"
else
  fail "the isolated greeter disables GTK and GIO portal requests without updating its user manager"
fi

runtime_line=$(grep -n -F 'expected_runtime_dir="/run/user/${current_uid}"' "$SESSION" | cut -d: -f1)
profile_line=$(grep -n -F 'if [ -r "$HOME/.profile" ]; then' "$SESSION" | cut -d: -f1)
if [ -n "$runtime_line" ] &&
   [ -n "$profile_line" ] &&
   [ "$runtime_line" -lt "$profile_line" ] &&
   grep -Fq '[ "$(stat -c '\''%a'\'' "$XDG_RUNTIME_DIR" 2>/dev/null || true)" != 700 ]' "$SESSION" &&
   grep -Fqx 'export XDG_RUNTIME_DIR' "$SESSION"; then
  pass "XDG_RUNTIME_DIR is canonical, owned, private, and exported before the login profile runs"
else
  fail "XDG_RUNTIME_DIR is canonical, owned, private, and exported before the login profile runs"
fi

if grep -Fq 'session_bus_path="${XDG_RUNTIME_DIR}/bus"' "$SESSION" &&
   grep -Fq 'session_bus_address="unix:path=${session_bus_path}"' "$SESSION" &&
   grep -Fq 'while [ ! -S "$session_bus_path" ] && [ "$session_bus_attempt" -le 5 ]; do' "$SESSION" &&
   grep -Fqx '  /usr/bin/sleep 1' "$SESSION" &&
   grep -Fq 'if [ ! -S "$session_bus_path" ]; then' "$SESSION" &&
   grep -Fqx 'DBUS_SESSION_BUS_ADDRESS=$session_bus_address' "$SESSION" &&
   grep -Fqx 'export DBUS_SESSION_BUS_ADDRESS' "$SESSION" &&
   ! grep -Fq 'DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-' "$SESSION"; then
  pass "Labwc waits for and exports only the canonical live systemd user-bus address"
else
  fail "Labwc waits for and exports only the canonical live systemd user-bus address"
fi

if grep -Fq '[ "${DBUS_SESSION_BUS_ADDRESS:-}" != "$session_bus_address" ]' "$SESSION" &&
   grep -Fq 'fatal: the login profile changed the managed XDG runtime or D-Bus session address' "$SESSION"; then
  pass "the login profile cannot replace the managed runtime directory or session bus"
else
  fail "the login profile cannot replace the managed runtime directory or session bus"
fi

if grep -Fqx "labwc_x11_environment_names='$x11_environment_names'" "$SESSION" &&
   grep -Fqx "labwc_x11_environment_names='$x11_environment_names'" "$GREETER_SESSION" &&
   grep -Fqx "labwc_x11_environment_names='$x11_environment_names'" "$AUTOSTART" &&
   grep -Fqx "labwc_x11_environment_names='$x11_environment_names'" "$GREETER_CLIENT" &&
   [ "$(grep -Fc 'unset $labwc_x11_environment_names' "$SESSION")" -eq 2 ] &&
   [ "$(grep -Fc 'unset $labwc_x11_environment_names' "$GREETER_SESSION")" -eq 2 ] &&
   [ "$(grep -Fc 'unset $labwc_x11_environment_names' "$AUTOSTART")" -eq 1 ] &&
   [ "$(grep -Fc 'unset $labwc_x11_environment_names' "$GREETER_CLIENT")" -eq 1 ] &&
   grep -Fq -- '--user unset-environment $cleanup_environment_names' "$SESSION" &&
   grep -Fq -- '--user unset-environment $labwc_x11_environment_names' "$AUTOSTART" &&
   ! grep -Fq '/opt/xwayland' "$SESSION" &&
   ! grep -Fq '/opt/xwayland' "$GREETER_SESSION" &&
   ! grep -Fq '/opt/xwayland' "$AUTOSTART" &&
   ! grep -Fq '/opt/xwayland' "$GREETER_CLIENT" &&
   ! grep -Fq '/tmp/.X11-unix' "$SESSION" &&
   ! grep -Fq '/tmp/.X11-unix' "$GREETER_SESSION" &&
   ! grep -Fq '/tmp/.X11-unix' "$AUTOSTART" &&
   ! grep -Fq '/tmp/.X11-unix' "$GREETER_CLIENT" &&
   grep -Fq "grep -q \"^labwc_x11_environment_names='DISPLAY XAUTHORITY WLR_XWAYLAND" "$FIRSTBOOT_VALIDATION" &&
   ! grep -Fq '_JAVA_AWT_WM_NONREPARENTING' "$LABWC_WAYLAND_ENVIRONMENT" &&
   ! grep -Fq '_JAVA_AWT_WM_NONREPARENTING' "$AUTOSTART" &&
   ! grep -Fq 'xwaylandPersistence' "$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/labwc/rc.xml.tmpl" &&
   ! grep -Fq 'xwaylandPersistence' "$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/share/labwc-greeter/rc.xml"; then
  pass "Labwc login, greeter, autostart, and user-manager boundaries scrub inherited X11 state without private-runtime access"
else
  fail "Labwc login, greeter, autostart, and user-manager boundaries scrub inherited X11 state without private-runtime access"
fi

if grep -Fqx 'cleanup_environment_names="LABWC_SESSION_OWNER LABWC_PID WAYLAND_DISPLAY SWAYSOCK ${labwc_x11_environment_names}"' "$SESSION" &&
   grep -Fq -- '--user unset-environment $cleanup_environment_names' "$SESSION" &&
   ! grep -Fq -- '--user unset-environment $activation_environment_names' "$SESSION" &&
   ! sed -n '/^cleanup_labwc_session() {$/,/^}$/p' "$SESSION" |
     grep -Fq 'dbus-update-activation-environment'; then
  pass "session teardown preserves the user-bus environment without contacting a stopping broker"
else
  fail "session teardown preserves the user-bus environment without contacting a stopping broker"
fi

compositor_environment_names=$(sed -n "s/^compositor_environment_names='\([^']*\)'$/\1/p" "$SESSION")
compositor_environment_complete=true
for environment_name in \
  PATH \
  LABWC_SESSION_UID \
  LABWC_SESSION_OWNER \
  XDG_SESSION_TYPE \
  XDG_RUNTIME_DIR \
  DBUS_SESSION_BUS_ADDRESS \
  QT_QPA_PLATFORM \
  GDK_BACKEND \
  WLR_RENDERER
do
  case " $compositor_environment_names " in
    *" $environment_name "*) ;;
    *) compositor_environment_complete=false ;;
  esac
done
import_line=$(grep -n -F '"$systemctl_cmd" --user import-environment $compositor_environment_names' "$SESSION" | cut -d: -f1)
handoff_line=$(grep -n -F 'wait_for_greeter_seat_release' "$SESSION" | tail -n 1 | cut -d: -f1)
compositor_wait_line=$(grep -n -F '"$systemctl_cmd" --user --wait start labwc-compositor.service 9>&- || labwc_status=$?' "$SESSION" | cut -d: -f1)
cleanup_call_line=$(grep -n -F 'cleanup_labwc_session' "$SESSION" | tail -n 1 | cut -d: -f1)
if [ "$compositor_environment_complete" = true ] &&
   [ -n "$handoff_line" ] &&
   [ -n "$import_line" ] &&
   [ -n "$compositor_wait_line" ] &&
   [ -n "$cleanup_call_line" ] &&
   [ "$handoff_line" -lt "$import_line" ] &&
   [ "$import_line" -lt "$compositor_wait_line" ] &&
   [ "$compositor_wait_line" -lt "$cleanup_call_line" ] &&
   ! printf '%s\n' "$compositor_environment_names" |
     grep -Eq '(^| )(DISPLAY|LABWC_PID|SWAYSOCK|WAYLAND_DISPLAY)( |$)' &&
   ! grep -Fq 'trap cleanup_labwc_session EXIT' "$SESSION" &&
   ! grep -Fq '/usr/bin/labwc 9>&-' "$SESSION"; then
  pass "the login wrapper imports bounded static policy and waits on the user-manager compositor"
else
  fail "the login wrapper imports bounded static policy and waits on the user-manager compositor"
fi

greeter_session_filter=$(sed -n "/^greeter_session_filter='$/,/^'$/p" "$SESSION" | sed '1d;$d')
busy_state=$(
  printf '%s\n' '[{"session":"4","uid":1000},{"session":"2","uid":989}]' |
    jq -er \
      --argjson current_uid 1000 \
      --argjson greeter_uid 989 \
      "$greeter_session_filter"
) || busy_state=invalid
released_state=$(
  printf '%s\n' '[{"session":"4","uid":1000},{"session":"5","uid":1000}]' |
    jq -er \
      --argjson current_uid 1000 \
      --argjson greeter_uid 989 \
      "$greeter_session_filter"
) || released_state=invalid
invalid_inventory_accepted=false
if printf '%s\n' '[{"session":"2","uid":989}]' |
   jq -er \
     --argjson current_uid 1000 \
     --argjson greeter_uid 989 \
     "$greeter_session_filter" >/dev/null 2>&1; then
  invalid_inventory_accepted=true
fi
handoff_call_line=$(grep -n -F 'wait_for_greeter_seat_release' "$SESSION" | tail -n 1 | cut -d: -f1)
compositor_start_line=$(grep -n -F '"$systemctl_cmd" --user --wait start labwc-compositor.service 9>&- || labwc_status=$?' "$SESSION" | cut -d: -f1)
if [ "$busy_state" = busy ] &&
   [ "$released_state" = released ] &&
   [ "$invalid_inventory_accepted" = false ] &&
   grep -Fqx 'greeter_user=${LABWC_GREETER_USER:-}' "$SESSION" &&
   grep -Fq 'greeter_uid=$(/usr/bin/id -u -- "$greeter_user" 2>/dev/null)' "$SESSION" &&
   grep -Fqx 'readonly greeter_user greeter_uid' "$SESSION" &&
   grep -Fqx '  handoff_deadline=$((handoff_started + 20))' "$SESSION" &&
   grep -Fqx '          --kill-after=1s \' "$SESSION" &&
   grep -Fqx '          2s \' "$SESSION" &&
   grep -Fqx '            --json=short \' "$SESSION" &&
   grep -Fqx '            list-sessions \' "$SESSION" &&
   grep -Fq 'fatal: the managed greeter did not release all logind sessions within 20 seconds:' "$SESSION" &&
   [ -n "$handoff_call_line" ] &&
   [ -n "$compositor_start_line" ] &&
   [ "$handoff_call_line" -lt "$compositor_start_line" ] &&
   ! grep -Eq '/usr/bin/sleep (10|20)([[:space:]]|$)' "$SESSION"; then
  pass "the desktop compositor waits on a bounded, validated logind greeter-session handoff"
else
  fail "the desktop compositor waits on a bounded, validated logind greeter-session handoff"
fi

if grep -Fq 'session_bus_path="${XDG_RUNTIME_DIR}/bus"' "$AUTOSTART" &&
   grep -Fq 'if [ ! -S "$session_bus_path" ]; then' "$AUTOSTART" &&
   grep -Fqx 'DBUS_SESSION_BUS_ADDRESS="unix:path=${session_bus_path}"' "$AUTOSTART" &&
   grep -Fqx 'export DBUS_SESSION_BUS_ADDRESS' "$AUTOSTART" &&
   ! grep -Fq 'DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-' "$AUTOSTART"; then
  pass "Labwc autostart reasserts the canonical live user bus before importing the environment"
else
  fail "Labwc autostart reasserts the canonical live user bus before importing the environment"
fi

activation_environment_names=$(sed -n "s/^activation_environment_names='\([^']*\)'$/\1/p" "$AUTOSTART")
desktop_activation_environment_complete=true
for environment_name in \
  LABWC_SESSION_OWNER \
  XDG_SESSION_TYPE \
  XDG_RUNTIME_DIR \
  WAYLAND_DISPLAY \
  DBUS_SESSION_BUS_ADDRESS \
  ANGLE_DEFAULT_PLATFORM \
  WGPU_BACKEND \
  SDL_RENDER_DRIVER
do
  case " $activation_environment_names " in
    *" $environment_name "*) ;;
    *) desktop_activation_environment_complete=false ;;
  esac
done
if [ "$desktop_activation_environment_complete" = true ] &&
   ! printf '%s\n' "$activation_environment_names" | grep -Eq '(^| )DISPLAY( |$)' &&
   grep -Fq '"$systemctl_cmd" --user import-environment $activation_environment_names' "$AUTOSTART" &&
   grep -Fq '"$systemctl_cmd" --user set-environment LABWC_SESSION_OWNER=desktop' "$AUTOSTART" &&
   grep -Fq 'dbus-update-activation-environment --systemd $activation_environment_names' "$AUTOSTART"; then
  pass "the desktop user manager receives Labwc ownership and the complete Wayland session environment"
else
  fail "the desktop user manager receives Labwc ownership and the complete Wayland session environment"
fi

environment_sync_line=$(grep -n -F 'sync_user_activation_environment' "$AUTOSTART" | tail -n 1 | cut -d: -f1)
output_wait_line=$(grep -n -F 'wait_for_wayland_output' "$AUTOSTART" | tail -n 1 | cut -d: -f1)
target_start_line=$(grep -n -F 'start_session_target' "$AUTOSTART" | tail -n 1 | cut -d: -f1)
readiness_wait_line=$(grep -n -F 'wait_for_required_session_units' "$AUTOSTART" | tail -n 1 | cut -d: -f1)
if [ -n "$environment_sync_line" ] &&
   [ -n "$output_wait_line" ] &&
   [ -n "$target_start_line" ] &&
   [ -n "$readiness_wait_line" ] &&
   [ "$environment_sync_line" -lt "$target_start_line" ] &&
   [ "$target_start_line" -lt "$output_wait_line" ] &&
   [ "$output_wait_line" -lt "$readiness_wait_line" ] &&
   grep -Fqx 'output_waiter=/usr/local/libexec/labwc-output-watch' "$AUTOSTART" &&
   grep -Fqx '  "$output_waiter" --wait-for-output || {' "$AUTOSTART" &&
   grep -Fqx 'required_session_units='\''labwc-kwallet-portal.service hyprpolkitagent.service xdg-desktop-portal.service xdg-desktop-portal-gtk.service xdg-desktop-portal-wlr.service xdg-desktop-portal-lxqt.service'\''' "$AUTOSTART" &&
   ! grep -Fq 'validate_xwayland_display' "$AUTOSTART" &&
   ! grep -Fq '/tmp/.X11-unix' "$AUTOSTART" &&
   ! grep -Fq '/opt/xwayland' "$AUTOSTART" &&
   grep -Fqx '  "$systemctl_cmd" --user --no-block start labwc-session.target >/dev/null 2>&1 || {' "$AUTOSTART" &&
   grep -Fqx '      if ! "$systemctl_cmd" --user --quiet is-active "$session_unit"; then' "$AUTOSTART" &&
   grep -Fq 'fatal: required Labwc authentication, secret, or portal services did not become active:' "$AUTOSTART" &&
   grep -Fq 'wayland_info=$(command -v wayland-info || true)' "$OUTPUT_WATCH" &&
   grep -Fq 'wayland_snapshot_has_current_output "$wayland_snapshot"' "$OUTPUT_WATCH" &&
   grep -Fq '/usr/bin/timeout "$output_remaining" "$readiness_refresh" >/dev/null 2>&1 || true' "$OUTPUT_WATCH" &&
   grep -Fqx 'ExecStartPre=/usr/local/libexec/labwc-output-watch --wait-for-output' "$OUTPUT_WATCH_UNIT" &&
   ! grep -Fqx 'ExecStartPre=/usr/local/libexec/labwc-output-refresh' "$OUTPUT_WATCH_UNIT" &&
   grep -Fqx '  /usr/local/libexec/labwc-output-watch rPx -> managed-labwc-output-watch,' "$APPARMOR" &&
   grep -Fqx '  /usr/bin/wayland-info pux,' "$APPARMOR"; then
  pass "Labwc activates the session transaction before bounded output and service readiness checks"
else
  fail "Labwc activates the session transaction before bounded output and service readiness checks"
fi

if grep -Fqx 'ConditionEnvironment=LABWC_SESSION_OWNER=desktop' "$COMPOSITOR_UNIT" &&
   grep -Fqx 'DefaultDependencies=no' "$COMPOSITOR_UNIT" &&
   grep -Fqx 'Conflicts=shutdown.target' "$COMPOSITOR_UNIT" &&
   grep -Fqx 'Before=shutdown.target' "$COMPOSITOR_UNIT" &&
   grep -Fqx 'Requires=dbus.service dbus.socket' "$COMPOSITOR_UNIT" &&
   grep -Fqx 'After=dbus.service dbus.socket' "$COMPOSITOR_UNIT" &&
   grep -Fqx 'PartOf=labwc-session.target' "$COMPOSITOR_UNIT" &&
   grep -Fqx 'Before=labwc-session.target' "$COMPOSITOR_UNIT" &&
   grep -Fqx 'Environment=LIBSEAT_BACKEND=seatd' "$COMPOSITOR_UNIT" &&
   grep -Fqx 'UnsetEnvironment=DISPLAY XAUTHORITY WLR_XWAYLAND XWAYLAND XWAYLAND_PATH XWAYLAND_NO_GLAMOR XWAYLAND_FORCE_SCALE XWAYLAND_RESTART_DELAY _XWAYLAND_GLOBAL_OUTPUT_SCALE WINDOWID SESSION_MANAGER DESKTOP_STARTUP_ID' "$COMPOSITOR_UNIT" &&
   ! grep -Fq 'Environment=WLR_XWAYLAND=' "$COMPOSITOR_UNIT" &&
   grep -Fqx 'ExecStart=/usr/bin/labwc' "$COMPOSITOR_UNIT" &&
   grep -Fqx 'TimeoutStopSec=30s' "$COMPOSITOR_UNIT" &&
   grep -Fqx 'Requires=dbus.service dbus.socket' "$SESSION_TARGET" &&
   grep -Fqx 'BindsTo=labwc-compositor.service' "$SESSION_TARGET" &&
   grep -Fqx 'After=dbus.service dbus.socket labwc-compositor.service' "$SESSION_TARGET" &&
   grep -Fqx 'DefaultDependencies=no' "$SESSION_TARGET" &&
   grep -Fqx 'Conflicts=shutdown.target' "$SESSION_TARGET" &&
   grep -Fqx 'Before=shutdown.target' "$SESSION_TARGET"; then
  pass "the session target stops clients before the compositor, user broker, and user D-Bus socket"
else
  fail "the session target stops clients before the compositor, user broker, and user D-Bus socket"
fi

if grep -Fqx '[Unit]' "$USER_MANAGER_SEATD_DROPIN" &&
   grep -Fqx 'After=seatd.service' "$USER_MANAGER_SEATD_DROPIN" &&
   ! grep -Eq '^(BindsTo|Conflicts|Requires|Wants)=' "$USER_MANAGER_SEATD_DROPIN" &&
   grep -Fq 'etc/systemd/system/user@.service.d/20-labwc-seatd.conf' "$DESKTOP_COMPONENTS" &&
   grep -Fq '/etc/systemd/system/user@.service.d/20-labwc-seatd.conf' "$DESKTOP_COMPONENTS" &&
   grep -Fq 'etc/skel/.config/systemd/user/labwc-compositor.service' "$DESKTOP_COMPONENTS" &&
   grep -Fq '/etc/skel/.config/systemd/user/labwc-compositor.service' "$DESKTOP_COMPONENTS"; then
  pass "installer staging reverses seatd and user-manager stop order without lifecycle coupling"
else
  fail "installer staging reverses seatd and user-manager stop order without lifecycle coupling"
fi

if grep -Fqx 'Wants=systemd-user-sessions.service systemd-logind.service seatd.service dbus.socket' "$GREETD_SERVICE_DROPIN" &&
   grep -Fqx 'After=systemd-user-sessions.service systemd-logind.service seatd.service dbus.socket' "$GREETD_SERVICE_DROPIN" &&
   grep -Fqx 'export LIBSEAT_BACKEND=seatd' "$GREETER_SESSION" &&
   ! grep -Eq '^(After|BindsTo|Requires|Wants)=.*(greetd|seatd|systemd-user-sessions)[.]service' "$COMPOSITOR_UNIT"; then
  pass "system-manager login readiness and seat ownership stay separate from user-manager compositor ordering"
else
  fail "system-manager login readiness and seat ownership stay separate from user-manager compositor ordering"
fi

portal_units='xdg-desktop-portal.service xdg-desktop-portal-gtk.service xdg-desktop-portal-wlr.service xdg-desktop-portal-lxqt.service'
portal_enablement_block=$(awk '
  /^desktop_enable_target_services\(\) \{$/ { show = 1 }
  show { print }
  show && /^}$/ { exit }
' "$DESKTOP_COMPONENTS")
portal_units_are_session_bound=true
for portal_unit in $portal_units; do
  portal_dropin="$PORTAL_DROPIN_ROOT/${portal_unit}.d/10-labwc-session.conf"
  if ! grep -Fqx 'ConditionEnvironment=LABWC_SESSION_OWNER=desktop' "$portal_dropin" ||
     ! grep -Fqx 'ConditionEnvironment=WAYLAND_DISPLAY' "$portal_dropin" ||
     ! grep -Fqx 'ConditionEnvironment=XDG_SESSION_TYPE=wayland' "$portal_dropin" ||
     ! grep -Eq '^After=labwc-session\.target( |$)' "$portal_dropin" ||
     ! grep -Fqx 'PartOf=labwc-session.target' "$portal_dropin" ||
     ! grep -Fqx 'WantedBy=labwc-session.target' "$portal_dropin" ||
     grep -Fq 'graphical-session.target' "$portal_dropin" ||
     ! printf '%s\n' "$portal_enablement_block" | grep -Fq "    $portal_unit"; then
    portal_units_are_session_bound=false
    break
  fi
done
if [ "$portal_units_are_session_bound" = true ] &&
   printf '%s\n' "$portal_enablement_block" |
     grep -Fqx '    desktop_stage_user_unit_wanted_by "$unit" labwc-session.target'; then
  pass "all selected desktop portal units remain Wayland-gated and bound to labwc-session.target"
else
  fail "all selected desktop portal units remain Wayland-gated and bound to labwc-session.target"
fi

if [ -r "$DBUS_USER_HARDENING_TEMPLATE" ] &&
   [ ! -e "$LEGACY_DBUS_USER_HARDENING_TEMPLATE" ] &&
   grep -Fqx 'TasksMax=__INSTALLER_DBUS_BROKER_TASKS_MAX__' "$DBUS_USER_HARDENING_TEMPLATE" &&
   grep -Fqx 'LimitNOFILE=__INSTALLER_DBUS_BROKER_LIMIT_NOFILE__' "$DBUS_USER_HARDENING_TEMPLATE" &&
   ! grep -Fq 'dbus-broker.service.d/10-broker-hardening.conf.tmpl' "$DESKTOP_COMPONENTS" &&
   grep -Fq 'etc/systemd/user/dbus-broker.service.d/10-broker-hardening.conf.tmpl' "$DBUS_LATE" &&
   grep -q '^FILE_DBUS_USER_BROKER_SERVICE_OVERRIDE=' "$RUNTIME_ENV"; then
  pass "the user-broker hardening drop-in remains system-wide for every user manager"
else
  fail "the user-broker hardening drop-in remains system-wide for every user manager"
fi

if profile_block managed-labwc-session |
   grep -Fqx '  owner /run/user/[0-9]*/bus r,' &&
   profile_block managed-labwc-session |
   grep -Fqx '  /usr/bin/{flock,id,jq,sleep,stat} rix,' &&
   profile_block managed-labwc-session |
     grep -Fqx '  /usr/bin/{loginctl,systemctl,timeout} pux,' &&
   profile_block managed-labwc-session |
     grep -Fqx '  @{PROC}/uptime r,' &&
   ! profile_block managed-labwc-session |
     grep -Fq 'dbus-update-activation-environment' &&
   ! profile_block managed-labwc-session |
     grep -Fq '/opt/xwayland' &&
   profile_block managed-labwc-autostart |
     grep -Fqx '  owner /run/user/[0-9]*/bus r,' &&
   ! profile_block managed-labwc-autostart |
     grep -Fq '/tmp/.X11-unix'; then
  pass "AppArmor keeps Labwc session and autostart outside the private compatibility boundary"
else
  fail "AppArmor keeps Labwc session and autostart outside the private compatibility boundary"
fi

if ! rg -q 'XDG_DBUS' "$SESSION" "$AUTOSTART" "$PAM_GREETD" "$SESSION_TARGET"; then
  pass "the implementation uses the standard XDG_RUNTIME_DIR and DBUS_SESSION_BUS_ADDRESS names"
else
  fail "the implementation uses the standard XDG_RUNTIME_DIR and DBUS_SESSION_BUS_ADDRESS names"
fi

printf '1..%s\n' "$tests"
[ "$failures" -eq 0 ]
