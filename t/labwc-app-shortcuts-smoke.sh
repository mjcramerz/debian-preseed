#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)

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

labwc_rc="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/labwc/rc.xml.tmpl"
desktop_class="$ROOT_DIR/d-i/forky/classes/class-select/role/desktop.cfg"
software_class="$ROOT_DIR/d-i/forky/classes/class-addon/software.cfg"
managed_app="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-managed-app"
managed_app_profiles="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/lib/python3.14/dist-packages/labwc_managed_app/profiles.py"
software_helper="$ROOT_DIR/d-i/forky/scripts/late/software.sh"
wayscriber_toggle="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-wayscriber-toggle"
readme="$ROOT_DIR/README.md"
target_readme="$ROOT_DIR/d-i/forky/hooks/role/desktop/README.target.md"

if python3 - "$labwc_rc" <<'PY' >/dev/null 2>&1
import collections
import sys
import xml.etree.ElementTree as ET

expected = {
    "C-A-space": "labwc-run",
    "C-A-m": "labwc-computer-management",
    "W-m": "labwc-computer-management",
    "W-f": "thunar",
    "C-A-f": "thunar",
    "W-b": "/usr/local/bin/labwc-managed-app nvidia vivaldi",
    "C-A-b": "/usr/local/bin/labwc-managed-app nvidia vivaldi",
    "W-t": "labwc-terminal",
    "C-A-t": "labwc-terminal",
    "W-e": "/usr/local/bin/labwc-managed-app nvidia tutanota",
    "C-A-e": "/usr/local/bin/labwc-managed-app nvidia tutanota",
    "W-p": "/usr/local/bin/labwc-managed-app nvidia bitwarden",
    "C-A-p": "/usr/local/bin/labwc-managed-app nvidia bitwarden",
    "W-w": "labwc-wayscriber-toggle",
    "C-A-w": "labwc-wayscriber-toggle",
    "W-s": "/usr/local/bin/labwc-managed-app auto spotify",
    "C-A-s": "/usr/local/bin/labwc-managed-app auto spotify",
    "W-c": "qalculate-qt",
    "C-A-c": "qalculate-qt",
    "W-o": "/usr/local/bin/labwc-managed-app nvidia filen",
    "C-A-o": "/usr/local/bin/labwc-managed-app nvidia filen",
    "W-a": "__INSTALLER_LABWC_AUDIO_CONTROL_COMMAND__",
    "C-A-a": "__INSTALLER_LABWC_AUDIO_CONTROL_COMMAND__",
    "W-S-p": "labwc-power-menu",
    "W-S-o": "labwc-output-refresh",
}

root = ET.parse(sys.argv[1]).getroot()
xwayland_persistence = [
    node.text.strip()
    for node in root.iter()
    if node.tag.rsplit("}", 1)[-1] == "xwaylandPersistence" and node.text
]
assert xwayland_persistence == []
window_rules = [
    node.attrib
    for node in root.iter()
    if node.tag.rsplit("}", 1)[-1] == "windowRule"
]
assert window_rules == [
    {"identifier": "com.adrianbonpin.gridline", "serverDecoration": "yes"},
    {"identifier": "*", "serverDecoration": "yes"},
]
bindings = collections.defaultdict(list)
for node in root.iter():
    if node.tag.rsplit("}", 1)[-1] != "keybind":
        continue
    key = node.attrib.get("key")
    for action in node:
        if action.tag.rsplit("}", 1)[-1] != "action":
            continue
        command = action.attrib.get("command")
        if command:
            bindings[key].append(command)
        for child in action:
            if child.tag.rsplit("}", 1)[-1] == "command" and child.text:
                bindings[key].append(child.text.strip())

for key, command in expected.items():
    assert bindings[key] == [command]
PY
then
  pass "Labwc defaults managed application shortcuts to NVIDIA, preserves power/output bindings, and forces Gridline SSD"
else
  fail "Labwc defaults managed application shortcuts to NVIDIA, preserves power/output bindings, and forces Gridline SSD"
fi

if grep -Eq '(^|[[:space:]])thunar([[:space:]]|$)' "$desktop_class" &&
   grep -Eq '(^|[[:space:]])foot([[:space:]]|$)' "$desktop_class" &&
   grep -Eq '(^|[[:space:]])qalculate-qt([[:space:]]|$)' "$desktop_class" &&
   grep -Eq '(^|[[:space:]])wayscriber([[:space:]]|$)' "$desktop_class" &&
   grep -Eq '(^|[[:space:]])vivaldi-stable([[:space:]]|$)' "$software_class" &&
   grep -Eq '(^|[[:space:]])spotify-client([[:space:]]|$)' "$software_class" &&
   grep -Fq 'PACKAGE_DIRECTORY = PACKAGE_ROOT / "labwc_managed_app"' "$managed_app" &&
   grep -q '"vivaldi": {' "$managed_app_profiles" &&
   grep -q '"tutanota": {' "$managed_app_profiles" &&
   grep -q '"bitwarden": {' "$managed_app_profiles" &&
   grep -q '"filen": {' "$managed_app_profiles" &&
   grep -q '/opt/Bitwarden/bitwarden' "$software_helper" &&
   grep -q '/opt/Filen/Filen' "$software_helper" &&
   grep -q '/opt/tuta-mail/AppRun' "$managed_app_profiles" &&
   [ -x "$wayscriber_toggle" ]; then
  pass "shortcut commands are grounded in baseline packages or managed application launch contracts"
else
  fail "shortcut commands are grounded in baseline packages or managed application launch contracts"
fi

if grep -q '`Ctrl+Alt+F/B/T/E/P/W/S/C/O/A`' "$readme" &&
   grep -q '`Super+S` and `Ctrl+Alt+S` for Spotify' "$readme" &&
   grep -q '`Super+M` and `Ctrl+Alt+M` open' "$readme" &&
   grep -q '`Ctrl+Alt+Space` opens the Fuzzel application' "$readme" &&
   grep -q '`Super+Shift+P` and' "$readme" &&
   grep -q '`Super+Shift+O`' "$readme" &&
   grep -q '`Ctrl+Alt+F/B/T/E/P/W/S/C/O/A`' "$target_readme" &&
   grep -q '`Super+S` and `Ctrl+Alt+S` for Spotify' "$target_readme" &&
   grep -q '`Super+M` and `Ctrl+Alt+M` open' "$target_readme" &&
   grep -q '`Ctrl+Alt+Space` opens the Fuzzel application' "$target_readme" &&
   grep -q '`Super+Shift+P` and `Super+Shift+O`' "$target_readme"; then
  pass "desktop documentation records the original and alternate application shortcuts"
else
  fail "desktop documentation records the original and alternate application shortcuts"
fi

[ "$FAIL_COUNT" -eq 0 ]
