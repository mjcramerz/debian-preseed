#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/installer-hook-smoke.XXXXXX")
TEST_COUNT=47
TEST_INDEX=0
FAIL_COUNT=0
trap 'rm -rf "$TMP_DIR"' EXIT HUP INT TERM

pass() {
  TEST_INDEX=$((TEST_INDEX + 1))
  printf 'ok %s - %s\n' "$TEST_INDEX" "$1"
}

fail() {
  TEST_INDEX=$((TEST_INDEX + 1))
  FAIL_COUNT=$((FAIL_COUNT + 1))
  printf 'not ok %s - %s\n' "$TEST_INDEX" "$1"
}

render_answers() {
  case_name=$1
  classes=$2
  output_path=$3
  error_path=$4

  runtime_dir="$TMP_DIR/runtime-$case_name"
  cmdline="classes=$classes primary_user=user primary_password=secret root_password=root fruux_username=alice fruux_password=token ip=192.168.50.82 netmask=255.255.255.0 gateway=192.168.50.1 nameservers=192.168.50.1"

  if answers_file=$(
    INSTALLER_RUNTIME_DIR="$runtime_dir" \
    INSTALLER_SOURCE_ROOT="$ROOT_DIR/d-i/forky" \
    INSTALLER_CMDLINE="$cmdline" \
      sh "$ROOT_DIR/d-i/forky/scripts/preseed/answers.sh" render "$ROOT_DIR/d-i/forky" 2>"$error_path"
  ); then
    printf '%s\n' "$answers_file" >"$output_path"
    return 0
  fi

  return 1
}

answers_path() {
  sed -n '1p' "$1"
}

printf '1..%s\n' "$TEST_COUNT"

PATH=/bin
export PATH
# shellcheck disable=SC1090
. "$ROOT_DIR/d-i/forky/scripts/common/hook.sh"

case ":$PATH:" in
  *:/sbin:*:*:/usr/sbin:*|*:/sbin:*|*:/usr/sbin:*)
    pass "installer hook path includes sbin directories"
    ;;
  *)
    fail "installer hook path includes sbin directories"
    ;;
esac

secure_boot_tool="$ROOT_DIR/d-i/forky/hooks/shared/target/usr/libexec/install-tools/secure-boot-tool.tmpl"
if grep -q '^PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin$' "$secure_boot_tool"; then
  pass "secure boot target tool pins a PATH that can resolve sbin and bin toolchain commands"
else
  fail "secure boot target tool pins a PATH that can resolve sbin and bin toolchain commands"
fi

nvme_candidates=$(hook_nvme_install_disk_candidates "/dev/vd* /dev/nvme*n* /dev/sd*")
if [ "$nvme_candidates" = "/dev/nvme*n*" ]; then
  pass "nvme candidate filter excludes virtual and SCSI fallbacks"
else
  fail "nvme candidate filter excludes virtual and SCSI fallbacks"
fi

pci_root="$TMP_DIR/pci"
mkdir -p "$pci_root/0000:00:01.0"
printf '0x144d\n' >"$pci_root/0000:00:01.0/vendor"
printf '0x010802\n' >"$pci_root/0000:00:01.0/class"
if INSTALLER_PCI_DEVICES_ROOT="$pci_root" hook_nvme_controller_present; then
  pass "hook detects NVMe controller from PCI class"
else
  fail "hook detects NVMe controller from PCI class"
fi

early_hook="$ROOT_DIR/d-i/forky/hooks/shared/d-i/early.sh"
common_hook="$ROOT_DIR/d-i/forky/scripts/common/hook.sh"
if grep -q '/usr/lib/pre-pkgsel.d' "$early_hook" &&
   ! grep -q 'early_stage_critical_retriever_compat' "$early_hook" &&
   grep -q 'installer_repo_join_var DIR_HOOKS_SHARED_APT_SETUP_GENERATORS generators/99-apt-preferences' "$early_hook" &&
   grep -q 'installer_repo_join_var DIR_HOOKS_SHARED_APT_SETUP_GENERATORS generators/98-cuda-legacy-source' "$early_hook" &&
   grep -q 'installer_repo_join_var DIR_HOOKS_SHARED_BASE_STAGE_D 20-fstab-guard' "$early_hook" &&
   grep -q 'installer_repo_join_var DIR_HOOKS_SHARED_PRE_PKGSEL_D 88temporary-os-prober.sh' "$early_hook" &&
   grep -q 'installer_repo_join_var DIR_HOOKS_SHARED_PRE_PKGSEL_D 89temporary-unshare.sh' "$early_hook" &&
   grep -q 'installer_repo_join_var DIR_HOOKS_SHARED_PRE_PKGSEL_D 90secure-boot-dkms.sh' "$early_hook" &&
   grep -q 'installer_repo_join_var DIR_HOOKS_SHARED_PRE_PKGSEL_D 91cuda-legacy-apt.sh' "$early_hook" &&
   grep -q 'installer_repo_join_var DIR_HOOKS_SHARED_PRE_PKGSEL_D 92nvidia-legacy-dkms.sh' "$early_hook" &&
   grep -q 'installer_repo_join_var DIR_HOOKS_SHARED_FINISH_INSTALL_D 99-normalize-finish' "$early_hook" &&
   grep -q 'chmod 0755 /usr/lib/finish-install.d/95-normalize-apt /usr/lib/finish-install.d/99-normalize-finish' "$early_hook" &&
   grep -q '/usr/lib/pre-pkgsel.d/88temporary-os-prober' "$early_hook" &&
   grep -q '/usr/lib/pre-pkgsel.d/89temporary-unshare' "$early_hook" &&
   grep -q '/usr/lib/pre-pkgsel.d/90secure-boot-dkms' "$early_hook" &&
   grep -q '/usr/lib/pre-pkgsel.d/91cuda-legacy-apt' "$early_hook" &&
   grep -q '/usr/lib/pre-pkgsel.d/92nvidia-legacy-dkms' "$early_hook" &&
   ! grep -q 'installer_repo_join_var DIR_HOOKS_SHARED_FINISH_INSTALL_D 10clock-setup' "$early_hook" &&
   ! grep -q 'installer_repo_join_var DIR_HOOKS_SHARED_FINISH_INSTALL_D 20final-message' "$early_hook" &&
   ! grep -q '/usr/lib/finish-install.d/10clock-setup' "$early_hook" &&
   ! grep -q '/usr/lib/finish-install.d/20final-message' "$early_hook" &&
   ! grep -q '93qemu-securityfs' "$early_hook" &&
   ! grep -q '/usr/lib/post-base-installer.d' "$early_hook" &&
   ! grep -q 'hooks/shared/post-base-installer.d/99secure-boot-stage.sh' "$early_hook"; then
  pass "early installer hook keeps shared finish-install extras without overriding stock clock or final-message hooks"
else
  fail "early installer hook keeps shared finish-install extras without overriding stock clock or final-message hooks"
fi

temporary_os_prober_hook="$ROOT_DIR/d-i/forky/hooks/shared/pre-pkgsel.d/88temporary-os-prober.sh"
normalize_finish_hook="$ROOT_DIR/d-i/forky/hooks/shared/finish-install.d/99-normalize-finish"
dualboot_class="$ROOT_DIR/d-i/forky/classes/class-addon/dualboot.cfg"
if sh -n "$temporary_os_prober_hook" &&
   grep -q '^OS_PROBER_REAL_PATH=/usr/bin/os-prober.installer-real$' "$temporary_os_prober_hook" &&
   grep -q '^OS_PROBER_STATE_PATH=/var/lib/installer-state/temporary-os-prober-shim$' "$temporary_os_prober_hook" &&
   grep -q '^OS_PROBER_MARKER=INSTALLER_TEMPORARY_FAKE_OS_PROBER_V1$' "$temporary_os_prober_hook" &&
   grep -q 'installer_selected_class_reference_is_selected addon/dualboot' "$temporary_os_prober_hook" &&
   grep -q 'hook_ensure_installer_command os-prober os-prober-udeb' "$early_hook" &&
   grep -q 'target os-prober remains unchanged' "$temporary_os_prober_hook" &&
   ! grep -q '/target/usr/bin/os-prober' "$temporary_os_prober_hook" &&
   grep -q '^restore_temporary_installer_os_prober() {$' "$normalize_finish_hook" &&
   grep -q '^restore_temporary_installer_os_prober$' "$normalize_finish_hook" &&
   grep -q '^d-i grub-installer/enable_os_prober_otheros_yes boolean false$' "$dualboot_class" &&
   grep -q '^d-i grub-installer/enable_os_prober_otheros_no boolean false$' "$dualboot_class" &&
   grep -q '^grub2 grub2/enable_os_prober boolean false$' "$dualboot_class"; then
  pass "dualboot defers os-prober from Debian Installer to the controlled target-side late GRUB pass"
else
  fail "dualboot defers os-prober from Debian Installer to the controlled target-side late GRUB pass"
fi

grub_helper="$ROOT_DIR/d-i/forky/scripts/late/grub.sh"
if grep -q 'update GRUB configuration with unrelated USB storage hidden from os-prober' "$grub_helper" &&
   grep -q '/usr/bin/unshare.installer-real --mount /bin/sh -eu -c' "$grub_helper" &&
   grep -q 'install_disk_path=$(readlink -f "\$DEV_INSTALL_DISK"' "$grub_helper" &&
   grep -q '^mount --make-rprivate /$' "$grub_helper" &&
   grep -q '\*/usb\*)' "$grub_helper" &&
   grep -q 'mount --bind "\$empty_sys_block" "\$sys_block"' "$grub_helper" &&
   grep -q '\[ "\$block_name" = "\$install_disk_name" \] && continue' "$grub_helper"; then
  pass "controlled dualboot os-prober keeps the install disk visible while hiding unrelated USB storage"
else
  fail "controlled dualboot os-prober keeps the install disk visible while hiding unrelated USB storage"
fi

temporary_unshare_hook="$ROOT_DIR/d-i/forky/hooks/shared/pre-pkgsel.d/89temporary-unshare.sh"
if sh -n "$temporary_unshare_hook" &&
   grep -q '^UNSHARE_DIVERT_PATH=/usr/bin/unshare.installer-real$' "$temporary_unshare_hook" &&
   grep -q '^UNSHARE_STATE_PATH=/var/lib/installer-state/temporary-unshare-shim$' "$temporary_unshare_hook" &&
   grep -q '^UNSHARE_MARKER=INSTALLER_TEMPORARY_FAKE_UNSHARE_V1$' "$temporary_unshare_hook" &&
   grep -q -- '--divert "\$UNSHARE_DIVERT_PATH"' "$temporary_unshare_hook" &&
   grep -q -- '--add "\$UNSHARE_PATH"' "$temporary_unshare_hook" &&
   grep -q '^exit 0$' "$temporary_unshare_hook" &&
   grep -q '^restore_temporary_unshare() {$' "$ROOT_DIR/d-i/forky/hooks/shared/finish-install.d/99-normalize-finish" &&
   grep -q '^restore_temporary_unshare$' "$ROOT_DIR/d-i/forky/hooks/shared/finish-install.d/99-normalize-finish"; then
  pass "installer stages a temporary unshare diversion and restores the real binary during final normalization"
else
  fail "installer stages a temporary unshare diversion and restores the real binary during final normalization"
fi

f2fs_partman_early="$ROOT_DIR/d-i/forky/hooks/shared/partman/f2fs-early.sh"
common_cfg="$ROOT_DIR/d-i/forky/common.cfg"
if grep -q 'hook_anna_install_optional "f2fs-modules-${kernel_release}-di" || true' "$early_hook" &&
   grep -q 'hook_anna_install_optional f2fs-modules || true' "$early_hook" &&
   grep -q 'hook_preload_installer_udeb f2fs-tools-udeb || true' "$early_hook" &&
   grep -q '^ensure_f2fs_kernel_support() {$' "$f2fs_partman_early" &&
   grep -q 'f2fs-modules-${kernel_release}-di' "$f2fs_partman_early" &&
   grep -q 'hook_anna_install_optional f2fs-modules' "$f2fs_partman_early" &&
   grep -q 'unable to load the Debian Installer F2FS kernel module' "$f2fs_partman_early" &&
   grep -q '^ensure_f2fs_kernel_support$' "$f2fs_partman_early" &&
   grep -Eq '^d-i anna/choose_modules multiselect .* f2fs-modules f2fs-tools-udeb( |$)' "$common_cfg" &&
   grep -q 'hook_ensure_installer_udeb f2fs-tools-udeb' "$f2fs_partman_early" &&
   ! grep -q 'hook_preload_installer_udeb f2fs-tools-udeb || true' "$f2fs_partman_early"; then
  pass "f2fs installer flow preloads and verifies matching kernel support before partman recipes are applied"
else
  fail "f2fs installer flow preloads and verifies matching kernel support before partman recipes are applied"
fi

partman_early_common="$ROOT_DIR/d-i/forky/hooks/shared/partman/early.sh"
btrfs_partman_early="$ROOT_DIR/d-i/forky/hooks/shared/partman/btrfs-early.sh"
if grep -q '^partman_early_sanitize_install_disk() {$' "$partman_early_common" &&
   grep -q 'hook_preload_installer_command blkid util-linux-udeb || true' "$common_hook" &&
   ! grep -q 'hook_.*installer_.*wipefs .*udeb' "$common_hook" &&
   grep -q '^partman_early_clear_signatures() {$' "$partman_early_common" &&
   ! grep -q 'partman_early_require_command wipefs' "$partman_early_common" &&
   grep -q 'wipefs is not shipped in the Debian Installer udebs' "$partman_early_common" &&
   grep -q 'install disk is not a block device' "$partman_early_common" &&
   grep -q '^  disk_discarded=false$' "$partman_early_common" &&
   grep -q 'blkdiscard -f "\$disk"' "$partman_early_common" &&
   grep -q 'partman_early_clear_signatures "\$dev"' "$partman_early_common" &&
   grep -q 'partman_early_clear_signatures "\$disk"' "$partman_early_common" &&
   ! grep -q '^.*dd if=.*$' "$partman_early_common" &&
   grep -q 'partman_early_sanitize_install_disk "\$DEV_DISK_BLOCK"' "$btrfs_partman_early" &&
   grep -q 'partman_early_sanitize_install_disk "\$DEV_INSTALL_DISK"' "$f2fs_partman_early" &&
   ! grep -q '^.*dd if=.*$' "$btrfs_partman_early" &&
   ! grep -q '^.*dd if=.*$' "$f2fs_partman_early"; then
  pass "full-disk partitioning uses discard first and falls back to installer-native GPT cleanup without requiring wipefs"
else
  fail "full-disk partitioning uses discard first and falls back to installer-native GPT cleanup without requiring wipefs"
fi

if (
  no_wipefs_bin="$TMP_DIR/no-wipefs-bin"
  no_wipefs_log="$TMP_DIR/no-wipefs.log"
  saved_path=$PATH
  mkdir -p "$no_wipefs_bin"
  installer_warn() {
    printf 'warn:%s\n' "$*" >>"$no_wipefs_log"
  }
  installer_fatal() {
    printf 'fatal:%s\n' "$*" >>"$no_wipefs_log"
    return 1
  }
  PATH=$no_wipefs_bin
  . "$partman_early_common"
  partman_early_clear_signatures /dev/test-no-wipefs
  PATH=$saved_path
  grep -q 'wipefs is not shipped in the Debian Installer udebs' "$no_wipefs_log"
) && (
  failing_wipefs_bin="$TMP_DIR/failing-wipefs-bin"
  failing_wipefs_log="$TMP_DIR/failing-wipefs.log"
  saved_path=$PATH
  mkdir -p "$failing_wipefs_bin"
  cat >"$failing_wipefs_bin/wipefs" <<'EOF'
#!/bin/sh
exit 1
EOF
  chmod 0755 "$failing_wipefs_bin/wipefs"
  installer_warn() {
    printf 'warn:%s\n' "$*" >>"$failing_wipefs_log"
  }
  installer_fatal() {
    printf 'fatal:%s\n' "$*" >>"$failing_wipefs_log"
    return 1
  }
  PATH=$failing_wipefs_bin
  . "$partman_early_common"
  if partman_early_clear_signatures /dev/test-failing-wipefs; then
    exit 1
  fi
  PATH=$saved_path
  grep -q 'failed to clear storage signatures from /dev/test-failing-wipefs' "$failing_wipefs_log"
); then
  pass "partman signature cleanup tolerates an unavailable wipefs but fails when an available wipefs reports an error"
else
  fail "partman signature cleanup tolerates an unavailable wipefs but fails when an available wipefs reports an error"
fi

if grep -q '\[ "\$slot" -ge "\$RUNTIME_DEBIAN_START_SLOT" \] || continue' "$btrfs_partman_early" &&
   grep -q '\[ "\$slot" -ge "\$RUNTIME_DEBIAN_START_SLOT" \] || continue' "$f2fs_partman_early" &&
   grep -Fq "printf '%s %s %s\\n' \"\$slot\" \"\$part_id\" \"\$path\"" "$btrfs_partman_early" &&
   grep -Fq "printf '%s %s %s\\n' \"\$slot\" \"\$part_id\" \"\$path\"" "$f2fs_partman_early" &&
   grep -q 'blkdiscard -f "\$part_path"' "$btrfs_partman_early" &&
   grep -q 'blkdiscard -f "\$part_path"' "$f2fs_partman_early" &&
   grep -q 'wipefs -a -f "\$part_path"' "$btrfs_partman_early" &&
   grep -q 'wipefs -a -f "\$part_path"' "$f2fs_partman_early" &&
   grep -q 'wipefs is unavailable in Debian Installer; continuing with validated partman deletion' "$btrfs_partman_early" &&
   grep -q 'wipefs is unavailable in Debian Installer; continuing with validated partman deletion' "$f2fs_partman_early" &&
   ! grep -q 'wipefs is required before deleting Debian-owned partitions' "$btrfs_partman_early" &&
   ! grep -q 'wipefs is required before deleting Debian-owned partitions' "$f2fs_partman_early" &&
   grep -q 'cleared and removed Debian-owned slot' "$btrfs_partman_early" &&
   grep -q 'cleared and removed Debian-owned slot' "$f2fs_partman_early"; then
  pass "dual-boot discards or optionally wipes only Debian-owned slots before validated deletion"
else
  fail "dual-boot discards or optionally wipes only Debian-owned slots before validated deletion"
fi

f2fs_runtime="$ROOT_DIR/d-i/forky/scripts/runtime/f2fs.sh"
f2fs_layout_finish="$ROOT_DIR/d-i/forky/hooks/shared/partman/finish.d/99-storage-layout.sh"
f2fs_layout_env="$ROOT_DIR/d-i/forky/hosts/shared/layout-f2fs.env"
f2fs_valid="$ROOT_DIR/d-i/forky/hooks/shared/partman/f2fs-backend/valid_filesystems/f2fs"
f2fs_mountoptions="$ROOT_DIR/d-i/forky/hooks/shared/partman/f2fs-backend/mountoptions/f2fs"
f2fs_mount="$ROOT_DIR/d-i/forky/hooks/shared/partman/f2fs-backend/mount.d/f2fs"
f2fs_fstab="$ROOT_DIR/d-i/forky/hooks/shared/partman/f2fs-backend/fstab.d/f2fs"
f2fs_init="$ROOT_DIR/d-i/forky/hooks/shared/partman/f2fs-backend/init.d/kernelmodules_f2fs"
f2fs_check="$ROOT_DIR/d-i/forky/hooks/shared/partman/f2fs-backend/check.d/nomountpoint_f2fs"
f2fs_commit="$ROOT_DIR/d-i/forky/hooks/shared/partman/f2fs-backend/commit.d/format_f2fs"
if sh -n "$f2fs_valid" &&
   sh -n "$f2fs_mount" &&
   sh -n "$f2fs_fstab" &&
   sh -n "$f2fs_init" &&
   sh -n "$f2fs_check" &&
   sh -n "$f2fs_commit" &&
   grep -qx 'relatime' "$f2fs_mountoptions" &&
   grep -qx 'nodev' "$f2fs_mountoptions" &&
   grep -qx 'nosuid' "$f2fs_mountoptions" &&
   grep -q 'install_partman_f2fs_backend' "$f2fs_partman_early" &&
   grep -q 'hooks/shared/partman/f2fs-backend/mountoptions/f2fs' "$f2fs_partman_early" &&
   grep -q 'install -m 0644 .* /lib/partman/mountoptions/f2fs' "$f2fs_partman_early" &&
   grep -q 'hooks/shared/partman/f2fs-backend/commit.d/format_f2fs' "$f2fs_partman_early" &&
   grep -q '^rm -f /var/lib/partman/f2fs$' "$f2fs_init" &&
   grep -q 'grep -qw f2fs /proc/filesystems' "$f2fs_init" &&
   grep -q 'mkfs.f2fs -f' "$f2fs_commit" &&
   grep -q 'mount -t f2fs' "$f2fs_mount" &&
   grep -q '^    \${DEV_PART_ROOT_MB} \${DEV_PART_ROOT_MB} \${DEV_PART_ROOT_MB} ext4$' "$f2fs_runtime" &&
   grep -q '^    \${DEV_PART_ROOT_MB} \${DEV_PART_ROOT_MB} \${DEV_PART_ROOT_MB} ext4$' "$f2fs_runtime" &&
   [ "$(grep -c '^        use_filesystem{ } filesystem{ f2fs }$' "$f2fs_runtime")" -ge 2 ] &&
   grep -q '^        mountpoint{ / }$' "$f2fs_runtime" &&
   grep -q '^    \${DEV_PART_HOME_MB} \${DEV_PART_HOME_MB} \${DEV_PART_HOME_MB} ext4$' "$f2fs_runtime" &&
   grep -q '^        mountpoint{ /home }$' "$f2fs_runtime" &&
   grep -q '^    printf '\''d-i partman/default_filesystem string ext4\\n'\''$' "$f2fs_runtime" &&
   grep -q '^MNT_F2FS_INSTALLER_ROOT_OPTS="${MNT_F2FS_BOOT_BASE}"$' "$f2fs_layout_env" &&
   grep -q '^MNT_F2FS_BASE="${MNT_F2FS_BOOT_BASE},background_gc=on,gc_merge,atgc,extent_cache,age_extent_cache,checkpoint_merge"$' "$f2fs_layout_env" &&
   grep -q '^MNT_F2FS_COMPRESS_OPTS=.*compress_cache' "$f2fs_layout_env" &&
   grep -q '^MNT_F2FS_ROOT_OPTS="${MNT_F2FS_BASE},${MNT_F2FS_COMPRESS_OPTS}"$' "$f2fs_layout_env" &&
   grep -q '^MNT_F2FS_ROOT_BOOT_OPTS="${MNT_F2FS_ROOT_OPTS}"$' "$f2fs_layout_env" &&
   grep -q '^GRUB_ROOT_FLAGS="rootfstype=f2fs rootwait rootflags=\${MNT_F2FS_ROOT_BOOT_OPTS}"$' "$f2fs_layout_env" &&
   grep -q 'ensure_f2fs_filesystem "\$DEV_PART_ROOT" "\$MKFS_F2FS_ROOT_OPTS" "\$FS_LABEL_ROOT"' "$f2fs_layout_finish" &&
   grep -q 'ensure_f2fs_filesystem "\$DEV_PART_HOME" "\$MKFS_F2FS_HOME_OPTS" "\$FS_LABEL_HOME"' "$f2fs_layout_finish" &&
   grep -q 'mount_block_device "\$DEV_PART_ROOT" "\$TARGET_ROOT" f2fs "\${MNT_F2FS_INSTALLER_ROOT_OPTS:-\$MNT_F2FS_ROOT_OPTS}"' "$f2fs_layout_finish" &&
   grep -q 'mount_block_device "\$DEV_PART_HOME" "\$TARGET_ROOT\$DIR_HOME" f2fs "\${MNT_F2FS_INSTALLER_HOME_OPTS:-\$MNT_F2FS_HOME_OPTS}"' "$f2fs_layout_finish"; then
  pass "f2fs initramfs root flags carry the complete target mount policy"
else
  fail "f2fs initramfs root flags carry the complete target mount policy"
fi

f2fs_raw_block_helper="$TMP_DIR/f2fs-ensure-raw-block-device.sh"
sed -n '/^run_f2fs_storage_layout() {$/,$p' "$f2fs_layout_finish" |
  sed -n '/^ensure_raw_block_device() {$/,/^}$/p' >"$f2fs_raw_block_helper"
if [ "$(grep -c '^ensure_raw_block_device() {$' "$f2fs_layout_finish")" -eq 2 ] &&
   sh -n "$f2fs_raw_block_helper" &&
   grep -q '^  if \[ -n "\$current_type" \]; then$' "$f2fs_raw_block_helper" &&
   ! grep -q '\[ -n "\$current_type" \] && wipe_block_device "\$dev"' "$f2fs_raw_block_helper"; then
  pass "f2fs storage layout defines a set-e-safe local raw-partition helper"
else
  fail "f2fs storage layout defines a set-e-safe local raw-partition helper"
fi

f2fs_live_mount_helper="$TMP_DIR/f2fs-live-mount-options.sh"
sed -n '/^run_f2fs_storage_layout() {$/,$p' "$f2fs_layout_finish" |
  sed -n '/^f2fs_live_mount_options() {$/,/^}$/p' >"$f2fs_live_mount_helper"
if [ "$(
     sh -c '. "$1"; f2fs_live_mount_options "$2"' sh \
       "$f2fs_live_mount_helper" \
       'noatime,nodev,nosuid,noexec,x-systemd.requires-mounts-for=/var/log'
   )" = 'noatime,nodev,nosuid,noexec' ] &&
   grep -q '^  opts=$(f2fs_live_mount_options "\$4")$' "$f2fs_layout_finish" &&
   grep -q 'fstab_entry "\$journal_src" "\$DIR_VAR_LOG_JOURNAL" ext4 "\$MNT_VAR_LOG_JOURNAL_OPTS" 0 2' "$f2fs_layout_finish"; then
  pass "f2fs strips systemd-only options from installer mounts while preserving target fstab policy"
else
  fail "f2fs strips systemd-only options from installer mounts while preserving target fstab policy"
fi

if (
  set -eu
  # shellcheck disable=SC1090
  . "$ROOT_DIR/d-i/forky/scripts/runtime/common.sh"
  DEV_INSTALL_DISK=/dev/mmcblk3
  DEV_PART_PREFIX=
  runtime_derive_part_prefix
  [ "$DEV_PART_PREFIX" = "/dev/mmcblk3p" ]
  [ "$(runtime_partition_path 3)" = "/dev/mmcblk3p3" ]
); then
  pass "runtime partition derivation keeps the p-suffixed eMMC partition paths for mmcblk install disks"
else
  fail "runtime partition derivation keeps the p-suffixed eMMC partition paths for mmcblk install disks"
fi

grub_helper="$ROOT_DIR/d-i/forky/scripts/late/grub.sh"
btrfs_family="$ROOT_DIR/d-i/forky/scripts/late/btrfs-family.sh"
f2fs_family="$ROOT_DIR/d-i/forky/scripts/late/f2fs-family.sh"
prepkgsel_hook="$ROOT_DIR/d-i/forky/hooks/shared/pre-pkgsel.d/90secure-boot-dkms.sh"
cuda_prepkgsel_hook="$ROOT_DIR/d-i/forky/hooks/shared/pre-pkgsel.d/91cuda-legacy-apt.sh"
cuda_apt_setup_generator="$ROOT_DIR/d-i/forky/hooks/shared/apt-setup/generators/98-cuda-legacy-source"
nvidia_legacy_prepkgsel_hook="$ROOT_DIR/d-i/forky/hooks/shared/pre-pkgsel.d/92nvidia-legacy-dkms.sh"
apt_fragment="$ROOT_DIR/d-i/forky/fragments/apt.cfg"
if grep -q '^stage_target_secure_boot_runtime_assets$' "$prepkgsel_hook" &&
   grep -q '^run_installer_secure_boot_install_tool prepare-dkms$' "$prepkgsel_hook" &&
   grep -q '^  render_target_asset .*usr/libexec/install-tools/secure-boot-tool\.tmpl.*"\${FILE_SECURE_BOOT_TOOL}" 0755$' "$grub_helper" &&
   grep -q '^cmd_prepare_dkms() {$' "$ROOT_DIR/d-i/forky/hooks/shared/target/usr/libexec/install-tools/secure-boot-tool.tmpl"; then
  pass "pre-pkgsel Secure Boot hook stages payloads and key material before pkgsel starts DKMS builds"
else
  fail "pre-pkgsel Secure Boot hook stages payloads and key material before pkgsel starts DKMS builds"
fi

if grep -q '^stage_cuda_legacy_source() {$' "$cuda_prepkgsel_hook" &&
   grep -q '^prepare_cuda_legacy_target_apt_dirs() {$' "$cuda_prepkgsel_hook" &&
   grep -q '^refresh_cuda_legacy_target_apt_metadata() {$' "$cuda_prepkgsel_hook" &&
   grep -q 'repair legacy CUDA target apt directories' "$cuda_prepkgsel_hook" &&
   grep -q 'run_in_target "refresh legacy CUDA apt metadata before pkgsel"' "$cuda_prepkgsel_hook" &&
   grep -q 'Dir::Etc::sourcelist="\$cuda_target_sourcelist"' "$cuda_prepkgsel_hook" &&
   grep -q 'Dir::Etc::sourceparts=-' "$cuda_prepkgsel_hook" &&
   grep -q 'installer_copy_path_with_mode "\$source_cache" "\$target_source" 0644 "legacy CUDA apt source"' "$cuda_prepkgsel_hook"; then
  pass "pre-pkgsel legacy CUDA hook restages the keyring and refreshes only the managed CUDA source before pkgsel"
else
  fail "pre-pkgsel legacy CUDA hook restages the keyring and refreshes only the managed CUDA source before pkgsel"
fi

if grep -q 'stage_cuda_legacy_source()' "$cuda_apt_setup_generator" &&
   grep -q 'log "info: staged ${CUDA_SOURCE_REL} before apt-setup metadata refresh"' "$cuda_apt_setup_generator" &&
   grep -q 'installer_cuda_legacy_selected || {' "$cuda_apt_setup_generator" &&
   grep -q 'installer_nvidia_gpu_detected || {' "$cuda_apt_setup_generator" &&
   grep -q "trusted=yes allow-insecure=yes allow-weak=yes signed-by=%s" "$cuda_apt_setup_generator" &&
   ! grep -q '^stage_cuda_legacy_sources_list_block() {$' "$cuda_apt_setup_generator"; then
  pass "apt-setup legacy CUDA generator stages the keyring and source before apt-setup refreshes metadata"
else
  fail "apt-setup legacy CUDA generator stages the keyring and source before apt-setup refreshes metadata"
fi

if grep -q 'dpkg-divert --quiet --local --divert /usr/sbin/dkms.distrib --add /usr/sbin/dkms' "$nvidia_legacy_prepkgsel_hook" &&
   grep -q 'NV_INSTALLER_NVIDIA_LEGACY_OF_GPIO_COMPAT' "$nvidia_legacy_prepkgsel_hook" &&
   grep -q 'patch_nv_linux_header' "$nvidia_legacy_prepkgsel_hook" &&
   grep -q 'patch_legacy_nvidia_source_tree' "$nvidia_legacy_prepkgsel_hook" &&
   grep -q 'verify legacy NVIDIA dkms wrapper' "$nvidia_legacy_prepkgsel_hook"; then
  pass "pre-pkgsel legacy NVIDIA hook diverts dkms and backports NVIDIA's of_gpio compatibility fix before DKMS builds"
else
  fail "pre-pkgsel legacy NVIDIA hook diverts dkms and backports NVIDIA's of_gpio compatibility fix before DKMS builds"
fi

if grep -q '^d-i base-installer/includes string initramfs-tools busybox mokutil openssl shim-signed cryptsetup kmod gzip zstd$' "$apt_fragment"; then
  pass "base-installer includes initramfs-tools so target update-initramfs is available before late boot repair"
else
  fail "base-installer includes initramfs-tools so target update-initramfs is available before late boot repair"
fi

if grep -q 'stage_target_secure_boot_runtime_assets' "$btrfs_family" &&
   grep -q 'reset_target_secure_boot_mok_state' "$btrfs_family"; then
  pass "btrfs late flow owns Secure Boot staging and MOK reset after pkgsel"
else
  fail "btrfs late flow owns Secure Boot staging and MOK reset after pkgsel"
fi

if grep -q 'stage_target_secure_boot_runtime_assets' "$f2fs_family" &&
   grep -q 'reset_target_secure_boot_mok_state' "$f2fs_family"; then
  pass "f2fs late flow owns Secure Boot staging and MOK reset after pkgsel"
else
  fail "f2fs late flow owns Secure Boot staging and MOK reset after pkgsel"
fi

if sh -n "$f2fs_family" &&
   ! grep -qi 'fsck' "$f2fs_family" &&
   grep -q 'stage_target_zram_assets' "$f2fs_family" &&
   grep -q 'write_target_swap_fallback_config' "$f2fs_family" &&
   grep -Fq 'usr/local/libexec/swap-fallback-setup.tmpl' "$f2fs_family" &&
   grep -Fq 'render_target_template "$TMP_ENV_DIR/swap-fallback.service.tmpl"' "$f2fs_family" &&
   grep -q '^enable_target_storage_units$' "$f2fs_family" &&
   grep -q '^validate_swap_fallback_partition() {$' "$ROOT_DIR/d-i/forky/scripts/late/zram-swap.sh" &&
   grep -Fq 'configured_size_mb=${DEV_PART_RAW_SWAP_MB:-}' "$ROOT_DIR/d-i/forky/scripts/late/zram-swap.sh" &&
   ! grep -Eq 'configured_size_mb=[0-9]' "$ROOT_DIR/d-i/forky/scripts/late/zram-swap.sh" &&
   grep -q 'blockdev --getsize64 "\$raw_device"' "$ROOT_DIR/d-i/forky/scripts/late/zram-swap.sh" &&
   grep -q '^Before=zram-setup.service multi-user.target$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/systemd/system/swap-fallback.service.tmpl" &&
   grep -q '^After=local-fs.target systemd-modules-load.service swap-fallback.service swap.target$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/systemd/system/zram-setup.service.tmpl" &&
   grep -q '^Wants=local-fs.target systemd-modules-load.service swap-fallback.service swap.target$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/systemd/system/zram-setup.service.tmpl" &&
   ! grep -Eq 'lsinitramfs|installer-f2fs-initramfs' "$f2fs_family"; then
  pass "f2fs late flow orders custom zram setup after swap startup and before generic swap shutdown without custom fsck payloads"
else
  fail "f2fs late flow orders custom zram setup after swap startup and before generic swap shutdown without custom fsck payloads"
fi

intel_cpu_class="$ROOT_DIR/d-i/forky/classes/class-auto/cpu/intel.cfg"
if grep -Eq '(^|[[:space:]])firmware-intel-graphics([[:space:]]|$)' "$intel_cpu_class" &&
   grep -Eq '(^|[[:space:]])firmware-intel-misc([[:space:]]|$)' "$intel_cpu_class" &&
   grep -Eq '(^|[[:space:]])firmware-intel-sound([[:space:]]|$)' "$intel_cpu_class" &&
   grep -Eq '(^|[[:space:]])firmware-sof-signed([[:space:]]|$)' "$intel_cpu_class" &&
   grep -q 'set_optional_path FILE_MODPROBE_MEI_BLACKLIST false' "$f2fs_family" &&
   ! grep -q 'target_enable_mei_blacklist=true' "$f2fs_family"; then
  pass "f2fs Intel policy keeps MEI/CSE available and installs IPU6 and SOF firmware"
else
  fail "f2fs Intel policy keeps MEI/CSE available and installs IPU6 and SOF firmware"
fi

zram_swap_helper="$ROOT_DIR/d-i/forky/scripts/late/zram-swap.sh"
stable_path_bin="$TMP_DIR/stable-path-bin"
mkdir -p "$stable_path_bin"
cat >"$stable_path_bin/blkid" <<'EOF'
#!/bin/sh
printf '%s\n' 01234567-89ab-cdef-0123-456789abcdef
EOF
chmod 0755 "$stable_path_bin/blkid"
if (
  set -eu
  PATH="$stable_path_bin:/usr/bin:/bin"
  export PATH
  installer_fatal() {
    printf 'fatal: %s\n' "$*" >&2
    exit 1
  }
  # shellcheck disable=SC1090
  . "$zram_swap_helper"
  [ "$(raw_partition_partuuid /dev/mmcblk1p7)" = "01234567-89ab-cdef-0123-456789abcdef" ]
  [ "$(stable_raw_partition_path /dev/mmcblk1p7)" = "/dev/disk/by-partuuid/01234567-89ab-cdef-0123-456789abcdef" ]
) &&
   grep -q 'write_shell_config_var SWAP_FALLBACK_RAW_PARTUUID' "$zram_swap_helper" &&
   grep -q 'SWAP_FALLBACK_RAW_DEVICE=$(stable_raw_partition_path' "$zram_swap_helper" &&
   grep -q 'swap fallback raw device must use its configured PARTUUID path' "$ROOT_DIR/d-i/forky/hooks/shared/target/usr/local/libexec/swap-fallback-setup.tmpl"; then
  pass "swap-fallback persists a PARTUUID path instead of an unstable mmcblk device number"
else
  fail "swap-fallback persists a PARTUUID path instead of an unstable mmcblk device number"
fi

if (
  set -eu
  # shellcheck disable=SC1090
  . "$zram_swap_helper"
  swap_fallback_partition_size_is_acceptable 5991 5991000000 &&
    swap_fallback_partition_size_is_acceptable 5991 5990000000 &&
    swap_fallback_partition_size_is_acceptable 5991 5988902848 &&
    ! swap_fallback_partition_size_is_acceptable 5991 5988902847 &&
    ! swap_fallback_partition_size_is_acceptable invalid 5991000000
); then
  pass "swap-fallback validation permits only bounded partman alignment loss"
else
  fail "swap-fallback validation permits only bounded partman alignment loss"
fi

if grep -q 'sign_target_installed_kernel_modules' "$btrfs_family" &&
   grep -q 'repair_target_installed_kernels' "$btrfs_family" &&
   grep -q '^prepare_target_secure_boot_runtime() {$' "$grub_helper"; then
  pass "btrfs late flow prepares runtime and signs installed modules and kernels after pkgsel"
else
  fail "btrfs late flow prepares runtime and signs installed modules and kernels after pkgsel"
fi

if grep -q 'sync_target_secure_boot_bundle_to_installer_usb()' "$ROOT_DIR/d-i/forky/scripts/late/grub.sh" &&
   grep -q 'installer_usb_efi_device_from_seed_context()' "$ROOT_DIR/d-i/forky/scripts/late/grub.sh" &&
   grep -q 'LC_ALL=C fdisk -l -o Device,Type -- "$parent_disk"' "$ROOT_DIR/d-i/forky/scripts/late/grub.sh"; then
  pass "late GRUB helpers own installer USB EFI discovery and SB_MOK sync"
else
  fail "late GRUB helpers own installer USB EFI discovery and SB_MOK sync"
fi

if grep -q '^ensure_installer_secure_boot_install_tool() {$' "$grub_helper" &&
   grep -q '^reset_target_secure_boot_mok_state_attempt() {$' "$grub_helper" &&
   grep -q 'INSTALLER_SECURE_BOOT_TARGET_ROOT=/target' "$grub_helper" &&
   grep -q 'command -v in-target >/dev/null 2>&1' "$grub_helper" &&
   grep -q 'run_installer_secure_boot_install_tool prepare' "$grub_helper" &&
   grep -q '^reset_target_secure_boot_mok_state() {$' "$grub_helper" &&
   grep -q 'continuing install without a pending MOK reset' "$grub_helper" &&
   ! grep -q 'target_pending_mok_request_exists' "$grub_helper" &&
   ! grep -q 'secure-boot-install\.tmpl' "$grub_helper" &&
   ! grep -q 'secure-boot-install.backend' "$grub_helper"; then
  pass "late Secure Boot flow uses the inlined installer bridge and soft-fails automatic MOK reset"
else
  fail "late Secure Boot flow uses the inlined installer bridge and soft-fails automatic MOK reset"
fi

common_cfg="$ROOT_DIR/d-i/forky/common.cfg"
prod_site_cfg="$ROOT_DIR/d-i/forky/classes/class-select/site/prod.cfg"
if grep -q '^d-i debian-installer/language string en$' "$common_cfg" &&
   grep -q '^d-i debian-installer/language seen true$' "$common_cfg" &&
   grep -q '^d-i debian-installer/country string SE$' "$common_cfg" &&
   grep -q '^d-i debian-installer/country seen true$' "$common_cfg" &&
   grep -q '^d-i debian-installer/locale string en_US.UTF-8$' "$common_cfg" &&
   grep -q '^d-i debian-installer/locale seen true$' "$common_cfg" &&
   grep -q '^d-i localechooser/languagelist select en$' "$common_cfg" &&
   grep -q '^d-i localechooser/languagelist seen true$' "$common_cfg" &&
   grep -q '^d-i localechooser/countrylist/Europe select Sweden$' "$common_cfg" &&
   grep -q '^d-i localechooser/countrylist/Europe seen true$' "$common_cfg" &&
   grep -q '^d-i localechooser/shortlist/sv select Sweden$' "$common_cfg" &&
   grep -q '^d-i localechooser/shortlist/sv seen true$' "$common_cfg" &&
   grep -q '^d-i localechooser/preferred-locale select en_US.UTF-8$' "$common_cfg" &&
   grep -q '^d-i localechooser/preferred-locale seen true$' "$common_cfg" &&
   grep -q '^d-i localechooser/supported-locales multiselect en_US.UTF-8, sv_SE.UTF-8, zh_CN.UTF-8, zh_TW.UTF-8, ja_JP.UTF-8, ko_KR.UTF-8, ru_RU.UTF-8, uk_UA.UTF-8, he_IL.UTF-8, ar_SA.UTF-8, th_TH.UTF-8$' "$common_cfg" &&
   grep -q '^d-i localechooser/supported-locales seen true$' "$common_cfg" &&
   grep -q '^d-i clock-setup/utc boolean true$' "$common_cfg" &&
   grep -q '^d-i clock-setup/utc seen true$' "$common_cfg" &&
   grep -q '^d-i clock-setup/ntp boolean true$' "$common_cfg" &&
   grep -q '^d-i clock-setup/ntp seen true$' "$common_cfg" &&
   ! grep -q '^d-i clock-setup/ntp-server ' "$common_cfg" &&
   ! grep -q '^d-i clock-setup/hwclock-wait ' "$common_cfg" &&
   ! grep -q '^d-i clock-setup/system-time-changed ' "$common_cfg" &&
   ! grep -q '^d-i localechooser/shortlist seen true$' "$common_cfg" &&
   grep -q '^d-i netcfg/get_nameservers string 192.168.50.1$' "$prod_site_cfg" &&
   grep -q '^d-i netcfg/get_nameservers seen true$' "$prod_site_cfg" &&
   ! grep -q '^d-i clock-setup/' "$prod_site_cfg"; then
  pass "shared preseed defaults keep the firmware RTC in UTC while leaving NTP ownership in the static preseed source"
else
  fail "shared preseed defaults keep the firmware RTC in UTC while leaving NTP ownership in the static preseed source"
fi

top_preseed="$ROOT_DIR/d-i/forky/preseed.cfg"
finish_fragment="$ROOT_DIR/d-i/forky/fragments/finish.cfg"
answers_script="$ROOT_DIR/d-i/forky/scripts/preseed/answers.sh"
render_out="$TMP_DIR/render.out"
render_err="$TMP_DIR/render.err"
if grep -q '^d-i grub-installer/bootdev string default$' "$finish_fragment" &&
   grep -q '^d-i grub-installer/bootdev seen true$' "$finish_fragment" &&
   grep -q '^d-i grub-installer/only_debian boolean true$' "$finish_fragment" &&
   grep -q '^d-i grub-installer/only_debian seen true$' "$finish_fragment" &&
   grep -q '^d-i grub-installer/with_other_os boolean false$' "$finish_fragment" &&
   grep -q '^d-i grub-installer/with_other_os seen true$' "$finish_fragment" &&
   grep -q '^d-i grub-installer/enable_os_prober_otheros_yes boolean false$' "$finish_fragment" &&
   grep -q '^d-i grub-installer/enable_os_prober_otheros_yes seen true$' "$finish_fragment" &&
   grep -q '^d-i grub-installer/enable_os_prober_otheros_no boolean false$' "$finish_fragment" &&
   grep -q '^d-i grub-installer/enable_os_prober_otheros_no seen true$' "$finish_fragment" &&
   grep -q '^grub2 grub2/enable_os_prober boolean false$' "$finish_fragment" &&
   grep -q '^grub2 grub2/enable_os_prober seen true$' "$finish_fragment" &&
   grep -q '^d-i debian-installer/exit/halt boolean false$' "$finish_fragment" &&
   grep -q '^d-i debian-installer/exit/halt seen true$' "$finish_fragment" &&
   grep -q '^d-i debian-installer/exit/poweroff boolean false$' "$finish_fragment" &&
   grep -q '^d-i debian-installer/exit/poweroff seen true$' "$finish_fragment" &&
   grep -q '^d-i debian-installer/exit/reboot boolean true$' "$finish_fragment" &&
   grep -q '^d-i debian-installer/exit/reboot seen true$' "$finish_fragment" &&
   grep -q '^d-i finish-install/keep-consoles boolean false$' "$finish_fragment" &&
   grep -q '^d-i finish-install/keep-consoles seen true$' "$finish_fragment" &&
   grep -q '^d-i finish-install/reboot_in_progress note$' "$finish_fragment" &&
   ! grep -q '^d-i finish-install/reboot_in_progress seen true$' "$finish_fragment" &&
   grep -q '^d-i debconf/priority select critical$' "$top_preseed" &&
   grep -q '^d-i debconf/priority seen true$' "$top_preseed" &&
   grep -q '^d-i clock-setup/utc boolean true$' "$top_preseed" &&
   grep -q '^d-i clock-setup/utc seen true$' "$top_preseed" &&
   grep -q '^d-i clock-setup/ntp boolean false$' "$top_preseed" &&
   grep -q '^d-i clock-setup/ntp seen true$' "$top_preseed" &&
   ! grep -q '^d-i clock-setup/ntp-server ' "$top_preseed" &&
   ! grep -q '^d-i clock-setup/hwclock-wait ' "$top_preseed" &&
   ! grep -q '^d-i clock-setup/system-time-changed ' "$top_preseed" &&
   grep -q '^append_runtime_baseline_answers() {$' "$answers_script" &&
   grep -q '^append_preseed_record_with_fallback() {$' "$answers_script" &&
   grep -q 'ensure_cached_preseed_fragment "common.cfg"' "$answers_script" &&
   grep -q 'ensure_cached_preseed_fragment "fragments/finish.cfg"' "$answers_script" &&
   ! grep -q 'append_preseed_record_with_fallback "\$output_file" "time/zone"' "$answers_script" &&
   ! grep -q 'append_preseed_record_with_fallback "\$output_file" "clock-setup/utc"' "$answers_script" &&
   ! grep -q 'append_preseed_record_with_fallback "\$output_file" "clock-setup/ntp"' "$answers_script" &&
   render_answers finish-answers 'prod,desktop,static,standard,software,arch/amd64,cpu/intel,gpu/intel-uhd,disk/nvme' "$render_out" "$render_err"; then
  rendered_answers=$(answers_path "$render_out")
  if grep -q '^d-i debian-installer/language string en$' "$rendered_answers" &&
     grep -q '^d-i debian-installer/language seen true$' "$rendered_answers" &&
     grep -q '^d-i debian-installer/country string SE$' "$rendered_answers" &&
     grep -q '^d-i debian-installer/country seen true$' "$rendered_answers" &&
     grep -q '^d-i debian-installer/locale string en_US.UTF-8$' "$rendered_answers" &&
     grep -q '^d-i debian-installer/locale seen true$' "$rendered_answers" &&
     grep -q '^d-i localechooser/languagelist select en$' "$rendered_answers" &&
     grep -q '^d-i localechooser/languagelist seen true$' "$rendered_answers" &&
     grep -q '^d-i localechooser/countrylist/Europe select Sweden$' "$rendered_answers" &&
     grep -q '^d-i localechooser/countrylist/Europe seen true$' "$rendered_answers" &&
     grep -q '^d-i localechooser/shortlist/sv select Sweden$' "$rendered_answers" &&
     grep -q '^d-i localechooser/shortlist/sv seen true$' "$rendered_answers" &&
     grep -q '^d-i localechooser/preferred-locale select en_US.UTF-8$' "$rendered_answers" &&
     grep -q '^d-i localechooser/preferred-locale seen true$' "$rendered_answers" &&
     grep -q '^d-i localechooser/supported-locales seen true$' "$rendered_answers" &&
     grep -q '^d-i debian-installer/exit/halt boolean false$' "$rendered_answers" &&
     grep -q '^d-i debian-installer/exit/halt seen true$' "$rendered_answers" &&
     grep -q '^d-i debian-installer/exit/poweroff boolean false$' "$rendered_answers" &&
     grep -q '^d-i debian-installer/exit/poweroff seen true$' "$rendered_answers" &&
     grep -q '^d-i debian-installer/exit/reboot boolean true$' "$rendered_answers" &&
     grep -q '^d-i debian-installer/exit/reboot seen true$' "$rendered_answers" &&
     grep -q '^d-i finish-install/keep-consoles boolean false$' "$rendered_answers" &&
     grep -q '^d-i finish-install/keep-consoles seen true$' "$rendered_answers" &&
     grep -q '^d-i finish-install/reboot_in_progress note$' "$rendered_answers" &&
     ! grep -q '^d-i finish-install/reboot_in_progress seen true$' "$rendered_answers" &&
     grep -q '^d-i grub-installer/bootdev string default$' "$rendered_answers" &&
     grep -q '^d-i grub-installer/bootdev seen true$' "$rendered_answers" &&
     grep -q '^d-i grub-installer/enable_os_prober_otheros_yes boolean false$' "$rendered_answers" &&
     grep -q '^d-i grub-installer/enable_os_prober_otheros_no boolean false$' "$rendered_answers" &&
     grep -q '^grub2 grub2/enable_os_prober boolean false$' "$rendered_answers" &&
     ! grep -q '^d-i time/zone ' "$rendered_answers" &&
     ! grep -q '^d-i clock-setup/' "$rendered_answers"; then
    pass "generated runtime answers carry shared locale and finish defaults without re-seeding clock answers"
  else
    fail "generated runtime answers carry shared locale and finish defaults without re-seeding clock answers"
  fi
else
  fail "generated runtime answers carry shared locale and finish defaults without re-seeding clock answers"
fi

if render_answers mirror-suite 'prod,desktop,static,standard,software,arch/amd64,cpu/intel,gpu/intel-uhd,disk/nvme' "$TMP_DIR/mirror-suite.out" "$TMP_DIR/mirror-suite.err"; then
  rendered_answers=$(answers_path "$TMP_DIR/mirror-suite.out")
  if grep -q '^d-i mirror/codename string forky$' "$rendered_answers" &&
     grep -q '^d-i mirror/suite string forky$' "$rendered_answers" &&
     grep -q '^d-i mirror/udeb/suite string forky$' "$rendered_answers" &&
     grep -q '^d-i mirror/suite seen true$' "$rendered_answers" &&
     grep -q '^d-i mirror/https/hostname string deb.debian.org$' "$rendered_answers" &&
     grep -q '^d-i mirror/https/directory string /debian/$' "$rendered_answers" &&
     grep -q '^d-i apt-setup/use_mirror boolean true$' "$rendered_answers" &&
     grep -q '^d-i apt-setup/cdrom/set-first boolean false$' "$rendered_answers" &&
     grep -q '^d-i apt-setup/disable-cdrom-entries boolean true$' "$rendered_answers" &&
     grep -q '^d-i apt-setup/no_mirror boolean false$' "$rendered_answers" &&
     ! grep -q '^d-i apt-setup/local4/repository string https://deb.debian.org/debian forky main contrib non-free non-free-firmware$' "$rendered_answers" &&
     grep -q '^  planned_mirror_suite=forky$' "$answers_script"; then
    pass "forky runtime answers keep the forky suite metadata while choose-mirror continues to own the managed Debian archive"
  else
    fail "forky runtime answers keep the forky suite metadata while choose-mirror continues to own the managed Debian archive"
  fi
else
  fail "forky runtime answers keep the forky suite metadata while choose-mirror continues to own the managed Debian archive"
fi

if render_answers static-dns-fallback 'prod,desktop,static,standard,software,arch/amd64,cpu/intel,gpu/intel-uhd,disk/nvme' "$TMP_DIR/static-dns-fallback.out" "$TMP_DIR/static-dns-fallback.err"; then
  rendered_answers=$(answers_path "$TMP_DIR/static-dns-fallback.out")
  if grep -q '^d-i netcfg/get_gateway string 192.168.50.1$' "$rendered_answers" &&
     grep -q '^d-i netcfg/get_nameservers string 192.168.50.1$' "$rendered_answers"; then
    pass "static installs without explicit nameservers now fall back to the configured gateway for DNS"
  else
    fail "static installs without explicit nameservers now fall back to the configured gateway for DNS"
  fi
else
  fail "static installs without explicit nameservers now fall back to the configured gateway for DNS"
fi

apt_preferences_generator="$ROOT_DIR/d-i/forky/hooks/shared/apt-setup/generators/99-apt-preferences"
apt_preferences_stage_line=$(grep -n '^stage_configured_preferences$' "$apt_preferences_generator" | head -n 1 | cut -d: -f1)
apt_preferences_cdrom_purge_line=$(grep -n '^purge_target_cdrom_apt_sources$' "$apt_preferences_generator" | head -n 1 | cut -d: -f1)
if grep -q '^purge_target_cdrom_apt_sources() {$' "$apt_preferences_generator" &&
   grep -Fq 'index($0, "cdrom:")' "$apt_preferences_generator" &&
   ! grep -Fq 'cdrom://' "$apt_preferences_generator" &&
   [ -n "${apt_preferences_stage_line:-}" ] &&
   [ -n "${apt_preferences_cdrom_purge_line:-}" ] &&
   [ "$apt_preferences_cdrom_purge_line" -gt "$apt_preferences_stage_line" ]; then
  pass "apt-setup removes standard cdrom sources after preference staging and before pkgsel"
else
  fail "apt-setup removes standard cdrom sources after preference staging and before pkgsel"
fi

if ! grep -q '^d-i mirror/codename string ' "$top_preseed" &&
   ! grep -q '^d-i mirror/suite string ' "$top_preseed" &&
   ! grep -q '^d-i mirror/udeb/suite string ' "$top_preseed" &&
   ! grep -q 'seed_installer_debconf_answers' "$apt_preferences_generator" &&
   ! grep -q 'seed_installer_choose_mirror_defaults' "$apt_preferences_generator"; then
  pass "forky keeps mirror suite ownership out of top-level preseed and apt-setup generators"
else
  fail "forky keeps mirror suite ownership out of top-level preseed and apt-setup generators"
fi

if [ ! -e "$ROOT_DIR/d-i/forky/hooks/shared/finish-install.d/20final-message" ]; then
  pass "repository no longer ships a stock final-message finish-install override"
else
  fail "repository no longer ships a stock final-message finish-install override"
fi

clock_finish_runtime_refs=$(
  grep -R -l '/usr/lib/finish-install.d/10clock-setup' \
    "$ROOT_DIR/d-i/forky/hooks" \
    "$ROOT_DIR/d-i/forky/scripts" 2>/dev/null || true
)
if [ ! -e "$ROOT_DIR/d-i/forky/hooks/shared/finish-install.d/10clock-setup" ] &&
   [ -z "$clock_finish_runtime_refs" ]; then
  pass "repository neither ships nor mutates the stock clock-setup finish-install hook"
else
  fail "repository neither ships nor mutates the stock clock-setup finish-install hook"
fi

finish_hook="$ROOT_DIR/d-i/forky/hooks/shared/finish-install.d/99-normalize-finish"
apt_finish_hook="$ROOT_DIR/d-i/forky/hooks/shared/finish-install.d/95-normalize-apt"
qemu_securityfs_hook="$ROOT_DIR/d-i/forky/hooks/shared/pre-pkgsel.d/93qemu-securityfs.sh"
finish_close_line=$(grep -n '^close_secure_boot_luks_state_if_needed$' "$finish_hook" | head -n 1 | cut -d: -f1)
finish_tmpfs_line=$(grep -n '^for tmpfs_var in \\' "$finish_hook" | head -n 1 | cut -d: -f1)
apt_install_line=$(grep -n '^install_default_release_policy$' "$apt_finish_hook" | head -n 1 | cut -d: -f1)
apt_modernize_line=$(grep -n 'apt -y modernize-sources' "$apt_finish_hook" | head -n 1 | cut -d: -f1)
apt_cuda_cleanup_line=$(grep -n '^remove_cuda_legacy_repo_state$' "$apt_finish_hook" | head -n 1 | cut -d: -f1)
if grep -q '^secure_boot_finish_mode() {$' "$finish_hook" &&
   grep -q '^close_secure_boot_luks_state_if_needed() {$' "$finish_hook" &&
   grep -q '^normalize_systemd_unit_tree_permissions() {$' "$finish_hook" &&
   grep -q 'target_path_for /etc/systemd /etc/systemd' "$finish_hook" &&
   grep -q 'umount_mounts_at_or_below "\$secure_boot_target_mount"' "$finish_hook" &&
   grep -q 'cryptsetup close "\$secure_boot_mapper_name"' "$finish_hook" &&
   grep -q '^RUNTIME_LOG_FILE=/tmp/installer.log$' "$finish_hook" &&
   grep -q 'TARGET_LOG_FILE="\${TARGET}/var/lib/installer-state/installer.log"' "$finish_hook" &&
   grep -q 'installer_redact_log_stream <"\$LOG" >"\$target_log_tmp"' "$finish_hook" &&
   [ -n "${finish_close_line:-}" ] &&
   [ -n "${finish_tmpfs_line:-}" ] &&
   [ "$finish_close_line" -lt "$finish_tmpfs_line" ]; then
  pass "finish-install hook closes the Secure Boot LUKS state before final tmpfs normalization"
else
  fail "finish-install hook closes the Secure Boot LUKS state before final tmpfs normalization"
fi

if python3 - "$ROOT_DIR" <<'PY'
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
config_root = root / "d-i/forky/classes/configs"
class_root = root / "d-i/forky/classes"
records = []
for config_name in ("hardware.cfg", "system.cfg", "storage.cfg", "profile.cfg", "addons.cfg", "apps.cfg"):
    current = {}
    for raw_line in (config_root / config_name).read_text(encoding="utf-8").splitlines():
        if not raw_line:
            if current:
                records.append(current)
                current = {}
            continue
        if raw_line.startswith("#"):
            continue
        key, value = raw_line.split(": ", 1)
        current[key] = value
    if current:
        records.append(current)

expected = set()
for record in records:
    group = record["Group"]
    name = record["Name"]
    if group in {"arch", "cpu", "gpu", "disk"}:
        expected.add(class_root / "class-auto" / group / f"{name}.cfg")
    elif group == "profile":
        expected.add(class_root / "class-profile" / f"{name}.cfg")
    elif group == "addon":
        expected.add(class_root / "class-addon" / f"{name}.cfg")
    elif group == "apps":
        expected.add(class_root / "class-apps" / f"{name}.cfg")
    else:
        expected.add(class_root / "class-select" / group / f"{name}.cfg")

missing = sorted(path for path in expected if not path.is_file())
if missing:
    print("\n".join(str(path) for path in missing))
    raise SystemExit(1)
PY
then
  pass "every registered installer class, including per-application classes, has an answer fragment"
else
  fail "every registered installer class, including per-application classes, has an answer fragment"
fi

if grep -q '95-normalize-apt' "$ROOT_DIR/d-i/forky/hooks/shared/d-i/early.sh" &&
   grep -q 'apt -y modernize-sources' "$apt_finish_hook" &&
   grep -q '^DEBIAN_KEYRING=/usr/share/keyrings/debian-archive-keyring.gpg$' "$apt_finish_hook" &&
   grep -q '^CUDA_LEGACY_REPO_URL=https://developer.download.nvidia.com/compute/cuda/repos/debian12/x86_64$' "$apt_finish_hook" &&
   grep -q '^CUDA_LEGACY_REPO_MATCH=\${CUDA_LEGACY_REPO_URL#https://}$' "$apt_finish_hook" &&
   grep -q 'Signed-By: \${DEBIAN_KEYRING}' "$apt_finish_hook" &&
   grep -q '^rewrite_apt_http_to_https() {$' "$apt_finish_hook" &&
   grep -q '^remove_cuda_legacy_repo_state() {$' "$apt_finish_hook" &&
   grep -q '^strip_exact_repo_from_sources_file() {$' "$apt_finish_hook" &&
   grep -q '^CUDA_LEGACY_TARGET_SOURCE_PREFIX="\${SOURCES_DIR}/cuda-legacy-temp"$' "$apt_finish_hook" &&
   grep -q 'for src in "\${CUDA_LEGACY_TARGET_SOURCE_PREFIX}"\.\*; do' "$apt_finish_hook" &&
   grep -q 'rm -f "\$CUDA_LEGACY_TARGET_KEYRING"' "$apt_finish_hook" &&
   grep -q 'removed all staged legacy CUDA Debian 12 source artifacts and keyring state' "$apt_finish_hook" &&
   grep -q "sed 's#http://#https://#g'" "$apt_finish_hook" &&
   grep -q '^server_suite_selected() {$' "$apt_finish_hook" &&
   grep -q '^install_default_release_policy() {$' "$apt_finish_hook" &&
   grep -q '95default-server-suite' "$apt_finish_hook" &&
   grep -q '95default-release-forky' "$apt_finish_hook" &&
   grep -q 'APT::Default-Release "%s";' "$apt_finish_hook" &&
   ! grep -q '\.pending' "$apt_finish_hook" &&
   grep -q 'combine_named_sources cramerz.sources' "$apt_finish_hook" &&
   grep -q 'combine_named_sources crowdsec.sources' "$apt_finish_hook" &&
   grep -q 'merge_backports_into_debian_sources' "$apt_finish_hook" &&
   [ -n "${apt_install_line:-}" ] &&
   [ -n "${apt_modernize_line:-}" ] &&
   [ -n "${apt_cuda_cleanup_line:-}" ] &&
   [ "$apt_cuda_cleanup_line" -lt "$apt_modernize_line" ] &&
   [ "$apt_install_line" -gt "$apt_modernize_line" ]; then
  pass "finish-install normalizes apt sources before installing the managed default-release policy"
else
  fail "finish-install normalizes apt sources before installing the managed default-release policy"
fi

apt_hook_tmp="$TMP_DIR/apt-finish-hook"
apt_hook_target="$apt_hook_tmp/target"
apt_hook_bin="$apt_hook_tmp/bin"
cuda_legacy_url=https://developer.download.nvidia.com/compute/cuda/repos/debian12/x86_64
cuda_legacy_match=${cuda_legacy_url#https://}
mkdir -p "$apt_hook_target/etc/apt/sources.list.d" "$apt_hook_target/etc/apt/keyrings" "$apt_hook_bin"
cat >"$apt_hook_target/etc/apt/sources.list" <<EOF
deb cdrom:[Debian GNU/Linux 13.0.0 _Trixie_ - Official amd64 NETINST] trixie main
deb ${cuda_legacy_url} /
deb https://deb.debian.org/debian forky main
EOF
cat >"$apt_hook_target/etc/apt/sources.list.d/cuda-legacy-temp.sources" <<EOF
Types: deb
URIs: ${cuda_legacy_url}
Suites: /

EOF
cat >"$apt_hook_target/etc/apt/sources.list.d/cuda-legacy-temp.list.bak" <<EOF
deb ${cuda_legacy_url} /
EOF
cat >"$apt_hook_target/etc/apt/sources.list.d/mixed.sources" <<EOF
Types: deb
URIs: cdrom:[Debian GNU/Linux 13.0.0 _Trixie_ - Official amd64 NETINST]
Suites: trixie
Components: main

Types: deb
URIs: ${cuda_legacy_url}
Suites: /

Types: deb
URIs: https://deb.debian.org/debian
Suites: forky
Components: main
EOF
cat >"$apt_hook_target/etc/apt/sources.list.d/mixed.list.bak" <<EOF
deb http://${cuda_legacy_match} /
deb https://deb.debian.org/debian forky main
EOF
cat >"$apt_hook_target/etc/apt/sources.list.d/other-cuda.list" <<'EOF'
deb https://developer.download.nvidia.com/compute/cuda/repos/debian13/x86_64 /
EOF
printf '%s\n' legacy-key >"$apt_hook_target/etc/apt/keyrings/cuda-legacy-archive-key.asc"
cat >"$apt_hook_bin/in-target" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod 0755 "$apt_hook_bin/in-target"
if PATH="$apt_hook_bin:$PATH" \
   INSTALLER_TARGET_DIR="$apt_hook_target" \
   INSTALLER_RUNTIME_DIR="$apt_hook_tmp/runtime" \
   INSTALLER_ASSUME_TARGET_MOUNTED=1 \
   sh "$apt_finish_hook" &&
   grep -q '^APT::Default-Release "forky";$' "$apt_hook_target/etc/apt/apt.conf.d/95default-release-forky" &&
   [ ! -e "$apt_hook_target/etc/apt/apt.conf.d/95default-server-suite" ] &&
   ! find "$apt_hook_target/etc/apt/apt.conf.d" -name '*.pending' -print -quit | grep -q .; then
  pass "finish-install writes the Forky default-release policy directly without pending state"
else
  fail "finish-install writes the Forky default-release policy directly without pending state"
fi

if ! grep -R -F 'cdrom:' "$apt_hook_target/etc/apt" >/dev/null 2>&1; then
  pass "finish-install removes standard cdrom:[...] apt sources before target apt work"
else
  fail "finish-install removes standard cdrom:[...] apt sources before target apt work"
fi

if ! find "$apt_hook_target/etc/apt/sources.list.d" -maxdepth 1 -type f -name 'cuda-legacy-temp.*' -print -quit | grep -q . &&
   [ ! -e "$apt_hook_target/etc/apt/keyrings/cuda-legacy-archive-key.asc" ] &&
   ! grep -R -F "$cuda_legacy_match" "$apt_hook_target/etc/apt" >/dev/null 2>&1 &&
   grep -q '^deb https://deb.debian.org/debian forky main$' "$apt_hook_target/etc/apt/sources.list" &&
   grep -q '^URIs: https://deb.debian.org/debian$' "$apt_hook_target/etc/apt/sources.list.d/mixed.sources" &&
   grep -q '^deb https://deb.debian.org/debian forky main$' "$apt_hook_target/etc/apt/sources.list.d/mixed.list.bak" &&
   grep -q 'debian13/x86_64' "$apt_hook_target/etc/apt/sources.list.d/other-cuda.list"; then
  pass "finish-install removes every legacy CUDA source and archive while preserving unrelated repositories"
else
  fail "finish-install removes every legacy CUDA source and archive while preserving unrelated repositories"
fi

target_common="$ROOT_DIR/d-i/forky/scripts/common/target.sh"
prepkgsel_hook="$ROOT_DIR/d-i/forky/hooks/shared/pre-pkgsel.d/90secure-boot-dkms.sh"
if grep -q '^ensure_target_sys_rbind_mount() {$' "$target_common" &&
   grep -q 'mount --rbind /sys "$target_sys"' "$target_common" &&
   grep -q 'mount --make-rslave "$target_sys"' "$target_common" &&
   ! grep -q '^ensure_target_sys_rbind_mount /target$' "$prepkgsel_hook" &&
   grep -q '^reset_target_secure_boot_mok_state_attempt() {$' "$grub_helper" &&
   grep -q 'mount --rbind /sys "\$target_sys"' "$grub_helper" &&
   grep -q 'mount --make-rslave "\$target_sys"' "$grub_helper" &&
   grep -q 'target /sys/firmware/efi/efivars is unavailable after binding installer /sys into /target; skipping Secure Boot MOK reset' "$grub_helper" &&
   grep -q '^stage_target_secure_boot_runtime_assets$' "$prepkgsel_hook"; then
  pass "Secure Boot reset flow binds installer /sys into /target in the late reset helper, not in pre-pkgsel"
else
  fail "Secure Boot reset flow binds installer /sys into /target in the late reset helper, not in pre-pkgsel"
fi

target_exec_tmp="$TMP_DIR/target-exec"
target_exec_bin="$target_exec_tmp/bin"
target_exec_fallback_bin="$target_exec_tmp/fallback-bin"
target_exec_root="$target_exec_tmp/target"
target_exec_marker="$target_exec_tmp/runner"
mkdir -p "$target_exec_bin" "$target_exec_fallback_bin" "$target_exec_root"
mkdir -p "$target_exec_tmp/runtime"
cat >"$target_exec_bin/in-target" <<'EOF'
#!/bin/sh
pass_stdout=false
if [ "${1:-}" = "--pass-stdout" ]; then
  pass_stdout=true
  shift
fi
stdin_state=closed
if IFS= read -r _stdin_probe; then
  stdin_state=open
fi
printf 'runner=in-target pass_stdout=%s proxy=%s debconf=%s stdin=%s\n' \
  "$pass_stdout" \
  "${http_proxy:-unset}" \
  "${DEBCONF_DB_REPLACE:-unset}" \
  "$stdin_state" >"${TARGET_EXEC_MARKER:?}"
[ "$pass_stdout" = true ] && printf '%s\n' "${TARGET_EXEC_STDOUT:-}"
EOF
cat >"$target_exec_bin/chroot" <<'EOF'
#!/bin/sh
printf 'runner=chroot\n' >"${TARGET_EXEC_MARKER:?}"
EOF
cp "$target_exec_bin/chroot" "$target_exec_fallback_bin/chroot"
chmod 0755 "$target_exec_bin/in-target" "$target_exec_bin/chroot" "$target_exec_fallback_bin/chroot"

target_exec_in_target_line=$(grep -n 'in-target --pass-stdout "\$@"$' "$target_common" | sed -n '1s/:.*//p')
target_exec_chroot_line=$(grep -n '^    chroot "\$target_root" /usr/bin/env -i \\$' "$target_common" | sed -n '1s/:.*//p')
if [ -n "$target_exec_in_target_line" ] &&
   [ -n "$target_exec_chroot_line" ] &&
   [ "$target_exec_in_target_line" -lt "$target_exec_chroot_line" ] &&
   PATH="$target_exec_bin:/bin" \
   TARGET_EXEC_MARKER="$target_exec_marker" \
   INSTALLER_TARGET_DIR=/target \
   INSTALLER_RUNTIME_DIR="$target_exec_tmp/runtime" \
   http_proxy=http://proxy.example:8080 \
   DEBCONF_DB_REPLACE=configdb \
   TARGET_EXEC_STDOUT=amd64 \
     sh -c '. "$1"; . "$2"; installer_fatal() { exit 99; }; captured=$(capture_in_target test-command /usr/bin/dpkg --print-architecture); [ "$captured" = amd64 ]' sh "$ROOT_DIR/d-i/forky/scripts/common/lib.sh" "$target_common" &&
   grep -q '^runner=in-target pass_stdout=true proxy=http://proxy.example:8080 debconf=unset stdin=closed$' "$target_exec_marker" &&
   PATH="$target_exec_fallback_bin:/bin" \
   TARGET_EXEC_MARKER="$target_exec_marker" \
   INSTALLER_TARGET_DIR="$target_exec_root" \
   INSTALLER_RUNTIME_DIR="$target_exec_tmp/runtime" \
     sh -c '. "$1"; . "$2"; installer_fatal() { exit 99; }; target_exec /bin/true' sh "$ROOT_DIR/d-i/forky/scripts/common/lib.sh" "$target_common" &&
   grep -q '^runner=chroot$' "$target_exec_marker" &&
   grep -q '^  target_exec_available || fatal "target command execution is unavailable during ${phase_label}"$' "$ROOT_DIR/d-i/forky/scripts/late/core.sh" &&
   grep -q '^if target_exec_available; then$' "$ROOT_DIR/d-i/forky/scripts/late/btrfs-family.sh" &&
   grep -q '^if target_exec_available; then$' "$ROOT_DIR/d-i/forky/scripts/late/f2fs-family.sh"; then
  pass "late target command execution captures Debian Installer in-target stdout while scrubbing cdebconf env and closing stdin"
else
  fail "late target command execution captures Debian Installer in-target stdout while scrubbing cdebconf env and closing stdin"
fi

secure_boot_conf="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/default/secure-boot.conf.tmpl"
if grep -q '^SECURE_BOOT_MODE=__INSTALLER_SECURE_BOOT_MODE__$' "$secure_boot_conf" &&
   grep -q 'secure_boot_mode=\${SECURE_BOOT_MODE:-}' "$ROOT_DIR/d-i/forky/scripts/runtime/btrfs.sh" &&
   grep -q 'secure_boot_mode=\${SECURE_BOOT_MODE:-}' "$ROOT_DIR/d-i/forky/scripts/runtime/f2fs.sh" &&
   grep -q 'secure_boot_mode=\${SECURE_BOOT_MODE:-}' "$ROOT_DIR/d-i/forky/scripts/late/grub.sh"; then
  pass "Secure Boot mode alias is staged into target config and honored by runtime and late helpers"
else
  fail "Secure Boot mode alias is staged into target config and honored by runtime and late helpers"
fi

[ "$FAIL_COUNT" -eq 0 ]
