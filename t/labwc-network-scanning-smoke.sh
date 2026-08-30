#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/labwc-network-scanning.XXXXXX")
trap 'rm -rf "$TMP_DIR"' EXIT HUP INT TERM

TEST_COUNT=14
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

desktop_cfg="$ROOT_DIR/d-i/forky/classes/class-select/role/desktop.cfg"
labwc_rc="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/labwc/rc.xml.tmpl"
computer_management="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-computer-management"
network_menu="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-network-scan-menu"
network_action="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-network-scan-action"
network_root_template="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/libexec/labwc-network-scan-action-root.tmpl"
network_module_root="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/lib/perl5/site_perl/labwc-network-scan-action"
network_client_module="$network_module_root/LabwcNetworkScanAction/Client.pm"
network_root_module="$network_module_root/LabwcNetworkScanAction/Root.pm.tmpl"
network_validation_module="$network_module_root/LabwcNetworkScanAction/Validation.pm"
network_perl_smoke="$ROOT_DIR/t/labwc-network-scanning-perl-smoke.sh"
network_perl_log="$TMP_DIR/network-scanning-perl.log"
nmap_script_dir="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/share/nmap/scripts"
components="$ROOT_DIR/d-i/forky/scripts/desktop/components.sh"
desktop_late="$ROOT_DIR/d-i/forky/scripts/desktop/labwc.sh"
desktop_verify="$ROOT_DIR/d-i/forky/scripts/desktop/verify.sh"

printf '1..%s\n' "$TEST_COUNT"

packages_ok=true
for package in lua5.5 wireshark wireshark-common tshark tcpdump libcap2-bin; do
  grep -Eq "(^|[[:space:]])${package}([[:space:]]|$)" "$desktop_cfg" ||
    packages_ok=false
done
if [ "$packages_ok" = true ] &&
   grep -q '^wireshark-common wireshark-common/install-setuid boolean true$' "$desktop_cfg"; then
  pass "desktop package selection installs Lua 5.5, Wireshark, TShark, tcpdump, and capability tooling"
else
  fail "desktop package selection installs Lua 5.5, Wireshark, TShark, tcpdump, and capability tooling"
fi

if grep -q '^desktop_configure_packet_capture_access() {$' "$components" &&
   grep -q 'dpkg-reconfigure wireshark-common' "$components" &&
   grep -q "usermod -a -G wireshark \"\\\$account_user\"" "$components" &&
   grep -q 'unexpected automatically authorized wireshark group member' "$components" &&
   grep -Fq '[ $((dumpcap_mode_value & 0001)) -eq 0 ]' "$components" &&
   ! grep -Fq 'dumpcap_mode_value & 0007' "$components" &&
   ! grep -q 'desktop_configure_packet_capture_access' "$desktop_verify" &&
   grep -q 'dumpcap must use file capabilities instead of setuid root' "$components" &&
   grep -Eq 'cap_net_admin.*cap_net_raw|cap_net_raw.*cap_net_admin' "$components" &&
   grep -q '^  desktop_configure_packet_capture_access$' "$desktop_late"; then
  pass "late desktop configuration accepts mode 754, rejects outside execution, and enrolls only the primary account"
else
  fail "late desktop configuration accepts mode 754, rejects outside execution, and enrolls only the primary account"
fi

if ! grep -q '<keybind key="C-W-n">' "$labwc_rc" &&
   grep -q '" Network Management"' "$computer_management" &&
   grep -q '" Network Scanning"' "$computer_management" &&
   grep -q '" Connection Profiles"' "$computer_management" &&
   grep -q '" VPN Connections"' "$computer_management" &&
   grep -q '" WireGuard Connections"' "$computer_management" &&
   grep -q '" DNS Configuration"' "$computer_management" &&
   grep -q 'run_command labwc-network-scan-menu' "$computer_management" &&
   grep -q 'run_command labwc-network-control-menu' "$computer_management" &&
   grep -q "' Nmap'" "$network_menu" &&
   grep -q "' Wireshark'" "$network_menu" &&
   grep -q "' Dumpcap'" "$network_menu" &&
   grep -q "' Tcpdump'" "$network_menu" &&
   grep -q "' TShark'" "$network_menu"; then
  pass "Computer Management routes Network Management to every scanning category"
else
  fail "Computer Management routes Network Management to every scanning category"
fi

nmap_actions_ok=true
for label in \
  'Show Listening TCP/UDP Ports' \
  'Scan Localhost TCP Ports' \
  'Scan LAN TCP Ports' \
  'Scan Specific LAN IP' \
  'Scan Specific WAN IP' \
  'Discover Hosts' \
  'Inventory Your Network' \
  'Check Approved Services' \
  'Check TLS Settings' \
  'Check HTTP Security Headers' \
  'Run Compliance Checks' \
  'Check SSH Algorithms' \
  'Check SMB Security' \
  'Check DNS Service' \
  'Check Common Ports' \
  'Scan All TCP Ports (single host)'
do
  grep -Fq "'${label}'" "$network_menu" || nmap_actions_ok=false
done
if [ "$nmap_actions_ok" = true ]; then
  pass "Nmap launcher exposes inventory, approved-service, TLS, and compliance workflows"
else
  fail "Nmap launcher exposes inventory, approved-service, TLS, and compliance workflows"
fi

capture_actions_ok=true
for label in \
  'Launch Wireshark' \
  'Open Managed Capture' \
  'Capture General Traffic (60s)' \
  'Capture DNS Traffic (60s)' \
  'Capture DHCP Traffic (60s)' \
  'Capture TLS Traffic (60s)' \
  'Capture Discovery Traffic (60s)' \
  'Capture ICMP Traffic (60s)' \
  'Capture ARP Traffic (60s)' \
  'Capture TCP SYN Traffic (60s)' \
  'Print Traffic Summary (30s)' \
  'Show Live IP Endpoints (30s)' \
  'Show Live DNS Queries (30s)' \
  'Show Live TLS Server Names (30s)' \
  'Show TCP Retransmissions (30s)' \
  'Analyze Protocol Hierarchy' \
  'Analyze IP Conversations' \
  'Extract DNS Queries' \
  'Extract TLS Server Names' \
  'Show HTTP Error Responses'
do
  grep -Fq "'${label}'" "$network_menu" || capture_actions_ok=false
done
if [ "$capture_actions_ok" = true ]; then
  pass "Wireshark, Dumpcap, tcpdump, and TShark expose bounded capture and analysis actions"
else
  fail "Wireshark, Dumpcap, tcpdump, and TShark expose bounded capture and analysis actions"
fi

if grep -Fq "default => sub { '__INSTALLER_ACCOUNT_USERNAME__' }," "$network_root_module" &&
   grep -Fq '20-23:25:53:80:88' "$network_root_module" &&
   grep -Fq '1900:3478:4500:5060-5061:5353:5355:41641:51820' "$network_root_module" &&
   [ "$(grep -Fc "managed_approved_services.tcp=' . \$self->approved_tcp_ports() . ',managed_approved_services.udp=' . \$self->approved_udp_ports()" "$network_root_module")" -eq 2 ] &&
   grep -q 'string.match(value, "^(%d+)%-(%d+)$")' "$nmap_script_dir/managed-approved-services.nse" &&
   grep -q 'last_port - first_port <= 1024' "$nmap_script_dir/managed-approved-services.nse" &&
   grep -q 'managed_approved_services.tcp' "$nmap_script_dir/managed-approved-services.nse" &&
   grep -q 'managed_approved_services.udp' "$nmap_script_dir/managed-approved-services.nse" &&
   grep -q 'network capture privileges are restricted to the managed desktop account' "$network_root_module" &&
   grep -q '^sub public_target {$' "$network_validation_module" &&
   grep -q 'WAN scans accept one public IPv4 host, not a CIDR' "$network_validation_module" &&
   grep -Fq '$first == 192 && $second == 0 && ($third == 0 || $third == 2)' "$network_validation_module" &&
   grep -Fq '$first == 192 && $second == 88 && $third == 99' "$network_validation_module" &&
   grep -q 'authorized-wan-scan' "$network_validation_module" &&
   grep -q 'I am authorized to scan this WAN host' "$network_menu" &&
   grep -q '^run_specific_wan_scan() {$' "$network_menu" &&
   grep -q 'run_network_action show-listening-ports' "$network_menu" &&
   grep -q 'run_network_action nmap-full-tcp 127.0.0.1 private-scan' "$network_menu" &&
   grep -q '^choose_private_host() {$' "$network_menu" &&
   grep -q 'run_selected_nmap_action nmap-full-tcp host' "$network_menu" &&
   grep -q '^sub _notify {$' "$network_client_module" &&
   grep -Fq "'-a', 'Network Scanning'" "$network_client_module" &&
   grep -Fq "'-c', 'x-labwc.maintenance'" "$network_client_module" &&
   grep -q '^sub _run_bounded_nmap {$' "$network_root_module" &&
   grep -Fq "'--max-rate', \$rate" "$network_root_module" &&
   grep -Fq "\$self->_run_bounded_nmap(\$rate, '30m'" "$network_root_module" &&
   grep -q "if (\\\$action eq 'nmap-full-tcp')" "$network_root_module" &&
   grep -Fq "'--max-retries', '2'" "$network_root_module" &&
   grep -Fq "'--host-timeout', '12m'" "$network_root_module" &&
   grep -Fq "'--script-timeout', '3m'" "$network_root_module" &&
   grep -Fq "'-c', '20000', '-w', '-'" "$network_root_module" &&
   grep -Fq "'--preserve-status', '--signal=INT', '--kill-after=5s'" "$network_root_module"; then
  pass "privileged scans stay bounded and report terminal outcomes through Mako"
else
  fail "privileged scans stay bounded and report terminal outcomes through Mako"
fi

approved_port_count=$(
  sed -n \
    -e '/^has approved_tcp_ports => (/,/^);$/s/^[[:space:]]*'\''\(.*\)'\'';$/\1/p' \
    -e '/^has approved_udp_ports => (/,/^);$/s/^[[:space:]]*'\''\(.*\)'\'';$/\1/p' \
    "$network_root_module" |
    awk -F: '
      {
        for (field_index = 1; field_index <= NF; field_index++) {
          if ($field_index ~ /^[0-9]+-[0-9]+$/) {
            split($field_index, range, "-")
            count += range[2] - range[1] + 1
          } else if ($field_index ~ /^[0-9]+$/) {
            count++
          }
        }
      }
      END { print count + 0 }
    '
)
if [ "$approved_port_count" -ge 120 ]; then
  pass "approved-service policy expands to at least 120 common service ports"
else
  fail "approved-service policy expands to at least 120 common service ports"
fi

if grep -Fq "File::Spec->catdir(\$home, 'Captures', 'network-scanning')" "$network_validation_module" &&
   grep -q '^sub prepare_capture_root {$' "$network_validation_module" &&
   grep -q '^sub _require_capture_group {$' "$network_client_module" &&
   grep -q '^sub _run_wireshark_action {$' "$network_client_module" &&
   grep -Fq "\$self->command()->run(\$setsid, '-f', \$wireshark, '-r', \$capture_file)" "$network_client_module" &&
   grep -q 'managed capture directory symlinks are not allowed' "$network_validation_module" &&
   grep -q 'capture interface is unavailable to dumpcap' "$network_client_module" &&
   grep -Fq "'-a', 'duration:60', '-a', 'filesize:10240'" "$network_client_module" &&
   grep -Fq "'-a', 'duration:30', '-c', '5000'" "$network_client_module" &&
   grep -Fq 'run_to_new_file($output, $pkexec, $self->root_helper(), $action, $interface)' "$network_client_module" &&
   grep -q 'capture file symlinks are not allowed' "$network_validation_module" &&
   grep -q 'frontend_name in tshark wireshark' "$components" &&
   grep -q 'must not carry file capabilities' "$components"; then
  pass "Wireshark capture privileges stay isolated to dumpcap and private files"
else
  fail "Wireshark capture privileges stay isolated to dumpcap and private files"
fi

nse_count=$(find "$nmap_script_dir" -maxdepth 1 -type f -name '*.nse' | wc -l | tr -d '[:space:]')
nse_scripts_ok=true
for script_path in "$nmap_script_dir"/*.nse; do
  grep -q '^description = ' "$script_path" || nse_scripts_ok=false
  grep -q '^author = ' "$script_path" || nse_scripts_ok=false
  grep -q '^license = ' "$script_path" || nse_scripts_ok=false
  grep -q '^categories = ' "$script_path" || nse_scripts_ok=false
  grep -q '^portrule = ' "$script_path" || nse_scripts_ok=false
  grep -q '^action = ' "$script_path" || nse_scripts_ok=false
  grep -q 'stdnse.output_table()' "$script_path" || nse_scripts_ok=false
  if grep -q 'stdnse.format_output' "$script_path"; then
    nse_scripts_ok=false
  fi
  if grep -Eq 'os\\.execute|io\\.popen|require[[:space:]]+["'\'']unpwdb["'\'']|brute\\.' "$script_path"; then
    nse_scripts_ok=false
  fi
done
if [ "$nse_count" -eq 8 ] &&
   [ "$nse_scripts_ok" = true ] &&
   grep -q 'port.protocol == "tcp" or port.protocol == "udp"' "$nmap_script_dir/managed-approved-services.nse" &&
   grep -q 'shortport.ssl(host, port)' "$nmap_script_dir/managed-tls-service-policy.nse" &&
   grep -q 'INFO HSTS not evaluated on a cleartext HTTP service' "$nmap_script_dir/managed-http-security-headers.nse"; then
  pass "eight managed NSE scripts use protocol-aware safe compliance checks"
else
  fail "eight managed NSE scripts use protocol-aware safe compliance checks"
fi

if grep -q 'desktop_stage_role_asset usr/local/bin/labwc-network-scan-menu /usr/local/bin/labwc-network-scan-menu 0755' "$components" &&
   grep -q 'desktop_stage_role_asset usr/local/bin/labwc-network-scan-action /usr/local/bin/labwc-network-scan-action 0755' "$components" &&
   grep -q 'usr/local/libexec/labwc-network-scan-action-root.tmpl' "$components" &&
   grep -q '^desktop_managed_nmap_script_files() {$' "$components" &&
   [ "$(grep -c '^managed-.*\.nse$' "$components")" -eq 8 ] &&
   grep -q '^desktop_stage_managed_nmap_scripts() {$' "$components" &&
   grep -q '^  desktop_stage_managed_nmap_scripts$' "$components" &&
   ! grep -q 'desktop_stage_role_asset_tree usr/local/share/nmap/scripts' "$components" &&
   grep -q '/usr/local/bin/labwc-network-scan-menu' "$desktop_verify" &&
   grep -q '/usr/local/libexec/labwc-network-scan-action-root' "$desktop_verify" &&
   grep -q '/usr/local/share/nmap/scripts/managed-approved-services.nse' "$desktop_verify"; then
  pass "desktop staging and verification cover the full network scanning boundary"
else
  fail "desktop staging and verification cover the full network scanning boundary"
fi

network_perl_ok=false
if /bin/sh "$network_perl_smoke" >"$network_perl_log" 2>&1; then
  network_perl_ok=true
fi

bin_dir="$TMP_DIR/bin"
responses="$TMP_DIR/responses"
fuzzel_log="$TMP_DIR/fuzzel.log"
action_log="$TMP_DIR/action.log"
mkdir -p "$bin_dir"
cat >"$responses" <<'EOF'
 Nmap
Check Approved Services
Private or loopback target
192.168.50.0/24
Check TLS Settings
Authorized WAN IPv4 host
I am authorized to scan this WAN host
8.8.8.8
← Back
 Wireshark
Launch Wireshark
← Back
 Dumpcap
Capture DNS Traffic (60s)
eth0
← Back
EOF
cat >"$bin_dir/id" <<'EOF'
#!/bin/sh
[ "${1:-}" = -u ] && { printf '%s\n' 1000; exit 0; }
exec /usr/bin/id "$@"
EOF
cat >"$bin_dir/dumpcap" <<'EOF'
#!/bin/sh
if [ "${1:-}" = -D ]; then
  printf '%s\n' '1. eth0'
fi
EOF
cat >"$bin_dir/ip" <<'EOF'
#!/bin/sh
case "${1:-}" in
  -o)
    printf '%s\n' '192.168.50.0/24 dev eth0 proto kernel scope link src 192.168.50.10'
    ;;
esac
EOF
cat >"$bin_dir/labwc-fuzzel" <<'EOF'
#!/bin/sh
set -eu
cat >>"${FUZZEL_LOG:?}"
response=$(sed -n '1p' "${FUZZEL_RESPONSES:?}")
sed '1d' "$FUZZEL_RESPONSES" >"${FUZZEL_RESPONSES}.next"
mv "${FUZZEL_RESPONSES}.next" "$FUZZEL_RESPONSES"
printf '%s\n' "$response"
EOF
cat >"$bin_dir/labwc-network-scan-action" <<'EOF'
#!/bin/sh
set -eu
printf '%s\n' "$*" >>"${NETWORK_ACTION_LOG:?}"
EOF
chmod 0755 "$bin_dir"/*

if PATH="$bin_dir:/usr/bin:/bin" \
   HOME="$TMP_DIR/home" \
   FUZZEL_LOG="$fuzzel_log" \
   FUZZEL_RESPONSES="$responses" \
   NETWORK_ACTION_LOG="$action_log" \
   /bin/sh "$network_menu" &&
   [ "$(cat "$action_log")" = "nmap-approved-services 192.168.50.0/24 private-scan
nmap-tls-settings 8.8.8.8 authorized-wan-scan
wireshark-launch
dumpcap-capture-dns eth0" ] &&
   grep -q ' Nmap' "$fuzzel_log" &&
   grep -q ' Wireshark' "$fuzzel_log" &&
   grep -q ' Dumpcap' "$fuzzel_log" &&
   grep -q ' Tcpdump' "$fuzzel_log" &&
   grep -q ' TShark' "$fuzzel_log"; then
  pass "nested Fuzzel network choices dispatch validated action identifiers"
else
  fail "nested Fuzzel network choices dispatch validated action identifiers"
fi

if [ "$network_perl_ok" = true ] &&
   grep -Fq 'ok 6 - network scan client launches Wireshark unprivileged with fixed managed-capture argv' "$network_perl_log"; then
  pass "Wireshark launches unprivileged and only opens managed capture files"
else
  cat "$network_perl_log" >&2
  fail "Wireshark launches unprivileged and only opens managed capture files"
fi

if [ "$network_perl_ok" = true ] &&
   grep -Fq 'ok 8 - network scan client preserves the non-root desktop and internal-mode GUI boundaries' "$network_perl_log"; then
  pass "network action internal mode rejects direct root execution"
else
  cat "$network_perl_log" >&2
  fail "network action internal mode rejects direct root execution"
fi

if /bin/sh -n "$network_menu" &&
   [ "$network_perl_ok" = true ] &&
   grep -Fq 'ok 2 - network scanning Perl entrypoints, modules, and rendered root module compile' "$network_perl_log"; then
  pass "network scanning shell launcher and rendered Perl helpers validate in their declared runtimes"
else
  cat "$network_perl_log" >&2
  fail "network scanning shell launcher and rendered Perl helpers validate in their declared runtimes"
fi
