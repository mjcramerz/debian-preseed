#!/bin/sh
# shellcheck disable=SC1003,SC1090,SC2016,SC2031,SC2034,SC2153,SC2329
set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/podman-addon-smoke.XXXXXX")
trap 'rm -rf "$TMP_DIR"' EXIT HUP INT TERM

TEST_COUNT=31
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

podman_class="$ROOT_DIR/d-i/forky/classes/class-addon/podman.cfg"
addons_cfg="$ROOT_DIR/d-i/forky/classes/configs/addons.cfg"
desktop_env="$ROOT_DIR/d-i/forky/hosts/profiles/btrfs/desktop.env"
server_env="$ROOT_DIR/d-i/forky/hosts/shared/server.env"
helper="$ROOT_DIR/d-i/forky/scripts/late/podman.sh"
shared_loader="$ROOT_DIR/d-i/forky/hooks/shared/late_command.sh"
dispatch_script="$ROOT_DIR/d-i/forky/scripts/late/dispatch.sh"
quadlet_dropin="$ROOT_DIR/d-i/forky/hooks/shared/target/data/config/podman/templates/rootless/containers/systemd/container.d/10-podman-managed.conf.tmpl"
podman_slice="$ROOT_DIR/d-i/forky/hooks/shared/target/data/config/podman/templates/rootless/systemd/user/podman-rootless.slice.tmpl"
podman_service_dropin="$ROOT_DIR/d-i/forky/hooks/shared/target/data/config/podman/templates/rootless/systemd/user/podman.service.d/10-podman-service-managed.conf"
buildah_env_service="$ROOT_DIR/d-i/forky/hooks/shared/target/data/config/podman/templates/rootless/systemd/user/buildah-env.service.tmpl"
podman_env_service="$ROOT_DIR/d-i/forky/hooks/shared/target/data/config/podman/templates/rootless/systemd/user/podman-api-env.service.tmpl"
podman_env_file="$ROOT_DIR/d-i/forky/hooks/shared/target/data/config/podman/templates/rootless/environment.d/90-podman-api.conf.tmpl"
podman_linger_unit="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/systemd/system/podman-rootless-linger.service.tmpl"
podman_sysctl="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/sysctl.d/90-podman-rootless.conf.tmpl"
podbin_wrapper="$ROOT_DIR/d-i/forky/hooks/shared/target/usr/local/sbin/podbin.tmpl"
podbin_default="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/default/podbin.tmpl"
podbin_template_dir="$ROOT_DIR/d-i/forky/hooks/shared/target/data/config/podman/templates/podbin"
podbin_storage_template="$podbin_template_dir/storage.conf.tmpl"
rootless_storage_template="$ROOT_DIR/d-i/forky/hooks/shared/target/data/config/podman/templates/rootless/storage.conf.tmpl"
podbin_runtime_containerfile="$ROOT_DIR/d-i/forky/hooks/shared/target/data/config/podman/templates/podbin/images/runtime/Containerfile.tmpl"
podbin_runtime_entrypoint="$ROOT_DIR/d-i/forky/hooks/shared/target/data/config/podman/templates/podbin/images/runtime/entrypoint.sh.tmpl"
podbin_runtime_sshd="$ROOT_DIR/d-i/forky/hooks/shared/target/data/config/podman/templates/podbin/images/runtime/sshd_config.tmpl"
podbin_doc="$ROOT_DIR/d-i/forky/hooks/shared/target/data/docs/podbin.md"
podbin_service_bridge_doc="$ROOT_DIR/d-i/forky/hooks/shared/target/data/docs/podbin-service-bridge.md"
account_sudoers="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/sudoers.d/account.tmpl"
podbin_menu="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-podman-menu"
apparmor_profile="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/managed-desktop-wrappers"
desktop_podman_policy=$(grep '^PODMAN_' "$desktop_env")
server_podman_policy=$(grep '^PODMAN_' "$server_env")

if grep -Eq '^d-i pkgsel/include string .*podman .*buildah .*golang-github-containers-common .*conmon .*crun .*uidmap .*netavark .*aardvark-dns .*passt .*slirp4netns .*catatonit .*containernetworking-plugins .*openssh-client .*dbus-user-session$' "$podman_class" &&
   ! grep -qw 'fuse-overlayfs' "$podman_class"; then
  pass "podman addon fragment installs the requested rootless package baseline"
else
  fail "podman addon fragment installs the requested rootless package baseline"
fi

if grep -q '^Name: podman$' "$addons_cfg" &&
   grep -q '^Description: opt-in rootless Podman and Buildah runtime policy$' "$addons_cfg" &&
   ! grep -q '^LateHelper: podman-addon$' "$addons_cfg"; then
  pass "podman addon is package-selected directly while the shared late module handles target staging"
else
  fail "podman addon is package-selected directly while the shared late module handles target staging"
fi

if [ "$desktop_podman_policy" = "$server_podman_policy" ] &&
   grep -q '^PODMAN_USER="podsvc"$' "$desktop_env" &&
   grep -q '^PODMAN_USER_HOME="/data/accounts/podman"$' "$desktop_env" &&
   grep -q '^PODMAN_USER_SHELL="/usr/sbin/nologin"$' "$desktop_env" &&
   grep -q '^PODMAN_USER_LOCK=1$' "$desktop_env" &&
   grep -q '^PODMAN_USER_STRIP_GROUPS=1$' "$desktop_env" &&
   grep -q '^PODMAN_USER_LINGER=1$' "$desktop_env" &&
   grep -q '^PODMAN_USER_DOCKER_HOST=0$' "$desktop_env" &&
   grep -q '^PODMAN_USER_CONTAINER_HOST=0$' "$desktop_env" &&
   grep -q '^PODMAN_SERVICE_SLICE_ENABLE=1$' "$desktop_env" &&
   grep -q '^PODMAN_ENABLE_ROOTLESS_SYSCTL=1$' "$desktop_env" &&
   grep -q '^PODMAN_USER_CONFIG_BASE="/data/config/podman"$' "$desktop_env" &&
   grep -q '^PODMAN_ROOTLESS_STATE_BASE="/pool/podman"$' "$desktop_env" &&
   grep -q '^PODMAN_STORAGE_DRIVER="auto"$' "$desktop_env" &&
   ! grep -q 'glab-aptly' "$desktop_env" &&
   ! grep -q 'glab-user' "$desktop_env" &&
   ! grep -q '^PODMAN_APT_' "$desktop_env" &&
   ! grep -q '^PODMAN_GLOBAL_' "$desktop_env"; then
  pass "desktop profile and shared server podman policy mirror the hardened podsvc service-account contract"
else
  fail "desktop profile and shared server podman policy mirror the hardened podsvc service-account contract"
fi

if grep -q "podman \\\\" "$shared_loader" &&
   grep -q 'dbus-broker podman gitlab-runner zram-swap' "$dispatch_script"; then
  pass "late command loader wires the shared podman module through both loader paths"
else
  fail "late command loader wires the shared podman module through both loader paths"
fi

if ! grep -q '^PODMAN_ADDON_SELECTED=false$' "$ROOT_DIR/d-i/forky/scripts/late/btrfs-family.sh" &&
   ! grep -q '^PODMAN_ADDON_SELECTED=false$' "$ROOT_DIR/d-i/forky/scripts/late/f2fs-family.sh" &&
   grep -q 'PODMAN_ADDON_SELECTED=$(podman_addon_selection_state)' "$ROOT_DIR/d-i/forky/scripts/late/btrfs-family.sh" &&
   grep -q 'PODMAN_ADDON_SELECTED=$(podman_addon_selection_state)' "$ROOT_DIR/d-i/forky/scripts/late/f2fs-family.sh"; then
  pass "storage-family late hooks no longer preseed podman addon state to false before class resolution"
else
  fail "storage-family late hooks no longer preseed podman addon state to false before class resolution"
fi

if (
  set -eu
  INSTALLER_SOURCE_ROOT="$ROOT_DIR/d-i/forky"
  INSTALLER_RUNTIME_DIR="$TMP_DIR/runtime-selected-podman"
  export INSTALLER_SOURCE_ROOT INSTALLER_RUNTIME_DIR
  . "$ROOT_DIR/d-i/forky/scripts/common/lib.sh"
  installer_auto_class_tokens() {
    printf '%s\n' amd64
    printf '%s\n' intel
    printf '%s\n' generic
    printf '%s\n' nvme
  }
  installer_cmdline_value() {
    case "$1" in
      auto-install/classes|classes)
        printf '%s\n' 'lab,desktop,standard,dhcp,podman,btrfs-de'
        ;;
    esac
  }
  installer_debconf_value() { return 1; }
  installer_write_context "$ROOT_DIR/d-i/forky" >/dev/null
  . "$ROOT_DIR/d-i/forky/scripts/late/podman.sh"
  [ "$(podman_addon_selection_state)" = true ]
); then
  pass "podman addon selection state follows the resolved installer class records"
else
  fail "podman addon selection state follows the resolved installer class records"
fi

if grep -q 'PODMAN_SERVICE_USER=$PODMAN_USER' "$helper" &&
   grep -q '^podman_resolve_native_storage_driver() {$' "$helper" &&
   grep -q 'btrfs) printf.*btrfs' "$helper" &&
   grep -q 'ext2/ext3|f2fs|xfs) printf.*overlay' "$helper" &&
   grep -q 'refusing to reuse login-class account for Podman service user' "$helper" &&
   grep -q 'PODMAN_USER_HOME must not be a login home path' "$helper" &&
   grep -q 'configure_target_rootless_podman_if_selected()' "$helper" &&
   grep -q 'podman_ensure_service_subids' "$helper" &&
   grep -q ': "${PODMAN_USER_DOCKER_HOST:=1}"' "$helper" &&
   grep -q ': "${PODMAN_USER_CONTAINER_HOST:=1}"' "$helper" &&
   grep -q 'podman_chown_target_tree()' "$helper" &&
   grep -q 'podman_clear_target_dir_setgid_bits()' "$helper" &&
   grep -q 'podman_chmod_target_paths()' "$helper" &&
   grep -q 'usermod -p "!" -- "$service_user"' "$helper" &&
   grep -q '/etc/shadow' "$helper" &&
   ! grep -q 'glab-aptly' "$helper" &&
   ! grep -q 'glab-user' "$helper" &&
   ! grep -q 'passwd -l "$service_user"' "$helper" &&
   ! grep -q 'passwd -S "$service_user"' "$helper" &&
   grep -q 'PODMAN_ROOTLESS_CONTAINERS_CONFIG_DIR="${PODMAN_ROOTLESS_CONFIG_ROOT}/containers"' "$helper" &&
   grep -q 'PODMAN_ROOTLESS_QUADLET_DIR="${PODMAN_ROOTLESS_CONTAINERS_CONFIG_DIR}/systemd"' "$helper" &&
   grep -q 'PODMAN_ROOTLESS_RUNTIME_DIR="/run/user/${PODMAN_SERVICE_UID}"' "$helper" &&
   grep -q 'PODMAN_ROOTLESS_RUNROOT="${PODMAN_ROOTLESS_RUNTIME_DIR}/run"' "$helper" &&
   grep -q 'PODMAN_ROOTLESS_TMPDIR="${PODMAN_ROOTLESS_RUNTIME_LIBPOD_DIR}/tmp"' "$helper" &&
   grep -q 'find "/target${target_path}" -type d -exec chmod g-s {} +' "$helper" &&
   grep -q 'podman_chmod_target_paths 0700 \\' "$helper" &&
   grep -q 'PODMAN_SERVICE_HOME_MODE=0711' "$helper" &&
   grep -q 'install -d -m "$PODMAN_SERVICE_HOME_MODE" "/target${PODMAN_SERVICE_HOME}"' "$helper" &&
   grep -q 'managed Podman user daemon requires PODMAN_USER_LINGER=1' "$helper" &&
   grep -q 'PODMAN_EFFECTIVE_USER_DAEMON=1' "$helper" &&
   grep -q 'PODMAN_EFFECTIVE_USER_API_ENV=1' "$helper" &&
   grep -q 'Podman addon must not stage rootful /etc/containers/containers.conf' "$helper"; then
  pass "podman helper enforces the hardened service user, unique subids, managed roots, and rootless runtime-path policy"
else
  fail "podman helper enforces the hardened service user, unique subids, managed roots, and rootless runtime-path policy"
fi

if grep -q '^podman_runtime_stage_stamp() {$' "$helper" &&
   grep -Fq '[ -e "$target_abs_path" ] || [ -L "$target_abs_path" ] || continue' "$helper" &&
   grep -Fq 'managed rootless Podman already staged earlier in this install for service user=${PODMAN_SERVICE_USER}; skipping duplicate late_command run' "$helper" &&
   grep -Fq 'podman_mark_runtime_stage_complete "$PODMAN_SERVICE_USER"' "$helper"; then
  pass "podman helper survives repeated late_command runs by guarding missing link chown calls and stamping completed service-user staging"
else
  fail "podman helper survives repeated late_command runs by guarding missing link chown calls and stamping completed service-user staging"
fi

if grep -q 'containers/systemd/container.d/10-podman-managed.conf.tmpl' "$helper" &&
   grep -q 'podman-rootless.slice.tmpl' "$helper" &&
   grep -q 'podman-api-env.service.tmpl' "$helper" &&
   grep -q '90-podman-api.conf.tmpl' "$helper" &&
   grep -q 'data/config/podman/templates/podbin/user.env.tmpl' "$helper"; then
  pass "podman helper stages Quadlet and user-manager assets from managed target templates"
else
  fail "podman helper stages Quadlet and user-manager assets from managed target templates"
fi

if grep -q '^podman_render_registries_conf_file() {$' "$helper" &&
   grep -q 'podman_render_registries_conf_file "/target${PODMAN_ROOTLESS_CONTAINERS_CONFIG_DIR}/registries.conf"' "$helper" &&
   ! grep -q 'registries.conf.tmpl' "$helper"; then
  pass "podman helper renders registries.conf directly instead of shipping unresolved multiline placeholders"
else
  fail "podman helper renders registries.conf directly instead of shipping unresolved multiline placeholders"
fi

if grep -q '^podman_target_relative_path() {$' "$helper" &&
   grep -q '^podman_prepare_openssl_backend() {$' "$helper" &&
   grep -q '^podman_write_rand_hex_file() {$' "$helper" &&
   grep -Fq 'test_in_target test -x /usr/bin/openssl' "$helper" &&
   grep -Fq 'attempt_in_target "$label" /bin/sh -c ' "$helper" &&
   grep -Fq 'hex=$(openssl rand -hex "$bytes" 2>/dev/null || true)' "$helper" &&
   grep -Fq 'hex=$(od -An -N "$bytes" -tx1 /dev/urandom 2>/dev/null | tr -d " \n" || true)' "$helper" &&
   grep -Fq 'podman_write_rand_hex_file "generate Podman TLS passphrase" 32 "$passphrase_path"' "$helper" &&
   grep -Fq 'podman_run_openssl_quiet "generate Podman TLS CA key" genpkey \' "$helper" &&
   grep -Fq 'podman_run_openssl_quiet "generate Podman TLS server certificate for ${registry}" x509 -req \' "$helper"; then
  pass "podman helper falls back to target OpenSSL when the installer environment lacks the binary"
else
  fail "podman helper falls back to target OpenSSL when the installer environment lacks the binary"
fi

if grep -Fq 'tmp_output_path="${output_dir}/.$(basename "$output_path").tmp.$$"' "$helper" &&
   grep -Fq '[ -s "$tmp_output_path" ] || {' "$helper" &&
   grep -Fq 'podman_fatal "${label} produced an empty file"' "$helper" &&
   grep -Fq 'mv -f "$tmp_output_path" "$output_path"' "$helper" &&
   grep -Fq 'if [ ! -s "$passphrase_path" ]; then' "$helper"; then
  pass "podman helper regenerates an empty TLS passphrase file and replaces it atomically"
else
  fail "podman helper regenerates an empty TLS passphrase file and replaces it atomically"
fi

if (
  set -eu
  TMP_CASE_DIR=$(mktemp -d "${TMPDIR:-/tmp}/podman-empty-openssl.XXXXXX")
  trap 'rm -rf "$TMP_CASE_DIR"' EXIT HUP INT TERM
  mkdir -p "$TMP_CASE_DIR/bin"
  cat >"$TMP_CASE_DIR/bin/openssl" <<'EOF'
#!/bin/sh
if [ "$1" = rand ] && [ "$2" = -hex ]; then
  exit 0
fi
printf 'unexpected openssl args: %s\n' "$*" >&2
exit 1
EOF
  cat >"$TMP_CASE_DIR/bin/od" <<'EOF'
#!/bin/sh
printf ' ca fe f0 0d\n'
EOF
  chmod +x "$TMP_CASE_DIR/bin/openssl" "$TMP_CASE_DIR/bin/od"
  PATH="$TMP_CASE_DIR/bin:$PATH"
  installer_fatal() {
    printf 'fatal:%s\n' "$*" >&2
    exit 1
  }
  . "$ROOT_DIR/d-i/forky/scripts/late/podman.sh"
  PASSFILE="$TMP_CASE_DIR/passphrase.txt"
  : >"$PASSFILE"
  PODMAN_OPENSSL_BACKEND=installer
  podman_write_rand_hex_file "empty openssl fallback" 4 "$PASSFILE"
  [ -s "$PASSFILE" ]
  grep -qx 'cafef00d' "$PASSFILE"
); then
  pass "podman helper rewrites an empty passphrase file when openssl returns success with no output"
else
  fail "podman helper rewrites an empty passphrase file when openssl returns success with no output"
fi

if grep -q '^\[Service\]$' "$quadlet_dropin" &&
   grep -q '^TimeoutStartSec=900$' "$quadlet_dropin" &&
   grep -q '__INSTALLER_PODMAN_SERVICE_SLICE_LINE__' "$quadlet_dropin"; then
  pass "quadlet container drop-in applies managed startup and slice policy"
else
  fail "quadlet container drop-in applies managed startup and slice policy"
fi

if ! grep -q '^CPUAccounting=' "$podman_slice" &&
   grep -q '^CPUWeight=__INSTALLER_PODMAN_SERVICE_SLICE_CPU_WEIGHT__$' "$podman_slice" &&
   grep -q '^IOWeight=__INSTALLER_PODMAN_SERVICE_SLICE_IO_WEIGHT__$' "$podman_slice" &&
   grep -q '^TasksMax=__INSTALLER_PODMAN_SERVICE_SLICE_TASKS_MAX__$' "$podman_slice" &&
   grep -q '^Delegate=true$' "$podman_service_dropin" &&
   grep -q '^UnsetEnvironment=DOCKER_HOST CONTAINER_HOST$' "$podman_service_dropin" &&
   grep -q '^ExecStart=$' "$podman_service_dropin" &&
   grep -q '^ExecStart=/usr/bin/podman \$LOGGING system service --time=0$' "$podman_service_dropin" &&
   grep -q '__INSTALLER_PODMAN_SERVICE_SLICE_LINE__' "$podman_service_dropin"; then
  pass "podman service limits are bound to a dedicated rootless slice without removed CPUAccounting and the API backend stays pinned without an idle timeout"
else
  fail "podman service limits are bound to a dedicated rootless slice without removed CPUAccounting and the API backend stays pinned without an idle timeout"
fi

if grep -q '^__INSTALLER_PODMAN_API_SERVICE_ENVIRONMENT_LINES__$' "$podman_env_service" &&
   grep -q '^Description=Managed rootless Podman API environment for __INSTALLER_PODMAN_SERVICE_USER__$' "$podman_env_service" &&
   grep -q '^ExecStart=/usr/bin/systemctl --user set-environment __INSTALLER_PODMAN_API_SET_ENV_ARGS__$' "$podman_env_service" &&
   grep -q '^ExecStop=/usr/bin/systemctl --user unset-environment __INSTALLER_PODMAN_API_UNSET_ENV_NAMES__$' "$podman_env_service" &&
   grep -q '^ExecStart=/usr/bin/systemctl --user set-environment BUILDAH_ISOLATION=__INSTALLER_PODMAN_ROOTLESS_BUILDAH_ISOLATION__ BUILDAH_TMPDIR=__INSTALLER_PODMAN_ROOTLESS_BUILDAH_TMPDIR__$' "$buildah_env_service" &&
   ! grep -q '/bin/sh -lc' "$podman_env_service" &&
   ! grep -q '/bin/sh -lc' "$buildah_env_service" &&
   grep -q '^__INSTALLER_PODMAN_API_ENV_FILE_LINES__$' "$podman_env_file"; then
  pass "server socket compatibility exports both DOCKER_HOST and CONTAINER_HOST without shell wrappers"
else
  fail "server socket compatibility exports both DOCKER_HOST and CONTAINER_HOST without shell wrappers"
fi

if grep -q '^kernel\.unprivileged_userns_clone=__INSTALLER_PODMAN_ROOTLESS_USERNS_CLONE__$' "$podman_sysctl" &&
   grep -q '^user\.max_user_namespaces=__INSTALLER_PODMAN_ROOTLESS_MAX_USER_NAMESPACES__$' "$podman_sysctl" &&
   grep -q '^ExecStart=/usr/bin/loginctl enable-linger __INSTALLER_PODMAN_SERVICE_USER__$' "$podman_linger_unit" &&
   grep -q '^  : "\${PODMAN_LINGER_MARKER:=/usr/local/lib/podman/podman-rootless-linger\.done}"$' "$helper" &&
   grep -q 'runuser -u __INSTALLER_PODMAN_SERVICE_USER__ -- /usr/bin/env HOME=__INSTALLER_PODMAN_SERVICE_HOME__ XDG_RUNTIME_DIR=/run/user/__INSTALLER_PODMAN_SERVICE_UID__' "$podman_linger_unit" &&
   grep -q '/usr/bin/systemctl --user start __INSTALLER_PODMAN_API_START_UNITS__' "$podman_linger_unit" &&
   grep -q '^ConditionPathExists=!__INSTALLER_PODMAN_LINGER_MARKER__$' "$podman_linger_unit"; then
  pass "server lingering and rootless userns tuning are staged from managed target templates"
else
  fail "server lingering and rootless userns tuning are staged from managed target templates"
fi

if grep -q '^PODBIN_KEY_DIR="__INSTALLER_PODBIN_KEY_DIR__"$' "$podbin_default" &&
   grep -q '^PODBIN_KEY_NAME="__INSTALLER_PODBIN_KEY_NAME__"$' "$podbin_default" &&
   grep -q '^PODBIN_TEMPLATE_DIR="__INSTALLER_PODBIN_TEMPLATE_DIR__"$' "$podbin_default" &&
   grep -q '^PODBIN_STORAGE_DRIVER="__INSTALLER_PODBIN_STORAGE_DRIVER__"$' "$podbin_default" &&
   grep -q '^PODBIN_SERVICE_USER="__INSTALLER_PODBIN_SERVICE_USER__"$' "$podbin_default" &&
   grep -q '^PODBIN_DEFAULT_IMAGE="__INSTALLER_PODBIN_DEFAULT_IMAGE__"$' "$podbin_default" &&
   grep -q '^PODBIN_RUNTIME_USER_NAME="__INSTALLER_PODBIN_RUNTIME_USER_NAME__"$' "$podbin_default" &&
   grep -q '^PODBIN_RUNTIME_AUTH_KEYS_DIR="__INSTALLER_PODBIN_RUNTIME_AUTH_KEYS_DIR__"$' "$podbin_default" &&
   grep -q '^PODBIN_KNOWN_HOSTS_FILE="__INSTALLER_PODBIN_KNOWN_HOSTS_FILE__"$' "$podbin_default" &&
   grep -Fq ': "${PODBIN_KEY_DIR:=/data/pki/ssh/podbin}"' "$helper" &&
   grep -Fq ': "${PODBIN_KEY_NAME:=podbin_ed25519}"' "$helper" &&
   grep -q ': "${PODBIN_SERVICE_USER:=$PODMAN_SERVICE_USER}"' "$helper" &&
   grep -q ': "${PODBIN_DEFAULT_IMAGE:=localhost/podbin-runtime:trixie}"' "$helper" &&
   grep -q ': "${PODBIN_RUNTIME_USER_NAME:=poduser}"' "$helper" &&
   grep -q ': "${PODBIN_DEFAULT_CONTAINER_SSH_USER:=$PODBIN_RUNTIME_USER_NAME}"' "$helper" &&
   grep -q 'PODBIN_TEMPLATE_DIR=$PODBIN_TEMPLATE_DIR' "$helper" &&
   grep -q 'PODBIN_STORAGE_DRIVER=$PODBIN_STORAGE_DRIVER' "$helper" &&
   grep -q 'stage_target_helper_docs podbin.md podbin-service-bridge.md' "$helper" &&
   [ -r "$podbin_doc" ] &&
   [ -r "$podbin_service_bridge_doc" ] &&
   grep -q '/usr/local/sbin/podbin --ensure-keypair _' "$helper" &&
   grep -q 'PODBIN_KEY_DIR must remain /data/pki/ssh/podbin' "$helper" &&
   grep -q '/data/pki/ssh/podbin/podbin_ed25519' "$podbin_doc" &&
   grep -q 'safe_install_dir 0700 "\$PODBIN_SERVICE_USER" "\$PODBIN_SERVICE_USER" "\$PODBIN_KEY_DIR"' "$podbin_wrapper" &&
   grep -q 'chown "\$PODBIN_SERVICE_UID:\$PODBIN_SERVICE_GID" "\$key_path" "\${key_path}.pub"' "$podbin_wrapper"; then
  pass "podbin defaults render the managed non-root image and host SSH policy through an isolated Podbin-only SSH key directory"
else
  fail "podbin defaults render the managed non-root image and host SSH policy through an isolated Podbin-only SSH key directory"
fi

if [ -r "$podbin_wrapper" ] &&
   grep -q 'Usage:' "$podbin_wrapper" &&
   grep -q -- '--create-user' "$podbin_wrapper" &&
   grep -q -- '--create-container' "$podbin_wrapper" &&
   grep -q -- '--delete-container' "$podbin_wrapper" &&
   grep -q -- '--start-container' "$podbin_wrapper" &&
   grep -q -- '--stop-container' "$podbin_wrapper" &&
   grep -q -- '--restart-container' "$podbin_wrapper" &&
   grep -q -- '--enable-container' "$podbin_wrapper" &&
   grep -q -- '--disable-container' "$podbin_wrapper" &&
   grep -q -- '--logs-container' "$podbin_wrapper" &&
   grep -q -- '--inspect-container' "$podbin_wrapper" &&
   grep -q -- '--connect-container' "$podbin_wrapper" &&
   grep -q -- '--open-container' "$podbin_wrapper" &&
   grep -q -- '--list-images' "$podbin_wrapper" &&
   grep -q -- '--list-volumes' "$podbin_wrapper" &&
   grep -q -- '--list-networks' "$podbin_wrapper" &&
   grep -q -- '--list-pods' "$podbin_wrapper" &&
   grep -q -- '--prune-all' "$podbin_wrapper" &&
   grep -q -- '--user-podman' "$podbin_wrapper" &&
   grep -q -- 'podbin --create-container <username> \[container\]' "$podbin_wrapper" &&
   grep -q 'requested_container=\${2:-}' "$podbin_wrapper" &&
   grep -q 'create_container "\$@"' "$podbin_wrapper" &&
   grep -q -- '--wipe-all' "$podbin_wrapper" &&
   grep -q '/data/docs/podbin.md' "$podbin_wrapper" &&
   grep -q 'PODBIN_PORT_SCAN_START' "$podbin_wrapper" &&
   grep -q 'require_high_port "host SSH port"' "$podbin_wrapper" &&
   grep -q 'refusing reserved Podman service account name' "$podbin_wrapper" &&
   grep -q 'PODBIN_USER_MANAGER_READY_UIDS' "$podbin_wrapper" &&
   grep -q 'ensure_runtime_image()' "$podbin_wrapper" &&
   grep -q 'ensure_known_hosts_file()' "$podbin_wrapper" &&
   grep -q ': "${PODBIN_RUNTIME_USER_NAME:=poduser}"' "$podbin_wrapper" &&
   grep -q ': "${PODBIN_DEFAULT_CONTAINER_SSH_USER:=$PODBIN_RUNTIME_USER_NAME}"' "$podbin_wrapper" &&
   grep -q 'exec --user "${PODBIN_RUNTIME_USER_UID}:${PODBIN_RUNTIME_USER_GID}"' "$podbin_wrapper" &&
   grep -q '^load_managed_user() {$' "$podbin_wrapper" &&
   grep -q 'system reset --force' "$podbin_wrapper" &&
   grep -q 'managed Podman config is incomplete for \$user; skipping system reset' "$podbin_wrapper" &&
   grep -q 'userdel -- "\$user"' "$podbin_wrapper" &&
   grep -q 'groupdel -- "\$wipe_group"' "$podbin_wrapper" &&
   ! grep -q 'prompt "Container SSH user"' "$podbin_wrapper" &&
   ! grep -q 'prompt "Container authorized_keys directory"' "$podbin_wrapper" &&
   ! grep -q 'prompt "Container shell"' "$podbin_wrapper" &&
   ! grep -q 'prompt "Container runtime user uid' "$podbin_wrapper" &&
   ! grep -q 'validate_container_user()' "$podbin_wrapper" &&
   ! grep -q 'PODBIN_RUN_USER' "$podbin_wrapper" &&
   ! grep -q -- '--user 0' "$podbin_wrapper"; then
  pass "podbin wrapper exposes the lifecycle controls while fixing the interactive contract to the managed non-root runtime user"
else
  fail "podbin wrapper exposes the lifecycle controls while fixing the interactive contract to the managed non-root runtime user"
fi

if [ -r "$podbin_template_dir/containers.conf.tmpl" ] &&
   [ -r "$podbin_template_dir/storage.conf.tmpl" ] &&
   [ -r "$podbin_template_dir/registries.conf" ] &&
   [ -r "$podbin_template_dir/systemd/user/podbin-rootless.slice" ] &&
   [ -r "$podbin_template_dir/systemd/users/container.d/10-podbin-managed.conf" ] &&
   [ -r "$podbin_template_dir/systemd/users/container.container.tmpl" ] &&
   [ -r "$podbin_template_dir/metadata.env.tmpl" ] &&
   grep -q '^tmp_dir = "__PODBIN_RUNTIME_TMP_DIR__"$' "$podbin_template_dir/containers.conf.tmpl" &&
   grep -q '^driver = "__PODBIN_STORAGE_DRIVER__"$' "$podbin_storage_template" &&
   grep -q '^runroot = "__PODBIN_RUN_ROOT__"$' "$podbin_storage_template" &&
   ! grep -q 'fuse-overlayfs\|mount_program' "$podbin_storage_template" &&
   ! grep -q 'fuse-overlayfs\|mount_program' "$rootless_storage_template" &&
   grep -q 'data/config/podman/templates/podbin/containers.conf.tmpl' "$helper" &&
   grep -q 'PODMAN_ROOTLESS_IMAGE_TMPDIR' "$helper" &&
   grep -q 'native rootless OverlayFS' "$helper" &&
   grep -q 'install_template containers.conf.tmpl' "$podbin_wrapper" &&
   grep -q 'mktemp "\${PODBIN_WORK_DIR}/template-render.XXXXXX"' "$podbin_wrapper" &&
   grep -q '^User=__PODBIN_RUNTIME_USER_UID__:__PODBIN_RUNTIME_USER_GID__$' "$podbin_template_dir/systemd/users/container.container.tmpl" &&
   grep -q '^Tmpfs=/tmp:rw,mode=1777$' "$podbin_template_dir/systemd/users/container.container.tmpl" &&
   grep -q '^Tmpfs=/run/sshd:rw,mode=0755,uid=__PODBIN_RUNTIME_USER_UID__,gid=__PODBIN_RUNTIME_USER_GID__$' "$podbin_template_dir/systemd/users/container.container.tmpl" &&
   grep -q '^Tmpfs=/var/tmp:rw,mode=1777$' "$podbin_template_dir/systemd/users/container.container.tmpl" &&
   grep -q '^Tmpfs=__PODBIN_RUNTIME_USER_HOME__:rw,mode=0700,uid=__PODBIN_RUNTIME_USER_UID__,gid=__PODBIN_RUNTIME_USER_GID__$' "$podbin_template_dir/systemd/users/container.container.tmpl" &&
   grep -q '^Tmpfs=__PODBIN_RUNTIME_WORKDIR__:rw,mode=0755,uid=__PODBIN_RUNTIME_USER_UID__,gid=__PODBIN_RUNTIME_USER_GID__$' "$podbin_template_dir/systemd/users/container.container.tmpl" &&
   ! grep -q '^AddCapability=' "$podbin_template_dir/systemd/users/container.container.tmpl" &&
   ! grep -q 'cat >.*containers.conf' "$podbin_wrapper" &&
   ! grep -q 'cat >.*storage.conf' "$podbin_wrapper" &&
   ! grep -q 'cat >.*container.*[.]container' "$podbin_wrapper"; then
  pass "podbin renders managed config exclusively from shared target templates"
else
  fail "podbin renders managed config exclusively from shared target templates"
fi

podbin_function_prelude="$TMP_DIR/podbin-functions.sh"
awk '/^\[ "\$#" -ge 1 \] \|\| \{/ { exit } { print }' "$podbin_wrapper" >"$podbin_function_prelude"

if (
  TEST_ROOT="$TMP_DIR/user-home-base"
  PODBIN_DEFAULTS_FILE="$TEST_ROOT/missing-defaults"
  PODBIN_WORK_DIR="$TEST_ROOT/run"
  PODBIN_SERVICE_HOME="$TEST_ROOT/service-home"
  PODBIN_USER_HOME_BASE="$PODBIN_SERVICE_HOME/users"
  export PODBIN_DEFAULTS_FILE PODBIN_WORK_DIR PODBIN_SERVICE_HOME PODBIN_USER_HOME_BASE
  install -d -m 0700 "$PODBIN_WORK_DIR" "$PODBIN_SERVICE_HOME"
  . "$podbin_function_prelude"
  load_service_user() {
    PODBIN_SERVICE_USER=$(id -un)
    PODBIN_SERVICE_GROUP=$(id -gn)
    export PODBIN_SERVICE_USER PODBIN_SERVICE_GROUP
  }
  safe_install_dir() {
    install -d -m "$1" "$4"
  }
  ensure_user_home_base
  [ "$(stat -c '%a' "$PODBIN_SERVICE_HOME")" = 711 ] &&
    [ "$(stat -c '%a' "$PODBIN_USER_HOME_BASE")" = 711 ]
); then
  pass "podbin keeps nested workload homes traversable without making service directories listable"
else
  fail "podbin keeps nested workload homes traversable without making service directories listable"
fi

if (
  TEST_ROOT="$TMP_DIR/template-render"
  PODBIN_DEFAULTS_FILE="$TEST_ROOT/missing-defaults"
  PODBIN_WORK_DIR="$TEST_ROOT/run"
  PODBIN_TEMPLATE_DIR="$TEST_ROOT/templates"
  export PODBIN_DEFAULTS_FILE PODBIN_WORK_DIR PODBIN_TEMPLATE_DIR
  install -d "$PODBIN_WORK_DIR" "$PODBIN_TEMPLATE_DIR"
  printf 'value=__VALUE__\n' >"$PODBIN_TEMPLATE_DIR/sample.tmpl"
  . "$podbin_function_prelude"
  install_template sample.tmpl "$TEST_ROOT/rendered.conf" 0644 "$(id -un)" "$(id -gn)" VALUE native-overlay
  grep -qx 'value=native-overlay' "$TEST_ROOT/rendered.conf"
); then
  pass "podbin template rendering uses isolated work files without clobbering caller variables"
else
  fail "podbin template rendering uses isolated work files without clobbering caller variables"
fi

if (
  TEST_ROOT="$TMP_DIR/service-record"
  PODBIN_DEFAULTS_FILE="$TEST_ROOT/missing-defaults"
  PODBIN_WORK_DIR="$TEST_ROOT/run"
  export PODBIN_DEFAULTS_FILE PODBIN_WORK_DIR
  install -d "$PODBIN_WORK_DIR"
  . "$podbin_function_prelude"
  login_value() {
    printf '%s\n' 1000
  }
  getent() {
    case "$1:$2" in
      passwd:podsvc) printf '%s\n' 'podsvc:x:999:999:Managed Podman:/data/accounts/podman:/usr/sbin/nologin' ;;
      group:999) printf '%s\n' 'podsvc:x:999:' ;;
      *) return 2 ;;
    esac
  }
  PODBIN_SERVICE_USER=podsvc
  PODBIN_USER_NAME=alice
  PODBIN_USER_UID=995
  PODBIN_USER_GID=995
  PODBIN_USER_HOME=/data/accounts/podman/users/alice
  PODBIN_USER_GROUP=alice
  PODBIN_KEY_DIR="$TEST_ROOT/keys"
  safe_install_dir() {
    install -d -m "$1" "$4"
  }
  chown() {
    :
  }
  install -d "$PODBIN_KEY_DIR"
  : >"$PODBIN_KEY_DIR/$PODBIN_KEY_NAME"
  : >"$PODBIN_KEY_DIR/$PODBIN_KEY_NAME.pub"
  ensure_keypair
  [ "$PODBIN_USER_NAME" = alice ] &&
    [ "$PODBIN_USER_UID" = 995 ] &&
    [ "$PODBIN_USER_HOME" = /data/accounts/podman/users/alice ] &&
    [ "$PODBIN_SERVICE_UID" = 999 ] &&
    [ "$PODBIN_SERVICE_HOME" = /data/accounts/podman ]
); then
  pass "preparing the podsvc keypair does not overwrite the selected Podbin workload user"
else
  fail "preparing the podsvc keypair does not overwrite the selected Podbin workload user"
fi

if (
  TEST_ROOT="$TMP_DIR/storage-driver"
  PODBIN_DEFAULTS_FILE="$TEST_ROOT/missing-defaults"
  PODBIN_WORK_DIR="$TEST_ROOT/run"
  export PODBIN_DEFAULTS_FILE PODBIN_WORK_DIR
  install -d "$PODBIN_WORK_DIR" "$TEST_ROOT/storage"
  . "$podbin_function_prelude"
  stat() {
    printf '%s\n' btrfs
  }
  [ "$(resolve_native_storage_driver auto "$TEST_ROOT/storage")" = btrfs ]
  stat() {
    printf '%s\n' ext2/ext3
  }
  [ "$(resolve_native_storage_driver auto "$TEST_ROOT/storage")" = overlay ]
); then
  pass "podbin selects native btrfs or kernel overlay storage from the backing filesystem"
else
  fail "podbin selects native btrfs or kernel overlay storage from the backing filesystem"
fi

if [ -r "$podbin_runtime_containerfile" ] &&
   [ -r "$podbin_runtime_entrypoint" ] &&
   [ -r "$podbin_runtime_sshd" ] &&
   grep -q '^FROM docker.io/library/debian:trixie-slim$' "$podbin_runtime_containerfile" &&
   grep -q 'openssh-server' "$podbin_runtime_containerfile" &&
   grep -q '__INSTALLER_PODBIN_RUNTIME_USER_NAME__' "$podbin_runtime_containerfile" &&
   grep -q '__INSTALLER_PODBIN_RUNTIME_AUTH_KEYS_DIR__' "$podbin_runtime_containerfile" &&
   grep -q '^USER __INSTALLER_PODBIN_RUNTIME_USER_UID__:__INSTALLER_PODBIN_RUNTIME_USER_GID__$' "$podbin_runtime_containerfile" &&
   grep -q '^WORKDIR __INSTALLER_PODBIN_RUNTIME_WORKDIR__$' "$podbin_runtime_containerfile" &&
   grep -q 'chown __INSTALLER_PODBIN_RUNTIME_USER_UID__:__INSTALLER_PODBIN_RUNTIME_USER_GID__ /etc/ssh/ssh_host_\*_key' "$podbin_runtime_containerfile" &&
   grep -q 'COPY entrypoint.sh /usr/local/bin/podbin-entrypoint' "$podbin_runtime_containerfile" &&
   grep -q 'chmod 0755 /usr/local/bin/podbin-entrypoint' "$podbin_runtime_containerfile" &&
   grep -q 'CMD \["/usr/local/bin/podbin-entrypoint"\]' "$podbin_runtime_containerfile" &&
   grep -q '^install -d -m 0755 /run/sshd$' "$podbin_runtime_entrypoint" &&
   grep -q '^exec /usr/sbin/sshd -D -e -f /etc/ssh/sshd_config$' "$podbin_runtime_entrypoint" &&
   grep -q '^PidFile none$' "$podbin_runtime_sshd" &&
   grep -q '^PermitRootLogin no$' "$podbin_runtime_sshd" &&
   grep -q '^AllowUsers __INSTALLER_PODBIN_RUNTIME_USER_NAME__$' "$podbin_runtime_sshd" &&
   grep -q '^PasswordAuthentication no$' "$podbin_runtime_sshd" &&
   grep -q '^AuthorizedKeysFile .ssh/authorized_keys$' "$podbin_runtime_sshd" &&
   ! grep -q '__PODBIN_' "$podbin_runtime_containerfile" &&
   ! grep -q '__PODBIN_' "$podbin_runtime_sshd"; then
  pass "podbin stages a managed runtime image with a fixed non-root SSH user and root login disabled"
else
  fail "podbin stages a managed runtime image with a fixed non-root SSH user and root login disabled"
fi

if grep -Fq 'Cmnd_Alias PODBIN_DAILY_OPERATIONS' "$account_sudoers" &&
   grep -q '/usr/local/sbin/podbin --list-users' "$account_sudoers" &&
   grep -q '/usr/local/sbin/podbin --start-container \*' "$account_sudoers" &&
   grep -q '/usr/local/sbin/podbin --connect-container \*' "$account_sudoers" &&
   grep -q 'NOPASSWD: READONLY_SYSTEM_INSPECTION, PODBIN_DAILY_OPERATIONS' "$account_sudoers" &&
   ! grep -q '/usr/local/sbin/podbin --create-container \*' "$account_sudoers" &&
   ! grep -q '/usr/local/sbin/podbin --open-container \*' "$account_sudoers"; then
  pass "daily-account sudoers delegate only podbin start and connect without widening passwordless create or open access"
else
  fail "daily-account sudoers delegate only podbin start and connect without widening passwordless create or open access"
fi

if grep -q '^  podbin --import-user <username>$' "$podbin_wrapper" &&
   grep -q '^  podbin --diagnose-user <username>$' "$podbin_wrapper" &&
   grep -q '^  podbin --import-containers <username> \[container\]$' "$podbin_wrapper" &&
   grep -q '^import_user() {$' "$podbin_wrapper" &&
   grep -q '^import_existing_containers() {$' "$podbin_wrapper" &&
   grep -q 'PODBIN_BACKEND=quadlet' "$podbin_wrapper" &&
   grep -q 'PODBIN_BACKEND=podman' "$podbin_wrapper"; then
  pass "podbin exposes explicit user import, diagnostics, and existing-container adoption"
else
  fail "podbin exposes explicit user import, diagnostics, and existing-container adoption"
fi

if grep -q '^PODBIN_BACKEND=__PODBIN_BACKEND_SQ__$' "$podbin_template_dir/metadata.env.tmpl" &&
   grep -q '^PODBIN_USER_MODE=__PODBIN_USER_MODE_SQ__$' "$podbin_template_dir/user.env.tmpl" &&
   grep -q 'imported container is not Quadlet-managed' "$podbin_wrapper" &&
   grep -q 'failed to remove imported container' "$podbin_wrapper"; then
  pass "imported metadata keeps Podbin and Quadlet backends separate with safe destructive handling"
else
  fail "imported metadata keeps Podbin and Quadlet backends separate with safe destructive handling"
fi

if grep -q 'sudo -n "\$PODBIN_BINARY" --list-users' "$podbin_menu" &&
   grep -q '"Import Existing User"' "$podbin_menu" &&
   grep -q '"Diagnose User"' "$podbin_menu" &&
   grep -q '"Import Existing Containers"' "$podbin_menu" &&
   grep -q '^choose_import_user() {$' "$podbin_menu" &&
   grep -q '^prompt_new_container_name() {$' "$podbin_menu" &&
   grep -q 'launch_podbin_terminal --create-container "\$user" "\$container"' "$podbin_menu" &&
   grep -q '^choose_service_container() {$' "$podbin_menu" &&
   grep -q '"Inspect Service Container"' "$podbin_menu" &&
   grep -q '"Show Podman Socket Unit"' "$podbin_menu" &&
   grep -q '"Show Podman Service Properties"' "$podbin_menu" &&
   grep -q '"Enable Podman Service"' "$podbin_menu" &&
   grep -q '"Follow Podman Socket Logs"' "$podbin_menu" &&
   grep -q '^  /dev/tty rw,$' "$apparmor_profile" &&
   grep -q 'awk,cat,gawk,getent,grep,id,less' "$apparmor_profile" &&
   grep -q '^  /usr/bin/sudo PUx,$' "$apparmor_profile" &&
   grep -q '^  /usr/local/sbin/podbin rPx -> managed-podbin,$' "$apparmor_profile"; then
  pass "Labwc Container Management can discover, import, diagnose, and adopt designated users"
else
  fail "Labwc Container Management can discover, import, diagnose, and adopt designated users"
fi

if grep -q 'rootless Podman state/config directory or a subordinate UID entry' "$podbin_doc" &&
   grep -q 'Quadlet enable/disable and the managed SSH connector' "$podbin_doc" &&
   grep -q 'podbin --diagnose-user' "$podbin_doc"; then
  pass "Podbin documentation records import boundaries and troubleshooting actions"
else
  fail "Podbin documentation records import boundaries and troubleshooting actions"
fi

if (
  fake_bin="$TMP_DIR/podbin-menu-bin"
  fake_step="$TMP_DIR/podbin-menu-step"
  fake_log="$TMP_DIR/podbin-menu-log"
  install -d "$fake_bin"
  printf '0\n' >"$fake_step"
  cat >"$fake_bin/sudo" <<'EOF'
#!/bin/sh
if [ "${1:-}" = -n ]; then
  shift
fi
case "$*" in
  *--list-users)
    printf 'alice\tuid=950\thome=/data/accounts/podman/users/alice\tmode=managed\n'
    ;;
  *)
    printf '%s\n' "$*" >>"${FAKE_LOG:?}"
    ;;
esac
EOF
  cat >"$fake_bin/labwc-fuzzel" <<'EOF'
#!/bin/sh
step=$(cat "${FAKE_STEP:?}")
next=$((step + 1))
printf '%s\n' "$next" >"${FAKE_STEP:?}"
case "$step" in
  0) printf ' Containers\n' ;;
  1) printf 'alice\n' ;;
  2) printf 'Create Container\n' ;;
  3) printf 'demo\n' ;;
  *) printf 'Exit\n' ;;
esac
EOF
  cat >"$fake_bin/getent" <<'EOF'
#!/bin/sh
[ "${1:-}" = passwd ] || exit 1
printf 'alice:x:950:950::/data/accounts/podman/users/alice:/usr/sbin/nologin\n'
EOF
  cat >"$fake_bin/labwc-terminal" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"${FAKE_LOG:?}"
EOF
  chmod 0755 "$fake_bin/sudo" "$fake_bin/labwc-fuzzel" "$fake_bin/getent" "$fake_bin/labwc-terminal"
  FAKE_STEP="$fake_step" \
    FAKE_LOG="$fake_log" \
    PATH="$fake_bin:$PATH" \
    sh "$podbin_menu"
  grep -Fq -- '-e /usr/local/bin/labwc-podman-menu _run --create-container alice demo' "$fake_log"
); then
  pass "Container Management dispatches the Fuzzel-guided container name into the terminal-backed create action"
else
  fail "Container Management dispatches the Fuzzel-guided container name into the terminal-backed create action"
fi

[ "$FAIL_COUNT" -eq 0 ]
