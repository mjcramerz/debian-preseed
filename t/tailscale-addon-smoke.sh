#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/tailscale-addon-smoke.XXXXXX")
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
  cmdline="classes=$classes primary_user=user primary_password=secret root_password=root fruux_username=alice fruux_password=token ssh_port=45000 tailscale_authkey=tskey-auth-k8s-example-abcdef123456"

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

tailscale_cfg="$ROOT_DIR/d-i/forky/classes/class-addon/tailscale.cfg"
if grep -q '^d-i pkgsel/include string tailscale syncthing$' "$tailscale_cfg" &&
   grep -q '^d-i apt-setup/local14/repository string https://pkgs.tailscale.com/stable/debian trixie main$' "$tailscale_cfg" &&
   grep -q '^d-i apt-setup/local15/repository string https://pkgs.tailscale.com/stable/debian forky main$' "$tailscale_cfg" &&
   grep -q '^d-i apt-setup/local16/repository string https://pkgs.tailscale.com/stable/debian sid main$' "$tailscale_cfg"; then
  pass "tailscale addon fragment installs Tailscale, Syncthing, and all three upstream suites without OpenSSH"
else
  fail "tailscale addon fragment installs Tailscale, Syncthing, and all three upstream suites without OpenSSH" "$tailscale_cfg"
fi

addons_cfg="$ROOT_DIR/d-i/forky/classes/configs/addons.cfg"
if grep -q '^Name: tailscale$' "$addons_cfg" &&
   grep -q '^DebianAptPreferences: tailscale$' "$addons_cfg" &&
   grep -q '^LateHelper: tailscale$' "$addons_cfg"; then
  pass "tailscale addon metadata wires its preference set and late helper"
else
  fail "tailscale addon metadata wires its preference set and late helper" "$addons_cfg"
fi

render_out="$TMP_DIR/render.out"
render_err="$TMP_DIR/render.err"
if render_answers tailscale 'lab,server,standard,dhcp,tailscale,arch/amd64,cpu/intel,gpu/generic,disk/vm' "$render_out" "$render_err"; then
  answers=$(answers_path "$render_out")
  pkgsel=$(pkgsel_line "$answers")
  if grep -q '^d-i apt-setup/local5/repository string https://pkgs.tailscale.com/stable/debian trixie main$' "$answers" &&
     grep -q '^d-i apt-setup/local6/repository string https://pkgs.tailscale.com/stable/debian forky main$' "$answers" &&
     grep -q '^d-i apt-setup/local7/repository string https://pkgs.tailscale.com/stable/debian sid main$' "$answers" &&
     word_list_has "$pkgsel" tailscale &&
     ! word_list_has "$pkgsel" openssh-server &&
     word_list_has "$pkgsel" syncthing; then
    pass "tailscale-only render compacts the three upstream archives onto consecutive local slots and installs the managed package set without OpenSSH"
  else
    fail "tailscale-only render compacts the three upstream archives onto consecutive local slots and installs the managed package set without OpenSSH" "$answers"
  fi
else
  fail "tailscale-only render compacts the three upstream archives onto consecutive local slots and installs the managed package set without OpenSSH" "$render_err"
fi

combined_out="$TMP_DIR/render-combined.out"
combined_err="$TMP_DIR/render-combined.err"
if render_answers tailscale_ssh 'lab,server,standard,dhcp,tailscale,ssh,arch/amd64,cpu/intel,gpu/generic,disk/vm' "$combined_out" "$combined_err"; then
  combined_answers=$(answers_path "$combined_out")
  combined_pkgsel=$(pkgsel_line "$combined_answers")
  if word_list_has "$combined_pkgsel" openssh-server &&
     word_list_has "$combined_pkgsel" tailscale &&
     word_list_has "$combined_pkgsel" syncthing; then
    pass "tailscale plus ssh render keeps the explicit OpenSSH addon while also staging Tailscale and Syncthing"
  else
    fail "tailscale plus ssh render keeps the explicit OpenSSH addon while also staging Tailscale and Syncthing" "$combined_answers"
  fi
else
  fail "tailscale plus ssh render keeps the explicit OpenSSH addon while also staging Tailscale and Syncthing" "$combined_err"
fi

tailscale_pref="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apt/preferences.d/server/tailscale.pref"
if grep -q '^Pin: origin pkgs\.tailscale\.com$' "$tailscale_pref" &&
   grep -q '^Pin-Priority: 100$' "$tailscale_pref" &&
   grep -q '^Pin: release o=Tailscale,n=trixie,l=Tailscale$' "$tailscale_pref" &&
   grep -q '^Pin-Priority: 900$' "$tailscale_pref" &&
   grep -q '^Pin: release n=forky$' "$tailscale_pref" &&
   grep -q '^Pin: release n=sid$' "$tailscale_pref" &&
   grep -q '^Pin-Priority: -1$' "$tailscale_pref"; then
  pass "tailscale server apt preferences prefer the upstream trixie build and block the forky and sid variants"
else
  fail "tailscale server apt preferences prefer the upstream trixie build and block the forky and sid variants" "$tailscale_pref"
fi

storage_hook="$ROOT_DIR/d-i/forky/hooks/shared/partman/finish.d/99-storage-layout.sh"
if grep -q '^layout_syncthing_home_enabled() {$' "$storage_hook" &&
   grep -q 'layout_class_selected addon/tailscale' "$storage_hook" &&
   grep -q 'home_subvolumes=.*@home_workspace' "$storage_hook" &&
   grep -q 'home_subvolumes="${home_subvolumes} @home_syncthing"' "$storage_hook" &&
   grep -q 'if layout_syncthing_home_enabled; then' "$storage_hook"; then
  pass "tailscale-only storage staging keeps the Syncthing home subvolume behind the tailscale addon gate"
else
  fail "tailscale-only storage staging keeps the Syncthing home subvolume behind the tailscale addon gate" "$storage_hook"
fi

security_script="$ROOT_DIR/d-i/forky/scripts/late/security.sh"
if grep -q 'nftables_tailscale_selected()' "$security_script" &&
   grep -q 'tailscale syncthing' "$security_script" &&
   grep -q 'TAILSCALE_RUN_SSH_SERVER=' "$security_script" &&
   grep -q 'NFTABLES_TAILSCALE_ALLOW_INTERFACES' "$security_script" &&
   grep -q 'NFTABLES_SYNCTHING_ALLOW_INTERFACES' "$security_script"; then
  pass "late security staging auto-merges the Tailscale and Syncthing overlays and renders Tailscale SSH placeholders"
else
  fail "late security staging auto-merges the Tailscale and Syncthing overlays and renders Tailscale SSH placeholders" "$security_script"
fi

tailscale_helper="$ROOT_DIR/d-i/forky/scripts/late/tailscale.sh"
if grep -q '^umask 077$' "$tailscale_helper" &&
   grep -q 'tailscale_authkey' "$tailscale_helper" &&
   grep -q 'tailscale_auth_key' "$tailscale_helper" &&
   grep -q '^tailscale_normalize_token() {$' "$tailscale_helper" &&
   grep -q '^tailscale_stage_target_asset() {$' "$tailscale_helper" &&
   grep -q '^tailscale_render_target_asset() {$' "$tailscale_helper" &&
   grep -q 'runtime_env_file=${INSTALLER_RUNTIME_ENV_FILE:-/tmp/install-env/runtime.env}' "$tailscale_helper" &&
   grep -q 'FILE_TAILSCALED_DEFAULT' "$tailscale_helper" &&
   grep -q 'FILE_TAILSCALE_MANAGED_DEFAULT' "$tailscale_helper" &&
   grep -q 'FILE_TAILSCALED_CLEANUP_HELPER' "$tailscale_helper" &&
   grep -q 'FILE_TAILSCALE_TUN_MODULES_LOAD' "$tailscale_helper" &&
   grep -q 'FILE_TAILSCALE_AUTH_KEY' "$tailscale_helper" &&
   grep -q 'FILE_TAILSCALE_COMPLETE' "$tailscale_helper" &&
   grep -q 'FILE_TAILSCALE_STATUS' "$tailscale_helper" &&
   grep -q 'FILE_TAILSCALE_LOG' "$tailscale_helper" &&
   grep -q 'FILE_MANAGED_SYNCTHING_SERVICE' "$tailscale_helper" &&
   grep -q 'write_shell_config_var TAILSCALE_DAEMON_WAIT_SECONDS "${TAILSCALE_DAEMON_WAIT_SECONDS:-60}"' "$tailscale_helper" &&
   ! grep -q 'TAILSCALE_RETRY_DELAY_SECONDS' "$tailscale_helper" &&
   ! grep -q 'TAILSCALE_UP_ATTEMPTS' "$tailscale_helper" &&
   ! grep -q 'TAILSCALE_STABLE_SECONDS' "$tailscale_helper" &&
   ! grep -q 'TAILSCALE_RESTART_DAEMON_ON_RETRY' "$tailscale_helper" &&
   grep -q 'write_shell_config_var PORT "${TAILSCALE_UDP_PORT:-41641}"' "$tailscale_helper" &&
   grep -q 'write_shell_config_var FLAGS "--tun=${tailscale_interface}"' "$tailscale_helper" &&
   grep -q '^tailscale_validate_iface_name() {$' "$tailscale_helper" &&
   grep -q 'tailscale_validate_iface_name TAILSCALE_INTERFACE "$tailscale_interface"' "$tailscale_helper" &&
   grep -Fq 'usr/local/libexec/tailscaled-cleanup-if-needed.tmpl' "$tailscale_helper" &&
   grep -q 'tailscale_authkey is required when addon/tailscale is selected for unattended provisioning' "$tailscale_helper" &&
   grep -Fq 'usr/local/libexec/tailscale-managed-up' "$tailscale_helper" &&
   grep -Fq 'usr/local/libexec/managed-syncthing-configure' "$tailscale_helper" &&
   grep -Fq 'etc/modules-load.d/50-tailscale.conf' "$tailscale_helper" &&
   grep -q '^chmod 0644 "\${target_root}\${FILE_TAILSCALE_MANAGED_DEFAULT}" 2>/dev/null || true$' "$tailscale_helper" &&
   grep -q '^chmod 0644 "\${target_root}\${FILE_MANAGED_SYNCTHING_DEFAULT}" 2>/dev/null || true$' "$tailscale_helper" &&
   grep -q 'write_shell_config_var TAILSCALE_RUN_SSH_SERVER "${TAILSCALE_RUN_SSH_SERVER:-true}"' "$tailscale_helper" &&
   grep -q 'write_shell_config_var SYNCTHING_USER "$ACCOUNT_USERNAME"' "$tailscale_helper" &&
   grep -q 'write_shell_config_var TAILSCALE_ADVERTISE_TAGS' "$tailscale_helper" &&
   grep -q 'write_shell_config_var TAILSCALE_ADVERTISE_ROUTES' "$tailscale_helper" &&
   grep -q 'write_shell_config_var TAILSCALE_AUTH_KEY_REQUIRED "${TAILSCALE_AUTH_KEY_REQUIRED:-true}"' "$tailscale_helper" &&
   ! grep -q 'TAILSCALE_SSH_PORT' "$tailscale_helper" &&
   grep -q '^tailscale_run_target_chroot() {$' "$tailscale_helper" &&
   grep -q '^  else$' "$tailscale_helper" &&
   grep -q '^    code=\$?$' "$tailscale_helper" &&
   grep -q '^tailscale_run_target_chroot "prepare managed syncthing state during install"' "$tailscale_helper" &&
   grep -q "^test -r /usr/local/libexec/managed-syncthing-configure$" "$tailscale_helper" &&
   grep -q '^/bin/sh /usr/local/libexec/managed-syncthing-configure --prepare$' "$tailscale_helper" &&
   ! grep -q '^runuser -u "\$account_user"' "$tailscale_helper" &&
   grep -Fq 'chmod "$mode" "$target_host_path"' "$tailscale_helper" &&
   [ "$(grep -Fc 'target_normalize_systemd_config_parent_modes "$target_path" "$target_root"' "$tailscale_helper")" -eq 2 ] &&
   grep -q '^tailscale_stage_target_unit tailscaled.service$' "$tailscale_helper" &&
   grep -q '^tailscale_stage_target_unit tailscale-managed-bootstrap.service$' "$tailscale_helper" &&
   grep -q '^tailscale_stage_target_unit managed-syncthing.service$' "$tailscale_helper" &&
   ! grep -q 'systemctl --root=' "$tailscale_helper"; then
  pass "tailscale late helper captures chroot failures correctly and stages the current libexec runtime assets and bounded bootstrap units"
else
  fail "tailscale late helper captures chroot failures correctly and stages the current libexec runtime assets and bounded bootstrap units" "$tailscale_helper"
fi

ssh_helper="$ROOT_DIR/d-i/forky/scripts/common/ssh.sh"
tailscale_managed_helper="$ROOT_DIR/d-i/forky/hooks/shared/target/usr/local/libexec/tailscale-managed-up"
tailscale_managed_unit="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/systemd/system/tailscale-managed-bootstrap.service"
if [ -x "$tailscale_managed_helper" ] &&
   grep -q '^umask 077$' "$tailscale_managed_helper" &&
   grep -q '^  tailscale_require_bool TAILSCALE_RUN_SSH_SERVER "\$TAILSCALE_RUN_SSH_SERVER"$' "$tailscale_managed_helper" &&
   grep -q '^tailscale_wait_for_daemon() {$' "$tailscale_managed_helper" &&
   ! grep -q 'tailscale_request_daemon_recovery' "$tailscale_managed_helper" &&
   ! grep -q 'secondboot.service' "$tailscale_managed_helper" &&
   grep -q '^ConditionPathExists=!/usr/local/lib/tailscale/complete$' "$tailscale_managed_unit" &&
   grep -q '^OnSuccess=secondboot.service$' "$tailscale_managed_unit" &&
   grep -q '^tailscale_is_joined() {$' "$tailscale_managed_helper" &&
   grep -q '^tailscale_normalize_token() {$' "$tailscale_managed_helper" &&
   grep -q '^tailscale_normalize_auth_key_file() {$' "$tailscale_managed_helper" &&
   grep -q 'staged tailscale auth key must be a regular non-symlink file' "$tailscale_managed_helper" &&
   grep -q 'running one bounded tailscale up; any later retry is scheduled by systemd' "$tailscale_managed_helper" &&
   ! grep -q 'systemctl .*tailscaled.service' "$tailscale_managed_helper" &&
   ! grep -q 'TAILSCALE_RETRY_DELAY_SECONDS' "$tailscale_managed_helper" &&
   ! grep -q 'TAILSCALE_UP_ATTEMPTS' "$tailscale_managed_helper" &&
   ! grep -q 'TAILSCALE_STABLE_SECONDS' "$tailscale_managed_helper" &&
   ! grep -q 'TAILSCALE_RESTART_DAEMON_ON_RETRY' "$tailscale_managed_helper" &&
   ! grep -Fq -- '--reset' "$tailscale_managed_helper" &&
   grep -q '^tailscale_append_diagnostics() {$' "$tailscale_managed_helper" &&
   grep -q '^    /usr/bin/tailscale version || true$' "$tailscale_managed_helper" &&
   grep -q '^      /usr/bin/timeout --signal=TERM --kill-after=5s 30s /usr/bin/tailscale netcheck || true$' "$tailscale_managed_helper" &&
   grep -q 'journalctl --unit=tailscaled.service --boot --lines=80 --no-pager' "$tailscale_managed_helper" &&
   grep -q '^chmod 0600 "\$TAILSCALE_LOG_FILE"$' "$tailscale_managed_helper" &&
   grep -q 'tailscale up did not establish a joined state' "$tailscale_managed_helper" &&
   grep -q '^tailscale_remove_auth_key() {$' "$tailscale_managed_helper" &&
   [ "$(grep -c '^    tailscale_remove_auth_key$' "$tailscale_managed_helper")" -eq 2 ] &&
   grep -q 'tailscale_write_status false daemon-unavailable' "$tailscale_managed_helper" &&
   grep -q 'tailscale is already joined; skipping bootstrap' "$tailscale_managed_helper" &&
   grep -F -q '  --ssh="$TAILSCALE_RUN_SSH_SERVER" \' "$tailscale_managed_helper" &&
   ! grep -q 'TAILSCALE_SSH_PORT' "$tailscale_managed_helper" &&
   ! grep -q 'TAILSCALE_SSH_PUB' "$ssh_helper"; then
  pass "tailscale bootstrap preserves retry state without recycling tailscaled and queues cleanup only after the oneshot succeeds"
else
  fail "tailscale bootstrap preserves retry state without recycling tailscaled and queues cleanup only after the oneshot succeeds" "$tailscale_managed_helper"
fi

syncthing_helper="$ROOT_DIR/d-i/forky/hooks/shared/target/usr/local/libexec/managed-syncthing-configure"
if [ -x "$syncthing_helper" ] &&
   grep -q 'globalAnnounceEnabled", "false"' "$syncthing_helper" &&
   grep -q 'localAnnounceEnabled", "false"' "$syncthing_helper" &&
   grep -q 'relaysEnabled", "false"' "$syncthing_helper" &&
   grep -q 'natEnabled", "false"' "$syncthing_helper" &&
   grep -q 'install -d -m 0700 "\$SYNCTHING_DATA_DIR"' "$syncthing_helper" &&
   grep -q 'install -d -m 0700 "\$(dirname \"\$SYNCTHING_STATE_DIR\")" "\$SYNCTHING_STATE_DIR"' "$syncthing_helper" &&
   grep -q 'tcp://0.0.0.0:' "$syncthing_helper"; then
  pass "syncthing config helper disables discovery and relay paths and forces the managed TCP listener"
else
  fail "syncthing config helper disables discovery and relay paths and forces the managed TCP listener" "$syncthing_helper"
fi

syncthing_overlay="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/nftables/services/syncthing.yml"
if grep -q '__INSTALLER_SYNCTHING_TCP_PORT__' "$syncthing_overlay" &&
   grep -q '__INSTALLER_NFTABLES_SYNCTHING_ALLOW_INTERFACES__' "$syncthing_overlay" &&
   ! grep -q 'syncthing_local_discovery' "$syncthing_overlay" &&
   ! grep -q 'syncthing_sync_quic' "$syncthing_overlay"; then
  pass "syncthing firewall overlay exposes only the managed TCP endpoint"
else
  fail "syncthing firewall overlay exposes only the managed TCP endpoint" "$syncthing_overlay"
fi

tailscale_overlay="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/nftables/services/tailscale.yml"
if grep -q '__INSTALLER_TAILSCALE_RUN_SSH_SERVER__' "$tailscale_overlay" &&
   grep -q '__INSTALLER_NFTABLES_TAILSCALE_ALLOW_INTERFACES__' "$tailscale_overlay" &&
   grep -q '^    tailscale_control_https:$' "$tailscale_overlay" &&
   grep -q '^    tailscale_stun:$' "$tailscale_overlay" &&
   grep -q '^    tailscale_direct:$' "$tailscale_overlay" &&
   grep -q '^      source_ports:$' "$tailscale_overlay" &&
   grep -q '^      - __INSTALLER_TAILSCALE_UDP_PORT__$' "$tailscale_overlay" &&
   grep -q '^\s*- 22$' "$tailscale_overlay"; then
  pass "tailscale firewall overlay carries SSH plus protocol-specific control, STUN, and direct-connect egress"
else
  fail "tailscale firewall overlay carries SSH plus protocol-specific control, STUN, and direct-connect egress" "$tailscale_overlay"
fi

bootstrap_unit="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/systemd/system/tailscale-managed-bootstrap.service"
tailscaled_override="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/systemd/system/tailscaled.service.d/override.conf"
tailscaled_cleanup_template="$ROOT_DIR/d-i/forky/hooks/shared/target/usr/local/libexec/tailscaled-cleanup-if-needed.tmpl"
tailscale_modules_load="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/modules-load.d/50-tailscale.conf"
syncthing_unit="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/systemd/system/managed-syncthing.service.tmpl"
if grep -q '^Wants=network-online.target nss-lookup.target time-sync.target tailscaled.service$' "$bootstrap_unit" &&
   grep -q '^After=network-online.target nss-lookup.target time-sync.target nftables.service tailscaled.service$' "$bootstrap_unit" &&
   grep -q '^ConditionFileIsExecutable=/usr/local/libexec/tailscale-managed-up$' "$bootstrap_unit" &&
   ! grep -q '^ConditionPathIsExecutable=' "$bootstrap_unit" &&
   grep -q '^ExecStart=/usr/local/libexec/tailscale-managed-up --if-auth-key-present$' "$bootstrap_unit" &&
   grep -q '^Restart=on-failure$' "$bootstrap_unit" &&
   grep -q '^StartLimitIntervalSec=8h$' "$bootstrap_unit" &&
   grep -q '^StartLimitBurst=8$' "$bootstrap_unit" &&
   grep -q '^RestartSec=15min$' "$bootstrap_unit" &&
   grep -q '^TimeoutStartSec=15min$' "$bootstrap_unit" &&
   grep -q '^TimeoutStopSec=30s$' "$bootstrap_unit" &&
   grep -Fq '# The wrapper performs an explicit AppArmor transition into usr.bin.tailscale.' "$bootstrap_unit" &&
   grep -q '^NoNewPrivileges=false$' "$bootstrap_unit" &&
   grep -q '^StandardOutput=journal+console$' "$bootstrap_unit" &&
   grep -q '^StandardError=journal+console$' "$bootstrap_unit" &&
   grep -q '^PermissionsStartOnly=true$' "$syncthing_unit" &&
   grep -q '^ExecStartPre=/usr/local/libexec/managed-syncthing-configure --prepare$' "$syncthing_unit" &&
   ! grep -q '^ExecStartPre=/bin/sh ' "$syncthing_unit" &&
   grep -q '^tun$' "$tailscale_modules_load" &&
   grep -q '^Wants=systemd-modules-load.service network-online.target nss-lookup.target time-sync.target$' "$tailscaled_override" &&
   grep -q '^After=systemd-modules-load.service NetworkManager.service network.target network-online.target nss-lookup.target time-sync.target$' "$tailscaled_override" &&
   ! grep -q '^Requires=nftables.service$' "$tailscaled_override" &&
   ! grep -q '^ExecStartPre=/usr/bin/sleep ' "$tailscaled_override" &&
   ! grep -q '^Environment=TS_FORCE_NOISE_443=' "$tailscaled_override" &&
   grep -q 'automatic port 80 Noise to HTTPS/443 fallback' "$tailscaled_override" &&
   grep -q '^Restart=on-failure$' "$tailscaled_override" &&
   grep -q '^RestartSec=5s$' "$tailscaled_override" &&
   grep -q '^TimeoutStopSec=30s$' "$tailscaled_override" &&
   grep -Fqx 'LogFilterPatterns=~^ipnext: work queue shutdown failed: execqueue shut down$' "$tailscaled_override" &&
   grep -Fxq 'ExecStartPre=/usr/local/libexec/tailscaled-cleanup-if-needed' "$tailscaled_override" &&
   grep -Fxq 'ExecStopPost=' "$tailscaled_override" &&
   ! grep -Fq 'ExecStopPost=/usr/sbin/tailscaled --cleanup' "$tailscaled_override" &&
   grep -Fxq "interface_name='__INSTALLER_TAILSCALE_INTERFACE__'" "$tailscaled_cleanup_template" &&
   grep -Fxq '[ -e "$interface_path" ] || exit 0' "$tailscaled_cleanup_template" &&
   grep -Fxq 'sleep_bin=${TAILSCALED_SLEEP_BIN:-/usr/bin/sleep}' "$tailscaled_cleanup_template" &&
   grep -Fxq 'while [ "$cleanup_recheck" -lt 5 ]; do' "$tailscaled_cleanup_template" &&
   grep -Fxq '  "$sleep_bin" 0.1' "$tailscaled_cleanup_template" &&
   grep -Fxq '  [ -e "$interface_path" ] || exit 0' "$tailscaled_cleanup_template" &&
   grep -Fq 'cleanup_output=$("$tailscaled_bin" --cleanup "--tun=${interface_name}" 2>&1)' "$tailscaled_cleanup_template" &&
   grep -Fq 'failed to look up link \"${interface_name}\": Link not found' "$tailscaled_cleanup_template" &&
   grep -Fq '[ ! -e "$interface_path" ] && exit 0' "$tailscaled_cleanup_template" &&
   grep -q '^NoNewPrivileges=true$' "$tailscaled_override" &&
   grep -q '^PrivateTmp=true$' "$tailscaled_override"; then
  pass "tailscale target units reset duplicate post-stop cleanup without losing newer bootstrap hardening"
else
  fail "tailscale target units reset duplicate post-stop cleanup without losing newer bootstrap hardening" "$bootstrap_unit"
fi

cleanup_rendered="$TMP_DIR/tailscaled-cleanup-if-needed"
cleanup_invalid="$TMP_DIR/tailscaled-cleanup-invalid"
cleanup_sysfs="$TMP_DIR/sys/class/net"
cleanup_mock="$TMP_DIR/tailscaled"
cleanup_sleep_mock="$TMP_DIR/sleep"
cleanup_log="$TMP_DIR/tailscaled-cleanup.log"
cleanup_sleep_log="$TMP_DIR/tailscaled-sleep.log"
cleanup_stdout="$TMP_DIR/tailscaled-cleanup.out"
cleanup_stderr="$TMP_DIR/tailscaled-cleanup.err"
mkdir -p "$cleanup_sysfs"
sed 's/__INSTALLER_TAILSCALE_INTERFACE__/tailscale0/g' \
  "$tailscaled_cleanup_template" >"$cleanup_rendered"
sed 's|__INSTALLER_TAILSCALE_INTERFACE__|bad/name|g' \
  "$tailscaled_cleanup_template" >"$cleanup_invalid"
cat >"$cleanup_mock" <<'EOF'
#!/bin/sh
set -eu
printf '%s\n' "$*" >>"${CLEANUP_LOG:?}"
case "${CLEANUP_MODE:-success}" in
  success)
    exit 0
    ;;
  missing-link-race)
    rm -rf -- "${CLEANUP_INTERFACE_PATH:?}"
    printf 'router: enumerating tailscale0 addresses for cleanup failed: failed to look up link "tailscale0": Link not found\n' >&2
    exit 1
    ;;
  missing-link-still-present)
    printf 'router: enumerating tailscale0 addresses for cleanup failed: failed to look up link "tailscale0": Link not found\n' >&2
    exit 1
    ;;
  unrelated-failure)
    rm -rf -- "${CLEANUP_INTERFACE_PATH:?}"
    printf '%s\n' 'router: firewall cleanup failed: permission denied' >&2
    exit 1
    ;;
  *)
    exit 64
    ;;
esac
EOF
cat >"$cleanup_sleep_mock" <<'EOF'
#!/bin/sh
set -eu
printf '%s\n' "$*" >>"${CLEANUP_SLEEP_LOG:?}"
sleep_count=$(wc -l <"$CLEANUP_SLEEP_LOG")
if [ -n "${CLEANUP_SLEEP_REMOVE_AFTER:-}" ] &&
   [ "$sleep_count" -eq "$CLEANUP_SLEEP_REMOVE_AFTER" ]; then
  rm -rf -- "${CLEANUP_INTERFACE_PATH:?}"
fi
EOF
chmod 0755 "$cleanup_rendered" "$cleanup_invalid" "$cleanup_mock" "$cleanup_sleep_mock"

cleanup_behavior_ok=true
TAILSCALED_SYS_CLASS_NET_ROOT="$cleanup_sysfs" \
TAILSCALED_CLEANUP_BIN="$cleanup_mock" \
TAILSCALED_SLEEP_BIN="$cleanup_sleep_mock" \
CLEANUP_LOG="$cleanup_log" \
CLEANUP_SLEEP_LOG="$cleanup_sleep_log" \
CLEANUP_INTERFACE_PATH="$cleanup_sysfs/tailscale0" \
  /bin/sh "$cleanup_rendered" >"$cleanup_stdout" 2>"$cleanup_stderr" ||
  cleanup_behavior_ok=false
[ ! -e "$cleanup_log" ] || cleanup_behavior_ok=false
[ ! -e "$cleanup_sleep_log" ] || cleanup_behavior_ok=false
[ ! -s "$cleanup_stdout" ] || cleanup_behavior_ok=false
[ ! -s "$cleanup_stderr" ] || cleanup_behavior_ok=false

mkdir -p "$cleanup_sysfs/tailscale0"
: >"$cleanup_log"
: >"$cleanup_sleep_log"
TAILSCALED_SYS_CLASS_NET_ROOT="$cleanup_sysfs" \
TAILSCALED_CLEANUP_BIN="$cleanup_mock" \
TAILSCALED_SLEEP_BIN="$cleanup_sleep_mock" \
CLEANUP_LOG="$cleanup_log" \
CLEANUP_SLEEP_LOG="$cleanup_sleep_log" \
CLEANUP_INTERFACE_PATH="$cleanup_sysfs/tailscale0" \
  /bin/sh "$cleanup_rendered" >"$cleanup_stdout" 2>"$cleanup_stderr" ||
  cleanup_behavior_ok=false
[ "$(cat "$cleanup_log" 2>/dev/null || true)" = '--cleanup --tun=tailscale0' ] ||
  cleanup_behavior_ok=false
[ "$(wc -l <"$cleanup_sleep_log")" -eq 5 ] || cleanup_behavior_ok=false
[ "$(sort -u "$cleanup_sleep_log")" = '0.1' ] || cleanup_behavior_ok=false
[ ! -s "$cleanup_stderr" ] || cleanup_behavior_ok=false

mkdir -p "$cleanup_sysfs/tailscale0"
: >"$cleanup_log"
: >"$cleanup_sleep_log"
CLEANUP_SLEEP_REMOVE_AFTER=2 \
TAILSCALED_SYS_CLASS_NET_ROOT="$cleanup_sysfs" \
TAILSCALED_CLEANUP_BIN="$cleanup_mock" \
TAILSCALED_SLEEP_BIN="$cleanup_sleep_mock" \
CLEANUP_LOG="$cleanup_log" \
CLEANUP_SLEEP_LOG="$cleanup_sleep_log" \
CLEANUP_INTERFACE_PATH="$cleanup_sysfs/tailscale0" \
  /bin/sh "$cleanup_rendered" >"$cleanup_stdout" 2>"$cleanup_stderr" ||
  cleanup_behavior_ok=false
[ ! -e "$cleanup_sysfs/tailscale0" ] || cleanup_behavior_ok=false
[ ! -s "$cleanup_log" ] || cleanup_behavior_ok=false
[ "$(wc -l <"$cleanup_sleep_log")" -eq 2 ] || cleanup_behavior_ok=false
[ ! -s "$cleanup_stderr" ] || cleanup_behavior_ok=false

mkdir -p "$cleanup_sysfs/tailscale0"
: >"$cleanup_log"
: >"$cleanup_sleep_log"
CLEANUP_MODE=missing-link-race \
TAILSCALED_SYS_CLASS_NET_ROOT="$cleanup_sysfs" \
TAILSCALED_CLEANUP_BIN="$cleanup_mock" \
TAILSCALED_SLEEP_BIN="$cleanup_sleep_mock" \
CLEANUP_LOG="$cleanup_log" \
CLEANUP_SLEEP_LOG="$cleanup_sleep_log" \
CLEANUP_INTERFACE_PATH="$cleanup_sysfs/tailscale0" \
  /bin/sh "$cleanup_rendered" >"$cleanup_stdout" 2>"$cleanup_stderr" ||
  cleanup_behavior_ok=false
[ ! -e "$cleanup_sysfs/tailscale0" ] || cleanup_behavior_ok=false
[ ! -s "$cleanup_stderr" ] || cleanup_behavior_ok=false

mkdir -p "$cleanup_sysfs/tailscale0"
if CLEANUP_MODE=missing-link-still-present \
   TAILSCALED_SYS_CLASS_NET_ROOT="$cleanup_sysfs" \
   TAILSCALED_CLEANUP_BIN="$cleanup_mock" \
   TAILSCALED_SLEEP_BIN="$cleanup_sleep_mock" \
   CLEANUP_LOG="$cleanup_log" \
   CLEANUP_SLEEP_LOG="$cleanup_sleep_log" \
   CLEANUP_INTERFACE_PATH="$cleanup_sysfs/tailscale0" \
     /bin/sh "$cleanup_rendered" >"$cleanup_stdout" 2>"$cleanup_stderr"
then
  cleanup_behavior_ok=false
fi
grep -Fq 'failed to look up link "tailscale0": Link not found' "$cleanup_stderr" ||
  cleanup_behavior_ok=false

rm -rf -- "$cleanup_sysfs/tailscale0"
mkdir -p "$cleanup_sysfs/tailscale0"
if CLEANUP_MODE=unrelated-failure \
   TAILSCALED_SYS_CLASS_NET_ROOT="$cleanup_sysfs" \
   TAILSCALED_CLEANUP_BIN="$cleanup_mock" \
   TAILSCALED_SLEEP_BIN="$cleanup_sleep_mock" \
   CLEANUP_LOG="$cleanup_log" \
   CLEANUP_SLEEP_LOG="$cleanup_sleep_log" \
   CLEANUP_INTERFACE_PATH="$cleanup_sysfs/tailscale0" \
     /bin/sh "$cleanup_rendered" >"$cleanup_stdout" 2>"$cleanup_stderr"
then
  cleanup_behavior_ok=false
fi
grep -Fq 'firewall cleanup failed: permission denied' "$cleanup_stderr" ||
  cleanup_behavior_ok=false

if TAILSCALED_SYS_CLASS_NET_ROOT="$cleanup_sysfs" \
   TAILSCALED_CLEANUP_BIN="$cleanup_mock" \
   TAILSCALED_SLEEP_BIN="$cleanup_sleep_mock" \
   CLEANUP_LOG="$cleanup_log" \
   CLEANUP_SLEEP_LOG="$cleanup_sleep_log" \
   CLEANUP_INTERFACE_PATH="$cleanup_sysfs/tailscale0" \
     /bin/sh "$cleanup_invalid" >/dev/null 2>&1; then
  cleanup_behavior_ok=false
fi

if [ "$cleanup_behavior_ok" = true ]; then
  pass "tailscaled cleanup accepts only a disappearing-link race and preserves every other failure"
else
  fail "tailscaled cleanup accepts only a disappearing-link race and preserves every other failure" "$tailscaled_cleanup_template"
fi

if [ "$TEST_INDEX" -ne "$TEST_COUNT" ]; then
  printf 'not ok - planned %s tests but executed %s\n' "$TEST_COUNT" "$TEST_INDEX"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

[ "$FAIL_COUNT" -eq 0 ]
