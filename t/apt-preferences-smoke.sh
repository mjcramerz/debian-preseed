#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/apt-preferences-smoke.XXXXXX")
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
  if [ "$#" -gt 1 ] && [ -n "${2:-}" ] && [ -r "$2" ]; then
    sed 's/^/# /' "$2"
  fi
}

make_source_tree() {
  source_root=$1
  mkdir -p "$source_root/classes/configs"
  cp "$ROOT_DIR/d-i/forky/repo.env" "$source_root/repo.env"
  cp "$ROOT_DIR/d-i/forky/classes/install.conf" "$source_root/classes/install.conf"
  cp "$ROOT_DIR"/d-i/forky/classes/configs/*.cfg "$source_root/classes/configs/"
  cat >>"$source_root/classes/configs/addons.cfg" <<'EOF'

Type: class
Group: addon
Name: testprefs
Description: test additive apt preference merge
DebianAptPreferences: sid, dbus, forky, test

Type: class
Group: addon
Name: minprefs
Description: test override without repo defaults
DebianAptPreferences: sid, test
EOF
}

run_case() {
  case_name=$1
  selected_refs=$2
  output_path=$3
  error_path=$4

  source_root="$TMP_DIR/$case_name"
  mkdir -p "$source_root"
  make_source_tree "$source_root"

  if (
    set -eu
    INSTALLER_SOURCE_ROOT=$source_root
    INSTALLER_RUNTIME_DIR="$TMP_DIR/runtime-$case_name"
    INSTALLER_SELECTED_CLASS_REFS=$selected_refs
    export INSTALLER_SOURCE_ROOT INSTALLER_RUNTIME_DIR INSTALLER_SELECTED_CLASS_REFS
    # shellcheck disable=SC1090
    . "$ROOT_DIR/d-i/forky/scripts/common/lib.sh"
    installer_nvidia_gpu_detected() { return 0; }
    printf 'config=%s\n' "$(installer_apt_preferences_config)"
    printf 'names='
    installer_configured_apt_preferences | paste -sd, -
    printf '\n'
  ) >"$output_path" 2>"$error_path"; then
    return 0
  fi

  return 1
}

extract_value() {
  key=$1
  output_path=$2
  sed -n "s/^${key}=//p" "$output_path" | head -n 1
}

printf '1..%s\n' "$TEST_COUNT"

fallback_out="$TMP_DIR/fallback.out"
fallback_err="$TMP_DIR/fallback.err"
if run_case fallback "" "$fallback_out" "$fallback_err"; then
  if [ "$(extract_value config "$fallback_out")" = "forky,trixie,sid,experimental,cramerz,dbus,x11,vulkan" ] &&
     [ "$(extract_value names "$fallback_out")" = "forky.pref,trixie.pref,sid.pref,experimental.pref,cramerz.pref,dbus.pref,x11.pref,vulkan.pref" ]; then
    pass "repo.env apt preferences remain the fallback"
  else
    fail "repo.env apt preferences remain the fallback" "$fallback_out"
  fi
else
  fail "repo.env apt preferences remain the fallback" "$fallback_err"
fi

forky_out="$TMP_DIR/forky.out"
forky_err="$TMP_DIR/forky.err"
if run_case forky "addon/tailscale" "$forky_out" "$forky_err"; then
  if [ "$(extract_value config "$forky_out")" = "forky,trixie,sid,experimental,cramerz,dbus,x11,vulkan,tailscale" ] &&
     [ "$(extract_value names "$forky_out")" = "forky.pref,trixie.pref,sid.pref,experimental.pref,cramerz.pref,dbus.pref,x11.pref,vulkan.pref,tailscale.pref" ]; then
    pass "single class apt preference metadata extends repo.env"
  else
    fail "single class apt preference metadata extends repo.env" "$forky_out"
  fi
else
  fail "single class apt preference metadata extends repo.env" "$forky_err"
fi

merged_out="$TMP_DIR/merged.out"
merged_err="$TMP_DIR/merged.err"
if run_case merged "addon/tailscale addon/testprefs" "$merged_out" "$merged_err"; then
  if [ "$(extract_value config "$merged_out")" = "forky,trixie,sid,experimental,cramerz,dbus,x11,vulkan,tailscale,test" ] &&
     [ "$(extract_value names "$merged_out")" = "forky.pref,trixie.pref,sid.pref,experimental.pref,cramerz.pref,dbus.pref,x11.pref,vulkan.pref,tailscale.pref,test.pref" ]; then
    pass "multiple class apt preference metadata merges with deduplication"
  else
    fail "multiple class apt preference metadata merges with deduplication" "$merged_out"
  fi
else
  fail "multiple class apt preference metadata merges with deduplication" "$merged_err"
fi

override_out="$TMP_DIR/override.out"
override_err="$TMP_DIR/override.err"
if run_case override "addon/minprefs" "$override_out" "$override_err"; then
  if [ "$(extract_value config "$override_out")" = "forky,trixie,sid,experimental,cramerz,dbus,x11,vulkan,test" ] &&
     [ "$(extract_value names "$override_out")" = "forky.pref,trixie.pref,sid.pref,experimental.pref,cramerz.pref,dbus.pref,x11.pref,vulkan.pref,test.pref" ]; then
    pass "class metadata extends repo.env without duplicating base preferences"
  else
    fail "class metadata extends repo.env without duplicating base preferences" "$override_out"
  fi
else
  fail "class metadata extends repo.env without duplicating base preferences" "$override_err"
fi

cuda_out="$TMP_DIR/cuda.out"
cuda_err="$TMP_DIR/cuda.err"
if run_case cuda "addon/nvidia addon/cuda" "$cuda_out" "$cuda_err"; then
  if [ "$(extract_value config "$cuda_out")" = "forky,trixie,sid,experimental,cramerz,dbus,x11,vulkan,nvidia,cuda" ] &&
     [ "$(extract_value names "$cuda_out")" = "forky.pref,trixie.pref,sid.pref,experimental.pref,cramerz.pref,dbus.pref,x11.pref,vulkan.pref,nvidia.pref,cuda.pref" ]; then
    pass "cuda apt preference config requires and extends the nvidia pin set deterministically"
  else
    fail "cuda apt preference config requires and extends the nvidia pin set deterministically" "$cuda_out"
  fi
else
  fail "cuda apt preference config requires and extends the nvidia pin set deterministically" "$cuda_err"
fi

[ "$FAIL_COUNT" -eq 0 ]
