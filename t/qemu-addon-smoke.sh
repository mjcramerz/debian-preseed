#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/qemu-addon-smoke.XXXXXX")
trap 'rm -rf -- "$TMP_DIR"' EXIT HUP INT TERM

TEST_COUNT=18
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

pkgsel_line() {
  sed -n 's/^d-i pkgsel\/include string //p' "$1" | head -n 1
}

word_list_has() {
  words=$1
  needle=$2
  case " $words " in
    *" $needle "*) return 0 ;;
  esac
  return 1
}

render_template() {
  source_path=$1
  destination_path=$2
  shift 2

  cp -- "$source_path" "$destination_path"
  while [ "$#" -gt 0 ]; do
    placeholder=$1
    replacement=$2
    shift 2
    sed "s#__INSTALLER_${placeholder}__#${replacement}#g" \
      "$destination_path" >"${destination_path}.new"
    mv -f -- "${destination_path}.new" "$destination_path"
  done
  ! grep -Eq '__INSTALLER_[A-Z0-9_]+__' "$destination_path"
}

session_storage_helper_works() {
  helper_copy="$TMP_DIR/virt-session-storage"
  fake_stat="$TMP_DIR/stat"
  fake_virsh="$TMP_DIR/virsh"
  runtime_dir="$TMP_DIR/runtime"
  system_anchor="$TMP_DIR/system-owner"
  pool_root="$TMP_DIR/pool/libvirt/session"
  pool_path="${pool_root}/$(id -un)/images"
  pool_xml="$TMP_DIR/session-default-pool.xml"
  wrong_arg_xml="$TMP_DIR/wrong-pool.xml"
  virsh_log="$TMP_DIR/virsh.log"
  virsh_state="$TMP_DIR/virsh.state"
  current_uid=$(id -u)

  install -d -m 0755 -- "$system_anchor"
  install -d -m 0700 -- "$runtime_dir" "$pool_path"
  cat >"$pool_xml" <<EOF
<pool type='dir'>
  <name>default</name>
  <target>
    <path>${pool_path}</path>
  </target>
</pool>
EOF
  chmod 0644 "$pool_xml"
  cp -- "$pool_xml" "$wrong_arg_xml"

  sed \
    -e "s#^MANAGED_POOL_XML=.*#MANAGED_POOL_XML=${pool_xml}#" \
    -e "s#^SYSTEM_OWNER_ANCHOR=.*#SYSTEM_OWNER_ANCHOR=${system_anchor}#" \
    -e "s#expected_runtime=\"/run/user/\${actual_uid}\"#expected_runtime=\"${runtime_dir}\"#" \
    -e "s#/usr/bin/stat#${fake_stat}#g" \
    -e "s#/usr/bin/virsh#${fake_virsh}#g" \
    "$session_storage_script" >"$helper_copy"
  chmod 0755 "$helper_copy"

  cat >"$fake_stat" <<'EOF'
#!/bin/sh
set -eu

: "${FAKE_POOL_XML_MODE:?}"
: "${FAKE_POOL_XML_PATH:?}"
: "${FAKE_POOL_XML_UID:?}"
: "${FAKE_SYSTEM_MODE:?}"
: "${FAKE_SYSTEM_OWNER_ANCHOR:?}"
: "${FAKE_SYSTEM_UID:?}"

if [ "$#" -eq 4 ] && [ "$1" = -c ] && [ "$3" = -- ]; then
  format=$2
  inspected_path=$4
  if [ "$inspected_path" = "$FAKE_SYSTEM_OWNER_ANCHOR" ]; then
    case "$format" in
      %u) printf '%s\n' "$FAKE_SYSTEM_UID"; exit 0 ;;
      %a) printf '%s\n' "$FAKE_SYSTEM_MODE"; exit 0 ;;
    esac
  fi
  if [ "$inspected_path" = "$FAKE_POOL_XML_PATH" ]; then
    case "$format" in
      %u) printf '%s\n' "$FAKE_POOL_XML_UID"; exit 0 ;;
      %a) printf '%s\n' "$FAKE_POOL_XML_MODE"; exit 0 ;;
    esac
  fi
fi
exec /usr/bin/stat "$@"
EOF
  chmod 0755 "$fake_stat"

  cat >"$fake_virsh" <<'EOF'
#!/bin/sh
set -eu

: "${EXPECTED_POOL_PATH:?}"
: "${VIRSH_LOG:?}"
: "${VIRSH_SCENARIO:?}"
: "${VIRSH_STATE_FILE:?}"
[ "${LIBVIRT_AUTOSTART:-}" = 0 ]

  [ "$1" = -c ] && [ "$2" = qemu:///session ]
shift 2
command_name=$1
shift
  printf '%s\n' "-c qemu:///session ${command_name}${*:+ $*}" >>"$VIRSH_LOG"

case "$command_name" in
  pool-info)
    [ "$VIRSH_SCENARIO" != missing ]
    ;;
  pool-dumpxml)
    pool_type=dir
    pool_path=$EXPECTED_POOL_PATH
    [ "$VIRSH_SCENARIO" != wrong_path ] ||
      pool_path=/pool/libvirt/session/wrong/images
    [ "$VIRSH_SCENARIO" != wrong_type ] ||
      pool_type=fs
    printf "<pool type='%s'><name>default</name><target><path>%s</path></target></pool>\n" \
      "$pool_type" "$pool_path"
    ;;
  pool-define)
    grep -Fq '<name>default</name>' "$1"
    grep -Fq "<path>${EXPECTED_POOL_PATH}</path>" "$1"
    printf '%s\n' inactive >"$VIRSH_STATE_FILE"
    ;;
  pool-list)
    [ "${1:-}" = --name ]
    if [ -r "$VIRSH_STATE_FILE" ] &&
       [ "$(cat "$VIRSH_STATE_FILE")" = active ]; then
      printf '%s\n' default
    fi
    ;;
  pool-start)
    [ "${1:-}" = default ]
    printf '%s\n' active >"$VIRSH_STATE_FILE"
    ;;
  pool-autostart)
    [ "${1:-}" = default ]
    ;;
  *)
    exit 64
    ;;
esac
EOF
  chmod 0755 "$fake_virsh"

  run_session_storage_helper() {
    test_system_uid=$1
    test_system_mode=$2
    test_pool_xml_uid=$3
    test_pool_xml_mode=$4
    test_virsh_scenario=$5
    shift 5

    EXPECTED_POOL_PATH=$pool_path \
      FAKE_POOL_XML_MODE=$test_pool_xml_mode \
      FAKE_POOL_XML_PATH=$pool_xml \
      FAKE_POOL_XML_UID=$test_pool_xml_uid \
      FAKE_SYSTEM_MODE=$test_system_mode \
      FAKE_SYSTEM_OWNER_ANCHOR=$system_anchor \
      FAKE_SYSTEM_UID=$test_system_uid \
      VIRSH_LOG=$virsh_log \
      VIRSH_SCENARIO=$test_virsh_scenario \
      VIRSH_STATE_FILE=$virsh_state \
      XDG_RUNTIME_DIR=$runtime_dir \
      "$helper_copy" "$@"
  }

  for system_uid in 0 65534; do
    for scenario in missing inactive active; do
    : >"$virsh_log"
    case "$scenario" in
      missing) rm -f -- "$virsh_state" ;;
      inactive) printf '%s\n' inactive >"$virsh_state" ;;
      active) printf '%s\n' active >"$virsh_state" ;;
    esac
    run_session_storage_helper \
      "$system_uid" 755 "$system_uid" 644 "$scenario" \
      "$pool_xml" "$pool_path" ||
      return 1
    grep -Fq -- '-c qemu:///session pool-info default' "$virsh_log" ||
      return 1
    grep -Fq -- '-c qemu:///session pool-autostart default' "$virsh_log" ||
      return 1
    ! grep -Fq 'storage:///' "$virsh_log" || return 1
    case "$scenario" in
      missing)
        grep -Fq -- '-c qemu:///session pool-define ' "$virsh_log" &&
          grep -Fq -- '-c qemu:///session pool-start default' "$virsh_log" ||
          return 1
        ;;
      inactive)
        ! grep -Fq -- '-c qemu:///session pool-define ' "$virsh_log" &&
          grep -Fq -- '-c qemu:///session pool-start default' "$virsh_log" ||
          return 1
        ;;
      active)
        ! grep -Fq -- '-c qemu:///session pool-define ' "$virsh_log" &&
          ! grep -Fq -- '-c qemu:///session pool-start default' "$virsh_log" ||
          return 1
        ;;
    esac
    done
  done

  : >"$virsh_log"
  printf '%s\n' active >"$virsh_state"
  ! run_session_storage_helper \
    0 755 0 644 wrong_path \
    "$pool_xml" "$pool_path" >/dev/null 2>&1 ||
    return 1
  ! run_session_storage_helper \
    0 755 0 644 wrong_type \
    "$pool_xml" "$pool_path" >/dev/null 2>&1 ||
    return 1
  ! run_session_storage_helper \
    0 755 0 644 missing \
    "$pool_xml" >/dev/null 2>&1 ||
    return 1
  ! run_session_storage_helper \
    0 755 0 644 missing \
    "$pool_xml" relative/session/pool >/dev/null 2>&1 ||
    return 1
  ! run_session_storage_helper \
    0 755 0 644 missing \
    "$pool_xml" "${pool_root}/wrong-account/images" >/dev/null 2>&1 ||
    return 1

  sed 's#<name>default</name>#<name>vagrant</name>#' "$pool_xml" >"${pool_xml}.new"
  mv -- "${pool_xml}.new" "$pool_xml"
  chmod 0644 "$pool_xml"
  ! run_session_storage_helper \
    0 755 0 644 missing \
    "$pool_xml" "$pool_path" >/dev/null 2>&1 ||
    return 1

  cat >"$pool_xml" <<EOF
<pool type='dir'>
  <name>default</name>
  <target>
    <path>/pool/libvirt/session/wrong/images</path>
  </target>
</pool>
EOF
  chmod 0644 "$pool_xml"
  ! run_session_storage_helper \
    0 755 0 644 missing \
    "$pool_xml" "$pool_path" >/dev/null 2>&1 ||
    return 1

  ! run_session_storage_helper \
    0 755 0 644 missing \
    "$wrong_arg_xml" "$pool_path" >/dev/null 2>&1 ||
    return 1

  cp -- "$wrong_arg_xml" "$pool_xml"
  chmod 0644 "$pool_xml"
  mapped_system_uid=65534
  [ "$current_uid" != "$mapped_system_uid" ] ||
    mapped_system_uid=0
  ! run_session_storage_helper \
    "$mapped_system_uid" 755 "$current_uid" 644 missing \
    "$pool_xml" "$pool_path" >/dev/null 2>&1 ||
    return 1
  ! run_session_storage_helper \
    "$mapped_system_uid" 755 "$mapped_system_uid" 600 missing \
    "$pool_xml" "$pool_path" >/dev/null 2>&1 ||
    return 1

  mv -- "$pool_xml" "${pool_xml}.direct"
  ln -s -- "${pool_xml}.direct" "$pool_xml"
  ! run_session_storage_helper \
    "$mapped_system_uid" 755 "$mapped_system_uid" 644 missing \
    "$pool_xml" "$pool_path" >/dev/null 2>&1 ||
    return 1
  rm -f -- "$pool_xml"
  mv -- "${pool_xml}.direct" "$pool_xml"

  ! run_session_storage_helper \
    "$mapped_system_uid" 777 "$mapped_system_uid" 644 missing \
    "$pool_xml" "$pool_path" >/dev/null 2>&1 ||
    return 1

  mv -- "$system_anchor" "${system_anchor}.direct"
  ln -s -- "${system_anchor}.direct" "$system_anchor"
  ! run_session_storage_helper \
    "$mapped_system_uid" 755 "$mapped_system_uid" 644 missing \
    "$pool_xml" "$pool_path" >/dev/null 2>&1 ||
    return 1
  rm -f -- "$system_anchor"
  mv -- "${system_anchor}.direct" "$system_anchor"
}

lxcfs_stop_helper_works() {
  helper_copy="$TMP_DIR/lxcfs-stop"
  fake_findmnt="$TMP_DIR/findmnt"
  fake_fusermount="$TMP_DIR/fusermount3"
  fake_sleep="$TMP_DIR/sleep"
  mountpoint="$TMP_DIR/lxcfs"
  operation_log="$TMP_DIR/lxcfs-stop.log"
  stderr_log="$TMP_DIR/lxcfs-stop.stderr"

  install -d -m 0755 -- "$mountpoint"
  sed \
    -e "s#^mountpoint=/var/lib/lxcfs\$#mountpoint=${mountpoint}#" \
    -e "s#/usr/bin/findmnt#${fake_findmnt}#g" \
    -e "s#/usr/bin/fusermount3#${fake_fusermount}#g" \
    -e "s#/bin/fusermount#${fake_fusermount}#g" \
    -e "s#/usr/bin/sleep#${fake_sleep}#g" \
    "$lxcfs_stop_script" >"$helper_copy"
  chmod 0755 "$helper_copy"

  cat >"$fake_findmnt" <<'EOF'
#!/bin/sh
set -eu
[ -n "${FINDMNT_FSTYPE:-}" ] || exit 1
printf '%s\n' "$FINDMNT_FSTYPE"
EOF
  chmod 0755 "$fake_findmnt"

  cat >"$fake_fusermount" <<'EOF'
#!/bin/sh
set -eu
printf '%s\n' "$*" >>"$FUSERMOUNT_LOG"
case "${1:-}" in
  -uz) exit "${FUSERMOUNT_LAZY_STATUS:-0}" ;;
  *) exit "${FUSERMOUNT_NORMAL_STATUS:-1}" ;;
esac
EOF
  chmod 0755 "$fake_fusermount"

  cat >"$fake_sleep" <<'EOF'
#!/bin/sh
set -eu
printf 'sleep %s\n' "$*" >>"$FUSERMOUNT_LOG"
EOF
  chmod 0755 "$fake_sleep"

  : >"$operation_log"
  FINDMNT_FSTYPE=fuse.lxcfs \
    FUSERMOUNT_LOG="$operation_log" \
    FUSERMOUNT_NORMAL_STATUS=1 \
    FUSERMOUNT_LAZY_STATUS=0 \
    "$helper_copy" 2>"$stderr_log" ||
    return 1
  [ ! -s "$stderr_log" ] || return 1
  [ "$(grep -Fxc -- "-u $mountpoint" "$operation_log")" -eq 3 ] ||
    return 1
  [ "$(grep -Fxc -- "sleep 1" "$operation_log")" -eq 2 ] ||
    return 1
  [ "$(grep -Fxc -- "-uz $mountpoint" "$operation_log")" -eq 1 ] ||
    return 1

  : >"$operation_log"
  if FINDMNT_FSTYPE=ext4 \
       FUSERMOUNT_LOG="$operation_log" \
       FUSERMOUNT_NORMAL_STATUS=1 \
       FUSERMOUNT_LAZY_STATUS=1 \
       "$helper_copy" 2>"$stderr_log"; then
    return 1
  fi
  grep -Fq "refusing to unmount unexpected filesystem type ext4 at $mountpoint" \
    "$stderr_log" ||
    return 1
  [ ! -s "$operation_log" ] || return 1

  : >"$operation_log"
  if FINDMNT_FSTYPE=fuse.lxcfs \
       FUSERMOUNT_LOG="$operation_log" \
       FUSERMOUNT_NORMAL_STATUS=1 \
       FUSERMOUNT_LAZY_STATUS=1 \
       "$helper_copy" 2>"$stderr_log"; then
    return 1
  fi
  grep -Fq "failed to lazy-detach $mountpoint after bounded normal unmount attempts" \
    "$stderr_log" ||
    return 1
  [ "$(grep -Fxc -- "-u $mountpoint" "$operation_log")" -eq 3 ] ||
    return 1
  [ "$(grep -Fxc -- "-uz $mountpoint" "$operation_log")" -eq 1 ] ||
    return 1
}

managed_shutdown_helper_works() {
  helper_copy="$TMP_DIR/virt-host-managed-shutdown"
  fake_bin="$TMP_DIR/virt-host-fake-bin"
  config_file="$TMP_DIR/virt-host-managed.conf"
  network_xml="$TMP_DIR/virtops-network.xml"
  libvirt_state="$TMP_DIR/libvirt.state"
  operation_log="$TMP_DIR/virt-host-shutdown.log"
  stderr_log="$TMP_DIR/virt-host-shutdown.stderr"

  install -d -m 0755 -- "$fake_bin"
  cat >"$config_file" <<'EOF'
VIRT_LIBVIRT_NETWORK_NAME=virtops
EOF
  chmod 0644 "$config_file"

  sed \
    -e "s#^PATH=.*#PATH=${fake_bin}:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin#" \
    -e "s#^CONFIG_FILE=.*#CONFIG_FILE=${config_file}#" \
    -e "s#^LIBVIRT_NETWORK_XML=.*#LIBVIRT_NETWORK_XML=${network_xml}#" \
    "$managed_script" >"$helper_copy"
  chmod 0755 "$helper_copy"

  cat >"$fake_bin/virsh" <<'EOF'
#!/bin/sh
set -eu

[ "$1" = -c ] && [ "$2" = qemu:///system ]
shift 2
printf 'virsh %s\n' "$*" >>"$VIRT_SHUTDOWN_LOG"

case "$1:$2:${3:-}:${4:-}" in
  net-list:--all:--name:)
    if [ "$(cat "$VIRSH_STATE_FILE")" != absent ]; then
      printf '%s\n' virtops
    fi
    ;;
  net-list:--name::)
    case "$(cat "$VIRSH_STATE_FILE")" in
      active|destroy-fails) printf '%s\n' virtops ;;
    esac
    ;;
  net-destroy:virtops::)
    [ "$(cat "$VIRSH_STATE_FILE")" = active ] || exit 1
    printf '%s\n' inactive >"$VIRSH_STATE_FILE"
    ;;
  *)
    exit 64
    ;;
esac
EOF
  chmod 0755 "$fake_bin/virsh"

  run_managed_shutdown() {
    VIRSH_STATE_FILE="$libvirt_state" \
      VIRT_SHUTDOWN_LOG="$operation_log" \
      "$helper_copy" --shutdown >"$TMP_DIR/virt-host-shutdown.stdout" 2>"$stderr_log"
  }

  printf '%s\n' active >"$libvirt_state"
  : >"$operation_log"
  run_managed_shutdown || {
    cat "$stderr_log" >&2
    return 1
  }
  cat >"$TMP_DIR/virt-host-shutdown.expected" <<'EOF'
virsh net-list --all --name
virsh net-list --name
virsh net-destroy virtops
virsh net-list --name
EOF
  cmp -s "$TMP_DIR/virt-host-shutdown.expected" "$operation_log" ||
    return 1

  printf '%s\n' inactive >"$libvirt_state"
  : >"$operation_log"
  run_managed_shutdown || {
    cat "$stderr_log" >&2
    return 1
  }
  cat >"$TMP_DIR/virt-host-shutdown.expected" <<'EOF'
virsh net-list --all --name
virsh net-list --name
EOF
  cmp -s "$TMP_DIR/virt-host-shutdown.expected" "$operation_log" ||
    return 1

  printf '%s\n' absent >"$libvirt_state"
  : >"$operation_log"
  run_managed_shutdown || {
    cat "$stderr_log" >&2
    return 1
  }
  [ "$(cat "$operation_log")" = 'virsh net-list --all --name' ] ||
    return 1

  printf '%s\n' destroy-fails >"$libvirt_state"
  : >"$operation_log"
  if run_managed_shutdown; then
    return 1
  fi
  grep -Fq 'virsh net-destroy virtops' "$operation_log" &&
    grep -Fq 'could not stop managed libvirt network virtops' "$stderr_log" &&
    ! grep -Eq 'dnsmasq|kill -' "$operation_log" ||
    return 1

  printf '%s\n' VIRT_LIBVIRT_NETWORK_NAME=default >"$config_file"
  : >"$operation_log"
  if run_managed_shutdown; then
    return 1
  fi
  grep -Fq 'managed libvirt network must not reuse the package-owned default network' \
    "$stderr_log" &&
    [ ! -s "$operation_log" ] ||
    return 1
}

printf '1..%s\n' "$TEST_COUNT"

addons_cfg="$ROOT_DIR/d-i/forky/classes/configs/addons.cfg"
qemu_class="$ROOT_DIR/d-i/forky/classes/class-addon/qemu.cfg"
runtime_env="$ROOT_DIR/d-i/forky/hosts/shared/runtime.env"
desktop_env="$ROOT_DIR/d-i/forky/hosts/profiles/btrfs/desktop.env"
helper="$ROOT_DIR/d-i/forky/scripts/late/qemu.sh"
managed_unit="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/systemd/system/virt-host-managed.service"
managed_defaults="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/default/virt-host-managed.tmpl"
managed_tmpfiles="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/tmpfiles.d/85-virtualization-storage.conf.tmpl"
managed_script="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/libexec/virt-host-managed"
session_storage_unit="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/systemd/user/virt-session-storage.service.tmpl"
libvirt_session_unit="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/systemd/user/libvirt-session.service.tmpl"
libvirt_runtime_unit="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/systemd/user/managed-libvirt-runtime.service.tmpl"
virtlockd_unit="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/systemd/user/managed-virtlockd.service.tmpl"
virtlogd_unit="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/systemd/user/managed-virtlogd.service.tmpl"
libvirtd_logging_dropin="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/systemd/system/libvirtd.service.d/20-managed-logging.conf"
virtlockd_logging_dropin="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/systemd/system/virtlockd.service.d/20-managed-logging.conf"
virtlogd_logging_dropin="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/systemd/system/virtlogd.service.d/20-managed-logging.conf"
session_storage_script="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/libexec/virt-session-storage"
lxcfs_stop_script="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/libexec/lxcfs-stop"
lxcfs_stop_dropin="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/systemd/system/lxcfs.service.d/20-managed-stop.conf"
bridge_template="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/qemu/bridge.conf.tmpl"
swtpm_sysusers="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/sysusers.d/swtpm-sysusers.conf"
security_script="$ROOT_DIR/d-i/forky/scripts/late/security.sh"
qemu_nft="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/nftables/services/qemu.yml"
zabbly_pref="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apt/preferences.d/desktop/zabbly.pref"
system_libvirt_dir="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/libvirt"
user_libvirt_dir="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/libvirt"
pool_xml_template="$system_libvirt_dir/managed/session-default-pool.xml.tmpl"
network_xml_template="$system_libvirt_dir/managed/virtops-network.xml.tmpl"
libvirt_environment="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/environment.d/72-libvirt-session.conf"
virt_manager_schema="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/share/glib-2.0/schemas/91-virt-manager-session.gschema.override.tmpl"
libvirt_rsyslog="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/rsyslog.d/43-libvirt.conf"
libvirt_logrotate="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/logrotate.d/libvirt-managed"
vagrant_profile="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.profile.d/72-virt-vagrant.sh.tmpl"
vagrant_global="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.vagrant.d/Vagrantfile"
virt_manager_wrapper="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/virt-manager-virtops"
virt_manager_desktop="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/share/applications/virt-manager.desktop"
sandbox_profiles="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/lib/python3.14/dist-packages/labwc_managed_app/profiles.py"
apparmor_policy="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/managed-desktop-wrappers"
firstboot_wrapper="$ROOT_DIR/d-i/forky/scripts/firstboot/firstboot.sh"
firstboot_core="$ROOT_DIR/d-i/forky/scripts/late/core.sh"
desktop_components="$ROOT_DIR/d-i/forky/scripts/desktop/components.sh"

if grep -q '^Name: qemu$' "$addons_cfg" &&
   grep -q '^RequiresClasses: role/desktop$' "$addons_cfg" &&
   grep -q '^DebianAptPreferences: zabbly$' "$addons_cfg" &&
   grep -q '^LateHelper: qemu$' "$addons_cfg"; then
  pass "qemu addon metadata requires the desktop role, pins Zabbly, and wires the late helper"
else
  fail "qemu addon metadata requires the desktop role, pins Zabbly, and wires the late helper"
fi

qemu_pkgsel=$(pkgsel_line "$qemu_class")
if word_list_has "$qemu_pkgsel" qemu-system-x86 &&
   word_list_has "$qemu_pkgsel" qemu-system-modules-opengl &&
   word_list_has "$qemu_pkgsel" ovmf &&
   word_list_has "$qemu_pkgsel" virt-manager &&
   word_list_has "$qemu_pkgsel" virt-install &&
   word_list_has "$qemu_pkgsel" virt-viewer &&
   word_list_has "$qemu_pkgsel" vagrant/trixie &&
   word_list_has "$qemu_pkgsel" vagrant-libvirt/trixie &&
   word_list_has "$qemu_pkgsel" libvirt-common &&
   word_list_has "$qemu_pkgsel" libvirt-daemon &&
   word_list_has "$qemu_pkgsel" libvirt-daemon-common &&
   word_list_has "$qemu_pkgsel" libvirt-daemon-config-nwfilter &&
   word_list_has "$qemu_pkgsel" libvirt-daemon-driver-network &&
   word_list_has "$qemu_pkgsel" libvirt-daemon-driver-nodedev &&
   word_list_has "$qemu_pkgsel" libvirt-daemon-driver-nwfilter &&
   word_list_has "$qemu_pkgsel" libvirt-daemon-driver-qemu &&
   word_list_has "$qemu_pkgsel" libvirt-daemon-driver-secret &&
   word_list_has "$qemu_pkgsel" libvirt-daemon-driver-storage &&
   word_list_has "$qemu_pkgsel" libvirt-daemon-log &&
   word_list_has "$qemu_pkgsel" libvirt-daemon-lock &&
   word_list_has "$qemu_pkgsel" libvirt-daemon-plugin-lockd &&
   ! word_list_has "$qemu_pkgsel" libvirt-daemon-system &&
   word_list_has "$qemu_pkgsel" incus &&
   word_list_has "$qemu_pkgsel" incus-client &&
   word_list_has "$qemu_pkgsel" incus-ui-canonical &&
   word_list_has "$qemu_pkgsel" lxc &&
   word_list_has "$qemu_pkgsel" lxcfs &&
   ! word_list_has "$qemu_pkgsel" fuse-overlayfs &&
   word_list_has "$qemu_pkgsel" virtiofsd &&
   word_list_has "$qemu_pkgsel" passt &&
   word_list_has "$qemu_pkgsel" uidmap &&
   grep -q '^d-i apt-setup/local17/repository string https://pkgs.zabbly.com/incus/stable trixie main$' "$qemu_class" &&
   grep -q '^d-i apt-setup/local17/key string https://pkgs.zabbly.com/key.asc$' "$qemu_class"; then
  pass "qemu addon preserves GUI clients and installs QEMU OpenGL plus libvirtd with explicit split drivers without the system meta-package"
else
  fail "qemu addon preserves GUI clients and installs QEMU OpenGL plus libvirtd with explicit split drivers without the system meta-package"
fi

if grep -q '^DIR_POOL_LIBVIRT="${DIR_POOL}/libvirt"$' "$runtime_env" &&
   grep -q '^DIR_POOL_LIBVIRT_SESSION="${DIR_POOL_LIBVIRT}/session"$' "$runtime_env" &&
   ! grep -q '^DIR_POOL_LIBVIRT_SYSTEM=' "$runtime_env" &&
   grep -q '^DIR_POOL_INCUS="${DIR_POOL}/incus"$' "$runtime_env" &&
   grep -q '^DIR_POOL_LXC="${DIR_POOL}/lxc"$' "$runtime_env" &&
   grep -q '^DIR_POOL_VAGRANT="${DIR_POOL}/vagrant"$' "$runtime_env" &&
   ! grep -q '^QEMU_LIBVIRT_POOL_NAME=' "$desktop_env"; then
  pass "shared policy exposes only session libvirt, Incus, LXC, and Vagrant storage roots"
else
  fail "shared policy exposes only session libvirt, Incus, LXC, and Vagrant storage roots"
fi

if grep -q '^QEMU_INCUS_HTTPS_ADDRESS=":8443"$' "$desktop_env" &&
   grep -q '^QEMU_INCUS_HTTPS_PORT="8443"$' "$desktop_env" &&
   grep -q '^Package: incus-ui-canonical$' "$zabbly_pref" &&
   grep -q '^Pin: origin pkgs.zabbly.com$' "$zabbly_pref" &&
   grep -q '^Pin-Priority: 950$' "$zabbly_pref"; then
  pass "desktop profile policy and target APT pinning prefer only the Zabbly Incus UI package"
else
  fail "desktop profile policy and target APT pinning prefer only the Zabbly Incus UI package"
fi

if grep -q 'installer_selected_class_reference_is_selected addon/qemu' "$helper" &&
   grep -q 'addon/qemu is restricted to the desktop role' "$helper" &&
   grep -Fq 'install -d -o root -g root -m 0755' "$helper" &&
   grep -Fq 'install -o root -g root -m "$mode"' "$helper" &&
   ! grep -Eq '(^|[[:space:]])stat([[:space:]]|$)' "$helper" &&
   grep -Fq 'for group_name in kvm incus incus-admin; do' "$helper" &&
   ! grep -Eq 'for group_name in .*libvirt' "$helper" &&
   grep -Fq 'for qemu_user_daemon in virtlockd virtlogd; do' "$helper" &&
   grep -Fq '"/etc/systemd/user/managed-${qemu_user_daemon}.service"' "$helper" &&
   grep -q '/etc/systemd/user/managed-libvirt-runtime.service' "$helper" &&
   grep -q '/etc/systemd/user/libvirt-session.service' "$helper" &&
   grep -q '/etc/systemd/user/virt-session-storage.service' "$helper" &&
   grep -q '/usr/local/libexec/lxcfs-stop' "$helper" &&
   grep -q '/etc/systemd/system/lxcfs.service.d/20-managed-stop.conf' "$helper" &&
   grep -q '^ExecStop=$' "$lxcfs_stop_dropin" &&
   grep -q '^ExecStop=/usr/local/libexec/lxcfs-stop$' "$lxcfs_stop_dropin" &&
   grep -q '^ExecStopPost=$' "$lxcfs_stop_dropin" &&
   grep -q '^ExecStopPost=/usr/local/libexec/lxcfs-stop$' "$lxcfs_stop_dropin" &&
   grep -q '^TimeoutStopSec=15s$' "$lxcfs_stop_dropin" &&
   grep -q '^mountpoint=/var/lib/lxcfs$' "$lxcfs_stop_script" &&
   grep -q '^\[ "\$mount_type" = fuse\.lxcfs \] ||$' "$lxcfs_stop_script" &&
   grep -q '^while \[ "\$attempt" -le 3 \]; do$' "$lxcfs_stop_script" &&
   grep -Fq 'if "$fusermount_bin" -uz "$mountpoint" 2>/dev/null; then' "$lxcfs_stop_script" &&
   grep -Fq 'A lazy-detached FUSE mount can remain visible' "$lxcfs_stop_script" &&
   grep -q 'failed to lazy-detach .* after bounded normal unmount attempts' "$lxcfs_stop_script" &&
   ! grep -q 'failed to detach .* after bounded normal and lazy unmount attempts' "$lxcfs_stop_script" &&
   grep -Fq 'for qemu_system_daemon in libvirtd virtlogd virtlockd; do' "$helper" &&
   grep -Fq '"/etc/systemd/system/${qemu_system_daemon}.service.d/20-managed-logging.conf"' "$helper" &&
   grep -q '/etc/libvirt/managed/session-default-pool.xml' "$helper" &&
   grep -q '/etc/libvirt/managed/virtops-network.xml' "$helper" &&
   grep -Fq 'for qemu_system_config in libvirtd virtlockd virtlogd; do' "$helper" &&
   grep -q '/usr/share/glib-2.0/schemas/91-virt-manager-session.gschema.override' "$helper" &&
   grep -q '/etc/rsyslog.d/43-libvirt.conf' "$helper" &&
   grep -q '/etc/logrotate.d/libvirt-managed' "$helper" &&
   grep -q '/etc/environment.d/72-libvirt-session.conf' "$helper" &&
   grep -Fq 'install -d -m 0700 "${target_root}${ACCOUNT_HOME}/.config/libvirt"' "$helper" &&
   grep -Fq 'install -d -m 0700 "${target_root}${ACCOUNT_HOME}/.vagrant.d"' "$helper" &&
   grep -q '/usr/sbin/libvirtd' "$helper" &&
   grep -q '/usr/sbin/virtlogd' "$helper" &&
   grep -q '/usr/sbin/virtlockd' "$helper" &&
   grep -q 'libvirt_driver_network.so' "$helper" &&
   grep -q 'libvirt_driver_nodedev.so' "$helper" &&
   grep -q 'libvirt_driver_nwfilter.so' "$helper" &&
   grep -q 'libvirt_driver_qemu.so' "$helper" &&
   grep -q 'libvirt_driver_secret.so' "$helper" &&
   grep -q 'libvirt_driver_storage.so' "$helper" &&
   grep -q 'libvirt-daemon-system must not be installed' "$helper" &&
   ! grep -q 'qemu_mask_target_unit' "$helper" &&
   ! grep -Eq 'virtqemud|virtstoraged|virtnetworkd' "$helper" &&
   ! grep -q '/etc/xdg/virt-manager' "$helper" &&
   ! grep -q 'stage_target_systemd_unit_enabled' "$helper" &&
   ! grep -q 'systemctl --root=/ enable' "$helper" &&
   grep -Fq 'ln -sfn \' "$helper" &&
   grep -Fq '/etc/systemd/system/virt-host-managed.service \' "$helper" &&
   grep -Fq 'libvirtd with explicit split drivers' "$helper" &&
   grep -q '/etc/systemd/system/libvirtd.service.d' "$sandbox_profiles" &&
   grep -q '/etc/systemd/system/virtlogd.service.d' "$sandbox_profiles" &&
   grep -q '/etc/systemd/system/virtlockd.service.d' "$sandbox_profiles" &&
   grep -q '/etc/systemd/user/managed-libvirt-runtime.service' "$sandbox_profiles" &&
   grep -q '/etc/systemd/user/libvirt-session.service' "$sandbox_profiles" &&
   grep -q '/etc/systemd/user/managed-virtlockd.service' "$sandbox_profiles" &&
   grep -q '/etc/systemd/user/managed-virtlogd.service' "$sandbox_profiles" &&
   grep -q 'managed-libvirt-runtime.service' "$apparmor_policy" &&
   ! grep -Eq 'managed-virtqemud|managed-virtstoraged|managed-virtnetworkd' "$sandbox_profiles" &&
   ! grep -q '/etc/xdg/virt-manager' "$sandbox_profiles"; then
  pass "qemu late staging verifies split drivers and installs libvirtd-based administrator policy"
else
  fail "qemu late staging verifies split drivers and installs libvirtd-based administrator policy"
fi

if lxcfs_stop_helper_works; then
  pass "lxcfs stop retries normal unmounts, accepts validated lazy-detach draining, and rejects foreign filesystems"
else
  fail "lxcfs stop retries normal unmounts, accepts validated lazy-detach draining, and rejects foreign filesystems"
fi

if grep -q '^d __INSTALLER_DIR_POOL_LIBVIRT__ 0755 root root -$' "$managed_tmpfiles" &&
   grep -q '^d __INSTALLER_DIR_POOL_LIBVIRT_SESSION__ 0711 root root -$' "$managed_tmpfiles" &&
   grep -q '^d __INSTALLER_DIR_POOL_LIBVIRT_SESSION__/__INSTALLER_ACCOUNT_USERNAME__ 0700 __INSTALLER_ACCOUNT_USERNAME__ __INSTALLER_ACCOUNT_USERNAME__ -$' "$managed_tmpfiles" &&
   grep -q '^d __INSTALLER_DIR_POOL_LIBVIRT_SESSION__/__INSTALLER_ACCOUNT_USERNAME__/images 0700 __INSTALLER_ACCOUNT_USERNAME__ __INSTALLER_ACCOUNT_USERNAME__ -$' "$managed_tmpfiles" &&
   grep -q '^d /var/log/managed/libvirt 0751 root adm -$' "$managed_tmpfiles" &&
   grep -q '^f /var/log/managed/libvirt/daemons.log 0640 root adm -$' "$managed_tmpfiles" &&
   grep -q '^d /var/log/managed/libvirt/__INSTALLER_ACCOUNT_USERNAME__/cache/libvirt/qemu/log 0700 __INSTALLER_ACCOUNT_USERNAME__ __INSTALLER_ACCOUNT_USERNAME__ -$' "$managed_tmpfiles" &&
   grep -Fq '$programname == "libvirtd"' "$libvirt_rsyslog" &&
   grep -Fq '$programname == "managed-libvirt-runtime"' "$libvirt_rsyslog" &&
   grep -Fq '$programname == "virt-session-storage"' "$libvirt_rsyslog" &&
   grep -Fq '$programname == "virt-host-managed"' "$libvirt_rsyslog" &&
   ! grep -Eq 'virtqemud|virtstoraged|virtnetworkd' "$libvirt_rsyslog" &&
   grep -Fq '$programname == "virtlogd"' "$libvirt_rsyslog" &&
   grep -Fq '$programname == "virtlockd"' "$libvirt_rsyslog" &&
   grep -Fq 'set $.managed_security_routed = "on";' "$libvirt_rsyslog" &&
   grep -Fq 'file="/var/log/managed/libvirt/daemons.log"' "$libvirt_rsyslog" &&
   grep -Fxq '/var/log/managed/libvirt/daemons.log' "$libvirt_logrotate" &&
   grep -Eq '^[[:space:]]*maxsize 16M$' "$libvirt_logrotate" &&
   grep -q '^allow __INSTALLER_QEMU_LIBVIRT_NETWORK_BRIDGE__$' "$bridge_template" &&
   [ "$(grep -Ec '^(allow|include|deny) ' "$bridge_template")" -eq 1 ]; then
  pass "tmpfiles, rsyslog, logrotate, and bridge policy retain managed virtualization state safely"
else
  fail "tmpfiles, rsyslog, logrotate, and bridge policy retain managed virtualization state safely"
fi

journal_only_units=true
for unit_path in \
  "$managed_unit" \
  "$libvirt_runtime_unit" \
  "$libvirt_session_unit" \
  "$session_storage_unit" \
  "$virtlockd_unit" \
  "$virtlogd_unit" \
  "$libvirtd_logging_dropin" \
  "$virtlockd_logging_dropin" \
  "$virtlogd_logging_dropin"; do
  if grep -Eq '^Standard(Output|Error)=journal\+console$' "$unit_path" ||
     ! grep -q '^StandardOutput=journal$' "$unit_path" ||
     ! grep -q '^StandardError=journal$' "$unit_path"
  then
    journal_only_units=false
  fi
done
if [ "$journal_only_units" = true ] &&
   grep -q '^SyslogIdentifier=virt-host-managed$' "$managed_unit" &&
   grep -q '^SyslogIdentifier=managed-libvirt-runtime$' "$libvirt_runtime_unit" &&
   grep -q '^SyslogIdentifier=virt-session-storage$' "$session_storage_unit" &&
   grep -q '^StandardOutput=journal$' "$libvirtd_logging_dropin" &&
   grep -q '^StandardError=journal$' "$libvirtd_logging_dropin" &&
   grep -q '^SyslogIdentifier=libvirtd$' "$libvirtd_logging_dropin"; then
  pass "managed virtualization services use journal-only output and never copy records to a console"
else
  fail "managed virtualization services use journal-only output and never copy records to a console"
fi

libvirt_configs_ok=true
for config_name in libvirtd virtlockd virtlogd; do
  grep -q '^log_outputs = "3:journald"$' "$system_libvirt_dir/${config_name}.conf" ||
    libvirt_configs_ok=false
done
for config_name in libvirtd virtlockd; do
  grep -q '^log_outputs = "3:journald"$' "$user_libvirt_dir/${config_name}.conf" ||
    libvirt_configs_ok=false
done
if [ "$libvirt_configs_ok" = true ] &&
   grep -q '^uri_default = "qemu:///session"$' "$system_libvirt_dir/libvirt.conf" &&
   grep -q '^remote_mode = "legacy"$' "$system_libvirt_dir/libvirt.conf" &&
   grep -q '"session-storage=qemu:///session"' "$system_libvirt_dir/libvirt.conf" &&
   grep -q '"system-network=qemu:///system"' "$system_libvirt_dir/libvirt.conf" &&
   grep -q 'explicit split driver packages' "$system_libvirt_dir/libvirtd.conf" &&
   grep -q '^lock_manager = "lockd"$' "$system_libvirt_dir/qemu.conf" &&
   grep -q '^stdio_handler = "logd"$' "$system_libvirt_dir/qemu.conf" &&
   grep -q '^uri_default = "qemu:///session"$' "$user_libvirt_dir/libvirt.conf" &&
   grep -q '^remote_mode = "legacy"$' "$user_libvirt_dir/libvirt.conf" &&
   grep -q '"session-storage=qemu:///session"' "$user_libvirt_dir/libvirt.conf" &&
   ! grep -q 'qemu:///system' "$user_libvirt_dir/libvirt.conf" &&
   grep -q '^log_outputs = "3:journald"$' "$user_libvirt_dir/libvirtd.conf" &&
   grep -q '^security_driver = "none"$' "$user_libvirt_dir/qemu.conf" &&
   grep -q '^lock_manager = "lockd"$' "$user_libvirt_dir/qemu.conf" &&
   grep -q '^stdio_handler = "logd"$' "$user_libvirt_dir/qemu.conf" &&
   grep -q '^max_size = 2097152$' "$system_libvirt_dir/virtlogd.conf" &&
   grep -q '^max_age_days = 7$' "$user_libvirt_dir/virtlogd.conf.tmpl" &&
   grep -q '^log_root = "/var/log/managed/libvirt/__INSTALLER_ACCOUNT_USERNAME__/cache/libvirt/qemu"$' "$user_libvirt_dir/virtlogd.conf.tmpl" &&
   grep -Fxq 'LIBVIRT_AUTOSTART=0' "$libvirt_environment" &&
   [ ! -e "$system_libvirt_dir/virtqemud.conf" ] &&
   [ ! -e "$system_libvirt_dir/virtstoraged.conf" ] &&
   [ ! -e "$system_libvirt_dir/virtnetworkd.conf" ]; then
  pass "system and user libvirt configs select legacy libvirtd mode, journald, logd, and lockd"
else
  fail "system and user libvirt configs select legacy libvirtd mode, journald, logd, and lockd"
fi

if grep -Fq "uris=['qemu:///session']" "$virt_manager_schema" &&
   grep -Fq "autoconnect=['qemu:///session']" "$virt_manager_schema" &&
   grep -Fq "image-default='__INSTALLER_DIR_POOL_LIBVIRT_SESSION__/__INSTALLER_ACCOUNT_USERNAME__/images'" "$virt_manager_schema" &&
   grep -Fq "cpu-default='host-passthrough'" "$virt_manager_schema" &&
   grep -Fq "graphics-type='spice'" "$virt_manager_schema" &&
   grep -Fq "storage-format='qcow2'" "$virt_manager_schema" &&
   grep -q 'libvirt.qemu_use_session = true' "$vagrant_global" &&
   grep -q 'libvirt.uri = "qemu:///session"' "$vagrant_global" &&
   grep -q 'libvirt.system_uri = "qemu:///session"' "$vagrant_global" &&
   grep -q 'libvirt.storage_pool_name = "default"' "$vagrant_global" &&
   grep -q 'libvirt.storage_pool_path = "__INSTALLER_DIR_POOL_LIBVIRT_SESSION__/__INSTALLER_ACCOUNT_USERNAME__/images"' "$vagrant_global" &&
   grep -q 'libvirt.management_network_device = "__INSTALLER_QEMU_LIBVIRT_NETWORK_BRIDGE__"' "$vagrant_global" &&
   [ ! -e "$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/xdg/virt-manager/virt-manager.conf" ] &&
   [ ! -e "$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/virt-manager/virt-manager.conf" ]; then
  pass "virt-manager and Vagrant use the session default pool and managed image directory"
else
  fail "virt-manager and Vagrant use the session default pool and managed image directory"
fi

units_ok=true
rendered_runtime_unit="$TMP_DIR/managed-libvirt-runtime.service"
render_template "$libvirt_runtime_unit" "$rendered_runtime_unit" \
  ACCOUNT_USERNAME desktop ||
  units_ok=false
grep -q '^ConditionUser=desktop$' "$rendered_runtime_unit" || units_ok=false
grep -q '^StopWhenUnneeded=yes$' "$rendered_runtime_unit" || units_ok=false
grep -q '^Before=managed-virtlogd.service managed-virtlockd.service libvirt-session.service$' "$rendered_runtime_unit" ||
  units_ok=false
grep -q '^Type=oneshot$' "$rendered_runtime_unit" || units_ok=false
grep -q '^ExecStart=/usr/bin/true$' "$rendered_runtime_unit" || units_ok=false
grep -q '^RemainAfterExit=yes$' "$rendered_runtime_unit" || units_ok=false
grep -q '^RuntimeDirectory=libvirt$' "$rendered_runtime_unit" || units_ok=false
grep -q '^RuntimeDirectoryMode=0700$' "$rendered_runtime_unit" || units_ok=false
grep -q '^StandardOutput=journal$' "$rendered_runtime_unit" || units_ok=false
grep -q '^StandardError=journal$' "$rendered_runtime_unit" || units_ok=false
grep -q '^SyslogIdentifier=managed-libvirt-runtime$' "$rendered_runtime_unit" ||
  units_ok=false
! grep -q '^\[Install\]$' "$rendered_runtime_unit" || units_ok=false
! grep -q '^WantedBy=' "$rendered_runtime_unit" || units_ok=false
for daemon_name in virtlockd virtlogd; do
  unit_template="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/systemd/user/managed-${daemon_name}.service.tmpl"
  rendered_unit="$TMP_DIR/managed-${daemon_name}.service"
  render_template "$unit_template" "$rendered_unit" ACCOUNT_USERNAME desktop ||
    units_ok=false
  grep -q '^Type=notify$' "$rendered_unit" || units_ok=false
  grep -q '^Environment=LIBVIRT_AUTOSTART=0$' "$rendered_unit" || units_ok=false
  grep -q '^Environment=XDG_CONFIG_HOME=%h/.config$' "$rendered_unit" || units_ok=false
  grep -q '^Environment=XDG_CACHE_HOME=/var/log/managed/libvirt/desktop/cache$' "$rendered_unit" || units_ok=false
  grep -q '^Environment=XDG_RUNTIME_DIR=%t$' "$rendered_unit" || units_ok=false
  grep -q "^ExecStart=/usr/sbin/${daemon_name}$" "$rendered_unit" ||
    units_ok=false
  grep -q '^Requires=managed-libvirt-runtime.service$' "$rendered_unit" ||
    units_ok=false
  grep -q '^After=managed-libvirt-runtime.service$' "$rendered_unit" ||
    units_ok=false
  grep -q '^StopWhenUnneeded=yes$' "$rendered_unit" || units_ok=false
  ! grep -q '^RuntimeDirectory=' "$rendered_unit" || units_ok=false
  ! grep -q '^RuntimeDirectoryPreserve=' "$rendered_unit" || units_ok=false
  grep -q '^Restart=on-failure$' "$rendered_unit" || units_ok=false
  grep -q '^StandardOutput=journal$' "$rendered_unit" || units_ok=false
  grep -q '^StandardError=journal$' "$rendered_unit" || units_ok=false
  grep -q "^SyslogIdentifier=${daemon_name}$" "$rendered_unit" || units_ok=false
  ! grep -q '^\[Install\]$' "$rendered_unit" || units_ok=false
  ! grep -q '^WantedBy=' "$rendered_unit" || units_ok=false
done
rendered_libvirt_session_unit="$TMP_DIR/libvirt-session.service"
render_template "$libvirt_session_unit" "$rendered_libvirt_session_unit" \
  ACCOUNT_USERNAME desktop ||
  units_ok=false
grep -q '^Requires=managed-libvirt-runtime.service managed-virtlogd.service managed-virtlockd.service$' "$rendered_libvirt_session_unit" ||
  units_ok=false
grep -q '^Requisite=labwc-session.target$' "$rendered_libvirt_session_unit" ||
  units_ok=false
grep -q '^After=labwc-session.target managed-libvirt-runtime.service managed-virtlogd.service managed-virtlockd.service$' "$rendered_libvirt_session_unit" ||
  units_ok=false
grep -q '^PartOf=labwc-session.target$' "$rendered_libvirt_session_unit" ||
  units_ok=false
grep -q '^ExecStart=/usr/sbin/libvirtd --timeout 30$' "$rendered_libvirt_session_unit" ||
  units_ok=false
! grep -q '^RuntimeDirectory=' "$rendered_libvirt_session_unit" || units_ok=false
! grep -q '^RuntimeDirectoryPreserve=' "$rendered_libvirt_session_unit" ||
  units_ok=false
grep -q '^StandardOutput=journal$' "$rendered_libvirt_session_unit" ||
  units_ok=false
grep -q '^StandardError=journal$' "$rendered_libvirt_session_unit" ||
  units_ok=false
grep -q '^SyslogIdentifier=libvirtd$' "$rendered_libvirt_session_unit" ||
  units_ok=false
! grep -q '^\[Install\]$' "$rendered_libvirt_session_unit" || units_ok=false
rendered_storage_unit="$TMP_DIR/virt-session-storage.service"
render_template "$session_storage_unit" "$rendered_storage_unit" \
  ACCOUNT_USERNAME desktop \
  DIR_POOL_LIBVIRT_SESSION /pool/libvirt/session ||
  units_ok=false
grep -q '^Requires=libvirt-session.service$' "$rendered_storage_unit" ||
  units_ok=false
grep -q '^After=libvirt-session.service$' "$rendered_storage_unit" ||
  units_ok=false
grep -q '^StopWhenUnneeded=yes$' "$rendered_storage_unit" || units_ok=false
grep -q '^ConditionPathExists=/etc/libvirt/managed/session-default-pool.xml$' "$rendered_storage_unit" ||
  units_ok=false
! grep -q '^ConditionPathIsRegularFile=' "$rendered_storage_unit" ||
  units_ok=false
grep -q '^Environment=LIBVIRT_AUTOSTART=0$' "$rendered_storage_unit" ||
  units_ok=false
grep -q '^ExecStart=/usr/local/libexec/virt-session-storage /etc/libvirt/managed/session-default-pool.xml /pool/libvirt/session/desktop/images$' "$rendered_storage_unit" ||
  units_ok=false
grep -q '^RemainAfterExit=yes$' "$rendered_storage_unit" || units_ok=false
grep -q '^StandardOutput=journal$' "$rendered_storage_unit" || units_ok=false
grep -q '^StandardError=journal$' "$rendered_storage_unit" || units_ok=false
grep -q '^SyslogIdentifier=virt-session-storage$' "$rendered_storage_unit" ||
  units_ok=false
! grep -q '^RuntimeDirectory=' "$rendered_storage_unit" || units_ok=false
! grep -q '^RuntimeDirectoryPreserve=' "$rendered_storage_unit" ||
  units_ok=false
! grep -q '^\[Install\]$' "$rendered_storage_unit" || units_ok=false
! grep -q '^WantedBy=' "$rendered_storage_unit" || units_ok=false
runtime_owner_count=$(
  grep -h '^RuntimeDirectory=libvirt$' \
    "$rendered_runtime_unit" \
    "$TMP_DIR"/managed-virtlockd.service \
    "$TMP_DIR"/managed-virtlogd.service \
    "$rendered_libvirt_session_unit" \
    "$rendered_storage_unit" |
    wc -l |
    tr -d '[:space:]'
)
if [ "$units_ok" = true ] &&
   [ "$runtime_owner_count" -eq 1 ] &&
   [ ! -e "$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/systemd/user/managed-virtqemud.service.tmpl" ] &&
   [ ! -e "$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/systemd/user/managed-virtstoraged.service.tmpl" ] &&
   [ ! -e "$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/systemd/system/managed-virtnetworkd.service" ]; then
  pass "rendered libvirtd, log, lock, and storage units are on-demand, bounded, and never login-enabled"
else
  fail "rendered libvirtd, log, lock, and storage units are on-demand, bounded, and never login-enabled"
fi

if /bin/sh -n "$vagrant_profile" &&
   /bin/sh -n "$virt_manager_wrapper" &&
   grep -q '^LIBVIRT_AUTOSTART=0$' "$vagrant_profile" &&
   grep -q '^virtops_validate_services() ($' "$vagrant_profile" &&
   grep -Fq '"${HOME}/.config/libvirt/${virtops_config_name}" \' "$vagrant_profile" &&
   grep -Fq '      600 ||' "$vagrant_profile" &&
   grep -Fq '/usr/bin/systemd-run \' "$vagrant_profile" &&
   grep -Fq -- '--scope \' "$vagrant_profile" &&
   grep -Fq -- '--same-dir \' "$vagrant_profile" &&
   grep -Fq -- '--expand-environment=no \' "$vagrant_profile" &&
   grep -Fq -- '--property=Requires=virt-session-storage.service \' "$vagrant_profile" &&
   grep -Fq -- '--property=After=virt-session-storage.service \' "$vagrant_profile" &&
   grep -Fq '/usr/bin/virsh -c qemu:///session event --all --loop' "$vagrant_profile" &&
   grep -Fq '"$1" -i' "$vagrant_profile" &&
   grep -Fq 'Entering virtualization environment; exit to return' "$vagrant_profile" &&
   grep -Fqx '  virtops_activate' "$vagrant_profile" &&
   ! grep -Fq 'VIRTOPS_ACTIVE' "$vagrant_profile" &&
   ! grep -Fq 'virtops_deactivate' "$vagrant_profile" &&
   ! grep -Fq 'virtops_child_path' "$vagrant_profile" &&
   ! grep -Fq '/usr/local/bin/labwc-terminal' "$vagrant_profile" &&
   grep -Fq '__INSTALLER_DIR_POOL_VAGRANT__/${USER}/home' "$vagrant_profile" &&
   grep -Fq 'virtops_account_owned_path_is_mode file "${VAGRANT_HOME}/Vagrantfile" 600' "$vagrant_profile" &&
   sed -n '/install -d -m 0700 "${target_root}${DIR_POOL_VAGRANT}\/${ACCOUNT_USERNAME}\/home"/,+3p' "$helper" |
     grep -Fq 'install -m 0600' &&
   grep -Fq '__INSTALLER_DIR_POOL_LIBVIRT_SESSION__/${USER}/images' "$vagrant_profile" &&
   ! grep -Fq '/usr/bin/systemctl --user start virt-session-storage.service' "$vagrant_profile" &&
   ! grep -Eq 'storage:///session|virtqemud|virtstoraged' "$vagrant_profile" &&
   grep -Fq -- '--managed-client' "$virt_manager_wrapper" &&
   grep -Fq -- '--service-type=exec \' "$virt_manager_wrapper" &&
   grep -Fq -- '--property=Requires=virt-session-storage.service \' "$virt_manager_wrapper" &&
   grep -Fq -- "--property='After=labwc-session.target virt-session-storage.service' \\" "$virt_manager_wrapper" &&
   grep -Fq -- '--property=PartOf=labwc-session.target \' "$virt_manager_wrapper" &&
   grep -Fq -- '--property=StandardOutput=journal \' "$virt_manager_wrapper" &&
   grep -Fq -- '--property=StandardError=journal \' "$virt_manager_wrapper" &&
   grep -Fq -- '--property=TimeoutStopSec=5s \' "$virt_manager_wrapper" &&
   grep -Fq '/usr/bin/{systemctl,systemd-run} pux,' "$apparmor_policy" &&
   grep -Fq 'LIBVIRT_AUTOSTART=0' "$virt_manager_wrapper" &&
   grep -Fq '/usr/bin/virt-manager --connect qemu:///session' "$virt_manager_wrapper" &&
   grep -q '^TryExec=/usr/local/bin/virt-manager-virtops$' "$virt_manager_desktop" &&
   grep -q '^Exec=/usr/local/bin/virt-manager-virtops$' "$virt_manager_desktop" &&
   grep -q '^DBusActivatable=false$' "$virt_manager_desktop"; then
  pass "virtops enters a marker-free same-terminal nested shell while virt-manager holds an independent on-demand libvirt client lease"
else
  fail "virtops enters a marker-free same-terminal nested shell while virt-manager holds an independent on-demand libvirt client lease"
fi

if grep -q '^ExecStart=/usr/local/libexec/virt-host-managed$' "$managed_unit" &&
   grep -q '^ExecStop=/usr/local/libexec/virt-host-managed --shutdown$' "$managed_unit" &&
   grep -Fxq 'Requires=libvirtd.service' "$managed_unit" &&
   grep -Fq 'incus-startup.service' "$managed_unit" &&
   grep -q '^TimeoutStopSec=30s$' "$managed_unit" &&
   ! grep -q 'managed-virtnetworkd.service' "$managed_unit" &&
   grep -Fxq 'Requires=virtlockd.socket' "$libvirtd_logging_dropin" &&
   grep -Fxq 'After=virtlockd.service' "$libvirtd_logging_dropin" &&
   grep -q '^RemainAfterExit=yes$' "$managed_unit" &&
   grep -q '^Restart=on-failure$' "$managed_unit" &&
   grep -q '^LIBVIRT_NETWORK_XML=/etc/libvirt/managed/virtops-network.xml$' "$managed_script" &&
   grep -q '^LIBVIRT_NETWORK_URI=qemu:///system$' "$managed_script" &&
   grep -q '^LIBVIRT_AUTOSTART=0$' "$managed_script" &&
   ! grep -Eq '^INCUS_DNSMASQ_|^INCUS_NETWORK_STATE_ROOT=|^INCUS_SERVICE_CGROUP=|^KILL_BIN=|^PROC_ROOT=' "$managed_script" &&
   ! grep -q "INCUS_SHUTDOWN_HELPER" "$managed_script" &&
   ! grep -q '/usr/libexec/incus/shutdown' "$managed_script" &&
   grep -q "''|--prepare-install|--shutdown|--validate-config" "$managed_script" &&
   grep -q '^shutdown_managed_virtualization() {$' "$managed_script" &&
   grep -q 'net-destroy "$network_name"' "$managed_script" &&
   grep -Fq 'Incus owns its managed bridge, firewall state, and dnsmasq child' "$managed_script" &&
   ! grep -Eq 'stop_incus_dnsmasq|validate_incus_dnsmasq|dnsmasq\\.pid|(^|[[:space:]])(kill|pkill|killall)([[:space:]]|$)' "$managed_script" &&
   grep -q 'validate_managed_libvirt_network_xml()' "$managed_script" &&
   grep -q 'virsh -c "$LIBVIRT_NETWORK_URI" net-define "$network_xml"' "$managed_script" &&
   ! grep -q '/tmp/libvirt-network' "$managed_script" &&
   ! grep -Eq 'network:///system|virtqemud|virtstoraged|virtnetworkd' "$managed_script" &&
   ! grep -q 'virsh .* pool-' "$managed_script" &&
   ! grep -q 'ensure_libvirt_pool' "$managed_script" &&
   grep -q '/usr/sbin/libvirtd' "$managed_script" &&
   grep -q '/usr/libexec/incus/shutdown' "$helper" &&
   grep -q '/usr/sbin/dnsmasq' "$helper" &&
   grep -q '/usr/lib/systemd/system/incus-startup.service' "$helper" &&
   grep -q '^VIRT_LIBVIRT_NETWORK_NAME=' "$managed_defaults" &&
   ! grep -q 'POOL_NAME\\|POOL_PATH\\|VIRT_VAGRANT' "$managed_defaults"; then
  pass "root bootstrap consumes rendered XML through the split-driver libvirtd system connection"
else
  fail "root bootstrap consumes rendered XML through the split-driver libvirtd system connection"
fi

if /bin/sh -n "$managed_script" &&
   managed_shutdown_helper_works; then
  pass "managed virtualization shutdown is idempotent and never crosses into Incus-owned process teardown"
else
  fail "managed virtualization shutdown is idempotent and never crosses into Incus-owned process teardown"
fi

if /bin/sh -n "$session_storage_script" &&
   session_storage_helper_works; then
  pass "session storage helper is idempotent, default-named, and rejects XML or pool drift"
else
  fail "session storage helper is idempotent, default-named, and rejects XML or pool drift"
fi

rendered_pool_xml="$TMP_DIR/session-default-pool.xml"
rendered_network_xml="$TMP_DIR/virtops-network.xml"
if render_template "$pool_xml_template" "$rendered_pool_xml" \
     ACCOUNT_USERNAME desktop \
     DIR_POOL_LIBVIRT_SESSION /pool/libvirt/session &&
   render_template "$network_xml_template" "$rendered_network_xml" \
     QEMU_LIBVIRT_NETWORK_NAME virtops \
     QEMU_LIBVIRT_NETWORK_BRIDGE virbr-virtops \
     QEMU_LIBVIRT_NETWORK_ADDRESS 192.168.121.1 \
     QEMU_LIBVIRT_NETWORK_NETMASK 255.255.255.0 \
     QEMU_LIBVIRT_NETWORK_DHCP_START 192.168.121.2 \
     QEMU_LIBVIRT_NETWORK_DHCP_END 192.168.121.254 &&
   python3 - "$rendered_pool_xml" "$rendered_network_xml" <<'PY'
from pathlib import Path
import sys
import xml.etree.ElementTree as ET

pool = ET.parse(Path(sys.argv[1])).getroot()
network = ET.parse(Path(sys.argv[2])).getroot()
assert pool.tag == "pool"
assert pool.attrib == {"type": "dir"}
assert pool.findtext("name") == "default"
assert pool.findtext("target/path") == "/pool/libvirt/session/desktop/images"
assert network.tag == "network"
assert network.findtext("name") == "virtops"
assert network.find("forward").attrib == {"mode": "nat"}
assert network.find("bridge").attrib["name"] == "virbr-virtops"
assert network.find("ip").attrib == {
    "address": "192.168.121.1",
    "netmask": "255.255.255.0",
}
assert network.find("ip/dhcp/range").attrib == {
    "start": "192.168.121.2",
    "end": "192.168.121.254",
}
PY
then
  pass "rendered libvirt pool and network XML are well-formed and retain the managed identities"
else
  fail "rendered libvirt pool and network XML are well-formed and retain the managed identities"
fi

if [ ! -e "$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-sandbox" ] &&
   [ ! -e "$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/share/incus/sandbox-blueprint.yaml.tmpl" ] &&
   [ ! -e "$ROOT_DIR/d-i/forky/scripts/firstboot/03a-sandbox-apps.sh" ] &&
   ! grep -q '03a-sandbox-apps.sh' "$firstboot_wrapper" &&
   ! grep -q '03a-sandbox-apps.sh' "$firstboot_core" &&
   ! grep -q 'LABWC_SANDBOX' "$desktop_env" &&
   ! grep -q 'labwc-sandbox' "$desktop_components"; then
  pass "qemu keeps Incus as a general host runtime without desktop app-container provisioning"
else
  fail "qemu keeps Incus as a general host runtime without desktop app-container provisioning"
fi

if grep -q 'nftables_qemu_selected()' "$security_script" &&
   grep -q '\[ "${INSTALLER_HOST_VARIANT:-}" = desktop \]' "$security_script" &&
   grep -q 'nftables_merge_selected_services "$effective_services" qemu' "$security_script" &&
   grep -q 'nftables_qemu_service_placeholder_map' "$security_script" &&
   ! grep -q 'LABWC_SANDBOX' "$security_script" &&
   grep -q '^metadata:$' "$qemu_nft" &&
   grep -q '^  name: qemu$' "$qemu_nft" &&
   grep -q '^  qemu_guest_dhcp_v4:$' "$qemu_nft" &&
   grep -q '^  qemu_incus_api_ui:$' "$qemu_nft" &&
   grep -q '^forwarding:$' "$qemu_nft" &&
   grep -q '^nat:$' "$qemu_nft" &&
   grep -q 'interfaces: __INSTALLER_NFTABLES_QEMU_ALLOW_INTERFACES__' "$qemu_nft" &&
   grep -q 'ipv4: __INSTALLER_NFTABLES_QEMU_HOST_ALLOW_IPV4__' "$qemu_nft" &&
   grep -q 'ipv6: __INSTALLER_NFTABLES_QEMU_HOST_ALLOW_IPV6__' "$qemu_nft" &&
   grep -q "duplicate-account conflict" "$swtpm_sysusers"; then
  pass "qemu addon merges only the managed libvirt and Incus network overlay"
else
  fail "qemu addon merges only the managed libvirt and Incus network overlay"
fi

[ "$FAIL_COUNT" -eq 0 ]
