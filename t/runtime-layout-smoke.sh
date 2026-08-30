#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/runtime-layout-smoke.XXXXXX")
trap 'rm -rf "$TMP_DIR"' EXIT HUP INT TERM

TEST_COUNT=20
TEST_INDEX=0

pass() {
  TEST_INDEX=$((TEST_INDEX + 1))
  printf 'ok %s - %s\n' "$TEST_INDEX" "$1"
}

fail() {
  TEST_INDEX=$((TEST_INDEX + 1))
  printf 'not ok %s - %s\n' "$TEST_INDEX" "$1"
  if [ "$#" -gt 1 ] && [ -n "${2:-}" ] && [ -r "$2" ]; then
    sed 's/^/# /' "$2"
  fi
}

profile_layout_family() {
  case "$1" in
    btrfs|vm) printf 'btrfs\n' ;;
    f2fs) printf 'f2fs\n' ;;
    *) return 1 ;;
  esac
}

profile_runtime_script() {
  case "$1" in
    btrfs|vm) printf '%s\n' "$ROOT_DIR/d-i/forky/scripts/runtime/btrfs.sh" ;;
    f2fs) printf '%s\n' "$ROOT_DIR/d-i/forky/scripts/runtime/f2fs.sh" ;;
    *) return 1 ;;
  esac
}

compose_host_env() {
  profile_family=$1
  profile_variant=$2
  host_env_path=$3

  set -- \
    "$ROOT_DIR/d-i/forky/hosts/profiles/${profile_family}/${profile_variant}.env" \
    "$ROOT_DIR/d-i/forky/hosts/shared/identity.env" \
    "$ROOT_DIR/d-i/forky/hosts/shared/runtime.env"
  if [ "$profile_variant" = server ]; then
    set -- "$@" "$ROOT_DIR/d-i/forky/hosts/shared/server.env"
  fi
  set -- "$@" \
    "$ROOT_DIR/d-i/forky/hosts/shared/layout.env" \
    "$ROOT_DIR/d-i/forky/hosts/shared/layout-$(profile_layout_family "$profile_family").env" \
    "$ROOT_DIR/d-i/forky/hosts/shared/boot.env"
  cat "$@" >"$host_env_path"
}

run_runtime_case() {
  profile_family=$1
  profile_variant=$2
  disk_mb=$3
  ram_mib=$4
  output_path=$5
  error_path=$6

  host_env_path="$TMP_DIR/${profile_family}-${profile_variant}.env"
  compose_host_env "$profile_family" "$profile_variant" "$host_env_path"
  runtime_script_path=$(profile_runtime_script "$profile_family")

  if (
    set -eu
    . "$host_env_path"
    RUNTIME_COMMON_LIB="$ROOT_DIR/d-i/forky/scripts/runtime/common.sh"
    export RUNTIME_COMMON_LIB
    . "$ROOT_DIR/d-i/forky/scripts/runtime/common.sh"
    . "$runtime_script_path"
    DEV_INSTALL_DISK=/dev/fake
    DEV_PART_PREFIX=/dev/fakep
    INSTALLER_CMDLINE=
    RUNTIME_INSTALL_DISK_MB_OVERRIDE=$disk_mb
    RUNTIME_MEMTOTAL_MIB_OVERRIDE=$ram_mib
    installer_resolve_install_target_defaults() { :; }
    runtime_partition_path() { printf '%s%s\n' "$DEV_PART_PREFIX" "$1"; }
    runtime_ensure_system_identity() {
      SYSTEM_PREFIX=deb
      SYSTEM_HOSTNAME=deb-test
      SYSTEM_DOMAIN=example.test
    }
    runtime_apply_layout_from_cmdline
    runtime_compute_layout_sizing
    printf 'raw_swap_partition=%s\n' "$DEV_PART_RAW_SWAP_MB"
    printf 'raw_zram_partition=%s\n' "$DEV_PART_RAW_ZRAM_MB"
    printf 'usable=%s\n' "$RUNTIME_USABLE_BUDGET_MB"
    printf 'base=%s\n' "${RUNTIME_BASE_LAYOUT_MB:-}"
  ) >"$output_path" 2>"$error_path"; then
    return 0
  fi

  return 1
}

run_f2fs_override_runtime_case() {
  profile_name=$1
  disk_mb=$2
  ram_mib=$3
  output_path=$4
  error_path=$5
  host_env_path="$TMP_DIR/${profile_name}.env"
  recipe_path="$TMP_DIR/${profile_name}.recipe"

  cat \
    "$ROOT_DIR/d-i/forky/hosts/profiles/override/${profile_name}.env" \
    "$ROOT_DIR/d-i/forky/hosts/shared/identity.env" \
    "$ROOT_DIR/d-i/forky/hosts/shared/runtime.env" \
    "$ROOT_DIR/d-i/forky/hosts/shared/layout.env" \
    "$ROOT_DIR/d-i/forky/hosts/shared/layout-f2fs.env" \
    "$ROOT_DIR/d-i/forky/hosts/shared/boot.env" >"$host_env_path"

  if (
    set -eu
    . "$host_env_path"
    RUNTIME_COMMON_LIB="$ROOT_DIR/d-i/forky/scripts/runtime/common.sh"
    export RUNTIME_COMMON_LIB
    . "$ROOT_DIR/d-i/forky/scripts/runtime/common.sh"
    . "$ROOT_DIR/d-i/forky/scripts/runtime/f2fs.sh"
    DEV_INSTALL_DISK=/dev/fake
    DEV_PART_PREFIX=/dev/fakep
    INSTALLER_CMDLINE=
    RUNTIME_INSTALL_DISK_MB_OVERRIDE=$disk_mb
    RUNTIME_MEMTOTAL_MIB_OVERRIDE=$ram_mib
    installer_resolve_install_target_defaults() { :; }
    runtime_partition_path() { printf '%s%s\n' "$DEV_PART_PREFIX" "$1"; }
    runtime_ensure_system_identity() {
      SYSTEM_PREFIX=deb
      SYSTEM_HOSTNAME=deb-test
      SYSTEM_DOMAIN=example.test
    }
    runtime_write_expert_recipe "$recipe_path"
    printf 'root_partition=%s\n' "$DEV_PART_ROOT_MB"
    printf 'raw_swap_partition=%s\n' "$DEV_PART_RAW_SWAP_MB"
    printf 'raw_swap_slot=%s\n' "$RUNTIME_RAW_SWAP_SLOT"
    printf 'raw_swap_device=%s\n' "$DEV_PART_RAW_SWAP"
    printf 'raw_zram_partition=%s\n' "$DEV_PART_RAW_ZRAM_MB"
    printf 'usable=%s\n' "$RUNTIME_USABLE_BUDGET_MB"
    printf 'recipe_partition_count=%s\n' "$(
      awk '/^[[:space:]]+[0-9]+[[:space:]]+[0-9]+[[:space:]]+[0-9]+[[:space:]]+/ { count++ } END { print count + 0 }' "$recipe_path"
    )"
    printf 'recipe_raw_swap_index=%s\n' "$(
      awk -v expected_size="$DEV_PART_RAW_SWAP_MB" '
        /^[[:space:]]+[0-9]+[[:space:]]+[0-9]+[[:space:]]+[0-9]+[[:space:]]+/ {
          count++
          if ($1 == expected_size && $2 == expected_size && $3 == expected_size && $4 == "free") {
            raw_swap_index = count
          }
        }
        END { print raw_swap_index + 0 }
      ' "$recipe_path"
    )"
  ) >"$output_path" 2>"$error_path"; then
    return 0
  fi

  return 1
}

run_assignment_case() {
  profile_family=$1
  profile_variant=$2
  test_cmdline=$3
  output_path=$4
  error_path=$5
  report_mode=${6:-none}

  host_env_path="$TMP_DIR/${profile_family}-assignment.env"
  compose_host_env "$profile_family" "$profile_variant" "$host_env_path"
  runtime_script_path=$(profile_runtime_script "$profile_family")

  if (
    set -eu
    . "$host_env_path"
    RUNTIME_COMMON_LIB="$ROOT_DIR/d-i/forky/scripts/runtime/common.sh"
    export RUNTIME_COMMON_LIB
    . "$ROOT_DIR/d-i/forky/scripts/runtime/common.sh"
    . "$runtime_script_path"
    DEV_INSTALL_DISK=/dev/fake
    DEV_PART_PREFIX=/dev/fakep
    INSTALLER_CMDLINE=$test_cmdline
    installer_resolve_install_target_defaults() { :; }
    runtime_partition_path() { printf '%s%s\n' "$DEV_PART_PREFIX" "$1"; }
    runtime_apply_layout_from_cmdline
    case "$report_mode" in
      dualboot-summary)
        printf 'dualboot_enabled=%s\n' "$DUALBOOT_ENABLED"
        printf 'efi_slot=%s\n' "$RUNTIME_EFI_SLOT"
        printf 'boot_slot=%s\n' "$RUNTIME_BOOT_SLOT"
        printf 'preserved_slots=%s\n' "${RUNTIME_PRESERVED_SLOTS:-}"
        ;;
      qemu-pool-summary)
        RUNTIME_INSTALL_DISK_MB_OVERRIDE=98304
        RUNTIME_MEMTOTAL_MIB_OVERRIDE=16384
        runtime_compute_layout_sizing
        printf 'qemu_pool_enabled=%s\n' "${F2FS_QEMU_POOL_ENABLED:-false}"
        printf 'pool_slot=%s\n' "${RUNTIME_POOL_SLOT:-}"
        printf 'pool_device=%s\n' "${DEV_PART_POOL:-}"
        printf 'pool_mb=%s\n' "${DEV_PART_POOL_MB:-0}"
        ;;
      none) ;;
      *)
        printf 'unknown report mode: %s\n' "$report_mode" >&2
        exit 1
        ;;
    esac
  ) >"$output_path" 2>"$error_path"; then
    return 0
  fi

  return 1
}

extract_output_value() {
  key=$1
  output_path=$2
  sed -n "s/^${key}=//p" "$output_path" | head -n 1
}

printf '1..%s\n' "$TEST_COUNT"

clamp_out="$TMP_DIR/clamp.out"
clamp_err="$TMP_DIR/clamp.err"
if (
  set -eu
  . "$ROOT_DIR/d-i/forky/hosts/profiles/btrfs/server.env"
  . "$ROOT_DIR/d-i/forky/scripts/runtime/common.sh"
  printf 'clamp=%s\n' "$(runtime_clamp 12500 2048 32768)"
  printf 'raw_swap_partition=%s\n' "$(runtime_compute_swap_partition_mib 174847 16384)"
  printf 'raw_zram_partition=%s\n' "$(runtime_compute_raw_zram_partition_mb 174847 174847)"
) >"$clamp_out" 2>"$clamp_err"; then
  if [ "$(extract_output_value clamp "$clamp_out")" = "12500" ] &&
    [ "$(extract_output_value raw_swap_partition "$clamp_out")" = "4096" ] &&
    [ "$(extract_output_value raw_zram_partition "$clamp_out")" = "10927" ]; then
    pass "runtime clamp and raw backing partition sizing stay within bounds"
  else
    fail "runtime clamp and raw backing partition sizing stay within bounds" "$clamp_out"
  fi
else
  fail "runtime clamp and raw backing partition sizing stay within bounds" "$clamp_err"
fi

for profile in \
  "btrfs desktop" \
  "btrfs server" \
  "f2fs desktop" \
  "f2fs server" \
  "vm desktop" \
  "vm server"
do
  set -- $profile
  profile_family=$1
  profile_variant=$2
  output_path="$TMP_DIR/${profile_family}-${profile_variant}.out"
  error_path="$TMP_DIR/${profile_family}-${profile_variant}.err"
  if run_runtime_case "$profile_family" "$profile_variant" 400000 16384 "$output_path" "$error_path"; then
    pass "${profile_family}/${profile_variant} runtime partition sizing smoke test"
  else
    fail "${profile_family}/${profile_variant} runtime partition sizing smoke test" "$error_path"
  fi
done

all_profiles_swap_ok=true
for env_file in \
  "$ROOT_DIR"/d-i/forky/hosts/profiles/btrfs/*.env \
  "$ROOT_DIR"/d-i/forky/hosts/profiles/f2fs/*.env \
  "$ROOT_DIR"/d-i/forky/hosts/profiles/vm/*.env \
  "$ROOT_DIR"/d-i/forky/hosts/profiles/override/*.env
do
  if ! (
    unset DEFAULT_RAW_SWAP_SLOT SIZE_PART_RAW_SWAP_MB
    unset SIZE_PART_SWAP_MIN_MIB SIZE_PART_SWAP_MAX_MIB
    . "$env_file"
    [ "${DEFAULT_RAW_SWAP_SLOT:-0}" -gt 0 ]
    [ "${SIZE_PART_RAW_SWAP_MB:-0}" -gt 0 ]
    [ "${SIZE_PART_SWAP_MIN_MIB:-0}" -gt 0 ]
    [ "${SIZE_PART_SWAP_MAX_MIB:-0}" -ge "$SIZE_PART_SWAP_MIN_MIB" ]
    [ "$SIZE_PART_RAW_SWAP_MB" -ge "$SIZE_PART_SWAP_MIN_MIB" ]
    [ "$SIZE_PART_RAW_SWAP_MB" -le "$SIZE_PART_SWAP_MAX_MIB" ]
  ); then
    all_profiles_swap_ok=false
    break
  fi
done
if [ "$all_profiles_swap_ok" = true ]; then
  pass "every concrete profile reserves an explicit swap-fallback partition"
else
  fail "every concrete profile reserves an explicit swap-fallback partition" "$env_file"
fi

cbook_out="$TMP_DIR/f2fs-de-cbook.out"
cbook_err="$TMP_DIR/f2fs-de-cbook.err"
if run_f2fs_override_runtime_case f2fs-de-cbook 29952 3424 "$cbook_out" "$cbook_err"; then
  if [ "$(extract_output_value raw_swap_partition "$cbook_out")" = "2048" ] &&
     [ "$(extract_output_value raw_swap_slot "$cbook_out")" = "7" ] &&
     [ "$(extract_output_value raw_swap_device "$cbook_out")" = "/dev/fakep7" ] &&
     [ "$(extract_output_value recipe_partition_count "$cbook_out")" = "8" ] &&
     [ "$(extract_output_value recipe_raw_swap_index "$cbook_out")" = "7" ] &&
     [ "$(extract_output_value root_partition "$cbook_out")" = "16882" ] &&
     [ "$(extract_output_value usable "$cbook_out")" = "29696" ]; then
    pass "f2fs-de-cbook renders a 2 GiB swap-fallback partition at slot 7"
  else
    fail "f2fs-de-cbook renders a 2 GiB swap-fallback partition at slot 7" "$cbook_out"
  fi
else
  fail "f2fs-de-cbook renders a 2 GiB swap-fallback partition at slot 7" "$cbook_err"
fi

regression_out="$TMP_DIR/btrfs-server-regression.out"
regression_err="$TMP_DIR/btrfs-server-regression.err"
if run_runtime_case btrfs server 175103 16384 "$regression_out" "$regression_err"; then
  if [ "$(extract_output_value raw_swap_partition "$regression_out")" = "4096" ] &&
    [ "$(extract_output_value raw_zram_partition "$regression_out")" = "10927" ] &&
    [ "$(extract_output_value usable "$regression_out")" = "174847" ]; then
    pass "btrfs/server near-budget raw partition sizing regression stays installable"
  else
    fail "btrfs/server near-budget raw partition sizing regression stays installable" "$regression_out"
  fi
else
  fail "btrfs/server near-budget raw partition sizing regression stays installable" "$regression_err"
fi

desktop_regression_out="$TMP_DIR/btrfs-desktop-regression.out"
desktop_regression_err="$TMP_DIR/btrfs-desktop-regression.err"
if run_runtime_case btrfs desktop 175103 16384 "$desktop_regression_out" "$desktop_regression_err"; then
  if [ "$(extract_output_value raw_swap_partition "$desktop_regression_out")" = "4096" ] &&
    [ "$(extract_output_value raw_zram_partition "$desktop_regression_out")" = "10927" ] &&
    [ "$(extract_output_value usable "$desktop_regression_out")" = "174847" ]; then
    pass "btrfs/desktop near-budget sizing stays installable"
  else
    fail "btrfs/desktop near-budget sizing stays installable" "$desktop_regression_out"
  fi
else
  fail "btrfs/desktop near-budget sizing stays installable" "$desktop_regression_err"
fi

vm_desktop_regression_out="$TMP_DIR/vm-desktop-regression.out"
vm_desktop_regression_err="$TMP_DIR/vm-desktop-regression.err"
if run_runtime_case vm desktop 175103 16384 "$vm_desktop_regression_out" "$vm_desktop_regression_err"; then
  if [ "$(extract_output_value raw_swap_partition "$vm_desktop_regression_out")" = "4096" ] &&
    [ "$(extract_output_value raw_zram_partition "$vm_desktop_regression_out")" = "10927" ] &&
    [ "$(extract_output_value usable "$vm_desktop_regression_out")" = "174847" ]; then
    pass "vm/desktop near-budget sizing stays installable"
  else
    fail "vm/desktop near-budget sizing stays installable" "$vm_desktop_regression_out"
  fi
else
  fail "vm/desktop near-budget sizing stays installable" "$vm_desktop_regression_err"
fi

f2fs_regression_out="$TMP_DIR/f2fs-server-regression.out"
f2fs_regression_err="$TMP_DIR/f2fs-server-regression.err"
if run_runtime_case f2fs server 25000 16384 "$f2fs_regression_out" "$f2fs_regression_err"; then
  if [ "$(extract_output_value raw_swap_partition "$f2fs_regression_out")" = "2048" ] &&
    [ "$(extract_output_value raw_zram_partition "$f2fs_regression_out")" = "2048" ] &&
    [ "$(extract_output_value usable "$f2fs_regression_out")" = "24744" ]; then
    pass "f2fs/server near-budget sizing stays installable"
  else
    fail "f2fs/server near-budget sizing stays installable" "$f2fs_regression_out"
  fi
else
  fail "f2fs/server near-budget sizing stays installable" "$f2fs_regression_err"
fi

f2fs_qemu_pool_out="$TMP_DIR/f2fs-qemu-pool.out"
f2fs_qemu_pool_err="$TMP_DIR/f2fs-qemu-pool.err"
f2fs_without_qemu_pool_out="$TMP_DIR/f2fs-without-qemu-pool.out"
f2fs_without_qemu_pool_err="$TMP_DIR/f2fs-without-qemu-pool.err"
if run_assignment_case \
  f2fs \
  desktop \
  'classes=lab,desktop,standard,dhcp,qemu' \
  "$f2fs_qemu_pool_out" \
  "$f2fs_qemu_pool_err" \
  qemu-pool-summary &&
  run_assignment_case \
    f2fs \
    desktop \
    'classes=lab,desktop,standard,dhcp' \
    "$f2fs_without_qemu_pool_out" \
    "$f2fs_without_qemu_pool_err" \
    qemu-pool-summary
then
  if [ "$(extract_output_value qemu_pool_enabled "$f2fs_qemu_pool_out")" = true ] &&
     [ "$(extract_output_value pool_slot "$f2fs_qemu_pool_out")" = 5 ] &&
     [ "$(extract_output_value pool_device "$f2fs_qemu_pool_out")" = /dev/fakep5 ] &&
     [ "$(extract_output_value pool_mb "$f2fs_qemu_pool_out")" = 24576 ] &&
     [ "$(extract_output_value qemu_pool_enabled "$f2fs_without_qemu_pool_out")" = false ] &&
     [ -z "$(extract_output_value pool_slot "$f2fs_without_qemu_pool_out")" ] &&
     [ -z "$(extract_output_value pool_device "$f2fs_without_qemu_pool_out")" ] &&
     [ "$(extract_output_value pool_mb "$f2fs_without_qemu_pool_out")" = 0 ]
  then
    pass "f2fs desktop adds a protected Incus pool only for the qemu addon"
  else
    fail "f2fs desktop adds a protected Incus pool only for the qemu addon" "$f2fs_qemu_pool_out"
  fi
else
  fail "f2fs desktop adds a protected Incus pool only for the qemu addon" "$f2fs_qemu_pool_err"
fi

dualboot_budget_out="$TMP_DIR/btrfs-dualboot-budget.out"
dualboot_budget_err="$TMP_DIR/btrfs-dualboot-budget.err"
dualboot_budget_env="$TMP_DIR/btrfs-dualboot-budget.env"
compose_host_env btrfs server "$dualboot_budget_env"
if (
  set -eu
  . "$dualboot_budget_env"
  . "$ROOT_DIR/d-i/forky/scripts/runtime/common.sh"
  . "$ROOT_DIR/d-i/forky/scripts/runtime/btrfs.sh"
  DEV_INSTALL_DISK=/dev/fake
  DEV_PART_PREFIX=/dev/fakep
  INSTALLER_CMDLINE='classes=lab,server,standard,dhcp,dualboot dualboot_efi=1 dualboot_debian=5'
  RUNTIME_INSTALL_DISK_MB_OVERRIDE=400000
  RUNTIME_MEMTOTAL_MIB_OVERRIDE=16384
  installer_resolve_install_target_defaults() { :; }
  runtime_partition_path() { printf '%s%s\n' "$DEV_PART_PREFIX" "$1"; }
  runtime_ensure_system_identity() {
    SYSTEM_PREFIX=deb
    SYSTEM_HOSTNAME=deb-test
    SYSTEM_DOMAIN=example.test
  }
  runtime_apply_layout_from_cmdline
  RUNTIME_PARTITION_1_SIZE_MB=512
  RUNTIME_PARTITION_2_SIZE_MB=50000
  RUNTIME_PARTITION_3_SIZE_MB=50000
  RUNTIME_PARTITION_4_SIZE_MB=50000
  runtime_compute_layout_sizing
  printf 'raw_zram_partition=%s\n' "$DEV_PART_RAW_ZRAM_MB"
  printf 'usable=%s\n' "$RUNTIME_USABLE_BUDGET_MB"
) >"$dualboot_budget_out" 2>"$dualboot_budget_err"; then
  if [ "$(extract_output_value raw_zram_partition "$dualboot_budget_out")" = "15577" ] &&
    [ "$(extract_output_value usable "$dualboot_budget_out")" = "249232" ]; then
    pass "btrfs dualboot sizing uses only the installable budget after preserved partitions"
  else
    fail "btrfs dualboot sizing uses only the installable budget after preserved partitions" "$dualboot_budget_out"
  fi
else
  fail "btrfs dualboot sizing uses only the installable budget after preserved partitions" "$dualboot_budget_err"
fi

dualboot_assign_out="$TMP_DIR/dualboot-assignment.out"
dualboot_assign_err="$TMP_DIR/dualboot-assignment.err"
if run_assignment_case btrfs server 'classes=lab,server,standard,dhcp,dualboot dualboot_efi=1 dualboot_debian=5' "$dualboot_assign_out" "$dualboot_assign_err" dualboot-summary; then
  if [ "$(extract_output_value dualboot_enabled "$dualboot_assign_out")" = "true" ] &&
    [ "$(extract_output_value efi_slot "$dualboot_assign_out")" = "1" ] &&
    [ "$(extract_output_value boot_slot "$dualboot_assign_out")" = "5" ] &&
    [ "$(extract_output_value preserved_slots "$dualboot_assign_out")" = "2 3 4" ]; then
    pass "btrfs dualboot addon maps explicit EFI and Debian start slots"
  else
    fail "btrfs dualboot addon maps explicit EFI and Debian start slots" "$dualboot_assign_out"
  fi
else
  fail "btrfs dualboot addon maps explicit EFI and Debian start slots" "$dualboot_assign_err"
fi

missing_dualboot_slot_out="$TMP_DIR/dualboot-missing-slot.out"
missing_dualboot_slot_err="$TMP_DIR/dualboot-missing-slot.err"
if run_assignment_case btrfs server 'classes=lab,server,standard,dhcp,dualboot dualboot_efi=1' "$missing_dualboot_slot_out" "$missing_dualboot_slot_err" dualboot-summary; then
  fail "btrfs dualboot addon requires dualboot_debian slot"
elif grep -q 'requires dualboot_debian' "$missing_dualboot_slot_err"; then
  pass "btrfs dualboot addon requires dualboot_debian slot"
else
  fail "btrfs dualboot addon requires dualboot_debian slot" "$missing_dualboot_slot_err"
fi

stray_dualboot_slots_out="$TMP_DIR/dualboot-stray-slots.out"
stray_dualboot_slots_err="$TMP_DIR/dualboot-stray-slots.err"
if run_assignment_case btrfs server 'classes=lab,server,standard,dhcp dualboot_efi=1 dualboot_debian=5' "$stray_dualboot_slots_out" "$stray_dualboot_slots_err" dualboot-summary; then
  fail "btrfs dualboot slots require selected dualboot addon"
elif grep -q 'require classes=.*,dualboot' "$stray_dualboot_slots_err"; then
  pass "btrfs dualboot slots require selected dualboot addon"
else
  fail "btrfs dualboot slots require selected dualboot addon" "$stray_dualboot_slots_err"
fi

f2fs_dualboot_class_out="$TMP_DIR/f2fs-dualboot-class.out"
f2fs_dualboot_class_err="$TMP_DIR/f2fs-dualboot-class.err"
if run_assignment_case f2fs server 'classes=lab,server,standard,dhcp,dualboot dualboot_efi=1 dualboot_debian=5' "$f2fs_dualboot_class_out" "$f2fs_dualboot_class_err"; then
  fail "f2fs rejects selected dualboot addon"
elif grep -q 'dualboot is not supported for F2FS layouts' "$f2fs_dualboot_class_err"; then
  pass "f2fs rejects selected dualboot addon"
else
  fail "f2fs rejects selected dualboot addon" "$f2fs_dualboot_class_err"
fi

f2fs_stray_dualboot_slots_out="$TMP_DIR/f2fs-dualboot-stray-slots.out"
f2fs_stray_dualboot_slots_err="$TMP_DIR/f2fs-dualboot-stray-slots.err"
if run_assignment_case f2fs server 'classes=lab,server,standard,dhcp dualboot_efi=1 dualboot_debian=5' "$f2fs_stray_dualboot_slots_out" "$f2fs_stray_dualboot_slots_err"; then
  fail "f2fs dualboot slots require selected dualboot addon"
elif grep -q 'require classes=.*,dualboot' "$f2fs_stray_dualboot_slots_err"; then
  pass "f2fs dualboot slots require selected dualboot addon"
else
  fail "f2fs dualboot slots require selected dualboot addon" "$f2fs_stray_dualboot_slots_err"
fi
