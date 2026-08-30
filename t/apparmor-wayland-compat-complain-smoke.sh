#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
FIXTURE="$ROOT_DIR/t/fixtures/apparmor-wayland-compat-complain.log"
OUTPUT=$(mktemp "${TMPDIR:-/tmp}/apparmor-wayland-compat.XXXXXX")
trap 'rm -f -- "$OUTPUT"' EXIT HUP INT TERM

TEST_COUNT=2
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

if APPARMOR_DENIED_MASK_LOG="$FIXTURE" \
  /bin/sh "$ROOT_DIR/t/apparmor-denied-mask-smoke.sh" >"$OUTPUT" 2>&1; then
  pass "sanitized Zoom and Xwayland complain-mode fixture is fully classified"
else
  cat -- "$OUTPUT"
  fail "sanitized Zoom and Xwayland complain-mode fixture is fully classified"
fi

actual_categories=$(
  grep -E '^# (wayland_compat_|zoom_persistent_config:)' "$OUTPUT" || true
)
expected_categories=$(cat <<'EOF'
# wayland_compat_cpu_metadata: 8
# wayland_compat_diagnostic_exec: 11
# wayland_compat_iproute_metadata: 1
# wayland_compat_pci_metadata: 2
# wayland_compat_portal_inventory: 1
# wayland_compat_power_supply_metadata: 1
# wayland_compat_qt_shader_cache: 1
# wayland_compat_xkb_keymap: 4
# zoom_persistent_config: 9
EOF
)

if grep -Fqx '# reviewed complain-mode access records: 38' "$OUTPUT" &&
   grep -Fqx '# ignored root Zoom access records: 0' "$OUTPUT" &&
   [ "$actual_categories" = "$expected_categories" ]; then
  pass "fixture covers every bounded helper, metadata, keymap, cache, and atomic-config rule family"
else
  cat -- "$OUTPUT"
  fail "fixture covers every bounded helper, metadata, keymap, cache, and atomic-config rule family"
fi

if [ "$FAIL_COUNT" -ne 0 ]; then
  exit 1
fi
