#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT HUP INT TERM

desktop_cfg="$ROOT_DIR/d-i/forky/classes/class-select/role/desktop.cfg"
components="$ROOT_DIR/d-i/forky/scripts/desktop/components.sh"
desktop_verify="$ROOT_DIR/d-i/forky/scripts/desktop/verify.sh"
security_script="$ROOT_DIR/d-i/forky/scripts/late/security.sh"
storage_script="$ROOT_DIR/d-i/forky/scripts/late/storage-maintenance.sh"
btrfs_script="$ROOT_DIR/d-i/forky/scripts/late/btrfs-family.sh"
shared_etc="$ROOT_DIR/d-i/forky/hooks/shared/target/etc"
role_target="$ROOT_DIR/d-i/forky/hooks/role/desktop/target"
easyprof_conf="$shared_etc/apparmor/easyprof.conf"
logprof_conf="$shared_etc/apparmor/logprof.conf"
journald_conf="$shared_etc/systemd/journald.conf.d/10-storage.conf"
auditd_standard_conf="$shared_etc/audit/standard/auditd.conf"
auditd_enhanced_conf="$shared_etc/audit/enhanced/auditd.conf"
audit_syslog_plugin="$shared_etc/audit/plugins.d/syslog.conf"
auditd_tmpfiles="$shared_etc/tmpfiles.d/75-auditd-storage.conf"
audit_syslog_tmpfiles="$shared_etc/tmpfiles.d/65-audit-syslog.conf"
rsyslog_conf="$shared_etc/rsyslog.conf"
rsyslog_dir="$shared_etc/rsyslog.d"
audit_route="$rsyslog_dir/15-audit.conf"
auth_route="$rsyslog_dir/20-auth.conf"
usb_route="$rsyslog_dir/25-usb.conf"
apparmor_route="$rsyslog_dir/30-apparmor.conf"
storage_route="$rsyslog_dir/35-storage.conf"
zram_route="$rsyslog_dir/36-zram.conf"
whisper_route="$rsyslog_dir/37-whisper.conf"
timeshift_route="$rsyslog_dir/38-timeshift-managed.conf"
scanner_route="$rsyslog_dir/39-security-scanners.conf"
nftables_route="$rsyslog_dir/40-nftables.conf"
adb_route="$rsyslog_dir/42-adb.conf"
discard_route="$rsyslog_dir/99-discard.conf"
logrotate_conf="$shared_etc/logrotate.conf"
logrotate_rsyslog="$shared_etc/logrotate.d/rsyslog"
logrotate_audit="$shared_etc/logrotate.d/audit"
logrotate_auth="$shared_etc/logrotate.d/auth"
logrotate_usb="$shared_etc/logrotate.d/usb"
logrotate_apparmor="$shared_etc/logrotate.d/apparmor"
logrotate_storage="$shared_etc/logrotate.d/storage"
logrotate_zram="$shared_etc/logrotate.d/zram"
logrotate_whisper="$shared_etc/logrotate.d/whisper"
logrotate_timeshift="$shared_etc/logrotate.d/timeshift-managed"
logrotate_nftables="$shared_etc/logrotate.d/nftables"
logrotate_notify="$shared_etc/logrotate.d/security-notify"
logrotate_scanners="$shared_etc/logrotate.d/security-scanners"
logrotate_fail2ban="$shared_etc/logrotate.d/fail2ban-managed"
logrotate_adb="$shared_etc/logrotate.d/adb"
logrotate_timer_override="$shared_etc/systemd/system/logrotate.timer.d/override.conf"
security_tmpfiles="$shared_etc/tmpfiles.d/60-security-logs.conf"
scanner_socket_helper="$ROOT_DIR/d-i/forky/hooks/shared/target/usr/local/libexec/rsyslog-managed-security-socket"
scanner_socket_dropin="$shared_etc/systemd/system/rsyslog.service.d/30-managed-security-scanner-socket.conf"
zram_tmpfiles="$shared_etc/tmpfiles.d/60-zram-writeback.conf"
timeshift_tmpfiles="$shared_etc/tmpfiles.d/61-timeshift-managed.conf"
zram_script="$ROOT_DIR/d-i/forky/scripts/late/zram-swap.sh"
health_notifier="$role_target/usr/local/bin/labwc-health-notify"
health_path="$role_target/etc/skel/.config/systemd/user/labwc-health-notify.path"
mako_config="$role_target/etc/skel/.config/mako/config"

TEST_COUNT=12
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

printf '1..%s\n' "$TEST_COUNT"

if grep -Eq '^d-i pkgsel/include string .*(^|[[:space:]])rsyslog([[:space:]]|$)' "$desktop_cfg" &&
   grep -Eq '^d-i pkgsel/include string .*(^|[[:space:]])logrotate([[:space:]]|$)' "$desktop_cfg"; then
  pass "desktop package selection installs rsyslog and logrotate"
else
  fail "desktop package selection installs rsyslog and logrotate"
fi

logprof_config_complete=true
python3 - "$logprof_conf" <<'PY' || logprof_config_complete=false
from configparser import ConfigParser
from pathlib import Path
import sys

config_path = Path(sys.argv[1])
config = ConfigParser(interpolation=None, strict=True)
with config_path.open(encoding="utf-8") as handle:
    config.read_file(handle)

required_sections = {
    "settings",
    "qualifiers",
    "required_hats",
    "defaulthat",
    "globs",
}
if set(config.sections()) != required_sections:
    raise SystemExit(1)

settings = config["settings"]
expected_settings = {
    "profiledir": "/etc/apparmor.d /etc/subdomain.d",
    "inactive_profiledir": "/usr/share/apparmor/extra-profiles",
    "parser": "/usr/sbin/apparmor_parser /sbin/apparmor_parser /sbin/subdomain_parser",
    "logger": "/usr/bin/logger /bin/logger",
    "default_owner_prompt": "1",
    "custom_includes": "",
    "json_log": "0",
}
for key, expected in expected_settings.items():
    if settings.get(key) != expected:
        raise SystemExit(1)
PY
easyprof_native_ok=true
if [ -x /usr/bin/aa-easyprof ]; then
  /usr/bin/aa-easyprof \
    --config-file="$easyprof_conf" \
    --list-templates \
    >"$TMP_DIR/easyprof.templates" 2>&1 ||
    easyprof_native_ok=false
  /usr/bin/aa-easyprof \
    --config-file="$easyprof_conf" \
    --list-policy-groups \
    >"$TMP_DIR/easyprof.policy-groups" 2>&1 ||
    easyprof_native_ok=false
fi
if [ "$(grep -Ec '^(POLICYGROUPS_DIR|TEMPLATES_DIR)=' "$easyprof_conf")" -eq 2 ] &&
   grep -Fxq 'POLICYGROUPS_DIR="/usr/share/apparmor/easyprof/policygroups"' "$easyprof_conf" &&
   grep -Fxq 'TEMPLATES_DIR="/usr/share/apparmor/easyprof/templates"' "$easyprof_conf" &&
   [ "$easyprof_native_ok" = true ] &&
   [ "$logprof_config_complete" = true ] &&
   grep -q '^  logfiles = /var/log/managed/apparmor/apparmor.log ' "$logprof_conf" &&
   grep -q '^  /usr/bin/aa-easyprof      = u$' "$logprof_conf" &&
   grep -q '^  /usr/sbin/aa-complain     = u$' "$logprof_conf" &&
   grep -q '^  /usr/sbin/aa-decode       = u$' "$logprof_conf" &&
   grep -q '^  /usr/sbin/aa-enforce      = u$' "$logprof_conf" &&
   grep -q '^  /usr/sbin/aa-genprof      = u$' "$logprof_conf" &&
   grep -q '^  /usr/sbin/aa-logprof      = u$' "$logprof_conf" &&
   grep -q '^  /usr/bin/aa-notify        = u$' "$logprof_conf" &&
   grep -q '^  /usr/sbin/apparmor_parser = u$' "$logprof_conf" &&
   grep -Fq '  ^/usr/lib/modules/' "$logprof_conf"; then
  pass "AppArmor profiler configuration covers every supported section and package data path"
else
  fail "AppArmor profiler configuration covers every supported section and package data path"
fi

journald_config_complete=true
python3 - "$journald_conf" <<'PY' || journald_config_complete=false
from configparser import ConfigParser
from pathlib import Path
import sys

config_path = Path(sys.argv[1])
config = ConfigParser(interpolation=None, strict=True)
with config_path.open(encoding="utf-8") as handle:
    config.read_file(handle)

if config.sections() != ["Journal"]:
    raise SystemExit(1)

journal = config["Journal"]
expected = {
    "storage": "persistent",
    "compress": "yes",
    "seal": "yes",
    "splitmode": "uid",
    "syncintervalsec": "5m",
    "ratelimitintervalsec": "30s",
    "ratelimitburst": "10000",
    "systemmaxuse": "1G",
    "systemkeepfree": "256M",
    "systemmaxfilesize": "128M",
    "systemmaxfiles": "16",
    "runtimemaxuse": "128M",
    "runtimekeepfree": "64M",
    "runtimemaxfilesize": "16M",
    "runtimemaxfiles": "16",
    "maxretentionsec": "1month",
    "maxfilesec": "1week",
    "forwardtosyslog": "yes",
    "forwardtokmsg": "no",
    "forwardtoconsole": "no",
    "forwardtowall": "yes",
    "maxlevelstore": "debug",
    "maxlevelsyslog": "debug",
    "maxlevelkmsg": "notice",
    "maxlevelconsole": "info",
    "maxlevelwall": "emerg",
    "readkmsg": "no",
}
for key, value in expected.items():
    if journal.get(key) != value:
        raise SystemExit(1)
PY
if [ "$journald_config_complete" = true ] &&
   ! grep -Fxq 'ForwardToSyslog=no' "$journald_conf" &&
   ! grep -Fxq 'ReadKMsg=yes' "$journald_conf"; then
  pass "journald retains bounded service logs, forwards them to rsyslog, and excludes kernel nftables traffic"
else
  fail "journald retains bounded service logs, forwards them to rsyslog, and excludes kernel nftables traffic"
fi

managed_journal_units_ok=true
for managed_journal_unit in \
  "$shared_etc/systemd/system/crowdsec-firstboot.service" \
  "$shared_etc/systemd/system/firstboot.service" \
  "$shared_etc/systemd/system/managed-network.service" \
  "$shared_etc/systemd/system/tailscale-managed-bootstrap.service"
do
  if ! grep -Fxq 'StandardOutput=journal' "$managed_journal_unit" ||
     ! grep -Fxq 'StandardError=journal' "$managed_journal_unit" ||
     grep -Fq 'journal+console' "$managed_journal_unit"; then
    managed_journal_units_ok=false
    break
  fi
done

# shellcheck disable=SC2016
if grep -Fxq 'module(load="imuxsock")' "$rsyslog_conf" &&
   grep -Fxq 'module(load="imklog")' "$rsyslog_conf" &&
   grep -Fxq '$FileGroup adm' "$rsyslog_conf" &&
   grep -Fxq '$DirGroup adm' "$rsyslog_conf" &&
   grep -Fxq 'include(' "$rsyslog_conf" &&
   grep -Fxq '  file="/etc/rsyslog.d/*.conf"' "$rsyslog_conf" &&
   grep -Fxq '  mode="abort-if-missing"' "$rsyslog_conf" &&
   grep -Fq '*.*;auth,authpriv.none                 -/var/log/syslog' "$rsyslog_conf" &&
   grep -Fq 'daemon.*                               -/var/log/daemon.log' "$rsyslog_conf" &&
   grep -Fq 'kern.*                                 -/var/log/kern.log' "$rsyslog_conf" &&
   ! grep -Fq 'auth,authpriv.*' "$rsyslog_conf" &&
   ! grep -Eq '^[[:space:]]*module\(load="imudp"' "$rsyslog_conf" &&
   ! grep -Eq '^[[:space:]]*module\(load="imtcp"' "$rsyslog_conf" &&
   ! grep -Eq '^[[:space:]]*input\(type="imudp"' "$rsyslog_conf" &&
   ! grep -Eq '^[[:space:]]*input\(type="imtcp"' "$rsyslog_conf" &&
   ! grep -Fq ':omusrmsg:' "$rsyslog_conf" &&
   ! grep -Fq '[mcramer]' "$rsyslog_conf" &&
   [ "$managed_journal_units_ok" = true ]; then
  pass "managed services and rsyslog retain journal and file logs without console or terminal broadcast"
else
  fail "managed services and rsyslog retain journal and file logs without console or terminal broadcast"
fi

numbered_routes_ok=true
for route_name in \
  15-audit.conf \
  20-auth.conf \
  25-usb.conf \
  30-apparmor.conf \
  35-storage.conf \
  36-zram.conf \
  37-whisper.conf \
  38-timeshift-managed.conf \
  39-security-scanners.conf \
  40-nftables.conf \
  42-adb.conf \
  99-discard.conf
do
  [ -r "$rsyslog_dir/$route_name" ] || numbered_routes_ok=false
done
if [ "$numbered_routes_ok" = true ] &&
   [ ! -e "$rsyslog_dir/10-apparmor.conf" ] &&
   [ ! -e "$rsyslog_dir/20-nftables.conf" ]; then
  pass "rsyslog snippets use the required deterministic numbering"
else
  fail "rsyslog snippets use the required deterministic numbering"
fi

# shellcheck disable=SC2016
if grep -Fxq 'module(load="imfile" mode="polling" PollingInterval="1")' "$audit_route" &&
   grep -Fxq '  File="/var/log/audit/audit.log"' "$audit_route" &&
   grep -Fxq '  Tag="auditd-file:"' "$audit_route" &&
   grep -Fxq '  Facility="local0"' "$audit_route" &&
   grep -Fxq '  PersistStateInterval="100"' "$audit_route" &&
   grep -Fxq '  deleteStateOnFileDelete="on"' "$audit_route" &&
   grep -Fxq '  deleteStateOnFileMove="on"' "$audit_route" &&
   grep -Fq '$programname == "auditd-file"' "$audit_route" &&
   ! grep -Fq '$programname == "audit"' "$audit_route" &&
   ! grep -Fq '$programname == "auditd"' "$audit_route" &&
   ! grep -Fq '$syslogfacility-text == "kern"' "$audit_route" &&
   ! grep -Fq '$msg contains "audit:"' "$audit_route" &&
   ! grep -Fq '$msg contains "audit("' "$audit_route" &&
   grep -Fq 'file="/var/log/managed/audit/kernel-audit.log"' "$audit_route" &&
   grep -Fq '$syslogfacility-text == "authpriv"' "$auth_route" &&
   grep -Fq 'file="/var/log/managed/auth/auth.log"' "$auth_route" &&
   grep -Fq 'file="/var/lib/labwc-notifications/security/auth.signal"' "$auth_route" &&
   grep -Fq 'fileGroup="adm"' "$auth_route" &&
   grep -Fq 'dirGroup="logreader"' "$auth_route" &&
   grep -Fq 'fileCreateMode="0640"' "$auth_route" &&
   grep -Fq 'file="/var/log/managed/hardware/usb.log"' "$usb_route" &&
   grep -Fq 'file="/var/lib/labwc-notifications/security/usb.signal"' "$usb_route" &&
   grep -Fq '$msg contains "usbhid"' "$usb_route" &&
   grep -Fq '$msg contains "rndis_host"' "$usb_route" &&
   grep -Fq '$msg contains "type=1400"' "$apparmor_route" &&
   ! grep -Fq 'module(load="imfile"' "$apparmor_route" &&
   ! grep -Fq 'File="/pool/log/auditd/audit.log"' "$apparmor_route" &&
   grep -Fq 'file="/var/log/managed/apparmor/apparmor.log"' "$apparmor_route" &&
   grep -Fq 'file="/var/lib/labwc-notifications/security/apparmor.signal"' "$apparmor_route" &&
   grep -Fq '$msg contains '\''apparmor="DENIED"'\''' "$apparmor_route" &&
   grep -Fq '$msg contains "I/O error"' "$storage_route" &&
   grep -Fq '$msg contains "metadata I/O error"' "$storage_route" &&
   grep -Fq '$msg contains "critical medium error"' "$storage_route" &&
   grep -Fq '$msg contains "XFS (" or' "$storage_route" &&
   grep -Fq '$msg contains "corrupt" or' "$storage_route" &&
   grep -Fq 'file="/var/log/managed/storage/storage.log"' "$storage_route" &&
   grep -Fq 'file="/var/lib/labwc-notifications/security/storage.signal"' "$storage_route" &&
   grep -Fq '$programname == "zram-writeback"' "$zram_route" &&
   grep -Fq '$programname == "zram-device-setup"' "$zram_route" &&
   grep -Fq 'set $.managed_security_routed = "on";' "$zram_route" &&
   grep -Fq 'file="/var/log/managed/zram/zram.log"' "$zram_route" &&
   ! grep -Fq '/var/log/managed/zram/zram-writeback.log' "$zram_route" &&
   grep -Fq 'fileOwner="root"' "$zram_route" &&
   grep -Fq 'fileGroup="adm"' "$zram_route" &&
   grep -Fq 'fileCreateMode="0640"' "$zram_route" &&
   grep -Fq 'dirOwner="root"' "$zram_route" &&
   grep -Fq 'dirGroup="adm"' "$zram_route" &&
   grep -Fq 'dirCreateMode="0750"' "$zram_route" &&
   grep -Fq 'createDirs="on"' "$zram_route" &&
   grep -Fq '$programname == "timeshift-managed-snapshot" or' "$timeshift_route" &&
   grep -Fq '$programname == "grub-btrfs-refresh"' "$timeshift_route" &&
   grep -Fq 'set $.managed_security_routed = "on";' "$timeshift_route" &&
   grep -Fq 'file="/var/log/managed/timeshift/timeshift.log"' "$timeshift_route" &&
   grep -Fq 'fileOwner="root"' "$timeshift_route" &&
   grep -Fq 'fileGroup="adm"' "$timeshift_route" &&
   grep -Fq 'fileCreateMode="0640"' "$timeshift_route" &&
   grep -Fq 'dirOwner="root"' "$timeshift_route" &&
   grep -Fq 'dirGroup="adm"' "$timeshift_route" &&
   grep -Fq 'dirCreateMode="0750"' "$timeshift_route" &&
   grep -Fq 'createDirs="on"' "$timeshift_route" &&
   grep -Fq '$programname == "whisper-record-toggle"' "$whisper_route" &&
   grep -Fq '$programname == "systemd"' "$whisper_route" &&
   grep -Fq '$msg contains "whisper-record.service"' "$whisper_route" &&
   grep -Fq '$msg contains "whisper-transcribe.service"' "$whisper_route" &&
   grep -Fq '$msg contains "whisper-server.service"' "$whisper_route" &&
   grep -Fq '$msg contains "labwc-mute-default-microphone.service"' "$whisper_route" &&
   grep -Fq '$msg contains "whisper-local-transcription"' "$whisper_route" &&
   grep -Fq 'set $.managed_security_routed = "on";' "$whisper_route" &&
   grep -Fq 'file="/var/log/managed/whisper/whisper.log"' "$whisper_route" &&
   grep -Fq 'fileOwner="root"' "$whisper_route" &&
   grep -Fq 'fileGroup="adm"' "$whisper_route" &&
   grep -Fq 'fileCreateMode="0640"' "$whisper_route" &&
   grep -Fq 'dirOwner="root"' "$whisper_route" &&
   grep -Fq 'dirGroup="adm"' "$whisper_route" &&
   grep -Fq 'dirCreateMode="0750"' "$whisper_route" &&
   grep -Fq 'createDirs="on"' "$whisper_route" &&
   grep -Fq '  type="imuxsock"' "$scanner_route" &&
   grep -Fq 'ruleset(name="managed_security_scanner_input") {' "$scanner_route" &&
   grep -Fq '  Socket="/run/rsyslog/managed-security-scanners/scanner.sock"' "$scanner_route" &&
   grep -Fq '  CreatePath="off"' "$scanner_route" &&
   grep -Fq '  Ruleset="managed_security_scanner_input"' "$scanner_route" &&
   grep -Fq '  RateLimit.Interval="60"' "$scanner_route" &&
   grep -Fq '  RateLimit.Burst="4000"' "$scanner_route" &&
   grep -Fq '$programname == "managed-lynis-scan"' "$scanner_route" &&
   grep -Fq 'file="/var/log/managed/lynis/scan.log"' "$scanner_route" &&
   grep -Fq '$programname == "managed-rkhunter-scan"' "$scanner_route" &&
   grep -Fq 'file="/var/log/managed/rkhunter/scan.log"' "$scanner_route" &&
   grep -Fq '$programname == "managed-chkrootkit-scan"' "$scanner_route" &&
   grep -Fq 'file="/var/log/managed/chkrootkit/scan.log"' "$scanner_route" &&
   grep -Fq '$programname == "managed-debsecan-scan"' "$scanner_route" &&
   grep -Fq 'file="/var/log/managed/debsecan/scan.log"' "$scanner_route" &&
   grep -Fq '$programname == "managed-debsums-scan"' "$scanner_route" &&
   grep -Fq 'file="/var/log/managed/debsums/scan.log"' "$scanner_route" &&
   grep -Fq '$programname == "managed-spectre-meltdown-scan"' "$scanner_route" &&
   grep -Fq 'file="/var/log/managed/spectre-meltdown-checker/scan.log"' "$scanner_route" &&
   grep -Fq '$programname == "managed-fwupd-security-scan"' "$scanner_route" &&
   grep -Fq 'file="/var/log/managed/fwupd/security-scan.log"' "$scanner_route" &&
   grep -Fq '$programname == "managed-clamav-scan"' "$scanner_route" &&
   grep -Fq 'file="/var/log/managed/clamav/scan.log"' "$scanner_route" &&
   grep -Fq 'set $.managed_security_routed = "on";' "$scanner_route" &&
   grep -Fq '  stop' "$scanner_route" &&
   grep -Fq '$msg contains "nftables drop "' "$nftables_route" &&
   grep -Fq 'file="/var/log/managed/nftables/firewall.log"' "$nftables_route" &&
   grep -Fq 'file="/var/lib/labwc-notifications/security/firewall.signal"' "$nftables_route" &&
   grep -Fq '$programname == "labwc-adb"' "$adb_route" &&
   grep -Fq '$programname == "labwc-fuzzel-menu"' "$adb_route" &&
   grep -Fq '$programname == "labwc-fuzzel-action"' "$adb_route" &&
   grep -Fq '$msg contains "source=android-debug-bridge"' "$adb_route" &&
   grep -Fq '$programname == "systemd"' "$adb_route" &&
   grep -Fq '$msg contains "labwc-adb-server.service"' "$adb_route" &&
   grep -Fq 'set $.managed_security_routed = "on";' "$adb_route" &&
   grep -Fq 'file="/var/log/managed/adb/adb.log"' "$adb_route" &&
   grep -Fq 'fileOwner="root"' "$adb_route" &&
   grep -Fq 'fileGroup="adm"' "$adb_route" &&
   grep -Fq 'fileCreateMode="0640"' "$adb_route" &&
   grep -Fq 'dirOwner="root"' "$adb_route" &&
   grep -Fq 'dirGroup="adm"' "$adb_route" &&
   grep -Fq 'dirCreateMode="0750"' "$adb_route" &&
   grep -Fq 'createDirs="on"' "$adb_route" &&
   grep -Fq 'if ($.managed_security_routed == "on") then {' "$discard_route" &&
   grep -Fq '  stop' "$discard_route" &&
   ! grep -ERq 'file="/var/log/(audit|auth|hardware|apparmor|storage|whisper|nftables|adb)' "$rsyslog_dir"; then
  pass "numbered rules route authoritative auditd-file, auth, USB, AppArmor, storage, zram, Whisper, Timeshift, scanner, nftables, and ADB records before discard"
else
  fail "numbered rules route authoritative auditd-file, auth, USB, AppArmor, storage, zram, Whisper, Timeshift, scanner, nftables, and ADB records before discard"
fi

apparmor_logprof_template_ok=true
python3 - "$apparmor_route" <<'PY' || apparmor_logprof_template_ok=false
from pathlib import Path
import re
import sys

route = Path(sys.argv[1]).read_text(encoding="utf-8")
match = re.search(
    r'string="%msg:R,ERE,1,FIELD:(.*?)--end%\\n"',
    route,
)
if not match:
    raise SystemExit(1)

raw = (
    'node=LPL-262 type=AVC msg=audit(1785311798.990:4783): '
    'apparmor="ALLOWED" operation="mknod" class="file" '
    'profile="bitwarden" name="/home/user/.cache/app/sock" '
    'requested_mask="c" denied_mask="c"'
)
event_match = re.search(match.group(1), raw)
normalized = event_match.group(1) if event_match else raw
if not normalized.startswith("type=AVC msg=audit("):
    raise SystemExit(1)

try:
    import LibAppArmor
except ImportError:
    raise SystemExit(0)

event = LibAppArmor.parse_record(normalized)
try:
    if event.event != 3 or event.operation != "mknod" or event.profile != "bitwarden":
        raise SystemExit(1)
finally:
    LibAppArmor.free_record(event)
PY
if [ "$apparmor_logprof_template_ok" = true ] &&
   grep -Fq 'LibAppArmor rejects audit records that begin with auditd' "$apparmor_route"; then
  pass "managed AppArmor logs remove auditd node prefixes before aa-logprof parsing"
else
  fail "managed AppArmor logs remove auditd node prefixes before aa-logprof parsing"
fi

native_validation_ok=true
if [ -x /usr/sbin/rsyslogd ]; then
  rsyslog_test_group=$(id -gn)
  mkdir -p "$TMP_DIR/rsyslog.native.d"
  for route in "$rsyslog_dir"/*.conf; do
    sed \
      "s/fileGroup=\"adm\"/fileGroup=\"${rsyslog_test_group}\"/g
       s/dirGroup=\"adm\"/dirGroup=\"${rsyslog_test_group}\"/g
       s/fileGroup=\"logreader\"/fileGroup=\"${rsyslog_test_group}\"/g
       s/dirGroup=\"logreader\"/dirGroup=\"${rsyslog_test_group}\"/g" \
      "$route" >"$TMP_DIR/rsyslog.native.d/${route##*/}"
  done
  sed \
    -e "s|file=\"/etc/rsyslog.d/\\*.conf\"|file=\"${TMP_DIR}/rsyslog.native.d/*.conf\"|" \
    -e 's/^\$FileGroup adm$/\$FileGroup '"${rsyslog_test_group}"'/' \
    -e 's/^\$DirGroup adm$/\$DirGroup '"${rsyslog_test_group}"'/' \
    "$rsyslog_conf" >"$TMP_DIR/rsyslog.native.conf"
  /usr/sbin/rsyslogd \
    -N1 \
    -f "$TMP_DIR/rsyslog.native.conf" \
    >"$TMP_DIR/rsyslog.native.out" 2>&1 ||
    native_validation_ok=false
fi
if [ -x /usr/sbin/logrotate ]; then
  logrotate_test_user=$(id -un)
  logrotate_test_group=$(id -gn)
  mkdir -p "$TMP_DIR/logrotate.native.d"
  for policy in "$shared_etc"/logrotate.d/*; do
    sed \
      "s/^[[:space:]]*su root adm$/\tsu ${logrotate_test_user} ${logrotate_test_group}/
       s/^[[:space:]]*su root logreader$/\tsu ${logrotate_test_user} ${logrotate_test_group}/
       s/^[[:space:]]*create 0640 root logreader$/\tcreate 0640 ${logrotate_test_user} ${logrotate_test_group}/
       s|/var/log|${TMP_DIR}/var/log|g
       s|/var/lib/labwc-notifications|${TMP_DIR}/var/lib/labwc-notifications|g" \
      "$policy" >"$TMP_DIR/logrotate.native.d/${policy##*/}"
  done
  sed \
    "s|^include /etc/logrotate.d$|include ${TMP_DIR}/logrotate.native.d|" \
    "$logrotate_conf" >"$TMP_DIR/logrotate.native.conf"
  /usr/sbin/logrotate \
    --debug \
    --state "$TMP_DIR/logrotate.native.state" \
    "$TMP_DIR/logrotate.native.conf" \
    >"$TMP_DIR/logrotate.native.out" 2>&1 ||
    native_validation_ok=false
fi
if [ -x /usr/bin/systemd-analyze ]; then
  mkdir -p "$TMP_DIR/journald-root/etc/systemd/journald.conf.d"
  printf '[Journal]\n' >"$TMP_DIR/journald-root/etc/systemd/journald.conf"
  cp "$journald_conf" \
    "$TMP_DIR/journald-root/etc/systemd/journald.conf.d/10-storage.conf"
  chmod 0755 \
    "$TMP_DIR" \
    "$TMP_DIR/journald-root" \
    "$TMP_DIR/journald-root/etc" \
    "$TMP_DIR/journald-root/etc/systemd" \
    "$TMP_DIR/journald-root/etc/systemd/journald.conf.d"
  chmod 0644 \
    "$TMP_DIR/journald-root/etc/systemd/journald.conf" \
    "$TMP_DIR/journald-root/etc/systemd/journald.conf.d/10-storage.conf"
  if /usr/bin/systemd-analyze \
    --root="$TMP_DIR/journald-root" \
    cat-config \
    systemd/journald.conf \
    >"$TMP_DIR/journald.native.out" 2>&1; then
    grep -Fxq 'ReadKMsg=no' "$TMP_DIR/journald.native.out" ||
      native_validation_ok=false
  elif grep -Fq 'Permission denied' "$TMP_DIR/journald.native.out"; then
    printf '%s\n' \
      '# systemd-analyze cannot inspect alternate roots in this test runtime; static journald validation remains active'
  else
    native_validation_ok=false
  fi
  /usr/bin/systemd-analyze \
    calendar \
    '*-*-* *:00/15:00' \
    >"$TMP_DIR/logrotate-timer.native.out" 2>&1 ||
    native_validation_ok=false
fi
if [ "$native_validation_ok" = true ]; then
  pass "installed native readers accept the journald, rsyslog, and logrotate policy when available"
else
  cat \
    "$TMP_DIR/journald.native.out" \
    "$TMP_DIR/logrotate-timer.native.out" \
    "$TMP_DIR/rsyslog.native.out" \
    "$TMP_DIR/logrotate.native.out" 2>/dev/null || true
  fail "installed native readers accept the journald, rsyslog, and logrotate policy when available"
fi

logrotate_ok=true
grep -Fxq 'daily' "$logrotate_conf" || logrotate_ok=false
grep -Fxq 'rotate 4' "$logrotate_conf" || logrotate_ok=false
grep -Fxq 'maxage 7' "$logrotate_conf" || logrotate_ok=false
grep -Fxq 'dateext' "$logrotate_conf" || logrotate_ok=false
grep -Fxq 'dateformat -%Y%m%d-%H%M%S' "$logrotate_conf" || logrotate_ok=false
grep -Fxq 'compress' "$logrotate_conf" || logrotate_ok=false
grep -Fxq 'delaycompress' "$logrotate_conf" || logrotate_ok=false
grep -Fxq 'include /etc/logrotate.d' "$logrotate_conf" || logrotate_ok=false
for policy_spec in \
  "$logrotate_rsyslog:8M" \
  "$logrotate_audit:16M" \
  "$logrotate_auth:8M" \
  "$logrotate_usb:4M" \
  "$logrotate_apparmor:150M" \
  "$logrotate_storage:8M" \
  "$logrotate_zram:8M" \
  "$logrotate_whisper:4M" \
  "$logrotate_timeshift:8M" \
  "$logrotate_scanners:20M" \
  "$logrotate_nftables:8M" \
  "$logrotate_adb:4M"
do
  policy=${policy_spec%:*}
  maximum_size=${policy_spec##*:}
  grep -Eq '^[[:space:]]*daily$' "$policy" || logrotate_ok=false
  grep -Eq '^[[:space:]]*rotate 4$' "$policy" || logrotate_ok=false
  grep -Eq '^[[:space:]]*maxage 7$' "$policy" || logrotate_ok=false
  grep -Eq "^[[:space:]]*maxsize ${maximum_size}$" "$policy" || logrotate_ok=false
  grep -Eq '^[[:space:]]*compress$' "$policy" || logrotate_ok=false
  grep -Eq '^[[:space:]]*delaycompress$' "$policy" || logrotate_ok=false
  grep -Eq '^[[:space:]]*create 0640 root adm$' "$policy" || logrotate_ok=false
  grep -Eq '^[[:space:]]*su root adm$' "$policy" || logrotate_ok=false
  grep -Fq '/usr/lib/rsyslog/rsyslog-rotate' "$policy" || logrotate_ok=false
done
python3 - \
  "$logrotate_rsyslog" \
  "$logrotate_audit" \
  "$logrotate_auth" \
  "$logrotate_usb" \
  "$logrotate_apparmor" \
  "$logrotate_storage" \
  "$logrotate_zram" \
  "$logrotate_whisper" \
  "$logrotate_timeshift" \
  "$logrotate_scanners" \
  "$logrotate_fail2ban" \
  "$logrotate_nftables" \
  "$logrotate_adb" \
  "$logrotate_notify" <<'PY' || logrotate_ok=false
from pathlib import Path
import re
import sys

SIZE_MULTIPLIERS = {
    "K": 1024,
    "M": 1024 * 1024,
    "G": 1024 * 1024 * 1024,
}
MAX_MANAGED_BYTES = 2600 * 1024 * 1024

total = 0
for raw_path in sys.argv[1:]:
    path = Path(raw_path)
    lines = path.read_text(encoding="utf-8").splitlines()
    log_count = 0
    rotate = None
    maxsize = None
    in_paths = True
    for raw_line in lines:
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if line == "{":
            in_paths = False
            continue
        if in_paths:
            log_count += 1
            continue
        match = re.fullmatch(r"rotate\s+(\d+)", line)
        if match:
            rotate = int(match.group(1))
            continue
        match = re.fullmatch(r"maxsize\s+(\d+)([KMG])", line)
        if match:
            maxsize = int(match.group(1)) * SIZE_MULTIPLIERS[match.group(2)]

    if not log_count or rotate is None or maxsize is None:
        raise SystemExit(f"incomplete bounded rotation policy: {path}")
    total += log_count * (rotate + 1) * maxsize

if total > MAX_MANAGED_BYTES:
    raise SystemExit(
        f"managed active-plus-archive ceiling is {total} bytes, "
        f"above {MAX_MANAGED_BYTES} bytes"
    )
PY
if [ "$logrotate_ok" = true ] &&
   grep -Fxq '/var/log/managed/audit/kernel-audit.log' "$logrotate_audit" &&
   grep -Fxq '/var/log/managed/auth/auth.log' "$logrotate_auth" &&
   grep -Fxq '/var/log/managed/hardware/usb.log' "$logrotate_usb" &&
   grep -Fxq '/var/log/managed/apparmor/apparmor.log' "$logrotate_apparmor" &&
   grep -Fxq '/var/log/managed/storage/storage.log' "$logrotate_storage" &&
   grep -Fxq '/var/log/managed/zram/zram.log' "$logrotate_zram" &&
   ! grep -Fq '/var/log/managed/zram/zram-writeback.log' "$logrotate_zram" &&
   grep -Fxq '/var/log/managed/whisper/whisper.log' "$logrotate_whisper" &&
   grep -Fxq '/var/log/managed/timeshift/timeshift.log' "$logrotate_timeshift" &&
   grep -Fxq '/var/log/managed/lynis/scan.log' "$logrotate_scanners" &&
   grep -Fxq '/var/log/managed/lynis/lynis.log' "$logrotate_scanners" &&
   grep -Fxq '/var/log/managed/lynis/lynis-report.dat' "$logrotate_scanners" &&
   grep -Fxq '/var/log/managed/rkhunter/scan.log' "$logrotate_scanners" &&
   grep -Fxq '/var/log/managed/rkhunter/rkhunter.log' "$logrotate_scanners" &&
   grep -Fxq '/var/log/managed/chkrootkit/scan.log' "$logrotate_scanners" &&
   grep -Fxq '/var/log/managed/debsecan/scan.log' "$logrotate_scanners" &&
   grep -Fxq '/var/log/managed/debsums/scan.log' "$logrotate_scanners" &&
   grep -Fxq '/var/log/managed/spectre-meltdown-checker/scan.log' "$logrotate_scanners" &&
   grep -Fxq '/var/log/managed/fwupd/security-scan.log' "$logrotate_scanners" &&
   grep -Fxq '/var/log/managed/clamav/scan.log' "$logrotate_scanners" &&
   grep -Fxq '/var/log/managed/fail2ban/fail2ban.log' "$logrotate_fail2ban" &&
   grep -Eq '^[[:space:]]*maxsize 20M$' "$logrotate_fail2ban" &&
   grep -Eq '^[[:space:]]*create 0640 root adm$' "$logrotate_fail2ban" &&
   grep -Eq '^[[:space:]]*su root adm$' "$logrotate_fail2ban" &&
   grep -Fq '/usr/bin/fail2ban-client flushlogs' "$logrotate_fail2ban" &&
   grep -Fxq '/var/log/managed/nftables/firewall.log' "$logrotate_nftables" &&
   grep -Fxq '/var/log/managed/adb/adb.log' "$logrotate_adb" &&
   ! grep -Fq '/var/log/managed/auth/auth.log' "$logrotate_rsyslog" &&
   grep -Eq '^[[:space:]]*daily$' "$logrotate_notify" &&
   grep -Eq '^[[:space:]]*rotate 2$' "$logrotate_notify" &&
   grep -Eq '^[[:space:]]*maxage 2$' "$logrotate_notify" &&
   grep -Eq '^[[:space:]]*maxsize 128K$' "$logrotate_notify" &&
   grep -Eq '^[[:space:]]*compress$' "$logrotate_notify" &&
   grep -Eq '^[[:space:]]*delaycompress$' "$logrotate_notify" &&
   grep -Eq '^[[:space:]]*create 0640 root logreader$' "$logrotate_notify" &&
   grep -Eq '^[[:space:]]*su root logreader$' "$logrotate_notify" &&
   grep -Fxq '/var/lib/labwc-notifications/security/auth.signal' "$logrotate_notify" &&
   grep -Fxq '/var/lib/labwc-notifications/security/usb.signal' "$logrotate_notify" &&
   grep -Fxq '/var/lib/labwc-notifications/security/storage.signal' "$logrotate_notify" &&
   grep -Fxq '/var/lib/labwc-notifications/security/apparmor.signal' "$logrotate_notify" &&
   grep -Fxq '/var/lib/labwc-notifications/security/firewall.signal' "$logrotate_notify" &&
   grep -Fxq 'OnCalendar=' "$logrotate_timer_override" &&
   grep -Fxq 'OnCalendar=*-*-* *:00/15:00' "$logrotate_timer_override" &&
   grep -Fxq 'AccuracySec=1m' "$logrotate_timer_override" &&
   grep -Fxq 'RandomizedDelaySec=2m' "$logrotate_timer_override" &&
   grep -Fxq 'Persistent=true' "$logrotate_timer_override"; then
  pass "logrotate applies frequent size-bounded rotation, timestamp-safe archives, compression, and finite retention"
else
  fail "logrotate applies frequent size-bounded rotation, timestamp-safe archives, compression, and finite retention"
fi

audit_config_complete=true
python3 - \
  "$auditd_standard_conf" \
  "$auditd_enhanced_conf" \
  "$audit_syslog_plugin" <<'PY' || audit_config_complete=false
from pathlib import Path
import sys


def read_assignments(path):
    values = {}
    for line_number, raw_line in enumerate(Path(path).read_text(encoding="utf-8").splitlines(), 1):
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            raise SystemExit(f"{path}:{line_number}: invalid assignment")
        key, value = (part.strip() for part in line.split("=", 1))
        if key in values:
            raise SystemExit(f"{path}:{line_number}: duplicate key: {key}")
        values[key] = value
    return values


common_auditd = {
    "local_events": "yes",
    "write_logs": "yes",
    "log_file": "/var/log/audit/audit.log",
    "log_group": "adm",
    "log_format": "ENRICHED",
    "flush": "INCREMENTAL_ASYNC",
    "priority_boost": "4",
    "name_format": "HOSTNAME",
    "distribute_network": "no",
    "max_log_file_action": "ROTATE",
    "space_left": "25%",
    "space_left_action": "SYSLOG",
    "admin_space_left": "10%",
    "admin_space_left_action": "SUSPEND",
    "disk_full_action": "SUSPEND",
    "disk_error_action": "SUSPEND",
    "overflow_action": "SYSLOG",
    "max_restarts": "10",
    "plugin_dir": "/etc/audit/plugins.d",
    "end_of_event_timeout": "2",
}
profile_values = {
    "standard": {
        "freq": "50",
        "max_log_file": "8",
        "num_logs": "4",
        "q_depth": "4096",
    },
    "enhanced": {
        "freq": "100",
        "max_log_file": "16",
        "num_logs": "4",
        "q_depth": "8192",
    },
}
for profile, path in zip(("standard", "enhanced"), sys.argv[1:3]):
    values = read_assignments(path)
    expected = common_auditd | profile_values[profile]
    if values != expected:
        raise SystemExit(f"{path}: unexpected auditd configuration")

plugin_values = read_assignments(sys.argv[3])
if plugin_values != {
    "active": "no",
    "direction": "out",
    "path": "/usr/sbin/audisp-syslog",
    "type": "always",
    "args": "LOG_INFO LOG_LOCAL0",
    "format": "string",
}:
    raise SystemExit(f"{sys.argv[3]}: unexpected syslog plugin configuration")
PY

if [ "$audit_config_complete" = true ] &&
   grep -Fxq 'd /var/log/managed 0751 root adm -' "$audit_syslog_tmpfiles" &&
   grep -Fxq 'd /var/log/managed/audit 0750 root adm -' "$audit_syslog_tmpfiles" &&
   grep -Fxq 'f /var/log/managed/audit/kernel-audit.log 0640 root adm -' "$audit_syslog_tmpfiles" &&
   grep -Fxq 'd /var/log/managed/auth 0750 root adm -' "$security_tmpfiles" &&
   grep -Fxq 'f /var/log/managed/auth/auth.log 0640 root adm -' "$security_tmpfiles" &&
   grep -Fxq 'L /var/log/auth.log - - - - /var/log/managed/auth/auth.log' "$security_tmpfiles" &&
   grep -Fxq 'd /var/log/managed/hardware 0750 root adm -' "$security_tmpfiles" &&
   grep -Fxq 'f /var/log/managed/hardware/usb.log 0640 root adm -' "$security_tmpfiles" &&
   grep -Fxq 'd /var/log/managed/apparmor 0750 root adm -' "$security_tmpfiles" &&
   grep -Fxq 'f /var/log/managed/apparmor/apparmor.log 0640 root adm -' "$security_tmpfiles" &&
   grep -Fxq 'd /var/log/managed/storage 0750 root adm -' "$security_tmpfiles" &&
   grep -Fxq 'f /var/log/managed/storage/storage.log 0640 root adm -' "$security_tmpfiles" &&
   grep -Fxq 'd /var/log/managed/nftables 0750 root adm -' "$security_tmpfiles" &&
   grep -Fxq 'f /var/log/managed/nftables/firewall.log 0640 root adm -' "$security_tmpfiles" &&
   grep -Fxq 'd /var/log/managed/whisper 0750 root adm -' "$security_tmpfiles" &&
   grep -Fxq 'f /var/log/managed/whisper/whisper.log 0640 root adm -' "$security_tmpfiles" &&
   grep -Fxq 'd /var/log/managed/adb 0750 root adm -' "$security_tmpfiles" &&
   grep -Fxq 'f /var/log/managed/adb/adb.log 0640 root adm -' "$security_tmpfiles" &&
   grep -Fxq 'd /var/log/managed/lynis 0750 root adm -' "$security_tmpfiles" &&
   grep -Fxq 'f /var/log/managed/lynis/scan.log 0640 root adm -' "$security_tmpfiles" &&
   grep -Fxq 'f /var/log/managed/lynis/lynis.log 0640 root adm -' "$security_tmpfiles" &&
   grep -Fxq 'f /var/log/managed/lynis/lynis-report.dat 0640 root adm -' "$security_tmpfiles" &&
   grep -Fxq 'd /var/log/managed/rkhunter 0750 root adm -' "$security_tmpfiles" &&
   grep -Fxq 'f /var/log/managed/rkhunter/scan.log 0640 root adm -' "$security_tmpfiles" &&
   grep -Fxq 'f /var/log/managed/rkhunter/rkhunter.log 0640 root adm -' "$security_tmpfiles" &&
   grep -Fxq 'f /var/log/managed/chkrootkit/scan.log 0640 root adm -' "$security_tmpfiles" &&
   grep -Fxq 'f /var/log/managed/debsecan/scan.log 0640 root adm -' "$security_tmpfiles" &&
   grep -Fxq 'f /var/log/managed/debsums/scan.log 0640 root adm -' "$security_tmpfiles" &&
   grep -Fxq 'f /var/log/managed/spectre-meltdown-checker/scan.log 0640 root adm -' "$security_tmpfiles" &&
   grep -Fxq 'f /var/log/managed/fwupd/security-scan.log 0640 root adm -' "$security_tmpfiles" &&
   grep -Fxq 'f /var/log/managed/clamav/scan.log 0640 root adm -' "$security_tmpfiles" &&
   grep -Fxq 'd /var/log/managed/timeshift 0750 root adm -' "$timeshift_tmpfiles" &&
   grep -Fxq 'f /var/log/managed/timeshift/timeshift.log 0640 root adm -' "$timeshift_tmpfiles" &&
   grep -Fxq 'd /var/lib/labwc-notifications/security 0750 root logreader -' "$security_tmpfiles" &&
   grep -Fxq 'f /var/lib/labwc-notifications/security/auth.signal 0640 root logreader -' "$security_tmpfiles" &&
   grep -Fxq 'f /var/lib/labwc-notifications/security/usb.signal 0640 root logreader -' "$security_tmpfiles" &&
   grep -Fxq 'f /var/lib/labwc-notifications/security/storage.signal 0640 root logreader -' "$security_tmpfiles" &&
   grep -Fxq 'f /var/lib/labwc-notifications/security/apparmor.signal 0640 root logreader -' "$security_tmpfiles" &&
   grep -Fxq 'f /var/lib/labwc-notifications/security/firewall.signal 0640 root logreader -' "$security_tmpfiles" &&
   grep -Fxq 'd /var/log/audit 0750 root adm -' "$auditd_tmpfiles" &&
   grep -Fxq 'f /var/log/audit/audit.log 0640 root adm -' "$auditd_tmpfiles" &&
   grep -Fxq 'log_file = /var/log/audit/audit.log' "$auditd_standard_conf" &&
   grep -Fxq 'log_file = /var/log/audit/audit.log' "$auditd_enhanced_conf" &&
   grep -Fxq 'log_group = adm' "$auditd_standard_conf" &&
   grep -Fxq 'log_group = adm' "$auditd_enhanced_conf" &&
   grep -Fxq 'log_format = ENRICHED' "$auditd_standard_conf" &&
   grep -Fxq 'log_format = ENRICHED' "$auditd_enhanced_conf" &&
   grep -Fxq 'space_left = 25%' "$auditd_standard_conf" &&
   grep -Fxq 'space_left = 25%' "$auditd_enhanced_conf" &&
   grep -Fxq 'admin_space_left = 10%' "$auditd_standard_conf" &&
   grep -Fxq 'admin_space_left = 10%' "$auditd_enhanced_conf" &&
   grep -Fxq 'active = no' "$audit_syslog_plugin" &&
   grep -Fxq 'path = /usr/sbin/audisp-syslog' "$audit_syslog_plugin" &&
   grep -Fxq 'args = LOG_INFO LOG_LOCAL0' "$audit_syslog_plugin" &&
   grep -Fxq 'format = string' "$audit_syslog_plugin" &&
   ! grep -q 'getent group logreader' "$security_script" &&
   grep -q 'signal_reader_group=logreader' "$components" &&
   grep -q 'scanner_writer_group=securitylogger' "$components" &&
   grep -q 'for access_group in "$signal_reader_group" "$scanner_writer_group"; do' "$components" &&
   grep -q 'usermod -a -G "$access_group" "$account_user"' "$components"; then
  pass "tmpfiles, auditd, and rsyslog pre-create protected audit, scanner, and desktop log pipelines"
else
  fail "tmpfiles, auditd, and rsyslog pre-create protected audit, scanner, and desktop log pipelines"
fi

notify_test_dir="$TMP_DIR/security-notify"
notify_log="$notify_test_dir/notify.log"
notify_mock="$notify_test_dir/notify-send"
security_signal_dir="$notify_test_dir/security"
timeshift_event_dir="$notify_test_dir/timeshift"
unattended_event_dir="$notify_test_dir/unattended-upgrades"
meminfo_file="$notify_test_dir/meminfo"
power_supply_dir="$notify_test_dir/power-supply"
reboot_required_file="$notify_test_dir/reboot-required"
mkdir -p \
  "$notify_test_dir/home" \
  "$notify_test_dir/state" \
  "$security_signal_dir" \
  "$timeshift_event_dir" \
  "$unattended_event_dir" \
  "$power_supply_dir/BAT0"
chmod 0755 "$security_signal_dir" "$timeshift_event_dir" "$unattended_event_dir"
cat >"$notify_mock" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"$NOTIFY_LOG"
EOF
chmod 0755 "$notify_mock"
printf 'auth\nauth\n' >"$security_signal_dir/auth.signal"
printf 'usb\n' >"$security_signal_dir/usb.signal"
printf 'storage\n' >"$security_signal_dir/storage.signal"
printf 'apparmor\n' >"$security_signal_dir/apparmor.signal"
printf 'firewall\n' >"$security_signal_dir/firewall.signal"
cat >"$meminfo_file" <<'EOF'
MemTotal:       1048576 kB
MemAvailable:     52428 kB
EOF
printf 'Battery\n' >"$power_supply_dir/BAT0/type"
printf '9\n' >"$power_supply_dir/BAT0/capacity"
printf 'Discharging\n' >"$power_supply_dir/BAT0/status"
: >"$reboot_required_file"
chmod 0640 "$security_signal_dir"/*.signal
current_test_uid=$(id -u)
for _ in 1 2; do
  NOTIFY_LOG="$notify_log" \
  NOTIFY_SEND="$notify_mock" \
  MAIL="$notify_test_dir/missing-mailbox" \
  HOME="$notify_test_dir/home" \
  XDG_STATE_HOME="$notify_test_dir/state" \
  TIMESHIFT_EVENT_DIR="$timeshift_event_dir" \
  TIMESHIFT_SEEN_DIR="$notify_test_dir/timeshift-seen" \
  TIMESHIFT_EVENT_OWNER_UID="$current_test_uid" \
  UNATTENDED_EVENT_DIR="$unattended_event_dir" \
  UNATTENDED_SEEN_DIR="$notify_test_dir/unattended-seen" \
  SECURITY_SIGNAL_DIR="$security_signal_dir" \
  SECURITY_SIGNAL_STATE_DIR="$notify_test_dir/security-state" \
  ROOT_EVENT_OWNER_UID="$current_test_uid" \
  MEMINFO_FILE="$meminfo_file" \
  POWER_SUPPLY_DIR="$power_supply_dir" \
  REBOOT_REQUIRED_FILE="$reboot_required_file" \
  DBUS_SESSION_BUS_ADDRESS="unix:path=$notify_test_dir/fake-bus" \
    /bin/sh "$health_notifier"
done
if grep -Fxq 'PathModified=/var/lib/labwc-notifications/security/auth.signal' "$health_path" &&
   grep -Fxq 'PathModified=/var/lib/labwc-notifications/security/usb.signal' "$health_path" &&
   grep -Fxq 'PathModified=/var/lib/labwc-notifications/security/storage.signal' "$health_path" &&
   grep -Fxq 'PathModified=/var/lib/labwc-notifications/security/apparmor.signal' "$health_path" &&
   grep -Fxq 'PathModified=/var/lib/labwc-notifications/security/firewall.signal' "$health_path" &&
   grep -q '^check_security_signals() {$' "$health_notifier" &&
   grep -q '^\[app-name="Desktop Security" category=system.security.auth\]$' "$mako_config" &&
   grep -q '^\[app-name="Desktop Security" category=device.added\]$' "$mako_config" &&
   grep -q '^\[app-name="Desktop Security" category=device.error\]$' "$mako_config" &&
   grep -q '^\[app-name="Desktop Security" category=system.security\]$' "$mako_config" &&
   grep -q '^\[app-name="Desktop Security" category=system.security.network\]$' "$mako_config" &&
   [ "$(grep -c 'Authentication activity detected' "$notify_log" || true)" -eq 1 ] &&
   [ "$(grep -c 'USB or hardware hotplug activity detected' "$notify_log" || true)" -eq 1 ] &&
   [ "$(grep -c 'Storage error detected' "$notify_log" || true)" -eq 1 ] &&
   [ "$(grep -c 'AppArmor policy denial detected' "$notify_log" || true)" -eq 1 ] &&
   [ "$(grep -c 'Firewall blocked network traffic' "$notify_log" || true)" -eq 1 ] &&
   [ "$(grep -c 'Critical memory pressure' "$notify_log" || true)" -eq 1 ] &&
   [ "$(grep -c 'Critical battery level' "$notify_log" || true)" -eq 1 ] &&
   [ "$(grep -c 'System restart required' "$notify_log" || true)" -eq 1 ] &&
   grep -q '2 new events were recorded. Review /var/log/managed/auth/auth.log.' "$notify_log"; then
  pass "Labwc consumes sanitized security signals and state-based health conditions once through Mako"
else
  fail "Labwc consumes sanitized security signals and state-based health conditions once through Mako"
fi

staging_ok=true
for route_name in \
  15-audit.conf \
  20-auth.conf \
  25-usb.conf \
  30-apparmor.conf \
  35-storage.conf \
  39-security-scanners.conf \
  40-nftables.conf \
  99-discard.conf
do
  grep -q "DIR_HOOKS_SHARED_TARGET etc/rsyslog.d/${route_name}" "$components" ||
    staging_ok=false
  grep -q "/etc/rsyslog.d/${route_name}" "$desktop_verify" ||
    staging_ok=false
done
for route_name in 37-whisper.conf 42-adb.conf; do
  grep -q "DIR_HOOKS_SHARED_TARGET etc/rsyslog.d/${route_name}" "$components" ||
    staging_ok=false
  grep -q "/etc/rsyslog.d/${route_name}" "$components" ||
    staging_ok=false
done
for policy_name in audit auth usb apparmor storage nftables security-notify security-scanners; do
  grep -q "DIR_HOOKS_SHARED_TARGET etc/logrotate.d/${policy_name}" "$components" ||
    staging_ok=false
  grep -q "/etc/logrotate.d/${policy_name}" "$desktop_verify" ||
    staging_ok=false
done
for policy_name in whisper adb; do
  grep -q "DIR_HOOKS_SHARED_TARGET etc/logrotate.d/${policy_name}" "$components" ||
    staging_ok=false
  grep -q "/etc/logrotate.d/${policy_name}" "$components" ||
    staging_ok=false
done
timeshift_logging_staging_ok=true
for timeshift_asset in \
  'etc/rsyslog.d/38-timeshift-managed.conf /etc/rsyslog.d/38-timeshift-managed.conf 0644' \
  'etc/logrotate.d/timeshift-managed /etc/logrotate.d/timeshift-managed 0644' \
  'etc/tmpfiles.d/61-timeshift-managed.conf /etc/tmpfiles.d/61-timeshift-managed.conf 0644'
do
  grep -Fq "btrfs_stage_shared_target_asset ${timeshift_asset}" "$btrfs_script" ||
    timeshift_logging_staging_ok=false
done
if [ "$staging_ok" = true ] &&
   [ "$timeshift_logging_staging_ok" = true ] &&
   grep -q '^desktop_stage_logging_policy() {$' "$components" &&
   grep -q 'DIR_HOOKS_SHARED_TARGET etc/rsyslog.conf' "$components" &&
   grep -q 'DIR_HOOKS_SHARED_TARGET etc/tmpfiles.d/60-security-logs.conf' "$components" &&
   grep -Fq 'whisper=/var/log/managed/whisper/whisper.log' "$components" &&
   grep -Fq 'adb=/var/log/managed/adb/adb.log' "$components" &&
   grep -q 'DIR_HOOKS_SHARED_TARGET etc/tmpfiles.d/65-audit-syslog.conf' "$components" &&
   grep -q 'DIR_HOOKS_SHARED_TARGET usr/local/libexec/rsyslog-managed-security-socket' "$components" &&
   grep -q 'DIR_HOOKS_SHARED_TARGET etc/systemd/system/rsyslog.service.d/30-managed-security-scanner-socket.conf' "$components" &&
   grep -Fxq 'ExecStartPre=/usr/bin/install -d -o root -g securitylogger -m 0750 /run/rsyslog/managed-security-scanners' "$scanner_socket_dropin" &&
   grep -Fxq 'ExecStartPost=/usr/local/libexec/rsyslog-managed-security-socket' "$scanner_socket_dropin" &&
   grep -Fxq 'socket_path=/run/rsyslog/managed-security-scanners/scanner.sock' "$scanner_socket_helper" &&
   grep -Fxq 'socket_group=securitylogger' "$scanner_socket_helper" &&
   grep -Fxq 'd /run/rsyslog/managed-security-scanners 0750 root securitylogger -' "$security_tmpfiles" &&
   [ -x "$scanner_socket_helper" ] &&
   grep -q 'etc/tmpfiles.d/60-zram-writeback.conf' "$zram_script" &&
   grep -q 'etc/rsyslog.d/36-zram.conf' "$zram_script" &&
   grep -q 'etc/logrotate.d/zram' "$zram_script" &&
   grep -q '^verify_target_zram_staging() {$' "$zram_script" &&
   grep -q '/usr/sbin/rsyslogd' "$zram_script" &&
   grep -q -- '-N1' "$zram_script" &&
   grep -q '/usr/sbin/logrotate' "$zram_script" &&
   grep -q -- '--debug' "$zram_script" &&
   grep -q '/etc/logrotate.conf' "$zram_script" &&
   grep -Fxq 'd /var/log/managed/zram 0750 root adm -' "$zram_tmpfiles" &&
   grep -Fxq 'f /var/log/managed/zram/zram.log 0640 root adm -' "$zram_tmpfiles" &&
   grep -q 'DIR_HOOKS_SHARED_TARGET etc/tmpfiles.d/65-audit-syslog.conf' "$security_script" &&
   grep -q 'DIR_HOOKS_SHARED_TARGET etc/rsyslog.d/15-audit.conf' "$security_script" &&
   grep -q 'DIR_HOOKS_SHARED_TARGET etc/rsyslog.d/99-discard.conf' "$security_script" &&
   grep -q 'DIR_HOOKS_SHARED_TARGET etc/logrotate.conf' "$security_script" &&
   grep -q 'DIR_HOOKS_SHARED_TARGET etc/logrotate.d/audit' "$security_script" &&
   grep -q 'DIR_HOOKS_SHARED_TARGET etc/systemd/system/logrotate.timer.d/override.conf' "$security_script" &&
   grep -q 'DIR_HOOKS_SHARED_TARGET etc/systemd/system/logrotate.timer.d/override.conf' "$components" &&
   grep -q 'DIR_HOOKS_SHARED_TARGET etc/systemd/journald.conf.d/10-storage.conf' "$storage_script" &&
   grep -q 'ForwardToSyslog=yes' "$storage_script" &&
   grep -q 'ReadKMsg=no' "$storage_script" &&
   grep -q 'validate managed rsyslog configuration' "$components" &&
   grep -q 'validate managed logrotate configuration' "$components" &&
   grep -q 'desktop_enable_unit_if_available rsyslog.service system' "$components" &&
   grep -q 'desktop_enable_unit_if_available logrotate.timer system' "$components" &&
   grep -q 'security_mask_target_systemd_unit_if_available systemd-journald-audit.socket system' "$security_script" &&
   grep -q 'desktop_mask_unit_if_available systemd-journald-audit.socket system' "$components" &&
   grep -q 'DIR_HOOKS_SHARED_TARGET etc/apparmor/easyprof.conf' "$security_script" &&
   grep -q 'DIR_HOOKS_SHARED_TARGET etc/apparmor/logprof.conf' "$security_script" &&
   grep -q '/etc/systemd/journald.conf.d/10-storage.conf' "$desktop_verify" &&
   grep -q '/etc/systemd/system/logrotate.timer.d/override.conf' "$desktop_verify" &&
   grep -q '/etc/systemd/system/rsyslog.service.d/30-managed-security-scanner-socket.conf' "$desktop_verify" &&
   grep -q '/usr/local/libexec/rsyslog-managed-security-socket' "$desktop_verify" &&
   grep -q '^  rsyslogd \\$' "$desktop_verify" &&
   grep -q '^  logrotate \\$' "$desktop_verify"; then
  pass "installer staging, target validation, enablement, and verification cover the full logging policy"
else
  fail "installer staging, target validation, enablement, and verification cover the full logging policy"
fi
