#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT HUP INT TERM

generator="$ROOT_DIR/d-i/forky/hooks/shared/target/usr/local/sbin/nft-policy-generate.py"
desktop_profile="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/nftables/profiles/desktop.yml"
ssh_client_overlay="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/nftables/services/ssh-client.yml"
nftables_route="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/rsyslog.d/40-nftables.conf"

TEST_COUNT=5
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

mkdir -p "$TMP_DIR/none" "$TMP_DIR/info" "$TMP_DIR/apps"

NFTABLES_LOG_LEVEL=none python3 "$generator" \
  --profile "$desktop_profile" \
  --target-root "$TMP_DIR/none" \
  --write

NFTABLES_LOG_LEVEL=info python3 "$generator" \
  --profile "$desktop_profile" \
  --target-root "$TMP_DIR/info" \
  --write

if diff -ru \
  "$TMP_DIR/none/etc/nftables.d" \
  "$TMP_DIR/info/etc/nftables.d" \
  >"$TMP_DIR/log-level.diff"; then
  pass "NFTABLES_LOG_LEVEL changes diagnostics only and leaves packet policy identical"
else
  cat "$TMP_DIR/log-level.diff"
  fail "NFTABLES_LOG_LEVEL changes diagnostics only and leaves packet policy identical"
fi

filter="$TMP_DIR/none/etc/nftables.d/20-filter.nft"
if grep -Fq 'log prefix "nftables accept output "' "$filter" &&
   grep -Fq 'limit rate 5/minute burst 10 packets' "$filter"; then
  pass "desktop policy emits bounded accepted-output packet logging"
else
  fail "desktop policy emits bounded accepted-output packet logging"
fi

if grep -Fq 'log prefix "nftables drop input "' "$filter" &&
   grep -Fq 'log prefix "nftables drop forward "' "$filter"; then
  pass "desktop policy emits bounded final input and forward drop logging"
else
  fail "desktop policy emits bounded final input and forward drop logging"
fi

python3 "$generator" \
  --profile "$desktop_profile" \
  --overlay "$ssh_client_overlay" \
  --target-root "$TMP_DIR/apps" \
  --write

apps_filter="$TMP_DIR/apps/etc/nftables.d/20-filter.nft"
accept_line=$(grep -n -m 1 'log prefix "nftables accept output "' "$apps_filter" | cut -d: -f1)
app_line=$(grep -n -m 1 'egress ssh_client outbound' "$apps_filter" | cut -d: -f1)
if [ -n "$accept_line" ] &&
   [ -n "$app_line" ] &&
   [ "$accept_line" -lt "$app_line" ]; then
  pass "accepted-output logging runs before application outbound accept rules"
else
  fail "accepted-output logging runs before application outbound accept rules"
fi

# shellcheck disable=SC2016
if grep -Fq '$msg contains "nftables accept "' "$nftables_route" &&
   grep -Fq '$msg contains "nftables drop "' "$nftables_route" &&
   grep -Fq 'file="/var/log/managed/nftables/firewall.log"' "$nftables_route"; then
  pass "rsyslog routes managed accept and drop prefixes to firewall.log"
else
  fail "rsyslog routes managed accept and drop prefixes to firewall.log"
fi

[ "$FAIL_COUNT" -eq 0 ]
