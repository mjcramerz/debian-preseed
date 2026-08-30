#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/fail2ban-security-smoke.XXXXXX")
trap 'rm -rf "$TMP_DIR"' EXIT HUP INT TERM

apt_cfg="$ROOT_DIR/d-i/forky/fragments/apt.cfg"
security_script="$ROOT_DIR/d-i/forky/scripts/late/security.sh"
fail2ban_local="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/fail2ban/fail2ban.local"
ssh_jail_template="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/fail2ban/jail.d/managed/10-sshd.local.tmpl"
nginx_jail="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/fail2ban/jail.d/managed/20-nginx-botsearch.local"
service_dropin="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/systemd/system/fail2ban.service.d/managed.conf"
tmpfiles_policy="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/tmpfiles.d/62-fail2ban-managed.conf"
logrotate_policy="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/logrotate.d/fail2ban-managed"

TEST_COUNT=9
TEST_INDEX=0

pass() {
  TEST_INDEX=$((TEST_INDEX + 1))
  printf 'ok %s - %s\n' "$TEST_INDEX" "$1"
}

fail() {
  TEST_INDEX=$((TEST_INDEX + 1))
  printf 'not ok %s - %s\n' "$TEST_INDEX" "$1"
  exit 1
}

word_list_has() {
  list=$1
  wanted=$2

  for word in $list; do
    [ "$word" = "$wanted" ] && return 0
  done
  return 1
}

printf '1..%s\n' "$TEST_COUNT"

pkgsel=$(sed -n 's/^d-i pkgsel\/include string //p' "$apt_cfg")
if word_list_has "$pkgsel" fail2ban &&
   word_list_has "$pkgsel" nftables; then
  pass "base package selection installs Fail2ban with nftables"
else
  fail "base package selection installs Fail2ban with nftables"
fi

if grep -Fxq 'logtarget = /var/log/managed/fail2ban/fail2ban.log' "$fail2ban_local" &&
   grep -Fxq 'dbfile = /var/lib/fail2ban/fail2ban.sqlite3' "$fail2ban_local" &&
   grep -Fxq 'dbpurgeage = 7d' "$fail2ban_local" &&
   grep -Fxq 'dbmaxmatches = 10' "$fail2ban_local" &&
   ! grep -Fq 'SYSTEMD-JOURNAL' "$fail2ban_local"; then
  pass "Fail2ban uses managed file logging and persistent bounded state"
else
  fail "Fail2ban uses managed file logging and persistent bounded state"
fi

if grep -Fxq 'maxretry = 10' "$ssh_jail_template" &&
   grep -Fxq 'findtime = 10m' "$ssh_jail_template" &&
   grep -Fxq 'bantime = 24h' "$ssh_jail_template" &&
   grep -Fxq 'backend = systemd' "$ssh_jail_template" &&
   grep -Fxq 'enabled = true' "$ssh_jail_template" &&
   grep -Fxq 'port = __INSTALLER_SSH_PORT__' "$ssh_jail_template" &&
   grep -Fxq 'banaction = nftables[type=multiport, table=fail2ban, blocktype=drop]' "$ssh_jail_template" &&
   grep -Fxq 'banaction_allports = nftables[type=allports, table=fail2ban, blocktype=drop]' "$ssh_jail_template" &&
   grep -Fxq 'chain = fail2ban_input' "$ssh_jail_template" &&
   ! grep -Eq '^(logpath|journalmatch)[[:space:]]*=' "$ssh_jail_template" &&
   ! grep -Fq 'crowdsec' "$ssh_jail_template"; then
  pass "SSH authentication failures use the systemd backend and an isolated Fail2ban nftables namespace"
else
  fail "SSH authentication failures use the systemd backend and an isolated Fail2ban nftables namespace"
fi

if grep -Fxq '[nginx-botsearch]' "$nginx_jail" &&
   grep -Fxq 'enabled = true' "$nginx_jail" &&
   grep -Fxq 'backend = auto' "$nginx_jail" &&
   grep -Fxq 'port = http,https' "$nginx_jail" &&
   grep -Fxq 'logpath = /var/log/nginx/error.log' "$nginx_jail" &&
   ! grep -Fq 'SSH_PORT' "$nginx_jail"; then
  pass "public Nginx installs receive an SSH-independent Fail2ban bot-search jail"
else
  fail "public Nginx installs receive an SSH-independent Fail2ban bot-search jail"
fi

if grep -Fxq 'After=nftables.service systemd-tmpfiles-setup.service' "$service_dropin" &&
   grep -Fxq 'PartOf=nftables.service' "$service_dropin" &&
   grep -Fxq 'ReloadPropagatedFrom=nftables.service' "$service_dropin" &&
   grep -Fxq 'ExecStartPre=/usr/bin/fail2ban-client -t' "$service_dropin" &&
   grep -Fxq 'ExecReload=/usr/bin/fail2ban-client reload --restart --all' "$service_dropin" &&
   grep -Fxq 'NoNewPrivileges=yes' "$service_dropin" &&
   ! grep -Eq '^ExecStart=' "$service_dropin"; then
  pass "Fail2ban validates before start and rebuilds bans after managed nftables reloads"
else
  fail "Fail2ban validates before start and rebuilds bans after managed nftables reloads"
fi

if grep -Fxq 'd /var/log/managed/fail2ban 0750 root adm -' "$tmpfiles_policy" &&
   grep -Fxq 'f /var/log/managed/fail2ban/fail2ban.log 0640 root adm -' "$tmpfiles_policy" &&
   grep -Fxq 'd /var/lib/fail2ban 0750 root root -' "$tmpfiles_policy" &&
   grep -Fxq '/var/log/managed/fail2ban/fail2ban.log' "$logrotate_policy" &&
   grep -Eq '^[[:space:]]*maxsize 20M$' "$logrotate_policy" &&
   grep -Eq '^[[:space:]]*create 0640 root adm$' "$logrotate_policy" &&
   grep -Fq '/usr/bin/fail2ban-client flushlogs' "$logrotate_policy"; then
  pass "Fail2ban managed logs and database state have protected creation and bounded rotation"
else
  fail "Fail2ban managed logs and database state have protected creation and bounded rotation"
fi

nftables_line=$(grep -n '^[[:space:]]*configure_target_nftables$' "$security_script" | tail -n 1 | cut -d: -f1)
fail2ban_line=$(grep -n '^[[:space:]]*configure_target_fail2ban$' "$security_script" | tail -n 1 | cut -d: -f1)
if grep -q '^configure_target_fail2ban() {$' "$security_script" &&
   grep -q 'etc/fail2ban/fail2ban.local' "$security_script" &&
   grep -q 'etc/fail2ban/jail.d/managed/10-sshd.local.tmpl' "$security_script" &&
   grep -q 'etc/fail2ban/jail.d/managed/20-nginx-botsearch.local' "$security_script" &&
   grep -q 'fail2ban_jail_placeholder_map' "$security_script" &&
   grep -q 'installer_selected_class_reference_is_selected service/web' "$security_script" &&
   grep -q '/usr/bin/systemd-tmpfiles' "$security_script" &&
   grep -q '/usr/bin/fail2ban-client' "$security_script" &&
   grep -q '/usr/sbin/logrotate' "$security_script" &&
   grep -q 'stage_target_systemd_unit_enabled fail2ban.service system' "$security_script" &&
   grep -q 'unstage_target_systemd_unit_enabled fail2ban.service system' "$security_script" &&
   [ -n "$nftables_line" ] &&
   [ -n "$fail2ban_line" ] &&
   [ "$nftables_line" -lt "$fail2ban_line" ]; then
  pass "late security staging renders, validates, and enables Fail2ban after nftables"
else
  fail "late security staging renders, validates, and enables Fail2ban after nftables"
fi

# shellcheck disable=SC2034,SC2329
# These callbacks are invoked indirectly by the sourced security helper.
valid_map=$(
  TEST_SSH_PORT=2222
  installer_fatal() {
    printf '%s\n' "$*" >&2
    exit 1
  }
  runtime_apply_ssh_from_cmdline() {
    SSH_PORT=$TEST_SSH_PORT
  }
  # shellcheck disable=SC1090
  . "$security_script"
  fail2ban_jail_placeholder_map
)
if [ "$valid_map" = 'SSH_PORT=2222' ] &&
   ! (
     TEST_SSH_PORT=70000
     # shellcheck disable=SC2329
     installer_fatal() {
       exit 1
     }
     # shellcheck disable=SC2329
     runtime_apply_ssh_from_cmdline() {
       SSH_PORT=$TEST_SSH_PORT
     }
     # shellcheck disable=SC1090
     . "$security_script"
     fail2ban_jail_placeholder_map
   ) 2>/dev/null; then
  pass "Fail2ban jail rendering accepts valid SSH ports and rejects out-of-range values"
else
  fail "Fail2ban jail rendering accepts valid SSH ports and rejects out-of-range values"
fi

# shellcheck disable=SC2034,SC2329
# These callbacks are invoked indirectly by configure_target_fail2ban.
render_fail2ban_case() {
  case_name=$1

  (
    installer_fatal() {
      printf '%s\n' "$*" >&2
      exit 1
    }
    installer_selected_class_reference_is_selected() {
      [ "$case_name" = web ] && [ "$1" = service/web ]
    }
    installer_repo_join_var() {
      printf '%s\n' "$2"
    }
    install() {
      :
    }
    stage_target_asset() {
      printf 'stage:%s\n' "$2"
    }
    render_target_asset_with_placeholder_map() {
      printf 'render:%s\n' "$2"
      "$4" >/dev/null
    }
    normalize_target_tmpfiles_directory_policy() {
      :
    }
    run_in_target() {
      :
    }
    stage_target_systemd_unit_enabled() {
      printf 'enable:%s\n' "$1"
    }
    unstage_target_systemd_unit_enabled() {
      printf 'disable:%s\n' "$1"
    }
    nftables_validate_port_value() {
      [ "$1" = SSH_PORT ] && [ "$2" = 2222 ]
    }
    runtime_apply_ssh_from_cmdline() {
      case "$case_name" in
        ssh)
          SSH_PORT=2222
          ;;
        *)
          installer_fatal "unexpected SSH port rendering for ${case_name}"
          ;;
      esac
    }

    # shellcheck disable=SC1090
    . "$security_script"
    case "$case_name" in
      ssh) SSH_SERVER_ENABLED=true ;;
      *) SSH_SERVER_ENABLED=false ;;
    esac
    configure_target_fail2ban
  )
}

no_jail_render=$(render_fail2ban_case none)
web_render=$(render_fail2ban_case web)
ssh_render=$(render_fail2ban_case ssh)
if ! printf '%s\n' "$no_jail_render" | grep -Fq 'render:/etc/fail2ban/jail.d/managed/10-sshd.local' &&
   ! printf '%s\n' "$no_jail_render" | grep -Fq 'stage:/etc/fail2ban/jail.d/managed/20-nginx-botsearch.local' &&
   printf '%s\n' "$no_jail_render" | grep -Fxq 'disable:fail2ban.service' &&
   ! printf '%s\n' "$web_render" | grep -Fq 'render:/etc/fail2ban/jail.d/managed/10-sshd.local' &&
   printf '%s\n' "$web_render" | grep -Fxq 'stage:/etc/fail2ban/jail.d/managed/20-nginx-botsearch.local' &&
   printf '%s\n' "$web_render" | grep -Fxq 'enable:fail2ban.service' &&
   printf '%s\n' "$ssh_render" | grep -Fxq 'render:/etc/fail2ban/jail.d/managed/10-sshd.local' &&
   ! printf '%s\n' "$ssh_render" | grep -Fq 'stage:/etc/fail2ban/jail.d/managed/20-nginx-botsearch.local' &&
   printf '%s\n' "$ssh_render" | grep -Fxq 'enable:fail2ban.service'; then
  pass "Fail2ban independently selects SSH and Nginx jails, and disables itself without a protected service"
else
  fail "Fail2ban independently selects SSH and Nginx jails, and disables itself without a protected service"
fi
