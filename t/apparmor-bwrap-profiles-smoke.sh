#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
ABSTRACTION_DIR="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/abstractions"
BWRAP_ABSTRACTION="$ABSTRACTION_DIR/managed-bwrap-common"
BWRAP_DESKTOP_RUNTIME="$ABSTRACTION_DIR/managed-bwrap-desktop-runtime"
DESKTOP_APPLICATION="$ABSTRACTION_DIR/managed-desktop-application"
DESKTOP_RUNTIME="$ABSTRACTION_DIR/managed-desktop-runtime"
DEVOPS_RUNTIME="$ABSTRACTION_DIR/managed-devops-toolchain-runtime"
CODEX_RUNTIME="$ABSTRACTION_DIR/managed-codex-runtime"
ELECTRON_RUNTIME="$ABSTRACTION_DIR/managed-electron-runtime"
ELECTRON_SANDBOX="$ABSTRACTION_DIR/managed-electron-application"
WEBKIT_RUNTIME="$ABSTRACTION_DIR/managed-webkit-runtime"
GRIDLINE_PROFILE="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/usr.bin.gridline"
TUTA_PROFILE="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/opt.tuta-mail.AppRun"
MULLVAD_LOCAL="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/local/mullvad-browser"
VIVALDI_LOCAL="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/local/vivaldi-bin"
WRAPPER_PROFILE="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/managed-desktop-wrappers"
SECURITY_SCRIPT="$ROOT_DIR/d-i/forky/scripts/late/security.sh"

TEST_COUNT=17
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

tuta_main_block() {
  awk '
    /^profile tuta-mail / { in_profile = 1 }
    in_profile && /^  profile tuta-bwrap / { exit }
    in_profile { print }
  ' "$TUTA_PROFILE"
}

tuta_bwrap_block() {
  awk '
    /^  profile tuta-bwrap / { in_profile = 1 }
    in_profile { print }
    in_profile && /^  }$/ { exit }
  ' "$TUTA_PROFILE"
}

tuta_glycin_block() {
  awk '
    /^profile tuta-glycin-loader / { in_profile = 1 }
    in_profile { print }
    in_profile && /^}$/ { exit }
  ' "$TUTA_PROFILE"
}

waypaper_main_block() {
  awk '
    /^profile managed-waypaper / { in_profile = 1 }
    in_profile && /^  profile waypaper-bwrap / { exit }
    in_profile { print }
  ' "$WRAPPER_PROFILE"
}

waypaper_child_block() {
  expected_profile=$1

  awk -v expected_profile="$expected_profile" '
    $0 ~ "^  profile " expected_profile " " { in_profile = 1 }
    in_profile { print }
    in_profile && /^  }$/ { exit }
  ' "$WRAPPER_PROFILE"
}

waypaper_glycin_block() {
  awk '
    /^profile waypaper-glycin-loader / { in_profile = 1 }
    in_profile { print }
    in_profile && /^}$/ { exit }
  ' "$WRAPPER_PROFILE"
}

codex_wrapper_block() {
  awk '
    /^profile managed-codex-wrapper / { in_profile = 1 }
    in_profile { print }
    in_profile && /^}$/ { exit }
  ' "$WRAPPER_PROFILE"
}

codex_bwrap_block() {
  awk '
    /^  profile codex-bwrap / { in_profile = 1 }
    in_profile { print }
    in_profile && /^  }$/ { exit }
  ' "$WRAPPER_PROFILE"
}

codex_runtime_block() {
  awk '
    /^profile managed-codex-runtime / { in_profile = 1 }
    in_profile { print }
    in_profile && /^}$/ { exit }
  ' "$WRAPPER_PROFILE"
}

chatgpt_wrapper_block() {
  awk '
    /^profile managed-labwc-chatgpt / { in_profile = 1 }
    in_profile { print }
    in_profile && /^}$/ { exit }
  ' "$WRAPPER_PROFILE"
}

chatgpt_bwrap_block() {
  awk '
    /^  profile chatgpt-bwrap / { in_profile = 1 }
    in_profile { print }
    in_profile && /^  }$/ { exit }
  ' "$WRAPPER_PROFILE"
}

chatgpt_slirp4netns_block() {
  awk '
    /^profile managed-chatgpt-slirp4netns / { in_profile = 1 }
    in_profile { print }
    in_profile && /^}$/ { exit }
  ' "$WRAPPER_PROFILE"
}

private_xwayland_library_rules_present() {
  for private_library_name in \
    libXau.so.6 \
    libXdmcp.so.6 \
    libXfont2.so.2 \
    libfontenc.so.1 \
    libxcb-cursor.so.0 \
    libxcb-image.so.0 \
    libxcb-render-util.so.0 \
    libxcb-render.so.0 \
    libxcb-shm.so.0 \
    libxcb-util.so.1 \
    libxcb.so.1 \
    libxcvt.so.0 \
    libxshmfence.so.1
  do
    grep -Fqx \
      "  /opt/xwayland/usr/lib/x86_64-linux-gnu/${private_library_name} r," \
      "$WRAPPER_PROFILE" &&
      grep -Fqx \
        "  /opt/xwayland/usr/lib/x86_64-linux-gnu/${private_library_name}.* r," \
        "$WRAPPER_PROFILE" &&
      grep -Fqx \
        "    /opt/xwayland/usr/lib/x86_64-linux-gnu/${private_library_name} mr," \
        "$WRAPPER_PROFILE" &&
      grep -Fqx \
        "    /opt/xwayland/usr/lib/x86_64-linux-gnu/${private_library_name}.* mr," \
        "$WRAPPER_PROFILE" ||
      return 1
  done
  ! grep -Fq \
    '    /usr/lib/x86_64-linux-gnu/libxcb-cursor.so.' \
    "$WRAPPER_PROFILE"
}

printf '1..%s\n' "$TEST_COUNT"

if grep -qx 'userns,' "$BWRAP_ABSTRACTION" &&
   grep -qx 'capability chown,' "$BWRAP_ABSTRACTION" &&
   grep -qx 'capability dac_override,' "$BWRAP_ABSTRACTION" &&
   grep -qx 'capability setgid,' "$BWRAP_ABSTRACTION" &&
   grep -qx 'capability setpcap,' "$BWRAP_ABSTRACTION" &&
   grep -qx 'capability setuid,' "$BWRAP_ABSTRACTION" &&
   grep -qx 'capability net_admin,' "$BWRAP_ABSTRACTION" &&
   grep -qx 'capability sys_admin,' "$BWRAP_ABSTRACTION" &&
   grep -qx 'capability sys_chroot,' "$BWRAP_ABSTRACTION" &&
   grep -qx 'capability sys_ptrace,' "$BWRAP_ABSTRACTION"; then
  pass "shared Bubblewrap abstraction owns namespace capabilities"
else
  fail "shared Bubblewrap abstraction owns namespace capabilities"
fi

if grep -qx 'mount,' "$BWRAP_ABSTRACTION" &&
   grep -qx 'umount,' "$BWRAP_ABSTRACTION" &&
   grep -qx 'pivot_root,' "$BWRAP_ABSTRACTION" &&
   grep -qx '/ r,' "$BWRAP_ABSTRACTION" &&
   grep -qx '@{PROC}/sys/user/max_user_namespaces r,' "$BWRAP_ABSTRACTION" &&
   grep -qx 'owner @{PROC}/\[0-9\]\*/{gid_map,setgroups,uid_map} rw,' "$BWRAP_ABSTRACTION" &&
   grep -qx '/oldroot/\*\* rwkl,' "$BWRAP_ABSTRACTION" &&
   grep -qx '/newroot/\*\* rwkl,' "$BWRAP_ABSTRACTION" &&
   grep -qx '/tmp/newroot/\*\* rwkl,' "$BWRAP_ABSTRACTION" &&
   grep -qx '/tmp/oldroot/\*\* rwkl,' "$BWRAP_ABSTRACTION" &&
   grep -qx '/bindfile\* rw,' "$BWRAP_ABSTRACTION" &&
   grep -qx '/dev/{full,null,ptmx,random,tty,urandom,zero} rw,' "$BWRAP_ABSTRACTION"; then
  pass "shared Bubblewrap abstraction owns mount, proc, root, and device mechanics"
else
  fail "shared Bubblewrap abstraction owns mount, proc, root, and device mechanics"
fi

if ! grep -Eq '^/(opt/tuta-mail|usr/libexec/glycin-loaders)|@\{HOME\}|@\{XDG_' "$BWRAP_ABSTRACTION" &&
   ! grep -Eq '^network (inet|inet6)' "$BWRAP_ABSTRACTION" &&
   ! grep -Eq '[pP][xX]?[[:space:]]*->' "$BWRAP_ABSTRACTION"; then
  pass "shared Bubblewrap abstraction contains no application filesystem, network, or payload policy"
else
  fail "shared Bubblewrap abstraction contains no application filesystem, network, or payload policy"
fi

if grep -qx '#include <abstractions/managed-desktop-runtime>' "$ELECTRON_RUNTIME" &&
   grep -qx '#include <abstractions/managed-electron-runtime>' "$ELECTRON_SANDBOX" &&
   grep -Fqx '#include <abstractions/managed-desktop-runtime>' "$DESKTOP_APPLICATION" &&
   grep -Fqx '/usr/bin/xdg-open rpux,' "$DESKTOP_APPLICATION" &&
   ! grep -Fq 'xdg-open' "$DESKTOP_RUNTIME" &&
   ! grep -Eq '^(userns,|capability[[:space:]]|mount,|umount,|pivot_root,)' "$ELECTRON_RUNTIME" &&
   grep -Fqx '@{PROC}/[0-9]*/comm r,' "$ELECTRON_RUNTIME" &&
   grep -qx 'userns,' "$ELECTRON_SANDBOX" &&
   grep -qx 'capability sys_admin,' "$ELECTRON_SANDBOX" &&
   grep -qx 'capability sys_chroot,' "$ELECTRON_SANDBOX"; then
  pass "Electron runtime is capability-free while legacy sandbox users retain their compatibility layer"
else
  fail "Electron runtime is capability-free while legacy sandbox users retain their compatibility layer"
fi

tuta_main=$(tuta_main_block)
if printf '%s\n' "$tuta_main" |
     grep -Fqx '  #include <abstractions/managed-electron-runtime>' &&
   printf '%s\n' "$tuta_main" |
     grep -Fqx '  /usr/bin/bwrap rCx -> tuta-bwrap,' &&
   ! printf '%s\n' "$tuta_main" |
     grep -Eq 'managed-electron-application|managed-bwrap-common|/newroot/|capability[[:space:]]|^  userns,'; then
  pass "Tuta runtime transitions to Bubblewrap without inheriting constructor privileges"
else
  fail "Tuta runtime transitions to Bubblewrap without inheriting constructor privileges"
fi
unset tuta_main

tuta_bwrap=$(tuta_bwrap_block)
if printf '%s\n' "$tuta_bwrap" |
     grep -Fqx '    #include <abstractions/managed-bwrap-common>' &&
   printf '%s\n' "$tuta_bwrap" |
     grep -Fqx '    /opt/tuta-mail/** rPx -> tuta-mail,' &&
   printf '%s\n' "$tuta_bwrap" |
     grep -Fqx '    /usr/libexec/glycin-loaders/2+/glycin-image-rs rPx -> tuta-glycin-loader,' &&
   printf '%s\n' "$tuta_bwrap" |
     grep -Fqx '    /usr/libexec/glycin-loaders/2+/glycin-svg rPx -> tuta-glycin-loader,'; then
  pass "Tuta Bubblewrap child owns app-specific mounts and explicit payload exits"
else
  fail "Tuta Bubblewrap child owns app-specific mounts and explicit payload exits"
fi
unset tuta_bwrap

tuta_glycin=$(tuta_glycin_block)
if printf '%s\n' "$tuta_glycin" |
     grep -Fqx '  #include <abstractions/managed-desktop-application>' &&
   printf '%s\n' "$tuta_glycin" |
     grep -Fqx '  /usr/libexec/glycin-loaders/2+/glycin-image-rs mrix,' &&
   ! printf '%s\n' "$tuta_glycin" |
     grep -Eq 'managed-bwrap-common|^  userns,|^  capability[[:space:]]|^  (mount|umount|pivot_root),|^  network (inet|inet6)'; then
  pass "Glycin payload leaves Bubblewrap in a non-networked capability-free profile"
else
  fail "Glycin payload leaves Bubblewrap in a non-networked capability-free profile"
fi
unset tuta_glycin

waypaper_main=$(waypaper_main_block)
waypaper_bwrap=$(waypaper_child_block waypaper-bwrap)
waypaper_ps=$(waypaper_child_block waypaper-ps)
waypaper_kill=$(waypaper_child_block waypaper-kill)
waypaper_ldconfig=$(waypaper_child_block waypaper-ldconfig)
waypaper_glycin=$(waypaper_glycin_block)
if printf '%s\n' "$waypaper_main" |
     grep -Fqx '  /usr/bin/bwrap rCx -> waypaper-bwrap,' &&
   printf '%s\n' "$waypaper_main" |
     grep -Fqx '  /usr/bin/ps rCx -> waypaper-ps,' &&
   printf '%s\n' "$waypaper_main" |
     grep -Fqx '  /usr/bin/kill rCx -> waypaper-kill,' &&
   printf '%s\n' "$waypaper_main" |
     grep -Fqx '  /usr/sbin/ldconfig rCx -> waypaper-ldconfig,' &&
   printf '%s\n' "$waypaper_main" |
     grep -Fqx '  signal (send) set=(kill) peer=managed-waypaper//waypaper-bwrap,' &&
   ! printf '%s\n' "$waypaper_main" |
     grep -Eq 'managed-bwrap-common|^  capability[[:space:]]|@\{PROC\}/\[0-9\]\*/\{cmdline,environ' &&
   printf '%s\n' "$waypaper_bwrap" |
     grep -Fqx '    #include <abstractions/managed-bwrap-common>' &&
   printf '%s\n' "$waypaper_bwrap" |
     grep -Fqx '    ptrace (readby) peer=managed-waypaper//waypaper-ps,' &&
   printf '%s\n' "$waypaper_bwrap" |
     grep -Fqx '    /usr/libexec/glycin-loaders/2+/{glycin-image-rs,glycin-svg} rix,' &&
   printf '%s\n' "$waypaper_ps" |
     grep -Fqx '    capability sys_ptrace,' &&
   printf '%s\n' "$waypaper_ps" |
     grep -Fqx '    @{PROC}/[0-9]*/{cmdline,environ,stat,status} r,' &&
   printf '%s\n' "$waypaper_ps" |
     grep -Fqx '    ptrace (read) peer=unconfined,' &&
   ! printf '%s\n' "$waypaper_ps" |
     grep -Eq 'managed-bwrap-common|^    (mount|umount|pivot_root),|^    network (inet|inet6)' &&
   printf '%s\n' "$waypaper_kill" |
     grep -Fqx '    signal (send) set=(kill term) peer=unconfined,' &&
   ! printf '%s\n' "$waypaper_kill" |
     grep -Eq '^    (capability|ptrace|network|mount|umount|pivot_root)[[:space:](]' &&
   printf '%s\n' "$waypaper_ldconfig" |
     grep -Fqx '    /usr/sbin/ldconfig mr,' &&
   printf '%s\n' "$waypaper_ldconfig" |
     grep -Fqx '    /etc/ld.so.cache r,' &&
   printf '%s\n' "$waypaper_glycin" |
     grep -Fqx '  /usr/libexec/glycin-loaders/2+/glycin-image-rs mrix,' &&
   ! printf '%s\n' "$waypaper_glycin" |
     grep -Eq 'managed-bwrap-common|^  (capability|ptrace|network|mount|umount|pivot_root)[[:space:](]'; then
  pass "Waypaper isolates Bubblewrap, Glycin, process inspection, signal, and linker-cache helpers"
else
  fail "Waypaper isolates Bubblewrap, Glycin, process inspection, signal, and linker-cache helpers"
fi
unset waypaper_bwrap waypaper_glycin waypaper_kill waypaper_ldconfig waypaper_main waypaper_ps

if grep -q 'etc/apparmor.d/abstractions/managed-bwrap-common' "$SECURITY_SCRIPT" &&
   grep -q 'etc/apparmor.d/abstractions/managed-bwrap-desktop-runtime' "$SECURITY_SCRIPT" &&
   grep -q 'etc/apparmor.d/abstractions/managed-desktop-runtime' "$SECURITY_SCRIPT" &&
   grep -q 'etc/apparmor.d/abstractions/managed-devops-toolchain-runtime' "$SECURITY_SCRIPT" &&
   grep -q 'etc/apparmor.d/abstractions/managed-codex-runtime' "$SECURITY_SCRIPT" &&
   grep -q 'etc/apparmor.d/abstractions/managed-electron-runtime' "$SECURITY_SCRIPT" &&
   grep -q '^opt.tuta-mail.AppRun$' "$SECURITY_SCRIPT"; then
  pass "late security staging installs the Bubblewrap constructor and payload runtime split"
else
  fail "late security staging installs the Bubblewrap constructor and payload runtime split"
fi

codex_wrapper=$(codex_wrapper_block)
codex_bwrap=$(codex_bwrap_block)
codex_runtime=$(codex_runtime_block)
if printf '%s\n' "$codex_wrapper" |
     grep -Fqx '  /usr/bin/bwrap rCx -> codex-bwrap,' &&
   printf '%s\n' "$codex_wrapper" |
     grep -Fqx '  /usr/bin/slirp4netns rPx -> managed-codex-slirp4netns,' &&
   printf '%s\n' "$codex_wrapper" |
     grep -Fqx '  /dev/tty rw,' &&
   printf '%s\n' "$codex_wrapper" |
     grep -Fqx '  /data/codex/share/bin/codex rPx -> managed-codex-runtime,' &&
   printf '%s\n' "$codex_wrapper" |
     grep -Fqx '  signal (send, receive) peer=managed-codex-wrapper//codex-bwrap,' &&
   printf '%s\n' "$codex_wrapper" |
     grep -Fqx '  /run/{NetworkManager,resolvconf,systemd/resolve}/** r,' &&
   printf '%s\n' "$codex_bwrap" |
     grep -Fqx '    #include <abstractions/managed-bwrap-common>' &&
   printf '%s\n' "$codex_bwrap" |
     grep -Fqx '    #include <abstractions/managed-codex-runtime>' &&
   printf '%s\n' "$codex_runtime" |
     grep -Fqx '  #include <abstractions/managed-codex-runtime>' &&
   printf '%s\n' "$codex_runtime" |
     grep -Fqx '  /usr/bin/bwrap rCx -> codex-bwrap,' &&
   printf '%s\n' "$codex_runtime" |
     grep -Fqx '  /usr/bin/slirp4netns rPx -> managed-codex-slirp4netns,' &&
   printf '%s\n' "$codex_runtime" |
     grep -Fqx '  profile codex-bwrap flags=(attach_disconnected, mediate_deleted) {' &&
   printf '%s\n' "$codex_runtime" |
     grep -Fqx '    #include <abstractions/managed-bwrap-common>' &&
   printf '%s\n' "$codex_runtime" |
     grep -Fqx '    #include <abstractions/managed-codex-runtime>' &&
   printf '%s\n' "$codex_runtime" |
     grep -Fqx '    signal (send, receive) peer=managed-codex-runtime,' &&
   grep -Fqx '#include <abstractions/managed-devops-toolchain-runtime>' "$CODEX_RUNTIME" &&
   grep -Fqx '/data/ r,' "$CODEX_RUNTIME" &&
   grep -Fqx '/data/** rix,' "$CODEX_RUNTIME" &&
   grep -Fqx '/data/codex/ rw,' "$CODEX_RUNTIME" &&
   grep -Fqx '/data/codex/** rwklm,' "$CODEX_RUNTIME" &&
   grep -Fqx '/data/codex/** rix,' "$CODEX_RUNTIME" &&
   grep -Fqx 'deny /data/codex/.managed-codex-release wkl,' "$CODEX_RUNTIME" &&
   grep -Fqx 'deny /data/codex/config.schema.json wkl,' "$CODEX_RUNTIME" &&
   grep -Fqx 'deny /data/codex/{lib,share}/ wkl,' "$CODEX_RUNTIME" &&
   grep -Fqx 'deny /data/codex/{lib,share}/** wkl,' "$CODEX_RUNTIME" &&
   grep -Fqx '/data/codex/config.schema.json r,' "$CODEX_RUNTIME" &&
   grep -Fqx '/data/codex/lib/ r,' "$CODEX_RUNTIME" &&
   grep -Fqx '/data/codex/usr/etc/ r,' "$CODEX_RUNTIME" &&
   grep -Fqx 'deny /data/codex/usr/etc/ wkl,' "$CODEX_RUNTIME" &&
   grep -Fqx 'deny /data/codex/usr/etc/** wkl,' "$CODEX_RUNTIME" &&
   grep -Fqx '/data/codex/share/bin/* mrix,' "$CODEX_RUNTIME" &&
   grep -Fqx '/data/codex/usr/instructions/** r,' "$CODEX_RUNTIME" &&
   grep -Fqx 'deny /data/codex/usr/home/memories/.git rwkl,' "$CODEX_RUNTIME" &&
   grep -Fqx '/data/downloads/ rw,' "$CODEX_RUNTIME" &&
   grep -Fqx '/data/downloads/** rwklm,' "$CODEX_RUNTIME" &&
   grep -Fqx '/data/downloads/** rix,' "$CODEX_RUNTIME" &&
   ! grep -Eq '^/data/[*][*][[:space:]][^,]*w[^,]*,$' "$CODEX_RUNTIME" &&
   grep -Fqx '/opt/ r,' "$CODEX_RUNTIME" &&
   grep -Fqx 'owner /data/codex/usr/.git/ r,' "$CODEX_RUNTIME" &&
   grep -Fqx 'owner /data/codex/usr/.git/**/ r,' "$CODEX_RUNTIME" &&
   grep -Fqx '/var/cache/apt/pkgcache.bin r,' "$CODEX_RUNTIME" &&
   grep -Fqx '/var/lib/apt/lists/ r,' "$CODEX_RUNTIME" &&
   grep -Fqx '/var/lib/apt/lists/*_{Packages,Translation-*} r,' "$CODEX_RUNTIME" &&
   ! grep -Fqx '/var/lib/apt/lists/** r,' "$CODEX_RUNTIME" &&
   grep -Fqx '/var/lib/dpkg/status r,' "$CODEX_RUNTIME" &&
   grep -Fqx '/var/lib/dpkg/triggers/{File,Unincorp} r,' "$CODEX_RUNTIME" &&
   grep -Fqx '/var/lib/dpkg/updates/ r,' "$CODEX_RUNTIME" &&
   grep -Fqx '#include <abstractions/managed-electron-runtime>' "$CODEX_RUNTIME" &&
   grep -Fqx 'userns,' "$CODEX_RUNTIME" &&
   grep -Fqx 'capability sys_admin,' "$CODEX_RUNTIME" &&
   grep -Fqx 'capability sys_chroot,' "$CODEX_RUNTIME" &&
   grep -Fqx 'capability sys_ptrace,' "$CODEX_RUNTIME" &&
   grep -Fqx 'owner @{PROC}/[0-9]*/{gid_map,setgroups,uid_map} rw,' "$CODEX_RUNTIME" &&
   grep -Fqx 'deny /etc/opt/chrome/ w,' "$CODEX_RUNTIME" &&
   grep -Fqx 'deny /opt/vivaldi/extensions/ w,' "$CODEX_RUNTIME" &&
   grep -Fqx '/run/udev/data/c13:* r,' "$CODEX_RUNTIME" &&
   grep -Fqx '/usr/ r,' "$CODEX_RUNTIME" &&
   grep -Fqx '/var/cache/debconf/{config.dat,templates.dat} r,' "$CODEX_RUNTIME" &&
   grep -Fqx '/var/opt/vivaldi/media-codecs-*/libffmpeg.so mr,' "$CODEX_RUNTIME" &&
   grep -Fqx 'owner @{PROC}/[0-9]*/clear_refs w,' "$ELECTRON_RUNTIME" &&
   grep -Fqx 'owner @{PROC}/[0-9]*/oom_score_adj w,' "$ELECTRON_RUNTIME" &&
   grep -Fqx 'owner @{PROC}/@{pid}/fd/[0-9]* rw,' "$ELECTRON_RUNTIME" &&
   grep -Fqx 'deny /var/cache/fontconfig/ w,' "$DESKTOP_RUNTIME" &&
   grep -Fqx '/usr/** mrix,' "$DEVOPS_RUNTIME" &&
   grep -Fqx '/ r,' "$DEVOPS_RUNTIME" &&
   grep -Fqx '/opt/** mrix,' "$DEVOPS_RUNTIME" &&
   grep -Fqx 'owner @{HOME}/** rix,' "$DEVOPS_RUNTIME" &&
   grep -Fqx '/pool/ rw,' "$DEVOPS_RUNTIME" &&
   grep -Fqx '/pool/** rwklm,' "$DEVOPS_RUNTIME" &&
   grep -Fqx '/pool/** rix,' "$DEVOPS_RUNTIME" &&
   ! grep -Eq '^(userns,|capability[[:space:]]|mount,|umount,|pivot_root,)' "$DEVOPS_RUNTIME" "$ELECTRON_RUNTIME" &&
   ! grep -Eq '^(mount,|umount,|pivot_root,)' "$CODEX_RUNTIME" &&
   ! printf '%s\n%s\n' "$codex_wrapper" "$codex_runtime" |
     grep -Eq '[[:space:]][pP][uU]x,'; then
  pass "Codex wrapper and direct runtime isolate Bubblewrap constructors in confined child domains"
else
  fail "Codex wrapper and direct runtime isolate Bubblewrap constructors in confined child domains"
fi
unset codex_bwrap codex_runtime codex_wrapper

chatgpt_wrapper=$(chatgpt_wrapper_block)
chatgpt_bwrap=$(chatgpt_bwrap_block)
chatgpt_slirp4netns=$(chatgpt_slirp4netns_block)
if printf '%s\n' "$chatgpt_wrapper" |
     grep -Fqx '  /usr/bin/slirp4netns rPx -> managed-chatgpt-slirp4netns,' &&
   printf '%s\n' "$chatgpt_wrapper" |
     grep -Fqx '  signal (send) set=(kill term) peer=managed-labwc-chatgpt//chatgpt-bwrap,' &&
   printf '%s\n' "$chatgpt_wrapper" |
     grep -Fqx '  signal (send) set=(exists kill term) peer=managed-chatgpt-slirp4netns,' &&
   printf '%s\n' "$chatgpt_bwrap" |
     grep -Fqx '    signal (receive) set=(kill term) peer=managed-labwc-chatgpt,' &&
   printf '%s\n' "$chatgpt_bwrap" |
     grep -Fqx '    #include <abstractions/managed-codex-runtime>' &&
   ! printf '%s\n' "$chatgpt_bwrap" |
     grep -Eq '^    (userns,|capability sys_(admin|chroot|ptrace),|owner @\{PROC\}/\[0-9\]\*/\{gid_map,setgroups,uid_map\})' &&
   printf '%s\n' "$chatgpt_slirp4netns" |
     grep -Fqx 'profile managed-chatgpt-slirp4netns flags=(attach_disconnected) {' &&
   printf '%s\n' "$chatgpt_slirp4netns" |
     grep -Fqx '  capability net_admin,' &&
   printf '%s\n' "$chatgpt_slirp4netns" |
     grep -Fqx '  capability sys_admin,' &&
   printf '%s\n' "$chatgpt_slirp4netns" |
     grep -Fqx '  capability sys_ptrace,' &&
   printf '%s\n' "$chatgpt_slirp4netns" |
     grep -Fqx '  ptrace (read) peer=managed-labwc-chatgpt//chatgpt-bwrap,' &&
   printf '%s\n' "$chatgpt_slirp4netns" |
     grep -Fqx '  ptrace (readby) peer=aa-status-reader,' &&
   printf '%s\n' "$chatgpt_slirp4netns" |
     grep -Fqx '  signal (receive) set=(exists kill term) peer=managed-labwc-chatgpt,' &&
   printf '%s\n' "$chatgpt_slirp4netns" |
     grep -Fqx '  /dev/net/tun rw,' &&
   printf '%s\n' "$chatgpt_slirp4netns" |
     grep -Fqx '  /etc/resolv.conf r,' &&
   printf '%s\n' "$chatgpt_slirp4netns" |
     grep -Fqx '  /run/systemd/resolve/stub-resolv.conf r,' &&
   printf '%s\n' "$chatgpt_slirp4netns" |
     grep -Fqx '  @{PROC}/[0-9]*/ns/{net,user} r,' &&
   printf '%s\n' "$chatgpt_slirp4netns" |
     grep -Fqx '  owner /run/user/[0-9]*/labwc-chatgpt-sandbox-*/slirp4netns.stderr rw,' &&
   printf '%s\n' "$chatgpt_slirp4netns" |
     grep -Fqx '  owner /tmp/labwc-chatgpt-sandbox-*/slirp4netns.stderr rw,' &&
   ! printf '%s\n' "$chatgpt_slirp4netns" |
     grep -Fq '/data/codex/runtime/.control/'; then
  pass "ChatGPT reuses shared Codex runtime coverage with a dedicated slirp4netns helper"
else
  fail "ChatGPT reuses shared Codex runtime coverage with a dedicated slirp4netns helper"
fi
unset chatgpt_bwrap chatgpt_slirp4netns chatgpt_wrapper

if grep -Fqx '/usr/bin/bwrap rCx -> mullvad-bwrap,' "$MULLVAD_LOCAL" &&
   grep -Fqx 'profile mullvad-bwrap flags=(attach_disconnected, mediate_deleted) {' "$MULLVAD_LOCAL" &&
   grep -Fqx '  #include <abstractions/managed-bwrap-common>' "$MULLVAD_LOCAL" &&
   grep -Fqx '  /usr/libexec/glycin-loaders/2+/glycin-image-rs rix,' "$MULLVAD_LOCAL"; then
  pass "Mullvad Browser isolates Bubblewrap while retaining its bounded Glycin loader"
else
  fail "Mullvad Browser isolates Bubblewrap while retaining its bounded Glycin loader"
fi

if grep -Fqx '#include <abstractions/managed-electron-application>' "$VIVALDI_LOCAL" &&
   grep -Fqx '/usr/bin/bwrap rCx -> vivaldi-bwrap,' "$VIVALDI_LOCAL" &&
   grep -Fqx 'signal (send) set=(kill) peer=vivaldi-bin//vivaldi-bwrap,' "$VIVALDI_LOCAL" &&
   grep -Fqx 'profile vivaldi-bwrap flags=(attach_disconnected, mediate_deleted) {' "$VIVALDI_LOCAL" &&
   grep -Fqx '  #include <abstractions/managed-bwrap-common>' "$VIVALDI_LOCAL" &&
   grep -Fqx '  #include <abstractions/managed-electron-runtime>' "$VIVALDI_LOCAL" &&
   grep -Fqx '  signal (receive) set=(kill) peer=vivaldi-bin,' "$VIVALDI_LOCAL" &&
   grep -Fqx '  /opt/vivaldi/** mr,' "$VIVALDI_LOCAL" &&
   grep -Fqx '  /var/opt/vivaldi/** mr,' "$VIVALDI_LOCAL" &&
   grep -Fqx '  /usr/bin/true rix,' "$VIVALDI_LOCAL" &&
   grep -Fqx '  /usr/libexec/glycin-loaders/2+/{glycin-image-rs,glycin-svg} rix,' "$VIVALDI_LOCAL" &&
   grep -Fqx '  owner @{HOME}/.config/vivaldi/** rwkl,' "$VIVALDI_LOCAL" &&
   grep -Fqx 'owner @{HOME}/Workspace/llama-labwc/output/llama-{cuda,ram}.tar.gz r,' "$VIVALDI_LOCAL" &&
   grep -Fqx '/pool/build/whisper-labwc/artifacts/whisper-{cuda,ram}.tar.gz r,' "$VIVALDI_LOCAL" &&
   ! grep -Eq '^  (network|userns|capability)[[:space:],]' "$VIVALDI_LOCAL" &&
   ! grep -Eq '^  (mount|umount|pivot_root),$' "$VIVALDI_LOCAL" &&
   ! grep -Eq '^  owner @\{HOME\}/\*\*[[:space:]]' "$VIVALDI_LOCAL"; then
  pass "Vivaldi isolates Bubblewrap with reciprocal signals and bounded browser state"
else
  fail "Vivaldi isolates Bubblewrap with reciprocal signals and bounded browser state"
fi

if grep -Fqx '  /usr/bin/bwrap rCx -> freerdp-bwrap,' "$WRAPPER_PROFILE" &&
   grep -Fqx '  profile freerdp-bwrap flags=(attach_disconnected, mediate_deleted) {' "$WRAPPER_PROFILE" &&
   grep -Fqx '    #include <abstractions/managed-bwrap-common>' "$WRAPPER_PROFILE" &&
   grep -Fqx '    /usr/libexec/glycin-loaders/2+/glycin-image-rs rix,' "$WRAPPER_PROFILE"; then
  pass "FreeRDP askpass isolates its GTK Bubblewrap constructor"
else
  fail "FreeRDP askpass isolates its GTK Bubblewrap constructor"
fi

if grep -Fqx '@{PROC}/stat r,' "$WEBKIT_RUNTIME" &&
   grep -Fqx '@{sys}/fs/cgroup/**/{cpu.max,memory.current,memory.high,memory.max} r,' "$WEBKIT_RUNTIME" &&
   grep -Fqx '/usr/lib/@{multiarch}/webkit2gtk-4.1/WebKit{Network,Web}Process rix,' "$WEBKIT_RUNTIME" &&
   grep -Fqx '  #include <abstractions/managed-webkit-runtime>' "$GRIDLINE_PROFILE" &&
   grep -Fqx '  /usr/bin/bwrap rCx -> webkit-bwrap,' "$GRIDLINE_PROFILE" &&
   grep -Fqx '  signal (send) set=(kill) peer=gridline//webkit-bwrap,' "$GRIDLINE_PROFILE" &&
   grep -Fqx '  profile webkit-bwrap flags=(attach_disconnected, mediate_deleted) {' "$GRIDLINE_PROFILE" &&
   grep -Fqx '    #include <abstractions/managed-bwrap-common>' "$GRIDLINE_PROFILE" &&
   grep -Fqx '    #include <abstractions/managed-desktop-runtime>' "$GRIDLINE_PROFILE" &&
   grep -Fqx '    #include <abstractions/managed-webkit-runtime>' "$GRIDLINE_PROFILE" &&
   grep -Fqx '    signal (receive) set=(kill) peer=gridline,' "$GRIDLINE_PROFILE" &&
   grep -Fqx '    /usr/bin/true rix,' "$GRIDLINE_PROFILE" &&
   grep -Fqx '    /usr/libexec/glycin-loaders/2+/glycin-svg rix,' "$GRIDLINE_PROFILE" &&
   grep -Fqx '    owner /pool/db/*/gridline/** rwkl,' "$GRIDLINE_PROFILE"; then
  pass "Gridline isolates WebKit Bubblewrap while WebKit payloads inherit bounded native-Wayland runtime policy"
else
  fail "Gridline isolates WebKit Bubblewrap while WebKit payloads inherit bounded native-Wayland runtime policy"
fi

if grep -Fqx '  /usr/bin/bwrap rCx -> satty-bwrap,' "$WRAPPER_PROFILE" &&
   grep -Fqx '  profile satty-bwrap flags=(attach_disconnected, mediate_deleted) {' "$WRAPPER_PROFILE" &&
   grep -Fqx '    #include <abstractions/managed-bwrap-common>' "$WRAPPER_PROFILE" &&
   grep -Fqx '  signal (send) set=(kill) peer=managed-satty-runtime//satty-bwrap,' "$WRAPPER_PROFILE" &&
   grep -Fqx '    signal (receive) set=(kill) peer=managed-satty-runtime,' "$WRAPPER_PROFILE" &&
   grep -Fqx '    /usr/bin/true rix,' "$WRAPPER_PROFILE" &&
   grep -Fqx '    /usr/libexec/glycin-loaders/2+/{glycin-image-rs,glycin-svg} rix,' "$WRAPPER_PROFILE" &&
   grep -Fqx '    /usr/share/glycin-loaders/2+/conf.d/ r,' "$WRAPPER_PROFILE" &&
   grep -Fqx '    /usr/share/glycin-loaders/2+/conf.d/** r,' "$WRAPPER_PROFILE" &&
   grep -Fqx '    owner /run/user/[0-9]*/labwc-capture/satty-source.*.png r,' "$WRAPPER_PROFILE"; then
  pass "Satty isolates its Glycin Bubblewrap constructor and capture input"
else
  fail "Satty isolates its Glycin Bubblewrap constructor and capture input"
fi

if grep -Fqx '  /usr/bin/bwrap rCx -> managed-app-bwrap,' "$WRAPPER_PROFILE" &&
   grep -Fqx '  profile managed-app-bwrap flags=(attach_disconnected, mediate_deleted) {' "$WRAPPER_PROFILE" &&
   grep -Fqx '    #include <abstractions/managed-bwrap-common>' "$WRAPPER_PROFILE" &&
   grep -Fqx '    #include <abstractions/managed-bwrap-desktop-runtime>' "$WRAPPER_PROFILE" &&
   grep -Fqx '#include <abstractions/managed-electron-runtime>' "$BWRAP_DESKTOP_RUNTIME" &&
   grep -Fqx 'network inet6 stream,' "$BWRAP_DESKTOP_RUNTIME" &&
   ! grep -Eq '^(userns,|capability[[:space:]]|mount,|umount,|pivot_root,)' "$BWRAP_DESKTOP_RUNTIME" &&
   grep -Fqx '@{PROC}/sys/fs/inotify/max_user_watches r,' "$ELECTRON_RUNTIME" &&
   grep -Fqx '    /opt/tuta-mail/AppRun rix,' "$WRAPPER_PROFILE" &&
   grep -Fqx '    /proc/self/exe rix,' "$WRAPPER_PROFILE" &&
   grep -Fqx '    /usr/bin/ldd rix,' "$WRAPPER_PROFILE" &&
   grep -Fqx '    /opt/{Bitwarden,Filen,Obsidian,ledger-live,postman,sleek,tuta-mail}/** mrix,' "$WRAPPER_PROFILE" &&
   grep -Fqx '  /usr/bin/bwrap rCx -> managed-wayland-compat-app-bwrap,' "$WRAPPER_PROFILE" &&
   grep -Fqx '  /usr/bin/cage r,' "$WRAPPER_PROFILE" &&
   grep -Fqx '  profile managed-wayland-compat-app-bwrap flags=(attach_disconnected, mediate_deleted) {' "$WRAPPER_PROFILE" &&
   grep -Fqx '    #include <abstractions/managed-bwrap-common>' "$WRAPPER_PROFILE" &&
   grep -Fqx '    #include <abstractions/managed-bwrap-desktop-runtime>' "$WRAPPER_PROFILE" &&
   grep -Fqx '    #include <abstractions/managed-pipewire-audio>' "$WRAPPER_PROFILE" &&
   grep -Fqx '    capability dac_read_search,' "$WRAPPER_PROFILE" &&
   grep -Fqx '    signal (send, receive) peer=managed-labwc-managed-wayland-compat-app//managed-wayland-compat-app-bwrap,' "$WRAPPER_PROFILE" &&
   grep -Fqx '  /usr/bin/xdg-dbus-proxy rCx -> managed-wayland-compat-dbus-proxy,' "$WRAPPER_PROFILE" &&
   grep -Fqx '  profile managed-wayland-compat-dbus-proxy flags=(attach_disconnected) {' "$WRAPPER_PROFILE" &&
   grep -Fqx '    /run/dbus/system_bus_socket rw,' "$WRAPPER_PROFILE" &&
   grep -Fqx '    owner /run/user/[0-9]*/labwc-{discord,zoom}-sandbox-*/{session-bus,system-bus} rw,' "$WRAPPER_PROFILE" &&
   grep -Fqx '    owner @{HOME}/.config/ rw,' "$WRAPPER_PROFILE" &&
   grep -Fqx '    owner @{HOME}/.config/\#* rwkl,' "$WRAPPER_PROFILE" &&
   grep -Fqx '    owner @{HOME}/.config/zoomus.conf* rwkl,' "$WRAPPER_PROFILE" &&
   ! grep -Fqx '  /tmp/.X11-unix/ r,' "$WRAPPER_PROFILE" &&
   ! grep -Fqx '  owner /tmp/.X11-unix/X[0-9]* r,' "$WRAPPER_PROFILE" &&
   grep -Fqx '    owner /tmp/.X11-unix/ rw,' "$WRAPPER_PROFILE" &&
   grep -Fqx '    owner /tmp/.X11-unix/X[0-9]* rw,' "$WRAPPER_PROFILE" &&
   grep -Fqx '    owner /run/user/[0-9]*/wayland-[0-9]*.lock rwk,' "$WRAPPER_PROFILE" &&
   grep -Fqx '    owner /run/user/[0-9]*/discord-ipc-[0-9]* rwkl,' "$WRAPPER_PROFILE" &&
   ! grep -Fq '/tmp-overlay-work-' "$WRAPPER_PROFILE" &&
   grep -Fqx '  /opt/xwayland/usr/bin/xkbcomp r,' "$WRAPPER_PROFILE" &&
   ! grep -Fqx '  /usr/bin/xkbcomp r,' "$WRAPPER_PROFILE" &&
   grep -Fqx '  /opt/xwayland/usr/lib/xkbcomp-overlay/ r,' "$WRAPPER_PROFILE" &&
   grep -Fqx '  /opt/xwayland/usr/lib/xkbcomp-overlay/xkbcomp r,' "$WRAPPER_PROFILE" &&
   grep -Fqx '    /opt/xwayland/usr/bin/Xwayland rix,' "$WRAPPER_PROFILE" &&
   grep -Fqx '    /opt/xwayland/usr/bin/xkbcomp r,' "$WRAPPER_PROFILE" &&
   grep -Fqx '    /opt/xwayland/usr/lib/xkbcomp-overlay/ r,' "$WRAPPER_PROFILE" &&
   grep -Fqx '    /opt/xwayland/usr/lib/xkbcomp-overlay/xkbcomp r,' "$WRAPPER_PROFILE" &&
   grep -Fqx '    /usr/bin/xkbcomp rix,' "$WRAPPER_PROFILE" &&
   grep -Fqx '    /usr/bin/{bwrap,cage,pacmd,pactl,true} rix,' "$WRAPPER_PROFILE" &&
   grep -Fqx '    /usr/bin/{env,expr,xdg-open} rix,' "$WRAPPER_PROFILE" &&
   grep -Fqx '    /@/usr/bin/{lsb_release,xdg-mime,xdg-open} r,' "$WRAPPER_PROFILE" &&
   grep -Fqx '    deny /@/usr/bin/chromium r,' "$WRAPPER_PROFILE" &&
   grep -Fqx '    deny /usr/bin/chromium rx,' "$WRAPPER_PROFILE" &&
   grep -Fqx '    @{sys}/devices/**/{idProduct,idVendor,interface} r,' "$WRAPPER_PROFILE" &&
   grep -Fqx '    /usr/lib/x86_64-linux-gnu/libdecor/ r,' "$WRAPPER_PROFILE" &&
   grep -Fqx '    /usr/lib/x86_64-linux-gnu/libdecor/plugins-1/ r,' "$WRAPPER_PROFILE" &&
   grep -Fqx '    /usr/lib/x86_64-linux-gnu/libdecor/plugins-1/libdecor-gtk.so mr,' "$WRAPPER_PROFILE" &&
   private_xwayland_library_rules_present &&
   grep -Fqx '    /usr/local/libexec/labwc-zoom-discord-compat-runtime rix,' "$WRAPPER_PROFILE" &&
   grep -Fqx '    deny /usr/bin/Xwayland rxm,' "$WRAPPER_PROFILE" &&
   ! grep -Eq '/opt/xwayland/usr/bin/Xwayland[[:space:]]+r[PpCc]x[[:space:]]+->' "$WRAPPER_PROFILE" &&
   ! grep -Eq '^    profile [^ ]+' "$WRAPPER_PROFILE" &&
   grep -Fqx 'profile labwc-cage-direct-exec-deny /usr/bin/cage flags=(attach_disconnected, mediate_deleted) {' "$WRAPPER_PROFILE" &&
   grep -Fqx '  deny /usr/bin/cage mr,' "$WRAPPER_PROFILE" &&
   grep -Fqx 'profile labwc-xwayland-direct-exec-deny /{opt/xwayland/usr,usr}/bin/Xwayland flags=(attach_disconnected, mediate_deleted) {' "$WRAPPER_PROFILE" &&
   grep -Fqx '  deny /{opt/xwayland/usr,usr}/bin/Xwayland mr,' "$WRAPPER_PROFILE" &&
   grep -Fqx 'profile labwc-xkbcomp-direct-exec-deny /opt/xwayland/usr/{bin,lib/xkbcomp-overlay}/xkbcomp flags=(attach_disconnected, mediate_deleted) {' "$WRAPPER_PROFILE" &&
   grep -Fqx '  deny /opt/xwayland/usr/{bin,lib/xkbcomp-overlay}/xkbcomp mr,' "$WRAPPER_PROFILE" &&
   ! grep -Fq 'managed-labwc-private-xwayland' "$WRAPPER_PROFILE" &&
   grep -Fqx '  deny /opt/xwayland/** rxm,' "$WRAPPER_PROFILE" &&
   grep -Fqx '    deny /opt/xwayland/** rxm,' "$WRAPPER_PROFILE" &&
   grep -Fqx '  deny /usr/local/lib/python3.14/dist-packages/labwc_managed_app/wayland_compat{,_runtime}.py r,' "$WRAPPER_PROFILE" &&
   grep -Fqx '  deny /usr/local/lib/python3.14/dist-packages/labwc_managed_app/wayland_compat_runtime.py r,' "$WRAPPER_PROFILE" &&
   ! grep -Fq 'XAUTHORITY' "$WRAPPER_PROFILE" &&
   grep -Fqx '    deny @{sys}/devices/**/iio:device[0-9]*/in_accel_{offset,sampling_frequency,scale,x_raw,y_raw,z_raw} r,' "$WRAPPER_PROFILE" &&
   grep -Fqx '  /usr/bin/bwrap rCx -> qbittorrent-bwrap,' "$WRAPPER_PROFILE" &&
   grep -Fqx '  profile qbittorrent-bwrap flags=(attach_disconnected, mediate_deleted) {' "$WRAPPER_PROFILE" &&
   grep -Fqx '    #include <abstractions/managed-bwrap-common>' "$WRAPPER_PROFILE" &&
   grep -Fqx '    /usr/bin/qbittorrent rPx -> qbittorrent,' "$WRAPPER_PROFILE"; then
  pass "managed application payloads inherit dedicated Electron runtime permissions under no_new_privs"
else
  fail "managed application payloads inherit dedicated Electron runtime permissions under no_new_privs"
fi

if [ "$FAIL_COUNT" -ne 0 ]; then
  exit 1
fi
