#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)

TEST_COUNT=8
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

addons_cfg="$ROOT_DIR/d-i/forky/classes/configs/addons.cfg"
ch341a_class="$ROOT_DIR/d-i/forky/classes/class-addon/ch341a.cfg"
helper="$ROOT_DIR/d-i/forky/scripts/late/ch341a.sh"
udev_rule="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/udev/rules.d/61-ch341a-programmers.rules"
firmware_tmpfiles="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/tmpfiles.d/86-firmware-workspace.conf.tmpl"
firmware_profile="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.profile.d/75-firmware-workspace.sh.tmpl"
common_lib="$ROOT_DIR/d-i/forky/scripts/common/lib.sh"

if grep -q '^Name: ch341a$' "$addons_cfg" &&
   grep -q '^RequiresClasses: role/desktop$' "$addons_cfg" &&
   grep -q '^LateHelper: ch341a$' "$addons_cfg"; then
  pass "ch341a addon metadata requires the desktop role and wires the late helper"
else
  fail "ch341a addon metadata requires the desktop role and wires the late helper"
fi

if grep -Eq '^d-i pkgsel/include string .*flashrom .*flashprog .*imsprog .*binwalk .*uefitool-cli .*coreboot-utils .*mtd-utils .*squashfs-tools .*cramfsswap .*xxd .*hexedit .*python3-magic .*okteta$' "$ch341a_class"; then
  pass "ch341a addon keeps the requested firmware and programmer toolchain installable on Forky"
else
  fail "ch341a addon keeps the requested firmware and programmer toolchain installable on Forky"
fi

if grep -q 'installer_selected_class_reference_is_selected addon/ch341a' "$helper" &&
   grep -q 'groupadd --system usbadmin' "$helper" &&
   grep -q 'usermod -a -G usbadmin -- "$account_user"' "$helper" &&
   grep -q 'systemd-tmpfiles --create /etc/tmpfiles.d/86-firmware-workspace.conf' "$helper" &&
   grep -q 'command -v IMSProg >/dev/null 2>&1' "$helper" &&
   grep -q 'command -v cbfstool >/dev/null 2>&1' "$helper" &&
   grep -q '\[ -x /usr/bin/binwalk \] || \[ -x /usr/bin/pybinwalk \]' "$helper" &&
   grep -q 'installer_assert_no_unresolved_installer_placeholders "\$tmp_rendered" "ch341a template \${repo_path}"' "$helper"; then
  pass "ch341a late helper stages the firmware lab roots and grants usbadmin access"
else
  fail "ch341a late helper stages the firmware lab roots and grants usbadmin access"
fi

groupadd_line=$(grep -n 'groupadd --system usbadmin' "$helper" | head -n 1 | cut -d: -f1)
tmpfiles_line=$(grep -n 'systemd-tmpfiles --create /etc/tmpfiles.d/86-firmware-workspace.conf' "$helper" | head -n 1 | cut -d: -f1)
if [ -n "$groupadd_line" ] &&
   [ -n "$tmpfiles_line" ] &&
   [ "$groupadd_line" -lt "$tmpfiles_line" ]; then
  pass "ch341a creates usbadmin before applying the firmware tmpfiles policy"
else
  fail "ch341a creates usbadmin before applying the firmware tmpfiles policy"
fi

if grep -q 'ATTRS{idVendor}=="1a86", ATTRS{idProduct}=="5512"' "$udev_rule" &&
   grep -q 'ATTRS{idVendor}=="1a86", ATTRS{idProduct}=="55db"' "$udev_rule" &&
   grep -q 'GROUP="usbadmin"' "$udev_rule" &&
   grep -q 'ID_MM_DEVICE_IGNORE' "$udev_rule"; then
  pass "ch341a udev rule scopes CH341A and CH347 programmer access to usbadmin"
else
  fail "ch341a udev rule scopes CH341A and CH347 programmer access to usbadmin"
fi

if grep -q '^d __INSTALLER_DIR_POOL_FIRMWARE__ 2770 root usbadmin -$' "$firmware_tmpfiles" &&
   grep -q '^d __INSTALLER_DIR_POOL_FIRMWARE__/__INSTALLER_ACCOUNT_USERNAME__/captures 2750 __INSTALLER_ACCOUNT_USERNAME__ usbadmin -$' "$firmware_tmpfiles" &&
   grep -q '^FIRMWARE_POOL_ROOT="${FIRMWARE_POOL_ROOT:-__INSTALLER_DIR_POOL_FIRMWARE__}"$' "$firmware_profile" &&
   grep -q '^FIRMWARE_WORKSPACE_ROOT="${FIRMWARE_WORKSPACE_ROOT:-${FIRMWARE_POOL_ROOT}/${USER}}"$' "$firmware_profile" &&
   grep -q '^FIRMWARE_CAPTURE_DIR="${FIRMWARE_CAPTURE_DIR:-${FIRMWARE_WORKSPACE_ROOT}/captures}"$' "$firmware_profile"; then
  pass "firmware lab assets route captures and unpacked images into /pool/firmware"
else
  fail "firmware lab assets route captures and unpacked images into /pool/firmware"
fi

render_tmp="$ROOT_DIR/.tmp-ch341a-render.$$"
render_out="$ROOT_DIR/.tmp-ch341a-render.out.$$"
if (
  set -eu
  # shellcheck disable=SC1090
  . "$common_lib"
  installer_apply_scalar_placeholders \
    "$firmware_tmpfiles" \
    "$render_out" \
    ACCOUNT_USERNAME testuser \
    DIR_POOL_FIRMWARE /pool/firmware
  ! grep -q '__INSTALLER_' "$render_out" &&
  grep -q '^d /pool/firmware 2770 root usbadmin -$' "$render_out" &&
  grep -q '^d /pool/firmware/testuser/captures 2750 testuser usbadmin -$' "$render_out"
); then
  pass "ch341a helper placeholder arguments render the firmware tmpfiles policy fully"
else
  fail "ch341a helper placeholder arguments render the firmware tmpfiles policy fully"
fi
rm -f "$render_tmp" "$render_out"

if grep -q '^installer_assert_no_unresolved_installer_placeholders() {$' "$common_lib" &&
   grep -q 'installer_assert_no_unresolved_installer_placeholders "\$tmp_rendered" "ch341a template \${repo_path}"' "$helper"; then
  pass "ch341a late helper now fails fast when placeholder rendering leaves installer tokens behind"
else
  fail "ch341a late helper now fails fast when placeholder rendering leaves installer tokens behind"
fi

[ "$FAIL_COUNT" -eq 0 ]
