#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/forky-apt-target-policy-smoke.XXXXXX")
trap 'rm -rf "$TMP_DIR"' EXIT HUP INT TERM

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

check_case() {
  case_name=$1
  classes=$2
  expected_pref_names=$3
  expected_variant_path=$4

  runtime_dir="$TMP_DIR/runtime-$case_name"
  out_path="$TMP_DIR/$case_name.out"

  if (
    set -eu
    INSTALLER_SOURCE_ROOT="$ROOT_DIR/d-i/forky"
    INSTALLER_RUNTIME_DIR="$runtime_dir"
    export INSTALLER_SOURCE_ROOT INSTALLER_RUNTIME_DIR
    # shellcheck disable=SC1090
    . "$ROOT_DIR/d-i/forky/scripts/common/lib.sh"
    installer_auto_class_tokens() {
      printf '%s\n' amd64
      printf '%s\n' intel
      printf '%s\n' generic
      printf '%s\n' nvme
    }
    installer_cmdline_value() {
      case "$1" in
        auto-install/classes|classes)
          printf '%s\n' "$classes"
          ;;
      esac
    }
    installer_debconf_value() { return 1; }
    installer_write_context "$ROOT_DIR/d-i/forky" >/dev/null
    printf 'config=%s\n' "$(installer_apt_preferences_config)"
    printf 'names='
    installer_configured_apt_preferences | paste -sd, -
    printf '\n'
    printf 'forky_source=%s\n' "$(installer_target_apt_preference_source_path forky.pref)"
  ) >"$out_path"; then
    :
  else
    return 1
  fi

  config=$(sed -n 's/^config=//p' "$out_path" | head -n 1)
  names=$(sed -n 's/^names=//p' "$out_path" | head -n 1)
  forky_source=$(sed -n 's/^forky_source=//p' "$out_path" | head -n 1)

  [ "$config" = "$expected_pref_names" ] || return 1
  expected_names=$(printf '%s\n' "$expected_pref_names" | tr ',' '\n' | sed 's/$/.pref/' | paste -sd, -)
  [ "$names" = "$expected_names" ] || return 1
  [ "$forky_source" = "$expected_variant_path" ] || return 1
  return 0
}

if check_case \
  desktop_default \
  'prod,desktop,standard,static,software' \
  'forky,trixie,sid,experimental,cramerz,dbus,x11,vulkan' \
  'hooks/shared/target/etc/apt/preferences.d/desktop/forky.pref'; then
  pass "desktop target policy includes forky.pref in the configured preferences and uses the desktop variant path"
else
  fail "desktop target policy includes forky.pref in the configured preferences and uses the desktop variant path"
fi

if check_case \
  server_suite \
  'prod,server,standard,static,server-suite' \
  'forky,trixie,sid,experimental,cramerz,dbus,x11,vulkan' \
  'hooks/shared/target/etc/apt/preferences.d/server/forky.pref'; then
  pass "server-suite keeps the base forky preference ordering while switching to the server-side blocked pin"
else
  fail "server-suite keeps the base forky preference ordering while switching to the server-side blocked pin"
fi

if grep -q '^DEBIAN_APT_PREFERENCES="forky,trixie,sid,experimental,cramerz,dbus,x11,vulkan"$' "$ROOT_DIR/d-i/forky/repo.env"; then
  pass "repo.env base apt preferences keep suite ordering and append the Vulkan block"
else
  fail "repo.env base apt preferences keep suite ordering and append the Vulkan block"
fi

if grep -q '^Name: server-suite$' "$ROOT_DIR/d-i/forky/classes/configs/addons.cfg" &&
   grep -q '^DebianAptPreferences: forky$' "$ROOT_DIR/d-i/forky/classes/configs/addons.cfg"; then
  pass "server-suite explicitly requests the forky fallback apt preference"
else
  fail "server-suite explicitly requests the forky fallback apt preference"
fi

if grep -q '^Pin-Priority: 900$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apt/preferences.d/desktop/forky.pref" &&
   grep -q '^Pin-Priority: -1$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apt/preferences.d/server/forky.pref" &&
   grep -q '^Pin-Priority: 900$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apt/preferences.d/server/trixie.pref" &&
   grep -q '^Pin: release a=experimental,n=rc-buggy$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apt/preferences.d/desktop/experimental.pref" &&
   grep -q '^Pin: release a=experimental,n=rc-buggy$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apt/preferences.d/server/experimental.pref" &&
   grep -q '^Pin-Priority: 1$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apt/preferences.d/desktop/experimental.pref" &&
   grep -q '^Pin-Priority: 1$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apt/preferences.d/server/experimental.pref"; then
  pass "desktop forky pin stays preferred while server forky is blocked and Experimental remains inert"
else
  fail "desktop forky pin stays preferred while server forky is blocked and Experimental remains inert"
fi

[ "$FAIL_COUNT" -eq 0 ]
