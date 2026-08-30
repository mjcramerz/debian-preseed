#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)

TEST_COUNT=4
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

user_mimeapps="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/mimeapps.list"
system_mimeapps="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/xdg/mimeapps.list"
desktop_class="$ROOT_DIR/d-i/forky/classes/class-select/role/desktop.cfg"
software_class="$ROOT_DIR/d-i/forky/classes/class-addon/software.cfg"
tuta_desktop="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/share/applications/tuta-mail.desktop"
terminal_list="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/xdg-terminals.list"
mime_types="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/share/mime/packages/90-desktop-filetypes.xml"
desktop_components="$ROOT_DIR/d-i/forky/scripts/desktop/components.sh"
desktop_verify="$ROOT_DIR/d-i/forky/scripts/desktop/verify.sh"
launcher_sync="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-sync-application-launchers"

if ! cmp -s "$user_mimeapps" "$system_mimeapps" &&
   grep -Fq 'etc/skel/.config/mimeapps.list /etc/skel/.config/mimeapps.list 0600' "$desktop_components" &&
   grep -Fq 'file_mode=0600' "$desktop_components" &&
   grep -Fq 'MANAGED_DIRECTORY_MODE = 0o700' "$launcher_sync" &&
   grep -Fq 'MANAGED_FILE_MODE = 0o600' "$launcher_sync" &&
   python3 - "$user_mimeapps" "$system_mimeapps" <<'PY' >/dev/null 2>&1
import configparser
import sys

def load(path):
    parser = configparser.ConfigParser(interpolation=None, strict=True)
    parser.optionxform = str
    with open(path, encoding="utf-8") as handle:
        parser.read_file(handle)
    assert parser.sections() == ["Default Applications", "Added Associations"]
    assert dict(parser["Default Applications"]) == dict(parser["Added Associations"])
    return dict(parser["Default Applications"])

user_defaults = load(sys.argv[1])
system_defaults = load(sys.argv[2])
expected_system_defaults = {
    "inode/directory": "thunar.desktop;",
    "application/x-directory": "thunar.desktop;",
    "x-directory/normal": "thunar.desktop;",
    "x-scheme-handler/file": "thunar.desktop;",
}
assert system_defaults == expected_system_defaults
assert all(user_defaults[mime_type] == desktop_ids for mime_type, desktop_ids in system_defaults.items())
PY
then
  pass "system MIME policy stays minimal while the primary-user policy remains comprehensive"
else
  fail "system MIME policy stays minimal while the primary-user policy remains comprehensive"
fi

if python3 - "$user_mimeapps" <<'PY' >/dev/null 2>&1
import collections
import configparser
import sys

expected = {
    "inode/directory": "thunar.desktop;",
    "text/html": "vivaldi-stable.desktop;chromium.desktop;microsoft-edge.desktop;",
    "image/svg+xml": "vivaldi-stable.desktop;chromium.desktop;microsoft-edge.desktop;",
    "x-scheme-handler/https": "vivaldi-stable.desktop;chromium.desktop;microsoft-edge.desktop;",
    "x-scheme-handler/mailto": "tuta-mail.desktop;",
    "message/rfc822": "tuta-mail.desktop;",
    "application/pdf": "org.pwmt.zathura.desktop;com.github.xournalpp.xournalpp.desktop;",
    "application/x-xopp": "com.github.xournalpp.xournalpp.desktop;",
    "image/png": "qimgv.desktop;",
    "text/plain": "featherpad.desktop;",
    "application/x-desktop": "featherpad.desktop;",
    "text/x-systemd-unit": "featherpad.desktop;",
    "application/json": "featherpad.desktop;",
    "application/x-shellscript": "featherpad.desktop;",
    "application/yaml": "featherpad.desktop;",
    "application/xml": "featherpad.desktop;",
    "text/x-csrc": "featherpad.desktop;",
    "text/x-diff": "featherpad.desktop;",
    "application/x-subrip": "featherpad.desktop;",
    "application/vnd.oasis.opendocument.text": "focuswriter.desktop;",
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document": "focuswriter.desktop;",
    "application/rtf": "focuswriter.desktop;",
    "application/x-gnumeric": "org.gnumeric.gnumeric.desktop;",
    "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet": "org.gnumeric.gnumeric.desktop;",
    "text/csv": "org.gnumeric.gnumeric.desktop;sqlitebrowser.desktop;",
    "audio/flac": "mpv.desktop;",
    "audio/m3u": "mpv.desktop;",
    "video/mp4": "mpv.desktop;",
    "video/webm": "mpv.desktop;",
    "application/x-7z-compressed": "xarchiver.desktop;",
    "application/gzip": "xarchiver.desktop;",
    "application/vnd.appimage": "xarchiver.desktop;",
    "application/vnd.debian.binary-package": "xarchiver.desktop;",
    "application/x-cd-image": "xarchiver.desktop;",
    "application/x-tar": "xarchiver.desktop;",
    "application/zip": "xarchiver.desktop;",
    "application/rss+xml": "net.sourceforge.liferea.desktop;",
    "x-scheme-handler/feed": "net.sourceforge.liferea.desktop;",
    "application/x-rdp": "sdl-freerdp-file.desktop;",
    "x-scheme-handler/rdp": "sdl-freerdp-file.desktop;",
    "application/vnd.sqlite3": "sqlitebrowser.desktop;",
    "application/x-keepass2": "org.keepassxc.KeePassXC.desktop;",
    "application/x-bittorrent": "org.qbittorrent.qBittorrent.desktop;",
    "x-scheme-handler/magnet": "org.qbittorrent.qBittorrent.desktop;",
    "application/x-code-workspace": "code.desktop;",
    "x-scheme-handler/terminal": "foot.desktop;",
}

parser = configparser.ConfigParser(interpolation=None, strict=True)
parser.optionxform = str
with open(sys.argv[1], encoding="utf-8") as handle:
    parser.read_file(handle)
defaults = dict(parser["Default Applications"])
for mime_type, desktop_ids in expected.items():
    assert defaults[mime_type] == desktop_ids

expected_handler_counts = {
    "thunar.desktop;": 4,
    "vivaldi-stable.desktop;chromium.desktop;microsoft-edge.desktop;": 10,
    "tuta-mail.desktop;": 2,
    "org.pwmt.zathura.desktop;com.github.xournalpp.xournalpp.desktop;": 1,
    "com.github.xournalpp.xournalpp.desktop;": 4,
    "qimgv.desktop;": 6,
    "featherpad.desktop;": 54,
    "focuswriter.desktop;": 5,
    "org.gnumeric.gnumeric.desktop;": 29,
    "org.gnumeric.gnumeric.desktop;sqlitebrowser.desktop;": 2,
    "mpv.desktop;": 76,
    "xarchiver.desktop;": 55,
    "net.sourceforge.liferea.desktop;": 5,
    "sdl-freerdp-file.desktop;": 2,
    "sqlitebrowser.desktop;": 7,
    "org.keepassxc.KeePassXC.desktop;": 1,
    "org.qbittorrent.qBittorrent.desktop;": 2,
    "code.desktop;": 1,
    "foot.desktop;": 2,
}
assert collections.Counter(defaults.values()) == expected_handler_counts
assert len(defaults) == 268
assert all(value.endswith(";") for value in defaults.values())
assert "text/calendar" not in defaults
assert all("ikhal.desktop" not in value for value in defaults.values())
PY
then
  pass "desktop MIME policy comprehensively covers installed file, document, media, archive, database, and URL handlers"
else
  fail "desktop MIME policy comprehensively covers installed file, document, media, archive, database, and URL handlers"
fi

if grep -Eq '(^|[[:space:]])thunar([[:space:]]|$)' "$desktop_class" &&
   grep -Eq '(^|[[:space:]])xarchiver([[:space:]]|$)' "$desktop_class" &&
   grep -Eq '(^|[[:space:]])mpv([[:space:]]|$)' "$desktop_class" &&
   grep -Eq '(^|[[:space:]])qimgv([[:space:]]|$)' "$desktop_class" &&
   grep -Eq '(^|[[:space:]])zathura([[:space:]]|$)' "$desktop_class" &&
   grep -Eq '(^|[[:space:]])xournalpp([[:space:]]|$)' "$desktop_class" &&
   grep -Eq '(^|[[:space:]])featherpad([[:space:]]|$)' "$desktop_class" &&
   grep -Eq '(^|[[:space:]])focuswriter([[:space:]]|$)' "$desktop_class" &&
   grep -Eq '(^|[[:space:]])gnumeric([[:space:]]|$)' "$desktop_class" &&
   grep -Eq '(^|[[:space:]])keepassxc([[:space:]]|$)' "$desktop_class" &&
   grep -Eq '(^|[[:space:]])foot([[:space:]]|$)' "$desktop_class" &&
   grep -Eq '(^|[[:space:]])liferea([[:space:]]|$)' "$desktop_class" &&
   grep -Eq '(^|[[:space:]])freerdp-sdl([[:space:]]|$)' "$desktop_class" &&
   grep -Eq '(^|[[:space:]])code([[:space:]]|$)' "$software_class" &&
   grep -Eq '(^|[[:space:]])microsoft-edge-stable([[:space:]]|$)' "$software_class" &&
   grep -Eq '(^|[[:space:]])vivaldi-stable([[:space:]]|$)' "$software_class" &&
   grep -Eq '(^|[[:space:]])qbittorrent([[:space:]]|$)' "$software_class" &&
   grep -Eq '(^|[[:space:]])sqlitebrowser([[:space:]]|$)' "$software_class" &&
   grep -q '"microsoft-edge.desktop"' "$launcher_sync" &&
   grep -q '"vivaldi-stable.desktop"' "$launcher_sync" &&
   grep -q '"code.desktop"' "$launcher_sync" &&
   grep -q '"org.keepassxc.KeePassXC.desktop"' "$launcher_sync" &&
   grep -q '"org.qbittorrent.qBittorrent.desktop"' "$launcher_sync" &&
   grep -q '^MimeType=x-scheme-handler/mailto;$' "$tuta_desktop" &&
   grep -q '^foot.desktop$' "$terminal_list"; then
  pass "every configured desktop ID is grounded in the selected package or managed launcher contract"
else
  fail "every configured desktop ID is grounded in the selected package or managed launcher contract"
fi

if python3 - "$mime_types" <<'PY' >/dev/null 2>&1
import sys
import xml.etree.ElementTree as ET

namespace = {"mime": "http://www.freedesktop.org/standards/shared-mime-info"}
root = ET.parse(sys.argv[1]).getroot()
types = {
    node.attrib["type"]: {
        glob.attrib["pattern"]
        for glob in node.findall("mime:glob", namespace)
    }
    for node in root.findall("mime:mime-type", namespace)
}
assert "*.rdp" in types["application/x-rdp"]
assert "*.sqlite" in types["application/vnd.sqlite3"]
PY
   grep -q 'usr/share/mime/packages/90-desktop-filetypes.xml /usr/share/mime/packages/90-desktop-filetypes.xml 0644' "$desktop_components" &&
   grep -q '/usr/bin/update-mime-database /usr/share/mime' "$desktop_components" &&
   grep -q '/usr/share/mime/packages/90-desktop-filetypes.xml' "$desktop_verify"; then
  pass "RDP and .sqlite filename extensions are registered before mimeapps defaults are applied"
else
  fail "RDP and .sqlite filename extensions are registered before mimeapps defaults are applied"
fi

[ "$FAIL_COUNT" -eq 0 ]
