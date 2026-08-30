#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
TEST_COUNT=15
TEST_INDEX=0
FAIL_COUNT=0
pass() { TEST_INDEX=$((TEST_INDEX + 1)); printf 'ok %s - %s\n' "$TEST_INDEX" "$1"; }
fail() { TEST_INDEX=$((TEST_INDEX + 1)); FAIL_COUNT=$((FAIL_COUNT + 1)); printf 'not ok %s - %s\n' "$TEST_INDEX" "$1"; }

class_cfg="$ROOT_DIR/d-i/forky/classes/class-addon/qemu.cfg"
addons_cfg="$ROOT_DIR/d-i/forky/classes/configs/addons.cfg"
late="$ROOT_DIR/d-i/forky/scripts/late/qemu.sh"
helper="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/libexec/incus-host-managed"
defaults="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/default/incus-host-managed.tmpl"
unit="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/systemd/system/incus-host-managed.service"
user_dropin="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/systemd/system/incus-user.service.d/20-managed-bootstrap.conf"
tmpfiles="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/tmpfiles.d/85-qemu-incus-storage.conf.tmpl"
profile="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.profile.d/72-incus.sh.tmpl"
runtime_env="$ROOT_DIR/d-i/forky/hosts/shared/runtime.env"
security="$ROOT_DIR/d-i/forky/scripts/late/security.sh"
nft="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/nftables/services/qemu.yml"
apparmor="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/managed-desktop-wrappers"

packages=$(sed -n 's/^d-i pkgsel\/include string //p' "$class_cfg")
required='qemu-system-x86 qemu-system-modules-opengl qemu-utils qemu-block-extra ovmf swtpm swtpm-tools virtiofsd passt incus incus-client incus-ui-canonical uidmap libosinfo-bin genisoimage'
forbidden='virt-manager virt-install virt-viewer libvirt-common libvirt-daemon libvirt-clients vagrant/trixie vagrant-libvirt/trixie lxc lxcfs lxc-templates bridge-utils dnsmasq-base'
ok=true
for pkg in $required; do case " $packages " in *" $pkg "*) ;; *) ok=false;; esac; done
for pkg in $forbidden; do case " $packages " in *" $pkg "*) ok=false;; esac; done
if $ok && grep -q 'direct QEMU/KVM and confined Incus' "$addons_cfg"; then pass 'addon package and metadata contract is QEMU/Incus only'; else fail 'addon package and metadata contract is QEMU/Incus only'; fi

if dash -n "$late" && dash -n "$helper" && dash -n "$profile" &&
   ! grep -Eq '(^|[[:space:]])\+([[:space:]]|$)' "$late"; then
  pass 'QEMU/Incus shell sources parse without patch-marker arguments'
else fail 'QEMU/Incus shell sources parse without patch-marker arguments'; fi

if grep -Fq '/opt/incus/lib/systemd/incusd' "$late" &&
   grep -Fq '/opt/incus/ui/index.html' "$late" &&
   grep -Fq 'incus-user.service' "$late" &&
   grep -Fq 'incus-user.socket' "$late" &&
   grep -Fq 'for group_name in kvm incus; do' "$late" &&
   grep -Fq 'primary account must not belong to root-equivalent incus-admin' "$late" &&
   ! grep -Eq 'for group_name in.*incus-admin|usermod.*incus-admin|libvirt|vagrant|lxcfs-stop|(^|[[:space:]/])lxcfs\.service|lxc-config|virt-manager|virsh' "$late"; then
  pass 'late helper separates restricted Incus users from Incus administrators'
else fail 'late helper separates restricted Incus users from Incus administrators'; fi

if grep -Fq 'incus-user.service' "$helper" &&
   grep -Fq 'SocketMode=0660' "$helper" &&
   grep -Fq 'SocketGroup=incus-admin' "$helper" &&
   grep -Fq 'SocketGroup=incus' "$helper" &&
   grep -Fq 'ListenStream=/var/lib/incus/unix\.socket' "$helper" &&
   grep -Fq 'ListenStream=/var/lib/incus/unix\.socket\.user' "$helper" &&
   grep -Fq 'incus-user.socket must activate only incus-user.service' "$helper" &&
   grep -Fq 'incus-user.service does not execute the restricted user broker' "$helper" &&
   grep -Fq 'validate_live_socket "Incus administrator socket" "$INCUS_ADMIN_SOCKET" incus-admin' "$helper" &&
   grep -Fq 'validate_live_socket "Incus restricted user socket" "$INCUS_USER_SOCKET" incus' "$helper"; then
  pass 'Incus bootstrap validates separate configured and live user/admin sockets'
else fail 'Incus bootstrap validates separate configured and live user/admin sockets'; fi

if grep -Fq 'security.privileged: "false"' "$helper" &&
   grep -Fq 'profile get default security.privileged' "$helper" &&
   grep -Fq 'Incus default profile must set security.privileged=false' "$helper"; then
  pass 'Incus default profile is explicitly unprivileged and verified'
else fail 'Incus default profile is explicitly unprivileged and verified'; fi

if grep -Fq 'config: {}' "$helper" &&
   grep -Fq 'config get core.https_address' "$helper" &&
   ! grep -Eq 'config set core\.https_address|core\.https_address:' "$helper" &&
   grep -Fq -- '--unix-socket "$INCUS_ADMIN_SOCKET"' "$helper" &&
   grep -Fq 'http://localhost/ui/' "$helper" &&
   grep -Fq 'INCUS_UI=/opt/incus/ui/' "$helper"; then
  pass 'Incus initializes without a remote listener and verifies the packaged UI locally'
else fail 'Incus initializes without a remote listener and verifies the packaged UI locally'; fi

if grep -Fxq 'Requires=incus.service incus.socket incus-user.socket incus-startup.service' "$unit" &&
   grep -Fxq 'After=incus.service incus.socket incus-user.socket incus-startup.service network-online.target systemd-tmpfiles-setup.service' "$unit" &&
   grep -Fxq 'ExecStart=/usr/local/libexec/incus-host-managed' "$unit" &&
   ! grep -q '^ExecStop=' "$unit" &&
   ! grep -q '^\[Install\]$\|^WantedBy=' "$unit" &&
   grep -Fxq 'Requires=incus-host-managed.service' "$user_dropin" &&
   grep -Fxq 'After=incus-host-managed.service' "$user_dropin" &&
   grep -Fxq 'StandardOutput=journal' "$unit" && grep -Fxq 'StandardError=journal' "$unit"; then
  pass 'restricted Incus user activation waits for static managed bootstrap'
else fail 'restricted Incus user activation waits for static managed bootstrap'; fi

if grep -Fq 'incus-startup.service' "$unit" &&
   grep -Fq 'qemu_disable_target_unit "$service_unit"' "$late" &&
   grep -Fq 'incus.service incus-lxcfs.service incus-startup.service incus-user.service' "$late" &&
   grep -Fq 'incus-host-managed.service' "$late" &&
   grep -Fq 'incus.socket /usr/lib/systemd/system/incus.socket sockets.target.wants' "$late" &&
   grep -Fq 'incus-user.socket /usr/lib/systemd/system/incus-user.socket sockets.target.wants' "$late" &&
   ! grep -Eq 'qemu_enable_unit (incus|incus-user|incus-startup|incus-host-managed)\.service' "$late"; then
  pass 'Incus services start only through sockets and retain package-owned graceful shutdown'
else fail 'Incus services start only through sockets and retain package-owned graceful shutdown'; fi

if grep -Fxq 'd __INSTALLER_DIR_POOL_QEMU__ 2770 root devops -' "$tmpfiles" &&
   grep -Fxq 'd __INSTALLER_DIR_POOL_INCUS__ 0711 root root -' "$tmpfiles" &&
   [ "$(grep -c '^d ' "$tmpfiles")" -eq 2 ] &&
   grep -Fxq 'DIR_POOL_QEMU="${DIR_POOL}/qemu"' "$runtime_env" &&
   grep -Fxq 'DIR_POOL_INCUS="${DIR_POOL}/incus"' "$runtime_env" &&
   ! grep -Eq 'DIR_POOL_(LIBVIRT|LXC|VAGRANT)' "$runtime_env"; then
  pass 'storage policy creates only managed QEMU and Incus roots'
else fail 'storage policy creates only managed QEMU and Incus roots'; fi

if grep -q '^incusops() {' "$profile" && grep -q '^incusui() {' "$profile" &&
   grep -Fq 'command incus "$@"' "$profile" &&
   grep -Fq 'command incus webui' "$profile" &&
   ! grep -Eq '(^|[[:space:]])sudo([[:space:]]|$)|--force-local' "$profile" &&
   ! grep -Eqi 'libvirt|vagrant|mode-0?700|stat -c' "$profile"; then
  pass 'profile runs the confined Incus client directly as the desktop user'
else fail 'profile runs the confined Incus client directly as the desktop user'; fi

profile_count=$(rg -l '^INCUS_BRIDGE_NAME="incusbr0"$' "$ROOT_DIR/d-i/forky/hosts/profiles" -g '*.env' | wc -l)
if [ "$profile_count" -eq 13 ] &&
   ! rg -q 'QEMU_LIBVIRT_|QEMU_INCUS_HTTPS_|QEMU_INCUS_BRIDGE_NAME' "$ROOT_DIR/d-i/forky/hosts/profiles" -g '*.env'; then
  pass 'all desktop profiles declare only the Incus bridge identity'
else fail 'all desktop profiles declare only the Incus bridge identity'; fi

if grep -Fq 'INCUS_BRIDGE_NAME' "$security" && ! grep -Eq 'QEMU_LIBVIRT|QEMU_INCUS_HTTPS|qemu_host_allow' "$security" &&
   grep -Fq '__INSTALLER_NFTABLES_QEMU_ALLOW_INTERFACES__' "$nft" &&
   ! grep -Eq 'qemu_incus_api_ui|INCUS_HTTPS|HOST_ALLOW' "$nft"; then
  pass 'firewall policy covers only the local Incus guest bridge and exposes no API port'
else fail 'firewall policy covers only the local Incus guest bridge and exposes no API port'; fi

legacy_assets=$(find "$ROOT_DIR/d-i/forky/hooks/role/desktop/target" -type f \( -path '*/etc/libvirt/*' -o -iname '*virt-manager*' -o -iname '*vagrant*' -o -iname '*lxcfs*' -o -iname '*virt-session*' -o -iname '*virtlockd*' -o -iname '*virtlogd*' \) -print)
if [ -z "$legacy_assets" ] && [ -x "$helper" ] && [ -r "$defaults" ] && [ -r "$unit" ]; then
  pass 'obsolete libvirt, Vagrant, classic-LXC, and GUI assets are absent'
else fail 'obsolete libvirt, Vagrant, classic-LXC, and GUI assets are absent'; fi

if grep -q '^profile managed-incus-host-managed ' "$apparmor" &&
   grep -Fq '  /var/lib/incus/unix.socket.user r,' "$apparmor" &&
   ! grep -Eq 'managed-(virt|lxc)|libvirt|vagrant|virt-manager|lxcfs|/pool/lxc' "$apparmor"; then
  pass 'AppArmor exposes one Incus-only host reconciliation profile'
else fail 'AppArmor exposes one Incus-only host reconciliation profile'; fi

if grep -Fxq 'allow __INSTALLER_INCUS_BRIDGE_NAME__' "$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/qemu/bridge.conf.tmpl" &&
   grep -Fq 'incus.socket /usr/lib/systemd/system/incus.socket sockets.target.wants' "$late" &&
   grep -Fq 'incus-user.socket /usr/lib/systemd/system/incus-user.socket sockets.target.wants' "$late" &&
   ! grep -Fq 'incus-host-managed.service /etc/systemd/system/incus-host-managed.service multi-user.target.wants' "$late"; then
  pass 'bridge and socket enablement use the Incus-only identities'
else fail 'bridge and socket enablement use the Incus-only identities'; fi

if [ "$TEST_INDEX" -ne "$TEST_COUNT" ]; then printf 'not ok - planned %s tests but ran %s\n' "$TEST_COUNT" "$TEST_INDEX"; exit 1; fi
[ "$FAIL_COUNT" -eq 0 ] || exit 1
printf '1..%s\n' "$TEST_COUNT"
