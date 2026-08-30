#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/crypto-addon-smoke.XXXXXX")
trap 'rm -rf "$TMP_DIR"' EXIT HUP INT TERM

TEST_COUNT=13
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
  if [ "$#" -gt 1 ] && [ -n "${2:-}" ] && [ -r "$2" ]; then
    sed 's/^/# /' "$2"
  fi
}

word_list_has() {
  case " $1 " in
    *" $2 "*) return 0 ;;
  esac
  return 1
}

printf '1..%s\n' "$TEST_COUNT"

crypto_cfg="$ROOT_DIR/d-i/forky/classes/class-addon/crypto.cfg"
if grep -q '^d-i anna/choose_modules multiselect crypto-dm-modules$' "$crypto_cfg" &&
   grep -q '^d-i pkgsel/include string cryptsetup-initramfs systemd-cryptsetup systemd-tpm tpm2-tools tpm-udev mokutil$' "$crypto_cfg" &&
   ! grep -qi dracut "$crypto_cfg"; then
  pass "crypto class keeps initramfs-tools and installs the TPM2 token runtime"
else
  fail "crypto class keeps initramfs-tools and installs the TPM2 token runtime" "$crypto_cfg"
fi

addons_cfg="$ROOT_DIR/d-i/forky/classes/configs/addons.cfg"
if grep -q '^Name: crypto$' "$addons_cfg" &&
   grep -q '^AllowedHardwareClasses: disk/nvme, disk/vm, disk/emmc$' "$addons_cfg" &&
   grep -q '^LateHelper: crypto$' "$addons_cfg"; then
  pass "crypto class metadata wires hardware policy and the late helper"
else
  fail "crypto class metadata wires hardware policy and the late helper" "$addons_cfg"
fi

render_err="$TMP_DIR/render.err"
classes='lab,desktop,standard,dhcp,crypto,arch/amd64,cpu/intel,gpu/generic,disk/vm'
if answers_file=$(
  INSTALLER_RUNTIME_DIR="$TMP_DIR/runtime" \
  INSTALLER_SOURCE_ROOT="$ROOT_DIR/d-i/forky" \
  INSTALLER_CMDLINE="classes=$classes primary_user=user primary_password=secret root_password=root" \
    /bin/sh "$ROOT_DIR/d-i/forky/scripts/preseed/answers.sh" render "$ROOT_DIR/d-i/forky" 2>"$render_err"
); then
  pkgsel=$(sed -n 's/^d-i pkgsel\/include string //p' "$answers_file" | tail -n 1)
  if word_list_has "$pkgsel" initramfs-tools &&
     word_list_has "$pkgsel" cryptsetup-initramfs &&
     word_list_has "$pkgsel" systemd-cryptsetup &&
     word_list_has "$pkgsel" systemd-tpm &&
     word_list_has "$pkgsel" tpm2-tools &&
     word_list_has "$pkgsel" tpm-udev &&
     word_list_has "$pkgsel" mokutil &&
     ! word_list_has "$pkgsel" dracut &&
     grep -q '^d-i base-installer/kernel/linux/initramfs-generators string initramfs-tools$' "$answers_file"; then
    pass "rendered crypto install keeps initramfs-tools and adds required packages"
  else
    fail "rendered crypto install keeps initramfs-tools and adds required packages" "$answers_file"
  fi
else
  fail "rendered crypto install keeps initramfs-tools and adds required packages" "$render_err"
fi

crypto_answers="$TMP_DIR/runtime/state/crypto.answers.cfg"
if (
  set -eu
  INSTALLER_RUNTIME_DIR="$TMP_DIR/runtime"
  INSTALLER_SELECTED_CLASS_REFS=addon/crypto
  INSTALLER_CMDLINE='classes=crypto primary_user=alice'
  export INSTALLER_RUNTIME_DIR INSTALLER_SELECTED_CLASS_REFS INSTALLER_CMDLINE
  # shellcheck disable=SC1090
  . "$ROOT_DIR/d-i/forky/scripts/runtime/common.sh"
  RUNTIME_COMMON_LIB="$ROOT_DIR/d-i/forky/scripts/runtime/common.sh"
  export RUNTIME_COMMON_LIB
  # shellcheck disable=SC1090
  . "$ROOT_DIR/d-i/forky/scripts/runtime/account.sh"
  # shellcheck disable=SC1090
  . "$ROOT_DIR/d-i/forky/hosts/shared/account.env"
  runtime_write_crypto_answers "$crypto_answers"
  passphrase=$(sed -n 's/^d-i partman-crypto\/passphrase password //p' "$crypto_answers")
  passphrase_again=$(sed -n 's/^d-i partman-crypto\/passphrase-again password //p' "$crypto_answers")
  bootstrap_key="$INSTALLER_RUNTIME_DIR/state/crypto-bootstrap.key"
  ! grep -q '^d-i partman-auto-crypto/erase_disks ' "$crypto_answers"
  [ "$passphrase" = "$passphrase_again" ]
  [ "$passphrase" != alice ]
  case "$passphrase" in
    ????????-????-????-????-????????????) ;;
    *) exit 1 ;;
  esac
  [ -f "$bootstrap_key" ] && [ ! -L "$bootstrap_key" ]
  [ "$(cat "$bootstrap_key")" = "$passphrase" ]
  [ "$(stat -c %a "$bootstrap_key")" = 400 ]
  runtime_write_crypto_answers "$crypto_answers"
  [ "$(sed -n 's/^d-i partman-crypto\/passphrase password //p' "$crypto_answers")" = "$passphrase" ]
); then
  pass "runtime crypto preseeding reuses a root-only random bootstrap key"
else
  fail "runtime crypto preseeding reuses a root-only random bootstrap key" "$crypto_answers"
fi

no_od_bin="$TMP_DIR/no-od-bin"
no_od_answers="$TMP_DIR/no-od.answers"
no_od_error="$TMP_DIR/no-od.err"
mkdir -p "$no_od_bin"
for command_name in chmod dirname grep install mv; do
  command_path=$(command -v "$command_name")
  ln -s "$command_path" "$no_od_bin/$command_name"
done
if PATH="$no_od_bin" \
   INSTALLER_SELECTED_CLASS_REFS=addon/crypto \
   INSTALLER_CMDLINE='classes=crypto primary_user=alice' \
   /bin/sh -c '
set -eu
command -v od >/dev/null 2>&1 && exit 1
. "$1"
RUNTIME_COMMON_LIB=$1
export RUNTIME_COMMON_LIB
. "$2"
. "$3"
runtime_write_crypto_answers "$4"
' sh \
     "$ROOT_DIR/d-i/forky/scripts/runtime/common.sh" \
     "$ROOT_DIR/d-i/forky/scripts/runtime/account.sh" \
     "$ROOT_DIR/d-i/forky/hosts/shared/account.env" \
     "$no_od_answers" \
     2>"$no_od_error" &&
   no_od_passphrase=$(sed -n 's/^d-i partman-crypto\/passphrase password //p' "$no_od_answers") &&
   [ "$no_od_passphrase" != alice ] &&
   [ -f "$TMP_DIR/crypto-bootstrap.key" ] &&
   ! grep -q 'unable to generate crypto bootstrap key' "$no_od_error" &&
   ! grep -q "cat: can't open ''" "$no_od_error"; then
  pass "crypto answer rendering uses kernel UUID entropy without od"
else
  fail "crypto answer rendering uses kernel UUID entropy without od" "$no_od_error"
fi

late_crypto="$ROOT_DIR/d-i/forky/scripts/late/crypto.sh"
if grep -q '^crypto_stage_install_passphrase_file() {$' "$late_crypto" &&
   grep -q 'bootstrap_key_file="${runtime_dir}/state/crypto-bootstrap.key"' "$late_crypto" &&
   grep -q 'crypto_stage_install_passphrase_file "$bootstrap_key_file" "$install_passphrase_host"' "$late_crypto" &&
   grep -q 'crypto_passphrase_works "$DEV_PART_ROOT" "$install_passphrase_host"' "$late_crypto" &&
   grep -q 'crypto_passphrase_works "$DEV_PART_HOME" "$install_passphrase_host"' "$late_crypto" &&
   grep -q '/usr/local/lib/crypto/install-passphrase' "$late_crypto" &&
   grep -q 'runtime_generate_crypto_bootstrap_key()' "$ROOT_DIR/d-i/forky/scripts/runtime/common.sh" &&
   grep -q 'crypto-bootstrap.key' "$late_crypto" &&
   ! grep -q 'does not match primary_user' "$late_crypto"; then
  pass "late crypto stages only the random bootstrap key for enrollment"
else
  fail "late crypto stages only the random bootstrap key for enrollment" "$late_crypto"
fi

crypto_state_template="$ROOT_DIR/d-i/forky/hooks/shared/target/usr/local/lib/crypto/config.env.tmpl"
tpm2_config_template="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/tpm2-cryptroot.conf.tmpl"
cryptsetup_initramfs_config="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/cryptsetup-initramfs/conf-hook"
if grep -q '^crypto_render_target_template() {$' "$late_crypto" &&
   grep -q 'usr/local/lib/crypto/config.env.tmpl' "$late_crypto" &&
   grep -q 'etc/tpm2-cryptroot.conf.tmpl' "$late_crypto" &&
   grep -q 'etc/cryptsetup-initramfs/conf-hook' "$late_crypto" &&
   grep -q '^PRIMARY_USER=__INSTALLER_CRYPTO_PRIMARY_USER_VALUE__$' "$crypto_state_template" &&
   grep -q '^TPM2_FINAL_PCRS=__INSTALLER_CRYPTO_TPM2_FINAL_PCRS_VALUE__$' "$crypto_state_template" &&
   grep -q '^TPM2_CRYPTROOT_NAME=__INSTALLER_TPM2_CRYPTROOT_NAME_VALUE__$' "$tpm2_config_template" &&
   grep -q '^TPM2_CRYPTROOT_UUID=__INSTALLER_TPM2_CRYPTROOT_UUID_VALUE__$' "$tpm2_config_template" &&
   grep -q '^CRYPTSETUP=y$' "$cryptsetup_initramfs_config" &&
   ! grep -q "printf 'CRYPTSETUP=y" "$late_crypto" &&
   ! grep -q 'write_shell_config_var TPM2_CRYPTROOT_' "$late_crypto"; then
  pass "crypto persistent configuration is staged from tracked target-mirror templates"
else
  fail "crypto persistent configuration is staged from tracked target-mirror templates" "$late_crypto"
fi

btrfs_recipe="$TMP_DIR/btrfs.recipe"
btrfs_partman="$TMP_DIR/btrfs.partman"
btrfs_dual_partman="$TMP_DIR/btrfs-dual.partman"
if (
  set -eu
  INSTALLER_SELECTED_CLASS_REFS=addon/crypto
  export INSTALLER_SELECTED_CLASS_REFS
  # shellcheck disable=SC1090
  . "$ROOT_DIR/d-i/forky/scripts/runtime/common.sh"
  RUNTIME_COMMON_LIB="$ROOT_DIR/d-i/forky/scripts/runtime/common.sh"
  export RUNTIME_COMMON_LIB
  # shellcheck disable=SC1090
  . "$ROOT_DIR/d-i/forky/scripts/runtime/btrfs.sh"
  DEV_PART_BOOT_MB=100
  DEV_PART_ROOT_MB=1000
  DEV_PART_HOME_MB=1000
  DEV_PART_OPT_MB=100
  DEV_PART_DATA_MB=100
  DEV_PART_POOL_MB=100
  DEV_PART_VAR_TMP_MB=100
  DEV_PART_VAR_LIB_SHSIGNED_MB=100
  DEV_PART_VAR_LOG_JOURNAL_MB=100
  DEV_PART_RAW_SWAP_MB=100
  DEV_PART_RAW_ZRAM_MB=100
  FS_LABEL_VAR_LIB_SHSIGNED=SHIM
  DUALBOOT_ENABLED=false
  DEV_INSTALL_DISK=/dev/test
  PARTMAN_RECIPE_NAME=test-crypto-layout
  runtime_emit_debian_partition_recipe >"$btrfs_recipe"
  runtime_write_partman_fragment "$btrfs_partman" "$btrfs_recipe"
  DUALBOOT_ENABLED=true
  RUNTIME_EFI_SLOT=1
  RUNTIME_DEBIAN_START_SLOT=5
  RUNTIME_PRESERVED_SLOTS='2 3 4'
  runtime_write_partman_fragment "$btrfs_dual_partman" "$btrfs_recipe"
) &&
   [ "$(grep -c 'method{ crypto } format{ }' "$btrfs_recipe")" -eq 1 ] &&
   [ "$(grep -c 'crypto_type{ luks }' "$btrfs_recipe")" -eq 1 ] &&
   ! grep -q 'crypto_type{ dm-crypt }' "$btrfs_recipe" &&
   [ "$(grep -c 'keysize{ 512 }' "$btrfs_recipe")" -eq 1 ] &&
   grep -q 'mountpoint{ / }' "$btrfs_recipe" &&
   ! grep -q 'mountpoint{ /home }' "$btrfs_recipe" &&
   ! grep -q 'mountpoint{ /var/lib/shim-signed }' "$btrfs_recipe" &&
   grep -q '^d-i partman-auto/init_automatically_partition select installer_target_free$' "$btrfs_partman" &&
   ! grep -q '^d-i partman-auto/method string crypto$' "$btrfs_partman" &&
   ! grep -q '^d-i partman-auto/method string regular$' "$btrfs_dual_partman" &&
   ! grep -q '^d-i partman-auto/method string crypto$' "$btrfs_dual_partman"; then
  pass "Btrfs crypto recipes leave only root to native partman crypto"
else
  fail "Btrfs recipes encrypt root and home in addition to Secure Boot state" "$btrfs_recipe"
fi

f2fs_recipe="$TMP_DIR/f2fs.recipe"
f2fs_partman="$TMP_DIR/f2fs.partman"
if (
  set -eu
  INSTALLER_SELECTED_CLASS_REFS=addon/crypto
  export INSTALLER_SELECTED_CLASS_REFS
  # shellcheck disable=SC1090
  . "$ROOT_DIR/d-i/forky/scripts/runtime/common.sh"
  RUNTIME_COMMON_LIB="$ROOT_DIR/d-i/forky/scripts/runtime/common.sh"
  export RUNTIME_COMMON_LIB
  # shellcheck disable=SC1090
  . "$ROOT_DIR/d-i/forky/scripts/runtime/f2fs.sh"
  DEV_PART_BOOT_MB=100
  DEV_PART_ROOT_MB=1000
  DEV_PART_HOME_MB=1000
  DEV_PART_POOL_MB=0
  DEV_PART_VAR_LIB_SHSIGNED_MB=0
  DEV_PART_VAR_LOG_JOURNAL_MB=100
  DEV_PART_RAW_SWAP_MB=100
  DEV_PART_RAW_ZRAM_MB=100
  DUALBOOT_ENABLED=false
  DEV_INSTALL_DISK=/dev/test
  PARTMAN_RECIPE_NAME=test-crypto-layout
  runtime_emit_debian_partition_recipe >"$f2fs_recipe"
  runtime_write_partman_fragment "$f2fs_partman" "$f2fs_recipe"
) &&
   [ "$(grep -c 'method{ crypto } format{ }' "$f2fs_recipe")" -eq 1 ] &&
   [ "$(grep -c 'crypto_type{ luks }' "$f2fs_recipe")" -eq 1 ] &&
   ! grep -q 'crypto_type{ dm-crypt }' "$f2fs_recipe" &&
   [ "$(grep -c 'keysize{ 512 }' "$f2fs_recipe")" -eq 1 ] &&
   grep -q 'mountpoint{ / }' "$f2fs_recipe" &&
   ! grep -q 'mountpoint{ /home }' "$f2fs_recipe" &&
   ! grep -q 'mountpoint{ /var/lib/shim-signed }' "$f2fs_recipe" &&
   grep -q '^d-i partman-auto/init_automatically_partition select installer_target_free$' "$f2fs_partman" &&
   ! grep -q '^d-i partman-auto/method string crypto$' "$f2fs_partman" &&
   ! (
     INSTALLER_SELECTED_CLASS_REFS=addon/crypto
     export INSTALLER_SELECTED_CLASS_REFS
     # shellcheck disable=SC1090
     . "$ROOT_DIR/d-i/forky/scripts/runtime/common.sh"
     DEV_PART_ROOT=/dev/root
     DEV_PART_HOME=
     DEV_PART_HOME_MB=0
     runtime_validate_root_home_crypto_layout
   ) >/dev/null 2>&1; then
  pass "F2FS crypto recipes leave only root to native partman crypto"
else
  fail "F2FS recipes encrypt root/home and reject profiles without dedicated home" "$f2fs_recipe"
fi

finish_hook="$ROOT_DIR/d-i/forky/hooks/shared/partman/finish.d/99-storage-layout.sh"
late_devices="$ROOT_DIR/d-i/forky/scripts/late/zram-swap.sh"
if grep -q '^layout_mapper_for_raw_device() {$' "$finish_hook" &&
   grep -q '^layout_require_luks2() {$' "$finish_hook" &&
   grep -q '^layout_resolve_root_home_filesystem_devices() {$' "$finish_hook" &&
   grep -q 'Resolved native LUKS2 root and direct-managed encrypted home' "$finish_hook" &&
   grep -q '^layout_crypto_bootstrap_key_file() {$' "$finish_hook" &&
   grep -q '^layout_format_luks2_partition() {$' "$finish_hook" &&
   grep -q '^layout_open_luks2_partition() {$' "$finish_hook" &&
   grep -q 'layout_format_luks2_partition "\$DEV_PART_HOME" "\$HOME_CRYPT_NAME" "\$bootstrap_key_file"' "$finish_hook" &&
   grep -q '^install_crypto_skip_erase_hook() {$' "$ROOT_DIR/d-i/forky/hooks/shared/partman/btrfs-early.sh" &&
   grep -q '^install_crypto_skip_erase_hook() {$' "$ROOT_DIR/d-i/forky/hooks/shared/partman/f2fs-early.sh" &&
   grep -q ': >\"\$part_dir/skip_erase\"' "$ROOT_DIR/d-i/forky/hooks/shared/partman/btrfs-early.sh" &&
   grep -q ': >\"\$part_dir/skip_erase\"' "$ROOT_DIR/d-i/forky/hooks/shared/partman/f2fs-early.sh" &&
   ! grep -q 'partman-auto-crypto/erase_disks' "$ROOT_DIR/d-i/forky/scripts/runtime/common.sh" &&
   grep -q '^  install_crypto_skip_erase_hook$' "$ROOT_DIR/d-i/forky/hooks/shared/partman/btrfs-early.sh" &&
   grep -q '^  install_crypto_skip_erase_hook$' "$ROOT_DIR/d-i/forky/hooks/shared/partman/f2fs-early.sh" &&
   grep -q '^installer_filesystem_device() {$' "$late_devices" &&
   grep -q 'UUID=%s none luks,discard,initramfs' "$late_crypto" &&
   grep -q 'UUID=%s %s luks,discard' "$late_crypto" &&
   grep -q 'cryptsetup-keys.d/crypthome.key' "$late_crypto" &&
   grep -q -- '--unlock-key-file="$install_passphrase_target"' "$late_crypto" &&
   grep -q -- '--tpm2-pcrs=7' "$late_crypto" &&
   grep -q 'SecureBoot enabled' "$late_crypto" &&
   ! grep -q 'systemd-tpm2-generator' "$late_crypto" &&
   grep -q '/etc/initramfs-tools/scripts/local-top/00-tpm2-cryptroot' "$late_crypto" &&
   grep -q 'crypto-bootstrap.key' "$late_crypto"; then
  pass "partman creates native LUKS2 mappings before root validation"
else
  fail "partman and late-command use active mappers plus UUID-based crypttab" "$late_crypto"
fi

initramfs_hook="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/initramfs-tools/hooks/tpm2-cryptroot"
initramfs_script="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/initramfs-tools/scripts/local-top/tpm2-cryptroot"
if /bin/sh -n "$initramfs_hook" &&
   /bin/sh -n "$initramfs_script" &&
   grep -q 'libcryptsetup-token-systemd-tpm2.so' "$initramfs_hook" &&
   grep -q 'manual_add_modules dm_crypt' "$initramfs_hook" &&
   grep -q 'manual_add_modules tpm_crb' "$initramfs_hook" &&
   grep -q 'manual_add_modules tpm_tis_spi' "$initramfs_hook" &&
   grep -q 'manual_add_modules tpm_tis_i2c' "$initramfs_hook" &&
   grep -q 'manual_add_modules tpm_ftpm_tee' "$initramfs_hook" &&
   grep -q -- '--token-only' "$initramfs_script" &&
   grep -q -- '--token-type systemd-tpm2' "$initramfs_script" &&
   grep -q -- '--allow-discards' "$initramfs_script" &&
   grep -q 'falling back to recovery passphrase' "$initramfs_script" &&
   grep -q 'scripts/local-top/00-tpm2-cryptroot' "$late_crypto" &&
   ! grep -qi dracut "$initramfs_hook" "$initramfs_script"; then
  pass "initramfs-tools embeds TPM2 and dm-crypt support with fallback"
else
  fail "initramfs-tools embeds TPM2 and dm-crypt support with fallback" "$initramfs_script"
fi

enroll_helper="$ROOT_DIR/d-i/forky/hooks/shared/target/usr/local/sbin/tpm2-enroll.sh"
enroll_launcher="$ROOT_DIR/d-i/forky/hooks/shared/target/usr/local/bin/tpm2-enroll-launch"
enroll_prompt="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/profile.d/tpm2-enroll-prompt.sh"
if /bin/sh -n "$late_crypto" &&
   /bin/sh -n "$enroll_helper" &&
   /bin/sh -n "$enroll_launcher" &&
   /bin/sh -n "$enroll_prompt" &&
   grep -q 'FILE_CRYPTO_STATE_CONFIG' "$late_crypto" &&
   grep -q 'FILE_CRYPTO_PENDING' "$late_crypto" &&
   grep -q 'FILE_CRYPTO_COMPLETE' "$late_crypto" &&
   grep -q '/usr/local/lib/crypto/config.env' "$enroll_helper" &&
   grep -q '^STATE_DIR=\${TPM2_ENROLL_STATE_DIR:-/usr/local/lib/crypto}$' "$enroll_helper" &&
   grep -q '^PENDING_FILE=\${TPM2_ENROLL_PENDING_FILE:-\${STATE_DIR}/tpm2-enroll.pending}$' "$enroll_helper" &&
   grep -q 'New recovery passphrase' "$enroll_helper" &&
   grep -q 'Confirm recovery passphrase' "$enroll_helper" &&
   grep -q 'minimum 20 characters' "$enroll_helper" &&
   grep -q -- '--pbkdf argon2id' "$enroll_helper" &&
   grep -q -- '--iter-time 5000' "$enroll_helper" &&
   grep -q 'verify_fallback_pbkdf' "$enroll_helper" &&
   grep -q 'New TPM2 PIN' "$enroll_helper" &&
   grep -q 'Confirm TPM2 PIN' "$enroll_helper" &&
   grep -q 'cryptenroll.tpm2-pin' "$enroll_helper" &&
   grep -q 'cryptenroll.new-tpm2-pin' "$enroll_helper" &&
   grep -q -- '--unlock-key-file="$fallback_key"' "$enroll_helper" &&
   grep -q -- '--unlock-tpm2-device=auto' "$enroll_helper" &&
   grep -q -- '--tpm2-with-pin=yes' "$enroll_helper" &&
   grep -q '^: "\${TPM2_FINAL_PCRS:?TPM2_FINAL_PCRS must be configured}"$' "$enroll_helper" &&
   grep -q '\[ "$TPM2_FINAL_PCRS" = 7+14 \]' "$enroll_helper" &&
   grep -q -- '--wipe-slot=tpm2' "$enroll_helper" &&
   grep -q 'remove_install_passphrase_slots' "$enroll_helper" &&
   grep -q 'temporary installer passphrase is already absent' "$enroll_helper" &&
   grep -q 'interrupted enrollment recovery requires the existing recovery passphrase' "$enroll_helper" &&
   grep -q '^: "\${INSTALL_PASSPHRASE_FILE:?INSTALL_PASSPHRASE_FILE must be configured}"$' "$enroll_helper" &&
   grep -q 'rm -f "$INSTALL_PASSPHRASE_FILE"' "$enroll_helper" &&
   grep -q 'install -d -m 0755.*FILE_CRYPTO_PENDING' "$late_crypto" &&
   grep -q 'pending_user=$(cat "$pending_file")' "$enroll_launcher" &&
   grep -q '\[ "$(id -un)" = "$pending_user" \]' "$enroll_launcher" &&
   grep -q 'pending_user=$(cat "$pending_file")' "$enroll_prompt" &&
   grep -q '^crypto_verify_initramfs() {$' "$late_crypto" &&
   grep -q '^crypto_verify_initramfs$' "$late_crypto" &&
   grep -q 'root-contained /home key leaked' "$late_crypto" &&
   grep -q 'installer passphrase file leaked' "$late_crypto"; then
  pass "post-login enrollment prompts for recovery and PIN, verifies TPM2+PIN, and removes bootstrap-key access"
else
  fail "post-login enrollment prompts for recovery and PIN, verifies TPM2+PIN, and removes bootstrap-key access" "$enroll_helper"
fi

addon_readme="$ROOT_DIR/d-i/forky/classes/class-addon/README.md"
if grep -q '^`crypto.cfg` encrypts both `/` and `/home`' "$addon_readme" &&
   grep -q 'native `partman-crypto` flow' "$addon_readme" &&
   grep -q 'random bootstrap passphrase' "$addon_readme" &&
   grep -q 'creates AES-XTS LUKS2 containers' "$addon_readme" &&
   grep -q '20 characters' "$addon_readme" &&
   grep -q 'TPM2 PIN and confirmation' "$addon_readme" &&
   grep -q 'PCR 7+14' "$addon_readme" &&
   grep -q 'TPM2+PIN tokens' "$addon_readme" &&
   grep -q 'boot requests the PIN' "$addon_readme" &&
   grep -q 'recovery passphrase' "$addon_readme"; then
  pass "crypto class documentation records the one-PIN and recovery behavior"
else
  fail "crypto class documentation records the one-PIN and recovery behavior" "$addon_readme"
fi

[ "$FAIL_COUNT" -eq 0 ]
