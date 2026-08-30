#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/crowdsec-addon-smoke.XXXXXX")
trap 'rm -rf "$TMP_DIR"' EXIT HUP INT TERM

TEST_COUNT=14
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

render_answers() {
  case_name=$1
  classes=$2
  output_path=$3
  error_path=$4

  runtime_dir="$TMP_DIR/runtime-$case_name"
  cmdline="classes=$classes primary_user=user primary_password=secret root_password=root fruux_username=alice fruux_password=token crowdsec_token=ABC123TOKEN"

  if answers_file=$(
    INSTALLER_RUNTIME_DIR="$runtime_dir" \
    INSTALLER_SOURCE_ROOT="$ROOT_DIR/d-i/forky" \
    INSTALLER_CMDLINE="$cmdline" \
      sh "$ROOT_DIR/d-i/forky/scripts/preseed/answers.sh" render "$ROOT_DIR/d-i/forky" 2>"$error_path"
  ); then
    printf '%s\n' "$answers_file" >"$output_path"
    return 0
  fi

  return 1
}

answers_path() {
  sed -n '1p' "$1"
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

printf '1..%s\n' "$TEST_COUNT"

crowdsec_cfg="$ROOT_DIR/d-i/forky/classes/class-addon/crowdsec.cfg"
if grep -q '^d-i pkgsel/include string crowdsec crowdsec-firewall-bouncer-nftables$' "$crowdsec_cfg" &&
   grep -q '^d-i pkgsel/include seen true$' "$crowdsec_cfg" &&
   grep -q '^crowdsec crowdsec/lapi boolean true$' "$crowdsec_cfg" &&
   grep -q '^crowdsec crowdsec/capi boolean false$' "$crowdsec_cfg" &&
   ! grep -q 'suricata' "$crowdsec_cfg"; then
  pass "crowdsec addon keeps the focused package set and defers CAPI registration beyond pkgsel"
else
  fail "crowdsec addon keeps the focused package set and defers CAPI registration beyond pkgsel" "$crowdsec_cfg"
fi

addons_cfg="$ROOT_DIR/d-i/forky/classes/configs/addons.cfg"
if grep -q '^Name: crowdsec$' "$addons_cfg" &&
   grep -q '^DebianAptPreferences: crowdsec-testing, crowdsec-stable$' "$addons_cfg" &&
   grep -q '^LateHelper: crowdsec$' "$addons_cfg"; then
  pass "crowdsec addon metadata wires target pinning and the late helper"
else
  fail "crowdsec addon metadata wires target pinning and the late helper" "$addons_cfg"
fi

render_out="$TMP_DIR/render.out"
render_err="$TMP_DIR/render.err"
if render_answers crowdsec 'lab,server,standard,dhcp,crowdsec,arch/amd64,cpu/intel,gpu/generic,disk/vm' "$render_out" "$render_err"; then
  answers=$(answers_path "$render_out")
  pkgsel=$(pkgsel_line "$answers")
  crowdsec_repositories_consecutive=true
  awk '
    function repository_index(field, slot) {
      slot = field
      sub(/^apt-setup\/local/, "", slot)
      sub(/\/repository$/, "", slot)
      return slot
    }

    $1 == "d-i" &&
    $2 ~ /^apt-setup\/local[0-9]+\/repository$/ &&
    $3 == "string" &&
    $4 == "https://packagecloud.io/crowdsec/crowdsec/any" &&
    $5 == "any" &&
    $6 == "main" &&
    NF == 6 {
      stable = repository_index($2)
      stable_count++
    }

    $1 == "d-i" &&
    $2 ~ /^apt-setup\/local[0-9]+\/repository$/ &&
    $3 == "string" &&
    $4 == "https://packagecloud.io/crowdsec/crowdsec-testing/any" &&
    $5 == "any" &&
    $6 == "main" &&
    NF == 6 {
      testing = repository_index($2)
      testing_count++
    }

    END {
      if (stable_count != 1 || testing_count != 1 || testing != stable + 1) {
        exit 1
      }
    }
    ' "$answers" || crowdsec_repositories_consecutive=false
  if [ "$crowdsec_repositories_consecutive" = true ] &&
     word_list_has "$pkgsel" crowdsec &&
     word_list_has "$pkgsel" crowdsec-firewall-bouncer-nftables; then
    pass "crowdsec render keeps upstream repositories consecutive and installs the engine plus nftables bouncer"
  else
    fail "crowdsec render keeps upstream repositories consecutive and installs the engine plus nftables bouncer" "$answers"
  fi
else
  fail "crowdsec render keeps upstream repositories consecutive and installs the engine plus nftables bouncer" "$render_err"
fi

testing_pref="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apt/preferences.d/server/crowdsec-testing.pref"
stable_pref="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apt/preferences.d/server/crowdsec-stable.pref"
if grep -q '^Pin: release o=packagecloud.io/crowdsec/crowdsec-testing$' "$testing_pref" &&
   grep -q '^Pin: release l=packagecloud.io/crowdsec/crowdsec-testing$' "$testing_pref" &&
   grep -q '^Pin-Priority: 1001$' "$testing_pref" &&
   grep -q '^Pin: release o=packagecloud.io/crowdsec/crowdsec$' "$stable_pref" &&
   grep -q '^Pin: release l=packagecloud.io/crowdsec/crowdsec$' "$stable_pref" &&
   grep -q '^Pin-Priority: -1$' "$stable_pref"; then
  pass "crowdsec testing now wins and the stable origin is fully blocked"
else
  fail "crowdsec testing now wins and the stable origin is fully blocked" "$testing_pref"
fi

server_cramerz_pref="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apt/preferences.d/server/cramerz.pref"
desktop_cramerz_pref="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apt/preferences.d/desktop/cramerz.pref"
if grep -q '^Pin: origin downloadcontent.opensuse.org$' "$server_cramerz_pref" &&
   grep -q '^Pin-Priority: 100$' "$server_cramerz_pref" &&
   grep -q '^Package: labwc libwlroots-0.20 libwlroots-0.20-dev libwlroots-0.20-examples$' "$server_cramerz_pref" &&
   grep -q '^Pin-Priority: 1001$' "$server_cramerz_pref" &&
   grep -q '^Pin: release o=Debian,n=forky$' "$server_cramerz_pref" &&
   grep -q '^Pin: release o=Debian,n=trixie$' "$server_cramerz_pref" &&
   grep -q '^Pin: release o=Debian,n=sid$' "$server_cramerz_pref" &&
   [ "$(grep -c '^Pin-Priority: -1$' "$server_cramerz_pref")" -eq 3 ] &&
   grep -q '^Pin: release o=obs://build.opensuse.org/home:cramerz:debian/Debian_Unstable,l=home:cramerz:debian,n=Debian_Unstable$' "$desktop_cramerz_pref" &&
   [ "$(grep -c '^Pin-Priority: -1$' "$desktop_cramerz_pref")" -eq 1 ] &&
   grep -q '^#   apt-get install labwc/Debian_Unstable$' "$desktop_cramerz_pref" &&
   grep -q '^#   apt-get install -t Debian_Unstable labwc$' "$desktop_cramerz_pref" &&
   ! grep -q '^Pin: origin ' "$desktop_cramerz_pref" &&
   ! grep -q '^Pin-Priority: 1001$' "$desktop_cramerz_pref" &&
   ! grep -q '^Package: labwc ' "$desktop_cramerz_pref" &&
   ! grep -q '^Pin: release o=Debian,' "$desktop_cramerz_pref" &&
   ! cmp -s "$server_cramerz_pref" "$desktop_cramerz_pref"; then
  pass "desktop package policy uses Debian Forky by default and leaves the cramerz OBS release explicit-only"
else
  fail "desktop package policy uses Debian Forky by default and leaves the cramerz OBS release explicit-only" "$desktop_cramerz_pref"
fi

security_script="$ROOT_DIR/d-i/forky/scripts/late/security.sh"
if grep -q 'installer_selected_class_reference_is_selected addon/crowdsec' "$security_script" &&
   grep -q 'nftables_merge_selected_services "\$effective_services" crowdsec' "$security_script" &&
   grep -q '^opt.microsoft.msedge.msedge$' "$security_script" &&
   grep -q '^usr.bin.code$' "$security_script" &&
   grep -q '^usr.bin.sqlitebrowser$' "$security_script"; then
  pass "late security staging auto-merges the crowdsec overlay and carries the software bundle AppArmor set"
else
  fail "late security staging auto-merges the crowdsec overlay and carries the software bundle AppArmor set" "$security_script"
fi

crowdsec_helper="$ROOT_DIR/d-i/forky/scripts/late/crowdsec.sh"
if grep -q 'systemctl --root=/ disable crowdsec.service crowdsec-firewall-bouncer.service' "$crowdsec_helper" &&
   grep -q 'systemctl --root=/ enable crowdsec-firstboot.service' "$crowdsec_helper" &&
   grep -q '! systemctl --root=/ is-enabled crowdsec.service >/dev/null 2>&1' "$crowdsec_helper" &&
   grep -q 'installer_selected_class_reference_is_selected addon/crowdsec' "$crowdsec_helper" &&
   grep -q 'crowdsec_enroll_token crowdsec_attachment_key' "$crowdsec_helper" &&
   grep -q '^crowdsec_normalize_token() {$' "$crowdsec_helper" &&
   grep -q 'FILE_CROWDSEC_ENROLL_TOKEN' "$crowdsec_helper" &&
   grep -q 'FILE_CROWDSEC_COMPLETE' "$crowdsec_helper" &&
   grep -q 'FILE_CROWDSEC_STATUS' "$crowdsec_helper" &&
   grep -q 'FILE_CROWDSEC_LOG' "$crowdsec_helper" &&
   grep -q 'INSTALLER_LATE_HOST_ENV' "$crowdsec_helper" &&
   grep -Fq '. "$host_env"' "$crowdsec_helper" &&
   grep -Fq 'chmod "$mode" "$target_host_path"' "$crowdsec_helper" &&
   grep -Fq 'target_normalize_systemd_config_parent_modes "$target_path" "$target_root"' "$crowdsec_helper" &&
   grep -q '^chmod 0644 "\${target_root}\${firstboot_env_file}" 2>/dev/null || true$' "$crowdsec_helper" &&
   grep -q 'crowdsec_token not provided on kernel cmdline' "$crowdsec_helper"; then
  pass "crowdsec late helper stages exact asset modes and defers engine enablement until the post-boot bootstrap can validate DNS and provision the managed key"
else
  fail "crowdsec late helper stages exact asset modes and defers engine enablement until the post-boot bootstrap can validate DNS and provision the managed key" "$crowdsec_helper"
fi

helper_runtime_dir="$TMP_DIR/helper-runtime"
helper_target="$TMP_DIR/helper-target"
helper_host_env="$TMP_DIR/helper-host.env"
helper_bootstrap="$helper_runtime_dir/bootstrap/bootstrap.sh"
helper_err="$TMP_DIR/helper.err"
mkdir -p "$helper_runtime_dir/bootstrap" "$helper_target" "$TMP_DIR/helper-env"
if ! (
  INSTALLER_SOURCE_ROOT="$ROOT_DIR/d-i/forky"
  INSTALLER_RUNTIME_DIR="$TMP_DIR/host-env-runtime"
  export INSTALLER_SOURCE_ROOT INSTALLER_RUNTIME_DIR
  # shellcheck disable=SC1090,SC1091
  . "$ROOT_DIR/d-i/forky/scripts/common/lib.sh"
  installer_fetch_host_env "$ROOT_DIR/d-i/forky" btrfs-server "$helper_host_env" 0600
) >/dev/null 2>"$TMP_DIR/helper-host-env.err"; then
  cat "$TMP_DIR/helper-host-env.err" >"$helper_err"
fi
cat >"$helper_bootstrap" <<'EOF'
bootstrap_source_common_lib() { :; }
bootstrap_source_common_support_libs() {
  . "$INSTALLER_SOURCE_ROOT/scripts/common/target.sh"
  run_in_target() { :; }
}
installer_current_seed_base() { printf '%s\n' 'https://preseed.invalid/d-i/forky'; }
installer_seed_base() { installer_current_seed_base; }
installer_ensure_context_loaded() { :; }
installer_selected_class_reference_is_selected() { [ "$1" = addon/crowdsec ]; }
installer_selected_class_for_purpose() { printf '%s\n' server; }
installer_resolve_host_profile() { printf '%s\n' btrfs-server; }
installer_repo_join_var() { printf '%s\n' "$2"; }
bootstrap_fetch_seed_file() {
  bootstrap_fetch_destination=$3
  bootstrap_fetch_mode=$4
  printf '%s\n' staged >"$bootstrap_fetch_destination"
  chmod "$bootstrap_fetch_mode" "$bootstrap_fetch_destination"
}
installer_cmdline_value() {
  [ "$1" = crowdsec_token ] || return 1
  [ -n "${CROWDSEC_TEST_TOKEN:-}" ] || return 1
  printf '%s\n' "$CROWDSEC_TEST_TOKEN"
}
write_shell_config_var() { printf '%s=%s\n' "$1" "$2"; }
run_in_target() { :; }
EOF

install -d -m 0700 "$helper_target/etc/systemd" "$helper_target/etc/systemd/system"
if [ -r "$helper_host_env" ] &&
   INSTALLER_SOURCE_ROOT="$ROOT_DIR/d-i/forky" \
   INSTALLER_BOOTSTRAP_LIB="$helper_bootstrap" \
   INSTALLER_RUNTIME_DIR="$helper_runtime_dir" \
   INSTALLER_LATE_HOST_ENV="$helper_host_env" \
   INSTALLER_LATE_TMP_ENV_DIR="$TMP_DIR/helper-env" \
   sh "$crowdsec_helper" "$helper_target" 2>"$helper_err" &&
   grep -q '^FILE_CROWDSEC_ENROLL_TOKEN=' "$helper_host_env" &&
   [ -d "$helper_target/usr/local/lib/crowdsec" ] &&
   [ ! -e "$helper_target/usr/local/lib/crowdsec/enroll.token" ] &&
   [ "$(stat -c %a "$helper_target/etc/systemd")" = 755 ] &&
   [ "$(stat -c %a "$helper_target/etc/systemd/system")" = 755 ] &&
   [ "$(stat -c %a "$helper_target/etc/systemd/system/crowdsec-firstboot.service")" = 644 ] &&
   [ "$(stat -c %a "$helper_target/etc/systemd/system/crowdsec-firewall-bouncer.service.d/override.conf")" = 644 ] &&
   grep -q "^CROWDSEC_ENROLL_TOKEN_FILE='/usr/local/lib/crowdsec/enroll.token'$" "$helper_target/etc/default/crowdsec-firstboot" &&
   grep -q 'crowdsec_token not provided on kernel cmdline' "$helper_err"; then
  pass "crowdsec late helper normalizes systemd config modes and permits installation without the optional enrollment token"
else
  fail "crowdsec late helper normalizes systemd config modes and permits installation without the optional enrollment token" "$helper_err"
fi

token_target="$TMP_DIR/token-target"
token_err="$TMP_DIR/token.err"
mkdir -p "$token_target"
if INSTALLER_SOURCE_ROOT="$ROOT_DIR/d-i/forky" \
   INSTALLER_BOOTSTRAP_LIB="$helper_bootstrap" \
   INSTALLER_RUNTIME_DIR="$helper_runtime_dir" \
   INSTALLER_LATE_HOST_ENV="$helper_host_env" \
   INSTALLER_LATE_TMP_ENV_DIR="$TMP_DIR/helper-env" \
   CROWDSEC_TEST_TOKEN='"ABC123TOKEN"' \
   sh "$crowdsec_helper" "$token_target" 2>"$token_err" &&
   [ "$(cat "$token_target/usr/local/lib/crowdsec/enroll.token")" = ABC123TOKEN ] &&
   [ "$(stat -c %a "$token_target/usr/local/lib/crowdsec/enroll.token")" = 600 ]; then
  pass "crowdsec late helper persists a normalized preseed enrollment token for first-boot enrollment"
else
  fail "crowdsec late helper persists a normalized preseed enrollment token for first-boot enrollment" "$token_err"
fi

crowdsec_firstboot="$ROOT_DIR/d-i/forky/hooks/shared/target/usr/local/libexec/crowdsec-firstboot"
if grep -q 'cscli hub update' "$crowdsec_firstboot" &&
   grep -q '^CROWDSEC_STATE_DIR=\${CROWDSEC_STATE_DIR:-/usr/local/lib/crowdsec}$' "$crowdsec_firstboot" &&
   grep -q '^CROWDSEC_ENROLL_ATTEMPTS=\${CROWDSEC_ENROLL_ATTEMPTS:-6}$' "$crowdsec_firstboot" &&
   grep -q '^CROWDSEC_ENROLL_RETRY_DELAY_SECONDS=\${CROWDSEC_ENROLL_RETRY_DELAY_SECONDS:-10}$' "$crowdsec_firstboot" &&
   grep -q '^run_required_crowdsec_command() {$' "$crowdsec_firstboot" &&
   grep -q 'cscli collections install crowdsecurity/linux crowdsecurity/auditd --ignore' "$crowdsec_firstboot" &&
   grep -q '^ensure_capi_registration() {$' "$crowdsec_firstboot" &&
   grep -q 'crowdsec_config_path Config.API.Server.OnlineClient.CredentialsFilePath' "$crowdsec_firstboot" &&
   grep -q 'cscli config show -o raw --key "\$config_key"' "$crowdsec_firstboot" &&
   grep -q 'cscli capi register --error' "$crowdsec_firstboot" &&
   grep -q 'cscli console enroll --overwrite --name "\$host_name" "\$crowdsec_token"' "$crowdsec_firstboot" &&
   grep -q '^enroll_console() {$' "$crowdsec_firstboot" &&
   grep -q '^normalize_crowdsec_token() {$' "$crowdsec_firstboot" &&
   grep -q 'console_enrollment=retry hostname=' "$crowdsec_firstboot" &&
   grep -q 'console_enrollment=failed hostname=' "$crowdsec_firstboot" &&
   grep -q 'console_enrollment=pending reason=invalid-token hostname=' "$crowdsec_firstboot" &&
   grep -q 'write_status 1 failed' "$crowdsec_firstboot" &&
   grep -q 'crowdsec-firewall-bouncer.yaml.local' "$crowdsec_firstboot" &&
   grep -q 'cscli bouncers delete "\$bouncer_key_name"' "$crowdsec_firstboot" &&
   grep -q '^run_optional_crowdsec_command() {$' "$crowdsec_firstboot" &&
   grep -q 'wait_for_host_resolution api.crowdsec.net 45' "$crowdsec_firstboot" &&
   grep -q 'systemctl enable crowdsec.service crowdsec-firewall-bouncer.service' "$crowdsec_firstboot" &&
   grep -q 'systemctl start crowdsec.service' "$crowdsec_firstboot" &&
   grep -q 'stop_bootstrap_services' "$crowdsec_firstboot" &&
   grep -q '^remove_enrollment_token() {$' "$crowdsec_firstboot" &&
   ! grep -q 'secondboot.service' "$crowdsec_firstboot" &&
   grep -q 'console_enrollment=pending reason=invalid-token .* token_retained=true' "$crowdsec_firstboot" &&
   ! grep -q 'write_complete_marker invalid-token' "$crowdsec_firstboot" &&
   [ "$(grep -c '^remove_enrollment_token$' "$crowdsec_firstboot")" -eq 1 ] &&
   [ "$(grep -n 'log_line bootstrap info crowdsec "restarting_services=true"' "$crowdsec_firstboot" | cut -d: -f1)" -lt "$(grep -n '^enrollment_status=skipped$' "$crowdsec_firstboot" | cut -d: -f1)" ] &&
   grep -q 'hub_update=fallback-to-packaged-index' "$crowdsec_firstboot" &&
   grep -q '^  chmod 0600 "\$tmp_config" 2>/dev/null || true$' "$crowdsec_firstboot" &&
   ! grep -q 'cscli parsers install' "$crowdsec_firstboot" &&
   ! grep -q 'hub_content_install=skipped' "$crowdsec_firstboot" &&
   ! grep -q 'systemctl start crowdsec.service crowdsec-firewall-bouncer.service' "$crowdsec_firstboot" &&
   ! grep -q 'dataparse-enrich' "$crowdsec_firstboot"; then
  pass "crowdsec firstboot retains invalid enrollment state and completes cleanup only after valid or optional enrollment"
else
  fail "crowdsec firstboot retains invalid enrollment state and completes cleanup only after valid or optional enrollment" "$crowdsec_firstboot"
fi

bouncer_dropin="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/systemd/system/crowdsec-firewall-bouncer.service.d/override.conf"
firstboot_unit="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/systemd/system/crowdsec-firstboot.service"
if grep -q '^After=nftables.service crowdsec.service$' "$bouncer_dropin" &&
   grep -q '^Wants=network-online.target nss-lookup.target time-sync.target auditd.service$' "$firstboot_unit" &&
   grep -q '^After=network-online.target nss-lookup.target time-sync.target auditd.service$' "$firstboot_unit" &&
   grep -q '^ConditionPathExists=!/usr/local/lib/crowdsec/complete$' "$firstboot_unit" &&
   grep -q '^OnSuccess=secondboot.service$' "$firstboot_unit" &&
   grep -q '^Environment=CROWDSEC_ENROLL_ATTEMPTS=6$' "$firstboot_unit" &&
   grep -q '^Environment=CROWDSEC_ENROLL_RETRY_DELAY_SECONDS=10$' "$firstboot_unit" &&
   grep -q '^ExecStart=/usr/local/libexec/crowdsec-firstboot$' "$firstboot_unit" &&
   grep -q '^Restart=on-failure$' "$firstboot_unit" &&
   grep -q '^TimeoutStartSec=10min$' "$firstboot_unit" &&
   grep -q '^WantedBy=multi-user.target$' "$firstboot_unit"; then
  pass "crowdsec systemd ordering waits for dependencies and queues cleanup after successful bootstrap"
else
  fail "crowdsec systemd ordering waits for dependencies and queues cleanup after successful bootstrap" "$firstboot_unit"
fi

server_rules="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/audit/crowdsec/server.rules"
desktop_rules="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/audit/crowdsec/desktop.rules"
if grep -q 'crowdsec-user-exec' "$server_rules" &&
   ! grep -q 'crowdsec-user-exec' "$desktop_rules" &&
   grep -q 'crowdsec-shell' "$desktop_rules"; then
  pass "crowdsec audit rules stay broader on servers and narrower on desktops"
else
  fail "crowdsec audit rules stay broader on servers and narrower on desktops" "$server_rules"
fi

sshd_acquis="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/crowdsec/acquis.d/20-sshd.yaml"
auditd_acquis="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/crowdsec/acquis.d/21-auditd.yaml"
server_syslog_acquis="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/crowdsec/acquis.d/22-server-syslog.yaml"
if grep -q '^source: journalctl$' "$sshd_acquis" &&
   grep -q '^  type: syslog$' "$sshd_acquis" &&
   grep -q '^  type: auditd$' "$auditd_acquis" &&
   grep -q '^source: journalctl$' "$server_syslog_acquis"; then
  pass "crowdsec acquisitions use journalctl for ssh/syslog and auditd files for audit correlation"
else
  fail "crowdsec acquisitions use journalctl for ssh/syslog and auditd files for audit correlation" "$sshd_acquis"
fi

apparmor_modes="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor/managed-modes.conf.tmpl"
if grep -q '^__DESKTOP_APPARMOR_STATE__ if-executable code /usr/bin/code$' "$apparmor_modes" &&
   grep -q '^__DESKTOP_APPARMOR_STATE__ if-executable microsoft-edge-stable /usr/bin/microsoft-edge-stable$' "$apparmor_modes" &&
   grep -q '^profile spotify /usr/bin/spotify flags=(attach_disconnected)' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/usr.bin.spotify" &&
   grep -q '^profile sqlitebrowser /usr/bin/sqlitebrowser flags=(attach_disconnected, mediate_deleted)' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/usr.bin.sqlitebrowser" &&
   grep -q '^profile bitwarden /opt/Bitwarden/bitwarden flags=(attach_disconnected)' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/opt.Bitwarden.bitwarden" &&
   grep -q '^profile ledger-live /opt/ledger-live/AppRun flags=(attach_disconnected)' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/opt.ledger-live.AppRun"; then
  pass "software bundle AppArmor policy covers package-owned and installer-managed applications"
else
  fail "software bundle AppArmor policy covers package-owned and installer-managed applications" "$apparmor_modes"
fi

[ "$FAIL_COUNT" -eq 0 ]
