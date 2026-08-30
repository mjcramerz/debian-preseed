#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/security-audit-rules-smoke.XXXXXX")
trap 'rm -rf -- "$TMP_DIR"' EXIT HUP INT TERM

TEST_COUNT=36
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

standard_rules="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/audit/standard/rules.d/10-security-standard.rules"
enhanced_rules="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/audit/enhanced/rules.d/10-security-enhanced.rules"
standard_cfg="$ROOT_DIR/d-i/forky/classes/class-select/security/standard.cfg"
enhanced_cfg="$ROOT_DIR/d-i/forky/classes/class-select/security/enhanced.cfg"
security_script="$ROOT_DIR/d-i/forky/scripts/late/security.sh"
augenrules_wrapper="$ROOT_DIR/d-i/forky/hooks/shared/target/usr/local/libexec/augenrules-quiet"
auditd_override="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/systemd/system/auditd.service.d/override.conf"
audit_syslog_plugin="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/audit/plugins.d/syslog.conf"
audit_route="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/rsyslog.d/15-audit.conf"
apparmor_parser_conf="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor/parser.conf"
managed_apparmor_features_dir="$ROOT_DIR/d-i/forky/hooks/shared/target/usr/share/apparmor-features"
legacy_apparmor_defaults="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/default/apparmor"
managed_modes_transition="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/lib/perl5/site_perl/apparmor-managed-modes/AppArmor/ManagedModes/Transition.pm"

if awk '/^[[:space:]]*-/ && /(^|[[:space:]])-F[[:space:]]+arch=/ && !/(^|[[:space:]])-S[[:space:]]+/ { exit 1 }' "$standard_rules"; then
  pass "standard audit rules keep syscall selectors on every arch-qualified rule"
else
  fail "standard audit rules keep syscall selectors on every arch-qualified rule"
fi

if awk '/^[[:space:]]*-/ && /(^|[[:space:]])-F[[:space:]]+arch=/ && !/(^|[[:space:]])-S[[:space:]]+/ { exit 1 }' "$enhanced_rules"; then
  pass "enhanced audit rules keep syscall selectors on every arch-qualified rule"
else
  fail "enhanced audit rules keep syscall selectors on every arch-qualified rule"
fi

if ! grep -Eq '^[[:space:]]*-b[[:space:]]+' "$standard_rules" "$enhanced_rules" &&
   ! grep -Fq 'audit_backlog_limit' "$standard_rules" "$enhanced_rules"; then
  pass "audit rules preserve the boot profile's authoritative backlog limit"
else
  fail "audit rules preserve the boot profile's authoritative backlog limit"
fi

if grep -Fq '    /target/etc/audit/rules.d/audit.rules \' "$security_script"; then
  pass "late security hook removes Debian's package-owned backlog override"
else
  fail "late security hook removes Debian's package-owned backlog override"
fi

if grep -q '^-a always,exit -F arch=b64 -S execve -S execveat -F path=/usr/bin/sudo -F perm=x -F key=privilege-escalation$' "$standard_rules" &&
   grep -q '^-a always,exit -F arch=b64 -S execve -S execveat -F path=/usr/bin/sudo -F perm=x -F key=privilege-escalation$' "$enhanced_rules"; then
  pass "sudo execution auditing uses explicit exec syscalls in both profiles"
else
  fail "sudo execution auditing uses explicit exec syscalls in both profiles"
fi

if grep -q '^-a always,exit -F arch=b64 -S openat .* -F dir=/etc/apparmor.d -F perm=wa -F key=apparmor-policy$' "$standard_rules" &&
   grep -q '^-a always,exit -F arch=b64 -S openat .* -F dir=/etc/apparmor.d -F perm=wa -F key=apparmor-policy$' "$enhanced_rules"; then
  pass "AppArmor policy auditing uses syscall-form write and attribute selectors"
else
  fail "AppArmor policy auditing uses syscall-form write and attribute selectors"
fi

if grep -q '^-a always,exit -F arch=b64 -S openat .* -F path=/etc/apparmor/parser\.conf -F perm=wa -F key=apparmor-policy$' "$standard_rules" &&
   grep -q '^-a always,exit -F arch=b64 -S openat .* -F path=/etc/apparmor/parser\.conf -F perm=wa -F key=apparmor-policy$' "$enhanced_rules"; then
  pass "AppArmor parser.conf is audited alongside the managed policy tree"
else
  fail "AppArmor parser.conf is audited alongside the managed policy tree"
fi

security_config_rules_ok=true
for rules_path in "$standard_rules" "$enhanced_rules"; do
  grep -q ' -F dir=/etc/apparmor -F perm=wa -F key=apparmor-policy$' "$rules_path" ||
    security_config_rules_ok=false
  grep -q ' -F path=/etc/nftables\.conf -F perm=wa -F key=firewall-policy$' "$rules_path" ||
    security_config_rules_ok=false
  grep -q ' -F dir=/etc/nftables\.d -F perm=wa -F key=firewall-policy$' "$rules_path" ||
    security_config_rules_ok=false
  grep -q ' -F dir=/etc/nftables -F perm=wa -F key=firewall-policy$' "$rules_path" ||
    security_config_rules_ok=false
  grep -q ' -F dir=/etc/audit -F perm=wa -F key=audit-policy$' "$rules_path" ||
    security_config_rules_ok=false
  grep -q ' -F path=/etc/rsyslog\.conf -F perm=wa -F key=syslog-policy$' "$rules_path" ||
    security_config_rules_ok=false
  grep -q ' -F dir=/etc/rsyslog\.d -F perm=wa -F key=syslog-policy$' "$rules_path" ||
    security_config_rules_ok=false
done
if [ "$security_config_rules_ok" = true ]; then
  pass "security profiles audit AppArmor, nftables, auditd, and rsyslog configuration changes"
else
  fail "security profiles audit AppArmor, nftables, auditd, and rsyslog configuration changes"
fi

if [ ! -e "$legacy_apparmor_defaults" ] &&
   ! grep -q 'stage_target_asset .*etc/default/apparmor' "$security_script" &&
   ! grep -q '/etc/default/apparmor' "$standard_rules" "$enhanced_rules"; then
  pass "installer does not stage or audit obsolete Debian AppArmor defaults"
else
  fail "installer does not stage or audit obsolete Debian AppArmor defaults"
fi

if grep -Fq '"etc/audit/${security_class}/rules.d/10-security-${security_class}.rules"' \
     "$security_script"; then
  pass "late security hook stages the selected audit-rule source"
else
  fail "late security hook stages the selected audit-rule source"
fi

if ! grep -q 'audit rules with arch= must include explicit syscall selectors' "$security_script" &&
   ! grep -q 'must not use trailing slashes in dir= filters' "$security_script"; then
  pass "late security hook does not inspect staged audit-rule syntax"
else
  fail "late security hook does not inspect staged audit-rule syntax"
fi

totem_profile="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/usr.bin.totem"
crun_profile="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/crun"
crun_abstraction="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/abstractions/managed-crun-runtime"
timeshift_profile="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/timeshift"
timeshift_abstraction="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/abstractions/managed-timeshift-runtime"
apt_cacher_profile="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/usr.sbin.apt-cacher-ng"
avahi_profile="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/usr.sbin.avahi-daemon"

if grep -q '^profile /usr/bin/totem /usr/bin/totem flags=(attach_disconnected)' "$totem_profile" &&
   grep -q '^  profile sanitized_helper flags=(attach_disconnected)' "$totem_profile" &&
   grep -q '^profile apt-cacher-ng /usr/sbin/apt-cacher-ng flags=(attach_disconnected, complain)' "$apt_cacher_profile" &&
   grep -q '^profile avahi-daemon /usr/sbin/avahi-daemon flags=(attach_disconnected, complain)' "$avahi_profile"; then
  pass "managed AppArmor profiles enforce totem while retaining daemon audit modes"
else
  fail "managed AppArmor profiles enforce totem while retaining daemon audit modes"
fi

if ! grep -Eq 'flags=.*(unconfined|default_allow)' "$totem_profile" "$crun_profile" "$apt_cacher_profile" "$avahi_profile"; then
  pass "managed AppArmor profiles avoid unconfined and default_allow modes"
else
  fail "managed AppArmor profiles avoid unconfined and default_allow modes"
fi

if grep -q '^Include /etc/apparmor.d/$' "$apparmor_parser_conf" &&
   grep -q '^Include /usr/share/apparmor$' "$apparmor_parser_conf" &&
   grep -q '^write-cache$' "$apparmor_parser_conf" &&
   grep -q '^cache-loc=/var/cache/apparmor$' "$apparmor_parser_conf" &&
   grep -q '^Optimize=rule-merge$' "$apparmor_parser_conf" &&
   grep -q '^Optimize=compress-fast$' "$apparmor_parser_conf" &&
   grep -q '^policy-features=/usr/share/apparmor-features/features$' "$apparmor_parser_conf"; then
  pass "managed AppArmor parser.conf uses Debian's package-owned unversioned feature ABI"
else
  fail "managed AppArmor parser.conf uses Debian's package-owned unversioned feature ABI"
fi

if { [ ! -d "$managed_apparmor_features_dir" ] ||
     [ -z "$(find "$managed_apparmor_features_dir" -type f -print -quit)" ]; } &&
   ! grep -q 'stage_target_asset .*usr/share/apparmor-features/features' "$security_script" &&
   ! grep -q '^    /target/usr/share/apparmor-features \\$' "$security_script" &&
   ! grep -q 'apparmor_validate_package_feature_file' "$security_script" &&
   ! grep -q 'AppArmor package feature set' "$security_script"; then
  pass "installer leaves Debian's package-owned AppArmor feature set unmodified and uninspected"
else
  fail "installer leaves Debian's package-owned AppArmor feature set unmodified and uninspected"
fi

if grep -q 'apparmor_managed_profile_files()' "$security_script" &&
   grep -q 'usr.bin.totem' "$security_script" &&
   grep -q 'usr.bin.pwsh' "$security_script" &&
   grep -q '^crun$' "$security_script" &&
   grep -q '^timeshift$' "$security_script" &&
   grep -q 'opt.Bitwarden.bitwarden' "$security_script" &&
   grep -q 'usr.sbin.apt-cacher-ng' "$security_script" &&
   grep -q 'usr.sbin.avahi-daemon' "$security_script" &&
   grep -q '^apparmor_mode_config_has_profile() {$' "$security_script" &&
   ! grep -q 'stage_target_asset .*usr/local/sbin/apparmor-xanmod-features' "$security_script" &&
   grep -q 'apply managed AppArmor profile modes without touching the installer kernel' "$security_script" &&
   grep -q -- '--no-reload' "$security_script" &&
   ! grep -q 'managed wrapper profile set must contain exactly 72 attachments' "$security_script" &&
   ! grep -q 'verify managed AppArmor profile source modes' "$security_script" &&
   ! grep -q '^apparmor_validate_enabled_managed_profiles() {$' "$security_script"; then
  pass "late security hook stages and applies managed AppArmor profiles without post-staging verification"
else
  fail "late security hook stages and applies managed AppArmor profiles without post-staging verification"
fi

if grep -q 'stage_target_asset "$(installer_repo_join_var DIR_HOOKS_SHARED_TARGET usr/local/libexec/augenrules-quiet)" "/usr/local/libexec/augenrules-quiet" 0755' "$security_script" &&
   [ ! -e "$auditd_override" ] &&
   ! grep -q 'auditd.service.d/override.conf' "$security_script" &&
   grep -q 'stage_target_asset "$(installer_repo_join_var DIR_HOOKS_SHARED_TARGET etc/systemd/system/audit-rules.service.d/override.conf)" "/etc/systemd/system/audit-rules.service.d/override.conf" 0644' "$security_script" &&
   grep -q 'stage_target_asset "$(installer_repo_join_var DIR_HOOKS_SHARED_TARGET etc/apparmor/parser.conf)" "/etc/apparmor/parser.conf" 0644' "$security_script" &&
   ! grep -q 'stage_target_asset .*usr/share/apparmor-features/features' "$security_script" &&
   grep -q '^ExecStart=/usr/local/libexec/augenrules-quiet --load$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/systemd/system/audit-rules.service.d/override.conf" &&
   grep -Fq "'No rules'" "$augenrules_wrapper" &&
   grep -Fq "'No change'" "$augenrules_wrapper" &&
   grep -Fq "'loginuid_immutable '[0-9]*" "$augenrules_wrapper" &&
   grep -Fq "'failure '[0-9]*" "$augenrules_wrapper"; then
  pass "audit-rules is the sole filtered augenrules loader without removing real stderr output"
else
  fail "audit-rules is the sole filtered augenrules loader without removing real stderr output"
fi

if grep -Eq '^d-i pkgsel/include string .*auditd .*audispd-plugins .*rsyslog .*logrotate ' "$standard_cfg" &&
   grep -Eq '^d-i pkgsel/include string .*auditd .*audispd-plugins .*rsyslog .*logrotate ' "$enhanced_cfg" &&
   grep -q 'DIR_HOOKS_SHARED_TARGET etc/audit/plugins.d/syslog.conf' "$security_script" &&
   grep -q 'DIR_HOOKS_SHARED_TARGET etc/rsyslog.d/15-audit.conf' "$security_script" &&
   grep -Fxq 'active = no' "$audit_syslog_plugin" &&
   grep -Fxq 'module(load="imfile" mode="polling" PollingInterval="1")' "$audit_route" &&
   grep -Fxq '  File="/var/log/audit/audit.log"' "$audit_route" &&
   grep -Fxq '  deleteStateOnFileDelete="on"' "$audit_route" &&
   grep -Fxq '  deleteStateOnFileMove="on"' "$audit_route" &&
   grep -Fq '$programname == "auditd-file"' "$audit_route" &&
   ! grep -Fq '$programname == "audit"' "$audit_route" &&
   ! grep -Fq '$programname == "auditd"' "$audit_route" &&
   ! grep -Fq '$syslogfacility-text == "kern"' "$audit_route" &&
   ! grep -Fq '$msg contains "audit:"' "$audit_route" &&
   ! grep -Fq '$msg contains "audit("' "$audit_route" &&
   grep -q '^security_mask_target_systemd_unit_if_available() {$' "$security_script" &&
   grep -Fq 'ln -sfn /dev/null "$mask_path"' "$security_script" &&
   grep -Fq '[ "$(readlink "$mask_path")" = /dev/null ]' "$security_script" &&
   grep -q 'security_mask_target_systemd_unit_if_available systemd-journald-audit.socket system' "$security_script" &&
   grep -q 'DIR_HOOKS_SHARED_TARGET etc/rsyslog.d/99-discard.conf' "$security_script" &&
   grep -q 'DIR_HOOKS_SHARED_TARGET etc/logrotate.conf' "$security_script" &&
   grep -q 'DIR_HOOKS_SHARED_TARGET etc/logrotate.d/audit' "$security_script" &&
   grep -q 'DIR_HOOKS_SHARED_TARGET etc/systemd/system/logrotate.timer.d/override.conf' "$security_script" &&
   grep -q 'stage_target_systemd_unit_enabled rsyslog.service system' "$security_script" &&
   grep -q 'stage_target_systemd_unit_enabled logrotate.timer system' "$security_script"; then
  pass "security classes install and stage the complete auditd-to-rsyslog pipeline"
else
  fail "security classes install and stage the complete auditd-to-rsyslog pipeline"
fi

if grep -Fq 'contains_label_prefix' "$managed_modes_transition" &&
   grep -Fq 'bounded_capture(' "$managed_modes_transition" &&
   grep -Fq 'loaded AppArmor profile state' "$managed_modes_transition" &&
   grep -Fq '_profile_is_loaded(' "$managed_modes_transition" &&
   grep -Fq 'disabled AppArmor profile was already absent from the kernel' "$managed_modes_transition"; then
  pass "AppArmor mode reconciliation checks loaded labels before unloading disabled profiles"
else
  fail "AppArmor mode reconciliation checks loaded labels before unloading disabled profiles"
fi

desktop_abstraction="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/abstractions/managed-desktop-application"
desktop_runtime_abstraction="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/abstractions/managed-desktop-runtime"
graphics_abstraction="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/abstractions/managed-desktop-graphics"
bwrap_abstraction="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/abstractions/managed-bwrap-common"
electron_runtime_abstraction="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/abstractions/managed-electron-runtime"
electron_abstraction="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/abstractions/managed-electron-application"
codex_runtime_abstraction="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/abstractions/managed-codex-runtime"
chromium_local="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/local/chromium"
edge_local="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/local/microsoft-edge-stable"
vivaldi_stable_profile="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/vivaldi-stable"
vivaldi_bin_profile="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/vivaldi-bin"
vivaldi_bin_local="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/local/vivaldi-bin"
desktop_wrappers="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/managed-desktop-wrappers"
audio_abstraction="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/abstractions/managed-pipewire-audio"
audio_deny_override="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/abstractions/audio.d/managed-no-raw-audio"
managed_desktop_profiles_are_bounded=true
managed_desktop_profiles_have_local_tmp=true
managed_desktop_profiles_have_bounded_network=true
managed_app_wrapper_block=$(
  awk '
    /^profile managed-labwc-managed-app / { in_profile = 1 }
    in_profile { print }
    in_profile && /^}$/ { exit }
  ' "$desktop_wrappers"
)
launcher_sync_wrapper_block=$(
  awk '
    /^profile managed-labwc-sync-application-launchers / { in_profile = 1 }
    in_profile { print }
    in_profile && /^}$/ { exit }
  ' "$desktop_wrappers"
)
for managed_desktop_profile in \
  usr.bin.totem \
  usr.bin.qoredb \
  usr.bin.gridline \
  usr.bin.spotify \
  usr.bin.sqlitebrowser \
  usr.bin.retroarch \
  usr.bin.qbittorrent \
  usr.bin.telegram-desktop \
  usr.bin.keepassxc \
  usr.bin.zoom \
  opt.Bitwarden.bitwarden \
  opt.Filen.Filen \
  opt.postman.app.Postman \
  opt.ledger-live.AppRun \
  opt.tuta-mail.AppRun \
  Discord \
  obsidian \
  sleek
do
  managed_desktop_profile_path="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/$managed_desktop_profile"
  if grep -Eq '^  /(etc|proc|sys|data|media|mnt|pool|run/media|usr/lib|usr/libexec|usr/share|opt)/\*\* ' \
       "$managed_desktop_profile_path" ||
     grep -q '^  owner @{HOME}/\*\* ' "$managed_desktop_profile_path" ||
     grep -q '^  owner /run/user/\[0-9\]\*/\*\* ' "$managed_desktop_profile_path" ||
     { [ "$managed_desktop_profile" != "opt.postman.app.Postman" ] &&
       grep -Eq '^  /dev/dri/(card|controlD)' "$managed_desktop_profile_path"; } ||
     grep -Eq '^  /dev/nvidia-(uvm|uvm-tools)' "$managed_desktop_profile_path" ||
     grep -q '^  /dev/nvidia-caps/' "$managed_desktop_profile_path" ||
     grep -Eq '^  include.*<abstractions/(X|dri-common|gnome|mesa|opengl|vulkan)>$' \
       "$managed_desktop_profile_path"; then
    managed_desktop_profiles_are_bounded=false
  fi
  if ! grep -Eq '#include <abstractions/managed-(desktop|electron)-application>' \
       "$managed_desktop_profile_path"; then
    managed_desktop_profiles_are_bounded=false
  fi
  if [ "$managed_desktop_profile" = "opt.postman.app.Postman" ] &&
     ! awk '
       $1 ~ "^/dev/dri/" {
         if ($0 != "  /dev/dri/card[0-9]* rw,") {
           invalid_postman_card_rule = 1
         }
         saw_postman_card_rule = 1
       }
       END {
         exit saw_postman_card_rule && !invalid_postman_card_rule ? 0 : 1
       }
     ' "$managed_desktop_profile_path"; then
    managed_desktop_profiles_are_bounded=false
  fi
  if ! grep -q '^  include if exists <abstractions/user-tmp>$' \
       "$managed_desktop_profile_path"; then
    managed_desktop_profiles_have_local_tmp=false
  fi
  if grep -q '^  network,$' "$managed_desktop_profile_path"; then
    managed_desktop_profiles_have_bounded_network=false
  fi
  case "$managed_desktop_profile" in
    usr.bin.keepassxc)
      if grep -Eq '^  network inet(6)? (stream|dgram),$' \
           "$managed_desktop_profile_path"; then
        managed_desktop_profiles_have_bounded_network=false
      fi
      ;;
    usr.bin.sqlitebrowser)
      grep -q '^  network inet dgram,$' "$managed_desktop_profile_path" &&
        grep -q '^  network netlink dgram,$' "$managed_desktop_profile_path" ||
        managed_desktop_profiles_have_bounded_network=false
      if grep -Eq '^  network inet(6)? stream,$|^  network inet6 dgram,$' \
           "$managed_desktop_profile_path"; then
        managed_desktop_profiles_have_bounded_network=false
      fi
      ;;
    *)
      for managed_network_rule in \
        'network inet stream,' \
        'network inet6 stream,' \
        'network inet dgram,' \
        'network inet6 dgram,'
      do
        if ! grep -q "^  ${managed_network_rule}$" \
             "$managed_desktop_profile_path"; then
          managed_desktop_profiles_have_bounded_network=false
        fi
      done
      unset managed_network_rule
      ;;
  esac
done
unset managed_desktop_profile managed_desktop_profile_path

if grep -q '^#include <abstractions/managed-desktop-runtime>$' "$desktop_abstraction" &&
   grep -q '^/usr/bin/xdg-open rpux,$' "$desktop_abstraction" &&
   ! grep -q 'xdg-open' "$desktop_runtime_abstraction" &&
   grep -q '^#include <abstractions/base>$' "$desktop_runtime_abstraction" &&
   grep -q '^include if exists <abstractions/dbus-session>$' "$desktop_runtime_abstraction" &&
   grep -q '^include if exists <abstractions/dconf>$' "$desktop_runtime_abstraction" &&
   grep -q '^#include <abstractions/managed-desktop-graphics>$' "$desktop_runtime_abstraction" &&
   grep -q '^include if exists <abstractions/fonts>$' "$desktop_runtime_abstraction" &&
   grep -q '^include if exists <abstractions/freedesktop.org>$' "$desktop_runtime_abstraction" &&
   grep -q '^include if exists <abstractions/gtk>$' "$desktop_runtime_abstraction" &&
   grep -q '^include <abstractions/nameservice-strict>$' "$desktop_runtime_abstraction" &&
   grep -q '^include if exists <abstractions/openssl>$' "$desktop_runtime_abstraction" &&
   grep -q '^include if exists <abstractions/qt5>$' "$desktop_runtime_abstraction" &&
   grep -q '^include if exists <abstractions/qt6>$' "$desktop_runtime_abstraction" &&
   grep -q '^include if exists <abstractions/ssl_certs>$' "$desktop_runtime_abstraction" &&
   grep -q '^include if exists <abstractions/xdg-desktop>$' "$desktop_runtime_abstraction" &&
   ! grep -q '^include.*<abstractions/nameservice>$' "$desktop_runtime_abstraction" &&
   ! grep -q '^include.*<abstractions/user-tmp>$' "$desktop_runtime_abstraction" &&
   ! grep -q '^include.*<abstractions/dri-common>$' "$desktop_runtime_abstraction" &&
   ! grep -q '^include.*<abstractions/opengl>$' "$desktop_runtime_abstraction" &&
   ! grep -q '^include.*<abstractions/vulkan>$' "$desktop_runtime_abstraction" &&
   grep -q '^#include <abstractions/wayland>$' "$desktop_runtime_abstraction" &&
   ! grep -Eq '^(network|userns|io_uring),$' "$desktop_runtime_abstraction" &&
   ! grep -Eq '^/(etc|sys|usr/lib|usr/libexec|usr/share|opt|data|media|mnt|pool|run/media)/\*\* ' \
     "$desktop_runtime_abstraction" &&
   ! grep -q '^owner @{HOME}/\*\* ' "$desktop_runtime_abstraction" &&
   grep -q '^/home/ r,$' "$desktop_runtime_abstraction" &&
   grep -q '^/{,usr/}bin/{bash,dash,sh} rix,$' "$desktop_runtime_abstraction" &&
   grep -q '^/usr/bin/{awk,basename,cat,cut,dbus-send,dirname,gawk,getconf,getopt,grep,head,lsb_release,mawk,mkdir,mv,nawk,readlink,realpath,sed,sort,touch,tr,uname,xdg-mime,xdg-settings,xprop} rix,$' "$desktop_runtime_abstraction" &&
   grep -q '^owner /run/user/\[0-9\]\*/wayland-\[0-9\]\* rw,$' "$desktop_runtime_abstraction" &&
   ! grep -q '^owner /run/user/\[0-9\]\*/labwc-session.lock rwk,$' "$desktop_runtime_abstraction" &&
   ! grep -q 'crystal-dock.log' "$desktop_runtime_abstraction" &&
   grep -q '^/etc/debian_version r,$' "$desktop_runtime_abstraction" &&
   grep -q '^/usr/lib/os-release r,$' "$desktop_runtime_abstraction" &&
   grep -q '^owner /run/user/\[0-9\]\*/dconf/\*\* rwkl,$' "$desktop_runtime_abstraction" &&
   grep -q '^deny /var/cache/ w,$' "$desktop_runtime_abstraction" &&
   grep -q '^deny /var/cache/fontconfig/ w,$' "$desktop_runtime_abstraction" &&
   grep -q '^deny /var/cache/fontconfig/\*\* rwkl,$' "$desktop_runtime_abstraction" &&
   grep -q '^owner @{HOME}/.pki/nssdb/\*\* rwkl,$' "$desktop_runtime_abstraction" &&
   grep -q '^#include <abstractions/dri-enumerate>$' "$graphics_abstraction" &&
   grep -q '^#include <abstractions/nvidia>$' "$graphics_abstraction" &&
   grep -q '^network netlink dgram,$' "$graphics_abstraction" &&
   grep -q '^network netlink raw,$' "$graphics_abstraction" &&
   grep -q '^/dev/dri/ r,$' "$graphics_abstraction" &&
   grep -q '^/dev/dri/renderD\[0-9\] rw,$' "$graphics_abstraction" &&
   grep -q '^/dev/dri/renderD\[0-9\]\[0-9\] rw,$' "$graphics_abstraction" &&
   grep -q '^/dev/dri/renderD\[0-9\]\[0-9\]\[0-9\] rw,$' "$graphics_abstraction" &&
   ! grep -Eq '^/dev/dri/(card|controlD)' "$graphics_abstraction" &&
   ! grep -q '^/dev/dri/\*\* ' "$graphics_abstraction" &&
   grep -q '^/dev/nvidia\[0-9\]\* rw,$' "$graphics_abstraction" &&
   grep -q '^/dev/nvidia-caps/\*\* rw,$' "$graphics_abstraction" &&
   grep -q '^/dev/nvidia-modeset rw,$' "$graphics_abstraction" &&
   grep -q '^/dev/nvidia-uvm rw,$' "$graphics_abstraction" &&
   grep -q '^/dev/nvidia-uvm-tools rw,$' "$graphics_abstraction" &&
   grep -q '^/dev/nvidiactl rw,$' "$graphics_abstraction" &&
   grep -q '^/dev/char/195:\* rw,$' "$graphics_abstraction" &&
   grep -q '^/dev/char/226:\* rw,$' "$graphics_abstraction" &&
   grep -q '^/dev/char/5\[0-9\]\[0-9\]:\* rw,$' "$graphics_abstraction" &&
   grep -q '^/dev/char/511:\* rw,$' "$graphics_abstraction" &&
   grep -q '^deny /dev/char/{195,226,5\[0-9\]\[0-9\]}:\* l,$' "$graphics_abstraction" &&
   grep -q '^/dev/udmabuf rw,$' "$graphics_abstraction" &&
   grep -q '^/run/udev/data/c195:\* r,$' "$graphics_abstraction" &&
   grep -q '^/run/udev/data/c226:\[0-9\]\[0-9\]\[0-9\] r,$' "$graphics_abstraction" &&
   grep -q '^@{PROC}/driver/nvidia/\*\* r,$' "$graphics_abstraction" &&
   grep -q '^@{sys}/devices/@{pci_bus}/\*\*/{irq,resource} r,$' "$graphics_abstraction" &&
   grep -q '^@{sys}/devices/@{pci_bus}/\*\*/ r,$' "$graphics_abstraction" &&
   grep -q '^@{sys}/bus/\*/devices/ r,$' "$graphics_abstraction" &&
   grep -q '^@{sys}/class/\*/ r,$' "$graphics_abstraction" &&
   grep -q '^@{sys}/devices/\*\*/{bConfigurationValue,busnum,class,descriptors,device,devnum,manufacturer,numa_node,product,serial,subsystem_device,subsystem_vendor,uevent,vendor} r,$' "$graphics_abstraction" &&
   grep -q '^@{sys}/devices/system/cpu/{online,possible} r,$' "$graphics_abstraction" &&
   grep -q '^@{sys}/devices/system/cpu/cpufreq/policy\[0-9\]\*/cpuinfo_max_freq r,$' "$graphics_abstraction" &&
   grep -q '^@{sys}/devices/system/cpu/cpufreq/policy\[0-9\]\*/scaling_cur_freq r,$' "$graphics_abstraction" &&
   grep -q '^@{sys}/devices/system/cpu/cpufreq/policy\[0-9\]\*/scaling_max_freq r,$' "$graphics_abstraction" &&
   grep -q '^@{sys}/devices/system/cpu/cpu\[0-9\]\*/cache/index\[0-9\]\*/size r,$' "$graphics_abstraction" &&
   grep -q '^@{sys}/devices/system/memory/block_size_bytes r,$' "$graphics_abstraction" &&
   grep -q '^@{sys}/devices/system/node/node\[0-9\]\*/cpumap r,$' "$graphics_abstraction" &&
   grep -q '^@{sys}/devices/virtual/dmi/id/{product_name,product_sku,sys_vendor} r,$' "$graphics_abstraction" &&
   grep -q '^/usr/lib/@{multiarch}/dri/\*.so mr,$' "$graphics_abstraction" &&
   grep -q '^/usr/lib/@{multiarch}/lib{EGL,GL,GLESv1_CM,GLESv2,GLX,OpenGL,gbm}.so\* mr,$' "$graphics_abstraction" &&
   grep -q '^/usr/lib/@{multiarch}/libvulkan.so\* mr,$' "$graphics_abstraction" &&
   ! grep -q '^deny /usr/lib/@{multiarch}/libvulkan' "$graphics_abstraction" &&
   grep -Fqx '/usr/local/cuda-*/targets/x86_64-linux/lib/lib{cublas,cublasLt,cudart}.so* mr,' "$graphics_abstraction" &&
   grep -q '^/usr/local/cuda-\*/targets/\*/lib/libOpenCL.so\* mr,$' "$graphics_abstraction" &&
   ! grep -Eq '^/usr/local/cuda-[0-9]+([.][0-9]+)+/' "$graphics_abstraction" &&
   grep -q '^/usr/share/glvnd/egl_vendor.d/\*.json r,$' "$graphics_abstraction" &&
   grep -q '^deny /etc/vulkan/\*\* r,$' "$graphics_abstraction" &&
   grep -q '^deny /usr/share/vulkan/\*\* r,$' "$graphics_abstraction" &&
   grep -q '^owner @{HOME}/.cache/mesa_shader_cache/\*\* rwkl,$' "$graphics_abstraction" &&
   grep -q '^userns,$' "$bwrap_abstraction" &&
   grep -q '^capability chown,$' "$bwrap_abstraction" &&
   grep -q '^capability dac_override,$' "$bwrap_abstraction" &&
   grep -q '^capability setpcap,$' "$bwrap_abstraction" &&
   grep -q '^capability net_admin,$' "$bwrap_abstraction" &&
   grep -q '^capability sys_admin,$' "$bwrap_abstraction" &&
   grep -q '^capability sys_chroot,$' "$bwrap_abstraction" &&
   grep -q '^mount,$' "$bwrap_abstraction" &&
   grep -q '^umount,$' "$bwrap_abstraction" &&
   grep -q '^pivot_root,$' "$bwrap_abstraction" &&
   grep -q '^/newroot/\*\* rwkl,$' "$bwrap_abstraction" &&
   ! grep -Eq '^/(opt/tuta-mail|usr/libexec/glycin-loaders)|@\{HOME\}|@\{XDG_' "$bwrap_abstraction" &&
   grep -q '^@{PROC}/\[0-9\]\*/cgroup r,$' "$electron_runtime_abstraction" &&
   grep -q '^@{PROC}/sys/fs/pipe-max-size r,$' "$electron_runtime_abstraction" &&
   grep -q '^@{PROC}/uptime r,$' "$electron_runtime_abstraction" &&
   grep -q '^@{PROC}/sys/kernel/osrelease r,$' "$electron_abstraction" &&
   grep -q '^@{PROC}/sys/user/max_user_namespaces r,$' "$electron_abstraction" &&
   grep -q '^owner @{HOME}/.cache/nvidia/\*\* rwkl,$' "$graphics_abstraction" &&
   grep -q '^owner @{HOME}/.nv/\*\* rwkl,$' "$graphics_abstraction" &&
   grep -q '^#include <abstractions/managed-desktop-runtime>$' "$electron_runtime_abstraction" &&
   grep -q '^#include <abstractions/managed-electron-runtime>$' "$electron_abstraction" &&
   grep -q '^/usr/bin/xdg-open rpux,$' "$electron_abstraction" &&
   ! grep -Eq '^(userns,|capability[[:space:]]|mount,|umount,|pivot_root,)' "$electron_runtime_abstraction" &&
   grep -q '^userns,$' "$electron_abstraction" &&
   grep -q '^io_uring,$' "$electron_runtime_abstraction" &&
   grep -q '^mqueue type=posix,$' "$electron_runtime_abstraction" &&
   grep -q '^capability sys_admin,$' "$electron_abstraction" &&
   grep -q '^capability sys_chroot,$' "$electron_abstraction" &&
   grep -q '^capability sys_ptrace,$' "$electron_abstraction" &&
   grep -q '^ptrace (read, trace) peer=@{profile_name},$' "$electron_runtime_abstraction" &&
   ! grep -q '^network,$' "$electron_abstraction" &&
   grep -q '^owner @{PROC}/@{pid}/task/ r,$' "$electron_runtime_abstraction" &&
   grep -q '^owner @{PROC}/@{pid}/task/@{tid}/ r,$' "$electron_runtime_abstraction" &&
   grep -q '^owner @{PROC}/@{pid}/oom_score_adj w,$' "$electron_runtime_abstraction" &&
   grep -q '^owner @{PROC}/\[0-9\]\*/oom_score_adj w,$' "$electron_runtime_abstraction" &&
   grep -q '^owner @{PROC}/@{pid}/fd/\[0-9\]\* rw,$' "$electron_runtime_abstraction" &&
   grep -q '^owner @{PROC}/@{pid}/task/@{tid}/comm rw,$' "$electron_runtime_abstraction" &&
   grep -q '^owner @{PROC}/\[0-9\]\*/{cgroup,cmdline,environ,maps,stat,statm,status} r,$' "$electron_runtime_abstraction" &&
   grep -q '^owner @{PROC}/\[0-9\]\*/clear_refs w,$' "$electron_runtime_abstraction" &&
   grep -q '^owner @{PROC}/\[0-9\]\*/{gid_map,setgroups,uid_map} rw,$' "$electron_abstraction" &&
   grep -q '^owner @{PROC}/\[0-9\]\*/smaps_rollup r,$' "$electron_runtime_abstraction" &&
   grep -q '^owner @{PROC}/\[0-9\]\*/task/\[0-9\]\*/comm rw,$' "$electron_runtime_abstraction" &&
   grep -q '^owner @{PROC}/\[0-9\]\*/task/\[0-9\]\*/{stat,status} r,$' "$electron_runtime_abstraction" &&
   grep -q '^@{PROC}/\[0-9\]\*/fd/ r,$' "$electron_runtime_abstraction" &&
   grep -q '^@{PROC}/\[0-9\]\*/mountinfo r,$' "$electron_runtime_abstraction" &&
   ! grep -q '^@{PROC}/\[0-9\]\*/mountinfo r,$' "$electron_abstraction" &&
   grep -q '^@{PROC}/\[0-9\]\*/task/\[0-9\]\*/status r,$' "$electron_runtime_abstraction" &&
   grep -q '^@{PROC}/pressure/{cpu,io,memory} r,$' "$electron_runtime_abstraction" &&
   grep -q '^@{sys}/fs/cgroup/\*\*/cpu.max r,$' "$electron_runtime_abstraction" &&
   grep -q '^@{sys}/fs/cgroup/\*\*/{memory.high,memory.max} r,$' "$electron_runtime_abstraction" &&
   grep -q '^@{sys}/kernel/mm/transparent_hugepage/hpage_pmd_size r,$' "$electron_runtime_abstraction" &&
   grep -q '^deny /dev/tty\[0-9\]\* r,$' "$electron_runtime_abstraction" &&
   [ "$managed_desktop_profiles_are_bounded" = true ] &&
   [ "$managed_desktop_profiles_have_local_tmp" = true ] &&
   [ "$managed_desktop_profiles_have_bounded_network" = true ] &&
   [ -r "$audio_abstraction" ] &&
   [ -r "$audio_deny_override" ] &&
   grep -q '^deny /dev/snd/\*\* rwklm,$' "$audio_deny_override" &&
   grep -q '^deny /dev/snd/ r,$' "$audio_abstraction" &&
   grep -q '^deny /dev/snd/\*\* rwklm,$' "$audio_abstraction" &&
   grep -q '^owner /run/user/\[0-9\]\*/pipewire-\[0-9\]\* rw,$' "$audio_abstraction" &&
   grep -q '^owner /run/user/\[0-9\]\*/pulse/{native,pid} rwk,$' "$audio_abstraction" &&
   ! grep -Eq '#?include( if exists)? <abstractions/audio>' "$audio_abstraction" &&
   grep -q '^deny /dev/snd/\*\* rwklm,$' "$desktop_runtime_abstraction" &&
   grep -q '^/etc/ r,$' "$desktop_runtime_abstraction" &&
   ! grep -q '^/dev/input/' "$desktop_runtime_abstraction" &&
   ! grep -q '^/dev/video' "$desktop_runtime_abstraction" &&
   ! grep -q '^/dev/snd/' "$desktop_runtime_abstraction" &&
   grep -q '^profile bitwarden /opt/Bitwarden/bitwarden flags=(attach_disconnected)' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/opt.Bitwarden.bitwarden" &&
   grep -q '^  /opt/Bitwarden/\*\* mrix,$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/opt.Bitwarden.bitwarden" &&
   grep -q '^  owner @{HOME}/.cache/com.bitwarden.desktop/\*\* rwkl,$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/opt.Bitwarden.bitwarden" &&
   grep -q '^  owner @{HOME}/.config/{chromium,microsoft-edge,vivaldi}/ r,$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/opt.Bitwarden.bitwarden" &&
   grep -q '^  owner @{HOME}/.config/{chromium,microsoft-edge,vivaldi}/NativeMessagingHosts/ rw,$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/opt.Bitwarden.bitwarden" &&
   grep -q '^  owner @{HOME}/.config/{chromium,microsoft-edge,vivaldi}/NativeMessagingHosts/{.bitwarden_desktop_proxy,com.8bit.bitwarden.json} rwkl,$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/opt.Bitwarden.bitwarden" &&
   grep -q '^  owner @{HOME}/.config/{chromium,microsoft-edge}/NativeMessagingHosts/{.app.bw.socket,.app.bw.bitwarden.log} rwkl,$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/opt.Bitwarden.bitwarden" &&
   grep -q '^  deny owner @{HOME}/.mozilla/native-messaging-hosts/ rw,$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/opt.Bitwarden.bitwarden" &&
   grep -q '^  deny owner @{HOME}/.mozilla/native-messaging-hosts/\*\* rwkl,$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/opt.Bitwarden.bitwarden" &&
   ! grep -q '^  owner .*native-messaging-hosts' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/opt.Bitwarden.bitwarden" &&
   grep -q '^owner @{HOME}/.config/chromium/NativeMessagingHosts/.bitwarden_desktop_proxy rix,$' "$chromium_local" &&
   grep -q '^owner @{HOME}/.config/microsoft-edge/NativeMessagingHosts/.bitwarden_desktop_proxy rix,$' "$edge_local" &&
   grep -q '^owner @{HOME}/.config/vivaldi/NativeMessagingHosts/.bitwarden_desktop_proxy rix,$' "$vivaldi_bin_local" &&
   grep -q '^owner @{HOME}/.config/{chromium,microsoft-edge}/NativeMessagingHosts/.app.bw.socket rw,$' "$chromium_local" &&
   grep -q '^owner @{HOME}/.config/{chromium,microsoft-edge}/NativeMessagingHosts/.app.bw.socket rw,$' "$edge_local" &&
   grep -q '^owner @{HOME}/.config/{chromium,microsoft-edge}/NativeMessagingHosts/.app.bw.socket rw,$' "$vivaldi_bin_local" &&
   grep -q '^owner @{HOME}/.config/{chromium,microsoft-edge}/NativeMessagingHosts/.app.bw.bitwarden.log rwkl,$' "$chromium_local" &&
   grep -q '^owner @{HOME}/.config/{chromium,microsoft-edge}/NativeMessagingHosts/.app.bw.bitwarden.log rwkl,$' "$edge_local" &&
   grep -q '^owner @{HOME}/.config/{chromium,microsoft-edge}/NativeMessagingHosts/.app.bw.bitwarden.log rwkl,$' "$vivaldi_bin_local" &&
   printf '%s\n' "$managed_app_wrapper_block" |
     grep -Fqx '  /usr/bin/xdg-dbus-proxy pux,' &&
   printf '%s\n' "$managed_app_wrapper_block" |
     grep -Fqx '  dbus send' &&
   printf '%s\n' "$managed_app_wrapper_block" |
     grep -Fqx '  bus=session' &&
   printf '%s\n' "$managed_app_wrapper_block" |
     grep -Fqx '  path=/org/freedesktop/DBus' &&
   printf '%s\n' "$managed_app_wrapper_block" |
     grep -Fqx '  interface=org.freedesktop.DBus' &&
   printf '%s\n' "$managed_app_wrapper_block" |
     grep -Fqx '  member={GetNameOwner,NameHasOwner,StartServiceByName}' &&
   printf '%s\n' "$managed_app_wrapper_block" |
     grep -Fqx '  peer=(name=org.freedesktop.DBus),' &&
   printf '%s\n' "$launcher_sync_wrapper_block" |
     grep -Fqx '  owner @{HOME}/.config/autostart/bitwarden.desktop rwkl,' &&
   grep -q '^#include <abstractions/managed-electron-runtime>$' "$codex_runtime_abstraction" &&
   grep -q '^userns,$' "$codex_runtime_abstraction" &&
   grep -q '^capability sys_admin,$' "$codex_runtime_abstraction" &&
   grep -q '^capability sys_chroot,$' "$codex_runtime_abstraction" &&
   grep -q '^capability sys_ptrace,$' "$codex_runtime_abstraction" &&
   grep -q '^owner @{PROC}/\[0-9\]\*/{gid_map,setgroups,uid_map} rw,$' "$codex_runtime_abstraction" &&
   grep -q '^/run/udev/data/c13:\* r,$' "$codex_runtime_abstraction" &&
   grep -q '^/var/opt/vivaldi/media-codecs-\*/libffmpeg.so mr,$' "$codex_runtime_abstraction" &&
   grep -q '^/var/cache/debconf/{config.dat,templates.dat} r,$' "$codex_runtime_abstraction" &&
   grep -q '^deny /etc/opt/chrome/ w,$' "$codex_runtime_abstraction" &&
   grep -q '^deny /opt/vivaldi/extensions/ w,$' "$codex_runtime_abstraction" &&
   grep -q '^  network netlink raw,$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/opt.Bitwarden.bitwarden" &&
   grep -q '^profile postman /opt/postman/app/{Postman,postman} flags=(attach_disconnected)' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/opt.postman.app.Postman" &&
   grep -q '^  network netlink raw,$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/opt.postman.app.Postman" &&
   grep -q '^  /{,usr/}bin/{bash,dash,sh} rix,$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/opt.postman.app.Postman" &&
   grep -q '^profile pwsh /{usr/bin/pwsh,opt/microsoft/powershell/\*/pwsh} flags=(attach_disconnected, complain)' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/usr.bin.pwsh" &&
   ! grep -Eq '#include <abstractions/managed-(desktop|electron)-application>' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/usr.bin.pwsh" &&
   grep -q '^profile usr.bin.zoom /{usr/bin/zoom,opt/zoom/{zoom,ZoomLauncher}} flags=(attach_disconnected, mediate_deleted)' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/usr.bin.zoom" &&
   grep -q '^  #include <abstractions/managed-electron-application>$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/usr.bin.zoom" &&
   grep -q '^  #include <abstractions/managed-pipewire-audio>$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/usr.bin.zoom" &&
   grep -q '^  /opt/zoom/{ZoomLauncher,zoom} rix,$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/usr.bin.zoom" &&
   grep -q '^  /opt/zoom/\*\* mrix,$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/usr.bin.zoom" &&
   grep -q '^  owner @{HOME}/.config/zoom/\*\* rwkl,$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/usr.bin.zoom" &&
   grep -q '^  owner @{HOME}/.config/zoomus.conf\* rwkl,$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/usr.bin.zoom" &&
   grep -q '^  owner @{HOME}/.zoom/logs/zoom_stdout_stderr.log rak,$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/usr.bin.zoom" &&
   grep -q '^  /dev/video\* rw,$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/usr.bin.zoom" &&
   grep -q '^profile Discord /opt/discord/Discord flags=(attach_disconnected)' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/Discord" &&
   grep -q '^  #include <abstractions/managed-pipewire-audio>$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/Discord" &&
   grep -q '^  /opt/discord/\*\* mrix,$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/Discord" &&
   grep -q '^  /opt/discord/Discord rix,$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/Discord" &&
   grep -q '^  owner @{HOME}/.config/discord/\*\* rwkl,$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/Discord" &&
   ! grep -Eq '^  owner @\{HOME\}/[.]config/discord/app-[^[:space:]]*[[:space:]]+[^,]*[mix][^,]*,$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/Discord" &&
   ! grep -Eq '^  owner @\{HOME\}/[.]config/discord/app-[^[:space:]]*/.*[[:space:]]+[^,]*[mix][^,]*,$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/Discord" &&
   grep -q '^  owner @{PROC}/\[0-9\]\*/mem r,$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/Discord" &&
   grep -q '^  /dev/video\* rw,$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/Discord" &&
   grep -q '^  network netlink raw,$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/Discord" &&
   grep -q '^profile filen /{usr/bin/{filen,filen-desktop},opt/Filen/Filen} flags=(attach_disconnected)' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/opt.Filen.Filen" &&
   grep -q '^  #include <abstractions/managed-pipewire-audio>$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/opt.Filen.Filen" &&
   grep -q '^  network netlink raw,$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/opt.Filen.Filen" &&
   grep -q '^  /usr/bin/{filen,filen-desktop} mr,$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/opt.Filen.Filen" &&
   grep -q '^  owner @{HOME}/.config/@filen/\*\* rwkl,$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/opt.Filen.Filen" &&
   grep -q '^  owner @{HOME}/.config/@filen/desktop/rclone/bin/\*/{rclone,.copy-\*} rwklmrix,$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/opt.Filen.Filen" &&
   grep -q '^  network netlink raw,$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/opt.ledger-live.AppRun" &&
   grep -q '^  #include <abstractions/managed-pipewire-audio>$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/opt.ledger-live.AppRun" &&
   grep -q '^  /dev/tty rw,$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/opt.ledger-live.AppRun" &&
   grep -q '^  @{sys}/devices/\*\*/report_descriptor r,$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/opt.ledger-live.AppRun" &&
   grep -q '^  owner "@{HOME}/.config/Ledger Wallet/\*\*" rwkl,$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/opt.ledger-live.AppRun" &&
   grep -q '^profile obsidian /{usr/bin/obsidian,opt/Obsidian/obsidian} flags=(attach_disconnected)' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/obsidian" &&
   grep -q '^  network netlink raw,$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/obsidian" &&
   grep -q '^  /usr/bin/obsidian mr,$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/obsidian" &&
   grep -q '^  /usr/bin/{basename,cut,dbus-send,grep,head,mawk,realpath,tr,uname,xdg-mime,xdg-settings,xprop} rix,$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/obsidian" &&
   grep -q '^  owner @{HOME}/Syncthing/ r,$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/obsidian" &&
   grep -q '^  owner @{HOME}/Syncthing/obsidian-md/ rw,$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/obsidian" &&
   grep -q '^  owner @{HOME}/Syncthing/obsidian-md/\*\* rwkl,$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/obsidian" &&
   grep -q '^  owner /run/user/\[0-9\]\*/.obsidian-cli.sock rw,$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/obsidian" &&
   grep -q '^  /run/udev/data/{+usb:\*,c189:\*} r,$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/usr.bin.keepassxc" &&
   grep -q '^profile keepassxc /usr/bin/keepassxc flags=(attach_disconnected, mediate_deleted) {$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/usr.bin.keepassxc" &&
   grep -q '^  deny /dev/dri/card\[0-9\]\* rw,$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/usr.bin.keepassxc" &&
   grep -q '^  @{sys}/devices/\*\*/usb\*/speed r,$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/usr.bin.keepassxc" &&
   grep -q '^  @{sys}/devices/\*\*/usb\*/\*\*/speed r,$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/usr.bin.keepassxc" &&
   grep -q '^  owner @{HOME}/.config/qt6ct/\*\* rwkl,$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/usr.bin.keepassxc" &&
   grep -q '^  owner @{HOME}/.config/qt6ct/\*\* rwkl,$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/usr.bin.qbittorrent" &&
   grep -q '^  @{PROC}/\[0-9\]\*/mountinfo r,$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/usr.bin.qbittorrent" &&
   grep -q '^  network netlink raw,$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/opt.tuta-mail.AppRun" &&
   grep -q '^  /dev/tty rw,$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/opt.tuta-mail.AppRun" &&
   grep -q '^  deny @{sys}/devices/\*\*/iio:device\[0-9\]\*/in_accel_{offset,sampling_frequency,scale,x_raw,y_raw,z_raw} r,$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/opt.tuta-mail.AppRun" &&
   grep -q '^  #include <abstractions/managed-electron-runtime>$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/opt.tuta-mail.AppRun" &&
   grep -q '^  /usr/bin/bwrap rCx -> tuta-bwrap,$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/opt.tuta-mail.AppRun" &&
   grep -q '^  profile tuta-bwrap flags=(attach_disconnected, mediate_deleted) {$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/opt.tuta-mail.AppRun" &&
   grep -q '^    #include <abstractions/managed-bwrap-common>$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/opt.tuta-mail.AppRun" &&
   grep -q '^    /opt/tuta-mail/\*\* rPx -> tuta-mail,$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/opt.tuta-mail.AppRun" &&
   grep -q '^    /usr/libexec/glycin-loaders/2+/glycin-image-rs rPx -> tuta-glycin-loader,$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/opt.tuta-mail.AppRun" &&
   grep -q '^profile tuta-glycin-loader flags=(attach_disconnected, mediate_deleted) {$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/opt.tuta-mail.AppRun" &&
   grep -q '^  owner @{HOME}/.cache/glycin/\*\* rwkl,$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/opt.tuta-mail.AppRun" &&
   grep -q '^  owner @{HOME}/.config/tuta_integration/\*\* rwkl,$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/opt.tuta-mail.AppRun" &&
   grep -q '^  owner @{HOME}/.local/share/applications/tutanota-desktop.desktop rwkl,$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/opt.tuta-mail.AppRun" &&
   grep -q '^  owner @{HOME}/.local/share/icons/hicolor/{64x64,512x512}/apps/tutanota-desktop.png rwkl,$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/opt.tuta-mail.AppRun" &&
   grep -q '^  owner @{HOME}/.config/user-dirs.dirs r,$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/opt.tuta-mail.AppRun" &&
   grep -q '^  owner @{HOME}/@{XDG_DOCUMENTS_DIR}/\*\* r,$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/opt.tuta-mail.AppRun" &&
   grep -q '^  owner @{HOME}/@{XDG_DOWNLOAD_DIR}/\*\* rwkl,$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/opt.tuta-mail.AppRun" &&
   grep -q '^  owner @{HOME}/@{XDG_PICTURES_DIR}/\*\* r,$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/opt.tuta-mail.AppRun" &&
   grep -Fqx '  owner /dev/pts/[0-9]* rw,' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/Discord" &&
   grep -Fqx '  /dev/tty rw,' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/opt.postman.app.Postman" &&
   grep -Fqx '  /usr/bin/{dircolors,env,git,id,run-parts,ssh-agent,starship,zsh} rix,' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/opt.postman.app.Postman" &&
   grep -Fqx '  /etc/zsh/** r,' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/opt.postman.app.Postman" &&
   grep -Fqx '  /usr/share/zsh/** r,' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/opt.postman.app.Postman" &&
   grep -Fqx '  /usr/share/zsh-syntax-highlighting/** r,' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/opt.postman.app.Postman" &&
   grep -Fqx '  owner @{HOME}/.cache/zsh/** rwk,' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/opt.postman.app.Postman" &&
   grep -Fqx '  owner @{HOME}/.config/starship.toml r,' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/opt.postman.app.Postman" &&
   grep -Fqx '  owner @{HOME}/.ssh/agent/** rw,' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/opt.postman.app.Postman" &&
   grep -Fqx '  owner @{HOME}/.zshrc r,' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/opt.postman.app.Postman" &&
   grep -Fqx '  /dev/dri/card[0-9]* rw,' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/opt.postman.app.Postman" &&
   grep -Fqx '  /proc/[0-9]*/loginuid r,' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/opt.postman.app.Postman" &&
   grep -Fqx '  /usr/bin/ r,' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/opt.postman.app.Postman" &&
   grep -Fqx '  /usr/sbin/ r,' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/opt.postman.app.Postman" &&
   grep -Fqx '  /usr/local/bin/ r,' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/opt.postman.app.Postman" &&
   grep -Fqx '  /usr/local/sbin/ r,' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/opt.postman.app.Postman" &&
   grep -Fqx '  /dev/ r,' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/usr.bin.retroarch" &&
   grep -Fqx '  /dev/shm/ r,' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/usr.bin.retroarch" &&
   grep -Fqx '  /run/udev/data/{c13:*,+input:input*} r,' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/usr.bin.retroarch" &&
   grep -Fqx '  /sys/devices/**/power_supply/BAT[0-9]/{capacity,status,type} r,' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/usr.bin.retroarch" &&
   grep -Fqx '  /usr/lib/ r,' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/usr.bin.sqlitebrowser" &&
   grep -Fqx '  /usr/lib64/ r,' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/usr.bin.sqlitebrowser" &&
   grep -Fqx '  /usr/local/lib/ r,' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/usr.bin.sqlitebrowser" &&
   grep -Fqx '  owner @{HOME}/.config/QtProject.conf.lock rwkl,' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/usr.bin.sqlitebrowser" &&
   grep -Fqx '  owner @{HOME}/.config/sqlitebrowser/#[0-9]* rwkl,' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/usr.bin.sqlitebrowser" &&
   grep -Fqx '  owner @{HOME}/.config/sqlitebrowser/sqlitebrowser.conf rwkl,' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/usr.bin.sqlitebrowser" &&
   grep -q '^profile sleek /{usr/bin/sleek,opt/sleek/sleek} flags=(attach_disconnected)' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/sleek" &&
   grep -q '^  network netlink raw,$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/sleek" &&
   grep -q '^  /usr/bin/sleek mr,$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/sleek" &&
   grep -q '^  network inet stream,$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/sleek" &&
   grep -Fqx '  owner @{HOME}/.config/qt6ct/** r,' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/usr.bin.telegram-desktop" &&
   grep -Fqx '  /usr/share/qt6ct/colors/** r,' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/usr.bin.telegram-desktop" &&
   grep -Fqx '  owner @{HOME}/.local/share/TelegramDesktop/#* rwkl,' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/usr.bin.telegram-desktop" &&
   grep -Fqx '  owner @{HOME}/.local/share/TelegramDesktop/log.txt rwkl,' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/usr.bin.telegram-desktop" &&
   grep -q '^  network netlink raw,$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/usr.bin.retroarch" &&
   grep -q '^  network netlink dgram,$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/usr.bin.sqlitebrowser" &&
   grep -q '^  owner @{HOME}/.config/sqlitebrowser/\*\* rwkl,$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/usr.bin.sqlitebrowser" &&
   grep -q '^  /dev/input/\*\* rw,$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/usr.bin.retroarch" &&
   ! grep -R -Eq '#?include( if exists)? <abstractions/audio>' \
     "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d" &&
   ! grep -R -Eq '^[[:space:]]*(owner[[:space:]]+)?/dev/snd' \
     "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d" &&
   grep -q '^  owner @{HOME}/@{XDG_DOCUMENTS_DIR}/\*\* rwkl,$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/usr.bin.zoom" &&
   grep -q '^  owner @{HOME}/@{XDG_DOWNLOAD_DIR}/\*\* rwkl,$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/usr.bin.zoom"; then
  pass "managed desktop profiles keep GPU acceleration while bounding shared filesystem and kernel access"
else
  fail "managed desktop profiles keep GPU acceleration while bounding shared filesystem and kernel access"
fi

apparmor_modes="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor/managed-modes.conf.tmpl"
if grep -q '^__DESKTOP_APPARMOR_STATE__ if-executable code /usr/bin/code$' "$apparmor_modes" &&
   grep -q '^__DESKTOP_APPARMOR_STATE__ if-executable chromium /usr/bin/chromium$' "$apparmor_modes" &&
   ! grep -q ' vscode ' "$apparmor_modes" &&
   grep -q '^__DESKTOP_APPARMOR_STATE__ if-executable microsoft-edge-stable /usr/bin/microsoft-edge-stable$' "$apparmor_modes" &&
   grep -q '^__DESKTOP_APPARMOR_STATE__ optional opt.microsoft.msedge.microsoft-edge -$' "$apparmor_modes" &&
   grep -q '^__DESKTOP_APPARMOR_STATE__ if-executable mullvad-browser /usr/bin/mullvad-browser$' "$apparmor_modes" &&
   grep -q '^__DESKTOP_APPARMOR_STATE__ if-executable vivaldi-stable /usr/bin/vivaldi-stable$' "$apparmor_modes" &&
   grep -q '^__DESKTOP_APPARMOR_STATE__ if-executable vivaldi-bin /usr/bin/vivaldi-stable$' "$apparmor_modes" &&
   grep -q '^__DESKTOP_APPARMOR_STATE__ optional msedge -$' "$apparmor_modes" &&
   grep -q '^__DESKTOP_APPARMOR_STATE__ required opt.ledger-live.AppRun -$' "$apparmor_modes" &&
   grep -q '^__DESKTOP_APPARMOR_STATE__ required Discord -$' "$apparmor_modes" &&
   grep -q '^__DESKTOP_APPARMOR_STATE__ required obsidian -$' "$apparmor_modes" &&
   grep -q '^__DESKTOP_APPARMOR_STATE__ required sleek -$' "$apparmor_modes" &&
   grep -q '^__DESKTOP_APPARMOR_STATE__ required crun -$' "$apparmor_modes" &&
   grep -q '^__DESKTOP_APPARMOR_STATE__ required timeshift -$' "$apparmor_modes" &&
   [ "$(grep -c ' crun ' "$apparmor_modes")" -eq 1 ] &&
   grep -q '^__DESKTOP_APPARMOR_STATE__ optional discord -$' "$apparmor_modes" &&
   grep -q '^__DESKTOP_APPARMOR_STATE__ required usr.bin.keepassxc -$' "$apparmor_modes" &&
   grep -q '^__DESKTOP_APPARMOR_STATE__ if-executable firefox /usr/bin/firefox$' "$apparmor_modes" &&
   grep -q '^__DESKTOP_APPARMOR_STATE__ if-executable usr.bin.man /usr/bin/man$' "$apparmor_modes" &&
   ! grep -Eq '^(enforce|complain|disable)[[:space:]]' "$apparmor_modes"; then
  pass "managed AppArmor source template assigns every profile to the installer-selected desktop state"
else
  fail "managed AppArmor source template assigns every profile to the installer-selected desktop state"
fi

apparmor_coverage_ok=true
for package_profile in \
  1password \
  brave \
  chrome \
  element-desktop \
  firefox \
  github-desktop \
  keybase \
  opera \
  qutebrowser \
  signal-desktop \
  slack \
  steam
do
  if ! grep -Eq "^__DESKTOP_APPARMOR_STATE__ if-executable ${package_profile} /" "$apparmor_modes"; then
    apparmor_coverage_ok=false
  fi
done
for package_profile_spec in \
  'code /usr/bin/code' \
  'chromium /usr/bin/chromium' \
  'microsoft-edge-stable /usr/bin/microsoft-edge-stable' \
  'mullvad-browser /usr/bin/mullvad-browser' \
  'vivaldi-stable /usr/bin/vivaldi-stable' \
  'vivaldi-bin /usr/bin/vivaldi-stable'
do
  package_profile_name=${package_profile_spec%% *}
  package_profile_executable=${package_profile_spec#* }
  if ! grep -q "^__DESKTOP_APPARMOR_STATE__ if-executable ${package_profile_name} ${package_profile_executable}$" \
       "$apparmor_modes"; then
    apparmor_coverage_ok=false
  fi
done
unset package_profile_spec package_profile_name package_profile_executable
for managed_profile in \
  usr.bin.totem \
  usr.bin.qoredb \
  usr.bin.gridline \
  usr.bin.spotify \
  usr.bin.sqlitebrowser \
  usr.bin.retroarch \
  usr.bin.qbittorrent \
  usr.bin.telegram-desktop \
  usr.bin.keepassxc \
  usr.bin.zoom \
  opt.Bitwarden.bitwarden \
  opt.Filen.Filen \
  opt.postman.app.Postman \
  opt.ledger-live.AppRun \
  opt.tuta-mail.AppRun \
  Discord \
  obsidian \
  sleek
do
  if ! grep -q "^__DESKTOP_APPARMOR_STATE__ required ${managed_profile} -$" "$apparmor_modes" ||
     [ ! -r "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/${managed_profile}" ] ||
     ! grep -q '^abi "/usr/share/apparmor-features/features",$' \
       "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/${managed_profile}" ||
     ! grep -Eq '#include <abstractions/managed-(desktop|electron)-application>' \
       "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/${managed_profile}"; then
    apparmor_coverage_ok=false
  fi
done
crun_parser_ok=true
if [ -x /usr/sbin/apparmor_parser ]; then
  /usr/sbin/apparmor_parser \
    -q -Q -K -T \
    -I "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d" \
    -I /etc/apparmor.d \
    "$crun_profile" ||
    crun_parser_ok=false
fi
if ! grep -q '^__DESKTOP_APPARMOR_STATE__ required crun -$' "$apparmor_modes" ||
   [ "$crun_parser_ok" != true ] ||
   ! grep -q '^abi "/usr/share/apparmor-features/features",$' "$crun_profile" ||
   ! grep -q '^profile crun /usr/bin/crun flags=(attach_disconnected, mediate_deleted) {$' "$crun_profile" ||
   ! grep -q '^  #include <abstractions/managed-crun-runtime>$' "$crun_profile" ||
   grep -Eq 'local/crun|flags=.*(audit|complain|default_allow|unconfined)' "$crun_profile" ||
   ! grep -q '^capability,$' "$crun_abstraction" ||
   ! grep -q '^network,$' "$crun_abstraction" ||
   ! grep -q '^unix,$' "$crun_abstraction" ||
   ! grep -q '^dbus,$' "$crun_abstraction" ||
   ! grep -q '^io_uring,$' "$crun_abstraction" ||
   ! grep -q '^mqueue,$' "$crun_abstraction" ||
   ! grep -q '^userns,$' "$crun_abstraction" ||
   ! grep -q '^mount,$' "$crun_abstraction" ||
   ! grep -q '^remount,$' "$crun_abstraction" ||
   ! grep -q '^umount,$' "$crun_abstraction" ||
   ! grep -q '^pivot_root,$' "$crun_abstraction" ||
   ! grep -q '^ptrace,$' "$crun_abstraction" ||
   ! grep -q '^signal,$' "$crun_abstraction" ||
   ! grep -q '^change_profile -> \*\*,$' "$crun_abstraction" ||
   ! grep -q '^change_profile unsafe /\*\* -> \*\*,$' "$crun_abstraction" ||
   ! grep -q '^/dev/fd/\[0-9\]\* rix,$' "$crun_abstraction" ||
   ! grep -q '^/ r,$' "$crun_abstraction" ||
   ! grep -q '^/\*\* rwklm,$' "$crun_abstraction" ||
   ! grep -q '^/\*\* rix,$' "$crun_abstraction" ||
   grep -Eq '#?include( if exists)? <(abstractions|local)/' "$crun_abstraction"; then
  apparmor_coverage_ok=false
fi
unset crun_parser_ok
timeshift_parser_ok=true
if [ -x /usr/sbin/apparmor_parser ]; then
  /usr/sbin/apparmor_parser \
    -q -Q -K -T \
    -I "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d" \
    -I /etc/apparmor.d \
    "$timeshift_profile" ||
    timeshift_parser_ok=false
fi
if ! grep -q '^__DESKTOP_APPARMOR_STATE__ required timeshift -$' "$apparmor_modes" ||
   [ "$timeshift_parser_ok" != true ] ||
   ! grep -q '^abi "/usr/share/apparmor-features/features",$' "$timeshift_profile" ||
   ! grep -q '^profile timeshift /{usr/bin/timeshift,usr/bin/timeshift-gtk,usr/bin/timeshift-launcher,usr/local/libexec/timeshift-managed-snapshot,etc/timeshift/backup-hooks.d/90-grub-btrfs-refresh} flags=(attach_disconnected, mediate_deleted) {$' "$timeshift_profile" ||
   ! grep -q '^  #include <abstractions/managed-timeshift-runtime>$' "$timeshift_profile" ||
   grep -Eq 'local/(timeshift|usr.bin.timeshift)|flags=.*(audit|complain|default_allow|unconfined)' "$timeshift_profile" ||
   ! grep -q '^capability,$' "$timeshift_abstraction" ||
   ! grep -q '^network,$' "$timeshift_abstraction" ||
   ! grep -q '^unix,$' "$timeshift_abstraction" ||
   ! grep -q '^dbus,$' "$timeshift_abstraction" ||
   ! grep -q '^io_uring,$' "$timeshift_abstraction" ||
   ! grep -q '^mqueue,$' "$timeshift_abstraction" ||
   ! grep -q '^userns,$' "$timeshift_abstraction" ||
   ! grep -q '^mount,$' "$timeshift_abstraction" ||
   ! grep -q '^remount,$' "$timeshift_abstraction" ||
   ! grep -q '^umount,$' "$timeshift_abstraction" ||
   ! grep -q '^pivot_root,$' "$timeshift_abstraction" ||
   ! grep -q '^ptrace,$' "$timeshift_abstraction" ||
   ! grep -q '^signal,$' "$timeshift_abstraction" ||
   ! grep -q '^/ r,$' "$timeshift_abstraction" ||
   ! grep -q '^/\*\* rwklm,$' "$timeshift_abstraction" ||
   ! grep -q '^/\*\* rix,$' "$timeshift_abstraction" ||
   grep -Eq '#?include( if exists)? <(abstractions|local)/' "$timeshift_abstraction"; then
  apparmor_coverage_ok=false
fi
unset timeshift_parser_ok
for managed_profile in \
  usr.bin.pwsh \
  usr.sbin.apt-cacher-ng \
  usr.sbin.avahi-daemon
do
  if ! grep -q "^__DESKTOP_APPARMOR_STATE__ required ${managed_profile} -$" "$apparmor_modes" ||
     [ ! -r "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/${managed_profile}" ] ||
     ! grep -q '^abi "/usr/share/apparmor-features/features",$' \
       "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/${managed_profile}"; then
    apparmor_coverage_ok=false
  fi
done
if [ "$apparmor_coverage_ok" = true ]; then
  pass "all managed app classes and desktop launcher applications have explicit profile coverage"
else
  fail "all managed app classes and desktop launcher applications have explicit profile coverage"
fi

package_local_policy_ok=true
for package_local_name in \
  code \
  chromium \
  microsoft-edge-stable \
  mullvad-browser \
  vivaldi-bin
do
  package_local_path="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/local/$package_local_name"
  if [ ! -r "$package_local_path" ] ||
     ! grep -Eq '^#include <abstractions/managed-(desktop|electron)-application>$' \
       "$package_local_path" ||
     ! grep -q '^include if exists <abstractions/user-tmp>$' "$package_local_path" ||
     grep -Eq '^/(etc|proc|sys|data|media|mnt|pool|run/media|usr|opt)/\*\* ' \
       "$package_local_path" ||
     grep -q '^owner @{HOME}/\*\* ' "$package_local_path" ||
     grep -Eq '^/dev/dri/(card|controlD)' "$package_local_path" ||
     grep -q '^/dev/dri/\*\* ' "$package_local_path" ||
     grep -Eq '^/dev/nvidia-(uvm|uvm-tools)' "$package_local_path" ||
     grep -q '^/dev/nvidia-caps/' "$package_local_path" ||
     grep -q '^network,$' "$package_local_path"; then
    package_local_policy_ok=false
  fi
  for package_network_rule in \
    'network inet stream,' \
    'network inet6 stream,' \
    'network inet dgram,' \
    'network inet6 dgram,'
  do
    if ! grep -q "^${package_network_rule}$" "$package_local_path"; then
      package_local_policy_ok=false
    fi
  done
done
unset package_local_name package_local_path package_network_rule

for browser_local_name in \
  chromium \
  microsoft-edge-stable \
  mullvad-browser \
  vivaldi-bin
do
  browser_local_path="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/local/$browser_local_name"
  if ! grep -q '^#include <abstractions/managed-pipewire-audio>$' "$browser_local_path" ||
     ! grep -q '^/dev/video\* rw,$' "$browser_local_path" ||
     ! grep -q '^owner @{HOME}/@{XDG_DOWNLOAD_DIR}/\*\* rwkl,$' "$browser_local_path"; then
    package_local_policy_ok=false
  fi
done
unset browser_local_name browser_local_path

if ! grep -q '^apparmor_managed_local_include_files() {$' "$security_script" ||
   ! grep -q '^apparmor_support_local_include_files() {$' "$security_script" ||
   ! grep -q '^apparmor_obsolete_local_include_files() {$' "$security_script" ||
   ! grep -q '^apparmor_require_disconnected_profile_flags() {$' "$security_script" ||
   ! grep -Fq 'add_flag("attach_disconnected")' "$security_script" ||
   ! grep -Fq 'add_flag("mediate_deleted")' "$security_script" ||
   ! grep -Fq 'profile_basename=${profile_path#/target/etc/apparmor.d/}' "$security_script" ||
   ! grep -Fq 'refusing non-direct AppArmor profile source path:' "$security_script" ||
   ! grep -Fq '[ ! -L "$profile_path" ]' "$security_script" ||
   ! grep -Fq '[ "$profile_size" -le 1048576 ]' "$security_script" ||
   ! grep -Fq 'flag == "unconfined" || flag == "default_allow"' "$security_script" ||
   ! grep -Fq 'mv -f -- "$profile_tmp" "$profile_path"' "$security_script" ||
   ! grep -Fq 'if [ -x /target/opt/vivaldi/vivaldi ]; then' "$security_script" ||
   grep -Fq '[ -x /target/usr/bin/vivaldi-stable ]' "$security_script" ||
   ! grep -Fq 'for apparmor_profile in vivaldi-stable vivaldi-bin; do' "$security_script" ||
   ! grep -Fq '"etc/apparmor.d/${apparmor_profile}")' "$security_script" ||
   ! grep -Fq '"/etc/apparmor.d/${apparmor_profile}"' "$security_script" ||
   ! grep -Fq '"/target/etc/apparmor.d/${apparmor_profile}"' "$security_script" ||
   ! grep -q '^    /target/etc/apparmor.d/disable/crun \\$' "$security_script" ||
   ! grep -q '^    /target/etc/apparmor.d/disable/timeshift \\$' "$security_script" ||
   ! grep -q '^    /target/etc/apparmor.d/force-complain/crun \\$' "$security_script" ||
   ! grep -q '^    /target/etc/apparmor.d/force-complain/timeshift$' "$security_script" ||
   ! grep -q '^apparmor_compat_desktop_local_include_files() {$' "$security_script" ||
   ! grep -q 'etc/apparmor.d/local/${apparmor_local_include}' "$security_script" ||
   ! grep -q 'etc/apparmor.d/local/managed-desktop-application)' "$security_script" ||
   ! grep -q '^#include <abstractions/managed-desktop-application>$' \
     "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/local/managed-desktop-application" ||
   grep -q '^  apparmor_local_source=' "$security_script" ||
   ! grep -q '^/usr/share/code/\*\* mrix,$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/local/code" ||
   ! grep -q '^owner @{HOME}/.config/Code/\*\* rwkl,$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/local/code" ||
   ! grep -q '^owner @{HOME}/.vscode/\*\* rwklm,$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/local/code" ||
   ! grep -q '^owner @{HOME}/.vscode-shared/\*\* rwklm,$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/local/code" ||
   ! grep -q '^owner @{HOME}/.cache/Microsoft/DeveloperTools/\*\* rwkl,$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/local/code" ||
   grep -q 'crystal-dock.log' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/local/code" ||
   ! grep -q '^owner @{HOME}/Workspace/\*\* rwklm,$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/local/code" ||
   ! grep -q '^/usr/lib/{chromium,ungoogled-chromium}/\*\* mrix,$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/local/chromium" ||
   ! grep -q '^owner @{HOME}/.config/chromium/\*\* rwkl,$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/local/chromium" ||
   ! grep -q '^deny /usr/lib/chromium/extensions/ w,$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/local/chromium" ||
   ! grep -q '^/opt/microsoft/msedge/\*\* mrix,$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/local/microsoft-edge-stable" ||
   ! grep -q '^owner @{HOME}/.config/microsoft-edge/\*\* rwkl,$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/local/microsoft-edge-stable" ||
   ! grep -q '^/usr/lib/mullvad-browser/\*\* mrix,$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/local/mullvad-browser" ||
   ! grep -q '^owner @{HOME}/.mullvad-browser/\*\* rwkl,$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/local/mullvad-browser" ||
   ! grep -q '^/usr/bin/bwrap rCx -> mullvad-bwrap,$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/local/mullvad-browser" ||
   ! grep -q '^profile mullvad-bwrap flags=(attach_disconnected, mediate_deleted) {$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/local/mullvad-browser" ||
   ! grep -q '^  #include <abstractions/managed-bwrap-common>$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/local/mullvad-browser" ||
   ! grep -q '^signal (send) set=(kill) peer=mullvad-browser//mullvad-bwrap,$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/local/mullvad-browser" ||
   ! grep -q '^  signal (receive) set=(kill) peer=mullvad-browser,$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/local/mullvad-browser" ||
   ! grep -q '^  /usr/bin/true rix,$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/local/mullvad-browser" ||
   ! grep -q '^/dev/ r,$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/local/mullvad-browser" ||
   ! grep -q '^/etc/mime.types r,$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/local/mullvad-browser" ||
   ! grep -q '^@{sys}/fs/cgroup/\*\*/cpu.max r,$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/local/mullvad-browser" ||
   ! grep -q '^owner @{HOME}/.cache/mullvad/ rw,$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/local/mullvad-browser" ||
   ! grep -q '^owner /run/user/\[0-9\]\*/wayland-proxy-\* rw,$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/local/mullvad-browser" ||
   ! grep -q '^abi "/usr/share/apparmor-features/features",$' "$vivaldi_stable_profile" ||
   ! grep -q '^profile vivaldi-stable /opt/vivaldi/vivaldi flags=(attach_disconnected, mediate_deleted) {$' "$vivaldi_stable_profile" ||
   ! grep -q '^  include if exists <local/vivaldi-stable>$' "$vivaldi_stable_profile" ||
   grep -Eq 'flags=.*(unconfined|default_allow)' "$vivaldi_stable_profile" ||
   ! grep -q '^abi "/usr/share/apparmor-features/features",$' "$vivaldi_bin_profile" ||
   ! grep -q '^profile vivaldi-bin /opt/vivaldi/vivaldi-bin flags=(attach_disconnected, mediate_deleted) {$' "$vivaldi_bin_profile" ||
   ! grep -q '^  include if exists <local/vivaldi-bin>$' "$vivaldi_bin_profile" ||
   grep -Eq 'flags=.*(unconfined|default_allow)' "$vivaldi_bin_profile" ||
   ! grep -q '^#include <abstractions/base>$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/local/vivaldi-stable" ||
   ! grep -q '^deny /dev/snd/\*\* rwklm,$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/local/vivaldi-stable" ||
   ! grep -q '^/{,usr/}bin/bash rix,$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/local/vivaldi-stable" ||
   ! grep -q '^/{,usr/}bin/{cat,dirname,readlink,tr,uname} rix,$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/local/vivaldi-stable" ||
   ! grep -q '^/opt/vivaldi/vivaldi-bin px -> vivaldi-bin,$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/local/vivaldi-stable" ||
   grep -Eq '/usr/bin/.*(curl|wget|sh|rm|chmod|mv|ln|mkdir|touch|timeout|nohup)' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/local/vivaldi-stable" ||
   grep -Eq '^(network|/dev/video|include if exists <abstractions/audio>)' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/local/vivaldi-stable" ||
   grep -q '^owner @{HOME}/.local/lib/vivaldi/' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/local/vivaldi-stable" ||
   ! grep -q '^/opt/vivaldi/\*\* mrix,$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/local/vivaldi-bin" ||
   ! grep -q '^/usr/bin/bwrap rCx -> vivaldi-bwrap,$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/local/vivaldi-bin" ||
   ! grep -q '^profile vivaldi-bwrap flags=(attach_disconnected, mediate_deleted) {$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/local/vivaldi-bin" ||
   ! grep -q '^  #include <abstractions/managed-bwrap-common>$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/local/vivaldi-bin" ||
   ! grep -q '^  #include <abstractions/managed-electron-runtime>$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/local/vivaldi-bin" ||
   ! grep -q '^signal (send) set=(kill) peer=vivaldi-bin//vivaldi-bwrap,$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/local/vivaldi-bin" ||
   ! grep -q '^  signal (receive) set=(kill) peer=vivaldi-bin,$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/local/vivaldi-bin" ||
   ! grep -q '^/usr/libexec/glycin-loaders/2+/glycin-svg mrix,$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/local/vivaldi-bin" ||
   ! grep -q '^/usr/share/glycin-loaders/2+/conf.d/\*\* r,$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/local/vivaldi-bin" ||
   ! grep -q '^/run/dbus/system_bus_socket rw,$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/local/vivaldi-bin" ||
   ! grep -q '^owner /run/user/\[0-9\]\*/bus rw,$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/local/vivaldi-bin" ||
   ! grep -q '^owner @{HOME}/.config/vivaldi/\*\* rwkl,$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/local/vivaldi-bin" ||
   ! grep -q '^owner @{HOME}/Documents/\*\* rwkl,$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/local/vivaldi-bin" ||
   ! grep -q '^owner @{HOME}/.local/share/gvfs-metadata/root-\*.log r,$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/local/vivaldi-bin" ||
   ! grep -q '^owner @{HOME}/Workspace/llama-labwc/output/llama-{cuda,ram}.tar.gz r,$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/local/vivaldi-bin" ||
   ! grep -q '^/pool/build/whisper-labwc/artifacts/whisper-{cuda,ram}.tar.gz r,$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/local/vivaldi-bin" ||
   ! grep -q '^owner @{HOME}/.config/vivaldi/WidevineCdm/\*/_platform_specific/\*/libwidevinecdm.so mr,$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/local/vivaldi-bin" ||
   grep -q '^owner @{HOME}/.local/lib/vivaldi/' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/local/vivaldi-bin" ||
   ! grep -q '^/etc/vivaldi/policies/managed/\*\* r,$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/local/vivaldi-bin" ||
   ! grep -q '^/etc/vivaldi/policies/recommended/\*\* r,$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/local/vivaldi-bin" ||
   ! grep -q '^deny /etc/vivaldi/policies/ w,$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/local/vivaldi-bin" ||
   ! grep -q '^deny /etc/vivaldi/policies/\*\* wkl,$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/local/vivaldi-bin" ||
   ! grep -q '^deny /etc/opt/chrome/ w,$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/local/vivaldi-bin" ||
   ! grep -q '^deny /opt/vivaldi/extensions/ w,$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/local/vivaldi-bin" ||
   [ -e "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/local/crun" ] ||
   ! grep -q '^/var/lib/fangfrisch/update.lock rwk,$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/local/usr.bin.freshclam" ||
   grep -Eq '^/var/lib/fangfrisch/\*\* ' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/local/usr.bin.freshclam" ||
   ! grep -q '^/pool/podman/\*/run/netns/netns-\* r,$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/local/usr.bin.pasta" ||
   grep -Eq '^/pool/podman/\*\* ' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/local/usr.bin.pasta" ||
   ! grep -q '^/usr/lib/@{multiarch}/lib{atomic,c,glib-2.0,m,pcre2-8,seccomp,slirp}.so\* mr,$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/local/slirp4netns"; then
  package_local_policy_ok=false
fi

if [ -x /usr/sbin/apparmor_parser ]; then
  /usr/sbin/apparmor_parser \
    -q -Q -K -T \
    -I "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d" \
    -I /etc/apparmor.d \
    -I /usr/share/apparmor \
    "$vivaldi_stable_profile" ||
    package_local_policy_ok=false
  /usr/sbin/apparmor_parser \
    -q -Q -K -T \
    -I "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d" \
    -I /etc/apparmor.d \
    -I /usr/share/apparmor \
    "$vivaldi_bin_profile" ||
    package_local_policy_ok=false
fi

compat_local_names=$(
  awk '
    /^apparmor_compat_desktop_local_include_files\(\) \{$/ {
      in_function = 1
      next
    }
    in_function && /^}$/ {
      exit
    }
    in_function && /^[a-z0-9-]+$/ {
      print
    }
  ' "$security_script"
)
if [ "$(printf '%s\n' "$compat_local_names" | sed '/^$/d' | wc -l)" -ne 12 ]; then
  package_local_policy_ok=false
fi
for compat_local_name in \
  1password \
  brave \
  chrome \
  element-desktop \
  firefox \
  github-desktop \
  keybase \
  opera \
  qutebrowser \
  signal-desktop \
  slack \
  steam
do
  printf '%s\n' "$compat_local_names" | grep -qx "$compat_local_name" ||
    package_local_policy_ok=false
  grep -Eq "^__DESKTOP_APPARMOR_STATE__ if-executable ${compat_local_name} /" "$apparmor_modes" ||
    package_local_policy_ok=false
done
unset compat_local_name compat_local_names

if [ "$package_local_policy_ok" = true ]; then
  pass "repository profiles and compatibility package profiles receive complete managed policies"
else
  fail "repository profiles and compatibility package profiles receive complete managed policies"
fi

apparmor_flag_case="$TMP_DIR/apparmor-disconnected-flags"
apparmor_flag_target="$apparmor_flag_case/target"
apparmor_flag_profile_dir="$apparmor_flag_target/etc/apparmor.d"
apparmor_flag_runner="$apparmor_flag_case/run-normalizer"
mkdir -p "$apparmor_flag_profile_dir"

apparmor_flag_fixtures_ok=true
if ! python3 - \
  "$security_script" \
  "$apparmor_flag_runner" \
  "$apparmor_flag_profile_dir" <<'PY'
from pathlib import Path
import sys

source_path = Path(sys.argv[1])
runner_path = Path(sys.argv[2])
profile_dir = Path(sys.argv[3])
source = source_path.read_text(encoding="utf-8")
start_marker = "apparmor_require_disconnected_profile_flags() {\n"
end_marker = "\n}\n\napparmor_obsolete_profile_files() {"
if source.count(start_marker) != 1:
    raise SystemExit("expected exactly one AppArmor flag normalizer")
start = source.index(start_marker)
end = source.index(end_marker, start) + 2
function_text = source[start:end]
target_prefix = "/target/etc/apparmor.d/"
if function_text.count(target_prefix) != 2:
    raise SystemExit("unexpected target-prefix count in AppArmor flag normalizer")
function_text = function_text.replace(
    target_prefix,
    profile_dir.as_posix() + "/",
)
runner_path.write_text(
    "#!/bin/sh\n"
    "set -eu\n"
    "installer_fatal() {\n"
    "  printf '%s\\n' \"$*\" >&2\n"
    "  exit 1\n"
    "}\n\n"
    + function_text
    + "\n\napparmor_require_disconnected_profile_flags \"$@\"\n",
    encoding="utf-8",
)
runner_path.chmod(0o700)
PY
then
  apparmor_flag_fixtures_ok=false
fi

apparmor_flag_no_flags="$apparmor_flag_profile_dir/no-flags"
cat >"$apparmor_flag_no_flags" <<'EOF'
profile vivaldi-bin /opt/vivaldi/vivaldi-bin {
  /opt/vivaldi/** mr,
}
EOF
if ! "$apparmor_flag_runner" "$apparmor_flag_no_flags" vivaldi-bin ||
   ! grep -Fqx \
     'profile vivaldi-bin /opt/vivaldi/vivaldi-bin flags=(attach_disconnected, mediate_deleted) {' \
     "$apparmor_flag_no_flags" ||
   ! grep -Fqx '  /opt/vivaldi/** mr,' "$apparmor_flag_no_flags"; then
  apparmor_flag_fixtures_ok=false
fi

apparmor_flag_existing="$apparmor_flag_profile_dir/existing-flags"
cat >"$apparmor_flag_existing" <<'EOF'
profile vivaldi-bin /opt/vivaldi/vivaldi-bin flags=(audit) {
}
EOF
if ! "$apparmor_flag_runner" "$apparmor_flag_existing" vivaldi-bin ||
   ! grep -Fqx \
     'profile vivaldi-bin /opt/vivaldi/vivaldi-bin flags=(audit, attach_disconnected, mediate_deleted) {' \
     "$apparmor_flag_existing"; then
  apparmor_flag_fixtures_ok=false
fi

apparmor_flag_unsafe="$apparmor_flag_profile_dir/unsafe-flags"
apparmor_flag_unsafe_before="$apparmor_flag_case/unsafe-flags.before"
apparmor_flag_unsafe_stderr="$apparmor_flag_case/unsafe-flags.stderr"
cat >"$apparmor_flag_unsafe" <<'EOF'
profile vivaldi-bin /opt/vivaldi/vivaldi-bin flags=(unconfined, default_allow) {
}
EOF
cp "$apparmor_flag_unsafe" "$apparmor_flag_unsafe_before"
if "$apparmor_flag_runner" \
     "$apparmor_flag_unsafe" vivaldi-bin \
     >"$apparmor_flag_case/unsafe-flags.stdout" \
     2>"$apparmor_flag_unsafe_stderr" ||
   ! grep -Fq \
     'cannot normalize disconnected-path flags for AppArmor profile: vivaldi-bin' \
     "$apparmor_flag_unsafe_stderr" ||
   ! cmp -s "$apparmor_flag_unsafe_before" "$apparmor_flag_unsafe"; then
  apparmor_flag_fixtures_ok=false
fi

apparmor_flag_normalized="$apparmor_flag_profile_dir/already-normalized"
apparmor_flag_normalized_before="$apparmor_flag_case/already-normalized.before"
cat >"$apparmor_flag_normalized" <<'EOF'
profile vivaldi-bin /opt/vivaldi/vivaldi-bin flags=(attach_disconnected, mediate_deleted) {
}
EOF
cp "$apparmor_flag_normalized" "$apparmor_flag_normalized_before"
if ! "$apparmor_flag_runner" "$apparmor_flag_normalized" vivaldi-bin ||
   ! cmp -s "$apparmor_flag_normalized_before" "$apparmor_flag_normalized"; then
  apparmor_flag_fixtures_ok=false
fi

apparmor_flag_duplicate="$apparmor_flag_profile_dir/duplicate"
apparmor_flag_duplicate_before="$apparmor_flag_case/duplicate.before"
apparmor_flag_duplicate_stderr="$apparmor_flag_case/duplicate.stderr"
cat >"$apparmor_flag_duplicate" <<'EOF'
profile vivaldi-bin /opt/vivaldi/vivaldi-bin {
}
profile vivaldi-bin /opt/vivaldi/vivaldi-bin {
}
EOF
cp "$apparmor_flag_duplicate" "$apparmor_flag_duplicate_before"
if "$apparmor_flag_runner" \
     "$apparmor_flag_duplicate" vivaldi-bin \
     >"$apparmor_flag_case/duplicate.stdout" \
     2>"$apparmor_flag_duplicate_stderr" ||
   ! grep -Fq \
     'cannot normalize disconnected-path flags for AppArmor profile: vivaldi-bin' \
     "$apparmor_flag_duplicate_stderr" ||
   ! cmp -s "$apparmor_flag_duplicate_before" "$apparmor_flag_duplicate"; then
  apparmor_flag_fixtures_ok=false
fi

apparmor_flag_missing="$apparmor_flag_profile_dir/missing"
apparmor_flag_missing_before="$apparmor_flag_case/missing.before"
apparmor_flag_missing_stderr="$apparmor_flag_case/missing.stderr"
cat >"$apparmor_flag_missing" <<'EOF'
profile another-profile /usr/bin/another-profile {
}
EOF
cp "$apparmor_flag_missing" "$apparmor_flag_missing_before"
if "$apparmor_flag_runner" \
     "$apparmor_flag_missing" vivaldi-bin \
     >"$apparmor_flag_case/missing.stdout" \
     2>"$apparmor_flag_missing_stderr" ||
   ! grep -Fq \
     'cannot normalize disconnected-path flags for AppArmor profile: vivaldi-bin' \
     "$apparmor_flag_missing_stderr" ||
   ! cmp -s "$apparmor_flag_missing_before" "$apparmor_flag_missing"; then
  apparmor_flag_fixtures_ok=false
fi

apparmor_flag_symlink_target="$apparmor_flag_profile_dir/symlink-target"
apparmor_flag_symlink="$apparmor_flag_profile_dir/symlink"
apparmor_flag_symlink_stderr="$apparmor_flag_case/symlink.stderr"
cat >"$apparmor_flag_symlink_target" <<'EOF'
profile vivaldi-bin /opt/vivaldi/vivaldi-bin {
}
EOF
ln -s "$apparmor_flag_symlink_target" "$apparmor_flag_symlink"
if "$apparmor_flag_runner" \
     "$apparmor_flag_symlink" vivaldi-bin \
     >"$apparmor_flag_case/symlink.stdout" \
     2>"$apparmor_flag_symlink_stderr" ||
   ! grep -Fq 'refusing symlinked AppArmor profile source:' \
     "$apparmor_flag_symlink_stderr" ||
   ! grep -Fqx \
     'profile vivaldi-bin /opt/vivaldi/vivaldi-bin {' \
     "$apparmor_flag_symlink_target"; then
  apparmor_flag_fixtures_ok=false
fi

apparmor_flag_nested_dir="$apparmor_flag_profile_dir/nested"
apparmor_flag_nested="$apparmor_flag_nested_dir/profile"
apparmor_flag_nested_stderr="$apparmor_flag_case/nested.stderr"
mkdir -p "$apparmor_flag_nested_dir"
cat >"$apparmor_flag_nested" <<'EOF'
profile vivaldi-bin /opt/vivaldi/vivaldi-bin {
}
EOF
if "$apparmor_flag_runner" \
     "$apparmor_flag_nested" vivaldi-bin \
     >"$apparmor_flag_case/nested.stdout" \
     2>"$apparmor_flag_nested_stderr" ||
   ! grep -Fq 'refusing non-direct AppArmor profile source path:' \
     "$apparmor_flag_nested_stderr" ||
   ! grep -Fqx \
     'profile vivaldi-bin /opt/vivaldi/vivaldi-bin {' \
     "$apparmor_flag_nested"; then
  apparmor_flag_fixtures_ok=false
fi

apparmor_flag_oversized="$apparmor_flag_profile_dir/oversized"
apparmor_flag_oversized_stderr="$apparmor_flag_case/oversized.stderr"
if ! python3 - "$apparmor_flag_oversized" <<'PY'
from pathlib import Path
import sys

Path(sys.argv[1]).write_bytes(b"x" * 1048577)
PY
then
  apparmor_flag_fixtures_ok=false
elif "$apparmor_flag_runner" \
       "$apparmor_flag_oversized" vivaldi-bin \
       >"$apparmor_flag_case/oversized.stdout" \
       2>"$apparmor_flag_oversized_stderr" ||
     ! grep -Fq 'AppArmor profile source exceeds 1048576 bytes:' \
       "$apparmor_flag_oversized_stderr" ||
     [ "$(wc -c <"$apparmor_flag_oversized")" -ne 1048577 ]; then
  apparmor_flag_fixtures_ok=false
fi

if find "$apparmor_flag_profile_dir" \
     -maxdepth 1 -type f -name '*.flags.*' -print -quit |
   grep -q .; then
  apparmor_flag_fixtures_ok=false
fi

if [ "$apparmor_flag_fixtures_ok" = true ]; then
  pass "Vivaldi package-profile flag normalization is idempotent and fails closed"
else
  fail "Vivaldi package-profile flag normalization is idempotent and fails closed"
fi
unset \
  apparmor_flag_case \
  apparmor_flag_duplicate \
  apparmor_flag_duplicate_before \
  apparmor_flag_duplicate_stderr \
  apparmor_flag_existing \
  apparmor_flag_fixtures_ok \
  apparmor_flag_missing \
  apparmor_flag_missing_before \
  apparmor_flag_missing_stderr \
  apparmor_flag_nested \
  apparmor_flag_nested_dir \
  apparmor_flag_nested_stderr \
  apparmor_flag_no_flags \
  apparmor_flag_normalized \
  apparmor_flag_normalized_before \
  apparmor_flag_oversized \
  apparmor_flag_oversized_stderr \
  apparmor_flag_profile_dir \
  apparmor_flag_runner \
  apparmor_flag_symlink \
  apparmor_flag_symlink_stderr \
  apparmor_flag_symlink_target \
  apparmor_flag_target \
  apparmor_flag_unsafe \
  apparmor_flag_unsafe_before \
  apparmor_flag_unsafe_stderr

apparmor_mode_helper_source="$ROOT_DIR/d-i/forky/hooks/shared/target/usr/local/libexec/apparmor-managed-modes-run"
apparmor_mode_module_dir="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/lib/perl5/site_perl/apparmor-managed-modes/AppArmor/ManagedModes"
apparmor_mode_security_script="$ROOT_DIR/d-i/forky/scripts/late/security.sh"
apparmor_mode_module_root="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/lib/perl5/site_perl/apparmor-managed-modes"
apparmor_mode_helper_runner="$TMP_DIR/apparmor-managed-modes-test-runner.pl"
apparmor_mode_perl_compat="$TMP_DIR/apparmor-managed-modes-perl-compat"

apparmor_prepare_perl_compat() {
  mkdir -p "$apparmor_mode_perl_compat/MooX"

  # The installer declares these target dependencies.  The smoke test supplies
  # only compile-time no-op shims when the development host does not provide
  # them, so the behavior probe still exercises the repository modules.
  cat >"$apparmor_mode_perl_compat/MooX/StrictConstructor.pm" <<'EOF'
package MooX::StrictConstructor;
use strict;
use warnings;
sub import { return; }
1;
EOF

  cat >"$apparmor_mode_perl_compat/MooX/TypeTiny.pm" <<'EOF'
package MooX::TypeTiny;
use strict;
use warnings;
sub import { return; }
1;
EOF

  cat >"$apparmor_mode_perl_compat/MooX/Options.pm" <<'EOF'
package MooX::Options;
use strict;
use warnings;
sub import { return; }
1;
EOF
}

apparmor_prepare_perl_compat
apparmor_mode_module_contract_ok=true
for apparmor_mode_module in \
  CLI \
  Config \
  TrustedPath \
  Tool \
  Transition \
  LoadedState \
  Verify \
  Workspace
do
  [ -f "$apparmor_mode_module_dir/${apparmor_mode_module}.pm" ] ||
    apparmor_mode_module_contract_ok=false
done
unset apparmor_mode_module
if grep -qx '#!/usr/bin/perl' "$apparmor_mode_helper_source" &&
   grep -q 'use Cwd qw(abs_path);' "$apparmor_mode_helper_source" &&
   grep -q 'use File::Basename qw(dirname);' "$apparmor_mode_helper_source" &&
   ! grep -q 'FindBin' "$apparmor_mode_helper_source" &&
   grep -q 'use AppArmor::ManagedModes::CLI' "$apparmor_mode_helper_source" &&
   grep -q 'use AppArmor::ManagedModes::Config' "$apparmor_mode_helper_source" &&
   grep -q 'use AppArmor::ManagedModes::Transition' "$apparmor_mode_helper_source" &&
   grep -q 'use AppArmor::ManagedModes::Verify' "$apparmor_mode_helper_source" &&
   [ "$apparmor_mode_module_contract_ok" = true ] &&
   grep -q '/target/usr/local/lib/perl5/site_perl/apparmor-managed-modes/AppArmor/ManagedModes' "$apparmor_mode_security_script" &&
   grep -q '^apparmor_managed_modes_perl_modules() {' "$apparmor_mode_security_script" &&
   grep -q 'AppArmor/ManagedModes/Workspace.pm' "$apparmor_mode_security_script" &&
   grep -q 'usr/local/lib/perl5/site_perl/apparmor-managed-modes/${apparmor_managed_modes_module}' "$apparmor_mode_security_script" &&
   grep -q 'max_config_bytes' "$apparmor_mode_module_dir/Config.pm" &&
   grep -q 'max_tool_diagnostic_bytes' "$apparmor_mode_module_dir/Config.pm" &&
   grep -q 'must be a regular non-symlink file' "$apparmor_mode_module_dir/TrustedPath.pm" &&
   grep -q 'lstat($path)' "$apparmor_mode_module_dir/TrustedPath.pm" &&
   grep -q 'O_NOFOLLOW' "$apparmor_mode_module_dir/TrustedPath.pm" &&
   ! grep -q "open my \$fh, '-|', 'stat'" "$apparmor_mode_module_dir/TrustedPath.pm" &&
   grep -q 'sub _disable_profile' "$apparmor_mode_module_dir/Transition.pm" &&
   grep -q 'sub profile_defines_labels' "$apparmor_mode_module_dir/Transition.pm" &&
   ! grep -q 'aa-disable' "$apparmor_mode_module_dir/Transition.pm" &&
   grep -q 'AppArmor disable entry is not the managed symlink' "$apparmor_mode_module_dir/Transition.pm" &&
   grep -q 'publish_file' "$apparmor_mode_module_dir/Transition.pm" &&
   grep -q 'writable temporary directory must have the sticky bit' "$apparmor_mode_module_dir/Workspace.pm" &&
   grep -q 'File::Temp::tempfile' "$apparmor_mode_module_dir/Workspace.pm" &&
   grep -q -- '--check-loaded' "$apparmor_mode_module_dir/CLI.pm" &&
   grep -q 'loaded profile modes verified' "$apparmor_mode_module_dir/Verify.pm" &&
   grep -q 'installed executable has no package AppArmor profile' "$apparmor_mode_module_dir/Config.pm" &&
   grep -q 'skipping mode management:' "$apparmor_mode_module_dir/Config.pm" &&
   grep -q 'configuration line .* repeats profile file' "$apparmor_mode_module_dir/Config.pm" &&
   grep -q 'profile source already uses .* mode' "$apparmor_mode_module_dir/Transition.pm" &&
   grep -q 'required AppArmor audit tool' "$apparmor_mode_module_dir/Transition.pm" &&
   grep -q 'is missing' "$apparmor_mode_module_dir/Tool.pm" &&
   grep -q 'sub force_argument' "$apparmor_mode_module_dir/Tool.pm" &&
   grep -q 'run_stdout_to_file_limited_or_exit' "$apparmor_mode_module_dir/Tool.pm" &&
   grep -q 'run_with_stderr_file_limited' "$apparmor_mode_module_dir/Tool.pm" &&
   grep -q -- '--force' "$apparmor_mode_module_dir/Tool.pm" &&
   grep -q -- '--remove' "$apparmor_mode_module_dir/Transition.pm" &&
   grep -q -- '--no-reload' "$apparmor_mode_module_dir/Transition.pm" &&
   grep -q -- '--check' "$apparmor_mode_module_dir/CLI.pm"; then
  pass "AppArmor mode helper is a staged Perl CLI with bounded trust and mode-transition modules"
else
  fail "AppArmor mode helper is a staged Perl CLI with bounded trust and mode-transition modules"
fi

if ! grep -Eq \
     'CONFIG_|XanMod|apparmor=1|lsm=|/proc/cmdline|/sys/kernel/security/lsm|/sys/kernel/security/apparmor/features|aa-features-abi|--check-kernel|--kernel-release|--cmdline|--lsm-list|--kernel-feature-root|--policy-features|--features-tool|--parser-config' \
     "$apparmor_mode_helper_source" "$apparmor_mode_module_dir"/*.pm; then
  pass "AppArmor mode helper assumes the installer-provided kernel and LSM baseline without runtime gatekeeping"
else
  fail "AppArmor mode helper assumes the installer-provided kernel and LSM baseline without runtime gatekeeping"
fi

apparmor_mode_helper="$apparmor_mode_helper_source"

apparmor_helper_case="$TMP_DIR/apparmor-helper"
apparmor_helper_profile_dir="$apparmor_helper_case/profiles"
apparmor_helper_tool_dir="$apparmor_helper_case/tools"
apparmor_helper_config="$apparmor_helper_case/managed-modes.conf"
apparmor_helper_executable="$apparmor_helper_case/vendor-app"
apparmor_helper_stderr="$apparmor_helper_case/stderr"
apparmor_helper_unsafe_tmp_dir="$apparmor_helper_case/unsafe-tmp"
apparmor_helper_unsafe_tmp_stderr="$apparmor_helper_case/unsafe-tmp.stderr"
mkdir -p \
  "$apparmor_helper_profile_dir" \
  "$apparmor_helper_tool_dir" \
  "$apparmor_helper_unsafe_tmp_dir"
chmod 0777 "$apparmor_helper_unsafe_tmp_dir"
cat >"$apparmor_mode_helper_runner" <<'EOF'
#!/usr/bin/perl
use strict;
use warnings;

use lib $ENV{APPARMOR_MODE_MODULE_ROOT};
use AppArmor::ManagedModes::TrustedPath ();

no warnings 'redefine';
*AppArmor::ManagedModes::TrustedPath::_file_metadata = sub {
  my ($path) = @_;
  my @metadata = stat($path) or die "cannot inspect test file metadata: $path\n";
  return (0, 0644, $metadata[7], $metadata[2] & 0170000);
};

my $helper = $ENV{APPARMOR_MODE_HELPER};
defined($helper) && $helper ne '' or die "missing AppArmor helper path\n";
my $result = do $helper;
die $@ if $@;
die "cannot execute AppArmor helper: $helper\n" if !defined($result);
EOF
chmod 0755 "$apparmor_mode_helper_runner"
apparmor_mode_helper_run() {
  APPARMOR_MODE_HELPER="$apparmor_mode_helper" \
  APPARMOR_MODE_MODULE_ROOT="$apparmor_mode_module_root" \
  PERL5LIB="$apparmor_mode_perl_compat${PERL5LIB:+:$PERL5LIB}" \
    perl "$apparmor_mode_helper_runner" "$@"
}
cat >"$apparmor_helper_executable" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod 0755 "$apparmor_helper_executable"
printf 'complain if-executable vendor-profile %s\n' \
  "$apparmor_helper_executable" >"$apparmor_helper_config"
if apparmor_mode_helper_run \
     --check \
     --config "$apparmor_helper_config" \
     --profile-dir "$apparmor_helper_profile_dir" \
     --tool-dir "$apparmor_helper_tool_dir" \
     2>"$apparmor_helper_stderr" &&
   grep -q 'warning: installed executable has no package AppArmor profile; skipping mode management' \
     "$apparmor_helper_stderr" &&
   ! TMPDIR="$apparmor_helper_unsafe_tmp_dir" \
     apparmor_mode_helper_run \
       --check \
       --config "$apparmor_helper_config" \
       --profile-dir "$apparmor_helper_profile_dir" \
       --tool-dir "$apparmor_helper_tool_dir" \
       2>"$apparmor_helper_unsafe_tmp_stderr" &&
   grep -q 'writable temporary directory must have the sticky bit' \
     "$apparmor_helper_unsafe_tmp_stderr"; then
  pass "AppArmor mode reconciliation safely handles absent vendor aliases and unsafe temporary directories"
else
  fail "AppArmor mode reconciliation safely handles absent vendor aliases and unsafe temporary directories"
fi

apparmor_optional_stub_case="$TMP_DIR/apparmor-optional-stub"
apparmor_optional_stub_profile_dir="$apparmor_optional_stub_case/profiles"
apparmor_optional_stub_tool_dir="$apparmor_optional_stub_case/tools"
apparmor_optional_stub_config="$apparmor_optional_stub_case/managed-modes.conf"
apparmor_optional_stub_profile="$apparmor_optional_stub_profile_dir/vendor-stub"
apparmor_optional_stub_stdout="$apparmor_optional_stub_case/stdout"
mkdir -p \
  "$apparmor_optional_stub_profile_dir/disable" \
  "$apparmor_optional_stub_tool_dir"
printf '%s\n' '#include if exists <local/vendor-stub>' \
  >"$apparmor_optional_stub_profile"
cat >"$apparmor_optional_stub_tool_dir/apparmor_parser" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod 0755 "$apparmor_optional_stub_tool_dir/apparmor_parser"
ln -s "$apparmor_optional_stub_profile" \
  "$apparmor_optional_stub_profile_dir/disable/vendor-stub"
printf 'complain optional vendor-stub -\n' >"$apparmor_optional_stub_config"
if apparmor_mode_helper_run \
     --no-reload \
     --config "$apparmor_optional_stub_config" \
     --profile-dir "$apparmor_optional_stub_profile_dir" \
     --tool-dir "$apparmor_optional_stub_tool_dir" \
     >"$apparmor_optional_stub_stdout" &&
   [ ! -e "$apparmor_optional_stub_profile_dir/disable/vendor-stub" ] &&
   [ ! -L "$apparmor_optional_stub_profile_dir/disable/vendor-stub" ] &&
   grep -q 'no independent complain mode exists: vendor-stub' \
     "$apparmor_optional_stub_stdout" &&
   apparmor_mode_helper_run \
     --check \
     --config "$apparmor_optional_stub_config" \
     --profile-dir "$apparmor_optional_stub_profile_dir" \
     --tool-dir "$apparmor_optional_stub_tool_dir" \
     >"$apparmor_optional_stub_stdout" &&
   grep -q 'skipping source-mode verification: vendor-stub' \
     "$apparmor_optional_stub_stdout" &&
   ln -s "$apparmor_optional_stub_profile" \
     "$apparmor_optional_stub_profile_dir/disable/vendor-stub" &&
   printf 'enforce optional vendor-stub -\n' >"$apparmor_optional_stub_config" &&
   apparmor_mode_helper_run \
     --no-reload \
     --config "$apparmor_optional_stub_config" \
     --profile-dir "$apparmor_optional_stub_profile_dir" \
     --tool-dir "$apparmor_optional_stub_tool_dir" \
     >"$apparmor_optional_stub_stdout" &&
   [ ! -e "$apparmor_optional_stub_profile_dir/disable/vendor-stub" ] &&
   [ ! -L "$apparmor_optional_stub_profile_dir/disable/vendor-stub" ] &&
   grep -q 'no independent enforce mode exists: vendor-stub' \
     "$apparmor_optional_stub_stdout"; then
  pass "AppArmor global modes skip only optional sources that define no profile labels"
else
  fail "AppArmor global modes skip only optional sources that define no profile labels"
fi

apparmor_legacy_case="$TMP_DIR/apparmor-legacy-mode-tool"
apparmor_legacy_profile_dir="$apparmor_legacy_case/profiles"
apparmor_legacy_tool_dir="$apparmor_legacy_case/tools"
apparmor_legacy_config="$apparmor_legacy_case/managed-modes.conf"
apparmor_legacy_profile="$apparmor_legacy_profile_dir/mullvad-browser"
apparmor_legacy_loaded_state="$apparmor_legacy_case/profiles.loaded"
apparmor_legacy_loaded_stderr="$apparmor_legacy_case/check-loaded.stderr"
mkdir -p "$apparmor_legacy_profile_dir" "$apparmor_legacy_tool_dir"
printf '%s\n' \
  'profile mullvad-browser /bin/true flags=(attach_disconnected) {' \
  '  /bin/true r,' \
  '  profile mullvad-bwrap flags=(attach_disconnected, mediate_deleted) {' \
  '    /bin/true r,' \
  '  }' \
  '}' >"$apparmor_legacy_profile"
printf 'complain required mullvad-browser -\n' >"$apparmor_legacy_config"
cat >"$apparmor_legacy_tool_dir/aa-complain" <<'EOF'
#!/bin/sh
set -eu
if [ "${1:-}" = --help ]; then
  printf '%s\n' 'Usage: aa-complain [--no-reload] [-d DIR] PROFILE'
  exit 0
fi
profile_path=
for complain_arg in "$@"; do
  [ "$complain_arg" != --force ] || exit 64
  profile_path=$complain_arg
done
[ -n "$profile_path" ]
sed -i \
  's/flags=(attach_disconnected)/flags=(attach_disconnected, complain)/' \
  "$profile_path"
EOF
cat >"$apparmor_legacy_tool_dir/aa-audit" <<'EOF'
#!/bin/sh
exit 0
EOF
cat >"$apparmor_legacy_tool_dir/apparmor_parser" <<'EOF'
#!/bin/sh
set -eu
printf '%s\n' \
  mullvad-browser \
  mullvad-browser//mullvad-bwrap
EOF
chmod 0755 \
  "$apparmor_legacy_tool_dir/aa-audit" \
  "$apparmor_legacy_tool_dir/aa-complain" \
  "$apparmor_legacy_tool_dir/apparmor_parser"
if apparmor_mode_helper_run \
     --no-reload \
     --config "$apparmor_legacy_config" \
     --profile-dir "$apparmor_legacy_profile_dir" \
     --tool-dir "$apparmor_legacy_tool_dir" &&
   grep -Eq 'flags=\([^)]*complain([[:space:],)]|$)' "$apparmor_legacy_profile"; then
  pass "AppArmor mode reconciliation omits unsupported --force options on legacy utilities"
else
  fail "AppArmor mode reconciliation omits unsupported --force options on legacy utilities"
fi

printf '%s\n' \
  'mullvad-browser (complain)' \
  'mullvad-browser//mullvad-bwrap (enforce)' >"$apparmor_legacy_loaded_state"
if apparmor_mode_helper_run \
     --check-loaded \
     --config "$apparmor_legacy_config" \
     --profile-dir "$apparmor_legacy_profile_dir" \
     --tool-dir "$apparmor_legacy_tool_dir" \
     --loaded-profiles "$apparmor_legacy_loaded_state"; then
  printf '%s\n' \
    'mullvad-browser (complain)' \
    'mullvad-browser//mullvad-bwrap (unconfined)' >"$apparmor_legacy_loaded_state"
  if apparmor_mode_helper_run \
       --check-loaded \
       --config "$apparmor_legacy_config" \
       --profile-dir "$apparmor_legacy_profile_dir" \
       --tool-dir "$apparmor_legacy_tool_dir" \
       --loaded-profiles "$apparmor_legacy_loaded_state" \
       2>"$apparmor_legacy_loaded_stderr"; then
    fail "Mullvad Browser complain mode accepts only confined mullvad-bwrap child modes"
  elif grep -q \
       'AppArmor child profile is not loaded in a confined mode: mullvad-browser//mullvad-bwrap' \
       "$apparmor_legacy_loaded_stderr"; then
    pass "Mullvad Browser complain mode accepts only confined mullvad-bwrap child modes"
  else
    fail "Mullvad Browser complain mode accepts only confined mullvad-bwrap child modes"
  fi
else
  fail "Mullvad Browser complain mode accepts only confined mullvad-bwrap child modes"
fi

apparmor_label_overflow_stderr="$TMP_DIR/apparmor-profile-label-overflow.stderr"
cat >"$apparmor_legacy_tool_dir/apparmor_parser" <<'EOF'
#!/bin/sh
/usr/bin/perl -e 'print "x" x 65537'
EOF
chmod 0755 "$apparmor_legacy_tool_dir/apparmor_parser"
if apparmor_mode_helper_run \
     --check-loaded \
     --config "$apparmor_legacy_config" \
     --profile-dir "$apparmor_legacy_profile_dir" \
     --tool-dir "$apparmor_legacy_tool_dir" \
     --loaded-profiles "$apparmor_legacy_loaded_state" \
     2>"$apparmor_label_overflow_stderr"; then
  fail "AppArmor loaded-mode verification bounds parser label output"
elif grep -q \
     'AppArmor profile labels exceed 65536 bytes: mullvad-browser' \
     "$apparmor_label_overflow_stderr"; then
  pass "AppArmor loaded-mode verification bounds parser label output"
else
  fail "AppArmor loaded-mode verification bounds parser label output"
fi

apparmor_disable_case="$TMP_DIR/apparmor-disable"
apparmor_disable_profile_dir="$apparmor_disable_case/profiles"
apparmor_disable_tool_dir="$apparmor_disable_case/tools"
apparmor_disable_config="$apparmor_disable_case/managed-modes.conf"
apparmor_disable_profile="$apparmor_disable_profile_dir/disabled-profile"
apparmor_disable_loaded_state="$apparmor_disable_case/profiles.loaded"
apparmor_disable_marker="$apparmor_disable_case/apparmor-parser.args"
mkdir -p "$apparmor_disable_profile_dir" "$apparmor_disable_tool_dir"
printf '%s\n' \
  'profile disabled-profile /bin/true flags=(attach_disconnected) {' \
  '  /bin/true r,' \
  '}' >"$apparmor_disable_profile"
printf 'disable required disabled-profile -\n' >"$apparmor_disable_config"
printf 'not-disabled-profile (enforce)\n' >"$apparmor_disable_loaded_state"
cat >"$apparmor_disable_tool_dir/apparmor_parser" <<'EOF'
#!/bin/sh
set -eu
case " $* " in
  *' -N '*)
    printf 'disabled-profile\n'
    ;;
  *' -R '*)
    printf '%s\n' "$*" >>"$APPARMOR_TEST_DISABLE_MARKER"
    ;;
  *)
    profile_path=
    for parser_arg in "$@"; do
      profile_path=$parser_arg
    done
    profile_name=${profile_path##*/}
    profile_parent=${profile_path%/*}
    if [ -L "${profile_parent}/disable/${profile_name}" ]; then
      exit 0
    fi
    printf 'disabled-profile\n'
    ;;
esac
EOF
chmod 0755 "$apparmor_disable_tool_dir/apparmor_parser"
if APPARMOR_TEST_DISABLE_MARKER="$apparmor_disable_marker" \
   apparmor_mode_helper_run \
     --no-reload \
     --config "$apparmor_disable_config" \
     --profile-dir "$apparmor_disable_profile_dir" \
     --tool-dir "$apparmor_disable_tool_dir" &&
   [ -L "$apparmor_disable_profile_dir/disable/disabled-profile" ] &&
   [ "$(readlink "$apparmor_disable_profile_dir/disable/disabled-profile")" = "$apparmor_disable_profile" ] &&
   [ "$(stat -c '%a' -- "$apparmor_disable_profile_dir/disable")" = 755 ] &&
   [ ! -e "$apparmor_disable_marker" ] &&
   APPARMOR_TEST_DISABLE_MARKER="$apparmor_disable_marker" \
   apparmor_mode_helper_run \
     --config "$apparmor_disable_config" \
     --profile-dir "$apparmor_disable_profile_dir" \
     --tool-dir "$apparmor_disable_tool_dir" \
     --loaded-profiles "$apparmor_disable_loaded_state" &&
   [ ! -e "$apparmor_disable_marker" ]; then
  pass "AppArmor disable mode preserves directory permissions and skips unloaded profile removals"
else
  fail "AppArmor disable mode preserves directory permissions and skips unloaded profile removals"
fi

apparmor_loaded_case="$TMP_DIR/apparmor-loaded"
apparmor_loaded_profile_dir="$apparmor_loaded_case/profiles"
apparmor_loaded_tool_dir="$apparmor_loaded_case/tools"
apparmor_loaded_config="$apparmor_loaded_case/managed-modes.conf"
apparmor_loaded_profile="$apparmor_loaded_profile_dir/loaded-profile"
apparmor_loaded_state="$apparmor_loaded_case/profiles.loaded"
apparmor_loaded_stdout="$apparmor_loaded_case/stdout"
apparmor_loaded_stderr="$apparmor_loaded_case/stderr"
mkdir -p "$apparmor_loaded_profile_dir" "$apparmor_loaded_tool_dir"
printf '%s\n' \
  'profile loaded-profile /bin/true flags=(attach_disconnected, audit, unconfined) {' \
  '  /bin/true r,' \
  '}' >"$apparmor_loaded_profile"
printf 'enforce required loaded-profile -\n' >"$apparmor_loaded_config"
: >"$apparmor_loaded_state"
cat >"$apparmor_loaded_tool_dir/aa-enforce" <<'EOF'
#!/bin/sh
set -eu
if [ "${1:-}" = --help ]; then
  printf '%s\n' '  --force'
  exit 0
fi
force_seen=false
profile_path=
for enforce_arg in "$@"; do
  [ "$enforce_arg" = --force ] && force_seen=true
  profile_path=$enforce_arg
done
[ "$force_seen" = true ]
[ -n "$profile_path" ]
sed -i 's/, unconfined//' "$profile_path"
printf 'loaded-profile (enforce)\n' >"$APPARMOR_TEST_LOADED_PROFILES"
EOF
cat >"$apparmor_loaded_tool_dir/aa-audit" <<'EOF'
#!/bin/sh
set -eu
profile_path=
for audit_arg in "$@"; do
  profile_path=$audit_arg
done
[ -n "$profile_path" ]
sed -i 's/, audit//' "$profile_path"
printf 'loaded-profile (enforce)\n' >"$APPARMOR_TEST_LOADED_PROFILES"
EOF
cat >"$apparmor_loaded_tool_dir/apparmor_parser" <<'EOF'
#!/bin/sh
set -eu
printf 'loaded-profile\n'
EOF
chmod 0755 \
  "$apparmor_loaded_tool_dir/aa-audit" \
  "$apparmor_loaded_tool_dir/aa-enforce" \
  "$apparmor_loaded_tool_dir/apparmor_parser"
if APPARMOR_TEST_LOADED_PROFILES="$apparmor_loaded_state" \
   apparmor_mode_helper_run \
     --config "$apparmor_loaded_config" \
     --profile-dir "$apparmor_loaded_profile_dir" \
     --tool-dir "$apparmor_loaded_tool_dir" \
     --loaded-profiles "$apparmor_loaded_state" \
     >"$apparmor_loaded_stdout" 2>"$apparmor_loaded_stderr" &&
   ! grep -Eq 'audit|unconfined|default_allow' "$apparmor_loaded_profile" &&
   grep -q 'loaded profile modes verified' "$apparmor_loaded_stdout"; then
  printf 'loaded-profile (complain)\n' >"$apparmor_loaded_state"
  if apparmor_mode_helper_run \
       --check-loaded \
       --config "$apparmor_loaded_config" \
       --profile-dir "$apparmor_loaded_profile_dir" \
       --tool-dir "$apparmor_loaded_tool_dir" \
       --loaded-profiles "$apparmor_loaded_state" \
       >"$apparmor_loaded_stdout" 2>"$apparmor_loaded_stderr"; then
    fail "AppArmor loaded-mode verification detects loaded/source mismatches"
  elif grep -q 'AppArmor profile is not loaded in enforce mode: loaded-profile' "$apparmor_loaded_stderr"; then
    pass "AppArmor forced mode conversion reloads vendor profiles and detects loaded/source mismatches"
  else
    fail "AppArmor forced mode conversion reloads vendor profiles and detects loaded/source mismatches"
  fi
else
  fail "AppArmor forced mode conversion reloads vendor profiles and detects loaded/source mismatches"
fi

removed_kernel_gate_stderr="$TMP_DIR/apparmor-removed-kernel-gate.stderr"
if ! apparmor_mode_helper_run --check-kernel 2>"$removed_kernel_gate_stderr" &&
   grep -q 'unsupported argument: --check-kernel' "$removed_kernel_gate_stderr"; then
  pass "removed AppArmor kernel and LSM gatekeeping cannot be invoked"
else
  fail "removed AppArmor kernel and LSM gatekeeping cannot be invoked"
fi

apparmor_mode_unit="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/systemd/system/apparmor-managed-modes.service"
if grep -q '^Requires=apparmor.service$' "$apparmor_mode_unit" &&
   grep -q '^After=apparmor.service$' "$apparmor_mode_unit" &&
   grep -q '^Before=systemd-user-sessions.service display-manager.service multi-user.target$' "$apparmor_mode_unit" &&
   grep -q '^ReloadPropagatedFrom=apparmor.service$' "$apparmor_mode_unit" &&
   ! grep -q '^ConditionSecurity=' "$apparmor_mode_unit" &&
   ! grep -q '^ExecStartPre=' "$apparmor_mode_unit" &&
   grep -q '^ExecStart=/usr/local/libexec/apparmor-managed-modes-run$' "$apparmor_mode_unit" &&
   [ "$(grep -c '^ExecReload=/usr/local/libexec/apparmor-managed-modes-run$' "$apparmor_mode_unit")" -eq 1 ] &&
   grep -q '^ExecReload=/usr/local/libexec/apparmor-managed-modes-run$' "$apparmor_mode_unit" &&
   grep -q '^NoNewPrivileges=false$' "$apparmor_mode_unit" &&
   grep -q '^ProtectSystem=full$' "$apparmor_mode_unit" &&
   grep -q '^ReadWritePaths=/sys/kernel/security/apparmor$' "$apparmor_mode_unit" &&
   grep -q '^ReadWritePaths=/etc/apparmor.d /var/cache/apparmor$' "$apparmor_mode_unit" &&
   grep -q '^StandardOutput=journal$' "$apparmor_mode_unit" &&
   grep -q '^StandardError=journal$' "$apparmor_mode_unit" &&
   ! grep -q '^StandardOutput=journal+console$' "$apparmor_mode_unit" &&
   ! grep -q '^StandardError=journal+console$' "$apparmor_mode_unit" &&
   grep -q '^WantedBy=multi-user.target$' "$apparmor_mode_unit"; then
  pass "AppArmor mode reconciliation runs before login without console policy dumps"
else
  fail "AppArmor mode reconciliation runs before login without console policy dumps"
fi

firstboot_validation="$ROOT_DIR/d-i/forky/scripts/firstboot/04-validation.sh"
if grep -q 'apparmor-managed-modes.service' "$firstboot_validation" &&
   grep -q 'apparmor_mode_state=$(systemctl is-active apparmor-managed-modes.service' "$firstboot_validation" &&
   grep -q 'check_command apparmor-managed-modes /usr/local/libexec/apparmor-managed-modes-run --check' "$firstboot_validation" &&
   grep -q 'check_command apparmor-managed-modes-loaded /usr/local/libexec/apparmor-managed-modes-run --check-loaded' "$firstboot_validation" &&
   grep -q 'validation_deferred=true unit_state=' "$firstboot_validation" &&
   ! grep -q -- '--check-kernel' "$firstboot_validation" &&
   ! grep -q 'aa-features-abi' "$firstboot_validation" &&
   grep -q 'capture apparmor-status.json aa-status --pretty-json' "$firstboot_validation"; then
  pass "firstboot validation records AppArmor unit, source, loaded-mode, and JSON status evidence"
else
  fail "firstboot validation records AppArmor unit, source, loaded-mode, and JSON status evidence"
fi

[ "$FAIL_COUNT" -eq 0 ]
