#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/runtime-storage-roots-smoke.XXXXXX")
trap 'rm -rf -- "$TMP_DIR"' EXIT HUP INT TERM

TEST_COUNT=9
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

runtime_env="$ROOT_DIR/d-i/forky/hosts/shared/runtime.env"
storage_script="$ROOT_DIR/d-i/forky/scripts/late/storage-maintenance.sh"
volatile_script="$ROOT_DIR/d-i/forky/scripts/late/volatile-storage.sh"
asset_script="$ROOT_DIR/d-i/forky/scripts/late/target-assets.sh"
template_script="$ROOT_DIR/d-i/forky/scripts/late/templates.sh"
tmpfiles_roots="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/tmpfiles.d/10-runtime-storage-roots.conf"
tmpfiles_temporary="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/tmpfiles.d/tmp.conf"
creds_override="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/systemd/system/systemd-creds.socket.d/10-encrypted-only.conf"
var_log_mount_override="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/systemd/system/var-log.mount.d/override.conf"

if grep -q '^DIR_DATA_CONFIG="${DIR_DATA}/config"$' "$runtime_env" &&
   grep -q '^DIR_DATA_SERVICES_USR="${DIR_DATA_SERVICES}/usr"$' "$runtime_env" &&
   grep -q '^DIR_DATA_BIN="${DIR_DATA}/bin"$' "$runtime_env" &&
   grep -q '^DIR_DATA_DOCS="${DIR_DATA}/docs"$' "$runtime_env" &&
   grep -q '^DIR_DATA_DOWNLOADS="${DIR_DATA}/downloads"$' "$runtime_env" &&
   grep -q '^DIR_DATA_PKI="${DIR_DATA}/pki"$' "$runtime_env" &&
   grep -q '^DIR_DATA_BACKUP="${DIR_DATA}/backup"$' "$runtime_env" &&
   grep -q '^DIR_POOL_BUILD="${DIR_POOL}/build"$' "$runtime_env" &&
   grep -q '^DIR_POOL_QEMU="${DIR_POOL}/qemu"$' "$runtime_env" &&
   grep -q '^DIR_POOL_INCUS="${DIR_POOL}/incus"$' "$runtime_env" &&
   ! grep -q '^DIR_POOL_LIBVIRT=' "$runtime_env" &&
   ! grep -q '^DIR_POOL_LXC=' "$runtime_env" &&
   ! grep -q '^DIR_POOL_VAGRANT=' "$runtime_env" &&
   grep -q '^DIR_POOL_PODMAN="${DIR_POOL}/podman"$' "$runtime_env" &&
   grep -q '^DIR_POOL_LOG="${DIR_POOL}/log"$' "$runtime_env" &&
   ! grep -q '^DIR_POOL_BUILDS=' "$runtime_env"; then
  pass "shared runtime env defines the always-present /data and /pool roots without DIR_POOL_BUILDS"
else
  fail "shared runtime env defines the always-present /data and /pool roots without DIR_POOL_BUILDS"
fi

if grep -q '^d __INSTALLER_DIR_DATA__ 0755 root root -$' "$tmpfiles_roots" &&
   grep -q '^d __INSTALLER_DIR_DATA_CONFIG__ 0755 root root -$' "$tmpfiles_roots" &&
   grep -q '^d __INSTALLER_DIR_DATA_SERVICES_USR__ 0755 root root -$' "$tmpfiles_roots" &&
   grep -q '^d __INSTALLER_DIR_DATA_DOCS__ 2750 __INSTALLER_ACCOUNT_USERNAME__ __INSTALLER_ACCOUNT_USERNAME__ -$' "$tmpfiles_roots" &&
   grep -q '^d __INSTALLER_DIR_DATA_DOWNLOADS__ 2750 __INSTALLER_ACCOUNT_USERNAME__ __INSTALLER_ACCOUNT_USERNAME__ -$' "$tmpfiles_roots" &&
   grep -q '^d __INSTALLER_DIR_DATA_PKI__ 0711 root root -$' "$tmpfiles_roots" &&
   grep -q '^d __INSTALLER_DIR_DATA_PKI__/ssh 0711 __INSTALLER_ACCOUNT_USERNAME__ __INSTALLER_ACCOUNT_USERNAME__ -$' "$tmpfiles_roots" &&
   grep -q '^d __INSTALLER_DIR_DATA_PKI__/ssh/.keys 0700 __INSTALLER_ACCOUNT_USERNAME__ __INSTALLER_ACCOUNT_USERNAME__ -$' "$tmpfiles_roots" &&
   grep -q '^d __INSTALLER_DIR_DATA_PKI__/ssh/config.d 0700 __INSTALLER_ACCOUNT_USERNAME__ __INSTALLER_ACCOUNT_USERNAME__ -$' "$tmpfiles_roots" &&
   grep -q '^d __INSTALLER_DIR_DATA_PKI__/ssh/podbin 0700 __INSTALLER_PODMAN_SERVICE_USER__ __INSTALLER_PODMAN_SERVICE_USER__ -$' "$tmpfiles_roots" &&
   grep -q '^d __INSTALLER_DIR_DATA_BACKUP__ 0700 root root -$' "$tmpfiles_roots" &&
   grep -q '^d __INSTALLER_DIR_POOL__ 2775 root devops -$' "$tmpfiles_roots" &&
   grep -q '^d __INSTALLER_DIR_POOL_BUILD__ 2770 root devops -$' "$tmpfiles_roots" &&
   grep -q '^d __INSTALLER_DIR_POOL_BUILD_RUNNERS__ 2770 root devops -$' "$tmpfiles_roots" &&
   grep -q '^d __INSTALLER_DIR_POOL_CACHE__ 2770 root devops -$' "$tmpfiles_roots" &&
   grep -q '^d __INSTALLER_DIR_POOL_CACHE_RUNNERS__ 2770 root devops -$' "$tmpfiles_roots" &&
   grep -q '^d __INSTALLER_DIR_POOL_DB__ 2770 root devops -$' "$tmpfiles_roots" &&
   grep -q '^d __INSTALLER_DIR_POOL_PODMAN__ 0711 root root -$' "$tmpfiles_roots" &&
   grep -q '^d __INSTALLER_DIR_POOL_LOG__ 2770 root devops -$' "$tmpfiles_roots" &&
   ! grep -q '^d __INSTALLER_DIR_POOL_APTLY__ ' "$tmpfiles_roots"; then
  pass "tmpfiles root policy recreates the shared /data and /pool runtime roots"
else
  fail "tmpfiles root policy recreates the shared /data and /pool runtime roots"
fi

if grep -q '^normalize_target_tmpfiles_directory_policy() {$' "$storage_script" &&
   grep -q '^stage_target_runtime_storage_root_policy() {$' "$storage_script" &&
   grep -q '^    0\[0-7\]\[0-7\]\[0-7\]\[0-7\])$' "$storage_script" &&
   grep -q '^      entry_mode=\${entry_mode#0}$' "$storage_script" &&
   grep -q '^PODMAN_SERVICE_USER=' "$template_script" &&
   grep -q 'render_target_asset "$(installer_repo_join_var DIR_HOOKS_SHARED_TARGET etc/tmpfiles.d/10-runtime-storage-roots.conf)" "/etc/tmpfiles.d/10-runtime-storage-roots.conf" 0644' "$storage_script" &&
   grep -q 'normalize_target_tmpfiles_directory_policy "/etc/tmpfiles.d/10-runtime-storage-roots.conf" "shared runtime storage roots"' "$storage_script" &&
   grep -q 'etc/systemd/system/systemd-creds.socket.d/10-encrypted-only.conf' "$storage_script" &&
   grep -q '^ConditionPathIsEncrypted=/var/lib/systemd$' "$creds_override"; then
  pass "storage maintenance stages the runtime-root tmpfiles policy, systemd-creds gating, and normalized shared storage roots from one policy surface"
else
  fail "storage maintenance stages the runtime-root tmpfiles policy, systemd-creds gating, and normalized shared storage roots from one policy surface"
fi

temporary_tmpfiles_native_ok=true
if [ -x /usr/bin/systemd-tmpfiles ]; then
  mkdir -p \
    "$TMP_DIR/tmpfiles-root/etc/tmpfiles.d" \
    "$TMP_DIR/tmpfiles-root/tmp/boot-purge" \
    "$TMP_DIR/tmpfiles-root/var/tmp"
  : >"$TMP_DIR/tmpfiles-root/tmp/boot-purge/marker"
  cp "$tmpfiles_temporary" "$TMP_DIR/tmpfiles-root/etc/tmpfiles.d/tmp.conf"
  /usr/bin/systemd-tmpfiles \
    --root="$TMP_DIR/tmpfiles-root" \
    --boot \
    --remove \
    tmp.conf \
    >"$TMP_DIR/tmpfiles-boot.out" 2>&1 ||
    temporary_tmpfiles_native_ok=false
  [ ! -e "$TMP_DIR/tmpfiles-root/tmp/boot-purge/marker" ] ||
    temporary_tmpfiles_native_ok=false
  ! grep -q 'Duplicate line' "$TMP_DIR/tmpfiles-boot.out" ||
    temporary_tmpfiles_native_ok=false
  /usr/bin/systemd-tmpfiles \
    --root="$TMP_DIR/tmpfiles-root" \
    --boot \
    --create \
    --dry-run \
    tmp.conf \
    >"$TMP_DIR/tmpfiles-create.out" 2>&1 ||
    temporary_tmpfiles_native_ok=false
  /usr/bin/systemd-tmpfiles \
    --root="$TMP_DIR/tmpfiles-root" \
    --clean \
    --dry-run \
    tmp.conf \
    >"$TMP_DIR/tmpfiles-clean.out" 2>&1 ||
    temporary_tmpfiles_native_ok=false
fi
if grep -Fxq 'D! /tmp 1777 root root 0' "$tmpfiles_temporary" &&
   grep -Fxq 'e /tmp 1777 root root 7d' "$tmpfiles_temporary" &&
   grep -Fxq 'd /var/tmp 1777 root root 30d' "$tmpfiles_temporary" &&
   grep -q 'DIR_HOOKS_SHARED_TARGET etc/tmpfiles.d/tmp.conf' "$storage_script" &&
   ! grep -q 'tmp-boot-purge' "$storage_script" &&
   [ "$temporary_tmpfiles_native_ok" = true ]; then
  pass "managed tmpfiles policy purges /tmp at boot and applies periodic /tmp and /var/tmp retention"
else
  cat "$TMP_DIR/tmpfiles-boot.out" "$TMP_DIR/tmpfiles-create.out" "$TMP_DIR/tmpfiles-clean.out" 2>/dev/null || true
  fail "managed tmpfiles policy purges /tmp at boot and applies periodic /tmp and /var/tmp retention"
fi

if grep -q 'ensure_target_managed_runtime_storage_roots' "$ROOT_DIR/d-i/forky/scripts/late/btrfs-family.sh" &&
   grep -q 'ensure_target_managed_runtime_storage_roots' "$ROOT_DIR/d-i/forky/scripts/late/f2fs-family.sh"; then
  pass "both storage families invoke the shared runtime-root creator"
else
  fail "both storage families invoke the shared runtime-root creator"
fi

if grep -q '\[ -d "\$target_parent" \] || install -d -m 0755 "\$target_parent"' "$asset_script" &&
   grep -q '\[ -d "\$dest_parent" \] || install -d -m 0755 "\$dest_parent"' "$template_script"; then
  pass "target asset and template helpers preserve existing normalized parent-directory modes"
else
  fail "target asset and template helpers preserve existing normalized parent-directory modes"
fi

if grep -q '^target_helper_doc_owner_ids() {$' "$asset_script" &&
   grep -q '^target_chown_helper_doc_path() {$' "$asset_script" &&
   grep -q 'ACCOUNT_USERNAME must be set before staging helper docs' "$asset_script" &&
   grep -q "awk -F: -v wanted_user=\"\$ACCOUNT_USERNAME\" '\$1 == wanted_user { print \$3 \":\" \$4; exit }' /target/etc/passwd" "$asset_script" &&
   grep -q 'chown "\$helper_doc_owner_ids" "\$doc_host_path"' "$asset_script"; then
  pass "helper docs inherit the primary-user ownership contract instead of landing as root-owned files"
else
  fail "helper docs inherit the primary-user ownership contract instead of landing as root-owned files"
fi

tmpfs_pre_clean_function=$(sed -n '/^install_target_tmpfs_pre_clean_assets() {$/,/^}$/p' "$volatile_script")
if printf '%s\n' "$tmpfs_pre_clean_function" |
     grep -q 'render_target_template "$TMP_ENV_DIR/tmpfs-pre-clean.tmpl"' &&
   printf '%s\n' "$tmpfs_pre_clean_function" |
     grep -q 'render_target_template "$TMP_ENV_DIR/tmpfs-pre-clean.service.tmpl"' &&
   printf '%s\n' "$tmpfs_pre_clean_function" |
     grep -q 'etc/systemd/system/tmp.mount.d/override.conf' &&
   printf '%s\n' "$tmpfs_pre_clean_function" |
     grep -q 'stage_target_tmpfs_pre_clean_mount_override_if_enabled TMPFS_DEV_SHM' &&
   printf '%s\n' "$tmpfs_pre_clean_function" |
     grep -q 'stage_target_tmpfs_pre_clean_mount_override_if_enabled TMPFS_VAR_LOG' &&
   grep -Fxq 'Before=systemd-logind.service systemd-user-sessions.service' "$var_log_mount_override"; then
  pass "volatile storage stages pre-clean dependencies and keeps /var/log writable through session shutdown"
else
  fail "volatile storage stages pre-clean dependencies and keeps /var/log writable through session shutdown"
fi

tmpfs_pre_clean_verify_function=$(
  sed -n \
    '/^verify_target_tmpfs_pre_clean_and_apt_refresh_staging() {$/,/^verify_target_apt_default_release_policy() {$/p' \
    "$storage_script"
)
if printf '%s\n' "$tmpfs_pre_clean_verify_function" |
     grep -Fq 'tmpfs_dev_shm=${23}' &&
   printf '%s\n' "$tmpfs_pre_clean_verify_function" |
     grep -Fq '[ -x "$tmpfs_pre_clean_helper" ]' &&
   printf '%s\n' "$tmpfs_pre_clean_verify_function" |
     grep -Fq '[ -r "$tmpfs_pre_clean_service" ]' &&
   printf '%s\n' "$tmpfs_pre_clean_verify_function" |
     grep -Fq '[ -r "$tmp_mount_override" ]' &&
   printf '%s\n' "$tmpfs_pre_clean_verify_function" |
     grep -Fq 'check_mount_override_state "$tmpfs_dev_shm" "$dev_shm_mount_override"' &&
   printf '%s\n' "$tmpfs_pre_clean_verify_function" |
     grep -Fq 'check_mount_override_state "$tmpfs_var_log" "$var_log_mount_override"' &&
   printf '%s\n' "$tmpfs_pre_clean_verify_function" |
     grep -Fq '"${FILE_TMPFS_PRE_CLEAN_TMP_MOUNT_OVERRIDE}"' &&
   ! printf '%s\n' "$tmpfs_pre_clean_verify_function" |
     grep -Fq '[ ! -e "$tmpfs_pre_clean_helper" ]'; then
  pass "target verification requires the staged tmpfs pre-clean service and policy-matched mount overrides"
else
  fail "target verification requires the staged tmpfs pre-clean service and policy-matched mount overrides"
fi

[ "$FAIL_COUNT" -eq 0 ]
