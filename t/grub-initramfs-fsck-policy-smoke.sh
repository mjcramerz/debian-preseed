#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/grub-initramfs-fsck-policy.XXXXXX")
trap 'rm -rf "$TMP_DIR"' EXIT HUP INT TERM

TEST_COUNT=42
TEST_INDEX=0

pass() {
  TEST_INDEX=$((TEST_INDEX + 1))
  printf 'ok %s - %s\n' "$TEST_INDEX" "$1"
}

fail() {
  TEST_INDEX=$((TEST_INDEX + 1))
  printf 'not ok %s - %s\n' "$TEST_INDEX" "$1"
}

run_case() {
  root_flags=$1
  initramfs_flags=$2

  (
    set -eu
    . "$ROOT_DIR/d-i/forky/scripts/late/grub.sh"
    GRUB_ROOT_FLAGS=$root_flags
    GRUB_INITRAMFS_FLAGS=$initramfs_flags
    apply_root_initramfs_fsck_policy
    printf '%s\n' "$GRUB_INITRAMFS_FLAGS"
  )
}

printf '1..%s\n' "$TEST_COUNT"

if [ "$(run_case 'rootfstype=btrfs rootflags=subvol=@' 'initramfs_options=mode=0755,huge=within_size')" = \
  'initramfs_options=mode=0755,huge=within_size fsck.mode=skip' ]; then
  pass "Btrfs root forces initramfs fsck skip mode"
else
  fail "Btrfs root forces initramfs fsck skip mode"
fi

if [ "$(run_case 'rootfstype=f2fs rootwait rootflags=rw' 'initramfs_options=mode=0755,huge=within_size')" = \
  'initramfs_options=mode=0755,huge=within_size fsck.mode=skip' ]; then
  pass "F2FS root forces initramfs fsck skip mode"
else
  fail "F2FS root forces initramfs fsck skip mode"
fi

if [ "$(run_case 'rootfstype=btrfs rootflags=subvol=@' 'initramfs_options=mode=0755 fsck.mode=force')" = \
  'initramfs_options=mode=0755 fsck.mode=skip' ]; then
  pass "managed roots replace conflicting fsck mode with skip"
else
  fail "managed roots replace conflicting fsck mode with skip"
fi

if [ "$(run_case 'rootfstype=f2fs rootwait rootflags=rw' 'initramfs_options=mode=0755 fsck.repair=no')" = \
  'initramfs_options=mode=0755 fsck.repair=no fsck.mode=skip' ] &&
   [ "$(run_case 'rootfstype=f2fs rootwait rootflags=rw' 'initramfs_options=mode=0755 fsck.mode=skip')" = \
  'initramfs_options=mode=0755 fsck.mode=skip' ]; then
  pass "F2FS skip policy is appended once while retaining repair policy"
else
  fail "F2FS skip policy is appended once while retaining repair policy"
fi

grub_profiles="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/default/grub-profiles.tmpl"
if grep -q 'bootable_kernel_images=$(list_bootable_kernel_images)' "$grub_profiles" &&
   [ "$(grep -c 'list_bootable_kernel_images' "$grub_profiles")" -eq 2 ]; then
  pass "GRUB profile generator caches bootable kernel discovery once per run"
else
  fail "GRUB profile generator caches bootable kernel discovery once per run"
fi

fstab_generator="$ROOT_DIR/d-i/forky/hooks/shared/partman/finish.d/99-storage-layout.sh"
if grep -q 'fstab_entry "\$root_src" "/" "btrfs" "\$MNT_BTRFS_ROOT_OPTS" 0 0' "$fstab_generator" &&
   grep -q 'fstab_entry "\$root_src" / f2fs "\$MNT_F2FS_ROOT_OPTS" 0 0' "$ROOT_DIR/d-i/forky/scripts/late/f2fs-family.sh" &&
   grep -q 'fstab_entry "\$home_src" "\$DIR_HOME" f2fs "\$MNT_F2FS_HOME_OPTS" 0 0' "$ROOT_DIR/d-i/forky/scripts/late/f2fs-family.sh" &&
   grep -q 'fstab_entry "\$efi_src" "\$DIR_BOOT_EFI" "vfat" "\$MNT_EFI_OPTS" 0 2' "$fstab_generator" &&
   grep -q 'check_command efi-vfat-mounted findmnt -n -t vfat /boot/efi' "$ROOT_DIR/d-i/forky/scripts/firstboot/04-validation.sh"; then
  pass "managed fstab skips Btrfs/F2FS checks while preserving and validating the EFI VFAT mount"
else
  fail "managed fstab skips Btrfs/F2FS checks while preserving and validating the EFI VFAT mount"
fi

fstab_guard="$ROOT_DIR/d-i/forky/hooks/shared/base-stage.d/20-fstab-guard"
if grep -q 'btrfs:\*|f2fs:\*) pass=0 ;;' "$fstab_guard" &&
   grep -q 'vfat:\*|ext4:\*) pass=2 ;;' "$fstab_guard"; then
  pass "fallback fstab guard skips managed root families while keeping EFI at pass 2"
else
  fail "fallback fstab guard skips managed root families while keeping EFI at pass 2"
fi

if grep -q '^GRUB_REMOVABLE_BOOT_EFI_PATH=$INSTALLER_GRUB_REMOVABLE_BOOT_EFI_PATH$' "$ROOT_DIR/d-i/forky/scripts/late/templates.sh" &&
   grep -q '^rescue_usb_efi_path=__INSTALLER_GRUB_REMOVABLE_BOOT_EFI_PATH__$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/default/grub-profiles.tmpl" &&
   grep -q 'rescue_usb_uuid=${23}' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/default/grub-profiles.tmpl" &&
   grep -q 'Rescue USB not plugged in' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/default/grub-profiles.tmpl" &&
   ! grep -q 'ESPBOOT' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/default/grub-profiles.tmpl"; then
  pass "rescue USB GRUB entry uses the architecture-specific removable EFI path and installer-derived UUID search"
else
  fail "rescue USB GRUB entry uses the architecture-specific removable EFI path and installer-derived UUID search"
fi

# These grep patterns deliberately inspect unexpanded shell source.
# shellcheck disable=SC2016
if grep -q 'skip_mok_signing=false' "$grub_profiles" &&
   grep -q 'SKIP_MOK_SIGNING must be boolean when set' "$grub_profiles" &&
   grep -q 'MOK enrollment menu omitted because SKIP_MOK_SIGNING=1' "$grub_profiles" &&
   grep -q 'emit_mok_enrollment_menu()' "$grub_profiles" &&
   grep -Fq "printf 'dev_part_efi=%s" "$grub_profiles" &&
   grep -Fq 'dev_part_efi=$3' "$grub_profiles" &&
   grep -Fq 'efi_uuid=$(blkid -s UUID -o value "$dev_part_efi" 2>/dev/null || true)' "$grub_profiles" &&
   grep -Fq 'mokmanager_search="search --no-floppy --fs-uuid --set=esp ${efi_uuid}"' "$grub_profiles" &&
   grep -Fq 'mokmanager_search="search --no-floppy --file --set=esp ${mokmanager_path}"' "$grub_profiles" &&
   ! grep -Fq 'mokmanager_device=$(grub-probe' "$grub_profiles"; then
  pass "GRUB profile generator uses the historical explicit-ESP UUID search"
else
  fail "GRUB profile generator uses the historical explicit-ESP UUID search"
fi

mok_menu_block=$(sed -n '/^emit_mok_enrollment_menu() {/,/^}$/p' "$grub_profiles")
if printf '%s\n' "$mok_menu_block" |
     grep -Fqx '    insmod fat' &&
   printf '%s\n' "$mok_menu_block" |
     grep -Fqx '    insmod chain' &&
   printf '%s\n' "$mok_menu_block" |
     grep -Fqx '    ${mokmanager_search}' &&
   printf '%s\n' "$mok_menu_block" |
     grep -Fqx '    chainloader (\$esp)${mokmanager_path}' &&
   printf '%s\n' "$mok_menu_block" |
     grep -Fq 'Use MokManager to enroll the generated certificate stored at ${mok_der_path}.' &&
   ! grep -Fq 'grub-probe' "$grub_profiles"; then
  pass "MOK enrollment uses the historical GRUB esp variable chainload"
else
  fail "MOK enrollment uses the historical GRUB esp variable chainload"
fi

grub_helper="$ROOT_DIR/d-i/forky/scripts/late/grub.sh"
if grep -q '^queue_target_grub_mok_enrollment_boot() {$' "$grub_helper" &&
   grep -Fq 'MOK enrollment GRUB entry is missing' "$grub_helper" &&
   grep -Fq 'MokManager EFI loader is missing' "$grub_helper" &&
   grep -Fq 'MOK enrollment certificate is missing' "$grub_helper" &&
   grep -Fq 'next_entry=${mok_entry_id}' "$grub_helper"; then
  pass "one-shot MOK enrollment queue validates the generated entry, EFI loader, and certificate first"
else
  fail "one-shot MOK enrollment queue validates the generated entry, EFI loader, and certificate first"
fi

if grep -q 'prepare_target_secure_boot_runtime()' "$ROOT_DIR/d-i/forky/scripts/late/grub.sh" &&
   grep -q 'install_target_bootprofile_assets()' "$ROOT_DIR/d-i/forky/scripts/late/grub.sh" &&
   grep -q 'verify_target_bootprofile_core_staging()' "$ROOT_DIR/d-i/forky/scripts/late/grub.sh" &&
   grep -q 'prepare_target_secure_boot_runtime' "$ROOT_DIR/d-i/forky/scripts/late/f2fs-family.sh" &&
   grep -q 'install_target_bootprofile_assets' "$ROOT_DIR/d-i/forky/scripts/late/f2fs-family.sh" &&
   grep -q 'verify_target_bootprofile_core_staging' "$ROOT_DIR/d-i/forky/scripts/late/f2fs-family.sh" &&
   grep -q 'install_target_bootprofile_assets' "$ROOT_DIR/d-i/forky/scripts/late/btrfs-family.sh" &&
   grep -q 'verify_target_bootprofile_core_staging' "$ROOT_DIR/d-i/forky/scripts/late/btrfs-family.sh" &&
   grep -q '^sysctl_hardened=\$5$' "$ROOT_DIR/d-i/forky/scripts/late/btrfs-family.sh" &&
   grep -q '^sysctl_performance=\$6$' "$ROOT_DIR/d-i/forky/scripts/late/btrfs-family.sh" &&
   ! grep -q '^sysctl_default_family=' "$ROOT_DIR/d-i/forky/scripts/late/btrfs-family.sh" &&
   ! grep -q 'load_target_boot_tool_state' "$ROOT_DIR/d-i/forky/scripts/late/btrfs-family.sh" &&
   ! grep -q 'load_target_boot_tool_state' "$ROOT_DIR/d-i/forky/scripts/late/f2fs-family.sh"; then
  pass "late boot helpers expose shared Secure Boot and bootprofile helpers without stale sysctl verifier args or late initramfs probing"
else
  fail "late boot helpers expose shared Secure Boot and bootprofile helpers without stale sysctl verifier args or late initramfs probing"
fi

if (
  set -eu
  . "$ROOT_DIR/d-i/forky/scripts/late/grub.sh"
  installer_calls=0
  run_installer_secure_boot_install_tool() { installer_calls=$((installer_calls + 1)); }
  prepare_target_secure_boot_runtime
  prepare_target_secure_boot_runtime
  [ "$installer_calls" -eq 1 ]
  [ -z "${TARGET_HAS_OS_PROBER+x}" ]
  [ -z "${TARGET_HAS_UPDATE_GRUB+x}" ]
); then
  pass "cached GRUB late helpers avoid repeated target prepare without any late initramfs probe state"
else
  fail "cached GRUB late helpers avoid repeated target prepare without any late initramfs probe state"
fi

secure_boot_tool="$ROOT_DIR/d-i/forky/hooks/shared/target/usr/libexec/install-tools/secure-boot-tool.tmpl"
if grep -q '^reset_mok_state() {$' "$secure_boot_tool" &&
   grep -q '^resolve_mok_delete_password() {$' "$secure_boot_tool" &&
   grep -q 'installer_password=${SECURE_BOOT_MOK_DELETE_PASSWORD:-}' "$secure_boot_tool" &&
   ! grep -q 'primary_user=$(cmdline_value primary_user' "$secure_boot_tool" &&
   grep -F -q 'mok_enrolled=$(mokutil --list-enrolled | grep -F -- "Unattended")' "$secure_boot_tool" &&
   grep -q 'no enrolled Unattended MOK certificates; skipping MOK reset' "$secure_boot_tool" &&
   grep -F -q "printf '%s\\n%s\\n' \"\$mok_reset_password\" \"\$mok_reset_password\" | mokutil --reset" "$secure_boot_tool" &&
   grep -F -q 'mokutil --timeout 900' "$secure_boot_tool" &&
   ! grep -F -q 'if ! mokutil --timeout 900' "$secure_boot_tool" &&
   ! grep -q 'mokutil --delete' "$secure_boot_tool" &&
   ! grep -q 'mokutil --export' "$secure_boot_tool" &&
   ! grep -q 'mokutil --generate-hash' "$secure_boot_tool" &&
   ! grep -q 'mokutil --revoke' "$secure_boot_tool" &&
   ! grep -q 'mokutil --set-fallback' "$secure_boot_tool"; then
  pass "secure boot helper resets enrolled MOKs and directly starts a 15-minute enrollment window"
else
  fail "secure boot helper resets enrolled MOKs and directly starts a 15-minute enrollment window"
fi

if grep -q 'reset-moks' "$secure_boot_tool" &&
   ! grep -q 'mokutil --import' "$secure_boot_tool" &&
   ! grep -q 'mokutil --revoke-import' "$secure_boot_tool" &&
   ! grep -q 'SECURE_BOOT_MOK_ENROLL_PASSWORD' "$secure_boot_tool" &&
   grep -q 'SECURE_BOOT_MOK_DELETE_PASSWORD="$secure_boot_delete_password"' "$ROOT_DIR/d-i/forky/scripts/late/grub.sh"; then
  pass "secure boot helper removes import-era MokManager commands and exposes only the reset entrypoint"
else
  fail "secure boot helper removes import-era MokManager commands and exposes only the reset entrypoint"
fi

if (
  set -eu
  tmp_case_dir="$TMP_DIR/grub-mok-primary-user"
  mkdir -p "$tmp_case_dir/bin"
  cat >"$tmp_case_dir/bin/in-target" <<'EOF'
#!/bin/sh
prefix_seen=false
password_seen=false
tool_seen=false
verb_seen=false
for arg in "$@"; do
  case "$arg" in
    SECURE_BOOT_HOST_MOUNT_PREFIX=/target) prefix_seen=true ;;
    SECURE_BOOT_MOK_DELETE_PASSWORD=mcramer) password_seen=true ;;
    /usr/libexec/install-tools/secure-boot-tool) tool_seen=true ;;
    reset-moks) verb_seen=true ;;
  esac
done
[ "$prefix_seen" = true ] &&
[ "$password_seen" = true ] &&
[ "$tool_seen" = true ] &&
[ "$verb_seen" = true ]
EOF
  chmod +x "$tmp_case_dir/bin/in-target"
  PATH="$tmp_case_dir/bin:$PATH"
  installer_fatal() { return 99; }
  . "$ROOT_DIR/d-i/forky/scripts/late/grub.sh"
  ensure_installer_secure_boot_install_tool() {
    INSTALLER_SECURE_BOOT_TARGET_ROOT=/target
    INSTALLER_SECURE_BOOT_TARGET_TOOL=/usr/libexec/install-tools/secure-boot-tool
  }
  installer_cmdline_value() {
    [ "$1" = primary_user ] || return 1
    printf '%s\n' mcramer
  }
  run_installer_secure_boot_install_tool reset-moks
); then
  pass "late Secure Boot bridge passes primary_user as the MOK reset password"
else
  fail "late Secure Boot bridge passes primary_user as the MOK reset password"
fi

if (
  set -eu
  tmp_case_dir="$TMP_DIR/grub-mok-account-fallback"
  mkdir -p "$tmp_case_dir/bin"
  cat >"$tmp_case_dir/bin/in-target" <<'EOF'
#!/bin/sh
password_seen=false
for arg in "$@"; do
  case "$arg" in
    SECURE_BOOT_MOK_DELETE_PASSWORD=fallbackuser) password_seen=true ;;
  esac
done
[ "$password_seen" = true ]
EOF
  chmod +x "$tmp_case_dir/bin/in-target"
  PATH="$tmp_case_dir/bin:$PATH"
  installer_fatal() { return 99; }
  . "$ROOT_DIR/d-i/forky/scripts/late/grub.sh"
  ACCOUNT_USERNAME=fallbackuser
  ensure_installer_secure_boot_install_tool() {
    INSTALLER_SECURE_BOOT_TARGET_ROOT=/target
    INSTALLER_SECURE_BOOT_TARGET_TOOL=/usr/libexec/install-tools/secure-boot-tool
  }
  installer_cmdline_value() { return 1; }
  run_installer_secure_boot_install_tool reset-moks
); then
  pass "late Secure Boot bridge falls back to ACCOUNT_USERNAME when primary_user is absent"
else
  fail "late Secure Boot bridge falls back to ACCOUNT_USERNAME when primary_user is absent"
fi

secure_boot_tool_conf="$TMP_DIR/secure-boot-delete-password.conf"
cat >"$secure_boot_tool_conf" <<'EOF'
SECURE_BOOT_MODE=direct
SECURE_BOOT_STATE_MOUNTPOINT=/var/lib/shim-signed
SECURE_BOOT_STATE_DIR=/var/lib/shim-signed/secure-boot
SECURE_BOOT_MOK_KEY=/var/lib/shim-signed/secure-boot/MOK.priv
SECURE_BOOT_MOK_CERT_PEM=/var/lib/shim-signed/secure-boot/MOK.pem
SECURE_BOOT_MOK_CERT_DER=/var/lib/shim-signed/secure-boot/MOK.der
SECURE_BOOT_MOK_ENROLLMENT_DIR=/var/lib/shim-signed/secure-boot
SECURE_BOOT_MOK_ENROLLMENT_CERT=/var/lib/shim-signed/secure-boot/MOK.der
SECURE_BOOT_OPENSSL_CONFIG=/var/lib/shim-signed/secure-boot/openssl.cnf
SECURE_BOOT_DKMS_CONF=/etc/dkms/framework.conf.d/90-secure-boot.conf
ACCOUNT_USERNAME=fallbackuser
EOF
if SECURE_BOOT_CONFIG_PATH="$secure_boot_tool_conf" ROOT_DIR="$ROOT_DIR" \
  MOKUTIL_ARGS_FILE="$TMP_DIR/mokutil.args" \
  MOKUTIL_INPUT_FILE="$TMP_DIR/mokutil.input" \
  MOKUTIL_BIN_DIR="$TMP_DIR/mokutil-bin" \
  bash -eu <<'EOF'
tool_defs=$(mktemp)
trap 'rm -f "$tool_defs"; rm -rf "$MOKUTIL_BIN_DIR"' EXIT HUP INT TERM
sed '/^if \[ "\$#" -ge 2 \]; then/,$d' \
  "$ROOT_DIR/d-i/forky/hooks/shared/target/usr/libexec/install-tools/secure-boot-tool.tmpl" >"$tool_defs"
. "$tool_defs"
mkdir -p "$MOKUTIL_BIN_DIR"
cat >"$MOKUTIL_BIN_DIR/mokutil" <<'MOCK_MOKUTIL'
#!/bin/sh
set -eu
case "$1" in
  --list-enrolled)
    [ "$#" -eq 1 ]
    printf '%s\n' "$@" >>"$MOKUTIL_ARGS_FILE"
    if [ "${MOKUTIL_LIST_ENROLLED_STATUS:-0}" -ne 0 ]; then
      exit "$MOKUTIL_LIST_ENROLLED_STATUS"
    fi
    printf '%s' "${MOKUTIL_LIST_ENROLLED_OUTPUT:-}"
    ;;
  --reset)
    [ "$#" -eq 1 ]
    printf '%s\n' "$@" >>"$MOKUTIL_ARGS_FILE"
    cat >"$MOKUTIL_INPUT_FILE"
    ;;
  --timeout)
    [ "$#" -eq 2 ]
    [ "$2" = 900 ]
    printf '%s\n' "$@" >>"$MOKUTIL_ARGS_FILE"
    ;;
  *)
    exit 1
    ;;
esac
MOCK_MOKUTIL
chmod 0755 "$MOKUTIL_BIN_DIR/mokutil"
PATH="$MOKUTIL_BIN_DIR:$PATH"
keypair_prepared=0
dkms_framework_configured=0
require_root() {
  :
}
ensure_keypair() {
  keypair_prepared=1
}
ensure_dkms_framework_config() {
  dkms_framework_configured=1
}
SECURE_BOOT_MOK_DELETE_PASSWORD=installeruser
MOKUTIL_LIST_ENROLLED_OUTPUT='[key 1]
Subject: CN=Unattended Install Secure Boot'
export MOKUTIL_LIST_ENROLLED_OUTPUT
[ "$(resolve_mok_delete_password)" = installeruser ]
cmd_reset_moks
[ "$keypair_prepared" -eq 1 ]
[ "$dkms_framework_configured" -eq 1 ]
[ "$(cat "$MOKUTIL_ARGS_FILE")" = "$(printf '%s\n%s\n%s\n%s' --list-enrolled --reset --timeout 900)" ]
[ "$(cat "$MOKUTIL_INPUT_FILE")" = "$(printf 'installeruser\ninstalleruser')" ]
: >"$MOKUTIL_ARGS_FILE"
rm -f "$MOKUTIL_INPUT_FILE"
MOKUTIL_LIST_ENROLLED_OUTPUT=
export MOKUTIL_LIST_ENROLLED_OUTPUT
reset_mok_state
[ "$(cat "$MOKUTIL_ARGS_FILE")" = --list-enrolled ]
[ ! -e "$MOKUTIL_INPUT_FILE" ]
: >"$MOKUTIL_ARGS_FILE"
MOKUTIL_LIST_ENROLLED_OUTPUT='[key 1]
Subject: CN=existing MOK'
export MOKUTIL_LIST_ENROLLED_OUTPUT
reset_mok_state
[ "$(cat "$MOKUTIL_ARGS_FILE")" = --list-enrolled ]
[ ! -e "$MOKUTIL_INPUT_FILE" ]
: >"$MOKUTIL_ARGS_FILE"
MOKUTIL_LIST_ENROLLED_STATUS=1
export MOKUTIL_LIST_ENROLLED_STATUS
reset_mok_state
[ "$(cat "$MOKUTIL_ARGS_FILE")" = --list-enrolled ]
[ ! -e "$MOKUTIL_INPUT_FILE" ]
unset MOKUTIL_LIST_ENROLLED_STATUS
unset SECURE_BOOT_MOK_DELETE_PASSWORD
[ "$(resolve_mok_delete_password)" = fallbackuser ]
EOF
then
  pass "secure boot target tool resets enrolled Unattended MOK certificates with a 15-minute window"
else
  fail "secure boot target tool resets enrolled Unattended MOK certificates with a 15-minute window"
fi

bootprofile_apply="$ROOT_DIR/d-i/forky/hooks/shared/target/usr/libexec/install-tools/bootprofile-apply.tmpl"
grub_snapshot_helper="$ROOT_DIR/d-i/forky/hooks/shared/target/usr/local/sbin/grub-btrfs-refresh"
if grep -q 'systemd.setenv=BOOTPROFILE=' "$grub_profiles" &&
   grep -q 'systemd.setenv=BOOTPROFILE=' "$grub_snapshot_helper" &&
   grep -q 'BOOTPROFILE_FORCE:-${BOOTPROFILE:-}' "$bootprofile_apply" &&
   grep -q "systemd\\\\.setenv=BOOTPROFILE=" "$bootprofile_apply" &&
   grep -q "bootprofile=" "$bootprofile_apply"; then
  pass "bootprofile selection uses systemd.setenv while keeping one-shot legacy cmdline reads"
else
  fail "bootprofile selection uses systemd.setenv while keeping one-shot legacy cmdline reads"
fi

if grep -q '"/lib/modules/\$kernelver/weak-updates"' "$secure_boot_tool" &&
   grep -q 'kernel_modules_dir="/lib/modules/\$kernelver/kernel"' "$secure_boot_tool" &&
   grep -q -- "-name 'nvidia\\*.ko'" "$secure_boot_tool" &&
   grep -q -- "-path '.*/nvidia/\\*.ko'" "$secure_boot_tool"; then
  pass "secure boot helper scans weak-updates and kernel-tree NVIDIA modules for post-install resigning"
else
  fail "secure boot helper scans weak-updates and kernel-tree NVIDIA modules for post-install resigning"
fi

if (
  set -eu
  installer_fatal() { return 99; }
  . "$ROOT_DIR/d-i/forky/scripts/late/grub.sh"
  SECURE_BOOT_MODE=direct
  unset SECURE_BOOT_STATE_MODE
  [ "$(target_secure_boot_state_mode)" = direct ]
  SECURE_BOOT_MODE=luks
  SECURE_BOOT_STATE_MODE=luks
  [ "$(target_secure_boot_state_mode)" = luks ]
  set +e
  SECURE_BOOT_MODE=direct
  SECURE_BOOT_STATE_MODE=luks
  target_secure_boot_state_mode >/dev/null 2>&1
  status=$?
  set -e
  [ "$status" -ne 0 ]
); then
  pass "late Secure Boot mode resolver honors the alias and rejects conflicts"
else
  fail "late Secure Boot mode resolver honors the alias and rejects conflicts"
fi

if (
  set -eu
  runtime_fatal() { return 99; }
  . "$ROOT_DIR/d-i/forky/scripts/runtime/btrfs.sh"
  SECURE_BOOT_MODE=direct
  unset SECURE_BOOT_STATE_MODE
  [ "$(runtime_secure_boot_state_mode)" = direct ]
  set +e
  SECURE_BOOT_MODE=direct
  SECURE_BOOT_STATE_MODE=luks
  runtime_secure_boot_state_mode >/dev/null 2>&1
  status=$?
  set -e
  [ "$status" -ne 0 ]
); then
  pass "runtime Secure Boot mode resolver honors the alias and rejects conflicts"
else
  fail "runtime Secure Boot mode resolver honors the alias and rejects conflicts"
fi

postinst_hook="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/kernel/postinst.d/zz-sign-kernel.tmpl"
header_hook="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/kernel/header_postinst.d/zz-sign-kernel-headers.tmpl"
postrm_hook="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/kernel/postrm.d/zz-sign-kernel-cleanup.tmpl"
dkms_conf_template="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/dkms/framework.conf.d/90-secure-boot.conf.tmpl"
if grep -q '^mok_certificate=' "$dkms_conf_template" &&
   grep -q '^sign_file="/lib/modules/\${kernelver}/build/scripts/sign-file"$' "$dkms_conf_template" &&
   ! grep -q '^sign_tool=' "$dkms_conf_template" &&
   grep -F -q "sign_file=\"/lib/modules/\${kernelver}/build/scripts/sign-file\"" "$secure_boot_tool" &&
   grep -q 'DKMS sign_file compatibility requires a kernel version' "$secure_boot_tool"; then
  pass "managed DKMS framework config points directly at sign-file with kernel-version expansion"
else
  fail "managed DKMS framework config points directly at sign-file with kernel-version expansion"
fi

arch_amd64_class="$ROOT_DIR/d-i/forky/classes/class-auto/arch/amd64.cfg"
arch_arm64_class="$ROOT_DIR/d-i/forky/classes/class-auto/arch/arm64.cfg"
apt_fragment="$ROOT_DIR/d-i/forky/fragments/apt.cfg"
if grep -q '^d-i base-installer/includes string initramfs-tools busybox mokutil openssl shim-signed cryptsetup kmod gzip zstd$' "$apt_fragment" &&
   grep -q '^d-i base-installer/kernel/linux/initrd boolean true$' "$arch_amd64_class" &&
   grep -q '^#d-i base-installer/kernel/linux/link_in_boot boolean true$' "$arch_amd64_class" &&
   grep -q '^d-i base-installer/kernel/linux/initramfs-generators string initramfs-tools$' "$arch_amd64_class" &&
   grep -q '^d-i base-installer/kernel/linux/initramfs-tools/driver-policy string most$' "$arch_amd64_class" &&
   grep -q '^d-i base-installer/kernel/linux/initramfs-tools/compression string lz4$' "$arch_amd64_class" &&
   grep -q '^d-i base-installer/kernel/skip-install boolean true$' "$arch_amd64_class" &&
   grep -q '^d-i base-installer/kernel/skip-install seen true$' "$arch_amd64_class" &&
   grep -q '^d-i base-installer/kernel/image select none$' "$arch_amd64_class" &&
   grep -q '^d-i base-installer/kernel/linux/extra-packages string dkms kmod$' "$arch_amd64_class" &&
   grep -q '^d-i pkgsel/include string .*grub-efi-amd64 .*initramfs-tools .*kmod .*sbsigntool .*fwupd .*fwupd-amd64-signed' "$arch_amd64_class" &&
   ! grep -q '^d-i pkgsel/include string .*linux-image-amd64' "$arch_amd64_class" &&
   ! grep -q '^d-i pkgsel/include string .*linux-headers-amd64' "$arch_amd64_class" &&
   grep -q '^d-i base-installer/kernel/linux/initrd boolean true$' "$arch_arm64_class" &&
   grep -q '^#d-i base-installer/kernel/linux/link_in_boot boolean true$' "$arch_arm64_class" &&
   grep -q '^d-i base-installer/kernel/linux/initramfs-generators string initramfs-tools$' "$arch_arm64_class" &&
   grep -q '^d-i base-installer/kernel/linux/initramfs-tools/driver-policy string dep$' "$arch_arm64_class" &&
   grep -q '^d-i base-installer/kernel/linux/initramfs-tools/compression string gzip$' "$arch_arm64_class" &&
   grep -q '^d-i base-installer/kernel/linux/extra-packages string linux-headers-arm64 dkms kmod sbsigntool$' "$arch_arm64_class" &&
   grep -q '^d-i pkgsel/include string .*initramfs-tools .*linux-image-arm64 .*linux-headers-arm64 .*kmod .*sbsigntool .*fwupd .*fwupd-arm64-signed' "$arch_arm64_class" &&
   grep -q '^require_secure_boot_signing_commands() {$' "$secure_boot_tool" &&
   grep -q '^require_secure_boot_module_signing_commands() {$' "$secure_boot_tool" &&
   grep -q '^  require_command sbsign$' "$secure_boot_tool" &&
   grep -q '^  require_command sbverify$' "$secure_boot_tool" &&
   grep -q '^  require_command modinfo$' "$secure_boot_tool" &&
   grep -q '^  require_command depmod$' "$secure_boot_tool" &&
   grep -q '^  require_command gzip$' "$secure_boot_tool" &&
   grep -q '^  require_command xz$' "$secure_boot_tool" &&
   grep -q '^  require_command zstd$' "$secure_boot_tool" &&
   grep -q '^verify_installed_kernel_sign_file_paths() {$' "$secure_boot_tool" &&
   grep -q '^    external_modules=$(external_module_paths_for_kernel "\$kernelver" || true)$' "$secure_boot_tool" &&
   grep -q '^    \[ -n "\$external_modules" \] || continue$' "$secure_boot_tool" &&
   grep -q '^    resolve_sign_file "\$kernelver" >/dev/null$' "$secure_boot_tool" &&
   grep -q '^    log "info: no external modules require sign-file validation"$' "$secure_boot_tool" &&
   grep -q '"/usr/src/linux-headers-\$kernelver/scripts/sign-file"' "$secure_boot_tool" &&
   grep -q '"/usr/src/linux-headers-\$short_kernelver/scripts/sign-file"' "$secure_boot_tool" &&
   grep -q '^cmd_prepare() {$' "$secure_boot_tool" &&
   grep -q '^  require_secure_boot_signing_commands$' "$secure_boot_tool" &&
   grep -q '^  require_secure_boot_module_signing_commands$' "$secure_boot_tool" &&
   grep -q '^  verify_installed_kernel_sign_file_paths$' "$secure_boot_tool"; then
  pass "arch kernel policy now explicitly enables initrd generation through initramfs-tools while leaving legacy link_in_boot answers commented"
else
  fail "arch kernel policy now explicitly enables initrd generation through initramfs-tools while leaving legacy link_in_boot answers commented"
fi

if grep -q '^stage_target_secure_boot_runtime_assets() {$' "$ROOT_DIR/d-i/forky/scripts/late/grub.sh" &&
   grep -q '^  ensure_target_secure_boot_state_mount$' "$ROOT_DIR/d-i/forky/scripts/late/grub.sh" &&
   grep -q '^  write_target_secure_boot_payloads$' "$ROOT_DIR/d-i/forky/scripts/late/grub.sh" &&
   grep -q '^  remove_target_secure_boot_crypttab_entry$' "$ROOT_DIR/d-i/forky/scripts/late/grub.sh" &&
   grep -q '^  install_target_secure_boot_kernel_hooks$' "$ROOT_DIR/d-i/forky/scripts/late/grub.sh"; then
  pass "late Secure Boot helper stages the managed MOK, DKMS config, and kernel hooks after pkgsel"
else
  fail "late Secure Boot helper stages the managed MOK, DKMS config, and kernel hooks after pkgsel"
fi

if grep -q '^repair_target_secure_boot_mok_manager_loader() {$' "$ROOT_DIR/d-i/forky/scripts/late/grub.sh" &&
   grep -q 'run_in_target "ensure MokManager EFI loader is staged on the ESP"' "$ROOT_DIR/d-i/forky/scripts/late/grub.sh" &&
   grep -q '"/usr/lib/shim/\${mok_manager_name}\.signed"' "$ROOT_DIR/d-i/forky/scripts/late/grub.sh" &&
   grep -q '"/usr/lib/shim/\${mok_manager_name}"' "$ROOT_DIR/d-i/forky/scripts/late/grub.sh" &&
   grep -q '^  repair_target_secure_boot_mok_manager_loader$' "$ROOT_DIR/d-i/forky/scripts/late/grub.sh"; then
  pass "late Secure Boot package repair explicitly stages MokManager onto the ESP before GRUB profile installation"
else
  fail "late Secure Boot package repair explicitly stages MokManager onto the ESP before GRUB profile installation"
fi

if grep -q '^ensure_target_grub_profile_mounts() {$' "$ROOT_DIR/d-i/forky/scripts/late/grub.sh" &&
   grep -q 'ensure_target_mount "\${DEV_PART_BOOT}" "/target\${DIR_BOOT}" ext4 "\${MNT_BOOT_OPTS}" "/boot"' "$ROOT_DIR/d-i/forky/scripts/late/grub.sh" &&
   grep -q 'ensure_target_mount "\${DEV_PART_EFI}" "/target\${DIR_BOOT_EFI}" vfat "\${MNT_EFI_OPTS}" "/boot/efi"' "$ROOT_DIR/d-i/forky/scripts/late/grub.sh" &&
   grep -q 'target /boot and /boot/efi must be mounted before GRUB profile installation' "$ROOT_DIR/d-i/forky/scripts/late/grub.sh" &&
   grep -q '^  ensure_target_grub_profile_mounts$' "$ROOT_DIR/d-i/forky/scripts/late/grub.sh"; then
  pass "GRUB profile installation now hard-requires target /boot and /boot/efi to be mounted"
else
  fail "GRUB profile installation now hard-requires target /boot and /boot/efi to be mounted"
fi

if ! grep -q '^ensure_target_initramfs_tooling() {$' "$ROOT_DIR/d-i/forky/scripts/late/grub.sh" &&
   ! grep -q 'load_target_boot_tool_state()' "$ROOT_DIR/d-i/forky/scripts/late/grub.sh" &&
   ! grep -q 'target update-initramfs is unavailable even though initramfs-tools should already be installed' "$ROOT_DIR/d-i/forky/scripts/late/grub.sh"; then
  pass "late GRUB flow no longer carries an initramfs availability gate or repair path"
else
  fail "late GRUB flow no longer carries an initramfs availability gate or repair path"
fi

if grep -q '^ensure_target_grubenv_ready() {$' "$ROOT_DIR/d-i/forky/scripts/late/grub.sh" &&
   grep -q '^  require_target_grub_installed$' "$ROOT_DIR/d-i/forky/scripts/late/grub.sh" &&
   grep -q 'grub-editenv is unavailable in target' "$ROOT_DIR/d-i/forky/scripts/late/grub.sh" &&
   grep -q 'grubenv is missing after creation' "$ROOT_DIR/d-i/forky/scripts/late/grub.sh" &&
   grep -q '^ensure_target_bootable_kernel_pairs() {$' "$ROOT_DIR/d-i/forky/scripts/late/grub.sh" &&
   ! grep -q '^create_missing_initrds() {$' "$ROOT_DIR/d-i/forky/scripts/late/grub.sh" &&
   ! grep -F -q 'update-initramfs -c -k "$ver"' "$ROOT_DIR/d-i/forky/scripts/late/grub.sh" &&
   ! grep -F -q 'update-initramfs -u' "$ROOT_DIR/d-i/forky/scripts/late/grub.sh" &&
   ! grep -q '^installed_kernel_packages() {$' "$ROOT_DIR/d-i/forky/scripts/late/grub.sh" &&
   grep -q 'no bootable kernel/initrd pairs exist under /boot' "$ROOT_DIR/d-i/forky/scripts/late/grub.sh" &&
   grep -q '^  ensure_target_grubenv_ready$' "$ROOT_DIR/d-i/forky/scripts/late/grub.sh" &&
   grep -q '^  ensure_target_bootable_kernel_pairs$' "$ROOT_DIR/d-i/forky/scripts/late/grub.sh"; then
  pass "GRUB profile installation now only verifies existing kernel and initrd pairs without late initramfs regeneration"
else
  fail "GRUB profile installation now only verifies existing kernel and initrd pairs without late initramfs regeneration"
fi

if grep -q '^  ensure_target_grub_profile_mounts$' "$ROOT_DIR/d-i/forky/scripts/late/grub.sh" &&
   grep -q 'target /boot/efi is not mounted during Secure Boot verification' "$ROOT_DIR/d-i/forky/scripts/late/grub.sh" &&
   ! grep -q "skipping ESP-side Secure Boot verification" "$ROOT_DIR/d-i/forky/scripts/late/grub.sh"; then
  pass "late Secure Boot verification now requires a mounted target /boot/efi instead of silently skipping ESP checks"
else
  fail "late Secure Boot verification now requires a mounted target /boot/efi instead of silently skipping ESP checks"
fi

if grep -q '^refresh_initramfs_for_kernel() {$' "$secure_boot_tool" &&
   grep -F -q 'skipping kernel image without a matching module tree: $kernelver' "$secure_boot_tool" &&
   grep -F -q 'skipping kernel repair for $kernelver because /lib/modules/$kernelver is missing' "$secure_boot_tool" &&
   grep -F -q 'update-initramfs -u -k "$kernelver" || fatal "failed to refresh initramfs for kernel $kernelver after Secure Boot module signing"' "$secure_boot_tool" &&
   grep -F -q 'update-initramfs -c -k "$kernelver" || fatal "failed to create initramfs for kernel $kernelver after Secure Boot module signing"' "$secure_boot_tool" &&
   ! grep -F -q 'mkinitramfs -o "/boot/initrd.img-$kernelver" "$kernelver"' "$secure_boot_tool" &&
   grep -F -q '[ -e "/boot/initrd.img-$kernelver" ] || fatal "initramfs is still missing for kernel $kernelver after Secure Boot kernel repair"' "$secure_boot_tool"; then
  pass "Secure Boot kernel repair now relies on update-initramfs create/update paths and still requires the initrd to exist afterward"
else
  fail "Secure Boot kernel repair now relies on update-initramfs create/update paths and still requires the initrd to exist afterward"
fi

if (
  set -eu
  . "$ROOT_DIR/d-i/forky/scripts/late/grub.sh"
  tmp_secure_boot_dir=$(mktemp -d "${TMPDIR:-/tmp}/grub-secure-boot-smoke.XXXXXX")
  trap 'rm -rf "$tmp_secure_boot_dir"' EXIT HUP INT TERM
  installer_fatal() { return 99; }
  shell_single_quote() {
    printf "'%s'\n" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
  }
  target_secure_boot_state_mode() { printf '%s\n' direct; }
  cat >"$tmp_secure_boot_dir/secure-boot-tool" <<'EOF'
#!/bin/sh
set -eu
[ "${1:-}" = prepare ] || exit 1
EOF
  chmod 0755 "$tmp_secure_boot_dir/secure-boot-tool"
  install -d -m 0755 "$tmp_secure_boot_dir/boot-efi/EFI/debian" "$tmp_secure_boot_dir/boot-efi/EFI/BOOT"
  : >"$tmp_secure_boot_dir/boot-efi/EFI/debian/shimx64.efi"
  : >"$tmp_secure_boot_dir/boot-efi/EFI/debian/grubx64.efi"
  : >"$tmp_secure_boot_dir/boot-efi/EFI/debian/mmx64.efi"
  : >"$tmp_secure_boot_dir/boot-efi/EFI/BOOT/BOOTX64.EFI"
  FILE_SECURE_BOOT_TOOL="$tmp_secure_boot_dir/secure-boot-tool"
  FILE_SECURE_BOOT_CONFIG=/etc/passwd
  FILE_DKMS_FRAMEWORK_SECURE_BOOT=/etc/passwd
  FILE_KERNEL_POSTINST_SIGN=/bin/sh
  FILE_KERNEL_POSTRM_SIGN=/bin/sh
  FILE_KERNEL_HEADER_POSTINST_SIGN=/bin/sh
  FILE_SECURE_BOOT_MOK_KEY=/etc/passwd
  FILE_SECURE_BOOT_MOK_CERT_PEM=/etc/passwd
  FILE_SECURE_BOOT_MOK_CERT_DER=/etc/passwd
  DIR_SECURE_BOOT_ENROLLMENT_ESP=/tmp
  FILE_SECURE_BOOT_MOK_CERT_DER_ESP=/etc/passwd
  DIR_BOOT_EFI="$tmp_secure_boot_dir/boot-efi"
  DIR_BOOT=/boot
  DEV_PART_BOOT=/dev/test-boot
  DEV_PART_EFI=/dev/test-efi
  MNT_BOOT_OPTS=defaults
  MNT_EFI_OPTS=defaults
  INSTALLER_GRUB_SHIM_EFI_PATH=/EFI/debian/shimx64.efi
  INSTALLER_GRUB_BINARY_EFI_PATH=/EFI/debian/grubx64.efi
  INSTALLER_GRUB_MOK_MANAGER_EFI_PATH=/EFI/debian/mmx64.efi
  INSTALLER_GRUB_REMOVABLE_BOOT_EFI_PATH=/EFI/BOOT/BOOTX64.EFI
  target_is_mounted() { return 0; }
  target_mount_source() { return 0; }
  ensure_target_mount() { return 0; }
  test_in_target() { return 0; }
  run_in_target() {
    [ "$1" = "verify staged Secure Boot payload" ]
    [ "$2" = /bin/sh ]
    [ "$3" = -c ]
    [ "$#" -eq 4 ]
    printf '%s\n' "$4" | grep -F -q "state_mode='direct'"
    ! printf '%s\n' "$4" | grep -F -q 'state_mode=$1'
    /bin/sh -c "$4" >/dev/null 2>&1
  }
  verify_target_secure_boot_staging
); then
  pass "late Secure Boot verifier inlines quoted values and runs without sh -c positional arguments"
else
  fail "late Secure Boot verifier inlines quoted values and runs without sh -c positional arguments"
fi

if grep -q '^[[:space:]]*if reset_target_secure_boot_mok_state; then$' "$ROOT_DIR/d-i/forky/scripts/late/btrfs-family.sh" &&
   grep -q '^[[:space:]]*if reset_target_secure_boot_mok_state; then$' "$ROOT_DIR/d-i/forky/scripts/late/f2fs-family.sh" &&
   grep -q '^[[:space:]]*queue_target_grub_mok_enrollment_boot_for_reset$' "$ROOT_DIR/d-i/forky/scripts/late/btrfs-family.sh" &&
   grep -q '^[[:space:]]*queue_target_grub_mok_enrollment_boot_for_reset$' "$ROOT_DIR/d-i/forky/scripts/late/f2fs-family.sh" &&
   grep -q '^  sync_target_secure_boot_bundle_to_installer_usb$' "$ROOT_DIR/d-i/forky/scripts/late/btrfs-family.sh" &&
   grep -q '^  sync_target_secure_boot_bundle_to_installer_usb$' "$ROOT_DIR/d-i/forky/scripts/late/f2fs-family.sh"; then
  pass "late storage families reset MOK state and stage the MokManager boot only after GRUB is installed"
else
  fail "late storage families reset MOK state and stage the MokManager boot only after GRUB is installed"
fi

btrfs_family="$ROOT_DIR/d-i/forky/scripts/late/btrfs-family.sh"
f2fs_family="$ROOT_DIR/d-i/forky/scripts/late/f2fs-family.sh"
btrfs_pkgsel_repair_line=$(grep -n '^repair_target_pkgsel_include_packages$' "$btrfs_family" | head -n 1 | cut -d: -f1)
btrfs_grub_update_line=$(grep -n '^  run_target_grub_config_update$' "$btrfs_family" | head -n 1 | cut -d: -f1)
btrfs_mok_reset_line=$(grep -n '^  if reset_target_secure_boot_mok_state; then$' "$btrfs_family" | head -n 1 | cut -d: -f1)
btrfs_grub_queue_line=$(grep -n '^    queue_target_grub_mok_enrollment_boot_for_reset$' "$btrfs_family" | head -n 1 | cut -d: -f1)
btrfs_kernel_repair_line=$(grep -n '^  repair_target_installed_kernels$' "$btrfs_family" | head -n 1 | cut -d: -f1)
f2fs_pkgsel_repair_line=$(grep -n '^repair_target_pkgsel_include_packages$' "$f2fs_family" | head -n 1 | cut -d: -f1)
f2fs_grub_update_line=$(grep -n '^  run_target_grub_config_update$' "$f2fs_family" | head -n 1 | cut -d: -f1)
f2fs_mok_reset_line=$(grep -n '^  if reset_target_secure_boot_mok_state; then$' "$f2fs_family" | head -n 1 | cut -d: -f1)
f2fs_grub_queue_line=$(grep -n '^    queue_target_grub_mok_enrollment_boot_for_reset$' "$f2fs_family" | head -n 1 | cut -d: -f1)
f2fs_kernel_repair_line=$(grep -n '^  repair_target_installed_kernels$' "$f2fs_family" | head -n 1 | cut -d: -f1)
if [ -n "${btrfs_pkgsel_repair_line:-}" ] &&
   [ -n "${btrfs_grub_update_line:-}" ] &&
   [ -n "${btrfs_mok_reset_line:-}" ] &&
   [ -n "${btrfs_grub_queue_line:-}" ] &&
   [ -n "${btrfs_kernel_repair_line:-}" ] &&
   [ -n "${f2fs_pkgsel_repair_line:-}" ] &&
   [ -n "${f2fs_grub_update_line:-}" ] &&
   [ -n "${f2fs_mok_reset_line:-}" ] &&
   [ -n "${f2fs_grub_queue_line:-}" ] &&
   [ -n "${f2fs_kernel_repair_line:-}" ] &&
   ! grep -q '^write_target_secure_boot_payloads$' "$btrfs_family" &&
   ! grep -q '^remove_target_secure_boot_crypttab_entry$' "$btrfs_family" &&
   ! grep -q '^write_target_secure_boot_payloads$' "$f2fs_family" &&
   ! grep -q '^remove_target_secure_boot_crypttab_entry$' "$f2fs_family" &&
   ! grep -q '^install_target_secure_boot_kernel_hooks$' "$btrfs_family" &&
   ! grep -q '^install_target_secure_boot_kernel_hooks$' "$f2fs_family" &&
   [ "$btrfs_grub_update_line" -lt "$btrfs_mok_reset_line" ] &&
   [ "$btrfs_mok_reset_line" -lt "$btrfs_grub_queue_line" ] &&
   [ "$btrfs_grub_queue_line" -lt "$btrfs_kernel_repair_line" ] &&
   [ "$btrfs_grub_update_line" -lt "$btrfs_kernel_repair_line" ] &&
   [ "$f2fs_grub_update_line" -lt "$f2fs_mok_reset_line" ] &&
   [ "$f2fs_mok_reset_line" -lt "$f2fs_grub_queue_line" ] &&
   [ "$f2fs_grub_queue_line" -lt "$f2fs_kernel_repair_line" ] &&
   [ "$f2fs_grub_update_line" -lt "$f2fs_kernel_repair_line" ]; then
  pass "late storage families reset MOK state after update-grub before final kernel repair"
else
  fail "late storage families reset MOK state after update-grub before final kernel repair"
fi

if grep -q '^validate_secure_boot_certificate_settings() {$' "$secure_boot_tool" &&
   grep -F -q 'validate_country_code SECURE_BOOT_MOK_COUNTRY "$SECURE_BOOT_MOK_COUNTRY"' "$secure_boot_tool" &&
   grep -F -q "printf '%s\\n' '[ req ]'" "$secure_boot_tool" &&
   grep -F -q 'printf '\''mok_signing_key=%s\n'\'' "$(shell_single_quote "$SECURE_BOOT_MOK_KEY")"' "$secure_boot_tool" &&
   ! grep -F -q 'cat >"$SECURE_BOOT_OPENSSL_CONFIG" <<' "$secure_boot_tool" &&
   ! grep -F -q 'cat >"$SECURE_BOOT_DKMS_CONF" <<' "$secure_boot_tool"; then
  pass "secure boot helper validates certificate settings and avoids expanding heredocs for generated configs"
else
  fail "secure boot helper validates certificate settings and avoids expanding heredocs for generated configs"
fi

boot_env="$ROOT_DIR/d-i/forky/hosts/shared/boot.env"
display_template="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/default/grub.d/07-display.cfg.tmpl"
if grep -q '^GRUB_DISPLAY_GFXMODE="1024x768,auto"$' "$boot_env" &&
   grep -q '^GRUB_DISPLAY_PRELOAD_MODULES="efi_gop gfxterm"$' "$boot_env" &&
   ! grep -q '^GRUB_DISPLAY_COLOR_' "$boot_env" &&
   ! grep -q '^GRUB_COLOR_NORMAL=' "$display_template" &&
   ! grep -q '^GRUB_COLOR_HIGHLIGHT=' "$display_template"; then
  pass "managed GRUB display policy keeps GOP gfxterm at VGA 766 equivalent gfxmode without color settings"
else
  fail "managed GRUB display policy keeps GOP gfxterm at VGA 766 equivalent gfxmode without color settings"
fi

if grep -F -q 'menuentry "Last Boot (\$active_profile_label) [\$active_kernel_ver]"' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/default/grub-profiles.tmpl" &&
   grep -q '^installer_usb_first_partition() {$' "$ROOT_DIR/d-i/forky/scripts/late/grub.sh" &&
   grep -q 'LC_ALL=C fdisk -l -o Device,Type -- "$parent_disk"' "$ROOT_DIR/d-i/forky/scripts/late/grub.sh" &&
   grep -q 'index($0, "EFI System")' "$ROOT_DIR/d-i/forky/scripts/late/grub.sh" &&
   grep -q '^managed_grub_display_preload_modules() {$' "$ROOT_DIR/d-i/forky/scripts/late/grub.sh" &&
   grep -q '^normalize_target_grub_video_stack() {$' "$ROOT_DIR/d-i/forky/scripts/late/grub.sh"; then
  pass "managed GRUB labels last-boot entries clearly and discovers the installer USB EFI partition via fdisk before hardening EFI video loading"
else
  fail "managed GRUB labels last-boot entries clearly and discovers the installer USB EFI partition via fdisk before hardening EFI video loading"
fi

if grep -q 'best_source_fstype=' "$ROOT_DIR/d-i/forky/scripts/late/grub.sh" &&
   grep -q 'best_source_fstype=$(blkid -s TYPE -o value "$mount_source"' "$ROOT_DIR/d-i/forky/scripts/late/grub.sh"; then
  pass "GRUB rescue USB UUID detection records the mounted installer source filesystem type before falling back to the first FAT partition"
else
  fail "GRUB rescue USB UUID detection records the mounted installer source filesystem type before falling back to the first FAT partition"
fi

if grep -q '^secure_boot_packages_stage_stamp() {$' "$ROOT_DIR/d-i/forky/scripts/late/grub.sh" &&
   grep -q '^secure_boot_packages_stage_is_complete() {$' "$ROOT_DIR/d-i/forky/scripts/late/grub.sh" &&
   grep -q '^mark_secure_boot_packages_stage_complete() {$' "$ROOT_DIR/d-i/forky/scripts/late/grub.sh" &&
   grep -Fq 'Secure Boot target packages already repaired earlier in this install; skipping duplicate package and GRUB EFI refresh' "$ROOT_DIR/d-i/forky/scripts/late/grub.sh" &&
   grep -Fq 'mark_secure_boot_packages_stage_complete' "$ROOT_DIR/d-i/forky/scripts/late/grub.sh"; then
  pass "late Secure Boot package repair persists a completion stamp so repeated late_command runs skip duplicate shim and GRUB reinstalls"
else
  fail "late Secure Boot package repair persists a completion stamp so repeated late_command runs skip duplicate shim and GRUB reinstalls"
fi

snapshot_menu_line=$(grep -n "submenu 'BTRFS Snapshots'" "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/default/grub-profiles.tmpl" | head -n 1 | cut -d: -f1)
rescue_menu_line=$(grep -n "menuentry 'Boot from Rescue USB'" "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/default/grub-profiles.tmpl" | head -n 1 | cut -d: -f1)
if [ -n "${snapshot_menu_line:-}" ] &&
   [ -n "${rescue_menu_line:-}" ] &&
   [ "$snapshot_menu_line" -lt "$rescue_menu_line" ] &&
   grep -q 'configfile "${prefix}/grub-btrfs.cfg"' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/default/grub-profiles.tmpl"; then
  pass "managed GRUB menu places BTRFS snapshots before the rescue USB entry"
else
  fail "managed GRUB menu places BTRFS snapshots before the rescue USB entry"
fi

initramfs_btrfs_skip_hook="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/initramfs-tools/scripts/local-premount/20-btrfs-root-no-fsck"
if [ ! -e "$initramfs_btrfs_skip_hook" ] &&
   ! grep -q '20-btrfs-root-no-fsck' "$ROOT_DIR/d-i/forky/scripts/late/btrfs-family.sh" &&
   ! grep -q '20-btrfs-root-no-fsck' "$ROOT_DIR/d-i/forky/scripts/late/f2fs-family.sh"; then
  pass "filesystem-family staging no longer installs an initramfs fsck interceptor"
else
  fail "filesystem-family staging no longer installs an initramfs fsck interceptor"
fi

if ! grep -q 'install_target_mok_profile_aliases' "$ROOT_DIR/d-i/forky/scripts/late/grub.sh" &&
   ! grep -q 'install_target_mok_profile_aliases' "$ROOT_DIR/d-i/forky/scripts/late/btrfs-family.sh" &&
   ! grep -q 'install_target_mok_profile_aliases' "$ROOT_DIR/d-i/forky/scripts/late/f2fs-family.sh" &&
   ! grep -q 'Managed installer MOK LUKS aliases' "$ROOT_DIR/d-i/forky/scripts/late/grub.sh"; then
  pass "secure boot late helpers no longer rewrite managed shell rc files with MOK aliases"
else
  fail "secure boot late helpers no longer rewrite managed shell rc files with MOK aliases"
fi
