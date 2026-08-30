#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/managed-network-smoke.XXXXXX")
NETWORK_SCRIPT="$ROOT_DIR/d-i/forky/scripts/late/network.sh"
NETWORKMANAGER_DROPIN="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/systemd/system/NetworkManager.service.d/20-managed-dispatcher.conf"
DISPATCHER_DROPIN="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/systemd/system/NetworkManager-dispatcher.service.d/20-managed-persistent.conf"
TEST_COUNT=12
TEST_INDEX=0
FAIL_COUNT=0
trap 'rm -rf "$TMP_DIR"' EXIT HUP INT TERM
PERL_STUB_ROOT="$TMP_DIR/perl-stubs"

mkdir -p "$PERL_STUB_ROOT/MooX" "$PERL_STUB_ROOT/Types"
cat >"$PERL_STUB_ROOT/MooX/Options.pm" <<'EOF'
package MooX::Options;

use strict;
use warnings;

sub import {
    my ($class) = @_;
    my $caller = caller;

    no strict 'refs';
    *{"${caller}::option"} = sub {
        my ($name, @arguments) = @_;
        @arguments % 2 == 0 or die "invalid option specification\n";
        my %specification = @arguments;
        delete $specification{doc};
        my $has = \&{"${caller}::has"};
        $has->($name, %specification);
        return;
    };
    *{"${caller}::new_with_options"} = sub {
        my ($package, @arguments) = @_;
        @arguments % 2 == 0 or die "invalid constructor arguments\n";
        my %constructor = @arguments;
        while (@ARGV) {
            my $argument = shift @ARGV;
            if ($argument eq '--help' || $argument eq '-h') {
                $constructor{help} = 1;
                next;
            }
            $argument !~ /\A-/
                or die "unknown option: $argument\n";
            unshift @ARGV, $argument;
            last;
        }
        return $package->new(%constructor);
    };
    return;
}

1;
EOF
cat >"$PERL_STUB_ROOT/MooX/StrictConstructor.pm" <<'EOF'
package MooX::StrictConstructor;

use strict;
use warnings;

sub import { return; }

1;
EOF
cat >"$PERL_STUB_ROOT/MooX/TypeTiny.pm" <<'EOF'
package MooX::TypeTiny;

use strict;
use warnings;

sub import { return; }

1;
EOF
cat >"$PERL_STUB_ROOT/Types/Standard.pm" <<'EOF'
package Types::Standard;

use strict;
use warnings;

sub import {
    my ($class, @symbols) = @_;
    my $caller = caller;

    no strict 'refs';
    for my $symbol (@symbols) {
        *{"${caller}::${symbol}"} = sub { return sub { 1 }; };
    }
    return;
}

1;
EOF

pass() {
  TEST_INDEX=$((TEST_INDEX + 1))
  printf 'ok %s - %s\n' "$TEST_INDEX" "$1"
}

fail() {
  TEST_INDEX=$((TEST_INDEX + 1))
  FAIL_COUNT=$((FAIL_COUNT + 1))
  printf 'not ok %s - %s\n' "$TEST_INDEX" "$1"
}

assert_contains() {
  needle=$1
  path=$2
  grep -Fq -- "$needle" "$path"
}

printf '1..%s\n' "$TEST_COUNT"

INPUT_ENV="$TMP_DIR/managed-network-input.env"
STATE_ENV="$TMP_DIR/managed-network-state.env"
TARGET_ROOT="$TMP_DIR/target"
SYS_CLASS_NET="$TMP_DIR/sys/class/net"
mkdir -p "$TARGET_ROOT" "$SYS_CLASS_NET"

installer_cmdline_value() {
  case "$1" in
    ip|netcfg/get_ipaddress) printf '%s\n' 192.0.2.82 ;;
    netmask|netcfg/get_netmask) printf '%s\n' 255.255.255.0 ;;
    gateway|netcfg/get_gateway) printf '%s\n' 192.0.2.1 ;;
    nameservers|netcfg/get_nameservers|dns) printf '%s\n' 192.0.2.53 ;;
    ipv6_address) printf '%s\n' 2001:9b1:29fd:4e00::82/64 ;;
    ipv6_gateway) printf '%s\n' 2001:9b1:29fd:4e00::1 ;;
    ipv6_nameservers) printf '%s\n' 2001:9b1:29fd:4e00::1 ;;
    *) return 1 ;;
  esac
}

installer_debconf_value() {
  return 1
}

installer_default_route_interface() {
  return 1
}

installer_global_ipv4_interface() {
  return 1
}

installer_fatal() {
  printf '%s\n' "$*" >&2
  return 1
}

installer_info() {
  :
}

write_shell_config_var() {
  key=$1
  value=$2
  printf "%s='%s'\n" "$key" "$value"
}

write_target_file() {
  path=$1
  mode=$2
  mkdir -p "$(dirname -- "$path")"
  umask 077
  cat >"$path"
  chmod "$mode" "$path"
}

SYSTEM_HOSTNAME=preseed-test
SYSTEM_DOMAIN=example.test
TMP_ENV_DIR="$TMP_DIR"
export SYSTEM_HOSTNAME SYSTEM_DOMAIN TMP_ENV_DIR

# shellcheck disable=SC1090
. "$NETWORK_SCRIPT"

NETWORKMANAGER_VENDOR_UNIT="$TMP_DIR/NetworkManager.service.vendor"
NETWORKMANAGER_RENDERED_UNIT="$TMP_DIR/NetworkManager.service.rendered"
NETWORKMANAGER_GENERATED_UNIT="$TMP_DIR/var-lib-systemd-NetworkManager.service"
NETWORKMANAGER_VARIANT_UNIT="$TMP_DIR/NetworkManager.service.variant"
NETWORKMANAGER_VARIANT_RENDERED_UNIT="$TMP_DIR/NetworkManager.service.variant.rendered"
NETWORKMANAGER_SPLIT_UNIT="$TMP_DIR/NetworkManager.service.split"
NETWORKMANAGER_SPLIT_RENDERED_UNIT="$TMP_DIR/NetworkManager.service.split.rendered"
NETWORKMANAGER_MALFORMED_UNIT="$TMP_DIR/NetworkManager.service.malformed"
cat >"$NETWORKMANAGER_VENDOR_UNIT" <<'EOF'
[Unit]
Description=Network Manager
Wants=network.target
After=network-pre.target dbus.service
Before=network.target networking.service

[Service]
Type=dbus
BusName=org.freedesktop.NetworkManager
ExecStart=/usr/sbin/NetworkManager --no-daemon
EOF

cat >"$NETWORKMANAGER_GENERATED_UNIT" <<'EOF'
[Unit]
Description=Network Manager
Wants=network.target
After=network-pre.target dbus.service
Before=network.target

[Service]
Type=dbus
BusName=org.freedesktop.NetworkManager
ExecStart=/usr/sbin/NetworkManager --no-daemon
EOF

cat >"$NETWORKMANAGER_VARIANT_UNIT" <<'EOF'
[Unit]
Description=Network Manager
Wants=network.target
After=network-pre.target dbus.service
Before=shutdown.target \
  networking.service network.target

[Service]
Type=dbus
BusName=org.freedesktop.NetworkManager
ExecStart=/usr/sbin/NetworkManager --no-daemon
EOF

cat >"$NETWORKMANAGER_SPLIT_UNIT" <<'EOF'
[Unit]
Description=Network Manager
Wants=network.target
After=network-pre.target dbus.service
Before=shutdown.target
Before=networking.service

[Service]
Type=dbus
BusName=org.freedesktop.NetworkManager
ExecStart=/usr/sbin/NetworkManager --no-daemon
EOF

cat >"$NETWORKMANAGER_MALFORMED_UNIT" <<'EOF'
[Unit]
Description=Network Manager
Before=network.target \
EOF

if render_target_networkmanager_unit_override \
  "$NETWORKMANAGER_GENERATED_UNIT" >"$TMP_DIR/generated-unit.unused"; then
  networkmanager_generated_status=0
else
  networkmanager_generated_status=$?
fi

if grep -Fq '[ -x /target/usr/libexec/nm-dispatcher ]' "$NETWORK_SCRIPT" &&
   grep -Fq 'write_target_file /etc/systemd/system/NetworkManager.service 0644' "$NETWORK_SCRIPT" &&
   grep -Fq 'stage_target_systemd_unit_alias_to_path' "$NETWORK_SCRIPT" &&
   grep -Fq 'dbus-org.freedesktop.nm-dispatcher.service' "$NETWORK_SCRIPT" &&
   grep -Fq 'NetworkManager.service.d/20-managed-dispatcher.conf' "$NETWORK_SCRIPT" &&
   grep -Fq 'NetworkManager-dispatcher.service.d/20-managed-persistent.conf' "$NETWORK_SCRIPT" &&
   grep -Fqx 'Wants=NetworkManager-dispatcher.service' "$NETWORKMANAGER_DROPIN" &&
   grep -Fqx 'After=NetworkManager-dispatcher.service networking.service wpa_supplicant.service' "$NETWORKMANAGER_DROPIN" &&
   ! grep -q '^Before=' "$NETWORKMANAGER_DROPIN" &&
   grep -Fqx 'Before=NetworkManager.service' "$DISPATCHER_DROPIN" &&
   grep -Fqx 'PartOf=NetworkManager.service' "$DISPATCHER_DROPIN" &&
   grep -Fqx 'ExecStart=' "$DISPATCHER_DROPIN" &&
   grep -Fqx 'ExecStart=/usr/libexec/nm-dispatcher --persist' "$DISPATCHER_DROPIN" &&
   render_target_networkmanager_unit_override \
     "$NETWORKMANAGER_VENDOR_UNIT" >"$NETWORKMANAGER_RENDERED_UNIT" &&
   grep -Fqx 'Before=network.target' "$NETWORKMANAGER_RENDERED_UNIT" &&
   ! grep -Fq 'Before=network.target networking.service' "$NETWORKMANAGER_RENDERED_UNIT" &&
   [ "$networkmanager_generated_status" -eq 3 ] &&
   render_target_networkmanager_unit_override \
     "$NETWORKMANAGER_VARIANT_UNIT" >"$NETWORKMANAGER_VARIANT_RENDERED_UNIT" &&
   grep -Fqx 'Before=shutdown.target network.target' "$NETWORKMANAGER_VARIANT_RENDERED_UNIT" &&
   ! grep -Fq 'networking.service' "$NETWORKMANAGER_VARIANT_RENDERED_UNIT" &&
   render_target_networkmanager_unit_override \
     "$NETWORKMANAGER_SPLIT_UNIT" >"$NETWORKMANAGER_SPLIT_RENDERED_UNIT" &&
   grep -Fqx 'Before=shutdown.target' "$NETWORKMANAGER_SPLIT_RENDERED_UNIT" &&
   ! grep -Fqx 'Before=' "$NETWORKMANAGER_SPLIT_RENDERED_UNIT" &&
   ! grep -Fq 'networking.service' "$NETWORKMANAGER_SPLIT_RENDERED_UNIT"; then
  pass "NetworkManager conditionally removes only a real ifupdown ordering conflict"
else
  fail "NetworkManager conditionally removes only a real ifupdown ordering conflict"
fi

if render_target_networkmanager_unit_override \
  "$NETWORKMANAGER_MALFORMED_UNIT" >"$TMP_DIR/malformed-unit.unused"; then
  networkmanager_malformed_status=0
else
  networkmanager_malformed_status=$?
fi
if [ "$networkmanager_malformed_status" -eq 42 ]; then
  pass "NetworkManager override rendering fails closed on an unterminated Before directive"
else
  fail "NetworkManager override rendering fails closed on an unterminated Before directive"
fi

installer_network_interface_for_handoff() {
  case "$1" in
    ethernet) printf '%s\n' enp1s0 ;;
    wifi) printf '%s\n' wlp2s0 ;;
    *) return 1 ;;
  esac
}

installer_interface_mac_address() {
  case "$1" in
    enp1s0) printf '%s\n' 02:00:00:00:00:82 ;;
    wlp2s0) printf '%s\n' 02:00:00:00:00:83 ;;
    *) return 1 ;;
  esac
}

target_managed_network_input_target_path() {
  printf '%s\n' "$INPUT_ENV"
}

target_managed_network_state_target_path() {
  printf '%s\n' "$STATE_ENV"
}

target_managed_network_state_env() {
  printf '%s\n' "$STATE_ENV"
}

target_static_network_selected() {
  return 0
}

if write_target_managed_network_input static "$(target_managed_network_link_types)" &&
   assert_contains "MANAGED_NETWORK_LINK_TYPES='ethernet'" "$INPUT_ENV" &&
   assert_contains "MANAGED_NETWORK_WIFI_IFACE='managed-wifi0'" "$INPUT_ENV" &&
   assert_contains "MANAGED_NETWORK_WIFI_MAC='02:00:00:00:00:83'" "$INPUT_ENV" &&
   assert_contains "MANAGED_NETWORK_IPV6_ADDRESS='2001:9b1:29fd:4e00::82/64'" "$INPUT_ENV" &&
   ! grep -q '^MANAGED_NETWORK_WIFI_ESSID=' "$INPUT_ENV"; then
  pass "late network handoff keeps Wi-Fi out of the static config when no Wi-Fi answers were supplied while preserving deterministic managed Wi-Fi metadata and IPv6 CIDR input"
else
  fail "late network handoff keeps Wi-Fi out of the static config when no Wi-Fi answers were supplied while preserving deterministic managed Wi-Fi metadata and IPv6 CIDR input"
fi

cat >>"$INPUT_ENV" <<EOF
MANAGED_NETWORK_TARGET_ROOT='$TARGET_ROOT'
MANAGED_NETWORK_SYS_CLASS_NET='$SYS_CLASS_NET'
MANAGED_NETWORK_STATE_ENV='$STATE_ENV'
MANAGED_NETWORK_LINK_TYPES='ethernet wifi'
MANAGED_NETWORK_WIFI_ESSID='TestNet'
MANAGED_NETWORK_WIFI_ESSID_AGAIN='TestNet'
MANAGED_NETWORK_WIFI_PSK_SECURITY='wpa'
MANAGED_NETWORK_WIFI_WPA='0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef'
EOF

create_fake_network_interface() {
  fake_iface=$1
  fake_mac=$2
  fake_link_type=$3

  mkdir -p "$SYS_CLASS_NET/$fake_iface/device"
  printf '%s\n' "$fake_mac" >"$SYS_CLASS_NET/$fake_iface/address"
  printf '%s\n' 1 >"$SYS_CLASS_NET/$fake_iface/type"
  printf '%s\n' 1 >"$SYS_CLASS_NET/$fake_iface/carrier"
  printf '%s\n' up >"$SYS_CLASS_NET/$fake_iface/operstate"
  if [ "$fake_link_type" = wifi ]; then
    mkdir -p "$SYS_CLASS_NET/$fake_iface/wireless"
  fi
}

while IFS=' ' read -r fake_iface fake_mac fake_link_type; do
  [ -n "$fake_iface" ] || continue
  create_fake_network_interface "$fake_iface" "$fake_mac" "$fake_link_type"
done <<'EOF'
enp1s0 02:00:00:00:00:82 ethernet
wlp2s0 02:00:00:00:00:83 wifi
EOF

while IFS=' ' read -r fake_iface fake_mac fake_link_type; do
  [ -n "$fake_iface" ] || continue
  create_fake_network_interface "$fake_iface" "$fake_mac" "$fake_link_type"
done <<'EOF'
managed-eth0 02:00:00:00:00:82 ethernet
managed-wifi0 02:00:00:00:00:83 wifi
EOF

GENERATOR="$ROOT_DIR/d-i/forky/scripts/late/managed-network-generate.pl"
HELPER="$ROOT_DIR/d-i/forky/hooks/shared/target/usr/local/libexec/managed-network-run"

run_managed_network() {
  PERL5LIB="$PERL_STUB_ROOT" /usr/bin/perl "$HELPER" "$@"
}

NO_WIFI_INPUT_ENV="$TMP_DIR/no-wifi-managed-network-input.env"
cp "$INPUT_ENV" "$NO_WIFI_INPUT_ENV"
sed -i \
  -e "/^MANAGED_NETWORK_WIFI_ESSID=/d" \
  -e "/^MANAGED_NETWORK_WIFI_ESSID_AGAIN=/d" \
  -e "/^MANAGED_NETWORK_WIFI_PSK_SECURITY=/d" \
  -e "/^MANAGED_NETWORK_WIFI_WPA=/d" \
  -e "/^MANAGED_NETWORK_WIFI_WEP=/d" \
  "$NO_WIFI_INPUT_ENV"
if /usr/bin/perl "$GENERATOR" --input "$NO_WIFI_INPUT_ENV" --state-env "$TMP_DIR/no-wifi.state.env" &&
   MANAGED_TARGET_ROOT="$TARGET_ROOT" \
   MANAGED_SYS_CLASS_NET="$SYS_CLASS_NET" \
   MANAGED_NETWORK_CONFIG="$TARGET_ROOT/etc/default/managed-network" \
   run_managed_network validate >/dev/null 2>&1; then
  if ! grep -q '^iface managed-wifi0 ' "$TARGET_ROOT/etc/network/interfaces.d/50-managed-network" &&
     assert_contains 'Name=managed-wifi0' "$TARGET_ROOT/etc/systemd/network/11-managed-wifi.link"; then
    pass "managed network validator accepts Ethernet-only static management while preserving the dormant managed Wi-Fi rename"
  else
    fail "managed network validator accepts Ethernet-only static management while preserving the dormant managed Wi-Fi rename"
  fi
else
  fail "managed network validator accepts Ethernet-only static management while preserving the dormant managed Wi-Fi rename"
fi

if /usr/bin/perl "$GENERATOR" --input "$INPUT_ENV" --state-env "$STATE_ENV"; then
  pass "managed network generator accepts IPv6 CIDR input and explicit Wi-Fi credentials"
else
  fail "managed network generator accepts IPv6 CIDR input and explicit Wi-Fi credentials"
fi

if MANAGED_TARGET_ROOT="$TARGET_ROOT" \
   MANAGED_SYS_CLASS_NET="$SYS_CLASS_NET" \
   MANAGED_NETWORK_CONFIG="$TARGET_ROOT/etc/default/managed-network" \
   run_managed_network validate >/dev/null 2>&1; then
  pass "managed-network validator accepts the generated managed iface aliases and validates the staged handoff"
else
  fail "managed-network validator accepts the generated managed iface aliases and validates the staged handoff"
fi

WIFI_ONLY_TARGET="$TMP_DIR/wifi-only-target"
WIFI_ONLY_INPUT_ENV="$TMP_DIR/wifi-only-input.env"
WIFI_ONLY_STATE_ENV="$TMP_DIR/wifi-only-state.env"
mkdir -p "$WIFI_ONLY_TARGET"
cp "$INPUT_ENV" "$WIFI_ONLY_INPUT_ENV"
sed -i \
  -e "s#^MANAGED_NETWORK_TARGET_ROOT='.*'#MANAGED_NETWORK_TARGET_ROOT='$WIFI_ONLY_TARGET'#" \
  -e "s#^MANAGED_NETWORK_STATE_ENV='.*'#MANAGED_NETWORK_STATE_ENV='$WIFI_ONLY_STATE_ENV'#" \
  -e "s#^MANAGED_NETWORK_LINK_TYPES='.*'#MANAGED_NETWORK_LINK_TYPES='wifi'#" \
  "$WIFI_ONLY_INPUT_ENV"
if /usr/bin/perl "$GENERATOR" --input "$WIFI_ONLY_INPUT_ENV" --state-env "$WIFI_ONLY_STATE_ENV" &&
   assert_contains "iface managed-wifi0 inet static" "$WIFI_ONLY_TARGET/etc/network/interfaces.d/50-managed-network" &&
   assert_contains "address 192.0.2.83" "$WIFI_ONLY_TARGET/etc/network/interfaces.d/50-managed-network" &&
   assert_contains "iface managed-wifi0 inet6 static" "$WIFI_ONLY_TARGET/etc/network/interfaces.d/50-managed-network" &&
   assert_contains "address 2001:9b1:29fd:4e00::83" "$WIFI_ONLY_TARGET/etc/network/interfaces.d/50-managed-network" &&
   ! grep -q '^iface managed-eth0 ' "$WIFI_ONLY_TARGET/etc/network/interfaces.d/50-managed-network" &&
   MANAGED_TARGET_ROOT="$WIFI_ONLY_TARGET" \
   MANAGED_SYS_CLASS_NET="$SYS_CLASS_NET" \
   MANAGED_NETWORK_CONFIG="$WIFI_ONLY_TARGET/etc/default/managed-network" \
   run_managed_network validate >/dev/null 2>&1; then
  pass "managed network validator accepts Wi-Fi-only static management and derives Wi-Fi addresses as base plus one"
else
  fail "managed network validator accepts Wi-Fi-only static management and derives Wi-Fi addresses as base plus one"
fi

MISMATCH_DEFAULT="$TMP_DIR/managed-network-mismatch.env"
MISMATCH_LOG="$TMP_DIR/managed-network-mismatch.log"
cp "$TARGET_ROOT/etc/default/managed-network" "$MISMATCH_DEFAULT"
sed -i "s/^MANAGED_NETWORK_WIFI_IFACE='managed-wifi0'$/MANAGED_NETWORK_WIFI_IFACE='wrongwifi0'/" "$MISMATCH_DEFAULT"
chmod 0600 "$MISMATCH_DEFAULT"
if ! MANAGED_TARGET_ROOT="$TARGET_ROOT" \
     MANAGED_SYS_CLASS_NET="$SYS_CLASS_NET" \
     MANAGED_NETWORK_CONFIG="$MISMATCH_DEFAULT" \
     run_managed_network validate >"$MISMATCH_LOG" 2>&1 &&
   assert_contains 'expected wifi interface is absent: wrongwifi0' "$MISMATCH_LOG"; then
  pass "managed network validator still rejects alias mismatches for actively managed adapters"
else
  fail "managed network validator still rejects alias mismatches for actively managed adapters"
fi

INTERFACES="$TARGET_ROOT/etc/network/interfaces.d/50-managed-network"
if assert_contains "iface managed-eth0 inet6 static" "$INTERFACES" &&
   assert_contains "address 2001:9b1:29fd:4e00::82" "$INTERFACES" &&
   assert_contains "iface managed-wifi0 inet6 static" "$INTERFACES" &&
   assert_contains "address 2001:9b1:29fd:4e00::83" "$INTERFACES" &&
   assert_contains "wpa-ssid TestNet" "$INTERFACES" &&
   assert_contains "wpa-key-mgmt WPA-PSK" "$INTERFACES" &&
   [ "$(grep -Fc 'netmask 64' "$INTERFACES")" -eq 2 ] &&
   [ "$(grep -Fc 'gateway 2001:9b1:29fd:4e00::1' "$INTERFACES")" -eq 2 ] &&
   [ "$(grep -Fc 'dns-nameservers 2001:9b1:29fd:4e00::1' "$INTERFACES")" -eq 2 ] &&
   ! grep -Fq 'settle-dad.sh' "$INTERFACES" &&
   ! grep -Fq 'up /sbin/ip -6 addr replace' "$INTERFACES"; then
  pass "generated ifupdown stanzas restore the August 9 static IPv6 contract"
else
  fail "generated ifupdown stanzas restore the August 9 static IPv6 contract"
fi

if assert_contains 'Name=managed-eth0' "$TARGET_ROOT/etc/systemd/network/10-managed-ethernet.link" &&
   assert_contains 'Name=managed-wifi0' "$TARGET_ROOT/etc/systemd/network/11-managed-wifi.link"; then
  pass "MAC-matched link files preserve managed-eth0 and managed-wifi0 target names"
else
  fail "MAC-matched link files preserve managed-eth0 and managed-wifi0 target names"
fi

# shellcheck disable=SC2034 # Sourced security helper reads this as its handoff-state guard.
MANAGED_NETWORK_STATE_PREPARED=false
# shellcheck disable=SC1090
. "$ROOT_DIR/d-i/forky/scripts/late/security.sh"
target_prepare_managed_network_handoff_state
ipv6_cidrs=$(nftables_ssh_allow_ipv6_cidrs)
interfaces=$(nftables_ssh_allow_interfaces)
if [ "$ipv6_cidrs" = '2001:9b1:29fd:4e00::/64' ] &&
   printf '%s\n' "$interfaces" | grep -Fxq managed-eth0 &&
   printf '%s\n' "$interfaces" | grep -Fxq managed-wifi0; then
  pass "nftables receives the managed IPv6 network and deterministic interfaces"
else
  fail "nftables receives the managed IPv6 network and deterministic interfaces"
fi

BAD_TARGET_ROOT="$TMP_DIR/bad-target"
BAD_INPUT_ENV="$TMP_DIR/bad-input.env"
mkdir -p "$BAD_TARGET_ROOT"
cp "$INPUT_ENV" "$BAD_INPUT_ENV"
cat >>"$BAD_INPUT_ENV" <<EOF
MANAGED_NETWORK_TARGET_ROOT='$BAD_TARGET_ROOT'
MANAGED_NETWORK_IPV6_ADDRESS='2001:9b1:29fd:4e00::82'
EOF
if ! /usr/bin/perl "$GENERATOR" --input "$BAD_INPUT_ENV" --state-env "$TMP_DIR/bad-state.env" >/dev/null 2>&1 &&
   [ ! -e "$BAD_TARGET_ROOT/etc/network/interfaces" ]; then
  pass "IPv6 addresses without CIDR notation fail before target network files are written"
else
  fail "IPv6 addresses without CIDR notation fail before target network files are written"
fi

if [ "$TEST_INDEX" -ne "$TEST_COUNT" ]; then
  printf 'not ok - planned %s tests but executed %s\n' "$TEST_COUNT" "$TEST_INDEX"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

[ "$FAIL_COUNT" -eq 0 ]
