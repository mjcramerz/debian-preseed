#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/forky-profile-dualboot-smoke.XXXXXX")
trap 'rm -rf "$TMP_DIR"' EXIT HUP INT TERM

TEST_COUNT=6
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

printf '1..%s\n' "$TEST_COUNT"

check_profile_case() {
  label=$1
  classes=$2
  disk=$3
  expected_profile=$4
  expected_env_name=$5
  expected_family=$6
  expected_hook=$7
  output_path=$8
  error_path=$9

  if (
    set -eu
    INSTALLER_SOURCE_ROOT="$ROOT_DIR/d-i/forky"
    INSTALLER_RUNTIME_DIR="$TMP_DIR/runtime-$label"
    export INSTALLER_SOURCE_ROOT INSTALLER_RUNTIME_DIR
    . "$ROOT_DIR/d-i/forky/scripts/common/lib.sh"
    installer_auto_class_tokens() { printf '%s\n' amd64 intel generic "$disk"; }
    installer_cmdline_value() { case "$1" in auto-install/classes|classes) printf '%s\n' "$classes" ;; esac; }
    installer_debconf_value() { return 1; }
    installer_write_context "$ROOT_DIR/d-i/forky" >/dev/null
    conf=$(installer_runtime_install_conf_path)
    printf 'host_profile=%s\n' "$(sed -n 's/^host_profile=//p' "$conf")"
    printf 'host_profile_env_name=%s\n' "$(sed -n 's/^host_profile_env_name=//p' "$conf")"
    printf 'host_family=%s\n' "$(sed -n 's/^host_family=//p' "$conf")"
    printf 'hook_family=%s\n' "$(sed -n 's/^hook_family=//p' "$conf")"
  ) >"$output_path" 2>"$error_path"; then
    [ "$(sed -n 's/^host_profile=//p' "$output_path")" = "$expected_profile" ] &&
    [ "$(sed -n 's/^host_profile_env_name=//p' "$output_path")" = "$expected_env_name" ] &&
    [ "$(sed -n 's/^host_family=//p' "$output_path")" = "$expected_family" ] &&
    [ "$(sed -n 's/^hook_family=//p' "$output_path")" = "$expected_hook" ]
  else
    return 1
  fi
}

profile_out="$TMP_DIR/profile.out"
profile_err="$TMP_DIR/profile.err"
if check_profile_case \
  btrfs-dual \
  'lab,desktop,standard,dhcp,btrfs-de-dual,dualboot' \
  nvme \
  'override-btrfs-de-dual' \
  'btrfs-de-dual' \
  btrfs \
  btrfs \
  "$profile_out" \
  "$profile_err"; then
  pass "forky btrfs-de-dual resolves through the override profile path"
else
  fail "forky btrfs-de-dual resolves through the override profile path" "${profile_err:-$profile_out}"
fi

profile_f2fs_out="$TMP_DIR/profile-f2fs.out"
profile_f2fs_err="$TMP_DIR/profile-f2fs.err"
if check_profile_case \
  f2fs-dual \
  'lab,desktop,standard,dhcp,f2fs-de-dual,dualboot' \
  emmc \
  'override-f2fs-de-dual' \
  'f2fs-de-dual' \
  f2fs \
  f2fs \
  "$profile_f2fs_out" \
  "$profile_f2fs_err"; then
  pass "forky f2fs-de-dual resolves through the override profile path"
else
  fail "forky f2fs-de-dual resolves through the override profile path" "${profile_f2fs_err:-$profile_f2fs_out}"
fi

default_out="$TMP_DIR/default.out"
default_err="$TMP_DIR/default.err"
if (
  set -eu
  INSTALLER_SOURCE_ROOT="$ROOT_DIR/d-i/forky"
  INSTALLER_RUNTIME_DIR="$TMP_DIR/runtime-default"
  export INSTALLER_SOURCE_ROOT INSTALLER_RUNTIME_DIR
  . "$ROOT_DIR/d-i/forky/scripts/common/lib.sh"
  installer_auto_class_tokens() { printf '%s\n' amd64 intel generic nvme; }
  installer_cmdline_value() { case "$1" in auto-install/classes|classes) printf '%s\n' default ;; esac; }
  installer_debconf_value() { return 1; }
  installer_write_context "$ROOT_DIR/d-i/forky" >/dev/null
  sed -n 's/^selected_class_refs=//p' "$(installer_runtime_install_conf_path)"
) >"$default_out" 2>"$default_err" &&
  grep -q ' profile/btrfs-de ' "$default_out"; then
  pass "forky classes=default selects profile/btrfs-de"
else
  fail "forky classes=default selects profile/btrfs-de" "${default_err:-$default_out}"
fi

assignment_out="$TMP_DIR/assignment.out"
assignment_err="$TMP_DIR/assignment.err"
if (
  set -eu
  . "$ROOT_DIR/d-i/forky/hosts/profiles/f2fs/desktop.env"
  RUNTIME_COMMON_LIB="$ROOT_DIR/d-i/forky/scripts/runtime/common.sh"
  export RUNTIME_COMMON_LIB
  . "$ROOT_DIR/d-i/forky/scripts/runtime/common.sh"
  . "$ROOT_DIR/d-i/forky/scripts/runtime/f2fs.sh"
  DEV_INSTALL_DISK=/dev/fake
  DEV_PART_PREFIX=/dev/fakep
  INSTALLER_CMDLINE='classes=lab,desktop,standard,dhcp,dualboot,f2fs-de-dual dualboot_efi=1 dualboot_debian=5'
  installer_resolve_install_target_defaults() { :; }
  runtime_partition_path() { printf '%s%s\n' "$DEV_PART_PREFIX" "$1"; }
  runtime_apply_layout_from_cmdline
  printf 'dualboot_enabled=%s\n' "$DUALBOOT_ENABLED"
  printf 'efi_slot=%s\n' "$RUNTIME_EFI_SLOT"
  printf 'boot_slot=%s\n' "$RUNTIME_BOOT_SLOT"
  printf 'preserved_slots=%s\n' "${RUNTIME_PRESERVED_SLOTS:-}"
) >"$assignment_out" 2>"$assignment_err"; then
  if [ "$(sed -n 's/^dualboot_enabled=//p' "$assignment_out")" = "true" ] &&
     [ "$(sed -n 's/^efi_slot=//p' "$assignment_out")" = "1" ] &&
     [ "$(sed -n 's/^boot_slot=//p' "$assignment_out")" = "5" ] &&
     [ "$(sed -n 's/^preserved_slots=//p' "$assignment_out")" = "2 3 4" ]; then
    pass "forky f2fs dualboot maps reused EFI and Debian start slots"
  else
    fail "forky f2fs dualboot maps reused EFI and Debian start slots" "$assignment_out"
  fi
else
  fail "forky f2fs dualboot maps reused EFI and Debian start slots" "$assignment_err"
fi

stray_out="$TMP_DIR/stray.out"
stray_err="$TMP_DIR/stray.err"
if (
  set -eu
  . "$ROOT_DIR/d-i/forky/hosts/profiles/f2fs/desktop.env"
  RUNTIME_COMMON_LIB="$ROOT_DIR/d-i/forky/scripts/runtime/common.sh"
  export RUNTIME_COMMON_LIB
  . "$ROOT_DIR/d-i/forky/scripts/runtime/common.sh"
  . "$ROOT_DIR/d-i/forky/scripts/runtime/f2fs.sh"
  DEV_INSTALL_DISK=/dev/fake
  DEV_PART_PREFIX=/dev/fakep
  INSTALLER_CMDLINE='classes=lab,desktop,standard,dhcp,f2fs-de-dual dualboot_efi=1 dualboot_debian=5'
  installer_resolve_install_target_defaults() { :; }
  runtime_partition_path() { printf '%s%s\n' "$DEV_PART_PREFIX" "$1"; }
  runtime_apply_layout_from_cmdline
) >"$stray_out" 2>"$stray_err"; then
  fail "forky f2fs dualboot slot arguments still require the dualboot addon"
elif grep -q 'dualboot_efi and dualboot_debian require classes=.*dualboot' "$stray_err"; then
  pass "forky f2fs dualboot slot arguments still require the dualboot addon"
else
  fail "forky f2fs dualboot slot arguments still require the dualboot addon" "$stray_err"
fi

server_suite_out="$TMP_DIR/server-suite.out"
server_suite_err="$TMP_DIR/server-suite.err"
server_suite_target="$TMP_DIR/server-suite-target"
server_suite_bin="$TMP_DIR/server-suite-bin"
mkdir -p "$server_suite_target/etc/apt/sources.list.d" "$server_suite_bin"
cat >"$server_suite_bin/in-target" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod 0755 "$server_suite_bin/in-target"
if INSTALLER_TARGET_DIR="$server_suite_target" \
   INSTALLER_ASSUME_TARGET_MOUNTED=1 \
   INSTALLER_SELECTED_CLASS_REFS='addon/server-suite role/server' \
   INSTALLER_RUNTIME_DIR="$TMP_DIR/runtime-server-suite" \
   PATH="$server_suite_bin:$PATH" \
   sh "$ROOT_DIR/d-i/forky/hooks/shared/finish-install.d/95-normalize-apt" \
     >"$server_suite_out" 2>"$server_suite_err" &&
   grep -q '^APT::Default-Release "trixie";$' "$server_suite_target/etc/apt/apt.conf.d/95default-server-suite" &&
   [ ! -e "$server_suite_target/etc/apt/apt.conf.d/95default-release-forky" ] &&
   [ ! -e "$server_suite_target/etc/apt/apt.conf.d/95default-release-trixie" ]; then
  pass "forky server-suite installs the dedicated target default-release policy"
else
  fail "forky server-suite installs the dedicated target default-release policy" "${server_suite_err:-$server_suite_out}"
fi

[ "$FAIL_COUNT" -eq 0 ]
