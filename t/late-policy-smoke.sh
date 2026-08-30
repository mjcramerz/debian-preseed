#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/late-policy-smoke.XXXXXX")
trap 'rm -rf "$TMP_DIR"' EXIT HUP INT TERM

TEST_COUNT=48
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

common_lib="$ROOT_DIR/d-i/forky/scripts/common/lib.sh"
if grep -Fq 'live_log_max_bytes=${INSTALLER_LIVE_LOG_MAX_BYTES:-4194304}' "$common_lib" &&
   grep -Fq "printf '%s\\n' \"\$live_log_max_bytes\"" "$common_lib" &&
   ! grep -Fq "printf '%s\\n' \"\$INSTALLER_LIVE_LOG_MAX_BYTES\"" "$common_lib"; then
  pass "installer live-log byte limit handles unset values under set -u"
else
  fail "installer live-log byte limit handles unset values under set -u"
fi

target_locale_c_report="$TMP_DIR/target-locale-c.report"
: >"$target_locale_c_report"
find "$ROOT_DIR/d-i/forky/hooks" -path '*/target/*' -type f -print |
  while IFS= read -r target_script; do
    target_script_header=$(sed -n '1p' "$target_script")
    case "$target_script_header" in
      '#!'*) ;;
      *) continue ;;
    esac
    # Byte-oriented sorting and input-size accounting may scope LC_ALL=C to one
    # command. Persistent script locales and embedded subprocess environments
    # must remain UTF-8 capable.
    if target_locale_c_matches=$(
      grep -nE "(^[[:space:]]*(export[[:space:]]+)?(LC_ALL|LANG|LANGUAGE|LC_[A-Z_]+)[[:space:]]*=[[:space:]]*['\"]?C['\"]?[[:space:]]*(;[[:space:]]*)?(#.*)?$)|\"(LC_ALL|LANG|LANGUAGE|LC_[A-Z_]+)\"[[:space:]]*:[[:space:]]*\"C\"" \
        "$target_script"
    ); then
      printf '%s\n%s\n' "$target_script" "$target_locale_c_matches"
    fi
  done >"$target_locale_c_report"
if [ ! -s "$target_locale_c_report" ]; then
  pass "staged target scripts keep persistent locale overrides UTF-8 and scope bytewise C operations locally"
else
  cat "$target_locale_c_report" >&2
  fail "staged target scripts keep persistent locale overrides UTF-8 and scope bytewise C operations locally"
fi

early_dispatch="$ROOT_DIR/d-i/forky/scripts/early/dispatch.sh"
prepkgsel_secure_boot="$ROOT_DIR/d-i/forky/hooks/shared/pre-pkgsel.d/90secure-boot-dkms.sh"
prepkgsel_cuda_legacy="$ROOT_DIR/d-i/forky/hooks/shared/pre-pkgsel.d/91cuda-legacy-apt.sh"
prepkgsel_nvidia_legacy="$ROOT_DIR/d-i/forky/hooks/shared/pre-pkgsel.d/92nvidia-legacy-dkms.sh"
legacy_package_log_name=$(printf '%s%s\n' '07-' 'packages.log')
legacy_default_release_staging_function=$(printf '%s%s\n' 'stage_target_apt_' 'default_release_asset')
if grep -q '^installer_ensure_log_files$' "$early_dispatch" &&
   grep -Fq 'archive_mode=${1:-copy}' "$common_lib" &&
   grep -Fq "printf '%s\\n' /tmp/installer.log" "$common_lib" &&
   grep -Fq 'installer_runtime_log_file' "$prepkgsel_secure_boot" &&
   grep -Fq 'installer_runtime_log_file' "$prepkgsel_cuda_legacy" &&
   grep -Fq 'installer_runtime_log_file' "$prepkgsel_nvidia_legacy" &&
   ! grep -R -q -- "$legacy_package_log_name" "$ROOT_DIR/d-i/forky/hooks/shared/pre-pkgsel.d"; then
  pass "installer logging writes every stage and package hook to one installer.log"
else
  fail "installer logging writes every stage and package hook to one installer.log"
fi

target_output="$TMP_DIR/target-output.log"
target_output_log="$TMP_DIR/target-output-installer.log"
printf '%s\n' 'E: package repair failed' >"$target_output"
if INSTALLER_DEBUG_LOGS=1 INSTALLER_LOG_LEVEL=debug \
   sh -c '
     set -eu
     . "$1"
     test_runtime_log_file=$2
     installer_runtime_log_file() {
       printf "%s\n" "$test_runtime_log_file"
     }
     installer_log_target_command_output package package_install in-target "$3" error
   ' sh "$common_lib" "$target_output_log" "$target_output" &&
   grep -q 'stage=package_install level=error component=in-target E: package repair failed' "$target_output_log"; then
  pass "failed target command output remains visible at error level"
else
  fail "failed target command output remains visible at error level"
fi

runtime_env="$ROOT_DIR/d-i/forky/hosts/shared/runtime.env"
if grep -q '^DIR_POLKIT_LOCAL_RULES_D=' "$runtime_env" &&
   grep -q '^DIR_POLKIT_RUNTIME_RULES_D=' "$runtime_env" &&
   grep -q '^DIR_DBUS_SESSION_SERVICES=' "$runtime_env" &&
   grep -q '^DIR_DBUS_LOCAL_SESSION_SERVICES=' "$runtime_env" &&
   ! grep -q '^POLKIT_MANAGED_RULE_FILES=' "$runtime_env"; then
  pass "runtime env defines polkit target paths and shared dbus service directories"
else
  fail "runtime env defines polkit target paths and shared dbus service directories"
fi

desktop_components="$ROOT_DIR/d-i/forky/scripts/desktop/components.sh"
polkit_tmpfiles="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/tmpfiles.d/70-polkit-runtime.conf"
if grep -q '^d __INSTALLER_DIR_POLKIT_RUNTIME_RULES_D__ 0755 root root -$' "$polkit_tmpfiles" &&
   grep -q '^d __INSTALLER_DIR_POLKIT_LOCAL_RULES_D__ 0755 root root -$' "$polkit_tmpfiles"; then
  pass "desktop polkit tmpfiles file renders runtime path placeholders"
else
  fail "desktop polkit tmpfiles file renders runtime path placeholders"
fi

polkit_rules_ok=true
login1_power_rule="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/polkit-1/rules.d/20-login1-power.rules"
for polkit_rule in \
  05-active-local-gate.rules \
  10-pkexec.rules \
  20-login1-power.rules \
  40-networkmanager.rules \
  50-usb-policy.rules \
  55-software-management.rules \
  60-system-services-identity.rules \
  70-hardware-peripherals.rules
do
  polkit_rule_path="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/polkit-1/rules.d/$polkit_rule"
  if ! grep -q 'subject.active === true && subject.local === true' "$polkit_rule_path" ||
     grep -q 'subject.seat' "$polkit_rule_path"; then
    polkit_rules_ok=false
    break
  fi
done
if [ "$polkit_rules_ok" = true ] &&
   grep -q 'id === "org.freedesktop.login1.inhibit-delay-shutdown"' "$login1_power_rule" &&
   grep -A6 'id === "org.freedesktop.login1.inhibit-delay-shutdown"' "$login1_power_rule" |
     grep -q 'return polkit.Result.YES;' &&
   ! grep -q 'org.freedesktop.login1.inhibit-delay-sleep' "$login1_power_rule" &&
   [ ! -e "$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/polkit-1/rules.d/19-login1-sleep-inhibitor.rules" ] &&
   grep -q 'return polkit.Result.AUTH_ADMIN;' "$login1_power_rule"; then
  pass "managed polkit rules authorize only the shutdown delay inhibitor without weakening power authentication"
else
  fail "managed polkit rules authorize only the shutdown delay inhibitor without weakening power authentication"
fi

fwupd_refresh_rule="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/polkit-1/rules.d/04-fwupd-refresh.rules"
fwupd_refresh_dropin="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/systemd/system/fwupd-refresh.service.d/10-success-exit-status.conf"
fwupd_daemon_dropin="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/systemd/system/fwupd.service.d/20-managed-upower-ordering.conf"
storage_script="$ROOT_DIR/d-i/forky/scripts/late/storage-maintenance.sh"
if [ ! -e "$fwupd_refresh_rule" ] &&
   [ ! -e "$fwupd_refresh_dropin" ] &&
   ! sed -n '/^desktop_polkit_managed_rule_files() {$/,/^}$/p' "$desktop_components" |
     grep -qx '04-fwupd-refresh.rules' &&
   grep -q 'desktop_mask_unit_if_available fwupd-refresh.service system' "$desktop_components" &&
   grep -q 'desktop_mask_unit_if_available fwupd-refresh.timer system' "$desktop_components" &&
   grep -q '^After=upower.service$' "$fwupd_daemon_dropin" &&
   ! grep -q 'fwupd-refresh.service.d/10-success-exit-status.conf' "$storage_script" &&
   grep -q 'etc/systemd/system/fwupd.service.d/20-managed-upower-ordering.conf|/etc/systemd/system/fwupd.service.d/20-managed-upower-ordering.conf|0644' "$storage_script"; then
  pass "automatic fwupd refresh is masked while daemon-before-UPower shutdown ordering remains staged"
else
  fail "automatic fwupd refresh is masked while daemon-before-UPower shutdown ordering remains staged"
fi

account_script="$ROOT_DIR/d-i/forky/scripts/late/account.sh"
if grep -q '^desktop_polkit_managed_rule_files() {$' "$desktop_components" &&
   grep -q '^desktop_configure_usb_media_access() {$' "$desktop_components" &&
   grep -q 'desktop_render_role_target_template \\' "$desktop_components" &&
   grep -q 'etc/tmpfiles.d/70-polkit-runtime.conf' "$desktop_components" &&
   grep -q 'desktop_stage_role_asset \\' "$desktop_components" &&
   ! grep -q 'polkit_managed_rule_files' "$account_script"; then
  pass "desktop role owns managed polkit and USB media policy staging"
else
  fail "desktop role owns managed polkit and USB media policy staging"
fi

shared_profile="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/skel/.profile"
shared_bash_profile="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/skel/.bash_profile"
shared_bashrc="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/skel/.bashrc"
if [ -r "$shared_profile" ] &&
   [ -r "$shared_bash_profile" ] &&
   [ -r "$shared_bashrc" ] &&
   sh -n "$shared_profile" &&
   bash -n "$shared_bash_profile" &&
   bash -n "$shared_bashrc" &&
   ! grep -q '^alias ' "$shared_profile" &&
   grep -q '^umask 077$' "$shared_profile" &&
   ! grep -q '\. "\$HOME/\.bashrc"' "$shared_profile" &&
   grep -q '\. "\$HOME/\.profile"' "$shared_bash_profile" &&
   grep -q '\. "\$HOME/\.bashrc"' "$shared_bash_profile" &&
   grep -q '^alias ll=' "$shared_bashrc" &&
   ! grep -q 'luks-mok-' "$shared_bashrc"; then
  pass "shared shell assets are syntax-valid, keep login env in .profile, and do not inject MOK aliases"
else
  fail "shared shell assets are syntax-valid, keep login env in .profile, and do not inject MOK aliases"
fi

if grep -q '^stage_target_account_shell_assets() {$' "$account_script" &&
   grep -q 'etc/skel/.profile' "$account_script" &&
   grep -q 'etc/skel/.bash_profile' "$account_script" &&
   grep -q 'etc/skel/.bashrc' "$account_script" &&
   grep -q '^install_target_account_shell_assets() {$' "$account_script" &&
   grep -Fq 'install -d -m 0700 "$account_home"' "$account_script" &&
   grep -Fq 'install -m 0600 "$src" "$dst"' "$account_script" &&
   grep -q 'install managed shell assets for primary account' "$account_script"; then
  pass "account late hook stages managed shell assets for all installs and installs them into the primary account home"
else
  fail "account late hook stages managed shell assets for all installs and installs them into the primary account home"
fi

if grep -q '^configure_target_shared_account_access() {$' "$account_script" &&
   grep -q ': "${ACCOUNT_DEFAULT_GROUPS:?ACCOUNT_DEFAULT_GROUPS must be set}"' "$account_script" &&
   grep -q 'required_groups="${default_groups} devops"' "$account_script" &&
   grep -q 'usermod -a -G "$missing_groups" -- "$account_user"' "$account_script" &&
   grep -q 'refusing unsafe primary account uid/gid mapping' "$account_script" &&
   grep -q 'target path must be owned by root:root' "$account_script" &&
   grep -q '/usr/bin/sudo must be root-owned with setuid enabled' "$account_script" &&
   grep -q 'etc/udev/udev.conf.d/90-hardening.conf' "$account_script" &&
   ! grep -q 'usbmedia\\|usbadmin\\|udisks2\\|polkit-1/rules.d' "$account_script" &&
   grep -q '^configure_target_shared_account_access$' "$ROOT_DIR/d-i/forky/scripts/late/btrfs-family.sh" &&
   grep -q '^configure_target_shared_account_access$' "$ROOT_DIR/d-i/forky/scripts/late/f2fs-family.sh" &&
   grep -q '^  desktop_configure_usb_media_access$' "$ROOT_DIR/d-i/forky/scripts/desktop/labwc.sh"; then
  pass "shared hooks enforce the declared primary groups plus devops without overriding standard device removal wants"
else
  fail "shared hooks enforce the declared primary groups plus devops without overriding standard device removal wants"
fi

account_answers="$TMP_DIR/account.answers"
effective_account_env="$TMP_DIR/effective-account.env"
if INSTALLER_CMDLINE='primary_user=alice primary_password=userSecret primary_gpg_passphrase=gpgSecret root_password=rootSecret' \
  sh -c '
    set -eu
    . "$1/d-i/forky/scripts/runtime/common.sh"
    . "$1/d-i/forky/hosts/shared/account.env"
    . "$1/d-i/forky/scripts/runtime/account.sh"
    runtime_write_account_answers "$2"
    runtime_write_effective_account_env "$3"
    [ "$ACCOUNT_GPG_PASSPHRASE_IS_PLAIN" = true ]
    [ "$ACCOUNT_GPG_PASSPHRASE" = gpgSecret ]
  ' sh "$ROOT_DIR" "$account_answers" "$effective_account_env" &&
   grep -q '^d-i passwd/username string alice$' "$account_answers" &&
   grep -q '^d-i passwd/user-password password userSecret$' "$account_answers" &&
   grep -q '^d-i passwd/root-password password rootSecret$' "$account_answers" &&
   ! grep -q 'user-password-crypted' "$account_answers" &&
   grep -q "^ACCOUNT_USERNAME='alice'$" "$effective_account_env" &&
   grep -q "^ACCOUNT_HOME='/home/alice'$" "$effective_account_env" &&
   grep -q "^SSH_AUTHORIZED_KEYS_TARGET='/home/alice/.ssh/authorized_keys'$" "$effective_account_env" &&
   ! grep -q 'userSecret\|gpgSecret\|rootSecret' "$effective_account_env" &&
   grep -Fq 'primary_gpg_passphrase=*|' "$ROOT_DIR/d-i/forky/scripts/common/lib.sh" &&
   grep -Fq 'primary_gpg_passphrase=*|' "$ROOT_DIR/d-i/forky/scripts/firstboot/01-early.sh" &&
   grep -Fq 'primary_gpg_passphrase=*|' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/initramfs-tools/scripts/installer-health-common"; then
  pass "runtime account helper prefers and redacts the dedicated GPG passphrase without persisting plaintext credential env"
else
  fail "runtime account helper prefers and redacts the dedicated GPG passphrase without persisting plaintext credential env"
fi

default_account_hash='$6$rounds=100000$WgM/G0TmO8ATmIIr$BpWdcg72W3zedqfVeo3dwN0TGVtPINbS3IpimyUOaAjsGgCgt20UTXtzuvRUMXkbi6B6HrYT4rCFjM6uvfrc1.'
default_account_answers="$TMP_DIR/default-account.answers"
default_effective_account_env="$TMP_DIR/default-effective-account.env"
if INSTALLER_CMDLINE='' \
  sh -c '
    set -eu
    . "$1/d-i/forky/scripts/runtime/common.sh"
    . "$1/d-i/forky/hosts/shared/account.env"
    . "$1/d-i/forky/scripts/runtime/account.sh"
    runtime_write_account_answers "$2"
    runtime_write_effective_account_env "$3"
    [ "$ACCOUNT_GPG_PASSPHRASE_IS_PLAIN" = false ]
    [ -z "$ACCOUNT_GPG_PASSPHRASE" ]
  ' sh "$ROOT_DIR" "$default_account_answers" "$default_effective_account_env" &&
   grep -q '^d-i passwd/username string mcramer$' "$default_account_answers" &&
   grep -F -q "d-i passwd/user-password-crypted password $default_account_hash" "$default_account_answers" &&
   grep -F -q "d-i passwd/root-password-crypted password $default_account_hash" "$default_account_answers" &&
   ! grep -q '^d-i passwd/user-password password ' "$default_account_answers" &&
   ! grep -q '^d-i passwd/root-password password ' "$default_account_answers" &&
   grep -q "^ACCOUNT_USERNAME='mcramer'$" "$default_effective_account_env" &&
   grep -q "^FRUUX_CALENDAR_USERNAME='b3297374650'$" "$default_effective_account_env" &&
   grep -q "^FRUUX_CALENDAR_PASSWORD='testing123'$" "$default_effective_account_env"; then
  pass "runtime account helper falls back to shared account.env defaults when cmdline credentials are omitted"
else
  fail "runtime account helper falls back to shared account.env defaults when cmdline credentials are omitted"
fi

mixed_account_answers="$TMP_DIR/mixed-account.answers"
mixed_effective_account_env="$TMP_DIR/mixed-effective-account.env"
if INSTALLER_CMDLINE='primary_password=userSecret' \
  sh -c '
    set -eu
    . "$1/d-i/forky/scripts/runtime/common.sh"
    . "$1/d-i/forky/hosts/shared/account.env"
    . "$1/d-i/forky/scripts/runtime/account.sh"
    runtime_write_account_answers "$2"
    runtime_write_effective_account_env "$3"
    [ "$ACCOUNT_GPG_PASSPHRASE_IS_PLAIN" = true ]
    [ "$ACCOUNT_GPG_PASSPHRASE" = userSecret ]
  ' sh "$ROOT_DIR" "$mixed_account_answers" "$mixed_effective_account_env" &&
   grep -q '^d-i passwd/username string mcramer$' "$mixed_account_answers" &&
   grep -q '^d-i passwd/user-password password userSecret$' "$mixed_account_answers" &&
   grep -F -q "d-i passwd/root-password-crypted password $default_account_hash" "$mixed_account_answers" &&
   ! grep -q '^d-i passwd/user-password-crypted password ' "$mixed_account_answers" &&
   ! grep -q 'userSecret' "$mixed_effective_account_env"; then
  pass "runtime account helper falls back from the missing GPG passphrase to primary_password without persisting it"
else
  fail "runtime account helper falls back from the missing GPG passphrase to primary_password without persisting it"
fi

account_bootstrap_err="$TMP_DIR/account-bootstrap.err"
if RUNTIME_COMMON_LIB="$ROOT_DIR/d-i/forky/scripts/runtime/common.sh" \
  sh -c '
    set -eu
    . "$1/d-i/forky/scripts/runtime/account.sh"
    runtime_validate_printable_single_line empty ""
  ' sh "$ROOT_DIR" >"$TMP_DIR/account-bootstrap.out" 2>"$account_bootstrap_err"; then
  fail "runtime account helper bootstraps runtime_fatal from RUNTIME_COMMON_LIB"
elif grep -q 'fatal: empty must not be empty' "$account_bootstrap_err" &&
   ! grep -q 'runtime_fatal: not found' "$account_bootstrap_err"; then
  pass "runtime account helper bootstraps runtime_fatal from RUNTIME_COMMON_LIB"
else
  fail "runtime account helper bootstraps runtime_fatal from RUNTIME_COMMON_LIB"
fi

account_core_err="$TMP_DIR/account-core.err"
if INSTALLER_CMDLINE='primary_user=bob primary_password=userSecret root_password=rootSecret' \
  sh -c '
    set -eu
    root_dir=$1
    tmp_env_dir=$2

    TMP_ENV_DIR=$tmp_env_dir
    LATE_COMMAND_ACCOUNT_ENV="$root_dir/d-i/forky/hosts/shared/account.env"
    LATE_COMMAND_ACCOUNT_ENV_LOADED=0
    cp "$root_dir/d-i/forky/scripts/runtime/common.sh" "$TMP_ENV_DIR/runtime-common.sh"
    cp "$root_dir/d-i/forky/scripts/runtime/account.sh" "$TMP_ENV_DIR/account-runtime.sh"

    installer_fatal() {
      printf "fatal: %s\n" "$*" >&2
      exit 1
    }

    . "$root_dir/d-i/forky/scripts/late/core.sh"
    late_command_ensure_host_policy_envs() {
      :
    }
    late_command_load_account_env
    runtime_validate_printable_single_line empty ""
  ' sh "$ROOT_DIR" "$TMP_DIR" >"$TMP_DIR/account-core.out" 2>"$account_core_err"; then
  fail "late account env loader exports runtime common before sourcing account runtime"
elif grep -q 'fatal: empty must not be empty' "$account_core_err" &&
   ! grep -q 'runtime_fatal: not found' "$account_core_err"; then
  pass "late account env loader exports runtime common before sourcing account runtime"
else
  fail "late account env loader exports runtime common before sourcing account runtime"
fi

ssh_helper="$ROOT_DIR/d-i/forky/scripts/common/ssh.sh"
runtime_common="$ROOT_DIR/d-i/forky/scripts/runtime/common.sh"
sshd_config="$ROOT_DIR/d-i/forky/ssh/sshd_config"
if grep -q '^Port __INSTALLER_SSH_PORT__$' "$sshd_config" &&
   grep -q '^AllowUsers __INSTALLER_ACCOUNT_USERNAME__$' "$sshd_config" &&
   grep -q 'SSH_PORT "$SSH_PORT"' "$ssh_helper" &&
   grep -q 'installer_assert_no_unresolved_installer_placeholders "\$dest" "SSH template \${src}"' "$ssh_helper" &&
   grep -q 'installer_assert_no_unresolved_installer_placeholders "\$dest" "SSH user template \${src}"' "$ssh_helper" &&
   grep -q 'runtime_apply_ssh_from_cmdline' "$runtime_common" &&
   grep -q 'ssh_port must be 65535 or lower' "$runtime_common"; then
  pass "SSH provisioning renders Port and AllowUsers from selected cmdline/runtime values"
else
  fail "SSH provisioning renders Port and AllowUsers from selected cmdline/runtime values"
fi

core_script="$ROOT_DIR/d-i/forky/scripts/late/core.sh"
if grep -q 'installer_repo_join_var DIR_HOOKS_SHARED_TARGET etc/NetworkManager/conf.d/80-managed-link-privacy.conf' "$core_script" &&
   grep -q 'staged NetworkManager link privacy policy is missing' "$core_script" &&
   grep -q 'NetworkManager link privacy policy must enable Wi-Fi scan MAC randomization' "$core_script" &&
   grep -q 'NetworkManager link privacy policy must randomize Ethernet MAC addresses' "$core_script"; then
  pass "core late hook stages and verifies the NetworkManager link privacy policy"
else
  fail "core late hook stages and verifies the NetworkManager link privacy policy"
fi

wifi_client_conf="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/NetworkManager/conf.d/80-managed-link-privacy.conf"
if grep -q '^\[device\]$' "$wifi_client_conf" &&
   grep -q '^wifi\.scan-rand-mac-address=yes$' "$wifi_client_conf" &&
   grep -q '^ethernet\.cloned-mac-address=random$' "$wifi_client_conf" &&
   grep -q '^wifi\.cloned-mac-address=random$' "$wifi_client_conf"; then
  pass "link privacy policy randomizes both scan and active MAC identities"
else
  fail "link privacy policy randomizes both scan and active MAC identities"
fi

dbus_script="$ROOT_DIR/d-i/forky/scripts/late/dbus-broker.sh"
dbus_user_template="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/systemd/user/dbus-broker.service.d/10-broker-hardening.conf.tmpl"
legacy_dbus_user_template="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/systemd/user/dbus-broker.service.d/10-broker-hardening.conf.tmpl"
if grep -Fq 'for dir_var in DIR_DBUS_SESSION_SERVICES DIR_DBUS_LOCAL_SESSION_SERVICES; do' "$dbus_script" &&
   grep -Fq 'run_in_target "stage dbus-broker session service compatibility aliases"' "$dbus_script" &&
   grep -Fq 'divert_path="${source_path}.distrib"' "$dbus_script"; then
  pass "dbus late hook uses runtime paths and diversions for session service alias staging"
else
  fail "dbus late hook uses runtime paths and diversions for session service alias staging"
fi

if grep -q 'installer_repo_join_var DIR_HOOKS_SHARED_TARGET etc/dbus-1/system-local.conf.tmpl' "$dbus_script" &&
   grep -q 'installer_repo_join_var DIR_HOOKS_SHARED_TARGET etc/systemd/system/dbus-broker.service.d/10-broker-hardening.conf.tmpl' "$dbus_script" &&
   grep -q 'etc/systemd/user/dbus-broker.service.d/10-broker-hardening.conf.tmpl' "$dbus_script" &&
   ! grep -Fq 'dbus-broker.service.d/10-broker-hardening.conf.tmpl' "$desktop_components" &&
   grep -q 'installer_assert_no_unresolved_installer_placeholders "\$tmp_rendered" "D-Bus template \${repo_path}"' "$dbus_script" &&
   [ -r "$dbus_user_template" ] &&
   [ ! -e "$legacy_dbus_user_template" ] &&
   grep -q '^FILE_DBUS_USER_BROKER_SERVICE_OVERRIDE=' "$runtime_env"; then
  pass "D-Bus hardening renders system and user broker drop-ins from shared policy"
else
  fail "D-Bus hardening renders system and user broker drop-ins from shared policy"
fi

if grep -q 'org.xfce.Thunar.FileManager1.service:org.freedesktop.FileManager1' "$dbus_script" &&
   grep -q 'org.xfce.Tumbler.Thumbnailer1.service:org.freedesktop.thumbnails.Thumbnailer1' "$dbus_script"; then
  pass "dbus late hook keeps the expected compatibility alias coverage"
else
  fail "dbus late hook keeps the expected compatibility alias coverage"
fi

if grep -q 'sanitize_target_dbus_session_conf()' "$dbus_script" &&
   grep -Fq 'python3 -c "' "$dbus_script" &&
   grep -q 'attribute-free policy rules' "$dbus_script" &&
   sample_conf="$ROOT_DIR/.tmp-dbus-session-conf.$$" &&
   sample_out="$ROOT_DIR/.tmp-dbus-session-out.$$" &&
   cat >"$sample_conf" <<'EOF' &&
<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-Bus Bus Configuration 1.0//EN"
 "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig>
  <policy context="default">
    <allow send_destination="*" eavesdrop="true"/>
    <allow eavesdrop="true"/>
    <allow own="*"/>
  </policy>
</busconfig>
EOF
   python3 - "$sample_conf" "$sample_out" <<'PY' &&
import re
import sys
from pathlib import Path

source_path = Path(sys.argv[1])
target_path = Path(sys.argv[2])
single_quote = chr(39)
space_pattern = r"\s+"

output_lines = []
for raw_line in source_path.read_text(encoding="utf-8").splitlines():
    if re.search(r"<allow[^>]*eavesdrop\s*=", raw_line):
        stripped = re.sub(space_pattern + r'eavesdrop="[^"]*"', '', raw_line)
        stripped = re.sub(space_pattern + rf"eavesdrop={single_quote}[^{single_quote}]*{single_quote}", "", stripped)
        if re.search(r"<allow\s*/>", stripped):
            output_lines.extend([
                '    <allow receive_type="method_call"/>',
                '    <allow receive_type="method_return"/>',
                '    <allow receive_type="error"/>',
                '    <allow receive_type="signal"/>',
            ])
        else:
            output_lines.append(stripped)
        continue
    output_lines.append(raw_line)

target_path.write_text("\n".join(output_lines) + "\n", encoding="utf-8")
PY
   ! grep -Eq 'eavesdrop[[:space:]]*=' "$sample_out" &&
   grep -q '<allow send_destination="\*"/>' "$sample_out" &&
   grep -q '<allow receive_type="method_call"/>' "$sample_out" &&
   grep -q '<allow receive_type="signal"/>' "$sample_out" &&
   ! grep -Eq '<allow[[:space:]]*/>' "$sample_out" &&
   grep -q '<allow own="\*"/>' "$sample_out"; then
  pass "dbus late hook converts bare eavesdrop receive rules into explicit receive policy"
else
  fail "dbus late hook converts bare eavesdrop receive rules into explicit receive policy"
fi
rm -f "$ROOT_DIR/.tmp-dbus-session-conf.$$" "$ROOT_DIR/.tmp-dbus-session-out.$$"

security_script="$ROOT_DIR/d-i/forky/scripts/late/security.sh"
ssh_service_overlay="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/nftables/services/ssh-server.yml"
qbittorrent_service_overlay="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/nftables/services/qbittorrent.yml"
if grep -q 'late_command_nftables_effective_services()' "$security_script" &&
   grep -q 'SSH_SERVER_ENABLED' "$security_script" &&
   grep -q 'nftables_merge_selected_services "\$effective_services" ssh-server' "$security_script" &&
   grep -q '^nftables_software_selected() {$' "$security_script" &&
   grep -q 'installer_selected_class_reference_is_selected addon/software' "$security_script" &&
   grep -q 'nftables_merge_selected_services "\$effective_services" qbittorrent' "$security_script" &&
   grep -q 'nftables_ssh_service_placeholder_map' "$security_script" &&
   grep -q 'render_target_asset_with_placeholder_map' "$security_script" &&
   grep -q '^    - __INSTALLER_SSH_PORT__$' "$ssh_service_overlay" &&
   grep -q '^      ipv4: __INSTALLER_NFTABLES_SSH_ALLOW_IPV4__$' "$ssh_service_overlay" &&
   grep -q '^      ipv6: __INSTALLER_NFTABLES_SSH_ALLOW_IPV6__$' "$ssh_service_overlay" &&
   grep -q '^      interfaces: __INSTALLER_NFTABLES_SSH_ALLOW_INTERFACES__$' "$ssh_service_overlay" &&
   grep -q '^    - 50309$' "$qbittorrent_service_overlay"; then
  pass "security late hook auto-enables SSH and software-bundle qBittorrent firewall overlays"
else
  fail "security late hook auto-enables SSH and software-bundle qBittorrent firewall overlays"
fi

if grep -q '^FILE_MODULES_LOAD_TPM=' "$runtime_env" &&
   grep -q '^tpm$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/modules-load.d/32-tpm.conf" &&
   grep -q '^tpm_crb$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/modules-load.d/32-tpm.conf"; then
  pass "runtime env and shared target assets define the managed TPM module load list"
else
  fail "runtime env and shared target assets define the managed TPM module load list"
fi

if grep -q 'installer_repo_join_var DIR_HOOKS_SHARED_TARGET etc/modules-load.d/32-tpm.conf' "$ROOT_DIR/d-i/forky/scripts/late/btrfs-family.sh" &&
   grep -q 'installer_repo_join_var DIR_HOOKS_SHARED_TARGET etc/modules-load.d/32-tpm.conf' "$ROOT_DIR/d-i/forky/scripts/late/f2fs-family.sh"; then
  pass "late storage hooks stage the managed TPM module load list"
else
  fail "late storage hooks stage the managed TPM module load list"
fi

btrfs_nvme_modules="$ROOT_DIR/d-i/forky/hooks/hardware/disk/nvme/target/etc/modules-load.d/10-btrfs.conf"
btrfs_vm_modules="$ROOT_DIR/d-i/forky/hooks/hardware/disk/vm/target/etc/modules-load.d/10-btrfs.conf"
btrfs_expected_modules="$TMP_DIR/btrfs-modules.expected"
btrfs_actual_modules="$TMP_DIR/btrfs-modules.actual"
printf '%s\n' \
  btrfs \
  xfs \
  xxhash64 \
  xxhash64_generic \
  xxhash64-generic >"$btrfs_expected_modules"
sed '/^[[:space:]]*#/d; /^[[:space:]]*$/d' "$btrfs_nvme_modules" >"$btrfs_actual_modules"
if cmp -s "$btrfs_nvme_modules" "$btrfs_vm_modules" &&
   cmp -s "$btrfs_expected_modules" "$btrfs_actual_modules"; then
  pass "NVMe and VM storage profiles retain every explicit XXHASH module-name spelling"
else
  fail "NVMe and VM storage profiles retain every explicit XXHASH module-name spelling"
fi

ses_blacklist="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/modprobe.d/60-ses-blacklist.conf"
btrfs_family="$ROOT_DIR/d-i/forky/scripts/late/btrfs-family.sh"
f2fs_family="$ROOT_DIR/d-i/forky/scripts/late/f2fs-family.sh"
if grep -q '^FILE_MODPROBE_SES_BLACKLIST="${DIR_MODPROBE_D}/60-ses-blacklist.conf"$' "$runtime_env" &&
   grep -qx 'blacklist ses' "$ses_blacklist" &&
   grep -qx 'install ses /bin/false' "$ses_blacklist" &&
   grep -q 'installer_repo_join_var DIR_HOOKS_SHARED_TARGET etc/modprobe.d/60-ses-blacklist.conf' "$btrfs_family" &&
   grep -q 'installer_repo_join_var DIR_HOOKS_SHARED_TARGET etc/modprobe.d/60-ses-blacklist.conf' "$f2fs_family"; then
  pass "late storage hooks always stage the managed SES module blacklist"
else
  fail "late storage hooks always stage the managed SES module blacklist"
fi

modprobe_spacing_report="$TMP_DIR/modprobe-spacing.report"
find "$ROOT_DIR/d-i/forky/hooks" -path '*/etc/modprobe.d/*.conf' -type f -exec awk '
  /^[[:space:]]*#?(blacklist|install|options|alias|softdep|remove)[[:space:]]/ {
    if ($0 ~ /^[[:space:]]/ || $0 ~ /\t/ || $0 ~ /  / || $0 ~ /[[:space:]]$/) {
      printf "%s:%d:%s\n", FILENAME, FNR, $0
    }
  }
' {} + >"$modprobe_spacing_report"
if [ ! -s "$modprobe_spacing_report" ]; then
  pass "modprobe configuration directives use clean single-space separators"
else
  cat "$modprobe_spacing_report" >&2
  fail "modprobe configuration directives use clean single-space separators"
fi

apt_auto="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apt/apt.conf.d/20auto-upgrades"
apt_no_pdiffs="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apt/apt.conf.d/25no-pdiffs"
apt_unattended="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apt/apt.conf.d/52unattended-upgrades"
apt_default_trixie="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apt/apt.conf.d/95default-release-trixie"
apt_default_forky="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apt/apt.conf.d/95default-release-forky"
apt_no_recommends="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apt/apt.conf.d/99noinstall-recommends"
forky_pref="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apt/preferences.d/desktop/forky.pref"
sid_pref="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apt/preferences.d/desktop/sid.pref"
trixie_pref="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apt/preferences.d/desktop/trixie.pref"
login_defs="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/login.defs"
polkit_pam="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/pam.d/polkit-1"
systemd_user_pam="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/pam.d/systemd-user"
apt_daily_notify_dropin="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/systemd/system/apt-daily-upgrade.service.d/50-unattended-upgrades-notify.conf"
unattended_notify_helper="$ROOT_DIR/d-i/forky/hooks/shared/target/usr/local/libexec/unattended-upgrades-notify"
unattended_dropin="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/systemd/system/unattended-upgrades.service.d/override.conf"
unattended_event_root="$TMP_DIR/unattended-events"
EVENT_ROOT="$unattended_event_root" /bin/sh "$unattended_notify_helper" started
EVENT_ROOT="$unattended_event_root" \
SERVICE_RESULT=success \
EXIT_CODE=exited \
EXIT_STATUS=0 \
  /bin/sh "$unattended_notify_helper" finished
EVENT_ROOT="$unattended_event_root" \
SERVICE_RESULT=exit-code \
EXIT_CODE=exited \
EXIT_STATUS=100 \
  /bin/sh "$unattended_notify_helper" finished
unattended_event_count=$(find "$unattended_event_root/unattended-upgrades" -type f -name '*.event' | wc -l | tr -d '[:space:]')
expected_unattended_sites='deb.debian.org
security.debian.org
deb.xanmod.org
developer.download.nvidia.com
downloadcontent.opensuse.org
packagecloud.io
packages.gitlab.com
packages.microsoft.com
pkgs.tailscale.com
pkgs.zabbly.com
repo.mysql.com
repo.vivaldi.com
repository.mullvad.net
repository.spotify.com
storage.googleapis.com'
actual_unattended_sites=$(
  sed -n 's/^[[:space:]]*"site=\([^"]*\)";$/\1/p' "$apt_unattended"
)
if grep -q '^APT::Periodic::Update-Package-Lists "1";$' "$apt_auto" &&
   grep -q '^APT::Periodic::Unattended-Upgrade "1";$' "$apt_auto" &&
   grep -q '^Acquire::PDiffs "false";$' "$apt_no_pdiffs" &&
   apt-config -c "$apt_unattended" dump >/dev/null &&
   grep -q '^#clear Unattended-Upgrade::Allowed-Origins;$' "$apt_unattended" &&
   grep -q '^#clear Unattended-Upgrade::Origins-Pattern;$' "$apt_unattended" &&
   ! grep -Fq '"origin=*";' "$apt_unattended" &&
   [ "$actual_unattended_sites" = "$expected_unattended_sites" ] &&
   grep -Fq '"^.*(efi|uefi).*$";' "$apt_unattended" &&
   grep -Fq '"^linux($|-).*";' "$apt_unattended" &&
   grep -Fq '"^.*nvidia.*$";' "$apt_unattended" &&
   grep -Fq '"^.*cuda.*$";' "$apt_unattended" &&
   grep -Fq '"^.*firmware.*$";' "$apt_unattended" &&
   grep -Fq '"^.*vulkan.*$";' "$apt_unattended" &&
   grep -Fq '"^.*opengl.*$";' "$apt_unattended" &&
   grep -Fq '"^.*egl.*$";' "$apt_unattended" &&
   grep -Fq '"^mesa($|-).*";' "$apt_unattended" &&
   grep -Fq '"^libgl($|-|[0-9]).*";' "$apt_unattended" &&
   grep -Fq '"^libegl($|-|[0-9]).*";' "$apt_unattended" &&
   grep -Fq '"^libdrm($|-|[0-9]).*";' "$apt_unattended" &&
   grep -Fq '"^pipewire($|-).*";' "$apt_unattended" &&
   grep -Fq '"^wireplumber($|-).*";' "$apt_unattended" &&
   grep -q '^Unattended-Upgrade::AutoFixInterruptedDpkg "true";$' "$apt_unattended" &&
   grep -q '^Unattended-Upgrade::MailReport "on-change";$' "$apt_unattended" &&
   grep -q '^Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";$' "$apt_unattended" &&
   grep -q '^Unattended-Upgrade::Remove-New-Unused-Dependencies "true";$' "$apt_unattended" &&
   grep -q '^Unattended-Upgrade::Remove-Unused-Dependencies "true";$' "$apt_unattended" &&
   grep -q '^Unattended-Upgrade::InstallOnShutdown "false";$' "$apt_unattended" &&
   grep -q '^Unattended-Upgrade::Automatic-Reboot "false";$' "$apt_unattended" &&
   grep -q '^Unattended-Upgrade::Automatic-Reboot-WithUsers "false";$' "$apt_unattended" &&
   ! grep -q '^Unattended-Upgrade::Automatic-Reboot-Time ' "$apt_unattended" &&
   grep -q '^Unattended-Upgrade::Allow-APT-Mark-Fallback "true";$' "$apt_unattended" &&
   /bin/sh -n "$unattended_notify_helper" &&
   grep -q '^ExecStartPre=-/usr/local/libexec/unattended-upgrades-notify started$' "$apt_daily_notify_dropin" &&
   grep -q '^ExecStopPost=-/usr/local/libexec/unattended-upgrades-notify finished$' "$apt_daily_notify_dropin" &&
   [ "$unattended_event_count" -eq 3 ] &&
   grep -Rqx 'started|none|none|none' "$unattended_event_root/unattended-upgrades" &&
   grep -Rqx 'completed|success|exited|0' "$unattended_event_root/unattended-upgrades" &&
   grep -Rqx 'failed|exit-code|exited|100' "$unattended_event_root/unattended-upgrades" &&
   grep -q '^APT::Default-Release "trixie";$' "$apt_default_trixie" &&
   grep -q '^APT::Default-Release "forky";$' "$apt_default_forky" &&
   grep -q '^APT::Install-Recommends "false";$' "$apt_no_recommends" &&
   grep -q '^APT::Install-Suggests "false";$' "$apt_no_recommends" &&
   grep -q '^Pin: release n=forky$' "$forky_pref" &&
   grep -q '^Pin-Priority: 900$' "$forky_pref" &&
   grep -q '^Pin: release n=sid$' "$sid_pref" &&
   grep -q '^Pin-Priority: 100$' "$sid_pref" &&
   grep -q '^Pin: release n=trixie$' "$trixie_pref" &&
   grep -q '^Pin-Priority: 400$' "$trixie_pref" &&
   grep -q '^ENCRYPT_METHOD YESCRYPT$' "$login_defs" &&
   grep -q '^HOME_MODE[[:space:]]*0700$' "$login_defs" &&
   grep -q '^UMASK[[:space:]]*077$' "$login_defs" &&
   grep -q '^SYS_UID_MIN[[:space:]]*100$' "$login_defs" &&
   grep -q '^SYS_UID_MAX[[:space:]]*999$' "$login_defs" &&
   grep -q '^@include common-auth$' "$polkit_pam" &&
   grep -q '^@include common-account$' "$polkit_pam" &&
   grep -q '^account  sufficient pam_usertype\.so issystem$' "$systemd_user_pam" &&
   grep -q '^@include common-account$' "$systemd_user_pam" &&
   grep -q '^session  optional pam_systemd.so$' "$systemd_user_pam" &&
   grep -q '^Environment=PYTHONWARNINGS=ignore::DeprecationWarning$' "$unattended_dropin"; then
  pass "shared target policy allowlists approved unattended-upgrade sites, protects sensitive packages, emits desktop events, and preserves Debian PAM policy"
else
  fail "shared target policy allowlists approved unattended-upgrade sites, protects sensitive packages, emits desktop events, and preserves Debian PAM policy"
fi

storage_script="$ROOT_DIR/d-i/forky/scripts/late/storage-maintenance.sh"
if grep -q 'managed_target_policy_assets()' "$storage_script" &&
   grep -q 'etc/apt/apt.conf.d/20auto-upgrades' "$storage_script" &&
   grep -q 'etc/apt/apt.conf.d/25no-pdiffs' "$storage_script" &&
   grep -q 'etc/apt/apt.conf.d/52unattended-upgrades' "$storage_script" &&
   grep -q 'etc/apt/apt.conf.d/99noinstall-recommends' "$storage_script" &&
   grep -q '95default-release-forky' "$storage_script" &&
   grep -q '95default-release-trixie' "$storage_script" &&
   grep -q '^  stage_target_apt_login_policy_assets$' "$storage_script" &&
   grep -q 'verify_target_apt_default_release_policy()' "$storage_script" &&
   grep -q 'apt default release policy must be installed by finish-install:' "$storage_script" &&
   ! grep -q '\.pending' "$storage_script" &&
   ! grep -q "$legacy_default_release_staging_function" "$storage_script" &&
   grep -q 'etc/login.defs' "$storage_script" &&
   grep -q 'etc/pam.d/polkit-1' "$storage_script" &&
   grep -q 'etc/pam.d/systemd-user' "$storage_script" &&
   grep -q 'etc/systemd/system/apt-daily-upgrade.service.d/50-unattended-upgrades-notify.conf' "$storage_script" &&
   grep -q 'usr/local/libexec/unattended-upgrades-notify' "$storage_script" &&
   grep -q 'Acquire::PDiffs' "$storage_script" &&
   grep -q 'Unattended-Upgrade::MailReport' "$storage_script" &&
   grep -q 'APT::Install-Recommends' "$storage_script" &&
   grep -q 'ENCRYPT_METHOD' "$storage_script"; then
  pass "storage maintenance leaves the apt default-release policy for finish-install and stages Debian PAM compatibility files"
else
  fail "storage maintenance leaves the apt default-release policy for finish-install and stages Debian PAM compatibility files"
fi

if grep -q 'sanitize_target_xfs_scrub_systemd_units()' "$storage_script" &&
   grep -q 'target_xfs_scrub_cpuaccounting_units()' "$storage_script" &&
   grep -Fq "sed '/^[[:space:]]*CPUAccounting[[:space:]]*=/d'" "$storage_script" &&
   grep -q 'verify_target_xfs_scrub_systemd_units()' "$storage_script" &&
   grep -q 'sanitize_target_xfs_scrub_systemd_units' "$ROOT_DIR/d-i/forky/scripts/late/btrfs-family.sh" &&
   grep -q 'sanitize_target_xfs_scrub_systemd_units' "$ROOT_DIR/d-i/forky/scripts/late/f2fs-family.sh" &&
   grep -q 'verify_target_xfs_scrub_systemd_units' "$ROOT_DIR/d-i/forky/scripts/late/btrfs-family.sh" &&
   grep -q 'verify_target_xfs_scrub_systemd_units' "$ROOT_DIR/d-i/forky/scripts/late/f2fs-family.sh"; then
  pass "storage maintenance sanitizes xfs scrub units that still ship removed CPUAccounting"
else
  fail "storage maintenance sanitizes xfs scrub units that still ship removed CPUAccounting"
fi

profile_env_files='
d-i/forky/hosts/profiles/btrfs/desktop.env
d-i/forky/hosts/profiles/btrfs/server.env
d-i/forky/hosts/profiles/f2fs/desktop.env
d-i/forky/hosts/profiles/f2fs/server.env
d-i/forky/hosts/profiles/vm/desktop.env
d-i/forky/hosts/profiles/vm/server.env
'
profile_iface_ok=true
for relpath in $profile_env_files; do
  env_file="$ROOT_DIR/$relpath"
  if ! grep -q '^MANAGED_NETWORK_ETHERNET_IFACE="managed-eth0"$' "$env_file" ||
     ! grep -q '^MANAGED_NETWORK_WIFI_IFACE="managed-wifi0"$' "$env_file"; then
    profile_iface_ok=false
    break
  fi
done
if [ "$profile_iface_ok" = true ]; then
  pass "all concrete desktop and server profiles define configurable first-boot interface names"
else
  fail "all concrete desktop and server profiles define configurable first-boot interface names"
fi

desktop_profile_env_files='
d-i/forky/hosts/profiles/btrfs/desktop.env
d-i/forky/hosts/profiles/f2fs/desktop.env
d-i/forky/hosts/profiles/vm/desktop.env
d-i/forky/hosts/profiles/override/btrfs-de-dual-flex.env
d-i/forky/hosts/profiles/override/btrfs-de-dual-main.env
d-i/forky/hosts/profiles/override/btrfs-de-dual.env
d-i/forky/hosts/profiles/override/btrfs-de-flex.env
d-i/forky/hosts/profiles/override/btrfs-de-main.env
d-i/forky/hosts/profiles/override/btrfs-de.env
d-i/forky/hosts/profiles/override/f2fs-de-cbook.env
d-i/forky/hosts/profiles/override/f2fs-de-dual-cbook.env
d-i/forky/hosts/profiles/override/f2fs-de.env
d-i/forky/hosts/profiles/override/f2fs-de-dual.env
'
desktop_policy_keys="$TMP_DIR/desktop-policy.keys"
sed -n '/^# Profile-owned Labwc desktop and desktop-addon policy\.$/,$s/^\([A-Z0-9_][A-Z0-9_]*\)=.*/\1/p' \
  "$ROOT_DIR/d-i/forky/hosts/profiles/btrfs/desktop.env" |
  grep -vx 'TELPOLL_ENABLED' |
  sort >"$desktop_policy_keys"
desktop_profiles_ok=true
for relpath in $desktop_profile_env_files; do
  env_file="$ROOT_DIR/$relpath"
  current_policy_keys="$TMP_DIR/$(basename "$relpath").keys"
  sed -n '/^# Profile-owned Labwc desktop and desktop-addon policy\.$/,$s/^\([A-Z0-9_][A-Z0-9_]*\)=.*/\1/p' \
    "$env_file" |
    grep -vx 'TELPOLL_ENABLED' |
    sort >"$current_policy_keys"
  if ! cmp -s "$desktop_policy_keys" "$current_policy_keys" ||
     ! grep -q '^LABWC_OUTPUT_POLICY="auto"$' "$env_file" ||
     ! grep -q '^LABWC_OUTPUT_INTERNAL_PREFERRED_WIDTH="1920"$' "$env_file" ||
     ! grep -q '^LABWC_OUTPUT_INTERNAL_PREFERRED_HEIGHT="1080"$' "$env_file" ||
     ! grep -q '^LABWC_OUTPUT_INTERNAL_PREFERRED_REFRESH_HZ="60"$' "$env_file" ||
     ! grep -q '^LABWC_OUTPUT_EXTERNAL_PREFERRED_REFRESH_HZ="120"$' "$env_file" ||
     ! grep -q '^LABWC_OUTPUT_INTERNAL_SCALE="1"$' "$env_file" ||
     ! grep -q '^LABWC_OUTPUT_EXTERNAL_SCALE="1"$' "$env_file" ||
     ! grep -q '^LABWC_ENABLE_KANSHI="false"$' "$env_file" ||
     ! grep -q '^INCUS_BRIDGE_NAME="incusbr0"$' "$env_file" ||
     grep -Eq '^(QEMU_LIBVIRT_|QEMU_INCUS_)' "$env_file"; then
    desktop_profiles_ok=false
    break
  fi
  case "$relpath" in
    d-i/forky/hosts/profiles/override/btrfs-de-main.env)
      grep -q '^TELPOLL_ENABLED="true"$' "$env_file" || desktop_profiles_ok=false
      ;;
    *)
      ! grep -q '^TELPOLL_ENABLED=' "$env_file" || desktop_profiles_ok=false
      ;;
  esac
done
if [ "$desktop_profiles_ok" = true ] &&
   [ "$(wc -l <"$desktop_policy_keys")" -ge 200 ] &&
   [ ! -e "$ROOT_DIR/d-i/forky/hosts/shared/desktop.env" ] &&
   grep -q '^LABWC_WAYBAR_HEIGHT="38"$' "$ROOT_DIR/d-i/forky/hosts/profiles/override/f2fs-de-cbook.env" &&
   grep -q '^LABWC_WAYBAR_FONT_SIZE="11"$' "$ROOT_DIR/d-i/forky/hosts/profiles/override/f2fs-de-cbook.env" &&
   grep -q '^LABWC_CRYSTAL_DOCK_MAXIMUM_ICON_SIZE="60"$' "$ROOT_DIR/d-i/forky/hosts/profiles/override/f2fs-de-cbook.env" &&
   grep -q '^LABWC_GREETER_CLOCK_FONT_SIZE="88"$' "$ROOT_DIR/d-i/forky/hosts/profiles/override/f2fs-de-cbook.env"; then
  pass "desktop policy is profile-owned with one output manager, confined Incus, connector-specific modes, and compact Chromebook sizing"
else
  fail "desktop policy is profile-owned with one output manager, confined Incus, connector-specific modes, and compact Chromebook sizing"
fi

balanced_profile="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/sysctl.d/profiles/balanced/40-balanced.conf"
hardened_profile="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/sysctl.d/profiles/hardened/40-hardened.conf"
performance_profile="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/sysctl.d/profiles/performance/40-performance.conf"
baseline_profile="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/sysctl.d/10-baseline.conf"
if grep -q '__INSTALLER_SYSCTL_PROFILE_BALANCED_SWAPPINESS__' "$balanced_profile" &&
   grep -q '__INSTALLER_SYSCTL_PROFILE_HARDENED_SWAPPINESS__' "$hardened_profile" &&
   grep -q '__INSTALLER_SYSCTL_PROFILE_PERFORMANCE_SWAPPINESS__' "$performance_profile" &&
   grep -q '^kernel.yama.ptrace_scope         = 1$' "$baseline_profile" &&
   grep -q '^kernel.sysrq                     = 500$' "$baseline_profile" &&
   ! grep -q '^kernel.sysrq[[:space:]]*=' "$balanced_profile" &&
   ! grep -q '^kernel.sysrq[[:space:]]*=' "$hardened_profile" &&
   ! grep -q '^kernel.sysrq[[:space:]]*=' "$performance_profile" &&
   ! [ -e "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/sysctl.d/profiles/balanced/50-storage-balanced.conf.tmpl" ] &&
   ! [ -e "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/sysctl.d/profiles/hardened/50-storage-hardened.conf.tmpl" ] &&
   ! [ -e "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/sysctl.d/profiles/performance/50-storage-performance.conf.tmpl" ]; then
  pass "sysctl profiles render managed values without overriding the baseline ptrace and Magic SysRq policy"
else
  fail "sysctl profiles render managed values without overriding the baseline ptrace and Magic SysRq policy"
fi

tailscale_profile_env_files='
d-i/forky/hosts/profiles/btrfs/desktop.env
d-i/forky/hosts/profiles/btrfs/server.env
d-i/forky/hosts/profiles/f2fs/desktop.env
d-i/forky/hosts/profiles/f2fs/server.env
d-i/forky/hosts/profiles/vm/desktop.env
d-i/forky/hosts/profiles/vm/server.env
d-i/forky/hosts/profiles/override/btrfs-de-dual-flex.env
d-i/forky/hosts/profiles/override/btrfs-de-dual-main.env
d-i/forky/hosts/profiles/override/btrfs-de-dual.env
d-i/forky/hosts/profiles/override/btrfs-de-flex.env
d-i/forky/hosts/profiles/override/btrfs-de-main.env
d-i/forky/hosts/profiles/override/btrfs-de.env
d-i/forky/hosts/profiles/override/btrfs-gitlab-runner-srv-dual.env
d-i/forky/hosts/profiles/override/f2fs-de-cbook.env
d-i/forky/hosts/profiles/override/f2fs-de-dual-cbook.env
d-i/forky/hosts/profiles/override/f2fs-de.env
d-i/forky/hosts/profiles/override/f2fs-de-dual.env
d-i/forky/hosts/profiles/override/f2fs-pihole-srv.env
d-i/forky/hosts/profiles/override/btrfs-gitlab-runner-srv.env
'
tailscale_profile_vars_ok=true
for relpath in $tailscale_profile_env_files; do
  env_file="$ROOT_DIR/$relpath"
  if ! grep -q '^TAILSCALE_INTERFACE="tailscale0"$' "$env_file" ||
     ! grep -q '^TAILSCALE_UDP_PORT="41641"$' "$env_file" ||
     ! grep -q '^TAILSCALE_ACCEPT_DNS="false"$' "$env_file" ||
     ! grep -q '^TAILSCALE_RUN_SSH_SERVER="true"$' "$env_file" ||
     ! grep -q '^TAILSCALE_ADVERTISE_TAGS=""$' "$env_file" ||
     ! grep -q '^TAILSCALE_AUTH_KEY_REQUIRED="true"$' "$env_file" ||
     ! grep -q '^TAILSCALE_TIMEOUT="2m"$' "$env_file" ||
     grep -q '^TAILSCALE_SSH_PORT=' "$env_file" ||
     ! grep -q '^SYNCTHING_TCP_PORT="35000"$' "$env_file"; then
    tailscale_profile_vars_ok=false
    break
  fi
done
if [ "$tailscale_profile_vars_ok" = true ] &&
   ! grep -q '^TAILSCALE_INTERFACE=' "$ROOT_DIR/d-i/forky/hosts/shared/server.env" &&
   ! grep -q '^TAILSCALE_ADVERTISE_TAGS=' "$ROOT_DIR/d-i/forky/hosts/shared/server.env" &&
   [ ! -e "$ROOT_DIR/d-i/forky/hosts/shared/desktop.env" ]; then
  pass "tailscale and syncthing endpoint knobs stay profile-local instead of shared-role global"
else
  fail "tailscale and syncthing endpoint knobs stay profile-local instead of shared-role global"
fi

account_env="$ROOT_DIR/d-i/forky/hosts/shared/account.env"
runtime_account="$ROOT_DIR/d-i/forky/scripts/runtime/account.sh"
late_account="$ROOT_DIR/d-i/forky/scripts/late/account.sh"
if grep -q '^DIR_HOME_SYNCTHING="\${ACCOUNT_HOME}/Syncthing"$' "$account_env" &&
   grep -q 'DIR_HOME_SYNCTHING="\${ACCOUNT_HOME}/Syncthing"' "$runtime_account" &&
   grep -q '"\${DIR_HOME_SYNCTHING:-}"' "$late_account"; then
  pass "the managed account contract always creates ~/Syncthing, including non-btrfs families such as f2fs"
else
  fail "the managed account contract always creates ~/Syncthing, including non-btrfs families such as f2fs"
fi

btrfs_desktop_env="$ROOT_DIR/d-i/forky/hosts/profiles/btrfs/desktop.env"
f2fs_desktop_env="$ROOT_DIR/d-i/forky/hosts/profiles/f2fs/desktop.env"
if grep -q '^SYSCTL_PROFILE_BALANCED_SWAPPINESS="45"$' "$btrfs_desktop_env" &&
   grep -q '^SYSCTL_PROFILE_PERFORMANCE_SWAPPINESS="25"$' "$btrfs_desktop_env" &&
   grep -q '^SYSCTL_PROFILE_PERFORMANCE_WATERMARK_BOOST_FACTOR="0"$' "$btrfs_desktop_env" &&
   grep -q '^SYSCTL_PROFILE_BALANCED_SWAPPINESS="60"$' "$f2fs_desktop_env" &&
   grep -q '^SYSCTL_PROFILE_PERFORMANCE_SWAPPINESS="45"$' "$f2fs_desktop_env" &&
   grep -q '^SYSCTL_PROFILE_PERFORMANCE_WATERMARK_BOOST_FACTOR="0"$' "$f2fs_desktop_env"; then
  pass "desktop storage profiles keep calmer sysctl reclaim defaults for interactive responsiveness"
else
  fail "desktop storage profiles keep calmer sysctl reclaim defaults for interactive responsiveness"
fi

network_script="$ROOT_DIR/d-i/forky/scripts/late/network.sh"
network_generator="$ROOT_DIR/d-i/forky/scripts/late/managed-network-generate.pl"
if grep -q 'target_ethernet_iface=${MANAGED_NETWORK_ETHERNET_IFACE:-managed-eth0}' "$network_script" &&
   grep -q 'target_wifi_iface=${MANAGED_NETWORK_WIFI_IFACE:-managed-wifi0}' "$network_script" &&
   grep -q 'write_shell_config_var MANAGED_NETWORK_ETHERNET_IFACE "$target_ethernet_iface"' "$network_script" &&
   grep -q 'write_shell_config_var MANAGED_NETWORK_WIFI_IFACE "$target_wifi_iface"' "$network_script" &&
   grep -q 'return $link_type eq '\''wifi'\'' ? $CFG{MANAGED_NETWORK_WIFI_IFACE} : $CFG{MANAGED_NETWORK_ETHERNET_IFACE};' "$network_generator" &&
   grep -q 'MANAGED_NETWORK_ETHERNET_IFACE and MANAGED_NETWORK_WIFI_IFACE must differ' "$network_generator"; then
  pass "late network generation persists configurable first-boot interface names into the handoff defaults"
else
  fail "late network generation persists configurable first-boot interface names into the handoff defaults"
fi

if grep -q '"allow-hotplug \$record->{iface}"' "$network_generator" &&
   ! grep -q '"auto \$record->{iface}"' "$network_generator"; then
  pass "managed target interfaces rely on allow-hotplug instead of auto so disconnected links do not fail boot networking"
else
  fail "managed target interfaces rely on allow-hotplug instead of auto so disconnected links do not fail boot networking"
fi

layout_btrfs_env="$ROOT_DIR/d-i/forky/hosts/shared/layout-btrfs.env"
partman_layout="$ROOT_DIR/d-i/forky/hooks/shared/partman/finish.d/99-storage-layout.sh"
if grep -Fqx 'MNT_HOME_DOCUMENTS_OPTS="${MNT_BTRFS_USER_RESTRICTED},subvol=@home_documents"' "$layout_btrfs_env" &&
   grep -Fq 'DIR_HOME_DOCUMENTS' "$partman_layout" &&
   grep -Fq 'MNT_HOME_DOCUMENTS_OPTS' "$partman_layout" &&
   grep -Fqx 'home_subvolumes='\''@home @home_documents @home_downloads @home_public @home_pictures @home_workspace'\''' "$partman_layout" &&
   grep -Fqx '  fstab_entry "$home_src" "$DIR_HOME_DOCUMENTS" "btrfs" "$MNT_HOME_DOCUMENTS_OPTS" 0 0' "$partman_layout" &&
   grep -Fqx 'mount_block_device "$DEV_PART_HOME" "$TARGET_ROOT$DIR_HOME_DOCUMENTS" btrfs "$MNT_HOME_DOCUMENTS_OPTS"' "$partman_layout" &&
   grep -Fqx '$(fstab_entry "${home_src}" "${DIR_HOME_DOCUMENTS}" "btrfs" "${MNT_HOME_DOCUMENTS_OPTS}" 0 0)' "$btrfs_family"; then
  pass "btrfs home layout creates, mounts, and records a dedicated restricted Documents subvolume"
else
  fail "btrfs home layout creates, mounts, and records a dedicated restricted Documents subvolume"
fi

if grep -q 'subvol=@home_syncthing' "$layout_btrfs_env" &&
   grep -q 'DIR_HOME_SYNCTHING' "$partman_layout" &&
   grep -q '@home_syncthing' "$partman_layout"; then
  pass "btrfs home layout reserves a dedicated @home_syncthing subvolume and mountpoint"
else
  fail "btrfs home layout reserves a dedicated @home_syncthing subvolume and mountpoint"
fi

nft_readme="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/nftables/README.md"
nft_doc="$ROOT_DIR/d-i/forky/hooks/shared/target/data/docs/nft-policy-generate.md"
nm_unmanaged_template="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/NetworkManager/conf.d/90-managed-network-unmanaged.conf"
if grep -q 'nftables_interface_placeholder_map()' "$security_script" &&
   grep -q 'render_target_asset_with_placeholder_map "$(installer_repo_join_var DIR_HOOKS_SHARED_TARGET etc/nftables/README.md)" "/etc/nftables/README.md" 0644 nftables_interface_placeholder_map' "$security_script" &&
   grep -q 'stage_target_helper_doc nft-policy-generate.md nft-policy-generate.md' "$security_script" &&
   grep -q '__INSTALLER_MANAGED_NETWORK_ETHERNET_IFACE__' "$nft_readme" &&
   grep -q '__INSTALLER_MANAGED_NETWORK_WIFI_IFACE__' "$nft_readme" &&
   [ -r "$nft_doc" ] &&
   grep -q '__INSTALLER_MANAGED_NETWORK_ETHERNET_IFACE__' "$nm_unmanaged_template" &&
   grep -q '__INSTALLER_MANAGED_NETWORK_WIFI_IFACE__' "$nm_unmanaged_template"; then
  pass "nftables and NetworkManager artifacts render the configured managed interface names"
else
  fail "nftables and NetworkManager artifacts render the configured managed interface names"
fi

shared_loader="$ROOT_DIR/d-i/forky/hooks/shared/late_command.sh"
dispatch_script="$ROOT_DIR/d-i/forky/scripts/late/dispatch.sh"
volatile_script="$ROOT_DIR/d-i/forky/scripts/late/volatile-storage.sh"
asset_script="$ROOT_DIR/d-i/forky/scripts/late/target-assets.sh"
if [ ! -e "$ROOT_DIR/d-i/forky/scripts/late/tmpfs.sh" ] &&
   grep -q 'target-assets' "$shared_loader" &&
   grep -q 'volatile-storage' "$shared_loader" &&
   grep -q 'storage-maintenance' "$shared_loader" &&
   grep -q 'shared_modules="core target-assets volatile-storage storage-maintenance mullvad templates network grub security dbus-broker podman gitlab-runner zram-swap btrfs-family f2fs-family account"' "$dispatch_script" &&
   grep -q '^stage_target_helper_doc() {$' "$asset_script" &&
   grep -q 'apply_sysctl_profile_placeholders()' "$asset_script" &&
   grep -Fq 'index($0, "cdrom:")' "$volatile_script" &&
   ! grep -Fq 'cdrom://' "$volatile_script" &&
   grep -q 'apply_tmpfs_policy_placeholders()' "$volatile_script"; then
  pass "late module loader uses the split target-assets, volatile-storage, and storage-maintenance helpers"
else
  fail "late module loader uses the split target-assets, volatile-storage, and storage-maintenance helpers"
fi

udev_udisks_rules="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/udev/rules.d/90-udisks-behavior.rules"
account_script="$ROOT_DIR/d-i/forky/scripts/late/account.sh"
if grep -q 'ENV{ID_FS_LABEL}=="secure-boot-mok".*ENV{UDISKS_IGNORE}="1"' "$udev_udisks_rules" &&
   grep -q 'ENV{DM_NAME}=="secure-boot-mok".*ENV{UDISKS_IGNORE}="1"' "$udev_udisks_rules" &&
   grep -q 'ENV{ID_FS_LABEL}=="SHIM_SIGNED".*ENV{UDISKS_IGNORE}="1"' "$udev_udisks_rules"; then
  pass "udisks policy hides the secure-boot MOK state from file managers"
else
  fail "udisks policy hides the secure-boot MOK state from file managers"
fi

wpa_override="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/systemd/system/wpa_supplicant.service.d/override.conf"
core_script="$ROOT_DIR/d-i/forky/scripts/late/core.sh"
if ! grep -q ' -m /etc/wpa_supplicant/p2p-device.conf ' "$wpa_override" &&
   grep -q 'must not start a dedicated P2P device config' "$core_script"; then
  pass "wpa_supplicant D-Bus override avoids the dedicated P2P device path"
else
  fail "wpa_supplicant D-Bus override avoids the dedicated P2P device path"
fi

whisper_script="$ROOT_DIR/d-i/forky/scripts/late/whisper.sh"
whisper_class="$ROOT_DIR/d-i/forky/classes/class-addon/whisper.cfg"
addons_cfg="$ROOT_DIR/d-i/forky/classes/configs/addons.cfg"
cuda_class="$ROOT_DIR/d-i/forky/classes/class-addon/cuda.cfg"
cuda_legacy_class="$ROOT_DIR/d-i/forky/classes/class-addon/cuda-legacy.cfg"
devops_profile="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.profile.d/71-devops-de.sh"
whisper_profile_envs='
d-i/forky/hosts/profiles/btrfs/desktop.env
d-i/forky/hosts/profiles/f2fs/desktop.env
d-i/forky/hosts/profiles/vm/desktop.env
d-i/forky/hosts/profiles/override/btrfs-de.env
d-i/forky/hosts/profiles/override/btrfs-de-dual.env
d-i/forky/hosts/profiles/override/btrfs-de-dual-flex.env
d-i/forky/hosts/profiles/override/btrfs-de-dual-main.env
d-i/forky/hosts/profiles/override/btrfs-de-flex.env
d-i/forky/hosts/profiles/override/btrfs-de-main.env
d-i/forky/hosts/profiles/override/f2fs-de.env
d-i/forky/hosts/profiles/override/f2fs-de-cbook.env
d-i/forky/hosts/profiles/override/f2fs-de-dual.env
d-i/forky/hosts/profiles/override/f2fs-de-dual-cbook.env
'
required_whisper_profile_vars='
WHISPER_RELEASE_URL
WHISPER_RELEASE_SHA256
WHISPER_RELEASE_BYTES
WHISPER_RELEASE_MAXIMUM_EXTRACTED_BYTES
WHISPER_RELEASE_MAXIMUM_MEMBERS
WHISPER_RELEASE_ARCHIVE_ROOT
WHISPER_RELEASE_REQUIRED_CLASS
WHISPER_ROOT
WHISPER_BINARY_DIR
WHISPER_METADATA_DIR
WHISPER_MODEL_DIR
WHISPER_DOWNLOAD_RETRIES
WHISPER_DOWNLOAD_CONNECT_TIMEOUT_SECONDS
WHISPER_DOWNLOAD_MAX_TIME_SECONDS
WHISPER_HF_TOKEN
WHISPER_STRICT_RESOURCES
WHISPER_FORCE_DOWNLOAD
WHISPER_RUNTIME_THREADS
WHISPER_PERSISTENT_MEM
WHISPER_SERVER_PORT
WHISPER_DEFAULT_MODEL
WHISPER_DOWNLOAD_URL
WHISPER_MODEL_SHA256
WHISPER_MODEL_MIN_BYTES
WHISPER_MIN_MEMORY_MIB
WHISPER_MIN_CPU_CORES
'
whisper_magic_check="[ \"\$model_validation_magic\" = 6c6d6767 ]"
whisper_diagnostic_check="sha256=\${model_validation_sha256}, reason=\${model_validation_failure}"

whisper_profile_policy_validates() {
  policy_functions="${TMP_DIR}/whisper-release-policy-functions.sh"

  sed -n '1,/^whisper_stage_target_asset() {/p' "$whisper_script" |
    sed '$d' >"$policy_functions"
  [ -s "$policy_functions" ] || return 1

  for profile_relpath in $whisper_profile_envs; do
    profile_path="$ROOT_DIR/$profile_relpath"
    /usr/bin/env -i PATH=/usr/bin:/bin /bin/sh -eu -c '
      functions_file=$1
      profile_path=$2
      set -- --target-install
      # shellcheck disable=SC1090
      . "$functions_file"
      # shellcheck disable=SC1090
      . "$profile_path"
      whisper_validate_policy
    ' sh "$policy_functions" "$profile_path" || return 1
  done
}

whisper_release_class_selection_works() {
  selection_functions="${TMP_DIR}/whisper-release-class-functions.sh"
  selection_error="${TMP_DIR}/whisper-release-class.error"
  main_profile="$ROOT_DIR/d-i/forky/hosts/profiles/override/btrfs-de-main.env"
  flex_profile="$ROOT_DIR/d-i/forky/hosts/profiles/override/btrfs-de-flex.env"

  sed -n '1,/^whisper_stage_target_asset() {/p' "$whisper_script" |
    sed '$d' >"$selection_functions"
  [ -s "$selection_functions" ] || return 1

  run_selection() {
    selected_refs=$1
    profile_path=$2
    /usr/bin/env -i PATH=/usr/bin:/bin /bin/sh -eu -c '
      selected_refs=$1
      functions_file=$2
      profile_path=$3
      installer_selected_class_reference_is_selected() {
        case " $selected_refs " in
          *" $1 "*) return 0 ;;
        esac
        return 1
      }
      set -- --target-install
      # shellcheck disable=SC1090
      . "$functions_file"
      # shellcheck disable=SC1090
      . "$profile_path"
      whisper_validate_policy
      whisper_validate_release_class_selection
    ' sh "$selected_refs" "$selection_functions" "$profile_path"
  }

  run_selection 'addon/cuda-legacy' "$main_profile" || return 1
  run_selection '' "$flex_profile" || return 1
  if run_selection '' "$main_profile" >/dev/null 2>"$selection_error"; then
    return 1
  fi
  grep -Fq 'whisper-cuda requires the addon/cuda-legacy runtime class' "$selection_error"
}

whisper_release_rollback_works() {
  rollback_functions="${TMP_DIR}/whisper-release-rollback-functions.sh"
  rollback_root="${TMP_DIR}/whisper-release-rollback"

  sed -n \
    '/^whisper_target_rollback_release_publication() {/,/^whisper_target_download_and_install_release() {/p' \
    "$whisper_script" | sed '$d' >"$rollback_functions"
  [ -s "$rollback_functions" ] || return 1

  /usr/bin/env -i PATH=/usr/bin:/bin /bin/sh -eu -c '
    functions_file=$1
    WHISPER_ROOT=$2
    WHISPER_BINARY_DIR="${WHISPER_ROOT}/bin"
    WHISPER_METADATA_DIR="${WHISPER_ROOT}/metadata"
    # shellcheck disable=SC1090
    . "$functions_file"

    mkdir -p "$WHISPER_BINARY_DIR" "$WHISPER_METADATA_DIR"
    : >"${WHISPER_ROOT}/.installer-release"
    whisper_release_publish_in_progress=1
    whisper_target_rollback_release_publication
    [ "$whisper_release_publish_in_progress" = 0 ]
    [ ! -e "$WHISPER_BINARY_DIR" ]
    [ ! -e "$WHISPER_METADATA_DIR" ]
    [ ! -e "${WHISPER_ROOT}/.installer-release" ]

    mkdir -p "$WHISPER_BINARY_DIR" "$WHISPER_METADATA_DIR"
    : >"${WHISPER_ROOT}/.installer-release"
    whisper_release_publish_in_progress=0
    whisper_target_rollback_release_publication
    [ -d "$WHISPER_BINARY_DIR" ]
    [ -d "$WHISPER_METADATA_DIR" ]
    [ -f "${WHISPER_ROOT}/.installer-release" ]
  ' sh "$rollback_functions" "$rollback_root"
}

whisper_streamed_target_runner_works() {
  stream_root="${TMP_DIR}/whisper-streamed-target"
  stream_functions="${stream_root}/functions.sh"
  stream_harness="${stream_root}/harness.sh"
  stream_success="${stream_root}/success"
  stream_failure="${stream_root}/failure"

  install -d -m 0700 "$stream_root" "$stream_success" "$stream_failure"
  sed -n \
    '/^whisper_stream_target_output() {/,/^installer_selected_class_reference_is_selected addon\/whisper/p' \
    "$whisper_script" | sed '$d' >"$stream_functions"
  [ -s "$stream_functions" ] || return 1

  cat >"$stream_harness" <<'SH'
#!/bin/sh
set -eu

test_root=$1
emit_info=$2
shift 2

installer_runtime_temp_log_path() {
  printf '%s/%s\n' "$test_root" "$1"
}
target_log_should_emit() {
  case "$1:$emit_info" in
    info:1|error:*) return 0 ;;
  esac
  return 1
}
installer_info() {
  printf 'info:%s\n' "$*" >>"$test_root/events"
}
installer_error() {
  printf 'error:%s\n' "$*" >&2
}
target_log_command_start() {
  printf 'start:%s\n' "$1" >>"$test_root/events"
}
target_log_command_complete() {
  printf 'complete:%s\n' "$1" >>"$test_root/events"
  cp "$2" "$test_root/completed-output"
}
target_log_command_failure() {
  printf 'failure:%s:%s\n' "$1" "$2" >>"$test_root/events"
  cp "$4" "$test_root/failed-output"
}
target_exec() {
  "$@"
}
print_command() {
  printf 'command:'
  printf ' <%s>' "$@"
  printf '\n'
}

# shellcheck disable=SC1090
. "$test_root/functions.sh"
run_whisper_install_in_target "test Whisper release install" "$@"
SH
  chmod 0700 "$stream_harness"
  cp "$stream_functions" "$stream_success/functions.sh"
  cp "$stream_functions" "$stream_failure/functions.sh"

  printf '[1/2] download\n[2/2] extract\n' >"$stream_success/expected"
  "$stream_harness" \
    "$stream_success" \
    1 \
    /bin/sh -c 'printf "[1/2] download\n[2/2] extract\n"' \
    >"$stream_success/stdout" \
    2>"$stream_success/stderr" || return 1
  cmp -s "$stream_success/stdout" "$stream_success/expected" || return 1
  cmp -s "$stream_success/completed-output" "$stream_success/expected" || return 1
  [ ! -s "$stream_success/stderr" ] || return 1
  grep -Fqx 'complete:test Whisper release install' "$stream_success/events" || return 1

  if "$stream_harness" \
       "$stream_failure" \
       0 \
       /bin/sh -c 'printf "download failed\n" >&2; exit 17' \
       >"$stream_failure/stdout" \
       2>"$stream_failure/stderr"
  then
    return 1
  else
    stream_failure_status=$?
  fi
  [ "$stream_failure_status" -eq 17 ] || return 1
  [ ! -s "$stream_failure/stdout" ] || return 1
  printf 'download failed\n' >"$stream_failure/expected"
  cmp -s "$stream_failure/failed-output" "$stream_failure/expected" || return 1
  grep -Fqx 'failure:test Whisper release install:17' "$stream_failure/events" || return 1
  grep -Fq 'in-target failed during test Whisper release install (status 17)' \
    "$stream_failure/stderr" || return 1
  grep -Fqx 'download failed' "$stream_failure/stderr"
}

whisper_model_policy_ok=true
whisper_reference_schema="${TMP_DIR}/whisper-profile.schema"
: >"$whisper_reference_schema"
whisper_profile_index=0
whisper_cuda_count=0
whisper_ram_count=0
whisper_persistent_count=0
for whisper_profile_env in $whisper_profile_envs; do
  whisper_profile_path="$ROOT_DIR/$whisper_profile_env"
  whisper_profile_schema="${TMP_DIR}/whisper-profile.${whisper_profile_index}.schema"
  sed -n 's/^\(WHISPER_[A-Z0-9_]*\)=.*/\1/p' "$whisper_profile_path" >"$whisper_profile_schema"
  whisper_profile_var_count=$(wc -l <"$whisper_profile_schema" | tr -d ' ')
  whisper_model=$(sed -n 's/^WHISPER_DEFAULT_MODEL="\([^"]*\)"$/\1/p' "$whisper_profile_path")
  whisper_url=$(sed -n 's/^WHISPER_DOWNLOAD_URL="\([^"]*\)"$/\1/p' "$whisper_profile_path")
  whisper_sha256=$(sed -n 's/^WHISPER_MODEL_SHA256="\([^"]*\)"$/\1/p' "$whisper_profile_path")
  whisper_min_bytes=$(sed -n 's/^WHISPER_MODEL_MIN_BYTES=\([0-9][0-9]*\)$/\1/p' "$whisper_profile_path")

  if ! /bin/sh -n "$whisper_profile_path" ||
     [ "$whisper_profile_var_count" -ne 26 ] ||
     ! grep -Fqx 'WHISPER_ROOT="/data/whisper"' "$whisper_profile_path" ||
     ! grep -Fqx 'WHISPER_BINARY_DIR="/data/whisper/bin"' "$whisper_profile_path" ||
     ! grep -Fqx 'WHISPER_METADATA_DIR="/data/whisper/metadata"' "$whisper_profile_path" ||
     ! grep -Fqx 'WHISPER_MODEL_DIR="/pool/cache/whisper/models"' "$whisper_profile_path" ||
     ! grep -Fqx 'WHISPER_SERVER_PORT="59178"' "$whisper_profile_path" ||
     grep -Eq '^WHISPER_(CPP_REPO|CPP_REF|SOURCE_DIR|BUILD_DIR|OUTPUT_DIR|SCCACHE_DIR|DGGML_|CMAKE_|BUILD_JOBS|SOURCE_UPDATE|FORCE_SOURCE_RESET)=' "$whisper_profile_path"; then
    whisper_model_policy_ok=false
    break
  fi

  for profile_var in $required_whisper_profile_vars; do
    if ! grep -Eq "^${profile_var}=" "$whisper_profile_path"; then
      whisper_model_policy_ok=false
      break 2
    fi
  done

  if [ "$whisper_profile_index" -eq 0 ]; then
    cp "$whisper_profile_schema" "$whisper_reference_schema"
  elif ! cmp -s "$whisper_reference_schema" "$whisper_profile_schema"; then
    whisper_model_policy_ok=false
    break
  fi

  case "$whisper_model" in
    tiny.en-q8_0)
      whisper_expected_url="https://huggingface.co/ggerganov/whisper.cpp/resolve/d15393806e24a74f60827e23e986f0c10750b358/ggml-tiny.en-q8_0.bin"
      whisper_expected_sha256="5bc2b3860aa151a4c6e7bb095e1fcce7cf12c7b020ca08dcec0c6d018bb7dd94"
      whisper_expected_min_bytes=43550795
      ;;
    small.en-q8_0)
      whisper_expected_url="https://huggingface.co/ggerganov/whisper.cpp/resolve/0b364b566045a405be7225ee1e415a073e04da77/ggml-small.en-q8_0.bin"
      whisper_expected_sha256="67a179f608ea6114bd3fdb9060e762b588a3fb3bd00c4387971be4d177958067"
      whisper_expected_min_bytes=264477561
      ;;
    medium.en-q8_0)
      whisper_expected_url="https://huggingface.co/ggerganov/whisper.cpp/resolve/0b364b566045a405be7225ee1e415a073e04da77/ggml-medium.en-q8_0.bin"
      whisper_expected_sha256="43fa2cd084de5a04399a896a9a7a786064e221365c01700cea4666005218f11c"
      whisper_expected_min_bytes=823382461
      ;;
    *)
      whisper_model_policy_ok=false
      break
      ;;
  esac
  if [ "$whisper_url" != "$whisper_expected_url" ] ||
     [ "$whisper_sha256" != "$whisper_expected_sha256" ] ||
     [ "$whisper_min_bytes" != "$whisper_expected_min_bytes" ]; then
    whisper_model_policy_ok=false
    break
  fi

  case "$whisper_profile_env" in
    d-i/forky/hosts/profiles/override/btrfs-de-main.env|\
    d-i/forky/hosts/profiles/override/btrfs-de-dual-main.env)
      if ! grep -Fqx 'WHISPER_RELEASE_URL="https://github.com/mjcramerz/whisper-labwc/releases/download/whisper-labwc-main/whisper-cuda.tar.gz"' "$whisper_profile_path" ||
         ! grep -Fqx 'WHISPER_RELEASE_SHA256="00302338e184e53b76979289df90ab2aa62bba9838d8558c1a87e1a7b9932bb0"' "$whisper_profile_path" ||
         ! grep -Fqx 'WHISPER_RELEASE_BYTES="41076373"' "$whisper_profile_path" ||
         ! grep -Fqx 'WHISPER_RELEASE_MAXIMUM_EXTRACTED_BYTES="83886080"' "$whisper_profile_path" ||
         ! grep -Fqx 'WHISPER_RELEASE_MAXIMUM_MEMBERS="16"' "$whisper_profile_path" ||
         ! grep -Fqx 'WHISPER_RELEASE_ARCHIVE_ROOT="whisper-cuda"' "$whisper_profile_path" ||
         ! grep -Fqx 'WHISPER_RELEASE_REQUIRED_CLASS="addon/cuda-legacy"' "$whisper_profile_path"; then
        whisper_model_policy_ok=false
        break
      fi
      whisper_cuda_count=$((whisper_cuda_count + 1))
      ;;
    *)
      if ! grep -Fqx 'WHISPER_RELEASE_URL="https://github.com/mjcramerz/whisper-labwc/releases/download/whisper-labwc-main/whisper-ram.tar.gz"' "$whisper_profile_path" ||
         ! grep -Fqx 'WHISPER_RELEASE_SHA256="23a0db1cb6892a6fd2bcf41f5ff6f069bb1bc1cef8728fcc223a22fb16bc477b"' "$whisper_profile_path" ||
         ! grep -Fqx 'WHISPER_RELEASE_BYTES="2310809"' "$whisper_profile_path" ||
         ! grep -Fqx 'WHISPER_RELEASE_MAXIMUM_EXTRACTED_BYTES="8388608"' "$whisper_profile_path" ||
         ! grep -Fqx 'WHISPER_RELEASE_MAXIMUM_MEMBERS="16"' "$whisper_profile_path" ||
         ! grep -Fqx 'WHISPER_RELEASE_ARCHIVE_ROOT="whisper-ram"' "$whisper_profile_path" ||
         ! grep -Fqx 'WHISPER_RELEASE_REQUIRED_CLASS=""' "$whisper_profile_path"; then
        whisper_model_policy_ok=false
        break
      fi
      whisper_ram_count=$((whisper_ram_count + 1))
      ;;
  esac

  if grep -q '^WHISPER_PERSISTENT_MEM=1$' "$whisper_profile_path"; then
    whisper_persistent_count=$((whisper_persistent_count + 1))
    [ "$whisper_profile_env" = d-i/forky/hosts/profiles/override/btrfs-de-main.env ] ||
      whisper_model_policy_ok=false
  fi
  whisper_profile_index=$((whisper_profile_index + 1))
done

if [ "$whisper_model_policy_ok" = true ] &&
   [ "$whisper_profile_index" -eq 13 ] &&
   [ "$whisper_cuda_count" -eq 2 ] &&
   [ "$whisper_ram_count" -eq 11 ] &&
   [ "$whisper_persistent_count" -eq 1 ] &&
   grep -Eq '(^|[[:space:]])build-essential([[:space:]]|$)' "$whisper_class" &&
   grep -Eq '(^|[[:space:]])gcc([[:space:]]|$)' "$whisper_class" &&
   grep -Eq '(^|[[:space:]])g\+\+([[:space:]]|$)' "$whisper_class" &&
   grep -Eq '(^|[[:space:]])gcc-14([[:space:]]|$)' "$whisper_class" &&
   grep -Eq '(^|[[:space:]])g\+\+-14([[:space:]]|$)' "$whisper_class" &&
   grep -Eq '(^|[[:space:]])cmake([[:space:]]|$)' "$whisper_class" &&
   grep -Eq '(^|[[:space:]])ninja-build([[:space:]]|$)' "$whisper_class" &&
   grep -Eq '(^|[[:space:]])sccache([[:space:]]|$)' "$whisper_class" &&
   grep -Eq '(^|[[:space:]])libopenblas-dev([[:space:]]|$)' "$whisper_class" &&
   grep -Eq '(^|[[:space:]])python3([[:space:]]|$)' "$whisper_class" &&
   grep -Fqx 'Description: opt-in AMD64 profile-pinned whisper.cpp command-line runtime and Labwc voice-task capture' "$addons_cfg" &&
   grep -Fqx 'RequiresClasses: role/desktop arch/amd64' "$addons_cfg" &&
   grep -Eq '(^|[[:space:]])cuda-nvcc-13-1([[:space:]]|$)' "$cuda_class" &&
   grep -Eq '(^|[[:space:]])cuda-nvcc-12-8([[:space:]]|$)' "$cuda_legacy_class" &&
   grep -Eq '(^|[[:space:]])cuda-nvcc-12-9([[:space:]]|$)' "$cuda_legacy_class" &&
   grep -Fq 'if [ -d /usr/local/cuda-12.8/bin ]; then' "$devops_profile" &&
   grep -Fq 'devops_de_prepend_path /usr/local/cuda-12.8/bin || return 1' "$devops_profile" &&
   grep -Fq 'if [ -d /usr/local/cuda-12.9/bin ]; then' "$devops_profile" &&
   grep -Fq 'devops_de_prepend_path /usr/local/cuda-12.9/bin || return 1' "$devops_profile" &&
   grep -Fq 'if [ -d /usr/local/cuda-13.1/bin ]; then' "$devops_profile" &&
   grep -Fq 'devops_de_prepend_path /usr/local/cuda-13.1/bin || return 1' "$devops_profile" &&
   whisper_profile_policy_validates &&
   whisper_release_class_selection_works &&
   whisper_streamed_target_runner_works &&
   /bin/sh -n "$whisper_script" &&
   grep -Fq 'target_archive_helper=/tmp/installer-ai-runtime-archive.py' "$whisper_script" &&
   grep -Fq 'installer_repo_join_var DIR_SCRIPTS_LATE ai-runtime-archive.py' "$whisper_script" &&
   grep -Fq 'run_whisper_install_in_target "download and install selected whisper.cpp runtime"' "$whisper_script" &&
   grep -Fq -- '--max-filesize "$WHISPER_RELEASE_BYTES"' "$whisper_script" &&
   grep -Fq '[ "$archive_bytes" = "$WHISPER_RELEASE_BYTES" ]' "$whisper_script" &&
   grep -Fq '[ "$archive_sha256" = "$WHISPER_RELEASE_SHA256" ]' "$whisper_script" &&
   grep -Fq -- '--required-directory bin' "$whisper_script" &&
   grep -Fq -- '--required-directory metadata' "$whisper_script" &&
   grep -Fq -- '--required-binary whisper-cli' "$whisper_script" &&
   grep -Fq -- '--required-binary whisper-server' "$whisper_script" &&
   grep -Fq 'mv -- "$extract_dir/bin" "$WHISPER_BINARY_DIR"' "$whisper_script" &&
   grep -Fq 'mv -- "$extract_dir/metadata" "$WHISPER_METADATA_DIR"' "$whisper_script" &&
   grep -Fq 'whisper_release_publish_in_progress=1' "$whisper_script" &&
   grep -Fq 'whisper_target_rollback_release_publication' "$whisper_script" &&
   grep -Fq 'failed to publish the complete Whisper runtime release' "$whisper_script" &&
   whisper_release_rollback_works &&
   grep -Fq 'for binary_name in whisper-cli whisper-server; do' "$whisper_script" &&
   ! grep -Eq 'WHISPER_(CPP_REPO|CPP_REF|SOURCE_DIR|BUILD_DIR|OUTPUT_DIR|SCCACHE_DIR|DGGML_|CMAKE_|BUILD_JOBS)' "$whisper_script" &&
   ! grep -Eq 'run_whisper_build_in_target|--target-build|configure_and_build|(^|[[:space:]])(cmake|ninja|sccache)([[:space:]]|$)' "$whisper_script" &&
   grep -Fq "$whisper_magic_check" "$whisper_script" &&
   grep -Fq 'WHISPER_DOWNLOAD_URL must use an immutable 40-character revision' "$whisper_script" &&
   grep -Fq '$label must contain 64 lowercase hexadecimal characters' "$whisper_script" &&
   grep -Fq "$whisper_diagnostic_check" "$whisper_script"; then
  pass "Whisper profiles pin exact CUDA/RAM releases, retain compiler and nvcc tooling, and install both binaries without compilation"
else
  fail "Whisper profiles pin exact CUDA/RAM releases, retain compiler and nvcc tooling, and install both binaries without compilation"
fi

[ "$FAIL_COUNT" -eq 0 ]
