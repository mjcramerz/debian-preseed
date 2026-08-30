#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/labwc-remote-desktop.XXXXXX")
trap 'rm -rf "$TMP_DIR"' EXIT HUP INT TERM

TEST_COUNT=5
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

desktop_class="$ROOT_DIR/d-i/forky/classes/class-select/role/desktop.cfg"
labwc_rc="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/labwc/rc.xml.tmpl"
computer_management="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-computer-management"
computer_desktop="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/share/applications/computer-management.desktop"
rdp_helper="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-remote-desktop"
rdp_askpass="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-freerdp-askpass"
rdp_desktop="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/share/applications/remote-desktop-management.desktop"
desktop_components="$ROOT_DIR/d-i/forky/scripts/desktop/components.sh"
desktop_verify="$ROOT_DIR/d-i/forky/scripts/desktop/verify.sh"
firstboot_validation="$ROOT_DIR/d-i/forky/scripts/firstboot/04-validation.sh"

printf '1..%s\n' "$TEST_COUNT"

if grep -Eq '(^|[[:space:]])freerdp-sdl([[:space:]]|$)' "$desktop_class" &&
   ! grep -Eq '(^|[[:space:]])freerdp3-sdl([[:space:]]|$)' "$desktop_class" &&
   ! grep -Eq '(^|[[:space:]])freerdp-wayland([[:space:]]|$)' "$desktop_class" &&
   ! grep -Eq '(^|[[:space:]])freerdp3-wayland([[:space:]]|$)' "$desktop_class" &&
   grep -q '<keybind key="W-m">' "$labwc_rc" &&
   grep -q '<keybind key="C-A-m">' "$labwc_rc" &&
   grep -q 'command="labwc-computer-management"' "$labwc_rc" &&
   ! grep -q '<keybind key="C-W-r">' "$labwc_rc" &&
   grep -q '" Remote Desktop"' "$computer_management" &&
   grep -q 'run_command labwc-remote-desktop' "$computer_management" &&
   grep -q '^Name=Computer Management$' "$computer_desktop" &&
   grep -q '^Exec=/usr/local/bin/labwc-computer-management$' "$computer_desktop" &&
   grep -q '^Name=Remote Desktop Connection$' "$rdp_desktop" &&
   grep -q '^Exec=/usr/local/bin/labwc-remote-desktop$' "$rdp_desktop" &&
   grep -q '^NoDisplay=true$' "$rdp_desktop" &&
   grep -q '^Categories=Network;RemoteAccess;$' "$rdp_desktop" &&
   { ! command -v desktop-file-validate >/dev/null 2>&1 ||
     desktop-file-validate "$computer_desktop"; } &&
   { ! command -v desktop-file-validate >/dev/null 2>&1 ||
     desktop-file-validate "$rdp_desktop"; }; then
  pass "Computer Management exposes RDP while the MIME helper stays hidden"
else
  fail "Computer Management exposes RDP while the MIME helper stays hidden"
fi

if grep -q 'usr/local/bin/labwc-computer-management /usr/local/bin/labwc-computer-management 0755' "$desktop_components" &&
   grep -q 'usr/share/applications/computer-management.desktop /usr/share/applications/computer-management.desktop 0644' "$desktop_components" &&
   grep -q 'usr/local/bin/labwc-remote-desktop /usr/local/bin/labwc-remote-desktop 0755' "$desktop_components" &&
   grep -q 'usr/local/bin/labwc-freerdp-askpass /usr/local/bin/labwc-freerdp-askpass 0755' "$desktop_components" &&
   grep -q 'usr/share/applications/remote-desktop-management.desktop /usr/share/applications/remote-desktop-management.desktop 0644' "$desktop_components" &&
   grep -q '/usr/local/bin/labwc-remote-desktop' "$desktop_verify" &&
   grep -q '/usr/local/bin/labwc-freerdp-askpass' "$desktop_verify" &&
   grep -q '/usr/share/applications/computer-management.desktop' "$desktop_verify" &&
   grep -q '/usr/share/applications/remote-desktop-management.desktop' "$desktop_verify" &&
   grep -q 'labwc-computer-management' "$firstboot_validation" &&
   grep -q 'labwc-remote-desktop' "$firstboot_validation" &&
   grep -q 'labwc-freerdp-askpass' "$firstboot_validation" &&
   grep -q 'sdl-freerdp3' "$rdp_helper" &&
   grep -Fq 'environment["SDL_VIDEODRIVER"] = "wayland"' "$rdp_helper" &&
   grep -Fq 'environment.pop("DISPLAY", None)' "$rdp_helper"; then
  pass "desktop staging and validation require the managed SDL3 Wayland RDP boundary"
else
  fail "desktop staging and validation require the managed SDL3 Wayland RDP boundary"
fi

rdp_labels_ok=true
for label in \
  'Connect to Target (Direct)' \
  'Connect to Target (Shared)' \
  'Select Saved Connection' \
  'Save Connection (Direct)' \
  'Save Connection (Shared)' \
  'Edit Saved Connection' \
  'Delete Saved Connection' \
  'Open Saved Connections Folder' \
  'Show FreeRDP Help'
do
  grep -Fq "\"${label}\"" "$rdp_helper" || rdp_labels_ok=false
done
if [ "$rdp_labels_ok" = true ] &&
   grep -q '"Multi-monitor full screen"' "$rdp_helper" &&
   grep -q '"Microphone redirection"' "$rdp_helper" &&
   grep -q '"Printer redirection"' "$rdp_helper" &&
   grep -q '"Administrative console session"' "$rdp_helper" &&
   grep -q '"Ask before trusting the remote certificate (recommended)"' "$rdp_helper" &&
   ! grep -q '"Trust on first use (recommended)"' "$rdp_helper" &&
   ! grep -q '"Reset Last Failed Certificate"' "$rdp_helper" &&
   ! grep -q 'snapshot_freerdp_certificate_files' "$rdp_helper" &&
   grep -Fq 'if not output_lines or not output_lines[0].strip():' "$rdp_helper" &&
   ! grep -Eq -- '--(width|lines)=' "$rdp_helper"; then
  pass "RDP launcher delegates remote certificate approval to the SDL client"
else
  fail "RDP launcher exposes direct, shared, saved, display, device, and certificate actions"
fi

if PYTHONPYCACHEPREFIX="$TMP_DIR/pycache" python3 -m py_compile "$rdp_helper" "$rdp_askpass" &&
   python3 - "$rdp_helper" "$TMP_DIR" <<'PY'
import contextlib
import importlib.machinery
import io
import os
import pathlib
import stat
import sys
import types

script_path = sys.argv[1]
temp_root = pathlib.Path(sys.argv[2])
home = temp_root / "home"
config_home = home / ".config"
share = home / "Shared"
share.mkdir(parents=True)
os.environ["HOME"] = str(home)
os.environ["USER"] = "tester"
os.environ["XDG_CONFIG_HOME"] = str(config_home)
os.environ.pop("DBUS_SESSION_BUS_ADDRESS", None)

loader = importlib.machinery.SourceFileLoader("labwc_remote_desktop", script_path)
module = types.ModuleType(loader.name)
loader.exec_module(module)
module.pwd.getpwuid = lambda uid: types.SimpleNamespace(pw_name="tester", pw_dir=str(home))
module.REMOVABLE_MEDIA_ROOT = temp_root / "run-media"

runtime_dir = temp_root / "runtime"
runtime_dir.mkdir()
wayland_socket_path = runtime_dir / "wayland-0"
os.environ["XDG_SESSION_TYPE"] = "wayland"
os.environ["XDG_RUNTIME_DIR"] = str(runtime_dir)
os.environ["WAYLAND_DISPLAY"] = wayland_socket_path.name
os.environ["DISPLAY"] = ":1"
original_stat = module.os.stat

def fake_wayland_stat(path, *args, **kwargs):
    if path == str(wayland_socket_path) and not args and not kwargs:
        return types.SimpleNamespace(st_mode=stat.S_IFSOCK)
    return original_stat(path, *args, **kwargs)

module.os.stat = fake_wayland_stat
try:
    module.require_wayland_session()
finally:
    module.os.stat = original_stat

direct = module.validate_profile(
    {
        "name": "office",
        "host": "rdp.example.com",
        "port": 3389,
        "username": "tester",
        "domain": "EXAMPLE",
        "share_path": "",
        "display_mode": "dynamic",
        "width": 1600,
        "height": 900,
        "network": "auto",
        "audio_mode": "0",
        "clipboard": True,
        "microphone": False,
        "printer": False,
        "admin": False,
        "certificate": "prompt",
    }
)
direct_command = module.build_freerdp_command(direct)
assert module.PROFILE_VERSION == 2
assert "/from-stdin:force" in direct_command
assert "+force-console-callbacks" not in direct_command
assert not any(argument.startswith("/cert:") for argument in direct_command)
assert "/auth-pkg-list:!kerberos,!u2u" not in direct_command
assert "+dynamic-resolution" in direct_command
assert "/smart-sizing" not in direct_command
assert "/clipboard:direction-to:all,files-to:all" in direct_command
assert "/v:rdp.example.com:3389" in direct_command
assert not any(argument.startswith("/port:") for argument in direct_command)
assert not any(argument.startswith("/p:") for argument in direct_command)
assert not any(argument.startswith("/drive:") for argument in direct_command)
assert module.FREERDP_EXECUTABLE == "sdl-freerdp"
assert module.FREERDP_EXECUTABLE_CANDIDATES == ("sdl-freerdp", "sdl-freerdp3")
assert module.FREERDP_ASKPASS_HELPER == "/usr/local/bin/labwc-freerdp-askpass"
os.environ["HOME"] = "/etc"
os.environ["USER"] = "spoofed"
assert module.desktop_home() == home.resolve()
assert module.desktop_username() == "tester"
assert module.validate_share_path("~") == str(home.resolve())
authorized_media_share = module.REMOVABLE_MEDIA_ROOT / "tester" / "Shared"
authorized_media_share.mkdir(parents=True)
spoofed_media_share = module.REMOVABLE_MEDIA_ROOT / "spoofed" / "Shared"
spoofed_media_share.mkdir(parents=True)
assert module.validate_share_path(str(authorized_media_share)) == str(authorized_media_share)
with contextlib.redirect_stderr(io.StringIO()):
    try:
        module.validate_share_path(str(spoofed_media_share))
    except SystemExit as exc:
        assert exc.code == 1
    else:
        raise AssertionError("spoofed USER media root was accepted")
windowed = dict(direct)
windowed["display_mode"] = "window"
windowed_command = module.build_freerdp_command(windowed)
assert "+dynamic-resolution" not in windowed_command
assert "/smart-sizing" in windowed_command
local_account = dict(direct)
local_account["domain"] = ""
local_account_command = module.build_freerdp_command(local_account)
assert not any(argument.startswith("/d:") for argument in local_account_command)
assert "/auth-pkg-list:!kerberos,!u2u" in local_account_command

original_run = module.subprocess.run
original_validate_askpass = module.validate_askpass_helper
original_which = module.shutil.which
original_notify = module.notify
original_run_fuzzel = module.run_fuzzel
captured_process = {}
captured_fuzzel = {}

def fake_back_run(argv, **kwargs):
    captured_fuzzel["argv"] = list(argv)
    captured_fuzzel["kwargs"] = kwargs
    return types.SimpleNamespace(returncode=0, stdout="\n")

module.subprocess.run = fake_back_run
module.shutil.which = lambda executable: f"/usr/bin/{executable}"
assert module.run_fuzzel("Remote Desktop Management", ["Show FreeRDP Help"]) is None
assert not any(argument.startswith("--width=") for argument in captured_fuzzel["argv"])
assert not any(argument.startswith("--lines=") for argument in captured_fuzzel["argv"])

def fake_run(argv, **kwargs):
    captured_process["argv"] = argv
    captured_process["kwargs"] = kwargs
    return types.SimpleNamespace(returncode=0)

module.subprocess.run = fake_run
module.validate_askpass_helper = lambda: None
module.shutil.which = lambda executable: None if executable == "sdl-freerdp" else f"/usr/bin/{executable}"
module.os.stat = fake_wayland_stat
try:
    module.run_encoded_connection(module.encode_profile(direct))
finally:
    module.os.stat = original_stat
assert captured_process["argv"][0] == "/usr/bin/sdl-freerdp3"
assert "/v:rdp.example.com:3389" in captured_process["argv"]
assert not any(argument.startswith("/port:") for argument in captured_process["argv"])
assert "/from-stdin:force" in captured_process["argv"]
assert "+force-console-callbacks" not in captured_process["argv"]
assert captured_process["kwargs"]["env"]["SDL_VIDEODRIVER"] == "wayland"
assert captured_process["kwargs"]["env"]["FREERDP_ASKPASS"] == "/usr/local/bin/labwc-freerdp-askpass"
assert "DISPLAY" not in captured_process["kwargs"]["env"]
assert captured_process["kwargs"]["stdin"] is module.subprocess.DEVNULL
assert module.connection_log_path().stat().st_mode & 0o777 == 0o600
module.subprocess.run = original_run
module.validate_askpass_helper = original_validate_askpass
module.shutil.which = original_which

shared = dict(direct)
shared.update(
    {
        "name": "lab",
        "share_path": str(share),
        "display_mode": "multimon",
        "width": 0,
        "height": 0,
        "clipboard": False,
        "microphone": True,
        "printer": True,
        "admin": True,
        "certificate": "deny",
    }
)
shared = module.validate_profile(shared)
shared_command = module.build_freerdp_command(shared)
assert f"/drive:Shared,{share}" in shared_command
assert "/multimon:force" in shared_command
assert "/f" in shared_command
assert "/microphone" in shared_command
assert "/printer" in shared_command
assert "/admin" in shared_command
assert "/cert:deny" in shared_command
assert "/v:rdp.example.com:3389" in shared_command
assert "/auth-pkg-list:!kerberos,!u2u" not in shared_command
assert "/clipboard:direction-to:off,files-to:off" in shared_command

module.save_profiles([direct, shared])
loaded = module.load_profiles()
assert [profile["name"] for profile in loaded] == ["office", "lab"]
store = module.profile_store_path()
assert stat.S_IMODE(store.stat().st_mode) == 0o600
assert stat.S_IMODE(store.parent.stat().st_mode) == 0o700
assert module.decode_profile(module.encode_profile(shared)) == shared

offline_share = home / "OfflineShare"
offline = dict(shared)
offline["name"] = "offline"
offline["share_path"] = str(offline_share)
module.save_profiles([direct, offline])
loaded = module.load_profiles()
assert [profile["name"] for profile in loaded] == ["office", "offline"]
with contextlib.redirect_stderr(io.StringIO()):
    try:
        module.build_freerdp_command(loaded[1])
    except SystemExit as exc:
        assert exc.code == 1
    else:
        raise AssertionError("offline shared folder was accepted for connection")
offline_share.mkdir()
assert f"/drive:Shared,{offline_share}" in module.build_freerdp_command(loaded[1])

action_calls = []
module.connect_temporary = lambda shared: action_calls.append(("temporary", shared))
module.connect_saved = lambda: action_calls.append(("saved",))
module.save_connection = lambda shared: action_calls.append(("save", shared))
module.edit_connection = lambda: action_calls.append(("edit",))
module.delete_connection = lambda: action_calls.append(("delete",))
module.open_profile_directory = lambda: action_calls.append(("open",))
module.show_help = lambda: action_calls.append(("help",))
expected_actions = {
    "Connect to Target (Direct)": ("temporary", False),
    "Connect to Target (Shared)": ("temporary", True),
    "Select Saved Connection": ("saved",),
    "Save Connection (Direct)": ("save", False),
    "Save Connection (Shared)": ("save", True),
    "Edit Saved Connection": ("edit",),
    "Delete Saved Connection": ("delete",),
    "Open Saved Connections Folder": ("open",),
    "Show FreeRDP Help": ("help",),
}
for action, expected_call in expected_actions.items():
    module.run_fuzzel = lambda prompt, choices, selected=action: selected
    module.main_menu()
    assert action_calls.pop(0) == expected_call
assert not action_calls

module.subprocess.run = original_run
module.validate_askpass_helper = original_validate_askpass
module.shutil.which = original_which
module.notify = original_notify
module.run_fuzzel = original_run_fuzzel
PY
then
  pass "RDP actions dispatch correctly and profiles enforce shares at connection time"
else
  fail "RDP actions dispatch correctly and profiles enforce shares at connection time"
fi

if python3 - "$rdp_helper" "$TMP_DIR" <<'PY' >/dev/null 2>&1
import importlib.machinery
import os
import pathlib
import sys
import types

script_path = sys.argv[1]
temp_root = pathlib.Path(sys.argv[2])
home = temp_root / "negative-home"
home.mkdir()
os.environ["HOME"] = str(home)
os.environ["USER"] = "tester"
os.environ.pop("DBUS_SESSION_BUS_ADDRESS", None)

loader = importlib.machinery.SourceFileLoader("labwc_remote_desktop_negative", script_path)
module = types.ModuleType(loader.name)
loader.exec_module(module)
module.pwd.getpwuid = lambda uid: types.SimpleNamespace(pw_name="tester", pw_dir=str(home))
module.REMOVABLE_MEDIA_ROOT = temp_root / "run-media"

try:
    module.validate_share_path("/etc")
except SystemExit as exc:
    assert exc.code == 1
else:
    raise AssertionError("shared folder outside HOME or /run/media was accepted")

bad = {
    "name": "bad",
    "host": "rdp.example.com",
    "port": 3389,
    "username": "tester",
    "domain": "",
    "share_path": "",
    "display_mode": "window",
    "width": 639,
    "height": 900,
    "network": "auto",
    "audio_mode": "0",
    "clipboard": True,
    "microphone": False,
    "printer": False,
    "admin": False,
    "certificate": "prompt",
}
try:
    module.validate_profile(bad)
except SystemExit as exc:
    assert exc.code == 1
else:
    raise AssertionError("out-of-range RDP width was accepted")
PY
then
  pass "RDP validation rejects folder disclosure outside approved roots and invalid dimensions"
else
  fail "RDP validation rejects folder disclosure outside approved roots and invalid dimensions"
fi
