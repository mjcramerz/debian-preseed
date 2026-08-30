#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/qbittorrent-desktop-smoke.XXXXXX")
trap 'rm -rf "$TMP_DIR"' EXIT HUP INT TERM

TEST_COUNT=7
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

pkgsel_line() {
  sed -n 's/^d-i pkgsel\/include string //p' "$1" | head -n 1
}

word_list_has() {
  case " $1 " in
    *" $2 "*) return 0 ;;
  esac
  return 1
}

printf '1..%s\n' "$TEST_COUNT"

software_class="$ROOT_DIR/d-i/forky/classes/class-addon/software.cfg"
desktop_env="$ROOT_DIR/d-i/forky/hosts/profiles/btrfs/desktop.env"
f2fs_desktop_env="$ROOT_DIR/d-i/forky/hosts/profiles/f2fs/desktop.env"
desktop_detect="$ROOT_DIR/d-i/forky/scripts/desktop/detect.sh"
desktop_components="$ROOT_DIR/d-i/forky/scripts/desktop/components.sh"
desktop_defaults="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/default/labwc-desktop.tmpl"
desktop_verify="$ROOT_DIR/d-i/forky/scripts/desktop/verify.sh"
firstboot_validation="$ROOT_DIR/d-i/forky/scripts/firstboot/04-validation.sh"
launcher_sync="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-sync-application-launchers"
wrapper="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-qbittorrent"
security_script="$ROOT_DIR/d-i/forky/scripts/late/security.sh"
overlay="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/nftables/services/qbittorrent.yml"

software_packages=$(pkgsel_line "$software_class")
if word_list_has "$software_packages" qbittorrent; then
  pass "software addon installs qBittorrent"
else
  fail "software addon installs qBittorrent"
fi

if grep -q '^LABWC_QBITTORRENT_PORT="50309"$' "$desktop_env" &&
   grep -q '^LABWC_QBITTORRENT_PORT="50309"$' "$f2fs_desktop_env" &&
   grep -q '^LABWC_QBITTORRENT_USER=__INSTALLER_LABWC_QBITTORRENT_USER__$' "$desktop_defaults" &&
   grep -q '^LABWC_QBITTORRENT_ROOT=__INSTALLER_LABWC_QBITTORRENT_ROOT__$' "$desktop_defaults" &&
   grep -q 'LABWC_QBITTORRENT_USER "$(desktop_shell_config_value "$ACCOUNT_USERNAME")"' "$desktop_components" &&
   grep -q 'LABWC_QBITTORRENT_ROOT "$(desktop_shell_config_value "$qbittorrent_root")"' "$desktop_components" &&
   grep -q 'qbittorrent_root="/run/media/\${ACCOUNT_USERNAME}/bittorrent"' "$desktop_components" &&
   grep -q 'LABWC_QBITTORRENT_PORT "\${LABWC_QBITTORRENT_PORT:-50309}"' "$desktop_detect" &&
   grep -q 'desktop_stage_role_asset usr/local/bin/labwc-qbittorrent /usr/local/bin/labwc-qbittorrent 0755' "$desktop_components" &&
   grep -q 'labwc-qbittorrent' "$desktop_verify" &&
   grep -q 'labwc-qbittorrent' "$firstboot_validation" &&
   grep -q '"org.qbittorrent.qBittorrent.desktop"' "$launcher_sync" &&
   grep -q '"action_app": "qbittorrent"' "$launcher_sync" &&
   grep -q '"field_code": "%U"' "$launcher_sync" &&
   grep -q '"IntelAccelerated": ("intel", "IntelAccelerated")' "$launcher_sync" &&
   grep -q '"NvidiaAccelerated": ("nvidia", "NvidiaAccelerated")' "$launcher_sync"; then
  pass "desktop defaults and launcher wiring use the managed wrapper with GPU actions"
else
  fail "desktop defaults and launcher wiring use the managed wrapper with GPU actions"
fi

if grep -q '^nftables_software_selected() {$' "$security_script" &&
   grep -q 'installer_selected_class_reference_is_selected addon/software' "$security_script" &&
   grep -q 'nftables_merge_selected_services "$effective_services" qbittorrent' "$security_script" &&
   python3 - "$overlay" <<'PY'
from pathlib import Path
import sys
import yaml

overlay = yaml.safe_load(Path(sys.argv[1]).read_text(encoding="utf-8"))
assert overlay["metadata"]["applies_to_profiles"] == ["desktop"]
service = overlay["services"]["qbittorrent_incoming"]
assert service["protocols"] == ["tcp", "udp"]
assert service["ports"] == [50309]
assert "egress" not in overlay
PY
then
  pass "software selection auto-opens the fixed qBittorrent TCP and UDP peer port"
else
  fail "software selection auto-opens the fixed qBittorrent TCP and UDP peer port"
fi

if python3 - "$wrapper" "$TMP_DIR/config" <<'PY'
from pathlib import Path
import configparser
import runpy
import sys

module = runpy.run_path(sys.argv[1])
tmp = Path(sys.argv[2]).resolve()
missing = tmp / "missing"
try:
    module["prepare_storage"](missing)
except SystemExit as exc:
    assert exc.code == 1
else:
    raise AssertionError("missing qBittorrent storage root was accepted")

root = tmp / "bittorrent"
root.mkdir(parents=True)
paths = module["prepare_storage"](root)
config_path = module["write_config"](paths["profile_home"], paths)

parser = configparser.ConfigParser(interpolation=None, strict=False, delimiters=("=",))
parser.optionxform = str
parser.read(config_path, encoding="utf-8")
assert parser["BitTorrent"]["Session\\Port"] == "50309"
assert parser["BitTorrent"]["Session\\AnnounceToAllTiers"] == "true"
assert parser["BitTorrent"]["Session\\AnnounceToAllTrackers"] == "true"
assert parser["BitTorrent"]["Session\\AnonymousModeEnabled"] == "false"
assert parser["BitTorrent"]["Session\\BTProtocol"] == "Both"
assert parser["BitTorrent"]["Session\\DHTEnabled"] == "false"
assert parser["BitTorrent"]["Session\\PeXEnabled"] == "false"
assert parser["BitTorrent"]["Session\\LSDEnabled"] == "false"
assert parser["BitTorrent"]["Session\\SSRFMitigation"] == "true"
assert parser["BitTorrent"]["Session\\UseRandomPort"] == "false"
assert parser["BitTorrent"]["Session\\UseUPnP"] == "false"
assert parser["BitTorrent"]["Session\\ValidateHTTPSTrackerCertificate"] == "true"
assert parser["BitTorrent"]["Session\\DefaultSavePath"] == str(root / "completed")
assert parser["BitTorrent"]["Session\\TempPath"] == str(root / "active")
assert parser["BitTorrent"]["Session\\TorrentExportDirectory"] == str(root / "torrents-active")
assert parser["BitTorrent"]["Session\\FinishedTorrentExportDirectory"] == str(root / "torrents-completed")
assert parser["Network"]["PortForwardingEnabled"] == "false"
PY
then
  pass "wrapper refuses a missing root and renders private-tracker paths and fixed-port settings"
else
  fail "wrapper refuses a missing root and renders private-tracker paths and fixed-port settings"
fi

if python3 - "$wrapper" "$TMP_DIR/imports" <<'PY'
from pathlib import Path
import hashlib
import runpy
import stat
import sys

module = runpy.run_path(sys.argv[1])
tmp = Path(sys.argv[2]).resolve()
root = tmp / "bittorrent"
root.mkdir(parents=True)
paths = module["prepare_storage"](root)

torrent_path = tmp / "private-tracker.torrent"
torrent_payload = b"d4:infod4:name7:exampleee"
torrent_path.write_bytes(torrent_payload)
prepared = module["prepare_launch_arguments"](
    paths,
    [torrent_path.as_uri(), "magnet:?xt=urn:btih:test"],
)

expected_name = f"{hashlib.sha256(torrent_payload).hexdigest()}.torrent"
staged_path = paths["imports"] / expected_name
assert prepared == [
    f"/home/user/imports/{expected_name}",
    "magnet:?xt=urn:btih:test",
]
assert staged_path.read_bytes() == torrent_payload
assert stat.S_IMODE(staged_path.stat().st_mode) == 0o600

staged_path.write_bytes(b"tampered")
module["prepare_launch_arguments"](paths, [str(torrent_path)])
assert staged_path.read_bytes() == torrent_payload

symlink_path = tmp / "private-tracker-link.torrent"
symlink_path.symlink_to(torrent_path)
try:
    module["prepare_launch_arguments"](paths, [str(symlink_path)])
except SystemExit as exc:
    assert exc.code == 1
else:
    raise AssertionError("symlinked local torrent file was accepted")

oversized_path = tmp / "oversized.torrent"
with oversized_path.open("wb") as handle:
    handle.truncate(module["MAX_TORRENT_FILE_BYTES"] + 1)
try:
    module["prepare_launch_arguments"](paths, [str(oversized_path)])
except SystemExit as exc:
    assert exc.code == 1
else:
    raise AssertionError("oversized local torrent file was accepted")
PY
then
  pass "wrapper safely stages bounded private-tracker torrent files inside the sandbox"
else
  fail "wrapper safely stages bounded private-tracker torrent files inside the sandbox"
fi

if python3 - "$wrapper" "$TMP_DIR/bwrap" <<'PY'
from pathlib import Path
from types import SimpleNamespace
import os
import runpy
import sys

module = runpy.run_path(sys.argv[1])
tmp = Path(sys.argv[2]).resolve()
runtime = tmp / "runtime"
root = tmp / "bittorrent"
profile = root / ".qbittorrent-profile"
runtime.mkdir(parents=True)
profile.mkdir(parents=True)

wayland = runtime / "wayland-0"
bus = runtime / "bus-host"

module["shutil"].which = lambda command: f"/usr/bin/{command}"
module["build_command"].__globals__["require_socket"] = lambda path, label: None
module["os"].environ["XDG_RUNTIME_DIR"] = str(runtime)
module["os"].environ["WAYLAND_DISPLAY"] = "wayland-0"
module["os"].environ["DBUS_SESSION_BUS_ADDRESS"] = f"unix:path={bus}"
account = SimpleNamespace(pw_name="alice")
command = module["build_command"](
    account,
    root,
    profile,
    "launch",
    ["magnet:?xt=urn:btih:test"],
)

assert "--disable-userns" not in command
assert [str(profile), "/home/user"] in [command[index + 1:index + 3] for index, value in enumerate(command) if value == "--bind"]
assert [str(root), str(root)] in [command[index + 1:index + 3] for index, value in enumerate(command) if value == "--bind"]
bind_sources = {
    command[index + 1]
    for index, value in enumerate(command)
    if value == "--bind"
}
assert bind_sources <= {str(profile), str(root), str(wayland), str(bus)}
for temporary_directory in ("/tmp", "/var/tmp", "/dev/shm"):
    assert any(
        command[index : index + 5]
        == [
            "--tmpfs",
            temporary_directory,
            "--chmod",
            "01777",
            temporary_directory,
        ]
        for index in range(len(command) - 4)
    )
assert "/dev/snd" not in command
module["validate_no_host_audio_device_binds"](
    ["bwrap", "--bind", str(wayland), "/run/user/1000/wayland-0"]
)
try:
    module["validate_no_host_audio_device_binds"](
        ["bwrap", "--dev-bind", "/dev/snd/pcmC0D0p", "/dev/snd/pcmC0D0p"]
    )
except SystemExit as exc:
    assert exc.code == 1
else:
    raise AssertionError("qBittorrent bubblewrap accepted direct ALSA device access")
assert "/home/alice" not in command
environment = {
    command[index + 1]: command[index + 2]
    for index, value in enumerate(command)
    if value == "--setenv"
}
assert environment["QSG_RHI_BACKEND"] == "opengl"
assert "QT_QUICK_BACKEND" not in environment
assert not any(name.startswith(("VK_", "__VK_", "MESA_VK_")) for name in environment)
assert "__NV_PRIME_RENDER_OFFLOAD" not in environment
assert "__VK_LAYER_NV_optimus" not in environment
assert "__GLX_VENDOR_LIBRARY_NAME" not in environment
assert "QT_OPENGL" not in environment
assert "LIBGL_ALWAYS_SOFTWARE" not in environment
assert command[-2:] == ["/usr/bin/qbittorrent", "magnet:?xt=urn:btih:test"]

module["add_gpu_device_binds"] = lambda command, acceleration_mode: None
intel_command = module["build_command"](
    account,
    root,
    profile,
    "intel",
    ["magnet:?xt=urn:btih:test"],
)
intel_environment = {
    intel_command[index + 1]: intel_command[index + 2]
    for index, value in enumerate(intel_command)
    if value == "--setenv"
}
assert intel_environment["DRI_PRIME"] == "0"
assert intel_environment["LIBVA_DRIVER_NAME"] == "iHD"

nvidia_command = module["build_command"](
    account,
    root,
    profile,
    "nvidia",
    ["magnet:?xt=urn:btih:test"],
)
nvidia_environment = {
    nvidia_command[index + 1]: nvidia_command[index + 2]
    for index, value in enumerate(nvidia_command)
    if value == "--setenv"
}
assert nvidia_environment["LIBVA_DRIVER_NAME"] == "nvidia"
assert nvidia_environment["NVD_BACKEND"] == "direct"
assert nvidia_environment["__NV_PRIME_RENDER_OFFLOAD"] == "1"
assert nvidia_environment["__GLX_VENDOR_LIBRARY_NAME"] == "nvidia"

for unavailable_mode in ("intel", "nvidia"):
    try:
        module["select_acceleration_mode"](
            {
                "LABWC_INTEL_ACCELERATION_AVAILABLE": "false",
                "LABWC_NVIDIA_ACCELERATION_AVAILABLE": "false",
            },
            [f"--managed-acceleration={unavailable_mode}"],
        )
    except SystemExit as exc:
        assert exc.code == 1
    else:
        raise AssertionError(
            f"qBittorrent accepted unavailable {unavailable_mode} acceleration"
        )
PY
then
  pass "bubblewrap exposes managed storage and enforces Intel or NVIDIA VA-API drivers by action"
else
  fail "bubblewrap exposes managed storage and enforces Intel or NVIDIA VA-API drivers by action"
fi

if python3 -m py_compile "$wrapper" "$launcher_sync"; then
  pass "qBittorrent wrapper and launcher synchronizer compile"
else
  fail "qBittorrent wrapper and launcher synchronizer compile"
fi

[ "$FAIL_COUNT" -eq 0 ]
