#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
LOG=${APPARMOR_DENIED_MASK_LOG:-"$ROOT_DIR/failures/apparmor.log"}
APPARMOR_DIR="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d"
PROFILE="$APPARMOR_DIR/managed-desktop-wrappers"
SYSTEM_PROFILE="$APPARMOR_DIR/managed-system-wrappers"
SLIRP_PROFILE="$APPARMOR_DIR/slirp4netns"
SLIRP_LOCAL="$APPARMOR_DIR/local/slirp4netns"
AA_STATUS_PROFILE="$APPARMOR_DIR/usr.sbin.aa-status"
TAILSCALE_PROFILE="$APPARMOR_DIR/usr.sbin.tailscaled"
SECURITY_SCRIPT="$ROOT_DIR/d-i/forky/scripts/late/security.sh"
TAILSCALE_BOOTSTRAP_UNIT="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/systemd/system/tailscale-managed-bootstrap.service"
SECONDBOOT_UNIT="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/systemd/system/secondboot.service"
MODE_CONFIG="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor/managed-modes.conf.tmpl"
WRAPPER_DESKTOP="$APPARMOR_DIR/abstractions/managed-wrapper-desktop"
DESKTOP_APPLICATION="$APPARMOR_DIR/abstractions/managed-desktop-application"
DESKTOP_RUNTIME="$APPARMOR_DIR/abstractions/managed-desktop-runtime"
DESKTOP_GRAPHICS="$APPARMOR_DIR/abstractions/managed-desktop-graphics"
ELECTRON_APPLICATION="$APPARMOR_DIR/abstractions/managed-electron-application"
ELECTRON_RUNTIME="$APPARMOR_DIR/abstractions/managed-electron-runtime"
WEBKIT_RUNTIME="$APPARMOR_DIR/abstractions/managed-webkit-runtime"
PIPEWIRE_AUDIO="$APPARMOR_DIR/abstractions/managed-pipewire-audio"
BWRAP_COMMON="$APPARMOR_DIR/abstractions/managed-bwrap-common"
CODEX_RUNTIME="$APPARMOR_DIR/abstractions/managed-codex-runtime"
DEVOPS_TOOLCHAIN_RUNTIME="$APPARMOR_DIR/abstractions/managed-devops-toolchain-runtime"
CODEX_WRAPPER="$ROOT_DIR/d-i/forky/hooks/shared/target/data/codex/lib/codex"
CHROMIUM_LOCAL="$APPARMOR_DIR/local/chromium"
MULLVAD_LOCAL="$APPARMOR_DIR/local/mullvad-browser"
VIVALDI_BIN_LOCAL="$APPARMOR_DIR/local/vivaldi-bin"
DISCORD_PROFILE="$APPARMOR_DIR/Discord"
LEDGER_PROFILE="$APPARMOR_DIR/opt.ledger-live.AppRun"
TUTA_PROFILE="$APPARMOR_DIR/opt.tuta-mail.AppRun"
KEEPASSXC_PROFILE="$APPARMOR_DIR/usr.bin.keepassxc"
SQLITEBROWSER_PROFILE="$APPARMOR_DIR/usr.bin.sqlitebrowser"
SPOTIFY_PROFILE="$APPARMOR_DIR/usr.bin.spotify"
MUTE_DEFAULT_MICROPHONE="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/libexec/labwc-mute-default-microphone"
AUDIO_MODULE="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/lib/perl5/site_perl/whisper/WhisperMode/Audio.pm"
SESSION_WRAPPER="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-session.tmpl"
SESSION_CHILD_WRAPPER="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/libexec/labwc-session-child"
AUTOSTART_WRAPPER="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-autostart"
FUZZEL_WRAPPER="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-fuzzel"
KEYBOARD_WRAPPER="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-keyboard-layout"
LOCK_WRAPPER="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-lock"
POSTMAN_PROFILE="$APPARMOR_DIR/opt.postman.app.Postman"
MANAGED_APP_SANDBOX="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/lib/python3.14/dist-packages/labwc_managed_app/sandbox.py"
WHISPER_SERVER_UNIT="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/systemd/user/whisper-server.service"
GRIDLINE_PROFILE="$APPARMOR_DIR/usr.bin.gridline"
QOREDB_PROFILE="$APPARMOR_DIR/usr.bin.qoredb"

TEST_COUNT=18
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

profile_block() {
  expected_profile=$1
  profile_path=${2:-$PROFILE}

  awk -v expected_profile="$expected_profile" '
    $1 == "profile" && $2 == expected_profile { in_profile = 1 }
    in_profile { print }
    in_profile && /^}/ { exit }
  ' "$profile_path"
}

printf '1..%s\n' "$TEST_COUNT"

if python3 - \
  "$LOG" \
  "$PROFILE" \
  "$MANAGED_APP_SANDBOX" \
  "$SYSTEM_PROFILE" \
  "$SPOTIFY_PROFILE" \
  "$BWRAP_COMMON" \
  "$CODEX_RUNTIME" \
  "$DEVOPS_TOOLCHAIN_RUNTIME" \
  "$CODEX_WRAPPER" \
  "$VIVALDI_BIN_LOCAL" \
  "$TAILSCALE_PROFILE" \
  "$DESKTOP_APPLICATION" \
  "$DESKTOP_RUNTIME" \
  "$SESSION_CHILD_WRAPPER" \
  "$ELECTRON_RUNTIME" \
  "$SECURITY_SCRIPT" \
  "$WHISPER_SERVER_UNIT" \
  "$WEBKIT_RUNTIME" \
  "$GRIDLINE_PROFILE" \
  "$QOREDB_PROFILE" <<'PY'
from collections import Counter
import os
from pathlib import Path
import re
import string
import sys

log_path = Path(sys.argv[1])
profile_path = Path(sys.argv[2])
sandbox_path = Path(sys.argv[3])
system_profile_path = Path(sys.argv[4])
spotify_profile_path = Path(sys.argv[5])
bwrap_common_path = Path(sys.argv[6])
codex_runtime_path = Path(sys.argv[7])
devops_toolchain_runtime_path = Path(sys.argv[8])
codex_wrapper_path = Path(sys.argv[9])
vivaldi_bin_local_path = Path(sys.argv[10])
tailscale_profile_path = Path(sys.argv[11])
desktop_application_path = Path(sys.argv[12])
desktop_runtime_path = Path(sys.argv[13])
session_child_wrapper_path = Path(sys.argv[14])
electron_runtime_path = Path(sys.argv[15])
security_script_path = Path(sys.argv[16])
whisper_server_unit_path = Path(sys.argv[17])
webkit_runtime_path = Path(sys.argv[18])
gridline_profile_path = Path(sys.argv[19])
qoredb_profile_path = Path(sys.argv[20])
profiles_path = sandbox_path.with_name("profiles.py")
environment_path = sandbox_path.with_name("environment.py")
wayland_compat_path = sandbox_path.with_name("wayland_compat.py")
field_pattern = re.compile(
    r'(?P<key>[A-Za-z_][A-Za-z0-9_]*)='
    r'(?:"(?P<quoted>[^"]*)"|(?P<bare>[^\s\x1d]+))'
)
counts = Counter()
unclassified = []
ignored_root_zoom = 0
hex_digits = set(string.hexdigits)
tailscaled_ipv4_icmp_masks = {
    "bind": "bind",
    "create": "create",
    "getpeername": "getattr",
    "getsockname": "getattr",
    "recvmsg": "receive",
    "sendmsg": "send",
    "setsockopt": "setopt",
}
telbot_netlink_masks = {
    "bind": "bind",
    "create": "create",
    "getsockname": "getattr",
    "recvmsg": "receive",
    "sendmsg": "send",
}
codex_instruction_processes = {
    "/data/codex/usr/instructions/default/compact/prompt.md": "tokio-rt-worker",
    "/data/codex/usr/instructions/default/models/base.md": "tokio-rt-worker",
    "/data/codex/usr/instructions/models/default_catalog.json": "codex-main",
}
codex_package_metadata_processes = {
    "/var/cache/apt/pkgcache.bin": "apt-cache",
    "/var/lib/apt/lists/": "apt-cache",
    "/var/lib/dpkg/status": "dpkg-query",
    "/var/lib/dpkg/triggers/File": "dpkg-query",
    "/var/lib/dpkg/triggers/Unincorp": "dpkg-query",
    "/var/lib/dpkg/updates/": "dpkg-query",
}
codex_debconf_metadata_processes = {
    "/var/cache/debconf/config.dat": {
        "debconf-communi",
        "debconf-set-sel",
    },
    "/var/cache/debconf/templates.dat": {
        "debconf-communi",
        "debconf-set-sel",
    },
}
codex_vivaldi_codec_processes = {
    "awk",
    "basename",
    "cat",
    "chrome_crashpad",
    "cut",
    "dbus-send",
    "exe",
    "grep",
    "realpath",
    "tr",
    "uname",
    "vivaldi-bin",
    "xdg-mime",
    "xdg-settings",
    "xprop",
}
codex_runtime_inventory_directories = {
    "/data/codex/lib/",
    "/data/codex/usr/etc/",
    "/opt/",
    "/usr/",
}
wayland_compat_profile = (
    "managed-labwc-managed-wayland-compat-app"
    "//managed-wayland-compat-app-bwrap"
)
wayland_compat_exec_targets = {
    "/usr/bin/gsettings": "/usr/bin/gsettings",
    "/usr/bin/ip": "/usr/bin/ip",
    "/usr/sbin/ip": "/usr/bin/ip",
    "/usr/bin/ls": "/usr/bin/ls",
    "/usr/bin/lscpu": "/usr/bin/lscpu",
    "/usr/bin/lspci": "/usr/bin/lspci",
    "/usr/bin/pgrep": "/usr/bin/pgrep",
    "/usr/bin/pidof": "/usr/sbin/killall5",
    "/usr/sbin/killall5": "/usr/sbin/killall5",
    "/usr/bin/pipewire": "/usr/bin/pipewire",
    "/usr/libexec/xdg-desktop-portal": "/usr/libexec/xdg-desktop-portal",
}


def decode_audit_text(value):
    if (
        len(value) >= 2
        and len(value) % 2 == 0
        and set(value) <= hex_digits
    ):
        try:
            decoded = bytes.fromhex(value)
        except ValueError:
            return value
        text = decoded.decode("utf-8", errors="replace")
        if text.isprintable():
            return text
    return value


def decode_audit_value(value):
    decoded = decode_audit_text(value)
    return decoded if decoded.startswith("/") else value


def apparmor_profile_block(text, label, indent=""):
    lines = text.splitlines()
    start_pattern = re.compile(
        rf"^{re.escape(indent)}profile\s+{re.escape(label)}(?:\s|$).*{{\s*$"
    )
    for start_index, line in enumerate(lines):
        if start_pattern.match(line) is None:
            continue
        block = []
        for block_line in lines[start_index:]:
            block.append(block_line)
            if len(block) > 1 and block_line == f"{indent}}}":
                return "\n".join(block)
        break
    raise ValueError(f"missing or unterminated AppArmor profile: {label}")


policy_text = profile_path.read_text(encoding="utf-8")
sandbox_text = sandbox_path.read_text(encoding="utf-8")
system_policy_text = system_profile_path.read_text(encoding="utf-8")
spotify_policy_text = spotify_profile_path.read_text(encoding="utf-8")
bwrap_common_text = bwrap_common_path.read_text(encoding="utf-8")
codex_runtime_text = codex_runtime_path.read_text(encoding="utf-8")
devops_toolchain_runtime_text = devops_toolchain_runtime_path.read_text(
    encoding="utf-8"
)
codex_wrapper_text = codex_wrapper_path.read_text(encoding="utf-8")
vivaldi_bin_local_text = vivaldi_bin_local_path.read_text(encoding="utf-8")
tailscale_policy_text = tailscale_profile_path.read_text(encoding="utf-8")
desktop_application_text = desktop_application_path.read_text(encoding="utf-8")
desktop_runtime_text = desktop_runtime_path.read_text(encoding="utf-8")
electron_runtime_text = electron_runtime_path.read_text(encoding="utf-8")
security_script_text = security_script_path.read_text(encoding="utf-8")
whisper_server_unit_text = whisper_server_unit_path.read_text(encoding="utf-8")
webkit_runtime_text = webkit_runtime_path.read_text(encoding="utf-8")
gridline_profile_text = gridline_profile_path.read_text(encoding="utf-8")
qoredb_profile_text = qoredb_profile_path.read_text(encoding="utf-8")
desktop_graphics_text = (
    profile_path.parent / "abstractions/managed-desktop-graphics"
).read_text(encoding="utf-8")
profiles_text = profiles_path.read_text(encoding="utf-8")
environment_text = environment_path.read_text(encoding="utf-8")
wayland_compat_text = wayland_compat_path.read_text(encoding="utf-8")
try:
    ai_copilots_policy = apparmor_profile_block(
        policy_text,
        "managed-labwc-ai-copilots",
    )
    codex_wrapper_policy = apparmor_profile_block(
        policy_text,
        "managed-codex-wrapper",
    )
    telbot_policy = apparmor_profile_block(
        policy_text,
        "managed-telbot",
    )
    codex_bwrap_policy = apparmor_profile_block(
        policy_text,
        "codex-bwrap",
        "  ",
    )
    codex_slirp_policy = apparmor_profile_block(
        policy_text,
        "managed-codex-slirp4netns",
    )
    codex_direct_policy = apparmor_profile_block(
        policy_text,
        "managed-codex-runtime",
    )
    codex_direct_bwrap_policy = apparmor_profile_block(
        codex_direct_policy,
        "codex-bwrap",
        "  ",
    )
    devops_toolchain_policy = apparmor_profile_block(
        policy_text,
        "managed-devops-toolchain",
    )
    devops_publishing_policy = apparmor_profile_block(
        policy_text,
        "managed-devops-publishing",
    )
    virt_session_storage_policy = apparmor_profile_block(
        policy_text,
        "managed-virt-session-storage",
    )
    virt_manager_virtops_policy = apparmor_profile_block(
        policy_text,
        "managed-virt-manager-virtops",
    )
    chatgpt_policy = apparmor_profile_block(
        policy_text,
        "managed-labwc-chatgpt",
    )
    chatgpt_bwrap_policy = apparmor_profile_block(
        chatgpt_policy,
        "chatgpt-bwrap",
        "  ",
    )
    chatgpt_dbus_proxy_policy = apparmor_profile_block(
        chatgpt_policy,
        "chatgpt-dbus-proxy",
        "  ",
    )
    chatgpt_slirp_policy = apparmor_profile_block(
        policy_text,
        "managed-chatgpt-slirp4netns",
    )
    crowdsec_policy = apparmor_profile_block(
        system_policy_text,
        "managed-crowdsec-firstboot",
    )
    tailscaled_policy = apparmor_profile_block(
        tailscale_policy_text,
        "usr.sbin.tailscaled",
    )
    virt_host_policy = apparmor_profile_block(
        policy_text,
        "managed-virt-host-managed",
    )
    sync_launchers_policy = apparmor_profile_block(
        policy_text,
        "managed-labwc-sync-application-launchers",
    )
    unattended_upgrades_notify_policy = apparmor_profile_block(
        system_policy_text,
        "managed-unattended-upgrades-notify",
    )
    wayland_compat_bwrap_policy = apparmor_profile_block(
        policy_text,
        "managed-wayland-compat-app-bwrap",
        "  ",
    )
    wayland_compat_policy = apparmor_profile_block(
        policy_text,
        "managed-labwc-managed-wayland-compat-app",
    )
    wayland_compat_proxy_policy = apparmor_profile_block(
        policy_text,
        "managed-wayland-compat-dbus-proxy",
        "  ",
    )
    wayland_compat_slirp_policy = apparmor_profile_block(
        policy_text,
        "managed-wayland-compat-slirp4netns",
    )
    cage_direct_exec_deny_policy = apparmor_profile_block(
        policy_text,
        "labwc-cage-direct-exec-deny",
    )
    xwayland_direct_exec_deny_policy = apparmor_profile_block(
        policy_text,
        "labwc-xwayland-direct-exec-deny",
    )
    waypaper_policy = apparmor_profile_block(
        policy_text,
        "managed-waypaper",
    )
    waypaper_bwrap_policy = apparmor_profile_block(
        policy_text,
        "waypaper-bwrap",
        "  ",
    )
    waypaper_ps_policy = apparmor_profile_block(
        policy_text,
        "waypaper-ps",
        "  ",
    )
    waypaper_kill_policy = apparmor_profile_block(
        policy_text,
        "waypaper-kill",
        "  ",
    )
    waypaper_ldconfig_policy = apparmor_profile_block(
        policy_text,
        "waypaper-ldconfig",
        "  ",
    )
    waypaper_glycin_policy = apparmor_profile_block(
        policy_text,
        "waypaper-glycin-loader",
    )
    managed_app_policy = apparmor_profile_block(
        policy_text,
        "managed-labwc-managed-app",
    )
    managed_app_bwrap_policy = apparmor_profile_block(
        policy_text,
        "managed-app-bwrap",
        "  ",
    )
    satty_policy = apparmor_profile_block(
        policy_text,
        "managed-satty-runtime",
    )
    satty_bwrap_policy = apparmor_profile_block(
        policy_text,
        "satty-bwrap",
        "  ",
    )
    spotify_policy = apparmor_profile_block(
        spotify_policy_text,
        "spotify",
    )
    whisper_cli_policy = apparmor_profile_block(
        policy_text,
        "managed-whisper-cli-default-model",
    )
    whisper_record_policy = apparmor_profile_block(
        policy_text,
        "managed-whisper-record-toggle",
    )
    network_control_policy = apparmor_profile_block(
        policy_text,
        "managed-labwc-network-control-menu",
    )
    gridline_policy = apparmor_profile_block(
        gridline_profile_text,
        "gridline",
    )
    gridline_webkit_bwrap_policy = apparmor_profile_block(
        gridline_policy,
        "webkit-bwrap",
        "  ",
    )
    qoredb_policy = apparmor_profile_block(
        qoredb_profile_text,
        "qoredb",
    )
    managed_network_policy = apparmor_profile_block(
        system_policy_text,
        "managed-managed-network-run",
    )
    grub_refresh_policy = apparmor_profile_block(
        system_policy_text,
        "managed-grub-btrfs-refresh",
    )
except ValueError as exc:
    print(exc, file=sys.stderr)
    raise SystemExit(1)

waypaper_parent_policy = waypaper_policy.split(
    "\n  profile waypaper-bwrap",
    1,
)[0]
codex_direct_parent_policy = codex_direct_policy.split(
    "\n  profile codex-bwrap",
    1,
)[0]
managed_app_parent_policy = managed_app_policy.split(
    "\n  profile managed-app-bwrap",
    1,
)[0]
satty_parent_policy = satty_policy.split(
    "\n  profile satty-bwrap",
    1,
)[0]
chatgpt_legacy_profiles = {
    "chatgpt",
    "chatgpt//null-/usr/bin/dirname",
    "chatgpt//null-/usr/bin/readlink",
    "chatgpt//null-/usr/lib/chatgpt/ChatGPT",
    (
        "chatgpt//null-/usr/lib/chatgpt/ChatGPT"
        "//null-/usr/lib/chatgpt/browser_crashpad_handler"
    ),
    (
        "chatgpt//null-/usr/lib/chatgpt/ChatGPT"
        "//null-/usr/lib/chatgpt/browser_crashpad_handler"
        "//null-/usr/lib/chatgpt/browser_crashpad_handler"
    ),
}
chatgpt_parent_policy = chatgpt_policy.split(
    "\n  profile chatgpt-dbus-proxy",
    1,
)[0]
gridline_parent_policy = gridline_policy.split(
    "\n  profile webkit-bwrap",
    1,
)[0]
chatgpt_legacy_transition_eliminated = (
    "    /usr/bin/chatgpt rix," in chatgpt_bwrap_policy.splitlines()
)
codex_installation_id_descriptor_source_eliminated = (
    'chmod 0644 -- "${CODEX_CONTROL_DIR}/installation_id"'
    in codex_wrapper_text
    and (
        '--bind "${CODEX_CONTROL_DIR}/installation_id" '
        '"${CODEX_RUNTIME_HOME}/installation_id"'
    )
    in codex_wrapper_text
    and "installation_id_fd" not in codex_wrapper_text
    and "--ro-bind-data" not in codex_wrapper_text
)
labwc_session_child_source_eliminated = (
    not session_child_wrapper_path.exists()
    and "profile managed-labwc-session-child " not in policy_text
    and "peer=managed-labwc-session-child" not in policy_text
)
whisper_child_transitions_source_eliminated = all(
    required in whisper_record_policy
    for required in (
        "  /usr/local/bin/whisper-server rCx -> whisper-server,",
        "  /data/whisper/bin/whisper-server rCx -> whisper-server,",
        "  /usr/bin/curl rCx -> whisper-http-client,",
        "  /usr/bin/pw-record rCx -> whisper-record,",
        "  profile whisper-http-client flags=(attach_disconnected) {",
        "  profile whisper-server flags=(attach_disconnected) {",
        "  profile whisper-record flags=(attach_disconnected) {",
    )
) and (
    "NoNewPrivileges=false" in whisper_server_unit_text.splitlines()
    and "NoNewPrivileges=yes" not in whisper_server_unit_text.splitlines()
)
webkit_exec_rule = (
    "/usr/lib/@{multiarch}/webkit2gtk-4.1/"
    "WebKit{Network,Web}Process rix,"
)
webkit_runtime_source_covered = all(
    required in webkit_runtime_text.splitlines()
    for required in (
        "@{PROC}/stat r,",
        "@{PROC}/zoneinfo r,",
        "owner @{PROC}/[0-9]*/{cgroup,cmdline,maps,stat,statm} r,",
        "@{sys}/devices/virtual/dmi/id/chassis_type r,",
        "@{sys}/fs/cgroup/**/{cpu.max,memory.current,memory.high,memory.max} r,",
        webkit_exec_rule,
        "/usr/share/glycin-loaders/2+/conf.d/ r,",
        "/usr/share/glycin-loaders/2+/conf.d/*.conf r,",
    )
) and (
    "etc/apparmor.d/abstractions/managed-webkit-runtime"
    in security_script_text
)
gridline_webkit_source_eliminated = webkit_runtime_source_covered and all(
    required in gridline_parent_policy.splitlines()
    for required in (
        "  #include <abstractions/managed-webkit-runtime>",
        "  /usr/bin/bwrap rCx -> webkit-bwrap,",
        "  signal (send) set=(kill) peer=gridline//webkit-bwrap,",
    )
) and all(
    required in gridline_webkit_bwrap_policy.splitlines()
    for required in (
        "    #include <abstractions/managed-bwrap-common>",
        "    #include <abstractions/managed-desktop-runtime>",
        "    #include <abstractions/managed-webkit-runtime>",
        "    signal (receive) set=(kill) peer=gridline,",
        "    /usr/bin/true rix,",
        "    /usr/libexec/glycin-loaders/2+/glycin-svg rix,",
        "    owner /pool/db/*/gridline/** rwkl,",
    )
)
qoredb_webkit_source_eliminated = webkit_runtime_source_covered and (
    "  #include <abstractions/managed-webkit-runtime>"
    in qoredb_policy.splitlines()
)
chatgpt_fixed_helpers_source_eliminated = (
    "  /usr/bin/{chmod,id,mkdir,readlink,stat} rix,"
    in chatgpt_parent_policy.splitlines()
)
webkit_primary_drm_probe_covered = (
    "deny /dev/dri/card[0-9]* rw," in desktop_graphics_text.splitlines()
)
wayland_compat_current_evidence_covered = all(
    required in wayland_compat_bwrap_policy.splitlines()
    for required in (
        "    owner /run/user/[0-9]*/discord-ipc-[0-9]* rwkl,",
        "    /usr/bin/{env,expr,xdg-open} rix,",
        "    /@/usr/bin/{lsb_release,xdg-mime,xdg-open} r,",
        "    deny /@/usr/bin/chromium r,",
        "    deny /usr/bin/chromium rx,",
        "    @{sys}/devices/**/{idProduct,idVendor,interface} r,",
    )
)
vivaldi_bwrap_source_eliminated = all(
    required in vivaldi_bin_local_text
    for required in (
        "/usr/bin/bwrap rCx -> vivaldi-bwrap,",
        "profile vivaldi-bwrap flags=(attach_disconnected, mediate_deleted) {",
        "  #include <abstractions/managed-bwrap-common>",
        "  #include <abstractions/managed-electron-runtime>",
    )
)
vivaldi_disconnected_paths_covered = all(
    required in security_script_text
    for required in (
        "apparmor_require_disconnected_profile_flags() {",
        'add_flag("attach_disconnected")',
        'add_flag("mediate_deleted")',
        "/target/etc/apparmor.d/vivaldi-bin",
    )
)

policy_requirements = {
    "managed-labwc-ai-copilots": (
        ai_copilots_policy,
        {
            "  /dev/tty rw,",
            "  /usr/bin/cat rix,",
            "  /usr/bin/{find,fzf,id,sed,sort} rix,",
            "  owner @{PROC}/@{pid}/mountinfo r,",
            "  owner @{HOME}/.config/fzf/default-opts r,",
        },
    ),
    "managed-codex-wrapper": (
        codex_wrapper_policy,
        {
            "  signal (send) set=(exists term) peer=managed-codex-slirp4netns,",
            "  /usr/bin/slirp4netns rPx -> managed-codex-slirp4netns,",
            "  /dev/ r,",
            "  /dev/tty rw,",
            "  owner /run/user/[0-9]*/codex-devops-environment.* rwk,",
        },
    ),
    "managed-telbot": (
        telbot_policy,
        {
            "  network netlink raw,",
        },
    ),
    "managed-codex-wrapper//codex-bwrap": (
        codex_bwrap_policy,
        {
            "    capability dac_read_search,",
            "    signal (receive) set=(hup int term) peer=managed-codex-wrapper,",
            "    / r,",
            "    /data/codex/usr/instructions/ r,",
            "    /data/codex/usr/instructions/** r,",
        },
    ),
    "managed-codex-runtime": (
        codex_direct_parent_policy,
        {
            "  #include <abstractions/managed-codex-runtime>",
            "  signal (send, receive) peer=managed-codex-runtime//codex-bwrap,",
            "  signal (send) set=(exists term) peer=managed-codex-slirp4netns,",
            "  /usr/bin/bwrap rCx -> codex-bwrap,",
            "  /usr/bin/slirp4netns rPx -> managed-codex-slirp4netns,",
        },
    ),
    "managed-codex-runtime//codex-bwrap": (
        codex_direct_bwrap_policy,
        {
            "    #include <abstractions/managed-bwrap-common>",
            "    #include <abstractions/managed-codex-runtime>",
            "    signal (send, receive) peer=managed-codex-runtime,",
        },
    ),
    "managed-codex-slirp4netns": (
        codex_slirp_policy,
        {
            "  userns,",
            "  capability net_admin,",
            "  capability sys_admin,",
            "  capability sys_ptrace,",
            "  network create unix stream,",
            "  network inet stream,",
            "  network inet dgram,",
            "  ptrace (read) peer=managed-codex-wrapper//codex-bwrap,",
            "  ptrace (read) peer=managed-codex-runtime//codex-bwrap,",
            "  ptrace (readby) peer=managed-devops-toolchain,",
            "  ptrace (readby) peer=aa-status-reader,",
            "  signal (receive) set=(exists term) peer=managed-codex-wrapper,",
            "  signal (receive) set=(exists term) peer=managed-codex-runtime,",
            "  signal (receive) set=(exists hup) peer=unconfined,",
            "  / r,",
            "  /dev/null r,",
            "  /dev/net/tun rw,",
            "  /dev/urandom r,",
            "  /etc/ld.so.cache r,",
            "  /etc/resolv.conf r,",
            "  /run/resolvconf/resolv.conf r,",
            "  /run/systemd/resolve/stub-resolv.conf r,",
            "  /usr/bin/slirp4netns mr,",
            "  /usr/lib/@{multiarch}/ld-linux-*.so* mr,",
            "  /usr/lib/@{multiarch}/lib{atomic,c,glib-2.0,m,pcre2-8,seccomp,slirp}.so* mr,",
            "  @{PROC}/[0-9]*/ns/{net,user} r,",
            "  owner /data/codex/runtime/.control/launch.*/{slirp.stdout,slirp.stderr} w,",
            "  owner /data/codex/runtime/.control/launch.*/{bwrap-info.fifo,bwrap-block.fifo,slirp-ready.fifo} rw,",
        },
    ),
    "managed-crowdsec-firstboot": (
        crowdsec_policy,
        {
            "  /etc/machine-id r,",
        },
    ),
    "usr.sbin.tailscaled": (
        tailscaled_policy,
        {
            "  /usr/sbin/resolvconf rix,",
            "  /{,usr/}bin/{flock,sed} rix,",
            "  /usr/share/doc/resolvconf/copyright r,",
            "  /run/resolvconf/run-lock rwk,",
            "  /etc/resolvconf/update-libc.d/ rw,",
            "  /etc/resolvconf/update-libc.d/tailscale rw,",
            "  /etc/resolvconf/update-libc.d/tailscale.tmp[0-9]* rw,",
        },
    ),
    "managed-devops-toolchain": (
        devops_toolchain_policy,
        {
            "  #include <abstractions/managed-devops-toolchain-runtime>",
            "  capability sys_ptrace,",
            "  ptrace (read),",
            "  owner @{PROC}/[0-9]*/coredump_filter w,",
            "  owner @{PROC}/[0-9]*/task/[0-9]*/comm rw,",
        },
    ),
    "managed-devops-publishing": (
        devops_publishing_policy,
        {
            "  #include <abstractions/managed-devops-toolchain-runtime>",
            "  include if exists <abstractions/dbus-session-strict>",
            "  dbus (send, receive)",
            "  bus=session",
            "  peer=(name=org.freedesktop.secrets),",
        },
    ),
    "managed-virt-session-storage": (
        virt_session_storage_policy,
        {
            "  /dev/tty rw,",
            "  /sys/devices/system/node/ r,",
            "  owner /run/user/[0-9]*/libvirt/libvirtd.lock rwk,",
            "  owner /run/user/[0-9]*/libvirt/libvirt-sock rw,",
        },
    ),
    "managed-virt-manager-virtops": (
        virt_manager_virtops_policy,
        {
            "  owner /run/user/[0-9]*/libvirt/libvirtd.lock rwk,",
            "  owner /run/user/[0-9]*/libvirt/libvirt-sock rw,",
        },
    ),
    "managed-labwc-chatgpt//chatgpt-bwrap": (
        chatgpt_bwrap_policy,
        {
            "    #include <abstractions/managed-bwrap-common>",
            "    signal (receive) set=(kill term) peer=managed-labwc-chatgpt,",
            "    deny /etc/opt/ w,",
            "    deny /etc/opt/chrome/ w,",
            "    deny /etc/opt/chrome/native-messaging-hosts/ w,",
            "    /usr/bin/xdg-open rix,",
            "    /usr/bin/chatgpt rix,",
        },
    ),
    "managed-labwc-chatgpt": (
        chatgpt_parent_policy,
        {
            "  /usr/bin/{chmod,id,mkdir,readlink,stat} rix,",
            "  owner @{PROC}/@{pid}/fd/ r,",
            "  /run/resolvconf/resolv.conf r,",
            "  /usr/bin/slirp4netns rPx -> managed-chatgpt-slirp4netns,",
            "  signal (send) set=(exists kill term) peer=managed-chatgpt-slirp4netns,",
        },
    ),
    "managed-chatgpt-slirp4netns": (
        chatgpt_slirp_policy,
        {
            "  userns,",
            "  capability net_admin,",
            "  capability sys_admin,",
            "  capability sys_ptrace,",
            "  network create unix stream,",
            "  network inet stream,",
            "  network inet dgram,",
            "  ptrace (read) peer=managed-labwc-chatgpt//chatgpt-bwrap,",
            "  ptrace (readby) peer=aa-status-reader,",
            "  signal (receive) set=(exists kill term) peer=managed-labwc-chatgpt,",
            "  /dev/null rw,",
            "  /dev/net/tun rw,",
            "  /etc/resolv.conf r,",
            "  /run/resolvconf/resolv.conf r,",
            "  /run/systemd/resolve/stub-resolv.conf r,",
            "  /usr/bin/slirp4netns mr,",
            "  @{PROC}/[0-9]*/ns/{net,user} r,",
            "  owner /run/user/[0-9]*/labwc-chatgpt-sandbox-*/slirp4netns.stderr rw,",
        },
    ),
    "managed-labwc-chatgpt//chatgpt-dbus-proxy": (
        chatgpt_dbus_proxy_policy,
        {
            "    owner /run/user/[0-9]*/labwc-chatgpt-sandbox-*/{session-bus,system-bus} rw,",
        },
    ),
    "gridline": (
        gridline_parent_policy,
        {
            "  #include <abstractions/managed-webkit-runtime>",
            "  /usr/bin/bwrap rCx -> webkit-bwrap,",
            "  signal (send) set=(kill) peer=gridline//webkit-bwrap,",
        },
    ),
    "gridline//webkit-bwrap": (
        gridline_webkit_bwrap_policy,
        {
            "    #include <abstractions/managed-bwrap-common>",
            "    #include <abstractions/managed-desktop-runtime>",
            "    #include <abstractions/managed-webkit-runtime>",
            "    signal (receive) set=(kill) peer=gridline,",
            "    /usr/bin/true rix,",
            "    /usr/libexec/glycin-loaders/2+/glycin-svg rix,",
            "    owner /pool/db/*/gridline/** rwkl,",
        },
    ),
    "qoredb": (
        qoredb_policy,
        {
            "  #include <abstractions/managed-webkit-runtime>",
        },
    ),
    "managed-webkit-runtime abstraction": (
        webkit_runtime_text,
        {
            "@{PROC}/stat r,",
            "@{PROC}/zoneinfo r,",
            "owner @{PROC}/[0-9]*/{cgroup,cmdline,maps,stat,statm} r,",
            "@{sys}/devices/system/cpu/online r,",
            "@{sys}/devices/virtual/dmi/id/chassis_type r,",
            "@{sys}/fs/cgroup/**/{cpu.max,memory.current,memory.high,memory.max} r,",
            webkit_exec_rule,
            "/usr/share/glycin-loaders/2+/conf.d/ r,",
            "/usr/share/glycin-loaders/2+/conf.d/*.conf r,",
        },
    ),
    "managed-virt-host-managed": (
        virt_host_policy,
        {
            "  / r,",
            "  owner /tmp/{virt-host-lxc.*,virt-host-lxc-configs.*} rwk,",
        },
    ),
    "managed-labwc-sync-application-launchers": (
        sync_launchers_policy,
        {
            "  owner @{HOME}/.config/autostart/ r,",
            "  owner @{HOME}/.config/autostart/.bitwarden.desktop.*.desktop rwk,",
        },
    ),
    "managed-unattended-upgrades-notify": (
        unattended_upgrades_notify_policy,
        {
            "  / r,",
        },
    ),
    "managed-whisper-cli-default-model": (
        whisper_cli_policy,
        {
            "  /data/whisper/bin/ r,",
        },
    ),
    "managed-whisper-record-toggle": (
        whisper_record_policy,
        {
            "  /data/whisper/bin/ r,",
            "  /usr/local/bin/whisper-server rCx -> whisper-server,",
            "  /data/whisper/bin/whisper-server rCx -> whisper-server,",
            "  /usr/bin/curl rCx -> whisper-http-client,",
            "  /usr/bin/pw-record rCx -> whisper-record,",
            "  profile whisper-http-client flags=(attach_disconnected) {",
            "  profile whisper-server flags=(attach_disconnected) {",
            "  profile whisper-record flags=(attach_disconnected) {",
            "    @{PROC}/devices r,",
            "    @{PROC}/sys/vm/mmap_min_addr r,",
            "    owner @{PROC}/@{pid}/cmdline r,",
            "  owner @{HOME}/ r,",
            "  owner @{HOME}/Syncthing/sleek/whisper.txt rwk,",
        },
    ),
    "managed-labwc-network-control-menu": (
        network_control_policy,
        {
            "  owner @{HOME}/**/ r,",
        },
    ),
    "managed-labwc-managed-wayland-compat-app//managed-wayland-compat-dbus-proxy": (
        wayland_compat_proxy_policy,
        {
            "    /usr/bin/xdg-dbus-proxy mr,",
            "    /run/dbus/system_bus_socket rw,",
            "    owner /run/user/[0-9]*/bus rw,",
            "    owner /run/user/[0-9]*/labwc-{discord,zoom}-sandbox-*/{session-bus,system-bus} rw,",
        },
    ),
    "managed-labwc-managed-wayland-compat-app": (
        wayland_compat_policy,
        {
            "  /usr/bin/slirp4netns rPx -> managed-wayland-compat-slirp4netns,",
            "  signal (send) set=(exists kill term) peer=managed-wayland-compat-slirp4netns,",
            "  owner @{PROC}/@{pid}/fd/ r,",
        },
    ),
    "managed-wayland-compat-slirp4netns": (
        wayland_compat_slirp_policy,
        {
            "  userns,",
            "  capability net_admin,",
            "  capability sys_admin,",
            "  capability sys_ptrace,",
            "  network create unix stream,",
            "  network inet stream,",
            "  network inet dgram,",
            "  ptrace (read) peer=managed-labwc-managed-wayland-compat-app//managed-wayland-compat-app-bwrap,",
            "  signal (receive) set=(exists kill term) peer=managed-labwc-managed-wayland-compat-app,",
            "  /dev/null rw,",
            "  /dev/net/tun rw,",
            "  /run/systemd/resolve/stub-resolv.conf r,",
            "  /usr/bin/slirp4netns mr,",
            "  @{PROC}/[0-9]*/ns/{net,user} r,",
            "  owner /run/user/[0-9]*/labwc-{discord,zoom}-sandbox-*/slirp4netns.stderr rw,",
            "  owner /tmp/labwc-{discord,zoom}-sandbox-*/slirp4netns.stderr rw,",
        },
    ),
    "managed-labwc-managed-wayland-compat-app//managed-wayland-compat-app-bwrap": (
        wayland_compat_bwrap_policy,
        {
            "    #include <abstractions/managed-pipewire-audio>",
            "    capability dac_read_search,",
            "    signal (send, receive) peer=managed-labwc-managed-wayland-compat-app//managed-wayland-compat-app-bwrap,",
            "    /dev/console rw,",
            "    /dev/{media,video}[0-9]* rw,",
            "    /dev/v4l-subdev[0-9]* rw,",
            "    /run/dbus/system_bus_socket rw,",
            "    owner /run/user/[0-9]*/pulse/ rw,",
            "    owner /run/user/[0-9]*/discord-ipc-[0-9]* rwkl,",
            "    owner /run/user/[0-9]*/server-[0-9]*.xkm rw,",
            "    owner @{HOME}/.cache/qtshadercache-*/ rw,",
            "    owner @{HOME}/.cache/qtshadercache-*/** rwkl,",
            "    owner @{HOME}/.config/ rw,",
            "    owner @{HOME}/.config/\\#* rwkl,",
            "    owner @{HOME}/.config/pulse/ rw,",
            "    owner @{HOME}/.config/zoom.conf* rwkl,",
            "    owner @{HOME}/.config/zoomus.conf* rwkl,",
            "    owner @{PROC}/[0-9]*/mem r,",
            "    @{PROC}/bus/pci/devices r,",
            "    @{sys}/devices/**/power_supply/*/{capacity,online,type} r,",
            "    @{sys}/devices/system/cpu/cpu[0-9]*/cache/index[0-9]*/{coherency_line_size,number_of_sets,physical_line_partition,shared_cpu_map,type,ways_of_associativity} r,",
            "    @{sys}/devices/system/cpu/cpu[0-9]*/hotplug/state r,",
            "    @{sys}/devices/system/cpu/cpu[0-9]*/topology/{core_id,core_siblings,thread_siblings} r,",
            "    @{sys}/devices/system/cpu/cpufreq/policy[0-9]*/cpuinfo_min_freq r,",
            "    @{sys}/devices/system/cpu/hotplug/states r,",
            "    @{sys}/devices/system/cpu/vulnerabilities/ r,",
            "    @{sys}/devices/system/cpu/vulnerabilities/* r,",
            "    @{sys}/kernel/cpu_byteorder r,",
            "    /opt/xwayland/usr/bin/Xwayland rix,",
            "    /opt/xwayland/usr/lib/x86_64-linux-gnu/libXau.so.6 mr,",
            "    /opt/xwayland/usr/lib/x86_64-linux-gnu/libXau.so.6.* mr,",
            "    /opt/xwayland/usr/lib/x86_64-linux-gnu/libXdmcp.so.6 mr,",
            "    /opt/xwayland/usr/lib/x86_64-linux-gnu/libXdmcp.so.6.* mr,",
            "    /opt/xwayland/usr/lib/x86_64-linux-gnu/libXfont2.so.2 mr,",
            "    /opt/xwayland/usr/lib/x86_64-linux-gnu/libXfont2.so.2.* mr,",
            "    /opt/xwayland/usr/lib/x86_64-linux-gnu/libxcb-cursor.so.0 mr,",
            "    /opt/xwayland/usr/lib/x86_64-linux-gnu/libxcb-cursor.so.0.* mr,",
            "    /opt/xwayland/usr/lib/x86_64-linux-gnu/libxcb-image.so.0 mr,",
            "    /opt/xwayland/usr/lib/x86_64-linux-gnu/libxcb-image.so.0.* mr,",
            "    /opt/xwayland/usr/lib/x86_64-linux-gnu/libxcb-render-util.so.0 mr,",
            "    /opt/xwayland/usr/lib/x86_64-linux-gnu/libxcb-render-util.so.0.* mr,",
            "    /opt/xwayland/usr/lib/x86_64-linux-gnu/libxcb-render.so.0 mr,",
            "    /opt/xwayland/usr/lib/x86_64-linux-gnu/libxcb-render.so.0.* mr,",
            "    /opt/xwayland/usr/lib/x86_64-linux-gnu/libxcb.so.1 mr,",
            "    /opt/xwayland/usr/lib/x86_64-linux-gnu/libxcb.so.1.* mr,",
            "    /opt/xwayland/usr/lib/x86_64-linux-gnu/libxcvt.so.0 mr,",
            "    /opt/xwayland/usr/lib/x86_64-linux-gnu/libxcvt.so.0.* mr,",
            "    /opt/xwayland/usr/lib/x86_64-linux-gnu/libxshmfence.so.1 mr,",
            "    /opt/xwayland/usr/lib/x86_64-linux-gnu/libxshmfence.so.1.* mr,",
            "    /usr/bin/{gsettings,ls,lscpu,lspci,pgrep,pipewire} rix,",
            "    /usr/bin/{env,expr,xdg-open} rix,",
            "    /usr/{bin,sbin}/ip rix,",
            "    /usr/{bin/pidof,sbin/killall5} rix,",
            "    /usr/libexec/xdg-desktop-portal rix,",
            "    /usr/share/iproute2/group r,",
            "    /usr/share/misc/pci.ids r,",
            "    /usr/share/xdg-desktop-portal/portals/ r,",
            "    /@/usr/bin/{lsb_release,xdg-mime,xdg-open} r,",
            "    deny /@/usr/bin/chromium r,",
            "    deny /usr/bin/chromium rx,",
            "    @{sys}/devices/**/{idProduct,idVendor,interface} r,",
        },
    ),
    "managed-waypaper": (
        waypaper_parent_policy,
        {
            "  network inet stream,",
            "  network inet6 stream,",
            "  network inet dgram,",
            "  network inet6 dgram,",
            "  /usr/bin/bwrap rCx -> waypaper-bwrap,",
            "  /usr/bin/kill rCx -> waypaper-kill,",
            "  /usr/bin/ps rCx -> waypaper-ps,",
            "  /usr/sbin/ldconfig rCx -> waypaper-ldconfig,",
            "  /dev/dri/card[0-9]* r,",
            "  /usr/share/glycin-loaders/2+/conf.d/** r,",
            "  signal (send) set=(kill) peer=managed-waypaper//waypaper-bwrap,",
            "  owner /tmp/gdk-pixbuf-glycin-tmp.* rwk,",
            "  owner @{HOME}/.config/user-dirs.dirs r,",
        },
    ),
    "managed-waypaper//waypaper-bwrap": (
        waypaper_bwrap_policy,
        {
            "    #include <abstractions/base>",
            "    #include <abstractions/managed-bwrap-common>",
            "    signal (receive) set=(kill) peer=managed-waypaper,",
            "    ptrace (readby) peer=managed-waypaper//waypaper-ps,",
            "    /usr/bin/true rix,",
            "    /usr/libexec/glycin-loaders/2+/{glycin-image-rs,glycin-svg} rix,",
            "    owner @{HOME}/.cache/glycin/** rwkl,",
        },
    ),
    "managed-waypaper//waypaper-ps": (
        waypaper_ps_policy,
        {
            "    capability sys_ptrace,",
            "    ptrace (read) peer=unconfined,",
            "    ptrace (read) peer=managed-waypaper//waypaper-bwrap,",
            "    /usr/bin/ps mr,",
            "    @{PROC}/[0-9]*/{cmdline,environ,stat,status} r,",
        },
    ),
    "managed-waypaper//waypaper-kill": (
        waypaper_kill_policy,
        {
            "    /usr/bin/kill mr,",
            "    signal (send) set=(kill term) peer=unconfined,",
        },
    ),
    "managed-waypaper//waypaper-ldconfig": (
        waypaper_ldconfig_policy,
        {
            "    /usr/sbin/ldconfig mr,",
            "    /dev/null rw,",
            "    /etc/ld.so.cache r,",
        },
    ),
    "waypaper-glycin-loader": (
        waypaper_glycin_policy,
        {
            "  #include <abstractions/base>",
            "  /usr/libexec/glycin-loaders/2+/glycin-image-rs mrix,",
            "  /usr/libexec/glycin-loaders/2+/glycin-svg mrix,",
            "  owner @{HOME}/.cache/glycin/** rwkl,",
        },
    ),
    "managed-labwc-managed-app": (
        managed_app_parent_policy,
        {
            "  signal (send) set=(kill) peer=managed-labwc-managed-app//managed-app-bwrap,",
            "  /usr/bin/spotify rpx -> spotify,",
            "  /usr/share/spotify/spotify rpx -> spotify,",
        },
    ),
    "managed-labwc-managed-app//managed-app-bwrap": (
        managed_app_bwrap_policy,
        {
            "    #include <abstractions/managed-bwrap-common>",
            "    #include <abstractions/managed-bwrap-desktop-runtime>",
            "    signal (receive) set=(kill) peer=managed-labwc-managed-app,",
            "    /proc/self/exe rix,",
            "    /usr/bin/spotify rix,",
            "    /usr/share/spotify/ r,",
            "    /usr/share/spotify/** mr,",
            "    /usr/share/spotify/spotify rix,",
        },
    ),
    "managed-satty-runtime": (
        satty_parent_policy,
        {
            "  /usr/bin/bwrap rCx -> satty-bwrap,",
            "  /usr/share/glycin-loaders/2+/conf.d/ r,",
            "  /usr/share/glycin-loaders/2+/conf.d/** r,",
            "  signal (send) set=(kill) peer=managed-satty-runtime//satty-bwrap,",
            "  owner @{PROC}/@{pid}/cmdline r,",
        },
    ),
    "managed-satty-runtime//satty-bwrap": (
        satty_bwrap_policy,
        {
            "    #include <abstractions/managed-bwrap-common>",
            "    signal (receive) set=(kill) peer=managed-satty-runtime,",
            "    /usr/bin/true rix,",
            "    /usr/libexec/glycin-loaders/2+/{glycin-image-rs,glycin-svg} rix,",
            "    /usr/share/glycin-loaders/2+/conf.d/ r,",
            "    /usr/share/glycin-loaders/2+/conf.d/** r,",
            "    owner /run/user/[0-9]*/labwc-capture/satty-source.*.png r,",
        },
    ),
    "spotify": (
        spotify_policy,
        {
            "  #include <abstractions/managed-electron-application>",
            "  #include <abstractions/managed-pipewire-audio>",
            "  include if exists <abstractions/user-tmp>",
            "  network inet stream,",
            "  network inet6 stream,",
            "  network inet dgram,",
            "  network inet6 dgram,",
            "  /usr/bin/spotify rix,",
            "  /proc/self/exe rix,",
            "  /usr/share/spotify/ r,",
            "  /usr/share/spotify/** mrix,",
            "  owner @{HOME}/.cache/spotify/ rw,",
            "  owner @{HOME}/.cache/spotify/** rwk,",
            "  owner @{HOME}/.config/spotify/ rw,",
            "  owner @{HOME}/.config/spotify/** rwk,",
            "  owner @{HOME}/.local/share/spotify/ rw,",
            "  owner @{HOME}/.local/share/spotify/** rwk,",
        },
    ),
    "managed-grub-btrfs-refresh": (
        grub_refresh_policy,
        {
            "  /usr/bin/grub-script-check rix,",
            "  @{PROC}/@{pid}/mounts r,",
            "  /run/ r,",
            "  /run/blkid/ rw,",
            "  /run/blkid/** rwkl,",
            "  /run/lock/ rw,",
            "  /run/mount/utab r,",
            "  /run/udev/data/* r,",
            "  @{sys}/devices/**/ r,",
            "  @{sys}/devices/**/{dev,size,start,uevent} r,",
        },
    ),
    "managed-managed-network-run": (
        managed_network_policy,
        {
            "  @{sys}/devices/**/net/managed-{eth,wifi}[0-9]*/{address,type} r,",
        },
    ),
}
policy_errors = []
for label, (block, required_lines) in policy_requirements.items():
    block_lines = set(block.splitlines())
    for required_line in sorted(required_lines):
        if required_line not in block_lines:
            policy_errors.append(f"{label}: missing {required_line}")
if (
    "#include <abstractions/managed-desktop-runtime>"
    not in desktop_application_text.splitlines()
    or "/usr/bin/xdg-open rpux,"
    not in desktop_application_text.splitlines()
    or "xdg-open" in desktop_runtime_text
):
    policy_errors.append(
        "managed desktop xdg-open policy is not separated from no_new_privs runtime access"
    )
for label, block in (
    ("managed-virt-session-storage", virt_session_storage_policy),
    ("managed-virt-manager-virtops", virt_manager_virtops_policy),
):
    block_lines = set(block.splitlines())
    for forbidden_line in (
        "  owner /run/user/[0-9]*/libvirt/** rw,",
        "  owner /run/user/[0-9]*/libvirt/** rwk,",
        "  owner /run/user/[0-9]*/libvirt/** rwkl,",
    ):
        if forbidden_line in block_lines:
            policy_errors.append(f"{label}: stale or broad rule {forbidden_line}")
for label, policy, required_lines in (
    (
        "managed-bwrap-common",
        bwrap_common_text,
        {
            "/ r,",
            "/bindfile* rw,",
            "owner @{PROC}/[0-9]*/{gid_map,setgroups,uid_map} rw,",
        },
    ),
    (
        "managed-codex-runtime abstraction",
        codex_runtime_text,
        {
            "#include <abstractions/managed-electron-runtime>",
            "userns,",
            "capability sys_admin,",
            "capability sys_chroot,",
            "capability sys_ptrace,",
            "owner @{PROC}/[0-9]*/{gid_map,setgroups,uid_map} rw,",
            "deny /data/codex/config.schema.json wkl,",
            "deny /etc/opt/chrome/ w,",
            "deny /opt/vivaldi/extensions/ w,",
            "/data/codex/config.schema.json r,",
            "/data/codex/lib/ r,",
            "/data/codex/share/bin/* mrix,",
            "/data/codex/usr/etc/ r,",
            "/data/codex/usr/instructions/ r,",
            "/data/codex/usr/instructions/** r,",
            "/opt/ r,",
            "/run/udev/data/c13:* r,",
            "/usr/ r,",
            "owner /data/codex/usr/.git/ r,",
            "owner /data/codex/usr/.git/**/ r,",
            "/var/cache/apt/pkgcache.bin r,",
            "/var/cache/debconf/{config.dat,templates.dat} r,",
            "/var/lib/apt/lists/ r,",
            "/var/lib/apt/lists/*_{Packages,Translation-*} r,",
            "/var/lib/dpkg/status r,",
            "/var/lib/dpkg/triggers/{File,Unincorp} r,",
            "/var/lib/dpkg/updates/ r,",
            "/var/lib/software/debs/Packages r,",
            "/var/opt/vivaldi/media-codecs-*/libffmpeg.so mr,",
        },
    ),
    (
        "managed-electron-runtime abstraction",
        electron_runtime_text,
        {
            "owner @{PROC}/[0-9]*/clear_refs w,",
            "owner @{PROC}/[0-9]*/oom_score_adj w,",
            "owner @{PROC}/@{pid}/fd/[0-9]* rw,",
        },
    ),
    (
        "managed-desktop-runtime abstraction",
        desktop_runtime_text,
        {
            "deny /var/cache/fontconfig/ w,",
        },
    ),
    (
        "managed-devops-toolchain-runtime abstraction",
        devops_toolchain_runtime_text,
        {
            "/ r,",
            "/home/ r,",
            "/dev/** rw,",
            "/sys/** r,",
            "/usr/** mrix,",
        },
    ),
    (
        "managed-desktop-graphics abstraction",
        desktop_graphics_text,
        {
            "deny /dev/dri/card[0-9]* rw,",
            "/usr/local/cuda-*/targets/x86_64-linux/lib/lib{cublas,cublasLt,cudart}.so* mr,",
            "/usr/local/cuda-*/targets/*/lib/libOpenCL.so* mr,",
        },
    ),
    (
        "vivaldi-bin local include",
        vivaldi_bin_local_text,
        {
            "@{PROC}/[0-9]*/statm r,",
            "/run/udev/data/ r,",
            "/run/udev/data/** r,",
            "/usr/bin/bwrap rCx -> vivaldi-bwrap,",
            "profile vivaldi-bwrap flags=(attach_disconnected, mediate_deleted) {",
            "  #include <abstractions/managed-bwrap-common>",
            "  #include <abstractions/managed-electron-runtime>",
            "signal (send) set=(kill) peer=vivaldi-bin//vivaldi-bwrap,",
            "  signal (receive) set=(kill) peer=vivaldi-bin,",
            "owner @{HOME}/Documents/** rwkl,",
            "owner @{HOME}/.local/share/gvfs-metadata/root-*.log r,",
            "owner @{HOME}/Workspace/llama-labwc/output/llama-{cuda,ram}.tar.gz r,",
            "/pool/build/whisper-labwc/artifacts/whisper-{cuda,ram}.tar.gz r,",
        },
    ),
):
    policy_lines = set(policy.splitlines())
    for required_line in sorted(required_lines):
        if required_line not in policy_lines:
            policy_errors.append(f"{label}: missing {required_line}")
if not chatgpt_legacy_transition_eliminated:
    policy_errors.append(
        "managed ChatGPT child does not inherit /usr/bin/chatgpt re-execution"
    )
if not codex_installation_id_descriptor_source_eliminated:
    policy_errors.append(
        "Codex still sources the synthetic installation ID from an inherited descriptor"
    )
if "installation_id" in codex_slirp_policy:
    policy_errors.append(
        "managed-codex-slirp4netns still permits the synthetic installation-id file"
    )
if re.search(
    r"^  (?:capability|ptrace|userns|mount|umount|pivot_root)[\s,(]",
    waypaper_parent_policy,
    re.MULTILINE,
):
    policy_errors.append(
        "managed-waypaper retains helper-only namespace or process-inspection authority"
    )
for label, block in (
    ("managed-waypaper//waypaper-ps", waypaper_ps_policy),
    ("managed-waypaper//waypaper-kill", waypaper_kill_policy),
    ("managed-waypaper//waypaper-ldconfig", waypaper_ldconfig_policy),
    ("waypaper-glycin-loader", waypaper_glycin_policy),
):
    if "managed-bwrap-common" in block or re.search(
        r"^[ ]+(?:userns|mount|umount|pivot_root),",
        block,
        re.MULTILINE,
    ):
        policy_errors.append(
            f"{label} retains Bubblewrap namespace-construction authority"
        )
if re.search(
    r"^  (?:capability|network|ptrace)[\s,(]",
    waypaper_glycin_policy,
    re.MULTILINE,
):
    policy_errors.append(
        "waypaper-glycin-loader is not capability-free and non-networked"
    )
for required_source in (
    'command.extend(["--ro-bind", "/usr", "/usr"])',
    'payload_argv_prefix: tuple[str, ...] = (),',
    'payload_argv = [*payload_argv_prefix, *argv]',
    "def run_slirp4netns_sandbox(",
    '"--info-fd"',
    '"--block-fd"',
    '"--ready-fd"',
    '"--exit-fd"',
    '"--disable-host-loopback"',
    "def slirp4netns_resolv_conf() -> str:",
    'def add_persistent_directory_binds(',
    'sandbox.get("persistent_directory_binds", ())',
    'def start_system_bus_proxy(',
    'def add_system_bus_proxy_bind(command: list[str], proxy_socket: str) -> None:',
    'env["DBUS_SYSTEM_BUS_ADDRESS"] = SYSTEM_BUS_ADDRESS',
):
    if required_source not in sandbox_text:
        policy_errors.append(
            f"managed application sandbox is missing: {required_source}"
        )
for required_source in (
    "def validate_private_runtime() -> None:",
    "    validate_private_runtime()",
    "SANDBOX_LIFECYCLE_HELPER = "
    '"/usr/local/libexec/labwc-zoom-discord-compat-runtime"',
):
    if required_source not in wayland_compat_text:
        policy_errors.append(
            f"managed compatibility boundary is missing: {required_source}"
        )
for required_source in (
    'ZOOM_CONFIG_SOURCE = ".config/zoom"',
    '"persistent_directory_binds": (',
    '(ZOOM_CONFIG_SOURCE, ".config"),',
    '"require_system_bus": True',
    '"system_dbus_names": ()',
):
    if required_source not in profiles_text:
        policy_errors.append(
            f"managed application profile policy is missing: {required_source}"
        )
if '"xdg_config_home": ".config/zoom"' in profiles_text:
    policy_errors.append(
        "managed Zoom still redirects XDG_CONFIG_HOME instead of isolating the full config mount"
    )
for required_source in (
    "def ensure_discord_managed_settings(home_dir: str) -> None:",
    '"SKIP_HOST_UPDATE": True',
    '"SKIP_MODULE_UPDATE": True',
):
    if required_source not in environment_text:
        policy_errors.append(
            f"managed Discord policy is missing: {required_source}"
        )
if re.search(
    r"owner @\{HOME\}/[.]config/discord/app-[^\\n]*[mx]",
    wayland_compat_bwrap_policy,
):
    policy_errors.append(
        "managed Wayland compatibility sandbox permits user-installed Discord executables"
    )
if (
    "profile labwc-cage-direct-exec-deny /usr/bin/cage "
    "flags=(attach_disconnected, mediate_deleted) {"
    not in cage_direct_exec_deny_policy
    or "  deny /usr/bin/cage mr,"
    not in cage_direct_exec_deny_policy
):
    policy_errors.append(
        "direct Cage execution is not restricted to the managed Bubblewrap child"
    )
if (
    "profile labwc-xwayland-direct-exec-deny "
    "/{opt/xwayland/usr,usr}/bin/Xwayland "
    "flags=(attach_disconnected, mediate_deleted) {"
    not in xwayland_direct_exec_deny_policy
    or "  deny /{opt/xwayland/usr,usr}/bin/Xwayland mr,"
    not in xwayland_direct_exec_deny_policy
):
    policy_errors.append(
        "direct private or system Xwayland execution is not fail-closed"
    )
if (
    "managed-labwc-private-xwayland" in policy_text
    or re.search(
        r"/opt/xwayland/usr/bin/Xwayland\s+r[PpCc]x\s+->",
        wayland_compat_bwrap_policy,
    )
):
    policy_errors.append(
        "private Xwayland still attempts a post-no_new_privs profile transition"
    )
if policy_errors:
    print("AppArmor log coverage is not backed by current policy:", file=sys.stderr)
    print("\n".join(policy_errors), file=sys.stderr)
    raise SystemExit(1)

waypaper_bwrap_capabilities = {
    "chown",
    "dac_override",
    "setgid",
    "setpcap",
    "setuid",
    "net_admin",
    "sys_admin",
    "sys_chroot",
    "sys_ptrace",
}
waypaper_ps_peers = {
    "unconfined",
    "managed-waypaper",
    "managed-waypaper//null-/usr/bin/bwrap",
    "managed-waypaper//null-/usr/bin/ps",
    "managed-labwc-session",
    "managed-labwc-output-watch",
    "managed-labwc-plans",
}


def is_waypaper_runtime_library(name):
    return name == "/etc/ld.so.cache" or name.startswith("/usr/lib/")


def is_waypaper_bwrap_path(name):
    if name in {
        "/",
        "/dev/null",
        "/etc/ld.so.cache",
        "/proc/filesystems",
        "/proc/sys/kernel/overflowgid",
        "/proc/sys/kernel/overflowuid",
        "/proc/sys/user/max_user_namespaces",
        "/usr/bin/bwrap",
    }:
        return True
    if name.startswith(
        (
            "/newroot",
            "/oldroot",
            "/tmp/newroot",
            "/tmp/oldroot",
            "/usr/lib/",
            "/usr/share/backgrounds/",
        )
    ):
        return True
    return re.fullmatch(
        r"/proc/[0-9]+/(?:fd/|gid_map|mountinfo|setgroups|uid_map)",
        name,
    ) is not None


def is_waypaper_ps_path(name):
    if name in {
        "/",
        "/etc/ld.so.cache",
        "/etc/nsswitch.conf",
        "/etc/passwd",
        "/proc/",
        "/proc/cpuinfo",
        "/proc/meminfo",
        "/proc/stat",
        "/proc/sys/kernel/pid_max",
        "/proc/tty/drivers",
        "/sys/devices/system/cpu/possible",
        "/sys/devices/system/node/",
    }:
        return True
    if re.fullmatch(r"/dev/(?:pts/[0-9]+|tty[0-9]+)", name):
        return True
    if re.fullmatch(
        r"/proc/[0-9]+/(?:|cmdline|environ|stat|status|task/)",
        name,
    ):
        return True
    return name.startswith(("/usr/lib/", "/usr/share/zoneinfo/"))


satty_legacy_bwrap_profile = (
    "managed-satty-runtime//null-/usr/bin/bwrap"
)
spotify_legacy_profile = (
    "managed-labwc-managed-app//null-/usr/share/spotify/spotify"
)
spotify_legacy_reexec_profile = (
    spotify_legacy_profile
    + "//null-/usr/share/spotify/spotify"
)
ai_copilots_legacy_cat_profile = (
    "managed-labwc-ai-copilots//null-/usr/bin/cat"
)


def is_satty_bwrap_path(name):
    if name in {
        "/",
        "/dev/null",
        "/etc/ld.so.cache",
        "/proc/filesystems",
        "/proc/sys/kernel/overflowgid",
        "/proc/sys/kernel/overflowuid",
        "/proc/sys/user/max_user_namespaces",
        "/usr/bin/bwrap",
    }:
        return True
    if name.startswith(
        (
            "/newroot",
            "/oldroot",
            "/tmp/newroot",
            "/tmp/oldroot",
            "/usr/lib/",
        )
    ):
        return True
    return re.fullmatch(
        r"/proc/[0-9]+/(?:fd/|gid_map|mountinfo|setgroups|uid_map)",
        name,
    ) is not None


def is_satty_payload_runtime_path(name):
    return name == "/etc/ld.so.cache" or name.startswith("/usr/lib/")


def is_spotify_home_read_path(name):
    if re.fullmatch(r"/home/(?:|[^/]+/?)", name):
        return True
    return any(
        re.fullmatch(pattern, name)
        for pattern in (
            r"/home/[^/]+/[.]cache(?:/|/fontconfig(?:/.*)?|"
            r"/mesa_shader_cache(?:/.*)?|/spotify(?:/.*)?)",
            r"/home/[^/]+/[.]config/(?:gtk-3[.]0/settings[.]ini|"
            r"user-dirs[.]dirs)",
            r"/home/[^/]+/[.]local(?:/|/share(?:/|/pki(?:/.*)?|"
            r"/spotify(?:/.*)?))",
        )
    )


def is_spotify_proc_read_path(name):
    if name in {
        "/proc/",
        "/proc/cpuinfo",
        "/proc/filesystems",
        "/proc/meminfo",
        "/proc/self/exe",
        "/proc/stat",
        "/proc/sys/dev/i915/perf_stream_paranoid",
        "/proc/sys/fs/inotify/max_user_watches",
        "/proc/sys/kernel/yama/ptrace_scope",
        "/proc/sys/vm/overcommit_memory",
    }:
        return True
    return re.fullmatch(
        r"/proc/[0-9]+/(?:"
        r"clear_refs|comm|cmdline|fd/|maps|oom_score_adj|stat|statm|status|"
        r"task/|task/[0-9]+(?:/|/(?:stat|status))"
        r")",
        name,
    ) is not None


def is_spotify_read_path(name):
    if name == "/":
        return True
    if is_spotify_home_read_path(name) or is_spotify_proc_read_path(name):
        return True
    if name.startswith(
        (
            "/etc/",
            "/sys/",
            "/tmp/",
            "/usr/lib/",
            "/usr/share/",
            "/usr/local/share/fonts/",
        )
    ):
        return True
    if name == "/var/tmp/":
        return True
    if re.fullmatch(r"/run/user/[0-9]+/dconf(?:/|/user)", name):
        return True
    return (
        re.fullmatch(
            r"/dev/(?:"
            r"|dri(?:/|/(?:card|renderD)[0-9]+)|null|urandom|"
            r"shm/[.]org[.]chromium[.]Chromium[.][A-Za-z0-9]+"
            r")",
            name,
        )
        is not None
    )


def is_spotify_mutable_path(name):
    if re.fullmatch(
        r"/home/[^/]+/(?:"
        r"[.]cache/(?:mesa_shader_cache|spotify)(?:/.*)?|"
        r"[.]config/spotify(?:/.*)?|"
        r"[.]local/share/(?:pki/nssdb/(?:cert9[.]db|key4[.]db)|"
        r"spotify(?:/.*)?)"
        r")",
        name,
    ):
        return True
    if re.fullmatch(
        r"/dev/shm/[.]org[.]chromium[.]Chromium[.][A-Za-z0-9]+",
        name,
    ):
        return True
    if re.fullmatch(r"/dev/dri/renderD[0-9]+", name):
        return True
    if re.fullmatch(r"/proc/[0-9]+/(?:clear_refs|oom_score_adj)", name):
        return True
    if re.fullmatch(r"/run/user/[0-9]+/dconf/user", name):
        return True
    return name.startswith("/tmp/")


def is_spotify_legacy_runtime(
    profile,
    operation,
    requested_mask,
    denied_mask,
    name,
    peer,
    target,
    info,
):
    if profile not in {
        spotify_legacy_profile,
        spotify_legacy_reexec_profile,
    }:
        return False
    if operation == "exec":
        return (
            profile == spotify_legacy_profile
            and requested_mask == denied_mask == "x"
            and info in {"", "no new privs"}
            and name
            in {
                "/proc/self/exe",
                "/usr/share/spotify/spotify",
            }
            and target == spotify_legacy_reexec_profile
        )
    if operation == "ptrace":
        return (
            profile == spotify_legacy_profile
            and requested_mask == denied_mask
            and requested_mask in {"read", "readby"}
            and peer == spotify_legacy_profile
        )
    if requested_mask != denied_mask:
        return False
    if operation in {"getattr", "open"} and requested_mask == "r":
        return is_spotify_read_path(name)
    if (
        operation == "file_mmap"
        and requested_mask in {"r", "rm"}
        and (
            name.startswith("/usr/lib/")
            or name.startswith("/usr/share/spotify/")
        )
    ):
        return True
    mutable_masks = {
        "file_lock": {"k", "wk"},
        "file_perm": {"w"},
        "mkdir": {"c"},
        "mknod": {"c"},
        "open": {"a", "ac", "w", "wc", "wr", "wrc"},
        "rename_dest": {"wc"},
        "rename_src": {"wrd"},
        "rmdir": {"d"},
        "symlink": {"c"},
        "truncate": {"w"},
        "unlink": {"d"},
    }
    return (
        requested_mask in mutable_masks.get(operation, set())
        and is_spotify_mutable_path(name)
    )


def is_ai_copilots_legacy_cat_runtime(
    profile,
    operation,
    requested_mask,
    denied_mask,
    name,
    comm,
):
    if (
        profile != ai_copilots_legacy_cat_profile
        or comm != "cat"
        or requested_mask != denied_mask
    ):
        return False
    if operation == "file_mmap":
        return (
            requested_mask == "r"
            and (
                name == "/usr/bin/cat"
                or re.fullmatch(
                    r"/usr/lib/[^/]+/ld-linux-[^/]+[.]so[.]2",
                    name,
                )
                is not None
            )
        ) or (
            requested_mask == "rm"
            and re.fullmatch(
                r"/usr/lib/[^/]+/libc[.]so[.]6",
                name,
            )
            is not None
        )
    return (
        operation in {"getattr", "open"}
        and requested_mask == "r"
        and (
            name == "/etc/ld.so.cache"
            or name == "/usr/lib/locale/locale-archive"
            or re.fullmatch(
                r"/usr/lib/[^/]+/libc[.]so[.]6",
                name,
            )
            is not None
        )
    )


def is_bwrap_constructor_bindfile(
    profile,
    operation,
    requested_mask,
    denied_mask,
    name,
    comm,
):
    return (
        profile
        in {
            "managed-codex-wrapper//codex-bwrap",
            "managed-labwc-chatgpt//chatgpt-bwrap",
        }
        and comm == "bwrap"
        and re.fullmatch(r"/bindfile[A-Za-z0-9]+", name) is not None
        and requested_mask == denied_mask
        and (operation, requested_mask)
        in {
            ("chmod", "w"),
            ("mknod", "c"),
            ("open", "wrc"),
            ("unlink", "d"),
        }
    )


def is_virt_host_runtime_access(
    profile,
    operation,
    requested_mask,
    denied_mask,
    name,
    comm,
):
    if (
        profile != "managed-virt-host-managed"
        or requested_mask != denied_mask
    ):
        return False
    if (
        operation == "open"
        and name == "/"
        and comm == "find"
        and requested_mask == "r"
    ):
        return True
    return (
        re.fullmatch(
            r"/tmp/virt-host-lxc-configs[.][A-Za-z0-9]+",
            name,
        )
        is not None
        and (operation, requested_mask)
        in {
            ("mknod", "c"),
            ("open", "r"),
            ("open", "wc"),
            ("open", "wrc"),
            ("truncate", "w"),
            ("unlink", "d"),
        }
    )


def is_libvirt_session_lock_access(
    profile,
    operation,
    requested_mask,
    denied_mask,
    name,
    comm,
    fsuid,
    ouid,
):
    if (
        profile
        not in {
            "managed-virt-session-storage",
            "managed-virt-manager-virtops",
        }
        or comm != "virsh"
        or requested_mask != denied_mask
        or not fsuid
        or fsuid != ouid
    ):
        return False
    match = re.fullmatch(
        r"/run/user/([0-9]+)/libvirt/libvirtd[.]lock",
        name,
    )
    if match is None or match.group(1) != fsuid:
        return False
    return (operation, requested_mask) in {
        ("file_lock", "wk"),
        ("mknod", "c"),
        ("open", "wrc"),
        ("unlink", "d"),
    }


current_network_masks = {
    "accept": "accept",
    "bind": "bind",
    "connect": "connect",
    "create": "create",
    "getpeername": "getattr",
    "getsockname": "getattr",
    "getsockopt": "getopt",
    "listen": "listen",
    "recvmsg": "receive",
    "sendmsg": "send",
    "setsockopt": "setopt",
    "socket_shutdown": "shutdown",
}


def classify_current_whisper_evidence(fields):
    if fields.get("profile") != "managed-whisper-record-toggle":
        return None
    operation = fields.get("operation", "")
    requested_mask = fields.get("requested_mask", "")
    denied_mask = fields.get("denied_mask", "")
    if requested_mask != denied_mask:
        return None
    name = decode_audit_value(fields.get("name", ""))
    comm = decode_audit_text(fields.get("comm", ""))

    if (
        whisper_child_transitions_source_eliminated
        and operation == "exec"
        and requested_mask == "x"
        and comm == "whisper-record-"
        and fields.get("info") == "no new privs"
        and fields.get("error") == "-1"
        and (
            (
                name == "/usr/bin/curl"
                and fields.get("target")
                in {
                    "whisper-http-client",
                    "managed-whisper-record-toggle//whisper-http-client",
                }
            )
            or (
                name
                in {
                    "/pool/build/whisper/output/bin/whisper-server",
                    "/data/whisper/bin/whisper-server",
                }
                and fields.get("target")
                in {
                    "whisper-server",
                    "managed-whisper-record-toggle//whisper-server",
                }
            )
        )
    ):
        return "whisper_child_transition_source_eliminated"

    if not whisper_child_transitions_source_eliminated:
        return None
    expected_network_mask = current_network_masks.get(operation)
    if (
        expected_network_mask
        and requested_mask == expected_network_mask
        and fields.get("class") == "net"
        and fields.get("family") == "inet"
        and fields.get("sock_type") == "stream"
        and fields.get("protocol") == "6"
        and fields.get("info") == "failed af match"
        and fields.get("error") == "-13"
    ):
        if comm == "curl":
            return "whisper_http_child_network"
        if comm == "whisper-server":
            return "whisper_server_child_network"

    cuda_library = re.fullmatch(
        r"/usr/local/cuda-[^/]+/targets/x86_64-linux/lib/"
        r"lib(?:cublas|cublasLt|cudart)[.]so[.][0-9.]+",
        name,
    )
    if comm == "whisper-server":
        if (
            operation == "open"
            and requested_mask == "r"
            and (
                name in {"/proc/devices", "/proc/sys/vm/mmap_min_addr"}
                or re.fullmatch(r"/proc/[0-9]+/cmdline", name)
                or cuda_library is not None
            )
        ):
            return "whisper_server_child_files"
        if (
            operation == "file_mmap"
            and requested_mask == "rm"
            and cuda_library is not None
        ):
            return "whisper_server_child_files"
    return None


def classify_current_vivaldi_bwrap_evidence(fields):
    if fields.get("profile") != "vivaldi-bin//null-/usr/bin/bwrap":
        return None
    operation = fields.get("operation", "")
    requested_mask = fields.get("requested_mask", "")
    denied_mask = fields.get("denied_mask", "")
    name = decode_audit_value(fields.get("name", ""))
    if (
        not vivaldi_bwrap_source_eliminated
        or decode_audit_text(fields.get("comm", "")) != "bwrap"
        or requested_mask != denied_mask
    ):
        return None
    if (
        operation == "capable"
        and not requested_mask
        and fields.get("capname")
        in {"setpcap", "net_admin", "sys_admin", "sys_ptrace"}
    ):
        return "vivaldi_bwrap_capabilities"
    if (
        operation == "ptrace"
        and requested_mask in {"read", "readby"}
        and fields.get("peer") == "vivaldi-bin//null-/usr/bin/bwrap"
    ):
        return "vivaldi_bwrap_self_ptrace"
    if (
        operation == "file_inherit"
        and requested_mask in {"a", "r", "w", "wr"}
        and (
            re.fullmatch(
                r"/dev/shm/[.][.]com[.]vivaldi[.]Vivaldi[.][A-Za-z0-9]+",
                name,
            )
            or re.fullmatch(
                r"/home/[^/]+/[.]config/vivaldi/.+",
                name,
            )
        )
    ):
        return "vivaldi_bwrap_inherited_state"
    if operation == "file_inherit" and (
        (
            requested_mask == "r"
            and name
            in {
                "/dev/null",
                "/opt/vivaldi/locales/en-US.pak",
                "/opt/vivaldi/resources.pak",
                "/opt/vivaldi/v8_context_snapshot.bin",
                "/opt/vivaldi/vivaldi_100_percent.pak",
                "/opt/vivaldi/vivaldi_200_percent.pak",
            }
        )
        or (
            requested_mask == "wr"
            and re.fullmatch(r"/dev/dri/renderD[0-9]+", name)
        )
    ):
        return "vivaldi_bwrap_inherited_runtime"
    if (
        operation == "getattr"
        and requested_mask == "r"
        and not name
        and fields.get("info") == "Failed name lookup - disconnected path"
        and fields.get("error") == "-13"
    ):
        return "vivaldi_bwrap_attached_disconnected"
    if (
        operation == "open"
        and requested_mask == "wr"
        and re.fullmatch(r"proc/[0-9]+/uid_map", name)
        and fields.get("info") == "Failed name lookup - disconnected path"
        and fields.get("error") == "-13"
    ):
        return "vivaldi_bwrap_attached_disconnected"

    read_path = (
        name
        in {
            "/dev/dri/renderD128",
            "/dev/null",
            "/etc/ld.so.cache",
            "/proc/filesystems",
            "/proc/sys/kernel/overflowgid",
            "/proc/sys/kernel/overflowuid",
            "/usr/bin/bwrap",
            "/opt/vivaldi/locales/en-US.pak",
            "/opt/vivaldi/resources.pak",
            "/opt/vivaldi/v8_context_snapshot.bin",
            "/opt/vivaldi/vivaldi_100_percent.pak",
            "/opt/vivaldi/vivaldi_200_percent.pak",
        }
        or re.fullmatch(r"/proc/[0-9]+/fd/", name)
        or re.fullmatch(
            r"/usr/lib/[^/]+/(?:ld-linux-[^/]+[.]so[.]2|"
            r"lib(?:c|cap|gcc_s|m|pcre2-8|selinux)[.]so[^/]*)",
            name,
        )
        or re.fullmatch(
            r"/var/opt/vivaldi/media-codecs-[^/]+(?:/|/libffmpeg[.]so)",
            name,
        )
    )
    if read_path and (
        (operation in {"getattr", "open"} and requested_mask == "r")
        or (operation == "file_mmap" and requested_mask in {"r", "rm"})
    ):
        return "vivaldi_bwrap_runtime_files"
    return None


def classify_current_webkit_evidence(fields):
    profile = fields.get("profile", "")
    operation = fields.get("operation", "")
    requested_mask = fields.get("requested_mask", "")
    denied_mask = fields.get("denied_mask", "")
    name = decode_audit_value(fields.get("name", ""))

    null_webkit_match = re.fullmatch(
        r"(gridline|qoredb)//null-/usr/lib/[^/]+/webkit2gtk-4[.]1/"
        r"WebKit(?:Network|Web)Process",
        profile,
    )
    if null_webkit_match is not None:
        app_name = null_webkit_match.group(1)
        if (
            app_name == "gridline"
            and gridline_webkit_source_eliminated
        ) or (
            app_name == "qoredb"
            and qoredb_webkit_source_eliminated
        ):
            return "webkit_null_child_source_eliminated"
        return None

    if (
        profile == "gridline//null-/usr/bin/bwrap"
        and gridline_webkit_source_eliminated
    ):
        return "gridline_webkit_bwrap_source_eliminated"

    if profile not in {"gridline", "qoredb"}:
        return None
    source_covered = (
        gridline_webkit_source_eliminated
        if profile == "gridline"
        else qoredb_webkit_source_eliminated
    )
    if not source_covered or requested_mask != denied_mask:
        return None

    if (
        operation == "exec"
        and requested_mask == "x"
        and (
            re.fullmatch(
                r"/usr/lib/[^/]+/webkit2gtk-4[.]1/"
                r"WebKit(?:Network|Web)Process",
                name,
            )
            or (profile == "gridline" and name == "/usr/bin/bwrap")
        )
    ):
        return "webkit_named_exec_source_eliminated"

    if (
        operation == "signal"
        and profile == "gridline"
        and requested_mask == "send"
        and fields.get("signal") == "kill"
        and fields.get("peer") == "gridline//null-/usr/bin/bwrap"
    ):
        return "gridline_webkit_bwrap_signal_source_eliminated"

    if (
        operation == "open"
        and requested_mask == "wr"
        and re.fullmatch(r"/dev/dri/card[0-9]+", name)
        and webkit_primary_drm_probe_covered
    ):
        return "webkit_primary_drm_probe_denied"

    if operation == "open" and requested_mask == "r" and (
        name in {
            "/proc/zoneinfo",
            "/sys/devices/virtual/dmi/id/chassis_type",
            "/usr/share/glycin-loaders/2+/conf.d/",
        }
        or re.fullmatch(
            r"/proc/[0-9]+/(?:cgroup|cmdline|stat|statm)",
            name,
        )
        or re.fullmatch(
            r"/sys/fs/cgroup/.+/(?:cpu[.]max|memory[.](?:current|high|max))",
            name,
        )
        or re.fullmatch(
            r"/usr/share/glycin-loaders/2[+]/conf[.]d/[^/]+[.]conf",
            name,
        )
    ):
        return "webkit_runtime_metadata"
    return None


def classify_current_chatgpt_helper_evidence(fields):
    if not chatgpt_fixed_helpers_source_eliminated:
        return None
    profile = fields.get("profile", "")
    helper_match = re.fullmatch(
        r"managed-labwc-chatgpt//null-/usr/bin/(chmod|mkdir)",
        profile,
    )
    if helper_match is not None:
        return "chatgpt_fixed_helper_source_eliminated"
    if (
        profile == "managed-labwc-chatgpt"
        and fields.get("operation") == "exec"
        and fields.get("requested_mask") == fields.get("denied_mask") == "x"
        and fields.get("name") in {"/usr/bin/chmod", "/usr/bin/mkdir"}
    ):
        return "chatgpt_fixed_helper_source_eliminated"
    return None


def classify_current_wayland_compat_evidence(fields):
    if (
        not wayland_compat_current_evidence_covered
        or fields.get("profile") != wayland_compat_profile
        or fields.get("requested_mask") != fields.get("denied_mask")
    ):
        return None
    operation = fields.get("operation", "")
    requested_mask = fields.get("requested_mask", "")
    name = decode_audit_value(fields.get("name", ""))

    if (
        operation == "exec"
        and requested_mask == "x"
        and name in {"/usr/bin/env", "/usr/bin/expr", "/usr/bin/xdg-open"}
    ):
        return "wayland_compat_fixed_helper_source_eliminated"
    if (
        name in {"/usr/bin/chromium", "/@/usr/bin/chromium"}
        and (
            (operation == "exec" and requested_mask == "x")
            or (operation == "open" and requested_mask == "r")
        )
    ):
        return "wayland_compat_chromium_explicitly_denied"
    if (
        operation == "open"
        and requested_mask == "r"
        and name
        in {
            "/usr/bin/xdg-open",
            "/@/usr/bin/lsb_release",
            "/@/usr/bin/xdg-mime",
            "/@/usr/bin/xdg-open",
        }
    ):
        return "wayland_compat_fixed_helper_read"
    if (
        operation == "mknod"
        and requested_mask == "c"
        and re.fullmatch(r"/run/user/[0-9]+/discord-ipc-[0-9]+", name)
    ):
        return "wayland_compat_discord_ipc"
    if (
        operation == "open"
        and requested_mask == "r"
        and re.fullmatch(
            r"/sys/devices/.+/(?:idProduct|idVendor|interface)",
            name,
        )
    ):
        return "wayland_compat_usb_identity"
    return None


def classify_current_policy_evidence(fields):
    category = classify_current_webkit_evidence(fields)
    if category:
        return category
    category = classify_current_chatgpt_helper_evidence(fields)
    if category:
        return category
    category = classify_current_wayland_compat_evidence(fields)
    if category:
        return category
    category = classify_current_whisper_evidence(fields)
    if category:
        return category
    category = classify_current_vivaldi_bwrap_evidence(fields)
    if category:
        return category

    profile = fields.get("profile", "")
    operation = fields.get("operation", "")
    requested_mask = fields.get("requested_mask", "")
    denied_mask = fields.get("denied_mask", "")
    name = decode_audit_value(fields.get("name", ""))
    comm = decode_audit_text(fields.get("comm", ""))
    peer = fields.get("peer", "")
    signal_name = fields.get("signal", "")
    fsuid = fields.get("fsuid", "")
    ouid = fields.get("ouid", "")

    if (
        profile == "managed-managed-network-run"
        and operation == "open"
        and requested_mask == denied_mask == "r"
        and comm == "managed-network"
        and re.fullmatch(
            r"/sys/devices/.+/net/managed-(?:eth|wifi)[0-9]+/(?:address|type)",
            name,
        )
    ):
        return "managed_network_resolved_interface_metadata"

    if profile == "managed-codex-wrapper":
        snapshot_match = re.fullmatch(
            r"/run/user/([0-9]+)/codex-devops-environment[.][A-Za-z0-9._-]+",
            name,
        )
        if (
            snapshot_match is not None
            and fsuid
            and snapshot_match.group(1) == fsuid == ouid
            and (operation, requested_mask, comm)
            in {
                ("mknod", "c", "mktemp"),
                ("open", "wrc", "mktemp"),
                ("open", "wc", "codex"),
                ("truncate", "w", "codex"),
                ("open", "r", "codex"),
                ("unlink", "d", "rm"),
            }
            and requested_mask == denied_mask
        ):
            return "codex_devops_environment_snapshot"

    if (
        profile == "managed-labwc-sync-application-launchers"
        and comm == "labwc-sync-appl"
        and re.fullmatch(
            r"/home/[^/]+/[.]config/autostart/"
            r"[.]bitwarden[.]desktop[.][A-Za-z0-9_-]+[.]desktop",
            name,
        )
        and (operation, requested_mask)
        in {
            ("mknod", "c"),
            ("open", "wrc"),
            ("chmod", "w"),
            ("rename_src", "wrd"),
        }
        and requested_mask == denied_mask
        and fsuid
        and fsuid == ouid
    ):
        return "desktop_bitwarden_launcher_atomic_replace"

    if (
        profile == "managed-devops-toolchain"
        and comm == "llama-cli"
        and re.fullmatch(r"/proc/[0-9]+/task/[0-9]+/comm", name)
        and (operation, requested_mask)
        in {
            ("mknod", "c"),
            ("open", "wc"),
            ("truncate", "w"),
        }
        and requested_mask == denied_mask
        and fsuid
        and fsuid == ouid
    ):
        return "devops_thread_name"

    own_fd_match = re.fullmatch(r"/proc/([0-9]+)/fd/", name)
    if (
        profile == "managed-labwc-managed-wayland-compat-app"
        and comm == "labwc-managed-w"
        and operation == "open"
        and requested_mask == denied_mask == "r"
        and own_fd_match is not None
        and own_fd_match.group(1) == fields.get("pid")
        and fsuid
        and fsuid == ouid
    ):
        return "wayland_compat_own_fd_inventory"

    if profile == "managed-wayland-compat-slirp4netns" and comm == "slirp4netns":
        if (
            operation == "file_inherit"
            and requested_mask == denied_mask == "r"
            and re.fullmatch(
                r"/(?:run/user/[0-9]+|tmp)/"
                r"labwc-(?:discord|zoom)-sandbox-[^/]+/slirp4netns[.]stderr",
                name,
            )
            and fsuid
            and fsuid == ouid
        ):
            return "wayland_compat_slirp_diagnostic"
        if (
            operation == "open"
            and requested_mask == denied_mask == "r"
            and name == "/run/systemd/resolve/stub-resolv.conf"
        ):
            return "wayland_compat_slirp_resolver"

    if (
        profile == "managed-labwc-network-control-menu"
        and operation == "open"
        and requested_mask == denied_mask == "r"
        and comm == "find"
        and re.fullmatch(r"/home/[^/]+(?:/.+)?/", name)
        and fsuid
        and fsuid == ouid
    ):
        return "network_control_home_directories"

    if profile == "managed-codex-wrapper//codex-bwrap":
        if (
            operation == "open"
            and requested_mask == denied_mask == "r"
            and comm == "apt-cache"
            and (
                re.fullmatch(r"/var/lib/apt/lists/[^/]+", name)
                or name == "/var/lib/software/debs/Packages"
            )
        ):
            return "codex_bwrap_package_metadata"
        if (
            operation == "capable"
            and not requested_mask
            and not denied_mask
            and comm == "bwrap"
            and fields.get("capname") == "dac_read_search"
        ):
            return "codex_bwrap_dac_read_search"
        if (
            operation == "signal"
            and requested_mask == denied_mask == "receive"
            and comm == "codex"
            and peer == "managed-codex-wrapper"
            and signal_name in {"hup", "int", "term"}
        ):
            return "codex_bwrap_parent_signals"

    if profile == "vivaldi-bin":
        if (
            vivaldi_bwrap_source_eliminated
            and operation == "exec"
            and requested_mask == denied_mask == "x"
            and name == "/usr/bin/bwrap"
            and fields.get("target")
            == "vivaldi-bin//null-/usr/bin/bwrap"
        ):
            return "vivaldi_bwrap_transition_source_eliminated"
        if (
            operation
            in {"chmod", "mknod", "open", "rename_dest", "rename_src", "truncate"}
            and requested_mask == denied_mask
            and requested_mask in {"c", "r", "w", "wc", "wrd"}
            and re.fullmatch(r"/home/[^/]+/Documents/.+", name)
        ):
            return "vivaldi_documents"
        if (
            operation == "open"
            and requested_mask == denied_mask == "r"
            and (
                re.fullmatch(
                    r"/home/[^/]+/Workspace/llama-labwc/output/"
                    r"llama-(?:cuda|ram)[.]tar[.]gz",
                    name,
                )
                or re.fullmatch(
                    r"/pool/build/whisper-labwc/artifacts/"
                    r"whisper-(?:cuda|ram)[.]tar[.]gz",
                    name,
                )
            )
        ):
            return "vivaldi_build_artifacts"
        if (
            operation == "open"
            and requested_mask == denied_mask == "r"
            and (
                name == "/usr/share/glycin-loaders/2+/conf.d/"
                or re.fullmatch(
                    r"/usr/share/glycin-loaders/2[+]/conf[.]d/"
                    r"glycin-(?:heif|image-rs|jxl|svg)[.]conf",
                    name,
                )
            )
        ):
            return "vivaldi_glycin_configs"
        if (
            operation == "open"
            and requested_mask == denied_mask == "r"
            and re.fullmatch(
                r"/home/[^/]+/[.]local/share/gvfs-metadata/"
                r"root(?:-[0-9a-f]+[.]log)?",
                name,
            )
        ):
            return "vivaldi_gvfs_metadata"
        if (
            vivaldi_disconnected_paths_covered
            and operation == "getattr"
            and requested_mask == denied_mask == "r"
            and not name
            and fields.get("info") == "Failed name lookup - disconnected path"
            and fields.get("error") == "-13"
        ):
            return "vivaldi_attached_disconnected"

    if profile == "managed-codex-slirp4netns":
        if (
            operation == "open"
            and requested_mask == denied_mask == "r"
            and comm == "slirp4netns"
            and name == "/run/systemd/resolve/stub-resolv.conf"
        ):
            return "codex_slirp_resolver"
        if (
            operation == "signal"
            and requested_mask == denied_mask == "receive"
            and peer == "unconfined"
            and signal_name in {"exists", "hup"}
        ):
            return "codex_slirp_supervisor_signals"
        if (
            operation == "ptrace"
            and requested_mask == denied_mask == "readby"
            and comm == "aa-status"
            and peer == "aa-status-reader"
        ):
            return "slirp_status_reader"

    if (
        profile == "managed-devops-toolchain"
        and operation == "open"
        and requested_mask == denied_mask == "r"
        and comm == "esbuild"
        and name == "/home/"
    ):
        return "devops_home_root"

    if profile == "managed-chatgpt-slirp4netns":
        if (
            operation == "open"
            and requested_mask == denied_mask == "r"
            and comm == "slirp4netns"
            and name == "/run/systemd/resolve/stub-resolv.conf"
        ):
            return "chatgpt_slirp_resolver"
        if (
            operation == "file_inherit"
            and requested_mask == denied_mask == "r"
            and comm == "slirp4netns"
            and re.fullmatch(
                r"/run/user/[0-9]+/labwc-chatgpt-sandbox-[^/]+/"
                r"slirp4netns[.]stderr",
                name,
            )
            and fsuid
            and fsuid == ouid
        ):
            return "chatgpt_slirp_stderr"
        if (
            operation == "ptrace"
            and requested_mask == denied_mask == "readby"
            and comm == "aa-status"
            and peer == "aa-status-reader"
        ):
            return "slirp_status_reader"

    if (
        profile == "managed-labwc-managed-app"
        and operation == "signal"
        and requested_mask == denied_mask == "send"
        and signal_name == "kill"
        and peer == "managed-labwc-managed-app//managed-app-bwrap"
    ):
        return "managed_app_bwrap_signals"
    if (
        profile == "managed-labwc-managed-app//managed-app-bwrap"
        and operation == "signal"
        and requested_mask == denied_mask == "receive"
        and signal_name == "kill"
        and peer == "managed-labwc-managed-app"
    ):
        return "managed_app_bwrap_signals"
    if (
        profile == "managed-labwc-chatgpt"
        and operation == "open"
        and requested_mask == denied_mask == "r"
        and comm == "labwc-managed-a"
        and re.fullmatch(r"/proc/[0-9]+/fd/", name)
        and fsuid
        and fsuid == ouid
    ):
        return "chatgpt_own_fd_inventory"
    return None


for line_number, line in enumerate(
    log_path.open(encoding="utf-8", errors="replace"),
    1,
):
    if 'apparmor="ALLOWED"' not in line:
        continue
    fields = {
        match.group("key"): (
            match.group("quoted")
            if match.group("quoted") is not None
            else match.group("bare")
        )
        for match in field_pattern.finditer(line)
    }
    profile = fields.get("profile", "")
    base_profile = profile.split("//", 1)[0]
    operation = fields.get("operation", "")
    name = decode_audit_value(fields.get("name", ""))
    comm = decode_audit_text(fields.get("comm", ""))
    peer = fields.get("peer", "")
    signal_name = fields.get("signal", "")
    family = fields.get("family", "")
    sock_type = fields.get("sock_type", "")
    protocol = fields.get("protocol", "")
    requested_mask = fields.get("requested_mask", "")
    denied_mask = fields.get("denied_mask", "")
    capname = fields.get("capname", "")
    info = fields.get("info", "")
    addr = fields.get("addr", "")
    fsuid = fields.get("fsuid", "")
    ouid = fields.get("ouid", "")
    pid = fields.get("pid", "")

    if profile.startswith("usr.bin.zoom") and fsuid == "0":
        ignored_root_zoom += 1
        continue

    current_category = classify_current_policy_evidence(fields)
    if current_category:
        category = current_category
    elif (
        labwc_session_child_source_eliminated
        and profile == "managed-labwc-session-child"
    ):
        category = "labwc_session_child_source_eliminated"
    elif (
        chatgpt_legacy_transition_eliminated
        and profile in chatgpt_legacy_profiles
    ):
        category = "chatgpt_legacy_vendor_profiles_source_eliminated"
    elif is_bwrap_constructor_bindfile(
        profile,
        operation,
        requested_mask,
        denied_mask,
        name,
        comm,
    ):
        category = "bwrap_constructor_bindfiles"
    elif is_virt_host_runtime_access(
        profile,
        operation,
        requested_mask,
        denied_mask,
        name,
        comm,
    ):
        category = "virt_host_bounded_runtime"
    elif is_libvirt_session_lock_access(
        profile,
        operation,
        requested_mask,
        denied_mask,
        name,
        comm,
        fsuid,
        ouid,
    ):
        category = "libvirt_session_lock"
    elif (
        profile == "managed-virt-session-storage"
        and comm == "virsh"
        and operation == "open"
        and requested_mask == denied_mask
        and (
            (name == "/dev/tty" and requested_mask == "wr")
            or (
                name == "/sys/devices/system/node/"
                and requested_mask == "r"
            )
        )
    ):
        category = "virt_session_storage_runtime"
    elif (
        codex_installation_id_descriptor_source_eliminated
        and profile == "managed-codex-slirp4netns"
        and comm == "slirp4netns"
        and operation == "file_inherit"
        and re.fullmatch(
            r"/data/codex/runtime/[.]control/"
            r"launch[.][A-Za-z0-9]+/installation_id",
            name,
        )
        is not None
        and requested_mask == denied_mask == "r"
        and fsuid == ouid
    ):
        category = "codex_installation_id_descriptor_source_eliminated"
    elif (
        profile == "managed-devops-toolchain"
        and comm == "rustc"
        and operation == "open"
        and name == "/"
        and requested_mask == denied_mask == "r"
    ):
        category = "devops_root_inventory"
    elif (
        profile == "managed-unattended-upgrades-notify"
        and comm == "find"
        and operation == "open"
        and name == "/"
        and requested_mask == denied_mask == "r"
        and fsuid == ouid == "0"
    ):
        category = "unattended_upgrades_root_inventory"
    elif (
        profile == "managed-labwc-sync-application-launchers"
        and comm == "labwc-sync-appl"
        and operation == "open"
        and re.fullmatch(
            r"/home/[^/]+/[.]config/autostart/",
            name,
        )
        is not None
        and requested_mask == denied_mask == "r"
        and fsuid
        and fsuid == ouid
    ):
        category = "desktop_user_autostart_inventory"
    elif (
        profile == "managed-labwc-ai-copilots"
        and operation == "open"
        and name == f"/proc/{fields.get('pid', '')}/mountinfo"
        and comm == "fzf"
        and requested_mask == denied_mask == "r"
        and fsuid == ouid
    ):
        category = "ai_copilots_fzf_self_mountinfo"
    elif (
        profile == "managed-labwc-ai-copilots"
        and operation == "open"
        and re.fullmatch(
            r"/home/[^/]+/[.]config/fzf/default-opts",
            name,
        )
        and comm == "fzf"
        and requested_mask == denied_mask == "r"
        and fsuid == ouid
    ):
        category = "ai_copilots_fzf_default_options"
    elif (
        profile == "managed-labwc-ai-copilots"
        and operation == "exec"
        and name == "/usr/bin/cat"
        and comm == "labwc-ai-copilo"
        and requested_mask == denied_mask == "x"
        and fields.get("target", "") == ai_copilots_legacy_cat_profile
    ):
        category = "ai_copilots_cat_inherited_exec"
    elif is_ai_copilots_legacy_cat_runtime(
        profile,
        operation,
        requested_mask,
        denied_mask,
        name,
        comm,
    ):
        category = "legacy_ai_copilots_cat_null_child"
    elif (
        profile
        == "managed-labwc-managed-wayland-compat-app"
        "//managed-wayland-compat-app-bwrap"
        and operation == "exec"
        and name == "/opt/xwayland/usr/bin/Xwayland"
        and comm == "labwc-zoom-disc"
        and requested_mask == denied_mask == "x"
        and info in {"profile transition not found", "no new privs"}
        and fields.get("target", "")
        == (
            "managed-labwc-managed-wayland-compat-app"
            "//managed-wayland-compat-app-bwrap"
            "//null-/opt/xwayland/usr/bin/Xwayland"
        )
    ):
        category = "obsolete_wayland_compat_xwayland_transition"
    elif (
        profile == "managed-labwc-managed-app"
        and operation == "exec"
        and name == "/usr/share/spotify/spotify"
        and requested_mask == denied_mask == "x"
        and fields.get("target", "") == spotify_legacy_profile
    ):
        category = "spotify_parent_named_transition"
    elif (
        profile == "managed-satty-runtime"
        and requested_mask == denied_mask
        and (
            (
                operation == "exec"
                and name == "/usr/bin/bwrap"
                and requested_mask == "x"
                and fields.get("target", "") == satty_legacy_bwrap_profile
            )
            or (
                operation == "signal"
                and signal_name == "kill"
                and requested_mask == "send"
                and peer == satty_legacy_bwrap_profile
            )
            or (
                operation == "open"
                and requested_mask == "r"
                and (
                    re.fullmatch(
                        r"/usr/share/glycin-loaders/2\+/conf[.]d/"
                        r"(?:|[^/]+[.]conf)",
                        name,
                    )
                    or (
                        fields.get("pid", "")
                        and name
                        == f"/proc/{fields.get('pid', '')}/cmdline"
                    )
                )
            )
        )
    ):
        category = "satty_parent_named_boundary"
    elif (
        profile == satty_legacy_bwrap_profile
        and (
            (
                comm == "bwrap"
                and (
                    (
                        operation == "capable"
                        and capname
                        in {
                            "net_admin",
                            "setpcap",
                            "sys_admin",
                            "sys_ptrace",
                        }
                    )
                    or (
                        operation == "exec"
                        and requested_mask == denied_mask == "x"
                        and info in {"", "no new privs"}
                        and name
                        in {
                            "/usr/bin/true",
                            "/usr/libexec/glycin-loaders/2+/"
                            "glycin-image-rs",
                        }
                        and fields.get("target", "")
                        == f"{satty_legacy_bwrap_profile}//null-{name}"
                    )
                    or (
                        operation == "file_inherit"
                        and requested_mask == denied_mask == "r"
                        and (
                            name == "/dev/null"
                            or re.fullmatch(
                                r"/run/user/[0-9]+/labwc-capture/"
                                r"satty-source[.][A-Za-z0-9]+[.]png",
                                name,
                            )
                        )
                    )
                    or (
                        operation == "file_mmap"
                        and requested_mask == denied_mask
                        and requested_mask in {"r", "rm"}
                        and (
                            name == "/usr/bin/bwrap"
                            or name.startswith("/usr/lib/")
                        )
                    )
                    or (
                        operation in {"getattr", "open"}
                        and requested_mask == denied_mask == "r"
                        and is_satty_bwrap_path(name)
                    )
                    or (
                        operation in {"mkdir", "mknod", "symlink"}
                        and requested_mask == denied_mask == "c"
                        and is_satty_bwrap_path(name)
                    )
                    or (
                        operation == "open"
                        and requested_mask == denied_mask
                        and requested_mask in {"wc", "wr"}
                        and is_satty_bwrap_path(name)
                    )
                    or (
                        operation == "ptrace"
                        and requested_mask == denied_mask
                        and requested_mask in {"read", "readby"}
                        and peer == satty_legacy_bwrap_profile
                    )
                )
            )
            or (
                comm in {"glycin-image-rs", "true"}
                and operation in {"file_mmap", "getattr", "open"}
                and requested_mask == denied_mask
                and requested_mask in {"r", "rm"}
                and is_satty_payload_runtime_path(name)
            )
        )
    ):
        category = "satty_bwrap_named_child"
    elif is_spotify_legacy_runtime(
        profile,
        operation,
        requested_mask,
        denied_mask,
        name,
        peer,
        fields.get("target", ""),
        info,
    ):
        category = (
            "spotify_named_runtime"
            if profile == spotify_legacy_profile
            else "spotify_named_reexec_runtime"
        )
    elif (
        profile == "managed-waypaper"
        and family in {"inet", "inet6"}
        and sock_type in {"stream", "dgram"}
        and info == "failed af match"
        and {
            "connect": "connect",
            "create": "create",
            "getsockname": "getattr",
            "setsockopt": "setopt",
        }.get(operation)
        == requested_mask
        == denied_mask
    ):
        category = "waypaper_parent_network"
    elif (
        profile == "managed-waypaper"
        and operation == "exec"
        and requested_mask == "x"
        and denied_mask == "x"
        and {
            "/usr/bin/bwrap":
                "managed-waypaper//null-/usr/bin/bwrap",
            "/usr/bin/kill":
                "managed-waypaper//null-/usr/bin/kill",
            "/usr/bin/ps":
                "managed-waypaper//null-/usr/bin/ps",
            "/usr/sbin/ldconfig":
                "managed-waypaper//null-/usr/sbin/ldconfig",
        }.get(name)
        == fields.get("target", "")
    ):
        category = "waypaper_parent_helper_transitions"
    elif (
        profile == "managed-waypaper"
        and operation == "signal"
        and signal_name == "kill"
        and requested_mask == "send"
        and denied_mask == "send"
        and peer == "managed-waypaper//null-/usr/bin/bwrap"
    ):
        category = "waypaper_parent_signal"
    elif (
        profile == "managed-waypaper"
        and (
            (
                operation == "open"
                and requested_mask == denied_mask
                and (
                    (
                        requested_mask == "r"
                        and (
                            name
                            in {
                                "/",
                                "/etc/gai.conf",
                                "/etc/host.conf",
                                "/etc/hosts",
                                "/etc/resolv.conf",
                                "/usr/share/mime/mime.cache",
                            }
                            or re.fullmatch(r"/dev/dri/card[0-9]+", name)
                            or re.fullmatch(
                                r"/home/[^/]+/[.]config/user-dirs[.]dirs",
                                name,
                            )
                            or re.fullmatch(
                                r"/usr/share/glycin-loaders/2\+/conf[.]d/"
                                r"(?:|[^/]+[.]conf)",
                                name,
                            )
                            or re.fullmatch(
                                r"/tmp/gdk-pixbuf-glycin-tmp[.]"
                                r"[A-Za-z0-9]+",
                                name,
                            )
                        )
                    )
                    or (
                        requested_mask == "wrc"
                        and re.fullmatch(
                            r"/tmp/gdk-pixbuf-glycin-tmp[.]"
                            r"[A-Za-z0-9]+",
                            name,
                        )
                    )
                )
            )
            or (
                operation == "mknod"
                and requested_mask == "c"
                and denied_mask == "c"
                and re.fullmatch(
                    r"/tmp/gdk-pixbuf-glycin-tmp[.][A-Za-z0-9]+",
                    name,
                )
            )
            or (
                operation == "unlink"
                and requested_mask == "d"
                and denied_mask == "d"
                and re.fullmatch(
                    r"/tmp/gdk-pixbuf-glycin-tmp[.][A-Za-z0-9]+",
                    name,
                )
            )
        )
    ):
        category = "waypaper_parent_runtime_files"
    elif (
        profile == "managed-waypaper//waypaper-bwrap"
        and comm == "bwrap"
        and (
            (
                operation == "open"
                and name == "/"
                and requested_mask == denied_mask == "r"
            )
            or (
                operation == "exec"
                and re.fullmatch(
                    r"/usr/libexec/glycin-loaders/2\+/"
                    r"(?:glycin-image-rs|glycin-svg)",
                    name,
                )
                and requested_mask == denied_mask == "x"
                and info == "no new privs"
                and fields.get("target", "") == "waypaper-glycin-loader"
            )
        )
    ):
        category = "waypaper_named_bwrap_compatibility"
    elif (
        profile == "managed-waypaper//null-/usr/bin/bwrap"
        and comm == "bwrap"
        and (
            (
                operation == "capable"
                and capname in waypaper_bwrap_capabilities
            )
            or (
                operation == "exec"
                and requested_mask == "x"
                and denied_mask == "x"
                and (
                    name == "/usr/bin/true"
                    or re.fullmatch(
                        r"/usr/libexec/glycin-loaders/2\+/"
                        r"(?:glycin-image-rs|glycin-svg)",
                        name,
                    )
                )
            )
            or (
                operation
                in {
                    "file_inherit",
                    "file_mmap",
                    "getattr",
                    "mkdir",
                    "mknod",
                    "open",
                    "symlink",
                }
                and is_waypaper_bwrap_path(name)
            )
            or (
                operation == "ptrace"
                and requested_mask in {"read", "readby"}
                and denied_mask == requested_mask
                and peer == "managed-waypaper//null-/usr/bin/bwrap"
            )
        )
    ):
        category = "waypaper_bwrap_constructor"
    elif (
        profile == "managed-waypaper//null-/usr/bin/bwrap"
        and comm == "ps"
        and operation == "ptrace"
        and requested_mask == "readby"
        and denied_mask == "readby"
        and peer == "managed-waypaper//null-/usr/bin/ps"
    ):
        category = "waypaper_bwrap_ps_peer"
    elif (
        profile == "managed-waypaper//null-/usr/bin/bwrap"
        and comm == "true"
        and operation in {"file_mmap", "getattr", "open"}
        and requested_mask == denied_mask
        and requested_mask in {"r", "rm"}
        and is_waypaper_runtime_library(name)
    ):
        category = "waypaper_bwrap_true_runtime"
    elif (
        profile == "managed-waypaper//null-/usr/bin/bwrap"
        and comm in {"glycin-image-rs", "glycin-svg"}
        and operation in {"file_mmap", "getattr", "open"}
        and requested_mask == denied_mask
        and requested_mask in {"r", "rm"}
        and is_waypaper_runtime_library(name)
    ):
        category = "waypaper_glycin_loader_runtime"
    elif (
        profile == "managed-waypaper//null-/usr/bin/ps"
        and (
            (
                operation == "capable"
                and capname == "sys_ptrace"
            )
            or (
                operation == "ptrace"
                and requested_mask == "read"
                and denied_mask == "read"
                and peer in waypaper_ps_peers
            )
            or (
                operation in {"file_mmap", "getattr", "open"}
                and requested_mask == denied_mask
                and requested_mask in {"r", "rm"}
                and (
                    name == "/usr/bin/ps"
                    or is_waypaper_ps_path(name)
                )
            )
        )
    ):
        category = "waypaper_ps_helper"
    elif (
        profile == "managed-waypaper//null-/usr/bin/kill"
        and operation in {"file_mmap", "getattr", "open"}
        and requested_mask == denied_mask
        and requested_mask in {"r", "rm"}
        and (
            name == "/usr/bin/kill"
            or is_waypaper_runtime_library(name)
        )
    ):
        category = "waypaper_kill_helper"
    elif (
        profile == "managed-waypaper//null-/usr/sbin/ldconfig"
        and (
            (
                operation == "file_inherit"
                and name == "/dev/null"
                and requested_mask == "wr"
                and denied_mask == "wr"
            )
            or (
                operation == "file_mmap"
                and name == "/usr/sbin/ldconfig"
                and requested_mask == "r"
                and denied_mask == "r"
            )
            or (
                operation in {"getattr", "open"}
                and name == "/etc/ld.so.cache"
                and requested_mask == "r"
                and denied_mask == "r"
            )
        )
    ):
        category = "waypaper_ldconfig_helper"
    elif (
        profile == "managed-codex-slirp4netns"
        and comm == "java"
        and operation == "ptrace"
        and requested_mask == denied_mask == "readby"
        and peer == "managed-devops-toolchain"
    ):
        category = "codex_slirp_devops_process_inventory"
    elif (
        profile == "managed-codex-slirp4netns"
        and operation == "open"
        and name in {
            "/etc/resolv.conf",
            "/run/resolvconf/resolv.conf",
        }
        and requested_mask == "r"
        and denied_mask == "r"
    ):
        category = "codex_slirp_resolver"
    elif (
        profile == "managed-labwc-chatgpt"
        and comm == "labwc-managed-a"
        and operation == "open"
        and name == "/run/resolvconf/resolv.conf"
        and requested_mask == denied_mask == "r"
    ):
        category = "chatgpt_host_resolver"
    elif (
        profile == "managed-labwc-chatgpt//chatgpt-dbus-proxy"
        and comm == "xdg-dbus-proxy"
        and operation == "mknod"
        and re.fullmatch(
            r"/run/user/[0-9]+/labwc-chatgpt-sandbox-[A-Za-z0-9]+/"
            r"system-bus",
            name,
        )
        and requested_mask == denied_mask == "c"
    ):
        category = "chatgpt_system_bus_proxy"
    elif (
        profile == "managed-labwc-chatgpt//chatgpt-bwrap"
        and comm == "ThreadPoolForeg"
        and operation == "exec"
        and name == "/usr/bin/xdg-open"
        and info == "no new privs"
        and fields.get("target") == "unconfined"
        and requested_mask == denied_mask == "x"
    ):
        category = "chatgpt_xdg_open_no_new_privs"
    elif (
        profile == "managed-labwc-chatgpt//chatgpt-bwrap"
        and comm == "vivaldi-bin"
        and operation == "mkdir"
        and name
        in {
            "/etc/opt/",
            "/etc/opt/chrome/",
            "/etc/opt/chrome/native-messaging-hosts/",
        }
        and requested_mask == denied_mask == "c"
    ):
        category = "chatgpt_vivaldi_native_messaging_probe"
    elif (
        profile == "managed-codex-slirp4netns"
        and family == "inet"
        and sock_type == "stream"
        and info == "failed type match"
        and protocol in {"0", "6"}
        and {
            "connect": "connect",
            "create": "create",
            "getsockopt": "getopt",
            "recvmsg": "receive",
            "sendmsg": "send",
            "setsockopt": "setopt",
            "socket_shutdown": "shutdown",
        }.get(operation)
        == requested_mask
        == denied_mask
    ):
        category = "codex_slirp_inet_stream"
    elif (
        profile
        == "managed-labwc-managed-wayland-compat-app"
        "//managed-wayland-compat-app-bwrap"
        and (
            re.fullmatch(
                r"/home/[^/]+/[.]config/discord/"
                r"(?:Discord|app-[^/]+(?:/.*)?)",
                name,
            )
            or (
                name == "/proc/self/exe"
                and re.search(
                    r"/home/[^/]+/[.]config/discord/app-[^/]+/Discord$",
                    fields.get("target", ""),
                )
            )
        )
    ):
        category = "discord_self_update_source_eliminated"
    elif (
        profile == wayland_compat_profile
        and re.fullmatch(
            r"/run/user/[0-9]+/server-[0-9]+[.]xkm",
            name,
        )
        and (
            (
                operation == "mknod"
                and requested_mask == denied_mask == "c"
            )
            or (
                operation == "open"
                and requested_mask == denied_mask
                and requested_mask in {"r", "wc"}
            )
            or (
                operation == "unlink"
                and requested_mask == denied_mask == "d"
            )
        )
    ):
        category = "wayland_compat_xkb_keymap"
    elif (
        profile == wayland_compat_profile
        and (
            re.fullmatch(r"/home/[^/]+/[.]config/pulse(?:/.*)?", name)
            or re.fullmatch(r"/run/user/[0-9]+/pulse/", name)
        )
    ):
        category = "wayland_compat_pipewire_client_state"
    elif (
        profile == wayland_compat_profile
        and re.fullmatch(
            r"/home/[^/]+/[.]config/zoom(?:us)?[.]conf(?:[.][^/]*)?",
            name,
        )
        and (
            (
                operation == "mknod"
                and requested_mask == "c"
                and denied_mask == "c"
            )
            or (
                operation == "open"
                and requested_mask in {"r", "wc", "wrc"}
                and denied_mask == requested_mask
            )
            or (
                operation == "truncate"
                and requested_mask == "w"
                and denied_mask == "w"
            )
            or (
                operation == "file_lock"
                and requested_mask == denied_mask == "wk"
            )
            or (
                operation == "link"
                and requested_mask == denied_mask == "l"
            )
            or (
                operation == "chmod"
                and requested_mask == denied_mask == "w"
            )
            or (
                operation == "unlink"
                and requested_mask == denied_mask == "d"
            )
            or (
                operation == "rename_src"
                and requested_mask == denied_mask == "wrd"
            )
            or (
                operation == "rename_dest"
                and requested_mask == denied_mask == "wc"
            )
        )
    ):
        category = "zoom_persistent_config"
    elif (
        profile == wayland_compat_profile
        and operation == "exec"
        and name in wayland_compat_exec_targets
        and requested_mask == denied_mask == "x"
        and fields.get("target", "")
        == (
            f"{wayland_compat_profile}//null-"
            f"{wayland_compat_exec_targets[name]}"
        )
        and info in {"", "no new privs"}
    ):
        category = "wayland_compat_diagnostic_exec"
    elif (
        profile == wayland_compat_profile
        and operation == "open"
        and name == "/usr/share/iproute2/group"
        and requested_mask == denied_mask == "r"
    ):
        category = "wayland_compat_iproute_metadata"
    elif (
        profile == wayland_compat_profile
        and operation == "open"
        and name in {
            "/proc/bus/pci/devices",
            "/usr/share/misc/pci.ids",
        }
        and requested_mask == denied_mask == "r"
    ):
        category = "wayland_compat_pci_metadata"
    elif (
        profile == wayland_compat_profile
        and operation == "open"
        and name == "/usr/share/xdg-desktop-portal/portals/"
        and requested_mask == denied_mask == "r"
    ):
        category = "wayland_compat_portal_inventory"
    elif (
        profile == wayland_compat_profile
        and operation == "mkdir"
        and re.fullmatch(
            r"/home/[^/]+/[.]cache/qtshadercache-[^/]+/",
            name,
        )
        and requested_mask == denied_mask == "c"
    ):
        category = "wayland_compat_qt_shader_cache"
    elif (
        profile == wayland_compat_profile
        and operation == "open"
        and requested_mask == denied_mask == "r"
        and (
            name == "/sys/kernel/cpu_byteorder"
            or name == "/sys/devices/system/cpu/hotplug/states"
            or name == "/sys/devices/system/cpu/vulnerabilities/"
            or re.fullmatch(
                r"/sys/devices/system/cpu/vulnerabilities/[^/]+",
                name,
            )
            or re.fullmatch(
                r"/sys/devices/system/cpu/cpu[0-9]+/hotplug/state",
                name,
            )
            or re.fullmatch(
                r"/sys/devices/system/cpu/cpu[0-9]+/topology/"
                r"(?:core_id|core_siblings|thread_siblings)",
                name,
            )
            or re.fullmatch(
                r"/sys/devices/system/cpu/cpu[0-9]+/cache/"
                r"index[0-9]+/(?:coherency_line_size|number_of_sets|"
                r"physical_line_partition|shared_cpu_map|type|"
                r"ways_of_associativity)",
                name,
            )
            or re.fullmatch(
                r"/sys/devices/system/cpu/cpufreq/policy[0-9]+/"
                r"cpuinfo_min_freq",
                name,
            )
        )
    ):
        category = "wayland_compat_cpu_metadata"
    elif (
        profile == wayland_compat_profile
        and operation == "open"
        and re.fullmatch(
            r"/sys/devices/.+/power_supply/[^/]+/"
            r"(?:capacity|online|type)",
            name,
        )
        and requested_mask == denied_mask == "r"
    ):
        category = "wayland_compat_power_supply_metadata"
    elif (
        profile == wayland_compat_profile
        and operation == "open"
        and name == "/dev/console"
        and requested_mask == "wr"
        and denied_mask == "wr"
    ):
        category = "wayland_compat_private_console"
    elif (
        profile
        == "managed-labwc-managed-wayland-compat-app"
        "//managed-wayland-compat-app-bwrap"
        and operation == "open"
        and re.fullmatch(r"/proc/[0-9]+/mem", name)
        and requested_mask == "r"
        and denied_mask == "r"
    ):
        category = "wayland_compat_crashpad_memory"
    elif (
        profile == "managed-whisper-record-toggle"
        and operation == "open"
        and re.fullmatch(r"/home/[^/]+/", name)
        and requested_mask == "r"
        and denied_mask == "r"
    ):
        category = "whisper_home_directory"
    elif (
        profile == "managed-whisper-record-toggle"
        and operation == "open"
        and name == "/data/whisper/bin/"
        and requested_mask == "r"
        and denied_mask == "r"
    ):
        category = "whisper_binary_directory"
    elif (
        profile == "managed-whisper-record-toggle"
        and re.fullmatch(
            r"/home/[^/]+/Syncthing/sleek/whisper[.]txt",
            name,
        )
        and operation in {"chmod", "file_perm"}
        and requested_mask == "w"
        and denied_mask == "w"
    ):
        category = "whisper_task_permissions"
    elif (
        profile == "managed-grub-btrfs-refresh"
        and name.startswith("/run/blkid/")
    ):
        category = "grub_blkid_cache"
    elif (
        profile == "managed-grub-btrfs-refresh"
        and name.startswith("/sys/devices/")
    ):
        category = "grub_block_sysfs"
    elif (
        profile == "managed-grub-btrfs-refresh"
        and operation == "open"
        and re.fullmatch(r"/proc/[0-9]+/mounts", name)
        and requested_mask == "r"
        and denied_mask == "r"
    ):
        category = "grub_process_mounts"
    elif (
        profile == "managed-grub-btrfs-refresh"
        and name == "/run/"
    ):
        category = "grub_run_directory"
    elif (
        profile == "managed-grub-btrfs-refresh"
        and name == "/run/lock/"
    ):
        category = "grub_lock_directory"
    elif (
        profile == "managed-grub-btrfs-refresh"
        and name == "/run/mount/utab"
    ):
        category = "grub_mount_utab"
    elif (
        profile == "managed-grub-btrfs-refresh"
        and name.startswith("/run/udev/data/")
    ):
        category = "grub_udev_data"
    elif (
        profile == "managed-grub-btrfs-refresh"
        and operation == "exec"
        and name == "/usr/bin/grub-script-check"
    ):
        category = "grub_script_check_inherited"
    elif profile.startswith(
        "managed-grub-btrfs-refresh//null-/usr/bin/grub-script-check"
    ):
        category = "grub_script_check_inherited"
    elif (
        profile == "vivaldi-bin"
        and comm == "Gamepad polling"
        and operation == "open"
        and name.startswith("/run/udev/data/")
        and requested_mask == denied_mask == "r"
    ):
        category = "vivaldi_dynamic_udev_inventory"
    elif (
        profile == "vivaldi-bin"
        and comm == "MemoryInfra"
        and operation == "open"
        and re.fullmatch(r"/proc/[0-9]+/statm", name)
        and requested_mask == denied_mask == "r"
    ):
        category = "vivaldi_cross_owner_memory_inventory"
    elif (
        profile == "managed-devops-toolchain"
        and comm == "java"
        and (
            (
                operation == "open"
                and re.fullmatch(
                    r"/proc/[0-9]+/coredump_filter",
                    name,
                )
                and requested_mask == denied_mask == "w"
            )
            or (
                operation == "capable"
                and capname == "sys_ptrace"
            )
            or (
                operation == "ptrace"
                and requested_mask == denied_mask == "read"
                and bool(peer)
            )
        )
    ):
        category = "devops_java_process_inventory"
    elif (
        profile == "managed-codex-runtime"
        and (
            (
                operation == "open"
                and name.startswith("/data/codex/usr/instructions/")
                and requested_mask == denied_mask == "r"
            )
            or (
                comm == "bwrap"
                and (
                    (
                        operation == "open"
                        and name == "/"
                        and requested_mask == denied_mask == "r"
                    )
                    or (
                        operation == "open"
                        and re.fullmatch(
                            r"/proc/[0-9]+/(?:gid_map|setgroups|uid_map)",
                            name,
                        )
                        and requested_mask == denied_mask == "w"
                    )
                    or operation in {"mount", "pivotroot", "umount"}
                    or operation == "userns_create"
                    or (
                        operation == "capable"
                        and capname
                        in {
                            "net_admin",
                            "setpcap",
                            "sys_admin",
                            "sys_ptrace",
                        }
                    )
                )
            )
        )
    ):
        category = "codex_direct_runtime_and_bwrap"
    elif (
        profile == "managed-codex-runtime"
        and operation == "capable"
        and not requested_mask
        and not denied_mask
        and (
            (comm == "MemoryInfra" and capname == "sys_ptrace")
            or (
                comm == "vivaldi-bin"
                and capname in {"sys_admin", "sys_chroot", "sys_ptrace"}
            )
        )
    ):
        category = "codex_chromium_runtime_capabilities"
    elif (
        profile == "managed-codex-runtime"
        and operation == "userns_create"
        and comm == "vivaldi-bin"
        and not requested_mask
        and not denied_mask
    ):
        category = "codex_chromium_user_namespace"
    elif (
        profile == "managed-codex-runtime"
        and fsuid
        and fsuid == ouid
        and requested_mask == denied_mask
        and (
            (
                operation == "open"
                and comm == "MemoryInfra"
                and requested_mask == "w"
                and re.fullmatch(r"/proc/[0-9]+/clear_refs", name)
            )
            or (
                comm in {"ThreadPoolSingl", "vivaldi-bin"}
                and re.fullmatch(r"/proc/[0-9]+/oom_score_adj", name)
                and (
                    (operation == "open" and requested_mask == "wc")
                    or (operation == "truncate" and requested_mask == "w")
                )
            )
            or (
                operation == "open"
                and comm == "vivaldi-bin"
                and requested_mask == "w"
                and re.fullmatch(
                    r"/proc/[0-9]+/(?:gid_map|setgroups|uid_map)",
                    name,
                )
            )
            or (
                operation == "mknod"
                and comm == "vivaldi-stable"
                and requested_mask == "c"
                and bool(pid)
                and re.fullmatch(
                    rf"/proc/{re.escape(pid)}/fd/[0-9]+",
                    name,
                )
            )
        )
    ):
        category = "codex_chromium_process_control"
    elif (
        profile == "managed-codex-runtime"
        and comm in codex_vivaldi_codec_processes
        and fsuid
        and ouid
        and fsuid != ouid
        and re.fullmatch(
            r"/var/opt/vivaldi/media-codecs-[^/]+/libffmpeg[.]so",
            name,
        )
        and (
            (
                operation == "open"
                and requested_mask == denied_mask == "r"
            )
            or (
                operation == "file_mmap"
                and requested_mask == denied_mask == "rm"
            )
        )
    ):
        category = "codex_vivaldi_media_codec"
    elif (
        profile == "managed-codex-runtime"
        and operation == "open"
        and comm == "Gamepad polling"
        and requested_mask == denied_mask == "r"
        and fsuid
        and ouid
        and fsuid != ouid
        and re.fullmatch(r"/run/udev/data/c13:[0-9]+", name)
    ):
        category = "codex_vivaldi_gamepad_metadata"
    elif (
        profile == "managed-codex-runtime"
        and requested_mask == denied_mask
        and (
            (
                operation == "chmod"
                and comm == "vivaldi-bin"
                and name == "/var/cache/fontconfig/"
                and requested_mask == "w"
                and fsuid
                and ouid
                and fsuid != ouid
            )
            or (
                operation == "mkdir"
                and comm == "vivaldi-bin"
                and name == "/etc/opt/chrome/"
                and requested_mask == "c"
                and fsuid
                and fsuid == ouid
            )
            or (
                operation == "mkdir"
                and comm == "ThreadPoolForeg"
                and name == "/opt/vivaldi/extensions/"
                and requested_mask == "c"
                and fsuid
                and fsuid == ouid
            )
        )
    ):
        category = "codex_vivaldi_quiet_denies"
    elif (
        profile == "managed-codex-wrapper"
        and operation == "open"
        and name == "/dev/tty"
        and comm == "codex"
        and requested_mask == "wr"
        and denied_mask == "wr"
    ):
        category = "codex_wrapper_tty"
    elif (
        profile == "managed-codex-wrapper"
        and operation == "open"
        and name == "/dev/"
        and comm == "codex"
        and requested_mask == denied_mask == "r"
    ):
        category = "codex_wrapper_dev_inventory"
    elif (
        profile == "managed-telbot"
        and comm == "telbot"
        and family == "netlink"
        and sock_type == "raw"
        and protocol == "0"
        and info == "failed af match"
        and operation in telbot_netlink_masks
        and requested_mask
        == denied_mask
        == telbot_netlink_masks[operation]
    ):
        category = "telbot_netlink_raw"
    elif (
        profile == "managed-codex-wrapper//codex-bwrap"
        and operation == "open"
        and name == "/"
        and comm == "bwrap"
        and requested_mask == "r"
        and denied_mask == "r"
    ):
        category = "codex_bwrap_root"
    elif (
        profile == "managed-codex-wrapper//codex-bwrap"
        and operation == "open"
        and name in codex_instruction_processes
        and comm == codex_instruction_processes[name]
        and requested_mask == "r"
        and denied_mask == "r"
    ):
        category = "codex_bwrap_instructions"
    elif (
        profile == "managed-codex-wrapper//codex-bwrap"
        and operation == "open"
        and requested_mask == denied_mask == "r"
        and (
            (
                comm == codex_package_metadata_processes.get(name)
            )
            or (
                comm in codex_debconf_metadata_processes.get(name, set())
            )
            or (
                comm == "find"
                and (
                    name in codex_runtime_inventory_directories
                    or (
                        fsuid
                        and fsuid == ouid
                        and name == "/data/codex/usr/.git/"
                    )
                    or (
                        fsuid
                        and fsuid == ouid
                        and name.startswith("/data/codex/usr/.git/")
                        and name.endswith("/")
                    )
                )
            )
        )
    ):
        category = "codex_bwrap_read_only_inventory"
    elif (
        profile
        == "managed-labwc-managed-wayland-compat-app"
        "//managed-wayland-compat-app-bwrap"
        and comm == "bwrap"
        and operation == "capable"
        and capname == "dac_read_search"
    ):
        category = "wayland_compat_bwrap_constructor"
    elif (
        profile == "managed-whisper-cli-default-model"
        and operation == "open"
        and name == "/data/whisper/bin/"
        and comm == "whisper-cli"
        and requested_mask == "r"
        and denied_mask == "r"
    ):
        category = "whisper_cli_binary_directory"
    elif (
        profile == "slirp4netns"
        and operation == "capable"
        and comm == "slirp4netns"
        and capname == "sys_admin"
    ):
        category = "codex_slirp_sys_admin"
    elif (
        profile == "slirp4netns"
        and operation == "capable"
        and comm == "slirp4netns"
        and capname == "net_admin"
    ):
        category = "codex_slirp_net_admin"
    elif (
        profile == "slirp4netns"
        and operation == "create"
        and comm == "slirp4netns"
        and family == "inet"
        and sock_type == "dgram"
        and protocol == "0"
        and requested_mask == "create"
        and denied_mask == "create"
        and info == "failed af match"
    ):
        category = "codex_slirp_inet_dgram"
    elif (
        profile == "slirp4netns"
        and operation == "file_inherit"
        and comm == "slirp4netns"
        and name == "/dev/null"
        and requested_mask == "r"
        and denied_mask == "r"
    ):
        category = "codex_slirp_dev_null_inherit"
    elif (
        profile == "slirp4netns"
        and operation == "file_inherit"
        and comm == "slirp4netns"
        and re.fullmatch(
            r"/data/codex/runtime/[.]control/launch[.][A-Za-z0-9]+/"
            r"(?:slirp[.]stdout|slirp[.]stderr)",
            name,
        )
        and requested_mask == "w"
        and denied_mask == "w"
        and fsuid
        and fsuid == ouid
    ):
        category = "codex_slirp_control_logs_inherit"
    elif (
        profile == "slirp4netns"
        and operation == "file_inherit"
        and comm == "slirp4netns"
        and re.fullmatch(
            r"/data/codex/runtime/[.]control/launch[.][A-Za-z0-9]+/"
            r"(?:bwrap-info[.]fifo|bwrap-block[.]fifo|slirp-ready[.]fifo)",
            name,
        )
        and requested_mask == "wr"
        and denied_mask == "wr"
        and fsuid
        and fsuid == ouid
    ):
        category = "codex_slirp_control_fifos_inherit"
    elif (
        profile == "slirp4netns"
        and operation == "file_mmap"
        and comm == "slirp4netns"
        and name == "/usr/bin/slirp4netns"
        and requested_mask == "r"
        and denied_mask == "r"
    ):
        category = "codex_slirp_binary_mmap"
    elif (
        profile == "slirp4netns"
        and operation == "file_mmap"
        and comm == "slirp4netns"
        and name == "/usr/lib/x86_64-linux-gnu/ld-linux-x86-64.so.2"
        and requested_mask == "r"
        and denied_mask == "r"
    ):
        category = "codex_slirp_loader_mmap"
    elif (
        profile == "slirp4netns"
        and operation == "open"
        and comm == "slirp4netns"
        and name == "/"
        and requested_mask == "r"
        and denied_mask == "r"
    ):
        category = "codex_slirp_root"
    elif (
        profile == "slirp4netns"
        and operation == "open"
        and comm == "slirp4netns"
        and name == "/dev/net/tun"
        and requested_mask == "wr"
        and denied_mask == "wr"
    ):
        category = "codex_slirp_tun"
    elif (
        profile == "slirp4netns"
        and operation == "open"
        and comm == "slirp4netns"
        and name == "/dev/urandom"
        and requested_mask == "r"
        and denied_mask == "r"
    ):
        category = "codex_slirp_urandom"
    elif (
        profile == "slirp4netns"
        and operation == "signal"
        and comm == "codex"
        and signal_name == "exists"
        and peer == "managed-codex-wrapper"
        and requested_mask == "receive"
        and denied_mask == "receive"
    ):
        category = "codex_slirp_signal_exists"
    elif (
        profile == "slirp4netns"
        and operation == "signal"
        and comm == "codex"
        and signal_name == "term"
        and peer == "managed-codex-wrapper"
        and requested_mask == "receive"
        and denied_mask == "receive"
    ):
        category = "codex_slirp_signal_term"
    elif base_profile == "managed-update-initramfs":
        category = "update_initramfs_permissive_runtime"
    elif profile == "managed-apt-refresh-lists":
        category = "apt_refresh_permissive_runtime"
    elif profile == "managed-zram-writeback":
        category = "zram_writeback_permissive_runtime"
    elif (
        profile == "managed-tailscale-managed-up"
        and operation == "open"
        and name == "/"
    ):
        category = "tailscale_root_inventory"
    elif (
        profile == "managed-secondboot-cleanup"
        and comm
        in {
            "all_generic_ide",
            "blacklist",
            "btrfs",
            "cat",
            "chmod",
            "cp",
            "cpio",
            "depmod",
            "dmsetup",
            "dpkg",
            "dracut-install",
            "egrep",
            "env",
            "find",
            "fsck",
            "fstype",
            "fuse",
            "grep",
            "intel_microcode",
            "ischroot",
            "iucode_tool",
            "keymap",
            "klibc-utils",
            "kmod",
            "ld-linux-x86-64",
            "ldconfig",
            "ldd",
            "linux-version",
            "ln",
            "mkdir",
            "mkinitramfs",
            "mktemp",
            "resume",
            "rm",
            "sh",
            "simple-framebuf",
            "sort",
            "systemctl",
            "thermal",
            "touch",
            "update-initramf",
            "udev",
            "xargs",
            "xfs",
            "zz-busybox",
        }
    ):
        category = "legacy_secondboot_inherited_tools"
    elif (
        profile == "managed-apt-refresh-lists"
        and comm
        in {
            "apt-get",
            "copy",
            "dpkg",
            "file",
            "https",
            "sh",
            "sqv",
            "store",
        }
    ):
        category = "apt_refresh_runtime"
    elif (
        profile == "managed-tailscale-managed-up"
        and operation == "exec"
        and re.fullmatch(r"/usr/bin/python3[.][0-9]+", name)
    ):
        category = "tailscale_versioned_python"
    elif (
        re.fullmatch(
            r"managed-tailscale-managed-up//null-/usr/bin/python3[.][0-9]+",
            profile,
        )
        and comm == "python3"
    ):
        category = "legacy_tailscale_python_null_child"
    elif (
        profile == "managed-crowdsec-firstboot"
        and operation == "open"
        and name == "/etc/machine-id"
        and requested_mask == denied_mask == "r"
    ):
        category = "crowdsec_machine_identity"
    elif (
        profile == "managed-crowdsec-firstboot"
        and operation == "open"
        and (
            re.fullmatch(r"/proc/[0-9]+/mountinfo", name)
            or name == "/sys/kernel/mm/hugepages/"
        )
    ):
        category = "crowdsec_runtime_inventory"
    elif (
        profile == "managed-managed-syncthing-configure"
        and operation == "open"
        and name == "/"
    ):
        category = "syncthing_root_inventory"
    elif (
        profile == "managed-swap-fallback-setup"
        and operation == "open"
        and (
            name == "/etc/modprobe.d/"
            or name.startswith("/etc/modprobe.d/")
            or name == "/proc/cmdline"
            or re.fullmatch(r"/proc/[0-9]+/mounts", name)
            or re.fullmatch(r"/dev/dm-[0-9]+", name)
        )
    ):
        category = "swap_runtime_inventory"
    elif (
        profile == "managed-zram-device-setup"
        and (
            (
                operation == "open"
                and (
                    name == "/etc/modprobe.d/"
                    or name.startswith("/etc/modprobe.d/")
                    or name == "/proc/cmdline"
                    or re.fullmatch(r"/proc/[0-9]+/mounts", name)
                    or re.fullmatch(
                        r"/sys/module/(?:dm_mod|dm_crypt)/initstate",
                        name,
                    )
                    or re.fullmatch(r"/dev/dm-[0-9]+", name)
                    or name.startswith("/run/blkid/")
                )
            )
            or (
                operation
                in {
                    "chmod",
                    "link",
                    "mknod",
                    "rename_dest",
                    "rename_src",
                }
                and name.startswith("/run/blkid/")
            )
        )
    ):
        category = "zram_runtime_inventory"
    elif (
        profile == "usr.bin.tailscale"
        and operation == "file_inherit"
        and name == "/usr/local/lib/tailscale/bootstrap.log"
    ):
        category = "tailscale_bootstrap_log_inherit"
    elif (
        profile
        in {
            "managed-labwc-fuzzel",
            "managed-labwc-adb-menu",
            "managed-labwc-computer-management",
        }
        and operation == "exec"
        and name == "/usr/local/bin/labwc-fuzzel-log"
    ):
        category = "fuzzel_logger_transition"
    elif (
        re.fullmatch(
            r"managed-labwc-(?:fuzzel|adb-menu|computer-management)"
            r"//null-/usr/local/bin/labwc-fuzzel-log",
            profile,
        )
    ):
        category = "legacy_fuzzel_logger_null_child"
    elif (
        profile == "managed-labwc-security-action-root"
        and operation == "exec"
        and name == "/usr/sbin/aa-status"
    ):
        category = "aa_status_transition"
    elif (
        profile == "aa-status-reader"
        and operation == "capable"
        and fields.get("capname") == "sys_ptrace"
    ):
        category = "aa_status_process_metadata_capability"
    elif (
        profile
        == "managed-labwc-security-action-root//null-/usr/sbin/aa-status"
    ):
        category = "legacy_aa_status_null_child"
    elif (
        profile == "sqlitebrowser"
        and operation == "open"
        and fields.get("requested_mask") == "r"
        and re.fullmatch(r"/home/[^/]+/Templates/", name)
    ):
        category = "sqlitebrowser_templates"
    elif (
        profile == "managed-android-platform-tools"
        and comm == "adb"
        and operation == "open"
        and fields.get("requested_mask") == "r"
        and fields.get("denied_mask") == "r"
        and (
            name == "/proc/"
            or re.fullmatch(r"/proc/[0-9]+/fd/", name)
            or name
            in {
                f"/proc/{fields.get('pid', '')}/net/{protocol}"
                for protocol in ("tcp", "tcp6", "udp", "udp6")
            }
        )
    ):
        category = "android_adb_proc_runtime"
    elif (
        profile == "usr.sbin.tailscaled"
        and comm == "tailscaled"
        and fields.get("class") == "net"
        and fields.get("family") == "inet"
        and fields.get("sock_type") == "raw"
        and fields.get("protocol") == "1"
        and operation in tailscaled_ipv4_icmp_masks
        and fields.get("requested_mask")
        == tailscaled_ipv4_icmp_masks[operation]
        and fields.get("denied_mask")
        == tailscaled_ipv4_icmp_masks[operation]
    ):
        category = "tailscaled_ipv4_icmp"
    elif (
        profile == "usr.sbin.tailscaled"
        and operation == "capable"
        and fields.get("capname") == "dac_override"
    ):
        category = "tailscaled_tpm_dac_override"
    elif (
        profile == "usr.sbin.tailscaled"
        and operation == "capable"
        and fields.get("capname") == "sys_ptrace"
    ):
        category = "tailscaled_process_metadata_capability"
    elif (
        profile == "usr.sbin.tailscaled"
        and operation == "exec"
        and requested_mask == denied_mask == "x"
        and (
            (
                comm == "tailscaled"
                and name == "/usr/sbin/resolvconf"
            )
            or (
                comm == "resolvconf"
                and name
                in {
                    "/bin/flock",
                    "/bin/sed",
                    "/usr/bin/flock",
                    "/usr/bin/sed",
                }
            )
        )
    ):
        category = "tailscaled_resolvconf_exec"
    elif (
        profile == "usr.sbin.tailscaled"
        and operation == "open"
        and requested_mask == denied_mask == "r"
        and (
            (
                comm == "resolvconf"
                and name == "/usr/sbin/resolvconf"
            )
            or (
                comm == "sed"
                and name == "/usr/share/doc/resolvconf/copyright"
            )
        )
    ):
        category = "tailscaled_resolvconf_runtime"
    elif (
        profile == "usr.sbin.tailscaled"
        and name == "/run/resolvconf/run-lock"
        and requested_mask == denied_mask
        and (operation, requested_mask)
        in {
            ("file_lock", "wk"),
            ("open", "wc"),
            ("truncate", "w"),
        }
    ):
        category = "tailscaled_resolvconf_lock"
    elif (
        profile == "usr.sbin.tailscaled"
        and comm == "tailscaled"
        and requested_mask == denied_mask
        and (
            (
                name == "/etc/resolvconf/update-libc.d/"
                and (operation, requested_mask) == ("mkdir", "c")
            )
            or (
                re.fullmatch(
                    r"/etc/resolvconf/update-libc[.]d/"
                    r"tailscale[.]tmp[0-9]+",
                    name,
                )
                is not None
                and (operation, requested_mask)
                in {
                    ("chmod", "w"),
                    ("mknod", "c"),
                    ("open", "wrc"),
                    ("rename_src", "wrd"),
                }
            )
            or (
                name == "/etc/resolvconf/update-libc.d/tailscale"
                and (operation, requested_mask)
                in {
                    ("rename_dest", "wc"),
                    ("unlink", "d"),
                }
            )
        )
    ):
        category = "tailscaled_resolvconf_hook"
    elif (
        profile == "usr.sbin.tailscaled"
        and operation == "open"
        and name.startswith("/etc/")
        and name.endswith("/")
    ):
        category = "tailscaled_etc_directory_inventory"
    elif (
        profile == "usr.sbin.tailscaled"
        and operation == "open"
        and name == "/etc/debian_version"
    ):
        category = "tailscaled_debian_version"
    elif (
        profile == "usr.sbin.tailscaled"
        and operation == "open"
        and name == "/dev/tpmrm0"
        and fields.get("requested_mask") in {"rw", "wr"}
    ):
        category = "tailscaled_tpm"
    elif (
        profile == "usr.sbin.tailscaled"
        and operation == "exec"
        and name in {
            "/usr/sbin/ip6tables",
            "/usr/sbin/iptables",
            "/usr/sbin/xtables-nft-multi",
        }
    ):
        category = "tailscaled_xtables_exec"
    elif (
        profile == "usr.sbin.tailscaled"
        and operation == "ptrace"
        and fields.get("requested_mask") == "read"
        and peer == "unconfined"
    ):
        category = "tailscaled_process_metadata"
    elif (
        profile == "usr.sbin.tailscaled"
        and fields.get("comm") == "tailscale"
        and operation == "open"
        and re.fullmatch(r"/proc/[0-9]+/(?:cgroup|mountinfo)", name)
    ):
        category = "tailscale_cli_proc"
    elif (
        profile == "usr.sbin.tailscaled"
        and fields.get("comm") == "tailscale"
        and operation == "open"
        and name
        == "/sys/fs/cgroup/system.slice/"
        "tailscale-managed-bootstrap.service/cpu.max"
    ):
        category = "tailscale_cli_cgroup"
    elif (
        profile == "usr.sbin.tailscaled"
        and fields.get("comm") == "tailscale"
        and operation == "open"
        and name == "/usr/local/lib/tailscale/auth.key"
    ):
        category = "tailscale_cli_auth_key"
    elif (
        profile == "usr.sbin.tailscaled"
        and fields.get("comm") == "tailscaled"
        and operation == "open"
        and name.startswith("/proc/sys/net/ipv6/conf/")
        and name.endswith("/")
    ):
        category = "tailscaled_ipv6_directory"
    elif (
        profile == "usr.sbin.tailscaled"
        and fields.get("comm") == "tailscaled"
        and operation == "open"
        and (
            re.fullmatch(
                r"/proc/(?:1|[0-9]+)/"
                r"(?:cgroup|mountinfo|mounts|net/unix|stat)",
                name,
            )
            or name == "/proc/sys/net/core/somaxconn"
            or re.fullmatch(
                r"/proc/sys/net/ipv6/conf/[^/]+/"
                r"(?:disable_ipv6|disable_policy)",
                name,
            )
        )
    ):
        category = "tailscaled_proc_runtime"
    elif (
        profile == "usr.sbin.tailscaled"
        and fields.get("comm") == "tailscaled"
        and operation == "open"
        and re.fullmatch(
            r"/sys/devices/virtual/dmi/id/"
            r"(?:bios_vendor|product_name|sys_vendor)",
            name,
        )
    ):
        category = "tailscaled_dmi"
    elif (
        profile == "usr.sbin.tailscaled"
        and fields.get("comm") == "tailscaled"
        and operation == "open"
        and name
        == "/sys/fs/cgroup/system.slice/tailscaled.service/cpu.max"
    ):
        category = "tailscaled_cgroup"
    elif (
        profile == "managed-whisper-record-toggle"
        and operation == "chmod"
        and re.fullmatch(r"/home/[^/]+/Music/Whisper/", name)
    ):
        category = "whisper_root_directory_chmod"
    elif (
        profile == "managed-whisper-record-toggle"
        and operation == "exec"
        and name == "/usr/bin/systemctl"
    ):
        category = "whisper_systemctl_exec"
    elif (
        profile == "managed-whisper-record-toggle"
        and operation == "exec"
        and name == "/usr/bin/wpctl"
    ):
        category = "whisper_wpctl_exec"
    elif (
        profile == "managed-whisper-record-toggle"
        and operation == "open"
        and name in {
            "/usr/share/pipewire/client.conf",
            "/etc/pipewire/client.conf.d/",
            "/etc/pipewire/client.conf.d/20-managed-volume-ceiling.conf",
        }
    ):
        category = "whisper_pipewire_client_config"
    elif (
        profile == "managed-whisper-record-toggle"
        and operation == "open"
        and name in {
            "/sys/devices/virtual/dmi/id/bios_vendor",
            "/sys/devices/virtual/dmi/id/board_vendor",
        }
    ):
        category = "whisper_dmi"
    elif (
        profile == "managed-whisper-record-toggle"
        and operation == "open"
        and re.fullmatch(r"/proc/[0-9]+/task/[0-9]+/comm", name)
    ):
        category = "whisper_thread_comm"
    elif (
        profile == "managed-labwc-managed-app"
        and operation == "open"
        and name == "/usr/local/lib/python3.14/dist-packages/"
    ):
        category = "managed_app_python_parent"
    elif (
        profile in {
            "managed-labwc-wallpaper-save",
            "managed-labwc-output-refresh",
        }
        and operation == "file_inherit"
        and re.fullmatch(r"/run/user/[0-9]+/labwc-autostart[.]lock", name)
    ):
        category = "desktop_autostart_lock_inherit"
    elif (
        profile == "managed-labwc-dock"
        and operation == "file_perm"
        and re.fullmatch(
            r"/home/[^/]+/[.]local/state/labwc/crystal-dock[.]log",
            name,
        )
    ):
        category = "desktop_dock_log_descriptor"
    elif (
        profile == "tuta-mail"
        and operation == "open"
        and re.fullmatch(
            r"/sys/devices/.*/iio:device[0-9]+/"
            r"in_accel_(?:offset|sampling_frequency|scale|[xyz]_raw)",
            name,
        )
    ):
        category = "tuta_accelerometer_probe"
    elif (
        profile == "chromium"
        and operation == "mkdir"
        and name == "/usr/lib/chromium/extensions/"
    ):
        category = "chromium_package_extension_probe"
    elif (
        profile == "labwc-chromium-launcher"
        and operation == "open"
        and re.fullmatch(r"/home/[^/]+/", name)
    ):
        category = "chromium_launcher_home"
    elif (
        profile == "managed-labwc-digital-assets"
        and operation == "open"
        and fields.get("requested_mask") == "r"
        and re.fullmatch(r"/home/[^/]+/", name)
    ):
        category = "digital_assets_home"
    elif (
        profile == "managed-labwc-digital-assets-action"
        and operation == "file_inherit"
        and re.fullmatch(
            r"/run/user/[0-9]+/labwc-digital-assets-catalog[.][A-Za-z0-9]+",
            name,
        )
    ):
        category = "digital_assets_catalog_descriptor"
    elif (
        profile == "managed-labwc-sync-application-launchers"
        and operation == "open"
        and re.fullmatch(r"/usr/share/[^/]+/[^/]+[.]desktop", name)
    ):
        category = "desktop_package_launcher"
    elif (
        profile == "labwc-mullvad-browser-launcher"
        and operation == "open"
        and name == "/dev/tty"
    ):
        category = "mullvad_launcher_tty"
    elif (
        profile == "postman"
        and operation == "open"
        and fields.get("requested_mask") in {"rw", "wr"}
        and re.fullmatch(r"/dev/dri/card[0-9]+", name)
    ):
        category = "postman_drm_card"
    elif (
        profile == "postman"
        and operation == "open"
        and fields.get("requested_mask") == "r"
        and re.fullmatch(r"/proc/[0-9]+/loginuid", name)
    ):
        category = "postman_loginuid"
    elif (
        profile == "postman"
        and operation == "open"
        and fields.get("requested_mask") == "r"
        and name in {
            "/usr/bin/",
            "/usr/sbin/",
            "/usr/local/bin/",
            "/usr/local/sbin/",
        }
    ):
        category = "postman_executable_directory"
    elif (
        profile == "Discord"
        and operation == "exec"
        and re.fullmatch(
            r"/home/[^/]+/[.]config/discord/app-[^/]+/modules/"
            r"discord_voice-[^/]+/discord_voice/gpu_encoder_helper",
            name,
        )
    ):
        category = "discord_gpu_helper_exec"
    elif (
        profile.startswith("Discord//null-/")
        and profile.endswith(
            "/modules/discord_voice-1/discord_voice/gpu_encoder_helper"
        )
    ):
        category = "discord_gpu_helper_null_child"
    elif (
        profile == "Discord"
        and operation == "open"
        and re.fullmatch(r"/proc/[0-9]+/mem", name)
    ):
        category = "discord_crashpad_memory"
    elif (
        profile == "Discord"
        and operation == "open"
        and re.fullmatch(
            r"/sys/devices/system/cpu/cpufreq/policy[0-9]+/"
            r"scaling_max_freq",
            name,
        )
    ):
        category = "discord_cpu_scaling_max"
    elif (
        profile in {"Discord", "ledger-live"}
        and operation == "open"
        and name == "/etc/"
    ):
        category = "desktop_etc_directory"
    elif (
        profile in {"Discord", "ledger-live"}
        and operation == "open"
        and name == "/proc/uptime"
    ):
        category = "electron_uptime"
    elif (
        profile == "mullvad-browser"
        and operation == "mkdir"
        and re.fullmatch(r"/home/[^/]+/[.]cache/mullvad/", name)
    ):
        category = "mullvad_cache_parent"
    elif (
        profile == "mullvad-browser"
        and operation == "open"
        and name == "/dev/"
    ):
        category = "mullvad_device_directory"
    elif (
        profile == "mullvad-browser"
        and operation == "open"
        and name == "/etc/mime.types"
    ):
        category = "mullvad_mime_types"
    elif (
        profile == "mullvad-browser"
        and operation == "open"
        and re.fullmatch(r"/sys/fs/cgroup/.*/cpu[.]max", name)
    ):
        category = "mullvad_cgroup_cpu_max"
    elif (
        profile == "mullvad-browser//mullvad-bwrap"
        and operation == "exec"
        and name == "/usr/bin/true"
    ):
        category = "mullvad_bwrap_true_exec"
    elif (
        (
            profile == "mullvad-browser"
            and fields.get("requested_mask") == "send"
            and peer == "mullvad-browser//mullvad-bwrap"
        )
        or (
            profile == "mullvad-browser//mullvad-bwrap"
            and fields.get("requested_mask") == "receive"
            and peer == "mullvad-browser"
        )
    ) and operation == "signal" and signal_name == "kill":
        category = "mullvad_bwrap_signal"
    elif (
        profile == "ledger-live"
        and re.fullmatch(
            r"/home/[^/]+/[.]config/Ledger Wallet(?:/.*)?",
            name,
        )
    ):
        category = "ledger_legacy_state"
    elif (
        profile == "ledger-live"
        and operation == "open"
        and name == "/dev/tty"
    ):
        category = "ledger_tty"
    elif (
        profile == "ledger-live"
        and (
            name in {
                "/etc/pulse/client.conf",
                "/etc/pulse/client.conf.d/",
            }
            or re.fullmatch(r"/run/user/[0-9]+/pulse/", name)
            or re.fullmatch(
                r"/home/[^/]+/[.]config/pulse/cookie",
                name,
            )
        )
    ):
        category = "ledger_pipewire_audio"
    elif (
        profile == "ledger-live"
        and operation == "open"
        and name.startswith("/sys/devices/")
        and name.endswith("/report_descriptor")
    ):
        category = "ledger_hid_report_descriptor"
    elif (
        profile == "managed-labwc-managed-app//managed-app-bwrap"
        and fields.get("family") in {"inet", "inet6"}
        and fields.get("sock_type") in {"stream", "dgram"}
    ):
        category = "managed_bwrap_network"
    elif (
        profile == "managed-labwc-managed-app//managed-app-bwrap"
        and operation == "open"
        and (
            name == "/usr/share/glycin-loaders/2+/conf.d/"
            or re.fullmatch(
                r"/usr/share/glycin-loaders/2\+/conf[.]d/[^/]+[.]conf",
                name,
            )
        )
    ):
        category = "managed_bwrap_glycin_config"
    elif (
        profile == "managed-labwc-managed-app//managed-app-bwrap"
        and operation == "exec"
        and (
            name in {"/usr/bin/bwrap", "/usr/bin/true"}
            or re.fullmatch(
                r"/usr/libexec/glycin-loaders/2\+/"
                r"(?:glycin-image-rs|glycin-svg)",
                name,
            )
        )
    ):
        category = "managed_bwrap_glycin_exec"
    elif (
        profile == "managed-labwc-managed-app//managed-app-bwrap"
        and operation == "open"
        and re.fullmatch(
            r"/sys/devices/.*/iio:device[0-9]+/"
            r"in_accel_(?:offset|sampling_frequency|scale|[xyz]_raw)",
            name,
        )
    ):
        category = "managed_bwrap_accelerometer_probe"
    elif (
        profile == "managed-labwc-managed-app//managed-app-bwrap"
        and (
            name == "/proc/sys/fs/inotify/max_user_watches"
            or name == "/proc/self/exe"
            or re.fullmatch(
                r"/proc/[0-9]+/"
                r"(?:"
                r"|comm|cgroup|cmdline|environ|maps|stat|statm|status|"
                r"mountinfo|oom_score_adj|fd/|smaps_rollup|"
                r"task/(?:|[0-9]+/(?:|comm|stat|status))"
                r")",
                name,
            )
        )
    ):
        category = "managed_bwrap_proc_runtime"
    elif (
        profile == "managed-labwc-managed-app//managed-app-bwrap"
        and name.startswith("/dev/shm/")
    ):
        category = "managed_bwrap_shared_memory"
    elif (
        profile == "managed-labwc-managed-app//managed-app-bwrap"
        and (
            name == "/usr/bin/ldd"
            or name.startswith(
                (
                    "/opt/Bitwarden/",
                    "/opt/Filen/",
                    "/opt/Obsidian/",
                    "/opt/ledger-live/",
                    "/opt/postman/",
                    "/opt/sleek/",
                    "/opt/tuta-mail/",
                    "/opt/vivaldi/",
                    "/opt/microsoft/msedge/",
                    "/usr/lib/mullvad-browser/",
                    "/usr/share/code/",
                    "/opt/discord/",
                )
            )
        )
    ):
        category = "managed_bwrap_payload"
    elif (
        profile == "filen"
        and operation == "open"
        and re.fullmatch(r"/proc/[0-9]+/comm", name)
    ):
        category = "filen_process_comm"
    elif (
        profile == "managed-labwc-mute-default-microphone"
        and operation == "open"
        and name
        in {
            "/sys/devices/virtual/dmi/id/bios_vendor",
            "/sys/devices/virtual/dmi/id/board_vendor",
            "/sys/devices/virtual/dmi/id/product_name",
            "/sys/devices/virtual/dmi/id/sys_vendor",
        }
    ):
        category = "labwc_mute_default_microphone_dmi"
    elif (
        profile == "managed-labwc-mute-default-microphone"
        and operation == "open"
        and re.fullmatch(r"/proc/[0-9]+/task/[0-9]+/comm", name)
    ):
        category = "labwc_mute_default_microphone_process_metadata"
    elif (
        profile == "sqlitebrowser"
        and operation == "open"
        and re.fullmatch(
            r"/home/[^/]+/[.]"
            r"(?:bash_aliases|bash_profile|bashrc|dircolors|profile|"
            r"sudo_as_admin_successful|vimrc|zlogout|zprofile|"
            r"zsh_aliases|zshenv|zshrc)",
            name,
        )
    ):
        category = "sqlitebrowser_shell_preferences"
    elif (
        profile == "sqlitebrowser"
        and operation == "link"
        and re.fullmatch(
            r"/home/[^/]+/[.]config/"
            r"(?:sqlitebrowser/(?:#[0-9]+|sqlitebrowser[.]conf)|"
            r"#[0-9]+|QtProject[.]conf)",
            name,
        )
    ):
        category = "sqlitebrowser_atomic_link"
    elif (
        profile == "slirp4netns"
        and operation == "create"
        and family == "unix"
        and sock_type == "stream"
        and protocol == "0"
        and requested_mask == "create"
        and denied_mask == "create"
        and addr == "none"
    ):
        category = "slirp4netns_unix_socketpair"
    elif (
        profile == "slirp4netns"
        and operation == "capable"
        and capname == "sys_ptrace"
    ):
        category = "slirp4netns_process_capability"
    elif (
        profile == "slirp4netns"
        and operation == "ptrace"
        and requested_mask == "read"
        and denied_mask == "read"
        and peer == "unconfined"
    ):
        category = "slirp4netns_process_inspection"
    elif (
        profile == "slirp4netns"
        and operation == "open"
        and name == ""
        and requested_mask == "r"
        and denied_mask == "r"
        and info == "Failed name lookup - disconnected path"
    ):
        category = "slirp4netns_disconnected_namespace"
    else:
        unclassified.append(
            f"{log_path}:{line_number}: "
            f"profile={profile!r} operation={operation!r} "
            f"name={name!r} peer={peer!r}"
        )
        continue
    counts[category] += 1

if unclassified:
    print("unclassified complain-mode access records:", file=sys.stderr)
    print("\n".join(unclassified), file=sys.stderr)
    raise SystemExit(1)

expected_counts = Counter(
    {
        "bwrap_constructor_bindfiles": 12,
        "chatgpt_legacy_vendor_profiles_source_eliminated": 2708,
        "codex_installation_id_descriptor_source_eliminated": 1,
        "devops_root_inventory": 1,
        "virt_host_bounded_runtime": 7,
        "virt_session_storage_runtime": 4,
    }
)
if (
    not os.environ.get("APPARMOR_DENIED_MASK_LOG")
    and (counts != expected_counts or ignored_root_zoom != 0)
):
    print("unexpected complain-mode access classification counts:", file=sys.stderr)
    print(
        "ignored_root_zoom: "
        f"actual={ignored_root_zoom} expected=0",
        file=sys.stderr,
    )
    for category in sorted(set(counts) | set(expected_counts)):
        print(
            f"{category}: actual={counts[category]} "
            f"expected={expected_counts[category]}",
            file=sys.stderr,
        )
    raise SystemExit(1)

print(f"# reviewed complain-mode access records: {sum(counts.values())}")
print(f"# ignored root Zoom access records: {ignored_root_zoom}")
for category in sorted(counts):
    print(f"# {category}: {counts[category]}")
PY
then
  pass "every complain-mode access record is covered by bounded policy or source-level elimination"
else
  fail "every complain-mode access record is covered by bounded policy or source-level elimination"
fi

if python3 - "$LOG" <<'PY'
from collections import Counter
import os
from pathlib import Path
import re
import sys

log_path = Path(sys.argv[1])
field_pattern = re.compile(
    r'(?P<key>[A-Za-z_][A-Za-z0-9_]*)='
    r'(?:"(?P<quoted>[^"]*)"|(?P<bare>[^\s\x1d]+))'
)
counts = Counter()
signatures = set()
unclassified = []
records = 0

for line_number, line in enumerate(
    log_path.open(encoding="utf-8", errors="replace"),
    1,
):
    if 'apparmor="DENIED"' not in line:
        continue
    fields = {
        match.group("key"): (
            match.group("quoted")
            if match.group("quoted") is not None
            else match.group("bare")
        )
        for match in field_pattern.finditer(line)
    }
    records += 1
    signatures.add(
        tuple(
            fields.get(key, "")
            for key in (
                "profile",
                "operation",
                "name",
                "requested_mask",
                "denied_mask",
                "capname",
                "info",
                "target",
                "comm",
                "peer",
            )
        )
    )
    profile = fields.get("profile", "")
    operation = fields.get("operation", "")
    name = fields.get("name", "")
    capname = fields.get("capname", "")
    comm = fields.get("comm", "")
    peer = fields.get("peer", "")

    if (
        profile == "managed-apt-refresh-lists"
        and operation == "capable"
        and capname == "dac_read_search"
    ):
        category = "apt_dac_read_search"
    elif (
        profile == "managed-apt-refresh-lists"
        and operation == "open"
        and name == "/usr/share/dpkg/cputable"
    ):
        category = "apt_dpkg_runtime"
    elif (
        profile == "managed-crowdsec-firstboot"
        and operation == "exec"
        and name == "/usr/bin/mawk"
    ):
        category = "crowdsec_awk_alternative"
    elif (
        profile == "managed-crowdsec-firstboot"
        and operation == "capable"
        and capname == "net_admin"
    ):
        category = "crowdsec_net_admin"
    elif (
        profile == "managed-crowdsec-firstboot"
        and operation == "ptrace"
        and fields.get("denied_mask") == "read"
        and peer == "unconfined"
    ):
        category = "crowdsec_process_metadata"
    elif (
        profile == "managed-crowdsec-firstboot"
        and operation == "open"
        and re.fullmatch(r"/proc/[0-9]+/stat", name)
    ):
        category = "crowdsec_proc_stat"
    elif (
        profile == "managed-managed-syncthing-configure"
        and operation == "capable"
        and capname == "dac_read_search"
    ):
        category = "syncthing_dac_read_search"
    elif (
        profile == "managed-managed-syncthing-configure"
        and operation == "exec"
        and re.fullmatch(r"/usr/bin/python3[.][0-9]+", name)
    ):
        category = "syncthing_versioned_python"
    elif (
        profile == "managed-swap-fallback-setup"
        and operation == "exec"
        and name == "/usr/bin/kmod"
    ):
        category = "swap_kmod_target"
    elif (
        profile == "managed-swap-fallback-setup"
        and operation == "open"
        and name == "/proc/devices"
    ):
        category = "swap_proc_devices"
    elif (
        profile == "managed-swap-fallback-setup"
        and operation == "open"
        and name.startswith("/sys/devices/")
    ):
        category = "swap_block_sysfs"
    elif (
        profile == "managed-zram-device-setup"
        and operation == "exec"
        and name == "/usr/bin/kmod"
    ):
        category = "zram_kmod_target"
    elif (
        profile == "managed-zram-device-setup"
        and operation == "open"
        and name == "/proc/devices"
    ):
        category = "zram_proc_devices"
    elif (
        profile == "managed-tailscale-managed-up"
        and operation == "exec"
        and name == "/usr/bin/tailscale"
        and fields.get("info") == "no new privs"
        and fields.get("target") == "usr.bin.tailscale"
    ):
        category = "tailscale_named_transition"
    elif (
        profile == "managed-tailscale-managed-up"
        and operation == "capable"
        and capname == "sys_ptrace"
    ):
        category = "tailscale_process_capability"
    elif (
        profile == "managed-tailscale-managed-up"
        and operation == "open"
        and re.fullmatch(r"/proc/[0-9]+/stat", name)
    ):
        category = "tailscale_proc_stat"
    else:
        unclassified.append(
            f"{log_path}:{line_number}: "
            f"profile={profile!r} operation={operation!r} "
            f"name={name!r} capname={capname!r} comm={comm!r}"
        )
        continue
    counts[category] += 1

if unclassified:
    print("unclassified enforced AppArmor denial records:", file=sys.stderr)
    print("\n".join(unclassified), file=sys.stderr)
    raise SystemExit(1)

expected_counts = Counter()
if not os.environ.get("APPARMOR_DENIED_MASK_LOG"):
    if records != 0 or signatures or counts != expected_counts:
        print(
            "unexpected enforced AppArmor denial inventory: "
            f"records={records} unique={len(signatures)}",
            file=sys.stderr,
        )
        for category in sorted(set(counts) | set(expected_counts)):
            print(
                f"{category}: actual={counts[category]} "
                f"expected={expected_counts[category]}",
                file=sys.stderr,
            )
        raise SystemExit(1)

print(
    f"# reviewed enforced denial records: {records}; "
    f"unique signatures: {len(signatures)}"
)
PY
then
  android_platform_profile=$(profile_block managed-android-platform-tools)
  apt_profile=$(profile_block managed-apt-refresh-lists "$SYSTEM_PROFILE")
  crowdsec_profile=$(profile_block managed-crowdsec-firstboot "$SYSTEM_PROFILE")
  secondboot_profile=$(profile_block managed-secondboot-cleanup "$SYSTEM_PROFILE")
  update_initramfs_profile=$(profile_block managed-update-initramfs "$SYSTEM_PROFILE")
  syncthing_profile=$(profile_block managed-managed-syncthing-configure "$SYSTEM_PROFILE")
  swap_profile=$(profile_block managed-swap-fallback-setup "$SYSTEM_PROFILE")
  tailscale_bootstrap_profile=$(profile_block managed-tailscale-managed-up "$SYSTEM_PROFILE")
  zram_profile=$(profile_block managed-zram-device-setup "$SYSTEM_PROFILE")
  zram_writeback_profile=$(profile_block managed-zram-writeback "$SYSTEM_PROFILE")
  if printf '%s\n' "$android_platform_profile" |
       grep -Fqx '  @{PROC}/ r,' &&
     printf '%s\n' "$android_platform_profile" |
       grep -Fqx '  @{PROC}/[0-9]*/fd/ r,' &&
     printf '%s\n' "$android_platform_profile" |
       grep -Fqx '  @{PROC}/@{pid}/net/{tcp,tcp6,udp,udp6} r,' &&
     ! printf '%s\n' "$android_platform_profile" |
       grep -Fq 'owner @{PROC}/@{pid}/net/' &&
     ! printf '%s\n' "$android_platform_profile" |
       grep -Eq '@\{PROC\}/(\[0-9\]\*|\*\*)/net/' &&
     printf '%s\n' "$apt_profile" |
       grep -Fqx '  capability,' &&
     printf '%s\n' "$apt_profile" |
       grep -Fqx '  /{bin,boot,data,dev,etc,home,lib,lib64,media,mnt,opt,pool,proc,root,run,sbin,srv,sys,tmp,usr,var}/** rwklm,' &&
     printf '%s\n' "$apt_profile" |
       grep -Fqx '  /{bin,boot,data,dev,etc,home,lib,lib64,media,mnt,opt,pool,proc,root,run,sbin,srv,sys,tmp,usr,var}/** rix,' &&
     printf '%s\n' "$crowdsec_profile" |
       grep -Fqx '  capability net_admin,' &&
     printf '%s\n' "$crowdsec_profile" |
       grep -Fqx '  capability sys_ptrace,' &&
     printf '%s\n' "$crowdsec_profile" |
       grep -Fqx '  ptrace (read) peer=unconfined,' &&
     printf '%s\n' "$crowdsec_profile" |
       grep -Fqx '  /usr/bin/{awk,chmod,date,dirname,getent,grep,hostname,install,mawk,mkdir,mv,rm,sleep,ss,systemctl} rix,' &&
     printf '%s\n' "$crowdsec_profile" |
       grep -Fqx '  /etc/machine-id r,' &&
     printf '%s\n' "$crowdsec_profile" |
       grep -Fqx '  @{PROC}/[0-9]*/stat r,' &&
     printf '%s\n' "$crowdsec_profile" |
       grep -Fqx '  @{PROC}/[0-9]*/mountinfo r,' &&
     printf '%s\n' "$crowdsec_profile" |
       grep -Fqx '  /sys/kernel/mm/hugepages/ r,' &&
     printf '%s\n' "$secondboot_profile" |
       grep -Fqx '  /usr/sbin/update-initramfs rPx -> managed-update-initramfs,' &&
     printf '%s\n' "$secondboot_profile" |
       grep -Fqx '  /usr/bin/systemctl PUx,' &&
     printf '%s\n' "$update_initramfs_profile" |
       grep -Fqx '  /usr/sbin/update-initramfs rix,' &&
     printf '%s\n' "$update_initramfs_profile" |
       grep -Fqx '  capability,' &&
     printf '%s\n' "$update_initramfs_profile" |
       grep -Fqx '  /{bin,boot,data,dev,etc,home,lib,lib64,media,mnt,opt,pool,proc,root,run,sbin,srv,sys,tmp,usr,var}/** rwklm,' &&
     printf '%s\n' "$update_initramfs_profile" |
       grep -Fqx '  /{bin,boot,data,dev,etc,home,lib,lib64,media,mnt,opt,pool,proc,root,run,sbin,srv,sys,tmp,usr,var}/** rix,' &&
     grep -Fqx 'NoNewPrivileges=false' "$SECONDBOOT_UNIT" &&
     printf '%s\n' "$syncthing_profile" |
       grep -Fqx '  #include <abstractions/managed-wrapper-python>' &&
     printf '%s\n' "$syncthing_profile" |
       grep -Fqx '  capability dac_read_search,' &&
     printf '%s\n' "$syncthing_profile" |
       grep -Fqx '  / r,' &&
     printf '%s\n' "$swap_profile" |
       grep -Fqx '  /usr/bin/kmod rix,' &&
     printf '%s\n' "$swap_profile" |
       grep -Fqx '  /proc/devices r,' &&
     printf '%s\n' "$swap_profile" |
       grep -Fqx '  /etc/modprobe.d/** r,' &&
     printf '%s\n' "$swap_profile" |
       grep -Fqx '  /dev/dm-* rw,' &&
     printf '%s\n' "$swap_profile" |
       grep -Fqx '  /sys/devices/** r,' &&
     printf '%s\n' "$tailscale_bootstrap_profile" |
       grep -Fqx '  capability sys_ptrace,' &&
     printf '%s\n' "$tailscale_bootstrap_profile" |
       grep -Fqx '  ptrace (read) peer=unconfined,' &&
     printf '%s\n' "$tailscale_bootstrap_profile" |
       grep -Fqx '  @{PROC}/[0-9]*/stat r,' &&
     printf '%s\n' "$tailscale_bootstrap_profile" |
       grep -Fqx '  /usr/bin/tailscale rPx -> usr.bin.tailscale,' &&
     printf '%s\n' "$tailscale_bootstrap_profile" |
       grep -Fqx '  #include <abstractions/managed-wrapper-python>' &&
     printf '%s\n' "$tailscale_bootstrap_profile" |
       grep -Fqx '  / r,' &&
     grep -Fqx 'NoNewPrivileges=false' "$TAILSCALE_BOOTSTRAP_UNIT" &&
     ! grep -Fqx 'NoNewPrivileges=true' "$TAILSCALE_BOOTSTRAP_UNIT" &&
     printf '%s\n' "$zram_profile" |
       grep -Fqx '  /usr/bin/kmod rix,' &&
     printf '%s\n' "$zram_profile" |
       grep -Fqx '  /proc/devices r,' &&
     printf '%s\n' "$zram_profile" |
       grep -Fqx '  /run/blkid/** rwkl,' &&
     printf '%s\n' "$zram_profile" |
       grep -Fqx '  /dev/dm-* rw,' &&
     printf '%s\n' "$zram_writeback_profile" |
       grep -Fqx '  capability,' &&
     printf '%s\n' "$zram_writeback_profile" |
       grep -Fqx '  /{bin,boot,data,dev,etc,home,lib,lib64,media,mnt,opt,pool,proc,root,run,sbin,srv,sys,tmp,usr,var}/** rwklm,' &&
     printf '%s\n' "$zram_writeback_profile" |
       grep -Fqx '  /{bin,boot,data,dev,etc,home,lib,lib64,media,mnt,opt,pool,proc,root,run,sbin,srv,sys,tmp,usr,var}/** rix,' &&
     grep -Fqx '  /usr/local/lib/tailscale/bootstrap.log a,' "$TAILSCALE_PROFILE"; then
    pass "current system AppArmor observations map to compatibility rules or named child transitions"
  else
    fail "current system AppArmor observations map to compatibility rules or named child transitions"
  fi
  unset \
    android_platform_profile \
    apt_profile \
    crowdsec_profile \
    secondboot_profile \
    swap_profile \
    syncthing_profile \
    tailscale_bootstrap_profile \
    update_initramfs_profile \
    zram_profile \
    zram_writeback_profile
else
  fail "all enforced AppArmor denials are absent"
fi

fuzzel_profile=$(profile_block managed-labwc-fuzzel)
adb_menu_profile=$(profile_block managed-labwc-adb-menu)
computer_management_profile=$(profile_block managed-labwc-computer-management)
fuzzel_log_profile=$(profile_block managed-labwc-fuzzel-log)
security_root_profile=$(profile_block managed-labwc-security-action-root)
aa_status_profile=$(profile_block aa-status-reader "$AA_STATUS_PROFILE")
if printf '%s\n' "$fuzzel_profile" |
     grep -Fqx '  /usr/local/bin/labwc-fuzzel-log rPx -> managed-labwc-fuzzel-log,' &&
   printf '%s\n' "$adb_menu_profile" |
     grep -Fqx '  /usr/local/bin/labwc-fuzzel-log rPx -> managed-labwc-fuzzel-log,' &&
   printf '%s\n' "$computer_management_profile" |
     grep -Fqx '  /usr/local/bin/labwc-fuzzel-log rPx -> managed-labwc-fuzzel-log,' &&
   printf '%s\n' "$fuzzel_log_profile" |
     grep -Fqx '  #include <abstractions/managed-wrapper-perl>' &&
   printf '%s\n' "$fuzzel_log_profile" |
     grep -Fqx '  /dev/log w,' &&
   printf '%s\n' "$security_root_profile" |
     grep -Fqx '  /usr/{bin,sbin}/aa-status rPx -> aa-status-reader,' &&
   printf '%s\n' "$aa_status_profile" |
     grep -Fqx '  capability sys_ptrace,' &&
   printf '%s\n' "$aa_status_profile" |
     grep -Fqx '  ptrace (read),' &&
   printf '%s\n' "$aa_status_profile" |
     grep -Fqx '  @{PROC}/[0-9]*/attr/apparmor/current r,' &&
   grep -Fqx '  owner @{HOME}/Templates/ r,' "$SQLITEBROWSER_PROFILE" &&
   ! printf '%s\n' "$fuzzel_log_profile" |
     grep -Eq '//null-|[[:space:]][pP][uU]x,' &&
   ! grep -Eq '//null-|[[:space:]][pP][uU]x,' "$AA_STATUS_PROFILE"; then
  pass "Fuzzel logging, AppArmor status, and SQLite Templates denials enter named bounded profiles"
else
  fail "Fuzzel logging, AppArmor status, and SQLite Templates denials enter named bounded profiles"
fi
unset \
  aa_status_profile \
  adb_menu_profile \
  computer_management_profile \
  fuzzel_log_profile \
  fuzzel_profile \
  security_root_profile

tailscaled_profile=$(profile_block usr.sbin.tailscaled "$TAILSCALE_PROFILE")
tailscale_cli_profile=$(profile_block usr.bin.tailscale "$TAILSCALE_PROFILE")
if printf '%s\n' "$tailscaled_profile" |
     grep -Fqx '  capability dac_override,' &&
   printf '%s\n' "$tailscaled_profile" |
     grep -Fqx '  capability sys_ptrace,' &&
   printf '%s\n' "$tailscaled_profile" |
     grep -Fqx '  ptrace (read) peer=unconfined,' &&
   printf '%s\n' "$tailscaled_profile" |
     grep -Fqx '  /dev/tpmrm0 rw,' &&
   printf '%s\n' "$tailscaled_profile" |
     grep -Fqx '  /etc/**/ r,' &&
   printf '%s\n' "$tailscaled_profile" |
     grep -Fqx '  network inet raw,' &&
   printf '%s\n' "$tailscaled_profile" |
     grep -Fqx '  /usr/sbin/{ip6tables,ip6tables-restore,ip6tables-save,iptables,iptables-restore,iptables-save,xtables-nft-multi} rix,' &&
   printf '%s\n' "$tailscaled_profile" |
     grep -Fqx '  /usr/sbin/resolvconf rix,' &&
   printf '%s\n' "$tailscaled_profile" |
     grep -Fqx '  /{,usr/}bin/{flock,sed} rix,' &&
   printf '%s\n' "$tailscaled_profile" |
     grep -Fqx '  /usr/share/doc/resolvconf/copyright r,' &&
   printf '%s\n' "$tailscaled_profile" |
     grep -Fqx '  /run/resolvconf/run-lock rwk,' &&
   printf '%s\n' "$tailscaled_profile" |
     grep -Fqx '  /etc/resolvconf/update-libc.d/ rw,' &&
   printf '%s\n' "$tailscaled_profile" |
     grep -Fqx '  /etc/resolvconf/update-libc.d/tailscale rw,' &&
   printf '%s\n' "$tailscaled_profile" |
     grep -Fqx '  /etc/resolvconf/update-libc.d/tailscale.tmp[0-9]* rw,' &&
   printf '%s\n' "$tailscaled_profile" |
     grep -Fqx '  owner @{PROC}/@{pid}/{cgroup,mountinfo,mounts} r,' &&
   printf '%s\n' "$tailscaled_profile" |
     grep -Fqx '  @{PROC}/1/{cgroup,stat} r,' &&
   printf '%s\n' "$tailscaled_profile" |
     grep -Fqx '  @{sys}/devices/virtual/dmi/id/{bios_vendor,product_name,sys_vendor} r,' &&
   ! printf '%s\n' "$tailscaled_profile" |
     grep -Fq '/usr/bin/tailscale' &&
   printf '%s\n' "$tailscale_cli_profile" |
     grep -Fqx '  /usr/local/lib/tailscale/auth.key r,' &&
   printf '%s\n' "$tailscale_cli_profile" |
     grep -Fqx '  owner @{PROC}/@{pid}/{cgroup,mountinfo} r,' &&
   ! printf '%s\n' "$tailscale_cli_profile" |
     grep -Fq '/var/lib/tailscale' &&
   ! grep -Eq '[pP][uU]x|//null-' "$TAILSCALE_PROFILE" &&
   grep -Fqx '__DESKTOP_APPARMOR_STATE__ if-executable usr.sbin.tailscaled /usr/sbin/tailscaled' "$MODE_CONFIG"; then
  pass "Tailscale daemon, CLI, TPM, process metadata, and xtables activity stay in separate enforced least-privilege domains"
else
  fail "Tailscale daemon, CLI, TPM, process metadata, and xtables activity stay in separate enforced least-privilege domains"
fi
unset tailscale_cli_profile tailscaled_profile

codex_wrapper_profile=$(profile_block managed-codex-wrapper)
codex_slirp_profile=$(profile_block managed-codex-slirp4netns)
if grep -Fqx 'profile slirp4netns /usr/bin/slirp4netns flags=(unconfined, attach_disconnected) {' "$SLIRP_PROFILE" &&
   grep -Fqx 'network create unix stream,' "$SLIRP_LOCAL" &&
   grep -Fqx 'capability sys_ptrace,' "$SLIRP_LOCAL" &&
   grep -Fqx 'ptrace (read) peer=unconfined,' "$SLIRP_LOCAL" &&
   ! grep -Fq 'managed-codex' "$SLIRP_LOCAL" &&
   grep -Fqx '@{PROC}/[0-9]*/ns/{net,user} r,' "$SLIRP_LOCAL" &&
   printf '%s\n' "$codex_wrapper_profile" |
     grep -Fqx '  signal (send) set=(exists term) peer=managed-codex-slirp4netns,' &&
   printf '%s\n' "$codex_wrapper_profile" |
     grep -Fqx '  /usr/bin/slirp4netns rPx -> managed-codex-slirp4netns,' &&
   printf '%s\n' "$codex_slirp_profile" |
     grep -Fqx 'profile managed-codex-slirp4netns flags=(attach_disconnected) {' &&
   printf '%s\n' "$codex_slirp_profile" |
     grep -Fqx '  userns,' &&
   printf '%s\n' "$codex_slirp_profile" |
     grep -Fqx '  capability net_admin,' &&
   printf '%s\n' "$codex_slirp_profile" |
     grep -Fqx '  /run/resolvconf/resolv.conf r,' &&
   printf '%s\n' "$codex_slirp_profile" |
     grep -Fqx '  capability sys_admin,' &&
   printf '%s\n' "$codex_slirp_profile" |
     grep -Fqx '  capability sys_ptrace,' &&
   printf '%s\n' "$codex_slirp_profile" |
     grep -Fqx '  network create unix stream,' &&
   printf '%s\n' "$codex_slirp_profile" |
     grep -Fqx '  network inet dgram,' &&
   printf '%s\n' "$codex_slirp_profile" |
     grep -Fqx '  ptrace (read) peer=managed-codex-wrapper//codex-bwrap,' &&
   printf '%s\n' "$codex_slirp_profile" |
     grep -Fqx '  signal (receive) set=(exists term) peer=managed-codex-wrapper,' &&
   printf '%s\n' "$codex_slirp_profile" |
     grep -Fqx '  / r,' &&
   printf '%s\n' "$codex_slirp_profile" |
     grep -Fqx '  /dev/null r,' &&
   printf '%s\n' "$codex_slirp_profile" |
     grep -Fqx '  /dev/net/tun rw,' &&
   printf '%s\n' "$codex_slirp_profile" |
     grep -Fqx '  /dev/urandom r,' &&
   printf '%s\n' "$codex_slirp_profile" |
     grep -Fqx '  /usr/bin/slirp4netns mr,' &&
   printf '%s\n' "$codex_slirp_profile" |
     grep -Fqx '  /usr/lib/@{multiarch}/ld-linux-*.so* mr,' &&
   printf '%s\n' "$codex_slirp_profile" |
     grep -Fqx '  @{PROC}/[0-9]*/ns/{net,user} r,' &&
   printf '%s\n' "$codex_slirp_profile" |
     grep -Fqx '  owner /data/codex/runtime/.control/launch.*/{slirp.stdout,slirp.stderr} w,' &&
   printf '%s\n' "$codex_slirp_profile" |
     grep -Fqx '  owner /data/codex/runtime/.control/launch.*/{bwrap-info.fifo,bwrap-block.fifo,slirp-ready.fifo} rw,' &&
   grep -Fqx '__DESKTOP_APPARMOR_STATE__ required managed-desktop-wrappers -' "$MODE_CONFIG" &&
   grep -Fqx '__DESKTOP_APPARMOR_STATE__ if-executable slirp4netns /usr/bin/slirp4netns' "$MODE_CONFIG" &&
   awk '
     /^apparmor_managed_system_profile_files\(\) \{$/ {
       in_function = 1
       next
     }
     in_function && /^}$/ {
       exit
     }
     in_function && $0 == "slirp4netns" {
       found = 1
     }
     END {
       exit found ? 0 : 1
     }
   ' "$SECURITY_SCRIPT"; then
  pass "Codex slirp4netns enters a dedicated enforce-capable least-privilege domain"
else
  fail "Codex slirp4netns enters a dedicated enforce-capable least-privilege domain"
fi
unset codex_slirp_profile codex_wrapper_profile

managed_app_profile=$(profile_block managed-labwc-managed-app)
whisper_profile=$(profile_block managed-whisper-record-toggle)
if printf '%s\n' "$managed_app_profile" |
     grep -Fqx '  /usr/local/lib/python3.14/dist-packages/ r,' &&
   printf '%s\n' "$whisper_profile" |
     grep -Fqx '  #include <abstractions/managed-pipewire-audio>' &&
   printf '%s\n' "$whisper_profile" |
     grep -Fqx '  /usr/bin/systemctl ix,' &&
   printf '%s\n' "$whisper_profile" |
     grep -Fqx '  /usr/bin/wpctl ix,' &&
   printf '%s\n' "$whisper_profile" |
     grep -Fqx '  @{sys}/devices/virtual/dmi/id/{bios_vendor,board_vendor} r,' &&
   printf '%s\n' "$whisper_profile" |
     grep -Fqx '  owner @{PROC}/[0-9]*/task/[0-9]*/comm rw,' &&
   printf '%s\n' "$whisper_profile" |
     grep -Fqx '  owner /run/user/[0-9]*/bus rw,' &&
   printf '%s\n' "$whisper_profile" |
     grep -Fqx '  owner @{HOME}/Music/Whisper/ rw,'; then
  pass "managed app imports and Whisper control keep PipeWire access constrained without unconfined execution"
else
  fail "managed app imports and Whisper control keep PipeWire access constrained without unconfined execution"
fi
unset managed_app_profile whisper_profile

digital_assets_profile=$(profile_block managed-labwc-digital-assets)
digital_assets_action_profile=$(profile_block managed-labwc-digital-assets-action)
sync_launchers_profile=$(profile_block managed-labwc-sync-application-launchers)
managed_bwrap_profile=$(profile_block managed-app-bwrap)
if printf '%s\n' "$digital_assets_profile" |
     grep -Fqx '  owner @{HOME}/ r,' &&
   ! printf '%s\n' "$digital_assets_profile" |
     grep -Fq 'owner @{HOME}/**' &&
   printf '%s\n' "$digital_assets_action_profile" |
     grep -Fqx '  owner /run/user/[0-9]*/labwc-digital-assets-catalog.* rwk,' &&
   printf '%s\n' "$sync_launchers_profile" |
     grep -Fqx '  /usr/share/*/*.desktop r,' &&
   printf '%s\n' "$managed_bwrap_profile" |
     grep -Fqx '    /usr/share/glycin-loaders/2+/conf.d/** r,' &&
   printf '%s\n' "$managed_bwrap_profile" |
     grep -Fqx '    /usr/bin/{bwrap,true} rix,' &&
   printf '%s\n' "$managed_bwrap_profile" |
     grep -Fqx '    /usr/libexec/glycin-loaders/2+/{glycin-image-rs,glycin-svg} rix,' &&
   grep -Fqx '  /dev/dri/card[0-9]* rw,' "$POSTMAN_PROFILE" &&
   grep -Fqx '  /proc/[0-9]*/loginuid r,' "$POSTMAN_PROFILE" &&
   grep -Fqx '  /usr/bin/ r,' "$POSTMAN_PROFILE" &&
   grep -Fqx '  /usr/sbin/ r,' "$POSTMAN_PROFILE" &&
   grep -Fqx '  /usr/local/bin/ r,' "$POSTMAN_PROFILE" &&
   grep -Fqx '  /usr/local/sbin/ r,' "$POSTMAN_PROFILE"; then
  pass "Digital Assets, package launchers, Glycin, and Postman retain exact rules from the denied-mask log"
else
  fail "Digital Assets, package launchers, Glycin, and Postman retain exact rules from the denied-mask log"
fi
unset digital_assets_profile digital_assets_action_profile sync_launchers_profile managed_bwrap_profile

session_profile=$(profile_block managed-labwc-session)
edge_launcher_profile=$(profile_block labwc-microsoft-edge-launcher)
mullvad_launcher_profile=$(profile_block labwc-mullvad-browser-launcher)
if grep -Fq 'exec 9>"$lock_path"' "$SESSION_WRAPPER" &&
   grep -Fq '/usr/bin/flock --nonblock 9 || exit 0' "$SESSION_WRAPPER" &&
   grep -Fq '"$systemctl_cmd" --user --wait start labwc-compositor.service 9>&- || labwc_status=$?' "$SESSION_WRAPPER" &&
   ! grep -Fq '/usr/bin/labwc 9>&-' "$SESSION_WRAPPER" &&
   ! grep -Fq '/usr/bin/true' "$SESSION_WRAPPER" &&
   printf '%s\n' "$session_profile" |
     grep -Fqx '  owner /run/user/[0-9]*/labwc-session.lock rwk,' &&
   ! printf '%s\n' "$session_profile" |
     grep -Fq '/usr/bin/true' &&
   ! printf '%s\n' "$session_profile" |
     grep -Fq '/usr/bin/labwc' &&
   ! grep -Fq 'labwc-session.lock' "$WRAPPER_DESKTOP" &&
   ! grep -Fq 'labwc-session.lock' "$DESKTOP_RUNTIME" &&
   ! printf '%s\n' "$edge_launcher_profile" |
     grep -Fq 'labwc-session.lock' &&
   ! printf '%s\n' "$mullvad_launcher_profile" |
     grep -Fq 'labwc-session.lock'; then
  pass "Labwc session locking remains in the login wrapper without leaking the descriptor to systemctl"
else
  fail "Labwc session locking remains in the login wrapper without leaking the descriptor to systemctl"
fi
unset session_profile edge_launcher_profile mullvad_launcher_profile

if ! grep -Eq '(start_background|flock|labwc-[a-z-]+[.]lock)' "$AUTOSTART_WRAPPER" &&
   grep -Fq 'fuzzel "$@" <&7 >&1 2>&2 8>&- &' "$FUZZEL_WRAPPER" &&
   grep -Fq 'sleep 0.15 9>&-' "$KEYBOARD_WRAPPER" &&
   grep -Fq 'labwc --reconfigure 9>&- >/dev/null 2>&1 || true' "$KEYBOARD_WRAPPER" &&
   grep -Fq 'swaylock -f -c "$config_path" --image "$lock_background_path" --scaling fill "$@" 9>&-' "$LOCK_WRAPPER" &&
   ! grep -R -Fq 'crystal-dock.running.lock' "$APPARMOR_DIR"; then
  pass "persistent components use systemd while the remaining interactive singleton locks stay wrapper-owned"
else
  fail "persistent components use systemd while the remaining interactive singleton locks stay wrapper-owned"
fi

if grep -Fqx '  owner @{PROC}/[0-9]*/mem r,' "$DISCORD_PROFILE" &&
   grep -Fqx '  /opt/discord/** mrix,' "$DISCORD_PROFILE" &&
   ! grep -Eq '^  owner @\{HOME\}/[.]config/discord/app-[^[:space:]]*(/[^[:space:]]*)?[[:space:]]+[^,]*[mix][^,]*,$' "$DISCORD_PROFILE" &&
   grep -Fqx '/etc/ r,' "$DESKTOP_RUNTIME" &&
   grep -Fqx '@{PROC}/uptime r,' "$ELECTRON_RUNTIME" &&
   grep -Fqx '@{sys}/devices/system/cpu/cpufreq/policy[0-9]*/scaling_max_freq r,' "$DESKTOP_GRAPHICS"; then
  pass "Discord voice encoding and crash handling use the root-owned runtime without user-updater execution"
else
  fail "Discord voice encoding and crash handling use the root-owned runtime without user-updater execution"
fi

mullvad_launcher_profile=$(profile_block labwc-mullvad-browser-launcher)
if grep -Fqx 'signal (send) set=(kill) peer=mullvad-browser//mullvad-bwrap,' "$MULLVAD_LOCAL" &&
   grep -Fqx '  signal (receive) set=(kill) peer=mullvad-browser,' "$MULLVAD_LOCAL" &&
   grep -Fqx '  /usr/bin/true rix,' "$MULLVAD_LOCAL" &&
   grep -Fqx '/dev/ r,' "$MULLVAD_LOCAL" &&
   grep -Fqx '/etc/mime.types r,' "$MULLVAD_LOCAL" &&
   grep -Fqx '@{sys}/fs/cgroup/**/cpu.max r,' "$MULLVAD_LOCAL" &&
   grep -Fqx 'owner @{HOME}/.cache/mullvad/ rw,' "$MULLVAD_LOCAL" &&
   printf '%s\n' "$mullvad_launcher_profile" |
     grep -Fqx '  /dev/tty rw,'; then
  pass "Mullvad Browser and Bubblewrap have reciprocal bounded startup and signal access"
else
  fail "Mullvad Browser and Bubblewrap have reciprocal bounded startup and signal access"
fi
unset mullvad_launcher_profile

if grep -Fqx '  #include <abstractions/managed-pipewire-audio>' "$LEDGER_PROFILE" &&
   grep -Fqx '  /dev/tty rw,' "$LEDGER_PROFILE" &&
   grep -Fqx '  @{sys}/devices/**/report_descriptor r,' "$LEDGER_PROFILE" &&
   grep -Fqx '  owner "@{HOME}/.config/Ledger Wallet/" rw,' "$LEDGER_PROFILE" &&
   grep -Fqx '  owner "@{HOME}/.config/Ledger Wallet/**" rwkl,' "$LEDGER_PROFILE" &&
   grep -Fqx 'owner @{HOME}/.config/pulse/** rwk,' "$PIPEWIRE_AUDIO"; then
  pass "Ledger Live has its observed legacy state, PipeWire, TTY, and HID metadata access"
else
  fail "Ledger Live has its observed legacy state, PipeWire, TTY, and HID metadata access"
fi

if grep -Fqx '  deny @{sys}/devices/**/iio:device[0-9]*/in_accel_{offset,sampling_frequency,scale,x_raw,y_raw,z_raw} r,' "$TUTA_PROFILE" &&
   grep -Fqx 'deny /usr/lib/chromium/extensions/ w,' "$CHROMIUM_LOCAL"; then
  pass "Tuta sensor polling and Chromium package-tree creation remain explicitly unavailable"
else
  fail "Tuta sensor polling and Chromium package-tree creation remain explicitly unavailable"
fi

chromium_launcher_profile=$(profile_block labwc-chromium-launcher)
if printf '%s\n' "$chromium_launcher_profile" |
     grep -Fqx '  owner @{HOME}/ r,' &&
   ! printf '%s\n' "$chromium_launcher_profile" |
     grep -Fq 'owner @{HOME}/**'; then
  pass "Chromium launcher home discovery is limited to the user-home directory entry"
else
  fail "Chromium launcher home discovery is limited to the user-home directory entry"
fi
unset chromium_launcher_profile

if grep -Fqx '@{PROC}/[0-9]*/mountinfo r,' "$ELECTRON_RUNTIME" &&
   ! grep -Fq '@{PROC}/[0-9]*/mountinfo' "$ELECTRON_APPLICATION"; then
  pass "Electron mountinfo access lives in the capability-free runtime abstraction"
else
  fail "Electron mountinfo access lives in the capability-free runtime abstraction"
fi

if grep -Fqx 'profile keepassxc /usr/bin/keepassxc flags=(attach_disconnected, mediate_deleted) {' "$KEEPASSXC_PROFILE" &&
   grep -Fqx '  @{sys}/devices/**/usb*/speed r,' "$KEEPASSXC_PROFILE" &&
   grep -Fqx '  @{sys}/devices/**/usb*/**/speed r,' "$KEEPASSXC_PROFILE" &&
   grep -Fqx '  owner @{HOME}/.cache/keepassxc/** rwkl,' "$KEEPASSXC_PROFILE" &&
   grep -Fqx '  owner @{HOME}/.config/keepassxc/** rwkl,' "$KEEPASSXC_PROFILE"; then
  pass "KeePassXC permits observed atomic replacements and bounded USB speed reads"
else
  fail "KeePassXC permits observed atomic replacements and bounded USB speed reads"
fi

if grep -Fqx 'profile sqlitebrowser /usr/bin/sqlitebrowser flags=(attach_disconnected, mediate_deleted) {' "$SQLITEBROWSER_PROFILE" &&
   grep -Fqx '  owner @{HOME}/.config/QtProject.conf rwkl,' "$SQLITEBROWSER_PROFILE" &&
   grep -Fqx '  owner @{HOME}/.config/#[0-9]* rwkl,' "$SQLITEBROWSER_PROFILE" &&
   grep -Fqx '  owner @{HOME}/.config/sqlitebrowser/#[0-9]* rwkl,' "$SQLITEBROWSER_PROFILE" &&
   grep -Fqx '  owner @{HOME}/.config/sqlitebrowser/sqlitebrowser.conf rwkl,' "$SQLITEBROWSER_PROFILE"; then
  pass "SQLiteBrowser mediates deleted temporary files during bounded configuration replacements"
else
  fail "SQLiteBrowser mediates deleted temporary files during bounded configuration replacements"
fi

mute_default_microphone_profile=$(profile_block managed-labwc-mute-default-microphone)
if printf '%s\n' "$mute_default_microphone_profile" |
     grep -Fqx '  @{sys}/devices/virtual/dmi/id/{bios_vendor,board_vendor,product_name,sys_vendor} r,' &&
   printf '%s\n' "$mute_default_microphone_profile" |
     grep -Fqx '  owner @{PROC}/[0-9]*/task/[0-9]*/comm rw,' &&
   grep -Fqx '  owner @{HOME}/.{bash_aliases,bash_profile,bashrc,dircolors,profile,sudo_as_admin_successful,vimrc,zlogout,zprofile,zsh_aliases,zshenv,zshrc} r,' "$SQLITEBROWSER_PROFILE" &&
   grep -Fqx '$audio->set_available_sources_muted(1);' "$MUTE_DEFAULT_MICROPHONE" &&
   grep -Fqx 'sub set_available_sources_muted {' "$AUDIO_MODULE" &&
   grep -Fqx "    _command_status(\$wpctl, 'set-default', \$source->{id});" "$AUDIO_MODULE" &&
   grep -Fqx '    return 1 if $normalized =~ /hdmi/;' "$AUDIO_MODULE" &&
   grep -Fqx '    return 1 if $normalized =~ /display(?:[._ -]?port)/;' "$AUDIO_MODULE"; then
  pass "Microphone and SQLiteBrowser audit access stays bounded while every session input starts muted"
else
  fail "Microphone and SQLiteBrowser audit access stays bounded while every session input starts muted"
fi
unset mute_default_microphone_profile

[ "$FAIL_COUNT" -eq 0 ]
