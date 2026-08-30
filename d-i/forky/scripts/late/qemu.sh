#!/bin/sh
set -eu

target_root=${1:-/target}
[ -d "$target_root" ] || exit 0

qemu_fatal() {
  printf 'fatal: %s\n' "$*" >&2
  exit 1
}

qemu_info() {
  printf '[late:qemu] %s\n' "$*" >&2
}

qemu_validate_abs_path() {
  case "${2:-}" in
    /*) ;;
    *) qemu_fatal "$1 must be an absolute path: ${2:-unset}" ;;
  esac
  case "$2" in
    /|*..*|*//*|*[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._/@%:+,-]*)
      qemu_fatal "$1 contains unsupported path syntax: $2"
      ;;
  esac
}

qemu_stage_target_asset() {
  repo_path=$1
  target_path=$2
  mode=$3
  tmp_asset="${tmp_env_dir}/$(basename "$target_path").$$"
  target_host_path="${target_root}${target_path}"

  qemu_validate_abs_path "target path" "$target_path"
  bootstrap_fetch_seed_file "$seed_base" "$repo_path" "$tmp_asset" 0600 "qemu asset ${repo_path}"
  install -d -o root -g root -m 0755 "${target_root}$(dirname "$target_path")"
  install -o root -g root -m "$mode" "$tmp_asset" "$target_host_path"
  chmod "$mode" "$target_host_path"
  rm -f "$tmp_asset"
}

qemu_render_target_asset() {
  repo_path=$1
  target_path=$2
  mode=$3
  shift 3
  tmp_asset="${tmp_env_dir}/$(basename "$target_path").$$"
  tmp_rendered="${tmp_asset}.rendered"
  target_host_path="${target_root}${target_path}"

  qemu_validate_abs_path "target path" "$target_path"
  bootstrap_fetch_seed_file "$seed_base" "$repo_path" "$tmp_asset" 0600 "qemu template ${repo_path}"
  installer_apply_scalar_placeholders "$tmp_asset" "$tmp_rendered" "$@"
  if grep -Eq '__INSTALLER_[A-Z0-9_]+__' "$tmp_rendered"; then
    rm -f "$tmp_asset" "$tmp_rendered"
    qemu_fatal "qemu template rendered with unresolved placeholders: ${repo_path}"
  fi
  install -d -o root -g root -m 0755 "${target_root}$(dirname "$target_path")"
  install -o root -g root -m "$mode" "$tmp_rendered" "$target_host_path"
  chmod "$mode" "$target_host_path"
  rm -f "$tmp_asset" "$tmp_rendered"
}

target_passwd_ids() {
  awk -F: -v wanted_user="$1" '$1 == wanted_user { print $3 ":" $4; exit }' "${target_root}/etc/passwd" 2>/dev/null || true
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
tmp_env_dir=${INSTALLER_LATE_TMP_ENV_DIR:-/tmp/install-env-late/qemu}

[ -s "$bootstrap_lib" ] || qemu_fatal "installer bootstrap library is unavailable: ${bootstrap_lib}"
# shellcheck disable=SC1090,SC1091
. "$bootstrap_lib"
bootstrap_source_common_lib "" || qemu_fatal "failed to source installer common library"
seed_base=$(installer_current_seed_base 2>/dev/null || installer_seed_base "")
bootstrap_source_common_support_libs "$seed_base" "$tmp_env_dir" fetch hook target || {
  qemu_fatal "failed to source installer late support libraries"
}
installer_ensure_context_loaded "$seed_base"

installer_selected_class_reference_is_selected addon/qemu 2>/dev/null || exit 0

[ "${INSTALLER_HOST_VARIANT:-}" = desktop ] || qemu_fatal "addon/qemu is restricted to the desktop role"

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

: "${ACCOUNT_USERNAME:?ACCOUNT_USERNAME must be set before staging qemu assets}"
: "${ACCOUNT_HOME:?ACCOUNT_HOME must be set before staging qemu assets}"
: "${DIR_POOL:?DIR_POOL must be set before staging qemu assets}"
: "${DIR_POOL_LIBVIRT:=/pool/libvirt}"
: "${DIR_POOL_LIBVIRT_SESSION:=${DIR_POOL_LIBVIRT}/session}"
: "${DIR_POOL_INCUS:=/pool/incus}"
: "${DIR_POOL_LXC:=/pool/lxc}"
: "${DIR_POOL_VAGRANT:=/pool/vagrant}"
: "${TAILSCALE_INTERFACE:=tailscale0}"
: "${QEMU_LIBVIRT_NETWORK_NAME:=virtops}"
: "${QEMU_LIBVIRT_NETWORK_BRIDGE:=virbr-virtops}"
: "${QEMU_LIBVIRT_NETWORK_ADDRESS:=192.168.121.1}"
: "${QEMU_LIBVIRT_NETWORK_NETMASK:=255.255.255.0}"
: "${QEMU_LIBVIRT_NETWORK_DHCP_START:=192.168.121.2}"
: "${QEMU_LIBVIRT_NETWORK_DHCP_END:=192.168.121.254}"
: "${QEMU_INCUS_BRIDGE_NAME:=incusbr0}"
: "${QEMU_INCUS_HTTPS_ADDRESS:=:8443}"
: "${QEMU_INCUS_HTTPS_PORT:=8443}"

for path_value in \
  "$ACCOUNT_HOME" \
  "$DIR_POOL" \
  "$DIR_POOL_LIBVIRT" \
  "$DIR_POOL_LIBVIRT_SESSION" \
  "$DIR_POOL_INCUS" \
  "$DIR_POOL_LXC" \
  "$DIR_POOL_VAGRANT"
do
  qemu_validate_abs_path "managed virtualization path" "$path_value"
done
unset path_value

# Debian's explicit split driver packages are loadable modules for libvirtd.
# Verify the complete package, daemon, and driver-module contract before
# staging service policy so an incomplete archive fails closed.
# shellcheck disable=SC2016
run_in_target "verify split-driver libvirt package and executable contract" /bin/sh -eu -c '
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH

for package_name in \
  libvirt-common \
  libvirt-daemon \
  libvirt-daemon-common \
  libvirt-daemon-config-nwfilter \
  libvirt-daemon-driver-network \
  libvirt-daemon-driver-nodedev \
  libvirt-daemon-driver-nwfilter \
  libvirt-daemon-driver-qemu \
  libvirt-daemon-driver-secret \
  libvirt-daemon-driver-storage \
  libvirt-daemon-log \
  libvirt-daemon-lock \
  libvirt-daemon-plugin-lockd \
  libvirt-clients
do
  package_status=$(dpkg-query -W -f="\${db:Status-Abbrev}" "$package_name" 2>/dev/null || true)
  [ "$package_status" = "ii " ] || {
    printf "fatal: required split-driver virtualization package is not installed: %s\n" "$package_name" >&2
    exit 1
  }
done

legacy_meta_status=$(dpkg-query -W -f="\${db:Status-Abbrev}" libvirt-daemon-system 2>/dev/null || true)
[ "$legacy_meta_status" != "ii " ] || {
  printf "%s\n" "fatal: libvirt-daemon-system must not be installed; individual driver packages are required" >&2
  exit 1
}

for daemon_path in \
  /usr/bin/virsh \
  /usr/sbin/libvirtd \
  /usr/sbin/virtlogd \
  /usr/sbin/virtlockd
do
  [ -x "$daemon_path" ] || {
    printf "fatal: selected archive does not provide required libvirt executable: %s\n" "$daemon_path" >&2
    exit 1
  }
done

for incus_runtime_path in \
  /usr/libexec/incus/shutdown \
  /usr/sbin/dnsmasq
do
  [ -x "$incus_runtime_path" ] || {
    printf "fatal: selected archive does not provide required Incus runtime executable: %s\n" "$incus_runtime_path" >&2
    exit 1
  }
done
[ -r /usr/lib/systemd/system/incus-startup.service ] || {
  printf "%s\n" "fatal: selected archive does not provide incus-startup.service" >&2
  exit 1
}

for driver_contract in \
  libvirt-daemon-driver-network:libvirt_driver_network.so \
  libvirt-daemon-driver-nodedev:libvirt_driver_nodedev.so \
  libvirt-daemon-driver-nwfilter:libvirt_driver_nwfilter.so \
  libvirt-daemon-driver-qemu:libvirt_driver_qemu.so \
  libvirt-daemon-driver-secret:libvirt_driver_secret.so \
  libvirt-daemon-driver-storage:libvirt_driver_storage.so
do
  package_name=${driver_contract%%:*}
  driver_module=${driver_contract#*:}
  dpkg-query -L "$package_name" 2>/dev/null |
    grep -Eq "/${driver_module}\$" || {
      printf "fatal: %s does not provide required libvirt driver module: %s\n" \
        "$package_name" "$driver_module" >&2
      exit 1
    }
done
'

qemu_render_target_asset \
  "$(installer_repo_join_var DIR_HOOKS_ROLE_DESKTOP target/etc/default/virt-host-managed.tmpl)" \
  /etc/default/virt-host-managed \
  0644 \
  DIR_POOL_INCUS "$DIR_POOL_INCUS" \
  DIR_POOL_LXC "$DIR_POOL_LXC" \
  TAILSCALE_INTERFACE "$TAILSCALE_INTERFACE" \
  QEMU_LIBVIRT_NETWORK_NAME "$QEMU_LIBVIRT_NETWORK_NAME" \
  QEMU_LIBVIRT_NETWORK_BRIDGE "$QEMU_LIBVIRT_NETWORK_BRIDGE" \
  QEMU_LIBVIRT_NETWORK_ADDRESS "$QEMU_LIBVIRT_NETWORK_ADDRESS" \
  QEMU_LIBVIRT_NETWORK_NETMASK "$QEMU_LIBVIRT_NETWORK_NETMASK" \
  QEMU_LIBVIRT_NETWORK_DHCP_START "$QEMU_LIBVIRT_NETWORK_DHCP_START" \
  QEMU_LIBVIRT_NETWORK_DHCP_END "$QEMU_LIBVIRT_NETWORK_DHCP_END" \
  QEMU_INCUS_BRIDGE_NAME "$QEMU_INCUS_BRIDGE_NAME" \
  QEMU_INCUS_HTTPS_ADDRESS "$QEMU_INCUS_HTTPS_ADDRESS"

qemu_render_target_asset \
  "$(installer_repo_join_var DIR_HOOKS_ROLE_DESKTOP target/etc/tmpfiles.d/85-virtualization-storage.conf.tmpl)" \
  /etc/tmpfiles.d/85-virtualization-storage.conf \
  0644 \
  ACCOUNT_USERNAME "$ACCOUNT_USERNAME" \
  DIR_POOL_LIBVIRT "$DIR_POOL_LIBVIRT" \
  DIR_POOL_LIBVIRT_SESSION "$DIR_POOL_LIBVIRT_SESSION" \
  DIR_POOL_INCUS "$DIR_POOL_INCUS" \
  DIR_POOL_LXC "$DIR_POOL_LXC" \
  DIR_POOL_VAGRANT "$DIR_POOL_VAGRANT"

qemu_render_target_asset \
  "$(installer_repo_join_var DIR_HOOKS_ROLE_DESKTOP target/etc/skel/.profile.d/72-virt-vagrant.sh.tmpl)" \
  /etc/skel/.profile.d/72-virt-vagrant.sh \
  0644 \
  DIR_POOL_LIBVIRT_SESSION "$DIR_POOL_LIBVIRT_SESSION" \
  DIR_POOL_VAGRANT "$DIR_POOL_VAGRANT"

qemu_render_target_asset \
  "$(installer_repo_join_var DIR_HOOKS_ROLE_DESKTOP target/etc/qemu/bridge.conf.tmpl)" \
  /etc/qemu/bridge.conf \
  0644 \
  QEMU_LIBVIRT_NETWORK_BRIDGE "$QEMU_LIBVIRT_NETWORK_BRIDGE"
for qemu_user_daemon in virtlockd virtlogd; do
  qemu_render_target_asset \
    "$(installer_repo_join_var DIR_HOOKS_ROLE_DESKTOP target/etc/systemd/user/managed-${qemu_user_daemon}.service.tmpl)" \
    "/etc/systemd/user/managed-${qemu_user_daemon}.service" \
    0644 \
    ACCOUNT_USERNAME "$ACCOUNT_USERNAME"
done
unset qemu_user_daemon
qemu_render_target_asset \
  "$(installer_repo_join_var DIR_HOOKS_ROLE_DESKTOP target/etc/systemd/user/managed-libvirt-runtime.service.tmpl)" \
  /etc/systemd/user/managed-libvirt-runtime.service \
  0644 \
  ACCOUNT_USERNAME "$ACCOUNT_USERNAME"
qemu_render_target_asset \
  "$(installer_repo_join_var DIR_HOOKS_ROLE_DESKTOP target/etc/systemd/user/libvirt-session.service.tmpl)" \
  /etc/systemd/user/libvirt-session.service \
  0644 \
  ACCOUNT_USERNAME "$ACCOUNT_USERNAME"
qemu_render_target_asset \
  "$(installer_repo_join_var DIR_HOOKS_ROLE_DESKTOP target/etc/systemd/user/virt-session-storage.service.tmpl)" \
  /etc/systemd/user/virt-session-storage.service \
  0644 \
  ACCOUNT_USERNAME "$ACCOUNT_USERNAME" \
  DIR_POOL_LIBVIRT_SESSION "$DIR_POOL_LIBVIRT_SESSION"
qemu_render_target_asset \
  "$(installer_repo_join_var DIR_HOOKS_ROLE_DESKTOP target/etc/libvirt/managed/session-default-pool.xml.tmpl)" \
  /etc/libvirt/managed/session-default-pool.xml \
  0644 \
  ACCOUNT_USERNAME "$ACCOUNT_USERNAME" \
  DIR_POOL_LIBVIRT_SESSION "$DIR_POOL_LIBVIRT_SESSION"
qemu_render_target_asset \
  "$(installer_repo_join_var DIR_HOOKS_ROLE_DESKTOP target/etc/libvirt/managed/virtops-network.xml.tmpl)" \
  /etc/libvirt/managed/virtops-network.xml \
  0644 \
  QEMU_LIBVIRT_NETWORK_NAME "$QEMU_LIBVIRT_NETWORK_NAME" \
  QEMU_LIBVIRT_NETWORK_BRIDGE "$QEMU_LIBVIRT_NETWORK_BRIDGE" \
  QEMU_LIBVIRT_NETWORK_ADDRESS "$QEMU_LIBVIRT_NETWORK_ADDRESS" \
  QEMU_LIBVIRT_NETWORK_NETMASK "$QEMU_LIBVIRT_NETWORK_NETMASK" \
  QEMU_LIBVIRT_NETWORK_DHCP_START "$QEMU_LIBVIRT_NETWORK_DHCP_START" \
  QEMU_LIBVIRT_NETWORK_DHCP_END "$QEMU_LIBVIRT_NETWORK_DHCP_END"
qemu_stage_target_asset \
  "$(installer_repo_join_var DIR_HOOKS_ROLE_DESKTOP target/usr/local/libexec/virt-host-managed)" \
  /usr/local/libexec/virt-host-managed \
  0755
qemu_stage_target_asset \
  "$(installer_repo_join_var DIR_HOOKS_ROLE_DESKTOP target/usr/local/libexec/virt-session-storage)" \
  /usr/local/libexec/virt-session-storage \
  0755
qemu_stage_target_asset \
  "$(installer_repo_join_var DIR_HOOKS_ROLE_DESKTOP target/usr/local/libexec/lxcfs-stop)" \
  /usr/local/libexec/lxcfs-stop \
  0755
qemu_stage_target_asset \
  "$(installer_repo_join_var DIR_HOOKS_ROLE_DESKTOP target/etc/systemd/system/virt-host-managed.service)" \
  /etc/systemd/system/virt-host-managed.service \
  0644
qemu_stage_target_asset \
  "$(installer_repo_join_var DIR_HOOKS_ROLE_DESKTOP target/etc/systemd/system/lxcfs.service.d/20-managed-stop.conf)" \
  /etc/systemd/system/lxcfs.service.d/20-managed-stop.conf \
  0644
for qemu_system_daemon in libvirtd virtlogd virtlockd; do
  qemu_stage_target_asset \
    "$(installer_repo_join_var DIR_HOOKS_ROLE_DESKTOP target/etc/systemd/system/${qemu_system_daemon}.service.d/20-managed-logging.conf)" \
    "/etc/systemd/system/${qemu_system_daemon}.service.d/20-managed-logging.conf" \
    0644
done
unset qemu_system_daemon
qemu_stage_target_asset \
  "$(installer_repo_join_var DIR_HOOKS_ROLE_DESKTOP target/etc/sysusers.d/swtpm-sysusers.conf)" \
  /etc/sysusers.d/swtpm-sysusers.conf \
  0644
qemu_stage_target_asset \
  "$(installer_repo_join_var DIR_HOOKS_ROLE_DESKTOP target/etc/libvirt/libvirt.conf)" \
  /etc/libvirt/libvirt.conf \
  0644
for qemu_system_config in libvirtd virtlockd virtlogd; do
  qemu_stage_target_asset \
    "$(installer_repo_join_var DIR_HOOKS_ROLE_DESKTOP target/etc/libvirt/${qemu_system_config}.conf)" \
    "/etc/libvirt/${qemu_system_config}.conf" \
    0644
done
unset qemu_system_config
qemu_stage_target_asset \
  "$(installer_repo_join_var DIR_HOOKS_ROLE_DESKTOP target/etc/libvirt/qemu.conf)" \
  /etc/libvirt/qemu.conf \
  0644
qemu_stage_target_asset \
  "$(installer_repo_join_var DIR_HOOKS_ROLE_DESKTOP target/etc/environment.d/72-libvirt-session.conf)" \
  /etc/environment.d/72-libvirt-session.conf \
  0644
qemu_stage_target_asset \
  "$(installer_repo_join_var DIR_HOOKS_ROLE_DESKTOP target/etc/rsyslog.d/43-libvirt.conf)" \
  /etc/rsyslog.d/43-libvirt.conf \
  0644
qemu_stage_target_asset \
  "$(installer_repo_join_var DIR_HOOKS_ROLE_DESKTOP target/etc/logrotate.d/libvirt-managed)" \
  /etc/logrotate.d/libvirt-managed \
  0644
qemu_stage_target_asset \
  "$(installer_repo_join_var DIR_HOOKS_ROLE_DESKTOP target/usr/local/bin/virt-manager-virtops)" \
  /usr/local/bin/virt-manager-virtops \
  0755
qemu_stage_target_asset \
  "$(installer_repo_join_var DIR_HOOKS_ROLE_DESKTOP target/usr/share/applications/virt-manager.desktop)" \
  /usr/share/applications/virt-manager.desktop \
  0644
qemu_stage_target_asset \
  "$(installer_repo_join_var DIR_HOOKS_ROLE_DESKTOP target/etc/skel/.config/libvirt/libvirt.conf)" \
  /etc/skel/.config/libvirt/libvirt.conf \
  0644
for qemu_user_config in libvirtd virtlockd; do
  qemu_stage_target_asset \
    "$(installer_repo_join_var DIR_HOOKS_ROLE_DESKTOP target/etc/skel/.config/libvirt/${qemu_user_config}.conf)" \
    "/etc/skel/.config/libvirt/${qemu_user_config}.conf" \
    0644
done
unset qemu_user_config
qemu_render_target_asset \
  "$(installer_repo_join_var DIR_HOOKS_ROLE_DESKTOP target/etc/skel/.config/libvirt/virtlogd.conf.tmpl)" \
  /etc/skel/.config/libvirt/virtlogd.conf \
  0644 \
  ACCOUNT_USERNAME "$ACCOUNT_USERNAME"
qemu_stage_target_asset \
  "$(installer_repo_join_var DIR_HOOKS_ROLE_DESKTOP target/etc/skel/.config/libvirt/qemu.conf)" \
  /etc/skel/.config/libvirt/qemu.conf \
  0644
qemu_render_target_asset \
  "$(installer_repo_join_var DIR_HOOKS_ROLE_DESKTOP target/usr/share/glib-2.0/schemas/91-virt-manager-session.gschema.override.tmpl)" \
  /usr/share/glib-2.0/schemas/91-virt-manager-session.gschema.override \
  0644 \
  ACCOUNT_USERNAME "$ACCOUNT_USERNAME" \
  DIR_POOL_LIBVIRT_SESSION "$DIR_POOL_LIBVIRT_SESSION"
qemu_render_target_asset \
  "$(installer_repo_join_var DIR_HOOKS_ROLE_DESKTOP target/etc/skel/.vagrant.d/Vagrantfile)" \
  /etc/skel/.vagrant.d/Vagrantfile \
  0644 \
  ACCOUNT_USERNAME "$ACCOUNT_USERNAME" \
  DIR_POOL_LIBVIRT_SESSION "$DIR_POOL_LIBVIRT_SESSION" \
  QEMU_LIBVIRT_NETWORK_BRIDGE "$QEMU_LIBVIRT_NETWORK_BRIDGE"

run_in_target "prepare managed virtualization install-time filesystem state" /usr/local/libexec/virt-host-managed --prepare-install

# The single-quoted body is intentionally expanded by the target-side shell.
# shellcheck disable=SC2016
run_in_target "create managed virtualization storage roots" /bin/sh -eu -c '
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH
getent group devops >/dev/null 2>&1
install -d -m 0711 -o root -g root "$1"
install -d -m 0750 -o root -g root "$2"
install -d -m 2770 -o root -g devops "$3"
test -d "$1"
test -d "$2"
test -d "$3"
' sh "$DIR_POOL_INCUS" "$DIR_POOL_LXC" "$DIR_POOL_VAGRANT"

# The single-quoted body is intentionally expanded by the target-side shell.
# shellcheck disable=SC2016
run_in_target "grant rootless virtualization groups to primary account" /bin/sh -eu -c '
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH
account_user=$1
for group_name in kvm incus incus-admin; do
  getent group "$group_name" >/dev/null 2>&1 || {
    printf "fatal: required virtualization group is missing: %s\n" "$group_name" >&2
    exit 1
  }
done

for group_name in kvm incus incus-admin; do
  usermod -a -G "$group_name" -- "$account_user"
done
' sh "$ACCOUNT_USERNAME"

account_ids=$(target_passwd_ids "$ACCOUNT_USERNAME")
[ -n "$account_ids" ] || qemu_fatal "primary account is missing from target passwd: ${ACCOUNT_USERNAME}"

install -d -m 0700 "${target_root}${ACCOUNT_HOME}/.config/libvirt"
install -d -m 0700 "${target_root}${ACCOUNT_HOME}/.vagrant.d"
install -d -m 0700 "${target_root}${ACCOUNT_HOME}/.profile.d"
for qemu_user_config in \
  libvirt.conf \
  libvirtd.conf \
  qemu.conf \
  virtlockd.conf \
  virtlogd.conf
do
  install -m 0600 \
    "${target_root}/etc/skel/.config/libvirt/${qemu_user_config}" \
    "${target_root}${ACCOUNT_HOME}/.config/libvirt/${qemu_user_config}"
done
unset qemu_user_config
install -m 0600 \
  "${target_root}/etc/skel/.vagrant.d/Vagrantfile" \
  "${target_root}${ACCOUNT_HOME}/.vagrant.d/Vagrantfile"
install -m 0600 \
  "${target_root}/etc/skel/.profile.d/72-virt-vagrant.sh" \
  "${target_root}${ACCOUNT_HOME}/.profile.d/72-virt-vagrant.sh"
install -d -m 0700 "${target_root}${DIR_POOL_VAGRANT}/${ACCOUNT_USERNAME}/home"
install -m 0600 \
  "${target_root}/etc/skel/.vagrant.d/Vagrantfile" \
  "${target_root}${DIR_POOL_VAGRANT}/${ACCOUNT_USERNAME}/home/Vagrantfile"
chown -R "$account_ids" \
  "${target_root}${ACCOUNT_HOME}/.config" \
  "${target_root}${ACCOUNT_HOME}/.config/libvirt" \
  "${target_root}${ACCOUNT_HOME}/.profile.d" \
  "${target_root}${ACCOUNT_HOME}/.profile.d/72-virt-vagrant.sh" \
  "${target_root}${ACCOUNT_HOME}/.vagrant.d" \
  "${target_root}${ACCOUNT_HOME}/.vagrant.d/Vagrantfile" \
  "${target_root}${DIR_POOL_VAGRANT}/${ACCOUNT_USERNAME}/home" \
  "${target_root}${DIR_POOL_VAGRANT}/${ACCOUNT_USERNAME}/home/Vagrantfile"

managed_host_unit="${target_root}/etc/systemd/system/virt-host-managed.service"
managed_host_link_dir="${target_root}/etc/systemd/system/multi-user.target.wants"
[ -r "$managed_host_unit" ] ||
  qemu_fatal "managed virtualization host unit is unavailable: /etc/systemd/system/virt-host-managed.service"
install -d -m 0755 "$managed_host_link_dir"
ln -sfn \
  /etc/systemd/system/virt-host-managed.service \
  "${managed_host_link_dir}/virt-host-managed.service"
unset managed_host_unit managed_host_link_dir

qemu_info "staged libvirtd with explicit split drivers and administrator-managed session services"
qemu_info "staged desktop virtualization assets for account=${ACCOUNT_USERNAME}"
