#!/bin/sh
# shellcheck disable=SC2034,SC2329
set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf -- "$TMP_DIR"' EXIT HUP INT TERM

pass() {
  printf 'ok - %s\n' "$1"
}

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

run_target_tree_size_helper() {
  size_bin="$TMP_DIR/size-bin"
  mkdir -p "$size_bin"
  ln -s "$(command -v awk)" "$size_bin/awk"

  (
    PATH=$size_bin
    installer_fatal() {
      printf 'fatal: %s\n' "$*" >&2
      exit 1
    }
    capture_in_target() {
      label=$1
      shift
      [ "$label" = "measure test tree" ]
      [ "$#" -eq 4 ]
      [ "$1" = /usr/bin/du ]
      [ "$2" = -sk ]
      [ "$3" = -- ]
      [ "$4" = /tmp/test-tree ]
      printf '42\t/tmp/test-tree\n'
    }
    # shellcheck disable=SC1090
    . "$ROOT_DIR/d-i/forky/scripts/desktop/components.sh"
    [ "$(desktop_target_tree_size_kib "measure test tree" /tmp/test-tree)" = 42 ]
  )
}

run_android_access_configuration() {
  access_bin="$TMP_DIR/access-bin"
  access_log="$TMP_DIR/access.log"
  access_group_state="$TMP_DIR/access-group.state"
  mkdir -p "$access_bin"
  : >"$access_log"
  rm -f -- "$access_group_state"

  cat >"$access_bin/getent" <<'EOF'
#!/bin/sh
set -eu
if [ "${1:-}" = group ] && [ "${2:-}" = plugdev ]; then
  [ -f "${ANDROID_ACCESS_GROUP_STATE:?}" ] || exit 2
  printf '%s\n' 'plugdev:x:46:desktopuser'
  exit 0
fi
exit 2
EOF
  cat >"$access_bin/groupadd" <<'EOF'
#!/bin/sh
set -eu
[ "$*" = "--system plugdev" ]
printf '%s\n' "$*" >>"${ANDROID_ACCESS_LOG:?}"
: >"${ANDROID_ACCESS_GROUP_STATE:?}"
EOF
  cat >"$access_bin/usermod" <<'EOF'
#!/bin/sh
set -eu
[ "$*" = "-a -G plugdev desktopuser" ]
printf '%s\n' "$*" >>"${ANDROID_ACCESS_LOG:?}"
EOF
  cat >"$access_bin/id" <<'EOF'
#!/bin/sh
set -eu
if [ "${1:-}" = -nG ] && [ "${2:-}" = desktopuser ]; then
  printf '%s\n' 'desktopuser plugdev'
  exit 0
fi
exec /usr/bin/id "$@"
EOF
  for forbidden_command in dpkg-query udevadm; do
    cat >"$access_bin/$forbidden_command" <<'EOF'
#!/bin/sh
printf 'forbidden installer-time verification command executed: %s\n' "$0" >&2
exit 99
EOF
  done
  chmod 0755 "$access_bin"/*

  (
    set -eu
    ACCOUNT_USERNAME=desktopuser
    export ACCOUNT_USERNAME
    ANDROID_ACCESS_BIN=$access_bin
    ANDROID_ACCESS_LOG=$access_log
    ANDROID_ACCESS_GROUP_STATE=$access_group_state
    export ANDROID_ACCESS_BIN ANDROID_ACCESS_LOG ANDROID_ACCESS_GROUP_STATE

    installer_fatal() {
      printf 'fatal: %s\n' "$*" >&2
      exit 1
    }
    desktop_log() {
      :
    }
    run_in_target() {
      label=$1
      shift
      PATH="$ANDROID_ACCESS_BIN:/usr/bin:/bin" "$@"
    }

    # shellcheck disable=SC1090
    . "$components"
    desktop_stage_role_asset() {
      printf 'stage:%s:%s:%s\n' "$1" "$2" "$3" >>"$ANDROID_ACCESS_LOG"
    }
    desktop_configure_android_debug_bridge_access
  )

  grep -Fxq -- '--system plugdev' "$access_log" &&
    grep -Fxq -- '-a -G plugdev desktopuser' "$access_log" &&
    grep -Fxq \
      'stage:etc/udev/rules.d/51-android-debug-bridge.rules:/etc/udev/rules.d/51-android-debug-bridge.rules:0644' \
      "$access_log" &&
    grep -Fxq \
      'stage:etc/udev/rules.d/52-samsung-download-mode.rules:/etc/udev/rules.d/52-samsung-download-mode.rules:0644' \
      "$access_log"
}

desktop_cfg="$ROOT_DIR/d-i/forky/classes/class-select/role/desktop.cfg"
desktop_env="$ROOT_DIR/d-i/forky/hosts/profiles/btrfs/desktop.env"
desktop_hook="$ROOT_DIR/d-i/forky/hooks/role/desktop/late_command.sh"
desktop_labwc="$ROOT_DIR/d-i/forky/scripts/desktop/labwc.sh"
components="$ROOT_DIR/d-i/forky/scripts/desktop/components.sh"
desktop_verify="$ROOT_DIR/d-i/forky/scripts/desktop/verify.sh"
platform_tools_installer="$ROOT_DIR/d-i/forky/scripts/desktop/android-platform-tools.sh"
samloader_installer="$ROOT_DIR/d-i/forky/scripts/desktop/samloader.sh"
labwc_rc="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/labwc/rc.xml.tmpl"
labwc_menu="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/labwc/menu.xml"
computer_management="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-computer-management"
adb_menu="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-adb-menu"
adb_action="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-adb-action"
adb_service="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/systemd/user/labwc-adb-server.service"
adb_module_root="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/lib/perl5/site_perl/labwc-adb"
adb_logger_module="$adb_module_root/AndroidADB/Logger.pm"
adb_server_module="$adb_module_root/AndroidADB/ADB/Server.pm"
adb_backup_module="$adb_module_root/AndroidADB/ADB/Backup.pm"
adb_notification_module="$adb_module_root/AndroidADB/Notification.pm"
adb_samsung_module="$adb_module_root/AndroidADB/Vendor/Samsung.pm"
adb_config_module="$adb_module_root/AndroidADB/Config.pm"
adb_perl_smoke="$ROOT_DIR/t/labwc-adb-perl-smoke.sh"
adb_perl_log="$TMP_DIR/adb-perl-smoke.log"
udev_rules="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/udev/rules.d/51-android-debug-bridge.rules"
samsung_udev_rules="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/udev/rules.d/52-samsung-download-mode.rules"
ledger_udev_rules="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/udev/rules.d/53-ledger-wallet.rules"
samsung_extractor="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/libexec/labwc-samsung-firmware-extract"
adb_rsyslog="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/rsyslog.d/42-adb.conf"
adb_logrotate="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/logrotate.d/adb"
managed_logs_tmpfiles="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/tmpfiles.d/60-security-logs.conf"
apparmor_profile="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/managed-desktop-wrappers"

menu_cancel_bin_dir="$TMP_DIR/menu-cancel-bin"
menu_cancel_stdout="$TMP_DIR/menu-cancel.stdout"
menu_cancel_stderr="$TMP_DIR/menu-cancel.stderr"
menu_failure_stdout="$TMP_DIR/menu-failure.stdout"
menu_failure_stderr="$TMP_DIR/menu-failure.stderr"
mkdir -p "$menu_cancel_bin_dir"
cat >"$menu_cancel_bin_dir/id" <<'EOF'
#!/bin/sh
[ "${1:-}" = -u ] && { printf '%s\n' 1000; exit 0; }
exec /usr/bin/id "$@"
EOF
cat >"$menu_cancel_bin_dir/labwc-fuzzel" <<'EOF'
#!/bin/sh
exit "${FUZZEL_STATUS:?}"
EOF
cat >"$menu_cancel_bin_dir/labwc-adb-action" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod 0755 "$menu_cancel_bin_dir"/*

if PATH="$menu_cancel_bin_dir:/usr/bin:/bin" \
   HOME="$TMP_DIR/home" \
   FUZZEL_STATUS=1 \
   /bin/sh "$adb_menu" >"$menu_cancel_stdout" 2>"$menu_cancel_stderr" &&
   [ ! -s "$menu_cancel_stdout" ] &&
   [ ! -s "$menu_cancel_stderr" ] &&
   ! PATH="$menu_cancel_bin_dir:/usr/bin:/bin" \
     HOME="$TMP_DIR/home" \
     FUZZEL_STATUS=2 \
     /bin/sh "$adb_menu" >"$menu_failure_stdout" 2>"$menu_failure_stderr" &&
   grep -Fq 'unable to open the Android Debug Bridge menu (status 2)' \
     "$menu_failure_stderr"; then
  pass "Android Debug Bridge treats Fuzzel cancellation as Back while surfacing launcher failures"
else
  fail "Android Debug Bridge treats Fuzzel cancellation as Back while surfacing launcher failures"
fi

if ! grep -Eq '(^|[[:space:]])android-sdk-platform-tools-common([[:space:]]|$)' "$desktop_cfg" &&
   grep -Eq '(^|[[:space:]])libusb-1\.0-0([[:space:]]|$)' "$desktop_cfg" &&
   grep -q '^ANDROID_PLATFORM_TOOLS_ARCHITECTURE="amd64"$' "$desktop_env" &&
   grep -q '^ANDROID_PLATFORM_TOOLS_URL="https://dl.google.com/android/repository/platform-tools-latest-linux.zip"$' "$desktop_env" &&
   grep -q '^ANDROID_PLATFORM_TOOLS_MAXIMUM_BYTES="134217728"$' "$desktop_env" &&
   grep -q '^ANDROID_PLATFORM_TOOLS_MAXIMUM_EXTRACTED_BYTES="536870912"$' "$desktop_env" &&
   grep -q '^SAMLOADER_VERSION="2.0.0"$' "$desktop_env" &&
   grep -q '^SAMLOADER_ARCHITECTURE="amd64"$' "$desktop_env" &&
   grep -q '^SAMLOADER_SHA256="7c6514028f20d5ea0eb57d6f872eee41b3a52336eabac6379b15a01a06ed7a79"$' "$desktop_env"; then
  pass "desktop policy bounds official Android tools and pins samloader-rs with its libusb runtime"
else
  fail "desktop policy bounds official Android tools and pins samloader-rs with its libusb runtime"
fi

if grep -q 'for desktop_module in detect components satty xwayland waypaper android-platform-tools samloader digital-assets labwc' "$desktop_hook" &&
   grep -Fqx ". \"\${desktop_module_dir}/android-platform-tools.sh\"" "$desktop_hook" &&
   grep -Fqx ". \"\${desktop_module_dir}/samloader.sh\"" "$desktop_hook" &&
   grep -q '^  desktop_android_platform_tools_preflight_target_architecture$' "$desktop_labwc" &&
   grep -q '^  desktop_samloader_preflight_target_architecture$' "$desktop_labwc" &&
   grep -q '^  desktop_install_android_platform_tools$' "$desktop_labwc" &&
   grep -q '^  desktop_install_samloader$' "$desktop_labwc" &&
   grep -q '^  desktop_configure_android_debug_bridge_access$' "$desktop_labwc" &&
   grep -q '^  desktop_configure_fido2_security_key_access$' "$desktop_labwc"; then
  pass "desktop late-command loads and executes Platform-Tools, samloader-rs, and USB security-key policy modules"
else
  fail "desktop late-command loads and executes Platform-Tools, samloader-rs, and USB security-key policy modules"
fi

if /bin/sh -n "$platform_tools_installer" &&
   grep -q -- "--proto '=https'" "$platform_tools_installer" &&
   grep -q -- '--connect-timeout 15' "$platform_tools_installer" &&
   grep -q -- '--max-time 300' "$platform_tools_installer" &&
   grep -Fq -- "--max-filesize \"\$ANDROID_PLATFORM_TOOLS_MAXIMUM_BYTES\"" "$platform_tools_installer" &&
   ! grep -q -- '-quit' "$platform_tools_installer" &&
   ! grep -Fq "tr -d '[:space:]'" "$platform_tools_installer" &&
   grep -Fq "sed -n '1p'" "$platform_tools_installer" &&
   grep -Fq 'find "$platform_tools_staged_host" -type d -exec chmod 0755 {} \;' "$platform_tools_installer" &&
   grep -Fq 'find "$platform_tools_staged_host" -type f -exec chmod 0644 {} \;' "$platform_tools_installer" &&
   grep -q "downloaded archive contains an unsafe member path" "$platform_tools_installer" &&
   grep -q "downloaded archive contains too many members" "$platform_tools_installer" &&
   grep -q "unsupported node" "$platform_tools_installer" &&
   grep -Fq 'desktop_target_tree_size_kib \' "$platform_tools_installer" &&
   ! grep -Eq '^[[:space:]]+du -sk' "$platform_tools_installer" &&
   grep -q "Pkg.Revision" "$platform_tools_installer" &&
   grep -q "ELF 64-bit.*x86-64" "$platform_tools_installer" &&
   grep -Fq 'ln -sfn ../lib/android-sdk/platform-tools/adb /target/usr/local/bin/adb' "$platform_tools_installer" &&
   grep -Fq 'ln -sfn ../lib/android-sdk/platform-tools/fastboot /target/usr/local/bin/fastboot' "$platform_tools_installer" &&
   ! grep -Eq '(^|[[:space:]])adb([[:space:]].*)?start-server' "$platform_tools_installer"; then
  pass "latest Google archive installation is bounded, shape-validated, and never starts the ADB server"
else
  fail "latest Google archive installation is bounded, shape-validated, and never starts the ADB server"
fi

if /bin/sh -n "$samloader_installer" &&
   grep -q -- "--proto '=https'" "$samloader_installer" &&
   grep -Fq -- "--max-filesize \"\$SAMLOADER_MAXIMUM_BYTES\"" "$samloader_installer" &&
   ! grep -q -- '-quit' "$samloader_installer" &&
   ! grep -Fq "tr -d '[:space:]'" "$samloader_installer" &&
   grep -Fq "sed -n '1p'" "$samloader_installer" &&
   grep -q '7c6514028f20d5ea0eb57d6f872eee41b3a52336eabac6379b15a01a06ed7a79' "$samloader_installer" &&
   grep -q 'downloaded archive contains an unsafe or unexpected member' "$samloader_installer" &&
   grep -Fq 'desktop_target_tree_size_kib \' "$samloader_installer" &&
   ! grep -Eq '^[[:space:]]+du -sk' "$samloader_installer" &&
   grep -q 'ELF 64-bit.*x86-64' "$samloader_installer" &&
   grep -Fq 'ln -sfn ../lib/samloader/samloader /target/usr/local/bin/samloader' "$samloader_installer" &&
   grep -Fq '/usr/bin/timeout 20s /usr/local/lib/samloader/samloader --version' "$samloader_installer"; then
  pass "samloader-rs installation is pinned, checksum-verified, shape-validated, and version-checked"
else
  fail "samloader-rs installation is pinned, checksum-verified, shape-validated, and version-checked"
fi

if /bin/sh -n "$components" &&
   grep -Fq '/usr/bin/du -sk -- "$target_path"' "$components" &&
   run_target_tree_size_helper; then
  pass "desktop archive size checks run target-side and do not require installer du"
else
  fail "desktop archive size checks run target-side and do not require installer du"
fi

if grep -q '^desktop_configure_android_debug_bridge_access() {$' "$components" &&
   grep -q 'getent group plugdev' "$components" &&
   grep -q 'usermod -a -G plugdev' "$components" &&
   ! grep -q 'dpkg-query\\|udevadm\\|android-sdk-platform-tools-common' "$components" &&
   ! grep -Fq "\${Status}" "$components" &&
   grep -q 'etc/udev/rules.d/51-android-debug-bridge.rules' "$components" &&
   grep -q 'etc/udev/rules.d/52-samsung-download-mode.rules' "$components" &&
   grep -q 'desktop_stage_role_asset usr/local/bin/labwc-adb-menu /usr/local/bin/labwc-adb-menu 0755' "$components" &&
   grep -q 'desktop_stage_role_asset usr/local/bin/labwc-adb-action /usr/local/bin/labwc-adb-action 0755' "$components" &&
   grep -q 'desktop_stage_role_asset etc/skel/.config/systemd/user/labwc-adb-server.service /etc/skel/.config/systemd/user/labwc-adb-server.service 0644' "$components" &&
   grep -Fq 'AndroidADB/Logger.pm' "$components" &&
   grep -q 'labwc-samsung-firmware-extract' "$components"; then
  pass "desktop staging grants only the primary account plugdev access and installs managed ADB and Samsung assets"
else
  fail "desktop staging grants only the primary account plugdev access and installs managed ADB and Samsung assets"
fi

if grep -Fq 'etc/rsyslog.d/42-adb.conf' "$components" &&
   grep -Fq 'etc/logrotate.d/adb' "$components" &&
   grep -Fq 'file="/var/log/managed/adb/adb.log"' "$adb_rsyslog" &&
   grep -Fq '$programname == "labwc-adb"' "$adb_rsyslog" &&
   grep -Fq '$msg contains "source=android-debug-bridge"' "$adb_rsyslog" &&
   grep -Fq '$msg contains "labwc-adb-server.service"' "$adb_rsyslog" &&
   grep -Fqx '/var/log/managed/adb/adb.log' "$adb_logrotate" &&
   grep -Fqx 'd /var/log/managed/adb 0750 root adm -' "$managed_logs_tmpfiles" &&
   grep -Fqx 'f /var/log/managed/adb/adb.log 0640 root adm -' "$managed_logs_tmpfiles" &&
   grep -Fq "openlog('labwc-adb'" "$adb_logger_module" &&
   grep -Fq '/dev/log w,' "$apparmor_profile" &&
   grep -Fq '/run/systemd/journal/dev-log w,' "$apparmor_profile" &&
   grep -Fq 'member={GetUnit,LoadUnit,ResetFailedUnit,StartUnit,StopUnit,RestartUnit}' "$apparmor_profile"; then
  pass "ADB menu, application, daemon, and systemd lifecycle events route to the protected managed ADB log"
else
  fail "ADB menu, application, daemon, and systemd lifecycle events route to the protected managed ADB log"
fi

if grep -Fqx '  @{PROC}/@{pid}/net/{tcp,tcp6,udp,udp6} r,' "$apparmor_profile" &&
   ! grep -Fq 'owner @{PROC}/@{pid}/net/' "$apparmor_profile" &&
   ! grep -Eq '@\{PROC\}/(\[0-9\]\*|\*\*)/net/' "$apparmor_profile"; then
  pass "ADB may inspect only its own procfs network namespace tables without relying on inode ownership"
else
  fail "ADB procfs network namespace access remains missing, owner-qualified, or over-broad"
fi

if run_android_access_configuration; then
  pass "installer-time Android access configuration is set-u safe and only stages udev policy"
else
  fail "installer-time Android access configuration is set-u safe and only stages udev policy"
fi

if grep -q '^desktop_configure_fido2_security_key_access() {$' "$components" &&
   grep -q 'etc/udev/rules.d/53-ledger-wallet.rules' "$components" &&
   grep -q '/etc/udev/rules.d/53-ledger-wallet.rules' "$desktop_verify" &&
   grep -q 'SUBSYSTEM=="usb".*ATTR{idVendor}=="2c97".*TAG+="uaccess"' "$ledger_udev_rules" &&
   grep -q 'SUBSYSTEM=="hidraw".*ATTRS{idVendor}=="2c97".*TAG+="uaccess"' "$ledger_udev_rules" &&
   ! grep -q 'MODE="0666"' "$ledger_udev_rules" &&
   ! grep -Eq 'pam_u2f|pam_fido2|sudoers' "$components" "$desktop_labwc" "$ledger_udev_rules" &&
   if command -v udevadm >/dev/null 2>&1; then
     udevadm verify --resolve-names=never "$ledger_udev_rules" >/dev/null
   else
     true
   fi
then
  pass "desktop staging enables active-seat Ledger Stax browser FIDO2 access without PAM or sudo integration"
else
  fail "desktop staging enables active-seat Ledger Stax browser FIDO2 access without PAM or sudo integration"
fi

vendor_rules_ok=true
for vendor_id in \
  18d1 \
  04e8 \
  22b8 \
  0fce \
  1004 \
  0bb4 \
  12d1 \
  2717 \
  22d9 \
  2a70 \
  2e04 \
  19d2 \
  0b05 \
  1949 \
  2ae5 \
  05c6 \
  0e8d
do
  grep -Fq "ATTR{idVendor}==\"${vendor_id}\"" "$udev_rules" ||
    vendor_rules_ok=false
done
if [ "$vendor_rules_ok" = true ] &&
   grep -Fq 'ENV{ID_USB_INTERFACES}!="*:ff42??:*"' "$udev_rules" &&
   grep -Fq 'ENV{ID_USB_INTERFACES}!="*:ef0201:*"' "$udev_rules" &&
   grep -Fq 'MODE="0660", GROUP="plugdev", TAG+="uaccess"' "$udev_rules"; then
  pass "managed udev policy covers common OEMs while matching only Android debug interfaces"
else
  fail "managed udev policy covers common OEMs while matching only Android debug interfaces"
fi

download_mode_rules_ok=true
for product_id in 6601 685d 68c3; do
  grep -Fq "ATTR{idProduct}==\"${product_id}\"" "$samsung_udev_rules" ||
    download_mode_rules_ok=false
done
if [ "$download_mode_rules_ok" = true ] &&
   grep -Fq 'ATTR{idVendor}!="04e8"' "$samsung_udev_rules" &&
   grep -Fq 'MODE="0660", GROUP="plugdev", TAG+="uaccess"' "$samsung_udev_rules"; then
  pass "Samsung Download Mode access is limited to samloader-rs supported product identifiers"
else
  fail "Samsung Download Mode access is limited to samloader-rs supported product identifiers"
fi

if ! grep -q '<keybind key="C-W-a">' "$labwc_rc" &&
   grep -q 'label="Computer Management"' "$labwc_menu" &&
   grep -q 'command="labwc-computer-management"' "$labwc_menu" &&
   grep -q '" Phone Management"' "$computer_management" &&
   grep -q 'run_command labwc-adb-menu' "$computer_management"; then
  pass "Computer Management exposes the complete Android Debug Bridge launcher"
else
  fail "Computer Management exposes the complete Android Debug Bridge launcher"
fi

adb_menu_catalog_ok=true
for label in \
  'Start ADB Server' \
  'Repair / Restart ADB Server' \
  'Stop ADB Server' \
  'Reconnect USB Devices' \
  'Reconnect Offline Devices' \
  'Wait for Any Device (60s)' \
  'Diagnose Device Connections' \
  'Open Interactive Shell' \
  'Install / Replace APK' \
  'Grant Runtime Permission' \
  'Push File to Download' \
  'Pull Device File or Folder' \
  'Save Screenshot' \
  'Record Screen (30s)' \
  'Collect Bugreport' \
  'Pair with Pairing Code' \
  'Enable Legacy TCP/IP Port 5555' \
  'Forward Host TCP to Device TCP' \
  'Reboot to Recovery' \
  'Reboot to Bootloader' \
  'Backup Device' \
  'Download Official Samsung Firmware' \
  'Flash Official Firmware (Keep Data)' \
  'Flash Official Firmware (Factory Reset)' \
  'Show Fastboot Device Information'
do
  grep -Fq "'${label}'" "$adb_menu" || adb_menu_catalog_ok=false
done
if [ "$adb_menu_catalog_ok" = true ] &&
   grep -q "' ADB Server'" "$adb_menu" &&
   grep -q "' Fastboot'" "$adb_menu" &&
   grep -q 'Continue with authorized ADB action' "$adb_menu" &&
   grep -q 'FLASH HOME_CSC' "$adb_menu" &&
   grep -q 'FACTORY RESET' "$adb_menu"; then
  pass "Android Debug Bridge exposes backup plus strongly-confirmed Samsung download and flash actions"
else
  fail "Android Debug Bridge exposes backup plus strongly-confirmed Samsung download and flash actions"
fi

adb_perl_ok=false
if /bin/sh "$adb_perl_smoke" >"$adb_perl_log" 2>&1; then
  adb_perl_ok=true
fi

if [ "$adb_perl_ok" = true ] &&
   /bin/sh -n "$adb_menu" &&
   python3 -m py_compile "$samsung_extractor" &&
   grep -q '^sub ensure_responsive {$' "$adb_server_module" &&
   grep -q '^sub start_via_service {$' "$adb_server_module" &&
   grep -q '^sub repair_via_service {$' "$adb_server_module" &&
   grep -q '^sub stop_via_service {$' "$adb_server_module" &&
   grep -q "ADB server is stopped; start it from the Android Debug Bridge launcher" "$adb_server_module" &&
   grep -q "refusing process-table discovery or name-wide termination" "$adb_server_module" &&
   ! find "$adb_module_root" -type f -name '*.pm' \
     -exec grep -Eq '(^|[^[:alnum:]_])(pgrep|pkill|pidof)([^[:alnum:]_]|$)' {} + &&
   grep -q 'wait-for-device' "$adb_module_root/AndroidADB/Runtime.pm" &&
   grep -q 'timed out waiting for device' "$adb_module_root/AndroidADB/ADB/Device.pm" &&
   grep -q '^    run_adb_action wait-any-device$' "$adb_menu" &&
   grep -q 'accept the RSA USB-debugging prompt' "$adb_module_root/AndroidADB/ADB/Device.pm" &&
   grep -q 'desktop session lacks USB permission' "$adb_module_root/AndroidADB/ADB/Device.pm" &&
   grep -Fq 'for my $override (qw(ADB_SERVER_SOCKET ANDROID_ADB_SERVER_PORT))' "$adb_config_module" &&
   grep -q '^sub backup {$' "$adb_backup_module" &&
   grep -q '^sub download {$' "$adb_samsung_module" &&
   grep -q '^sub flash {$' "$adb_samsung_module" &&
   grep -q '^sub notify_result {$' "$adb_notification_module" &&
   grep -Fq "'-a', 'Android Device'" "$adb_notification_module" &&
   grep -Fq "'-c', 'x-labwc.maintenance'" "$adb_notification_module" &&
   [ -f "$adb_service" ] &&
   grep -Fqx 'ExecStart=/usr/local/bin/labwc-adb-action --service start' "$adb_service" &&
   grep -Fqx 'ExecStop=/usr/local/bin/labwc-adb-action --service stop' "$adb_service" &&
   grep -Fqx 'Environment=HOME=%h' "$adb_service" &&
   grep -Fqx 'Environment=XDG_RUNTIME_DIR=%t' "$adb_service" &&
   grep -Fqx 'SyslogIdentifier=labwc-adb' "$adb_service" &&
   grep -Fqx 'StandardOutput=journal' "$adb_service" &&
	   grep -Fqx 'StandardError=journal' "$adb_service" &&
	   grep -Fqx 'RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6 AF_NETLINK' "$adb_service" &&
	   grep -Fqx 'ConditionEnvironment=LABWC_SESSION_OWNER=desktop' "$adb_service" &&
	   grep -Fqx 'ConditionEnvironment=WAYLAND_DISPLAY' "$adb_service" &&
	   grep -Fqx 'ConditionEnvironment=XDG_SESSION_TYPE=wayland' "$adb_service" &&
	   grep -Fqx 'Requisite=labwc-session.target' "$adb_service" &&
	   grep -Fqx 'After=labwc-session.target' "$adb_service" &&
	   grep -Fqx 'PartOf=labwc-session.target' "$adb_service" &&
	   grep -Fqx 'RemainAfterExit=yes' "$adb_service" &&
	   ! grep -Fq 'ExecCondition=' "$adb_service" &&
	   ! grep -Fq '[Install]' "$adb_service" &&
   ! grep -Fq '    labwc-adb-server.service \' "$components" &&
   grep -Fq "elsif (@argv && \$argv[0] eq '--service')" "$adb_module_root/AndroidADB/CLI.pm" &&
   grep -Fq "'reset-failed'," "$adb_server_module" &&
   grep -q '^sub run_service_action {$' "$adb_module_root/AndroidADB/Runtime.pm" &&
   grep -Fq "? (\$firmware->{home_csc}, 'HOME_CSC')" "$adb_samsung_module" &&
   grep -Fq ": (\$firmware->{csc}, 'CSC');" "$adb_samsung_module" &&
   grep -q 'exactly one supported Samsung Download Mode device is required' "$adb_samsung_module"; then
  pass "ADB actions provide bounded operations, fail-closed firmware handling, and Mako results"
else
  cat "$adb_perl_log" >&2
  fail "ADB actions provide bounded operations, fail-closed firmware handling, and Mako results"
fi

required_command_block=$(
  sed -n '/^for cmd in \\/,/^do$/p' "$desktop_verify"
)
if ! printf '%s\n' "$required_command_block" |
  grep -Eq '^[[:space:]]+(adb|fastboot|samloader)[[:space:]]+\\$'
then
  pass "adb, fastboot, and samloader remain outside desktop_verify_required_commands"
else
  fail "adb, fastboot, and samloader remain outside desktop_verify_required_commands"
fi

menu_bin_dir="$TMP_DIR/menu-bin"
menu_responses="$TMP_DIR/menu-responses"
menu_action_log="$TMP_DIR/menu-action.log"
menu_fuzzel_log="$TMP_DIR/menu-fuzzel.log"
menu_device_state="$TMP_DIR/menu-device.state"
mkdir -p "$menu_bin_dir"
printf '%s\n' waiting >"$menu_device_state"
cat >"$menu_responses" <<'EOF'
 ADB Server
Start ADB Server
← Back
 Devices & Shell
ABC123 [device] Pixel_9
Show Device Summary
← Back
 Reboot & Recovery
ABC123 [device] Pixel_9
Backup Device
Continue with authorized ADB action
← Back
← Back
EOF
cat >"$menu_bin_dir/id" <<'EOF'
#!/bin/sh
[ "${1:-}" = -u ] && { printf '%s\n' 1000; exit 0; }
exec /usr/bin/id "$@"
EOF
cat >"$menu_bin_dir/labwc-fuzzel" <<'EOF'
#!/bin/sh
set -eu
cat >>"${FUZZEL_LOG:?}"
response=$(sed -n '1p' "${FUZZEL_RESPONSES:?}")
sed '1d' "$FUZZEL_RESPONSES" >"${FUZZEL_RESPONSES}.next"
mv "${FUZZEL_RESPONSES}.next" "$FUZZEL_RESPONSES"
printf '%s\n' "$response"
EOF
cat >"$menu_bin_dir/labwc-adb-action" <<'EOF'
#!/bin/sh
set -eu
case "${1:-}" in
  --menu-devices)
    if [ "$(cat "${ADB_MENU_DEVICE_STATE:?}")" = ready ]; then
      printf '%s\n' 'ABC123 [device] Pixel_9'
    fi
    exit 0
    ;;
  --menu-fastboot-devices)
    printf '%s\n' 'FAST123 [fastboot] product:pixel'
    exit 0
    ;;
esac
printf '%s\n' "$*" >>"${ADB_ACTION_LOG:?}"
if [ "${1:-}" = wait-any-device ]; then
  printf '%s\n' ready >"${ADB_MENU_DEVICE_STATE:?}"
fi
EOF
chmod 0755 "$menu_bin_dir"/*

if PATH="$menu_bin_dir:/usr/bin:/bin" \
   HOME="$TMP_DIR/home" \
   FUZZEL_LOG="$menu_fuzzel_log" \
   FUZZEL_RESPONSES="$menu_responses" \
   ADB_ACTION_LOG="$menu_action_log" \
   ADB_MENU_DEVICE_STATE="$menu_device_state" \
   /bin/sh "$adb_menu" &&
   [ "$(cat "$menu_action_log")" = "start-server
wait-any-device
device-summary ABC123
backup-device ABC123 confirmed-adb-action" ] &&
   grep -Fxq 'LABWC_FUZZEL_MANAGED_ICONS=1' "$adb_menu" &&
   grep -Fxq 'choose_menu_input() {' "$adb_menu" &&
   ! grep -Fq '|| true' "$adb_menu" &&
   grep -Fq "' Fastboot' \\" "$adb_menu" &&
   grep -Fq "'← Back'" "$adb_menu" &&
   grep -q ' ADB Server' "$menu_fuzzel_log" &&
   grep -q ' Devices & Shell' "$menu_fuzzel_log" &&
   grep -q '← Back' "$menu_fuzzel_log"; then
  pass "nested Android Debug Bridge Fuzzel choices dispatch fixed action identifiers"
else
  fail "nested Android Debug Bridge Fuzzel choices dispatch fixed action identifiers"
fi

if [ "$adb_perl_ok" = true ] &&
   grep -Fq 'ok 4 - ADB server control fails closed for stopped or unresponsive managed servers without process-wide termination' "$adb_perl_log"; then
  pass "an unresponsive managed ADB server fails closed without process discovery or name-wide termination"
else
  cat "$adb_perl_log" >&2
  fail "an unresponsive managed ADB server fails closed without process discovery or name-wide termination"
fi

if [ "$adb_perl_ok" = true ] &&
   grep -Fq 'ok 4 - ADB server control fails closed for stopped or unresponsive managed servers without process-wide termination' "$adb_perl_log"; then
  pass "showing launcher server status does not start or contact a stopped ADB server"
else
  cat "$adb_perl_log" >&2
  fail "showing launcher server status does not start or contact a stopped ADB server"
fi

if [ "$adb_perl_ok" = true ] &&
   grep -Fq 'ok 5 - ADB backup atomically stores shared data, metadata, status, and integrity hashes' "$adb_perl_log"; then
  pass "Backup Device atomically stores ADB-readable data, metadata, status, and integrity hashes"
else
  cat "$adb_perl_log" >&2
  fail "Backup Device atomically stores ADB-readable data, metadata, status, and integrity hashes"
fi

firmware_zip="$TMP_DIR/firmware.zip"
firmware_extract_dir="$TMP_DIR/firmware-extract"
malicious_zip="$TMP_DIR/malicious.zip"
malicious_extract_dir="$TMP_DIR/malicious-extract"
python3 - "$firmware_zip" "$malicious_zip" <<'PY'
import stat
import sys
import zipfile

firmware_zip, malicious_zip = sys.argv[1:]
with zipfile.ZipFile(firmware_zip, "w") as archive:
    for name in (
        "BL_TEST.tar.md5",
        "AP_TEST.tar.md5",
        "CP_TEST.tar.md5",
        "CSC_TEST.tar.md5",
        "HOME_CSC_TEST.tar.md5",
    ):
        archive.writestr(name, b"firmware")
with zipfile.ZipFile(malicious_zip, "w") as archive:
    archive.writestr("../escape", b"escape")
    symlink = zipfile.ZipInfo("link")
    symlink.create_system = 3
    symlink.external_attr = (stat.S_IFLNK | 0o777) << 16
    archive.writestr(symlink, b"target")
PY
mkdir "$firmware_extract_dir" "$malicious_extract_dir"
if python3 "$samsung_extractor" "$firmware_zip" "$firmware_extract_dir" &&
   [ -f "$firmware_extract_dir/BL_TEST.tar.md5" ] &&
   [ -f "$firmware_extract_dir/HOME_CSC_TEST.tar.md5" ] &&
   ! python3 "$samsung_extractor" "$malicious_zip" "$malicious_extract_dir" >/dev/null 2>&1 &&
   [ ! -e "$TMP_DIR/escape" ]; then
  pass "Samsung firmware extraction accepts regular packages and rejects traversal and symlink members"
else
  fail "Samsung firmware extraction accepts regular packages and rejects traversal and symlink members"
fi

if command -v udevadm >/dev/null 2>&1; then
  if udevadm verify --resolve-names=never "$udev_rules" "$samsung_udev_rules" >/dev/null; then
    pass "managed Android and Samsung udev rules parse successfully"
  else
    fail "managed Android and Samsung udev rules parse successfully"
  fi
fi
