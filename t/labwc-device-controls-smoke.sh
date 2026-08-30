#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/labwc-device-controls.XXXXXX")
trap 'rm -rf "$TMP_DIR"' EXIT HUP INT TERM

TEST_COUNT=14
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

waybar_template="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/waybar/config.tmpl"
network_menu="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-network-control-menu"
network_action="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-network-control-action"
network_root_action="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/libexec/labwc-network-control-action-root"
network_module_root="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/lib/perl5/site_perl/labwc-network-control-action"
network_client_module="$network_module_root/LabwcNetworkControlAction/Client.pm"
network_root_module="$network_module_root/LabwcNetworkControlAction/Root.pm"
network_validation_module="$network_module_root/LabwcNetworkControlAction/Validation.pm"
network_perl_smoke="$ROOT_DIR/t/labwc-network-management-smoke.sh"
network_perl_log="$TMP_DIR/network-perl-smoke.log"
bluetooth_helper="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-bluetooth"
brightness_helper="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-brightness-control"
capture_helper="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-capture"
bluetooth_init="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/libexec/bluetooth-controller-init"
bluetooth_init_service="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/systemd/system/bluetooth-controller-init.service"
bluetooth_override="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/systemd/system/bluetooth.service.d/override.conf"
bluetooth_main="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/bluetooth/main.conf"
terminal_helper="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-terminal"
components="$ROOT_DIR/d-i/forky/scripts/desktop/components.sh"
desktop_verify="$ROOT_DIR/d-i/forky/scripts/desktop/verify.sh"

printf '1..%s\n' "$TEST_COUNT"

if grep -q '"on-click-right": "labwc-network-control-menu"' "$waybar_template" &&
   grep -q '"on-click-right": "labwc-bluetooth menu"' "$waybar_template"; then
  pass "Waybar right-clicks open managed LAN and BLE Fuzzel controls"
else
  fail "Waybar right-clicks open managed LAN and BLE Fuzzel controls"
fi

network_labels_ok=true
for label in \
  'Enable Ethernet Adapter' \
  'Disable Ethernet Adapter' \
  'Enable WiFi Adapter' \
  'Disable WiFi Adapter' \
  'Activate Saved Connection' \
  'Deactivate Active Connection' \
  'Activate VPN Connection' \
  'Deactivate VPN Connection' \
  'Import OpenVPN Profile' \
  'Activate WireGuard Connection' \
  'Deactivate WireGuard Connection' \
  'Import WireGuard Profile' \
  'Show DNS Status' \
  'Restore Automatic DNS' \
  'Set Custom DNS Servers' \
  'Flush DNS Cache' \
  'Generate Random MAC Addresses'
do
  grep -Fq "'${label}'" "$network_menu" || network_labels_ok=false
done
if [ "$network_labels_ok" = true ] &&
   grep -q 'Continue with network change' "$network_menu" &&
   ! grep -Eq -- '--(width|lines)=' "$network_menu"; then
  pass "LAN Fuzzel menu exposes the complete requested action catalog"
else
  fail "LAN Fuzzel menu exposes the complete requested action catalog"
fi

if grep -Fq "use LabwcNetworkControlAction::Client;" "$network_action" &&
   grep -Fq "use LabwcNetworkControlAction::Root;" "$network_root_action" &&
   grep -Fq "default => sub { '/usr/local/libexec/labwc-network-control-action-root' }," "$network_client_module" &&
   grep -q '^sub interface_name {$' "$network_validation_module" &&
   grep -q 'network interface name exceeds the Linux interface limit' "$network_validation_module" &&
   grep -q '^sub _require_pkexec_invoker {$' "$network_root_module" &&
   grep -q '^sub _ifupdown_configured {$' "$network_root_module" &&
   grep -q '^sub _networkmanager_running {$' "$network_root_module" &&
   grep -q '^sub _networkmanager_managed {$' "$network_root_module" &&
   grep -q '^sub _set_custom_dns {$' "$network_root_module" &&
   grep -Fq '$self->command()->exec($ifup, $interface);' "$network_root_module" &&
   grep -Fq '$self->command()->exec($ifdown, $interface);' "$network_root_module" &&
   grep -q '802-3-ethernet.cloned-mac-address' "$network_root_module" &&
   grep -q '802-11-wireless.cloned-mac-address' "$network_root_module" &&
   grep -q '^sub _randomize_direct_interface {$' "$network_root_module" &&
   grep -q 'confirmed-network-action' "$network_client_module"; then
  pass "network actions support ifupdown and NetworkManager with confirmed MAC randomization"
else
  fail "network actions support ifupdown and NetworkManager with confirmed MAC randomization"
fi

bluetooth_labels_ok=true
for label in \
  'Scan for Devices' \
  'Pair Device' \
  'Connect Device' \
  'Disconnect Device' \
  'Trust Device' \
  'Untrust Device' \
  'Unpair Device' \
  'Device Information' \
  'Make Discoverable' \
  'Hide from Discovery' \
  'Enable Bluetooth' \
  'Disable Bluetooth' \
  'Open Interactive Console'
do
  grep -Fq "'${label}'" "$bluetooth_helper" || bluetooth_labels_ok=false
done
if [ "$bluetooth_labels_ok" = true ] &&
   grep -q '^set_power() {$' "$bluetooth_helper" &&
   grep -q '^run_action_menu() {$' "$bluetooth_helper" &&
   grep -q '^manage_device() {$' "$bluetooth_helper" &&
   grep -q '^run_adapter_menu() {$' "$bluetooth_helper" &&
   grep -q '^validate_device_address() {$' "$bluetooth_helper" &&
   grep -q '^scan_devices() {$' "$bluetooth_helper" &&
   grep -q '^pair_device_in_terminal() {$' "$bluetooth_helper" &&
   ! grep -Eq -- '--(width|lines)=' "$bluetooth_helper" &&
   grep -Fq -- '--signal=RTMIN+8' "$bluetooth_helper" &&
   grep -Fq 'waybar.service' "$bluetooth_helper" &&
   ! grep -Eq '(^|[^[:alnum:]_])(pgrep|pkill|pidof)([^[:alnum:]_]|$)' "$bluetooth_helper"; then
  pass "BLE Fuzzel menu exposes bounded controller and per-device actions"
else
  fail "BLE Fuzzel menu exposes bounded controller and per-device actions"
fi

if grep -q 'usr/local/bin/labwc-network-control-menu /usr/local/bin/labwc-network-control-menu 0755' "$components" &&
   grep -q 'usr/local/bin/labwc-network-control-action /usr/local/bin/labwc-network-control-action 0755' "$components" &&
   grep -q 'usr/local/libexec/labwc-network-control-action-root /usr/local/libexec/labwc-network-control-action-root 0755' "$components" &&
   grep -q '/usr/local/bin/labwc-network-control-menu' "$desktop_verify" &&
   grep -q '/usr/local/bin/labwc-network-control-action' "$desktop_verify" &&
   grep -q '/usr/local/libexec/labwc-network-control-action-root' "$desktop_verify"; then
  pass "desktop staging and verification include the complete LAN control boundary"
else
  fail "desktop staging and verification include the complete LAN control boundary"
fi

bin_dir="$TMP_DIR/bin"
responses="$TMP_DIR/responses"
action_log="$TMP_DIR/action.log"
mkdir -p "$bin_dir"
cat >"$responses" <<'EOF'
Enable Ethernet Adapter
enp1s0
EOF
cat >"$bin_dir/id" <<'EOF'
#!/bin/sh
[ "${1:-}" = -u ] && { printf '%s\n' 1000; exit 0; }
exec /usr/bin/id "$@"
EOF
cat >"$bin_dir/nmcli" <<'EOF'
#!/bin/sh
printf '%s\n' 'enp1s0:ethernet' 'wlan0:wifi'
EOF
cat >"$bin_dir/labwc-fuzzel" <<'EOF'
#!/bin/sh
set -eu
cat >/dev/null
response=$(sed -n '1p' "${FUZZEL_RESPONSES:?}")
sed '1d' "$FUZZEL_RESPONSES" >"${FUZZEL_RESPONSES}.next"
mv "${FUZZEL_RESPONSES}.next" "$FUZZEL_RESPONSES"
printf '%s\n' "$response"
EOF
cat >"$bin_dir/labwc-network-control-action" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"${NETWORK_ACTION_LOG:?}"
EOF
chmod 0755 "$bin_dir"/*

network_perl_ok=false
if /bin/sh "$network_perl_smoke" >"$network_perl_log" 2>&1; then
  network_perl_ok=true
fi

if PATH="$bin_dir:/usr/bin:/bin" \
   FUZZEL_RESPONSES="$responses" \
   NETWORK_ACTION_LOG="$action_log" \
   /bin/sh "$network_menu" connections &&
   [ "$(cat "$action_log")" = "enable-ethernet enp1s0" ] &&
   /bin/sh -n "$network_menu" &&
   [ "$network_perl_ok" = true ] &&
   /bin/sh -n "$bluetooth_helper" &&
   /bin/sh -n "$bluetooth_init" &&
   /bin/sh -n "$terminal_helper"; then
  pass "device control menus dispatch fixed actions and helpers validate in their declared runtimes"
else
  cat "$network_perl_log" >&2
  fail "device control menus dispatch fixed actions and helpers validate in their declared runtimes"
fi

if grep -q '^Wants=bluetooth.service$' "$bluetooth_init_service" &&
   grep -q '^After=bluetooth.service$' "$bluetooth_init_service" &&
   grep -q '^ConditionFileIsExecutable=/usr/local/libexec/bluetooth-controller-init$' "$bluetooth_init_service" &&
   ! grep -q 'bluetooth-controller-init.service' "$bluetooth_override" &&
   grep -q '^TIMEOUT=/usr/bin/timeout$' "$bluetooth_init" &&
   grep -q '^CONTROLLER_WAIT_SECONDS=5$' "$bluetooth_init" &&
   grep -q '^BTMGMT_TIMEOUT_SECONDS=2$' "$bluetooth_init" &&
   grep -q '^COMMAND_TIMEOUT_SECONDS=5$' "$bluetooth_init" &&
   grep -q '^COMMAND_KILL_GRACE_SECONDS=1$' "$bluetooth_init" &&
   grep -q '^MAX_CONTROLLERS=8$' "$bluetooth_init" &&
   grep -q '^TimeoutStartSec=35s$' "$bluetooth_init_service" &&
   grep -q -- '--kill-after="${COMMAND_KILL_GRACE_SECONDS}s"' "$bluetooth_init" &&
   grep -q '"\$@" </dev/null 2>&1' "$bluetooth_init" &&
   grep -q 'Bluetooth kernel subsystem is not present' "$bluetooth_init" &&
   grep -q '^wait_for_controllers() {$' "$bluetooth_init" &&
   grep -q '^rfkill_blocks_bluetooth() {$' "$bluetooth_init" &&
   grep -q '^controller_is_powered() {$' "$bluetooth_init" &&
   grep -q 'BlueZ already enabled the controller' "$bluetooth_init" &&
   grep -q 'preserving the rfkill state' "$bluetooth_init" &&
   grep -q 'leaving remaining controllers to BlueZ' "$bluetooth_init" &&
   grep -q 'BlueZ remains authoritative' "$bluetooth_init" &&
   ! grep -q '^KernelExperimental' "$bluetooth_main" &&
   ! grep -q 'rfkill unblock bluetooth' "$bluetooth_init" &&
   ! grep -q 'ensure_powered || ! run_controller_command pairable on' "$bluetooth_helper" &&
   grep -q '^effective_ctype=' "$terminal_helper" &&
   grep -q '^    LC_ALL=C.UTF-8$' "$terminal_helper" &&
   grep -q '^LC_ALL=C.UTF-8$' "$bluetooth_helper"; then
  pass "Bluetooth starts independently, preserves rfkill policy, and opens UTF-8 controls without blocking"
else
  fail "Bluetooth starts independently, preserves rfkill policy, and opens UTF-8 controls without blocking"
fi

bluetooth_harness="$TMP_DIR/bluetooth-harness"
bluetooth_bin="$bluetooth_harness/bin"
bluetooth_responses="$bluetooth_harness/responses"
bluetooth_log="$bluetooth_harness/actions.log"
bluetooth_invalid_log="$bluetooth_harness/invalid.log"
bluetooth_identity_log="$bluetooth_harness/identity.log"
bluetooth_unexpected_id_log="$bluetooth_harness/unexpected-id.log"
mkdir -p "$bluetooth_bin"
cat >"$bluetooth_responses" <<'EOF'
Connect Device
AA:BB:CC:DD:EE:FF  Test Keyboard
EOF
cat >"$bluetooth_bin/id" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"${BLUETOOTH_UNEXPECTED_ID_LOG:?}"
exit 97
EOF
cat >"$bluetooth_bin/bluetoothctl" <<'EOF'
#!/bin/sh
case "$*" in
  '--timeout 5 devices Paired')
    printf '%s\n' 'Device AA:BB:CC:DD:EE:FF Test Keyboard'
    ;;
  *)
    printf '%s\n' "$*" >>"${BLUETOOTH_ACTION_LOG:?}"
    ;;
esac
EOF
cat >"$bluetooth_bin/labwc-fuzzel" <<'EOF'
#!/bin/sh
set -eu
cat >/dev/null
response=$(sed -n '1p' "${FUZZEL_RESPONSES:?}")
sed '1d' "$FUZZEL_RESPONSES" >"${FUZZEL_RESPONSES}.next"
mv "${FUZZEL_RESPONSES}.next" "$FUZZEL_RESPONSES"
printf '%s\n' "$response"
EOF
cat >"$bluetooth_bin/pkill" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod 0755 "$bluetooth_bin"/*

rendered_bluetooth="$bluetooth_harness/labwc-bluetooth"
sed \
  -e "s|^PATH=/usr/local/bin:/usr/bin:/bin$|PATH=$bluetooth_bin:/usr/bin:/bin|" \
  "$bluetooth_helper" >"$rendered_bluetooth"
chmod 0755 "$rendered_bluetooth"

if LABWC_SESSION_OWNER=desktop \
   XDG_RUNTIME_DIR=/run/user/1000 \
   FUZZEL_RESPONSES="$bluetooth_responses" \
   BLUETOOTH_ACTION_LOG="$bluetooth_log" \
   BLUETOOTH_UNEXPECTED_ID_LOG="$bluetooth_unexpected_id_log" \
   /bin/sh "$rendered_bluetooth" menu &&
   grep -q '^--timeout 20 connect AA:BB:CC:DD:EE:FF$' "$bluetooth_log" &&
   [ ! -e "$bluetooth_unexpected_id_log" ] &&
   ! LABWC_SESSION_OWNER=desktop \
     XDG_RUNTIME_DIR=/run/user/1000 \
     BLUETOOTH_ACTION_LOG="$bluetooth_log" \
     BLUETOOTH_UNEXPECTED_ID_LOG="$bluetooth_unexpected_id_log" \
     /bin/sh "$rendered_bluetooth" pair 'not-an-address' >"$bluetooth_invalid_log" 2>&1 &&
   grep -q 'invalid Bluetooth device address' "$bluetooth_invalid_log"; then
  pass "BLE menu dispatches validated device addresses and rejects malformed input"
else
  fail "BLE menu dispatches validated device addresses and rejects malformed input"
fi

if ! LABWC_SESSION_OWNER=desktop \
     XDG_RUNTIME_DIR=/run/user/0 \
     /bin/sh "$rendered_bluetooth" status >"$bluetooth_identity_log" 2>&1 &&
   grep -q 'requires a non-root desktop runtime directory' "$bluetooth_identity_log" &&
   ! LABWC_SESSION_OWNER=other \
     XDG_RUNTIME_DIR=/run/user/1000 \
     /bin/sh "$rendered_bluetooth" status >"$bluetooth_identity_log" 2>&1 &&
   grep -q 'must run in the managed desktop session' "$bluetooth_identity_log" &&
   ! grep -Fq 'id -u' "$bluetooth_helper"; then
  pass "Bluetooth validates the managed non-root session without spawning an identity helper"
else
  fail "Bluetooth validates the managed non-root session without spawning an identity helper"
fi

brightness_harness="$TMP_DIR/brightness-harness"
brightness_bin="$brightness_harness/bin"
brightness_output="$brightness_harness/status.json"
brightness_error="$brightness_harness/status.err"
brightness_unexpected_id_log="$brightness_harness/unexpected-id.log"
mkdir -p "$brightness_bin"
cat >"$brightness_bin/id" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"${BRIGHTNESS_UNEXPECTED_ID_LOG:?}"
exit 97
EOF
cat >"$brightness_bin/brightnessctl" <<'EOF'
#!/bin/sh
printf '%s\n' 'intel_backlight,backlight,1200,50%'
EOF
chmod 0755 "$brightness_bin"/*

rendered_brightness="$brightness_harness/labwc-brightness-control"
sed \
  -e "s|^#!/bin/sh$|#!/bin/sh|" \
  "$brightness_helper" >"$rendered_brightness"
chmod 0755 "$rendered_brightness"

if LABWC_SESSION_OWNER=desktop \
   XDG_RUNTIME_DIR=/run/user/1000 \
   PATH="$brightness_bin:/usr/bin:/bin" \
   BRIGHTNESS_UNEXPECTED_ID_LOG="$brightness_unexpected_id_log" \
   /bin/sh "$rendered_brightness" status >"$brightness_output" 2>"$brightness_error" &&
   grep -q '"percentage":50' "$brightness_output" &&
   [ ! -e "$brightness_unexpected_id_log" ] &&
   ! LABWC_SESSION_OWNER=other \
     XDG_RUNTIME_DIR=/run/user/1000 \
     PATH="$brightness_bin:/usr/bin:/bin" \
     /bin/sh "$rendered_brightness" status >"$brightness_output" 2>"$brightness_error" &&
   grep -q 'must run in the managed desktop session' "$brightness_error" &&
   ! LABWC_SESSION_OWNER=desktop \
     XDG_RUNTIME_DIR=/run/user/0 \
     PATH="$brightness_bin:/usr/bin:/bin" \
     /bin/sh "$rendered_brightness" status >"$brightness_output" 2>"$brightness_error" &&
   grep -q 'requires a non-root desktop runtime directory' "$brightness_error"; then
  pass "brightness status uses managed session validation without spawning an identity helper"
else
  fail "brightness status uses managed session validation without spawning an identity helper"
fi

capture_harness="$TMP_DIR/capture-harness"
capture_bin="$capture_harness/bin"
capture_output="$capture_harness/status.json"
capture_error="$capture_harness/status.err"
capture_unexpected_id_log="$capture_harness/unexpected-id.log"
capture_unexpected_stat_log="$capture_harness/unexpected-stat.log"
capture_unexpected_install_log="$capture_harness/unexpected-install.log"
mkdir -p "$capture_bin"
cat >"$capture_bin/id" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"${CAPTURE_UNEXPECTED_ID_LOG:?}"
exit 97
EOF
cat >"$capture_bin/stat" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"${CAPTURE_UNEXPECTED_STAT_LOG:?}"
exit 97
EOF
cat >"$capture_bin/install" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"${CAPTURE_UNEXPECTED_INSTALL_LOG:?}"
exit 97
EOF
cat >"$capture_bin/systemctl" <<'EOF'
#!/bin/sh
case "$*" in
  *'--quiet is-active labwc-screen-recording.service'*) exit 1 ;;
esac
exit 0
EOF
chmod 0755 "$capture_bin"/*

rendered_capture="$capture_harness/labwc-capture"
sed \
  -e "s|^PATH=/usr/local/bin:/usr/bin:/bin$|PATH=$capture_bin:/usr/bin:/bin|" \
  "$capture_helper" >"$rendered_capture"
chmod 0755 "$rendered_capture"

if HOME="$capture_harness/home" \
   LABWC_SESSION_OWNER=desktop \
   XDG_RUNTIME_DIR=/run/user/1000 \
   CAPTURE_UNEXPECTED_ID_LOG="$capture_unexpected_id_log" \
   CAPTURE_UNEXPECTED_STAT_LOG="$capture_unexpected_stat_log" \
   CAPTURE_UNEXPECTED_INSTALL_LOG="$capture_unexpected_install_log" \
   /bin/sh "$rendered_capture" status >"$capture_output" 2>"$capture_error" &&
   grep -q '"class":"idle"' "$capture_output" &&
   [ ! -e "$capture_unexpected_id_log" ] &&
   [ ! -e "$capture_unexpected_stat_log" ] &&
   [ ! -e "$capture_unexpected_install_log" ] &&
   ! HOME="$capture_harness/home" \
     LABWC_SESSION_OWNER=other \
     XDG_RUNTIME_DIR=/run/user/1000 \
     /bin/sh "$rendered_capture" status >"$capture_output" 2>"$capture_error" &&
   grep -q 'must run in the managed desktop session' "$capture_error" &&
   ! HOME="$capture_harness/home" \
     LABWC_SESSION_OWNER=desktop \
     XDG_RUNTIME_DIR=/run/user/0 \
     /bin/sh "$rendered_capture" status >"$capture_output" 2>"$capture_error" &&
   grep -q 'requires a non-root desktop runtime directory' "$capture_error"; then
  pass "capture status avoids identity and path-ownership helpers before runtime initialization"
else
  fail "capture status avoids identity and path-ownership helpers before runtime initialization"
fi

if [ "$network_perl_ok" = true ] &&
   grep -Fq 'ok 10 - privileged network module controls and randomizes installer-owned ifupdown adapters' "$network_perl_log"; then
  pass "privileged LAN helper controls and randomizes installer-owned ifupdown adapters"
else
  cat "$network_perl_log" >&2
  fail "privileged LAN helper controls and randomizes installer-owned ifupdown adapters"
fi

if [ "$network_perl_ok" = true ] &&
   grep -Fq 'ok 9 - network client rejects unsafe interfaces and missing confirmations before pkexec' "$network_perl_log"; then
  pass "network wrapper rejects unsafe interfaces and missing confirmations before pkexec"
else
  cat "$network_perl_log" >&2
  fail "network wrapper rejects unsafe interfaces and missing confirmations before pkexec"
fi

if [ "$network_perl_ok" = true ] &&
   grep -Fq 'ok 11 - privileged network module controls and randomizes NetworkManager-owned adapters' "$network_perl_log"; then
  pass "privileged LAN helper controls and randomizes NetworkManager-owned adapters"
else
  cat "$network_perl_log" >&2
  fail "privileged LAN helper controls and randomizes NetworkManager-owned adapters"
fi
