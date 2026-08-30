#!/bin/sh
set -eu

target_root=${1:-/target}
[ -d "$target_root" ] || exit 0

ch341a_fatal() {
  printf 'fatal: %s\n' "$*" >&2
  exit 1
}

ch341a_info() {
  printf '[late:ch341a] %s\n' "$*" >&2
}

target_passwd_ids() {
  awk -F: -v wanted_user="$1" '$1 == wanted_user { print $3 ":" $4; exit }' "${target_root}/etc/passwd" 2>/dev/null || true
}

ch341a_validate_abs_path() {
  case "${2:-}" in
    /*) ;;
    *) ch341a_fatal "$1 must be an absolute path: ${2:-unset}" ;;
  esac
  case "$2" in
    /|*..*|*//*|*[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._/@%:+,-]*)
      ch341a_fatal "$1 contains unsupported path syntax: $2"
      ;;
  esac
}

ch341a_stage_target_asset() {
  repo_path=$1
  target_path=$2
  mode=$3
  tmp_asset="${tmp_env_dir}/$(basename "$target_path").$$"
  target_host_path="${target_root}${target_path}"

  ch341a_validate_abs_path "target path" "$target_path"
  bootstrap_fetch_seed_file "$seed_base" "$repo_path" "$tmp_asset" 0600 "ch341a asset ${repo_path}"
  install -d -m 0755 "${target_root}$(dirname "$target_path")"
  install -m "$mode" "$tmp_asset" "$target_host_path"
  chmod "$mode" "$target_host_path"
  rm -f "$tmp_asset"
}

ch341a_render_target_asset() {
  repo_path=$1
  target_path=$2
  mode=$3
  shift 3
  tmp_asset="${tmp_env_dir}/$(basename "$target_path").$$"
  tmp_rendered="${tmp_asset}.rendered"
  target_host_path="${target_root}${target_path}"

  ch341a_validate_abs_path "target path" "$target_path"
  bootstrap_fetch_seed_file "$seed_base" "$repo_path" "$tmp_asset" 0600 "ch341a template ${repo_path}"
  installer_apply_scalar_placeholders "$tmp_asset" "$tmp_rendered" "$@"
  installer_assert_no_unresolved_installer_placeholders "$tmp_rendered" "ch341a template ${repo_path}"
  install -d -m 0755 "${target_root}$(dirname "$target_path")"
  install -m "$mode" "$tmp_rendered" "$target_host_path"
  chmod "$mode" "$target_host_path"
  rm -f "$tmp_asset" "$tmp_rendered"
}

runtime_env_path() {
  for candidate in /tmp/install-env/runtime.env /tmp/install-runtime/state/runtime.env; do
    [ -r "$candidate" ] || continue
    printf '%s\n' "$candidate"
    return 0
  done
  return 1
}

runtime_dir=${INSTALLER_RUNTIME_DIR:-/tmp/install-runtime}
bootstrap_lib=${INSTALLER_BOOTSTRAP_LIB:-${runtime_dir}/bootstrap/bootstrap.sh}
tmp_env_dir=${INSTALLER_LATE_TMP_ENV_DIR:-/tmp/install-env-late/ch341a}

[ -s "$bootstrap_lib" ] || ch341a_fatal "installer bootstrap library is unavailable: ${bootstrap_lib}"
# shellcheck disable=SC1090,SC1091
. "$bootstrap_lib"
bootstrap_source_common_lib "" || ch341a_fatal "failed to source installer common library"
seed_base=$(installer_current_seed_base 2>/dev/null || installer_seed_base "")
bootstrap_source_common_support_libs "$seed_base" "$tmp_env_dir" fetch hook target || {
  ch341a_fatal "failed to source installer late support libraries"
}
installer_ensure_context_loaded "$seed_base"

installer_selected_class_reference_is_selected addon/ch341a 2>/dev/null || exit 0

account_env=${INSTALLER_LATE_ACCOUNT_ENV:-/tmp/install-env-late/account.env}
host_env=${INSTALLER_LATE_HOST_ENV:-/tmp/install-env-late/host.env}
[ -r "$account_env" ] || installer_fetch_account_env "$seed_base" "$account_env" 0600
[ -r "$host_env" ] || installer_fetch_host_env "$seed_base" "$(installer_resolve_host_profile "")" "$host_env" 0600

# shellcheck disable=SC1090,SC1091
. "$account_env"
# shellcheck disable=SC1090,SC1091
. "$host_env"

if runtime_env=$(runtime_env_path); then
  # shellcheck disable=SC1090,SC1091
  . "$runtime_env"
fi

: "${ACCOUNT_USERNAME:?ACCOUNT_USERNAME must be set before staging ch341a assets}"
: "${DIR_POOL_FIRMWARE:=/pool/firmware}"
ch341a_validate_abs_path "DIR_POOL_FIRMWARE" "$DIR_POOL_FIRMWARE"

run_in_target "create ch341a authorization group" /bin/sh -eu -c '
command -v getent >/dev/null 2>&1
command -v groupadd >/dev/null 2>&1
getent group usbadmin >/dev/null 2>&1 ||
  groupadd --system usbadmin
getent group usbadmin >/dev/null 2>&1
' sh

ch341a_stage_target_asset \
  "$(installer_repo_join_var DIR_HOOKS_ROLE_DESKTOP target/etc/udev/rules.d/61-ch341a-programmers.rules)" \
  /etc/udev/rules.d/61-ch341a-programmers.rules \
  0644

ch341a_render_target_asset \
  "$(installer_repo_join_var DIR_HOOKS_ROLE_DESKTOP target/etc/tmpfiles.d/86-firmware-workspace.conf.tmpl)" \
  /etc/tmpfiles.d/86-firmware-workspace.conf \
  0644 \
  ACCOUNT_USERNAME "$ACCOUNT_USERNAME" \
  DIR_POOL_FIRMWARE "$DIR_POOL_FIRMWARE"

ch341a_render_target_asset \
  "$(installer_repo_join_var DIR_HOOKS_ROLE_DESKTOP target/etc/skel/.profile.d/75-firmware-workspace.sh.tmpl)" \
  /etc/skel/.profile.d/75-firmware-workspace.sh \
  0644 \
  DIR_POOL_FIRMWARE "$DIR_POOL_FIRMWARE"

if [ -n "${ACCOUNT_HOME:-}" ]; then
  ch341a_validate_abs_path "ACCOUNT_HOME" "$ACCOUNT_HOME"
  install -d -m 0700 "${target_root}${ACCOUNT_HOME}/.profile.d"
  install -m 0644 \
    "${target_root}/etc/skel/.profile.d/75-firmware-workspace.sh" \
    "${target_root}${ACCOUNT_HOME}/.profile.d/75-firmware-workspace.sh"
  account_ids=$(target_passwd_ids "$ACCOUNT_USERNAME")
  if [ -n "$account_ids" ]; then
    chown "$account_ids" "${target_root}${ACCOUNT_HOME}/.profile.d"
    chown "$account_ids" "${target_root}${ACCOUNT_HOME}/.profile.d/75-firmware-workspace.sh"
  fi
fi

run_in_target "create firmware workspace roots" /bin/sh -eu -c '
systemd-tmpfiles --create /etc/tmpfiles.d/86-firmware-workspace.conf
test -d "$1"
test -d "$1/$2"
test -d "$1/$2/captures"
test -d "$1/$2/unpack"
test -d "$1/$2/work"
' sh "$DIR_POOL_FIRMWARE" "$ACCOUNT_USERNAME"

run_in_target "grant programmer USB access to primary account" /bin/sh -eu -c '
account_user=$1
getent group usbadmin >/dev/null 2>&1
usermod -a -G usbadmin -- "$account_user"
' sh "$ACCOUNT_USERNAME"

ch341a_info "staged firmware workspace assets for account=${ACCOUNT_USERNAME}"
