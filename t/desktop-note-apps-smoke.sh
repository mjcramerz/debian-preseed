#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/desktop-note-apps-smoke.XXXXXX")
trap 'rm -rf "$TMP_DIR"' EXIT HUP INT TERM

TEST_COUNT=12
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

desktop_cfg="$ROOT_DIR/d-i/forky/classes/class-select/role/desktop.cfg"
components="$ROOT_DIR/d-i/forky/scripts/desktop/components.sh"
desktop_verify="$ROOT_DIR/d-i/forky/scripts/desktop/verify.sh"
firstboot_validate="$ROOT_DIR/d-i/forky/scripts/firstboot/04-validation.sh"
common_lib="$ROOT_DIR/d-i/forky/scripts/common/lib.sh"
menu_xml="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/labwc/menu.xml"
xournal_settings="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/xournalpp/settings.xml.tmpl"
gnote_addins="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/gnote/addins/global.ini"
gnote_schema="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/share/glib-2.0/schemas/90-desktop-gnote.gschema.override.tmpl"
liferea_schema="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/share/glib-2.0/schemas/90-desktop-liferea.gschema.override"
user_mimeapps="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/mimeapps.list"
system_mimeapps="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/xdg/mimeapps.list"
xournal_override="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/share/applications/com.github.xournalpp.xournalpp.desktop"
gnote_override="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/share/applications/org.gnome.Gnote.desktop"

if grep -Eq '(^|[[:space:]])xournalpp([[:space:]]|$)' "$desktop_cfg" &&
   grep -Eq '(^|[[:space:]])gnote([[:space:]]|$)' "$desktop_cfg" &&
   grep -Eq '(^|[[:space:]])liferea([[:space:]]|$)' "$desktop_cfg"; then
  pass "desktop role installs Xournal++, Gnote, and Liferea in the managed package baseline"
else
  fail "desktop role installs Xournal++, Gnote, and Liferea in the managed package baseline"
fi

if grep -q '^desktop_render_note_app_defaults() {$' "$components" &&
   grep -q '^desktop_compile_glib_schemas() {$' "$components" &&
   grep -q '/etc/skel/.config/xournalpp/settings.xml' "$components" &&
   grep -q '/etc/skel/.config/gnote/addins/global.ini' "$components" &&
   grep -q '/usr/share/glib-2.0/schemas/90-desktop-gnote.gschema.override' "$components" &&
   grep -q '/usr/share/glib-2.0/schemas/90-desktop-liferea.gschema.override' "$components" &&
   ! grep -q '/usr/local/share/applications' "$components" &&
   grep -q '\.config/gnote \\' "$components" &&
   grep -q '\.config/xournalpp \\' "$components"; then
  pass "desktop components stage note-app configuration without installing launcher overrides"
else
  fail "desktop components stage note-app configuration without installing launcher overrides"
fi

if grep -q '  gnote \\' "$desktop_verify" &&
   grep -q '  liferea \\' "$desktop_verify" &&
   grep -q '  xournalpp \\' "$desktop_verify" &&
   grep -q '/etc/skel/.config/gnote/addins/global.ini' "$desktop_verify" &&
   grep -q '/etc/skel/.config/xournalpp/settings.xml' "$desktop_verify" &&
   grep -q '/usr/share/applications/com.github.xournalpp.xournalpp.desktop' "$desktop_verify" &&
   grep -q '/usr/share/applications/org.gnome.Gnote.desktop' "$desktop_verify" &&
   grep -q '/usr/share/glib-2.0/schemas/90-desktop-gnote.gschema.override' "$desktop_verify" &&
   grep -q '/usr/share/glib-2.0/schemas/90-desktop-liferea.gschema.override' "$desktop_verify" &&
   grep -q '  gnote \\' "$firstboot_validate" &&
   grep -q '    liferea \\' "$firstboot_validate" &&
   grep -q '  xournalpp \\' "$firstboot_validate"; then
  pass "desktop and firstboot validation surfaces both cover the note-taking apps"
else
  fail "desktop and firstboot validation surfaces both cover the note-taking apps"
fi

if grep -q 'label="Notes" icon="org.gnome.Gnote"' "$menu_xml" &&
   grep -q 'command="gnote"' "$menu_xml" &&
   grep -q 'label="Handwritten Notes" icon="com.github.xournalpp.xournalpp"' "$menu_xml" &&
   grep -q 'command="xournalpp"' "$menu_xml" &&
   grep -q 'label="Feed Reader" icon="net.sourceforge.liferea"' "$menu_xml" &&
   grep -q 'command="liferea"' "$menu_xml"; then
  pass "Labwc menu exposes first-class launchers for Gnote and Xournal++"
else
  fail "Labwc menu exposes first-class launchers for Gnote and Xournal++"
fi

if [ ! -e "$xournal_override" ] &&
   [ ! -e "$gnote_override" ] &&
   ! grep -q 'usr/local/share/applications/com.github.xournalpp.xournalpp.desktop' "$components" &&
   ! grep -q 'usr/local/share/applications/org.gnome.Gnote.desktop' "$components"; then
  pass "desktop role relies on package-provided launchers for both note apps"
else
  fail "desktop role relies on package-provided launchers for both note apps"
fi

if grep -q 'autosaveEnabled" value="true"' "$xournal_settings" &&
   grep -q 'autosaveTimeout" value="3"' "$xournal_settings" &&
   grep -q 'themeVariant" value="useSystem"' "$xournal_settings" &&
   grep -q 'lastSavePath" value="__INSTALLER_DIR_HOME_DOCUMENTS__"' "$xournal_settings" &&
   grep -q 'lastImagePath" value="__INSTALLER_DIR_HOME_PICTURES__"' "$xournal_settings" &&
   grep -q 'pageTemplate" value="xoj/template' "$xournal_settings"; then
  pass "Xournal++ template keeps autosave, system theming, and document-root defaults"
else
  fail "Xournal++ template keeps autosave, system theming, and document-root defaults"
fi

xournal_rendered="$TMP_DIR/xournal-settings.xml"
if (
  set -eu
  # shellcheck disable=SC1090
  . "$common_lib"
  installer_apply_scalar_placeholders \
    "$xournal_settings" \
    "$xournal_rendered" \
    DIR_HOME_DOCUMENTS /home/testuser/Documents \
    DIR_HOME_PICTURES /home/testuser/Pictures \
    LABWC_GTK_FONT_SIZE 12
  ! grep -q '__INSTALLER_' "$xournal_rendered"
  python3 - "$xournal_rendered" <<'PY'
import sys
import xml.etree.ElementTree as ET
tree = ET.parse(sys.argv[1])
root = tree.getroot()
props = {node.attrib["name"]: node.attrib.get("value", "") for node in root.findall("property")}
assert root.tag == "settings"
assert props["lastSavePath"] == "/home/testuser/Documents"
assert props["lastImagePath"] == "/home/testuser/Pictures"
assert props["autosaveEnabled"] == "true"
assert props["defaultSaveName"] == "%F-Xournalpp-%H-%M"
PY
); then
  pass "Xournal++ template renders cleanly and remains valid XML after placeholder substitution"
else
  fail "Xournal++ template renders cleanly and remains valid XML after placeholder substitution"
fi

if grep -q "^color-scheme='dark'$" "$gnote_schema" &&
   grep -q "^note-rename-behavior=2$" "$gnote_schema" &&
   grep -q "^editor-tab-width=4$" "$gnote_schema" &&
   grep -q "^last-directory='__INSTALLER_DIR_HOME_DOCUMENTS__'$" "$gnote_schema" &&
   grep -q "^format='%Y-%m-%d %H:%M'$" "$gnote_schema"; then
  pass "Gnote schema override forces the managed theme, rename policy, export root, and timestamp format"
else
  fail "Gnote schema override forces the managed theme, rename policy, export root, and timestamp format"
fi

gnote_rendered="$TMP_DIR/90-desktop-gnote.gschema.override"
if (
  set -eu
  # shellcheck disable=SC1090
  . "$common_lib"
  installer_apply_scalar_placeholders \
    "$gnote_schema" \
    "$gnote_rendered" \
    DIR_HOME_DOCUMENTS /home/testuser/Documents \
    LABWC_GTK_FONT_SIZE 12
  ! grep -q '__INSTALLER_' "$gnote_rendered"
  grep -q "^last-directory='/home/testuser/Documents'$" "$gnote_rendered"
  grep -q "^custom-font-face='Noto Sans 12'$" "$gnote_rendered"
); then
  pass "Gnote schema override renders fully for the target account paths and font policy"
else
  fail "Gnote schema override renders fully for the target account paths and font policy"
fi

if grep -q '^ExportToHtmlAddin=true$' "$gnote_addins" &&
   grep -q '^InsertTimestampAddin=true$' "$gnote_addins" &&
   grep -q '^NoteDirectoryWatcherAddin=true$' "$gnote_addins" &&
   grep -q '^SpecialNotesAddin=true$' "$gnote_addins" &&
   grep -q '^TableofcontentsAddin=true$' "$gnote_addins" &&
   grep -q '^FileSystemSyncServiceAddin=true$' "$gnote_addins" &&
   grep -q '^WebDavSyncServiceAddin=true$' "$gnote_addins"; then
  pass "Gnote addin defaults enable the managed authoring, export, and sync-friendly plugin set"
else
  fail "Gnote addin defaults enable the managed authoring, export, and sync-friendly plugin set"
fi

if grep -q '^\[net.sf.liferea\]$' "$liferea_schema" &&
   grep -q "^browser-id='default'$" "$liferea_schema" &&
   grep -q '^browse-inside-application=false$' "$liferea_schema" &&
   grep -q '^default-update-interval=60$' "$liferea_schema" &&
   grep -q '^disable-javascript=true$' "$liferea_schema" &&
   grep -q '^do-not-track=true$' "$liferea_schema" &&
   grep -q '^do-not-sell=true$' "$liferea_schema" &&
   grep -q '^enable-itp=true$' "$liferea_schema" &&
   grep -q '^enable-reader-mode=true$' "$liferea_schema" &&
   grep -q '^maxitemcount=500$' "$liferea_schema" &&
   grep -q '^application/rss+xml=net.sourceforge.liferea.desktop;$' "$user_mimeapps" &&
   grep -q '^application/atom+xml=net.sourceforge.liferea.desktop;$' "$user_mimeapps" &&
   grep -q '^x-scheme-handler/feed=net.sourceforge.liferea.desktop;$' "$user_mimeapps" &&
   ! grep -q '^application/rss+xml=' "$system_mimeapps" &&
   ! grep -q '^x-scheme-handler/feed=' "$system_mimeapps"; then
  pass "Liferea defaults use the system browser, privacy protections, hourly refreshes, and primary-user feed handlers"
else
  fail "Liferea defaults use the system browser, privacy protections, hourly refreshes, and primary-user feed handlers"
fi

if grep -q 'find /usr/lib -path ".*/glib-2.0/glib-compile-schemas"' "$components" &&
   grep -q 'glib-compile-schemas is unavailable in target' "$components"; then
  pass "desktop schema compilation has a guarded fallback when glib-compile-schemas is not on PATH"
else
  fail "desktop schema compilation has a guarded fallback when glib-compile-schemas is not on PATH"
fi

[ "$FAIL_COUNT" -eq 0 ]
