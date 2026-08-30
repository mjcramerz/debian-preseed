#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/desktop-var-cache-smoke.XXXXXX")
trap 'rm -rf "$TMP_DIR"' EXIT HUP INT TERM

TEST_COUNT=3
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

policy="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/tmpfiles.d/50-desktop-var-cache.conf"
man_policy="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/tmpfiles.d/man-db.conf"
components="$ROOT_DIR/d-i/forky/scripts/desktop/components.sh"
expected="$TMP_DIR/50-desktop-var-cache.expected"
man_expected="$TMP_DIR/man-db.expected"

cat >"$expected" <<'EOF'
# Managed by unattended-installer.
d /var/cache/ldconfig 0700 root root -
d /var/cache/mullvad-vpn 0755 root root -
d /var/cache/tailscale 0750 root root -
d /var/cache/fontconfig 0755 root root -
d /var/cache/incus 0700 root root -
d /var/cache/incus/resources 0700 root root -
d /var/cache/fwupd 0755 root root -
d /var/cache/fwupdmgr 0755 fwupd-refresh fwupd-refresh -
EOF
cat >"$man_expected" <<'EOF'
# Managed by unattended-installer.
# Keep Debian man-db cleanup semantics while overriding the vendor tmpfiles
# basename from /etc so the managed desktop policy remains the effective rule.
d /var/cache/man 0755 man man a:1w
x /var/cache/man/index*
x /var/cache/man/*/index*
EOF

if cmp -s "$expected" "$policy" &&
   cmp -s "$man_expected" "$man_policy" &&
   ! grep -Eq '__INSTALLER_[A-Z0-9_]+__' "$policy" "$man_policy"; then
  pass "desktop var-cache tmpfiles policy pins package-compatible modes and ownership"
else
  fail "desktop var-cache tmpfiles policy pins package-compatible modes and ownership"
fi

tmpfiles_sources="$TMP_DIR/tmpfiles.sources"
find "$ROOT_DIR/d-i/forky/hooks" -path '*/target/etc/tmpfiles.d/*' -type f -print |
  sort >"$tmpfiles_sources"
cache_paths='
/var/cache/ldconfig
/var/cache/mullvad-vpn
/var/cache/tailscale
/var/cache/fontconfig
/var/cache/incus
/var/cache/incus/resources
/var/cache/fwupd
/var/cache/fwupdmgr
/var/cache/man
'
cache_paths_unique=true
for cache_path in $cache_paths; do
  cache_path_count=0
  while IFS= read -r tmpfiles_source; do
    source_count=$(
      awk -v expected_path="$cache_path" '
        $1 == "d" && $2 == expected_path {
          count += 1
        }
        END {
          print count + 0
        }
      ' "$tmpfiles_source"
    )
    cache_path_count=$((cache_path_count + source_count))
  done <"$tmpfiles_sources"
  if [ "$cache_path_count" -ne 1 ]; then
    cache_paths_unique=false
    break
  fi
done
if [ "$cache_paths_unique" = true ]; then
  pass "each managed desktop var-cache directory has exactly one tracked tmpfiles rule"
else
  fail "each managed desktop var-cache directory has exactly one tracked tmpfiles rule"
fi

invocation="$TMP_DIR/desktop-var-cache.invocation"
harness="$TMP_DIR/desktop-var-cache-harness.sh"
cat >"$harness" <<'EOF'
#!/bin/sh
set -eu

. "$1"

installer_fatal() {
  printf 'fatal: %s\n' "$*" >&2
  exit 1
}

run_in_target_quiet() {
  [ "$1" = "validate desktop var-cache owners" ]
  [ "$2" = /bin/sh ]
  [ "$3" = -eu ]
  [ "$4" = -c ]
  printf '%s\n' "$5" | grep -q '^for account_name in man fwupd-refresh; do$'
  printf '%s\n' "$5" | grep -q 'getent passwd "$account_name"'
  printf '%s\n' "$5" | grep -q 'getent group "$account_name"'
  [ "$6" = sh ]
  printf '%s\n' validate >>"$DESKTOP_VAR_CACHE_INVOCATION"
}

desktop_stage_role_asset() {
  printf 'stage\n%s\n%s\n%s\n' "$1" "$2" "$3" >>"$DESKTOP_VAR_CACHE_INVOCATION"
}

normalize_target_tmpfiles_directory_policy() {
  printf 'normalize\n%s\n%s\n' "$1" "$2" >>"$DESKTOP_VAR_CACHE_INVOCATION"
}

desktop_log() {
  printf 'log\n%s\n' "$1" >>"$DESKTOP_VAR_CACHE_INVOCATION"
}

desktop_stage_var_cache_policy
EOF
chmod 0700 "$harness"
expected_invocation=$(cat <<'EOF'
validate
stage
etc/tmpfiles.d/50-desktop-var-cache.conf
/etc/tmpfiles.d/50-desktop-var-cache.conf
0644
stage
etc/tmpfiles.d/man-db.conf
/etc/tmpfiles.d/man-db.conf
0644
normalize
/etc/tmpfiles.d/50-desktop-var-cache.conf
desktop var-cache directories
normalize
/etc/tmpfiles.d/man-db.conf
desktop man-db cache directory
log
staged_desktop_var_cache policy=/etc/tmpfiles.d/50-desktop-var-cache.conf man_policy=/etc/tmpfiles.d/man-db.conf
EOF
)
if DESKTOP_VAR_CACHE_INVOCATION="$invocation" "$harness" "$components" &&
   [ "$(cat "$invocation")" = "$expected_invocation" ] &&
   grep -q '^  desktop_stage_var_cache_policy$' "$components"; then
  pass "desktop late staging validates named owners, installs the var-cache policy, and applies it immediately"
else
  fail "desktop late staging validates named owners, installs the var-cache policy, and applies it immediately"
fi

[ "$TEST_INDEX" -eq "$TEST_COUNT" ] || {
  printf 'not ok - planned %s tests but ran %s\n' "$TEST_COUNT" "$TEST_INDEX"
  exit 1
}

[ "$FAIL_COUNT" -eq 0 ]
