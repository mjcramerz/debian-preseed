#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
RULE_DIR="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/polkit-1/rules.d"
COMPONENTS="$ROOT_DIR/d-i/forky/scripts/desktop/components.sh"
VERIFY="$ROOT_DIR/d-i/forky/scripts/desktop/verify.sh"
FIRSTBOOT="$ROOT_DIR/d-i/forky/scripts/firstboot/04-validation.sh"
GREETER_RULE="$RULE_DIR/10-greetd-power.rules.tmpl"
POWER_RULE="$RULE_DIR/03-labwc-power.rules"
USB_RULE="$RULE_DIR/50-usb-policy.rules"
FWUPD_RULE="$RULE_DIR/04-fwupd-refresh.rules"
GATE_RULE="$RULE_DIR/05-active-local-gate.rules"

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

rule_names='
00-admin-identities.rules
03-labwc-power.rules
04-fwupd-refresh.rules
05-active-local-gate.rules
10-pkexec.rules
20-login1-power.rules
40-networkmanager.rules
50-usb-policy.rules
55-software-management.rules
60-system-services-identity.rules
70-hardware-peripherals.rules
'

catalog_ok=true
for rule_name in $rule_names; do
  if ! grep -A20 '^desktop_polkit_managed_rule_files() {' "$COMPONENTS" |
     grep -qx "$rule_name"; then
    catalog_ok=false
  fi
  if [ ! -r "$RULE_DIR/$rule_name" ]; then
    catalog_ok=false
  fi
done
if [ "$catalog_ok" = true ] &&
   grep -q '"etc/polkit-1/rules.d/${polkit_rule}"' "$COMPONENTS"; then
  pass "desktop staging owns the complete ordered polkit rule catalog"
else
  fail "desktop staging owns the complete ordered polkit rule catalog"
fi

if ! rg -n 'subject\.seat|subject\.local === true \|\|' "$RULE_DIR"; then
  pass "desktop polkit rules require subject.local and do not infer locality from seat strings"
else
  fail "desktop polkit rules require subject.local and do not infer locality from seat strings"
fi

if grep -Fq 'action.id === "org.freedesktop.fwupd.refresh-remote"' "$FWUPD_RULE" &&
   grep -Fq 'subject.user === FWUPD_REFRESH_USER' "$FWUPD_RULE" &&
   grep -Fq 'subject.system_unit === FWUPD_REFRESH_UNIT' "$FWUPD_RULE" &&
   grep -Fq 'var FWUPD_REFRESH_UNIT = "fwupd-refresh.service";' "$FWUPD_RULE"; then
  pass "fwupd metadata refresh authorization is limited to its system service"
else
  fail "fwupd metadata refresh authorization is limited to its system service"
fi

gated_prefixes='
org.freedesktop.policykit.exec
org.freedesktop.login1.
org.freedesktop.udisks2.
org.freedesktop.UDisks2.
org.freedesktop.NetworkManager.
org.freedesktop.PackageKit.
org.freedesktop.packagekit.
org.freedesktop.Flatpak.
org.freedesktop.fwupd.
org.freedesktop.systemd1.
org.freedesktop.accounts.
org.freedesktop.hostname1.
org.freedesktop.locale1.
org.freedesktop.timedate1.
org.freedesktop.realmd.
org.freedesktop.ModemManager1.
org.freedesktop.color-manager.
org.freedesktop.bolt.
org.freedesktop.upower.
org.opensuse.cupspkhelper.mechanism.
org.blueman.
org.bluez.
org.fedoraproject.FirewallD1.
'
gate_ok=true
for gated_prefix in $gated_prefixes; do
  if ! grep -Fq "\"${gated_prefix}\"" "$GATE_RULE"; then
    gate_ok=false
  fi
done
if [ "$gate_ok" = true ] &&
   grep -q 'return subject.active === true && subject.local === true;' "$GATE_RULE" &&
   grep -q 'function isRoot(subject)' "$GATE_RULE" &&
   grep -q '!isRoot(subject)' "$GATE_RULE"; then
  pass "early gate covers every managed desktop polkit mechanism namespace"
else
  fail "early gate covers every managed desktop polkit mechanism namespace"
fi
unset gated_prefix gated_prefixes gate_ok

if grep -Fq 'var POWER_HELPER = "/usr/local/libexec/labwc-admin-action-root";' "$POWER_RULE" &&
   grep -Fq 'action.id !== "org.freedesktop.policykit.exec"' "$POWER_RULE" &&
   grep -Fq 'lookupString(action, "program") !== POWER_HELPER' "$POWER_RULE" &&
   grep -Fq '!subject.isInGroup(ADMIN_GROUP)' "$POWER_RULE" &&
   grep -Fq 'return polkit.Result.AUTH_ADMIN;' "$POWER_RULE" &&
   ! grep -Eq 'subject\.(active|local|seat)' "$POWER_RULE"; then
  pass "the early exact-program power rule requires sudo authentication without display-manager session classification"
else
  fail "the early exact-program power rule requires sudo authentication without display-manager session classification"
fi

if grep -q 'function isRoot(subject)' "$GATE_RULE" &&
   grep -q '!isRoot(subject)' "$GATE_RULE" &&
   grep -q 'function isRoot(subject)' "$RULE_DIR/10-pkexec.rules" &&
   grep -q 'return polkit.Result.YES;' "$RULE_DIR/10-pkexec.rules"; then
  pass "pkexec and the early gate preserve root while denying inactive non-local callers"
else
  fail "pkexec and the early gate preserve root while denying inactive non-local callers"
fi

admin_rules_ok=true
for rule_name in \
  20-login1-power.rules \
  40-networkmanager.rules \
  55-software-management.rules \
  60-system-services-identity.rules \
  70-hardware-peripherals.rules
do
  if ! grep -q 'function isRoot(subject)' "$RULE_DIR/$rule_name" ||
     ! grep -q 'return polkit.Result.YES;' "$RULE_DIR/$rule_name"; then
    admin_rules_ok=false
  fi
done
if [ "$admin_rules_ok" = true ]; then
  pass "desktop admin policy families preserve root and require active local sudo users"
else
  fail "desktop admin policy families preserve root and require active local sudo users"
fi

if grep -q 'lookupString(action, "drive.removable") === "true"' "$USB_RULE" &&
   grep -q 'lookupString(action, "drive.removable.bus") === "usb"' "$USB_RULE" &&
   grep -q '"org.freedesktop.udisks2.filesystem-mount": true' "$USB_RULE" &&
   grep -q '"org.freedesktop.udisks2.filesystem-unmount-others": true' "$USB_RULE" &&
   grep -q '"org.freedesktop.udisks2.eject-media": true' "$USB_RULE" &&
   grep -q '"org.freedesktop.udisks2.power-off-drive": true' "$USB_RULE"; then
  pass "USB policy matches removable USB media and the supported UDisks2 action set"
else
  fail "USB policy matches removable USB media and the supported UDisks2 action set"
fi

if ! grep -q '"org.freedesktop.udisks2.filesystem-unmount": true' "$USB_RULE" &&
   ! grep -q '"org.freedesktop.udisks2.drive-eject": true' "$USB_RULE" &&
   ! grep -q '"id.bus"' "$USB_RULE"; then
  pass "USB policy rejects stale UDisks2 action names and unsupported id.bus matching"
else
  fail "USB policy rejects stale UDisks2 action names and unsupported id.bus matching"
fi

if grep -q 'subject.local !== true' "$GREETER_RULE" &&
   ! grep -q 'subject.seat' "$GREETER_RULE" &&
   grep -q 'org.freedesktop.login1.power-off' "$GREETER_RULE" &&
   grep -q 'org.freedesktop.login1.reboot' "$GREETER_RULE"; then
  pass "greetd power policy is limited to an active local greeter session and exact actions"
else
  fail "greetd power policy is limited to an active local greeter session and exact actions"
fi

if grep -q '/etc/polkit-1/rules.d/00-admin-identities.rules' "$VERIFY" &&
   grep -q '/etc/polkit-1/rules.d/70-hardware-peripherals.rules' "$VERIFY" &&
   ! grep -Eq 'grep .*polkit|drive\.removable\.bus|subject\.local|subject\.seat' "$VERIFY"; then
  pass "target verification checks staged polkit paths without duplicating rule-content assertions"
else
  fail "target verification checks staged polkit paths without duplicating rule-content assertions"
fi

if grep -q '/etc/polkit-1/rules.d/00-admin-identities.rules' "$FIRSTBOOT" &&
   grep -q '/etc/polkit-1/rules.d/70-hardware-peripherals.rules' "$FIRSTBOOT" &&
   grep -q 'desktop-polkit-policy' "$FIRSTBOOT" &&
   grep -q 'polkit_policy_invalid=true' "$FIRSTBOOT"; then
  pass "first-boot validation checks the staged desktop polkit policy"
else
  fail "first-boot validation checks the staged desktop polkit policy"
fi
