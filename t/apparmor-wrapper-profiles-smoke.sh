#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/apparmor-wrapper-profiles-smoke.XXXXXX")
trap 'rm -rf -- "$TMP_DIR"' EXIT HUP INT TERM

PROFILE="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/managed-desktop-wrappers"
SYSTEM_PROFILE="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/managed-system-wrappers"
APPARMOR_DIR="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d"
CHATGPT_PROFILE="$APPARMOR_DIR/chatgpt"
ABSTRACTION_DIR="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/abstractions"
APPARMOR_PARSER_TEST_CONFIG="$TMP_DIR/apparmor-parser.conf"
SPOTIFY_PROFILE="$APPARMOR_DIR/usr.bin.spotify"
NVIDIA_WRAPPER_LOCAL="$ROOT_DIR/d-i/forky/hooks/hardware/gpu/nvidia/target/etc/apparmor.d/local/managed-desktop-wrappers-nvidia"
MODE_CONFIG="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor/managed-modes.conf.tmpl"
SECURITY_SCRIPT="$ROOT_DIR/d-i/forky/scripts/late/security.sh"
FUZZEL_WRAPPER="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-fuzzel"
DISPLAY_CONFIGURATION_WRAPPER="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-display-configuration"
COMPUTER_MANAGEMENT_WRAPPER="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-computer-management"
MULLVAD_VPN_WRAPPER="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/mullvad-vpn"
MULLVAD_DAEMON_START="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/libexec/mullvad-daemon-start"
AUTOSTART_WRAPPER="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-autostart"
BLUETOOTH_WRAPPER="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-bluetooth"
BRIGHTNESS_WRAPPER="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-brightness-control"
CAPTURE_WRAPPER="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-capture"
KEYBOARD_WRAPPER="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-keyboard-layout"
LOCK_WRAPPER="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-lock"
SESSION_WRAPPER="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-session.tmpl"
BLUETOOTH_UNIT="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/systemd/system/bluetooth-controller-init.service"
CLAMAV_UPDATE_UNIT="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/systemd/system/managed-clamav-signature-update.service"
HEALTH_NOTIFY_UNIT="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/systemd/user/labwc-health-notify.service"
PLANS_NOTIFY_UNIT="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/systemd/user/labwc-plans.service"
SOFTWARE_NOTIFY_UNIT="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/systemd/user/managed-external-software-notify.service"
SOFTWARE_UPDATE_UNIT="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/systemd/system/managed-external-software-update.service"
INCUS_HOST_UNIT="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/systemd/system/incus-host-managed.service"
LABWC_ADMIN_WORKER_UNIT="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/systemd/system/labwc-admin-action@.service"
APPARMOR_MODE_UNIT="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/systemd/system/apparmor-managed-modes.service"
SECONDBOOT_UNIT="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/systemd/system/secondboot.service"
CROWDSEC_UNIT="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/systemd/system/crowdsec-firstboot.service"
MANAGED_SYNCTHING_UNIT="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/systemd/system/managed-syncthing.service.tmpl"
FIRSTBOOT_WRAPPER="$ROOT_DIR/d-i/forky/scripts/firstboot/firstboot.sh"
FIRSTBOOT_STAGE_SCRIPT="$ROOT_DIR/d-i/forky/scripts/late/core.sh"
APT_REFRESH_WRAPPER="$ROOT_DIR/d-i/forky/hooks/shared/target/usr/local/libexec/apt-refresh-lists.tmpl"
SWAP_FALLBACK_WRAPPER="$ROOT_DIR/d-i/forky/hooks/shared/target/usr/local/libexec/swap-fallback-setup.tmpl"
APTLY_MANAGED_WRAPPER="$ROOT_DIR/d-i/forky/hooks/services/gitlab-runner/target/usr/local/sbin/aptly-managed"
GITLAB_RUNNER_MANAGED_WRAPPER="$ROOT_DIR/d-i/forky/hooks/services/gitlab-runner/target/usr/local/sbin/gitlab-runner-managed"
APTLY_ENV_HELPER="$ROOT_DIR/d-i/forky/hooks/services/gitlab-runner/target/pool/aptly/bin/prepare-aptly-env.sh"
TIMESHIFT_PROFILE="$APPARMOR_DIR/timeshift"
TIMESHIFT_RUNTIME="$ABSTRACTION_DIR/managed-timeshift-runtime"
WEBKIT_RUNTIME="$ABSTRACTION_DIR/managed-webkit-runtime"
GRIDLINE_PROFILE="$APPARMOR_DIR/usr.bin.gridline"
QOREDB_PROFILE="$APPARMOR_DIR/usr.bin.qoredb"
TIMESHIFT_GRUB_HOOK="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/timeshift/backup-hooks.d/90-grub-btrfs-refresh"
GRUB_BTRFS_REFRESH_UNIT="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/systemd/system/grub-btrfs-refresh.service"
WIFI_REGDOM_RULE="$ROOT_DIR/d-i/forky/hooks/hardware/cpu/intel/target/etc/udev/rules.d/85-wifi-regdom.rules"

TEST_COUNT=40
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
  profile_block_from_file "$PROFILE" "$expected_profile"
}

system_profile_block() {
  expected_profile=$1
  profile_block_from_file "$SYSTEM_PROFILE" "$expected_profile"
}

profile_block_from_file() (
  profile_file=$1
  expected_profile=$2

  case "$profile_file" in
    "$PROFILE")
      cache_scope=desktop
      ;;
    "$SYSTEM_PROFILE")
      cache_scope=system
      ;;
    *)
      return 1
      ;;
  esac

  case "$expected_profile" in
    ''|*[!A-Za-z0-9_.-]*)
      return 1
      ;;
  esac

  cache_file="$TMP_DIR/profile-block-${cache_scope}-${expected_profile}"
  if [ -f "$cache_file" ]; then
    cat "$cache_file"
    return
  fi

  cache_tmp="$cache_file.tmp"

  awk -v expected_profile="$expected_profile" '
    $1 == "profile" && $2 == expected_profile {
      in_profile = 1
      depth = 0
    }
    in_profile {
      print
      if ($0 ~ /^[[:space:]]*profile[[:space:]].*[[:space:]]\{[[:space:]]*$/) {
        depth++
      } else if ($0 ~ /^[[:space:]]*\}[[:space:]]*$/) {
        depth--
        if (depth == 0) {
          exit
        }
      }
    }
  ' "$profile_file" >"$cache_tmp"
  mv -- "$cache_tmp" "$cache_file"
  cat "$cache_file"
)

private_xwayland_library_rules_present() {
  for private_library_name in \
    libXau.so.6 \
    libXdmcp.so.6 \
    libXfont2.so.2 \
    libfontenc.so.1 \
    libxcb-cursor.so.0 \
    libxcb-image.so.0 \
    libxcb-render-util.so.0 \
    libxcb-render.so.0 \
    libxcb-shm.so.0 \
    libxcb-util.so.1 \
    libxcb.so.1 \
    libxcvt.so.0 \
    libxshmfence.so.1
  do
    profile_block managed-labwc-managed-wayland-compat-app |
      grep -Fqx \
        "  /opt/xwayland/usr/lib/x86_64-linux-gnu/${private_library_name} r," &&
      profile_block managed-labwc-managed-wayland-compat-app |
        grep -Fqx \
          "  /opt/xwayland/usr/lib/x86_64-linux-gnu/${private_library_name}.* r," &&
      profile_block managed-wayland-compat-app-bwrap |
        grep -Fqx \
          "    /opt/xwayland/usr/lib/x86_64-linux-gnu/${private_library_name} mr," &&
      profile_block managed-wayland-compat-app-bwrap |
        grep -Fqx \
          "    /opt/xwayland/usr/lib/x86_64-linux-gnu/${private_library_name}.* mr," ||
      return 1
  done
  ! profile_block managed-wayland-compat-app-bwrap |
    grep -Fq '    /usr/lib/x86_64-linux-gnu/libxcb-cursor.so.'
}

printf '1..%s\n' "$TEST_COUNT"

# The development host may prepend its installed /etc/apparmor.d through
# parser.conf. Keep tracked policy authoritative and use package trees only as
# fallbacks for Debian-supplied abstractions and feature ABI data.
: >"$APPARMOR_PARSER_TEST_CONFIG"

expected_paths="$TMP_DIR/expected-paths"
actual_paths="$TMP_DIR/actual-paths"

if python3 - "$ROOT_DIR" "$APPARMOR_DIR" "$expected_paths" "$actual_paths" <<'PY'
from pathlib import Path
import fnmatch
import re
import sys

root = Path(sys.argv[1])
apparmor_dir = Path(sys.argv[2])
expected_output = Path(sys.argv[3])
actual_output = Path(sys.argv[4])

expected = []
for source_path in sorted((root / "d-i/forky/hooks").rglob("*")):
    if not source_path.is_file():
        continue
    source_text = source_path.as_posix()
    marker = "/target/usr/local/"
    if marker not in source_text:
        continue
    installed_path = source_text.split("/target", 1)[1]
    if not installed_path.startswith(
        ("/usr/local/bin/", "/usr/local/sbin/", "/usr/local/libexec/")
    ):
        continue
    if installed_path == "/usr/local/sbin/nft-policy-generate.py":
        installed_path = "/usr/local/sbin/nft-policy-generate"
    elif installed_path.endswith(".tmpl"):
        installed_path = installed_path[:-5]
    expected.append(installed_path)

# firstboot.sh is staged from scripts/firstboot rather than hooks/**/target.
expected.append("/usr/local/libexec/firstboot.sh")
expected.extend(
    (
        "/etc/initramfs-tools/hooks/tpm2-cryptroot",
        "/etc/initramfs-tools/scripts/init-bottom/90-installer-health",
        "/etc/initramfs-tools/scripts/init-premount/90-installer-health",
        "/etc/initramfs-tools/scripts/init-top/90-installer-health",
        "/etc/initramfs-tools/scripts/local-block/90-installer-health",
        "/etc/initramfs-tools/scripts/local-bottom/90-installer-health",
        "/etc/initramfs-tools/scripts/local-premount/90-installer-health",
        "/etc/initramfs-tools/scripts/local-top/00-tpm2-cryptroot",
        "/etc/initramfs-tools/scripts/local-top/90-installer-health",
        "/usr/libexec/install-tools/bootprofile-apply",
        "/usr/libexec/install-tools/secure-boot-tool",
        "/etc/kernel/postinst.d/zz-sign-kernel",
        "/etc/kernel/postrm.d/zz-sign-kernel-cleanup",
        "/etc/kernel/header_postinst.d/zz-sign-kernel-headers",
        "/etc/skel/.config/labwc/autostart",
        "/etc/skel/.config/labwc/shutdown",
        "/etc/timeshift/backup-hooks.d/90-grub-btrfs-refresh",
        "/data/codex/lib/codex",
        "/data/llama/lib/llama",
        "/pool/aptly/bin/aptly",
        "/pool/aptly/bin/aptly-bridge",
        "/pool/aptly/bin/prepare-aptly-env.sh",
    )
)
expected = sorted(set(expected))


def expand_braces(pattern: str) -> list[str]:
    start = pattern.find("{")
    if start < 0:
        return [pattern]
    depth = 0
    end = -1
    for index in range(start, len(pattern)):
        char = pattern[index]
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                end = index
                break
    if end < 0:
        raise SystemExit(f"unbalanced AppArmor attachment braces: {pattern}")
    body = pattern[start + 1 : end]
    choices = []
    choice_start = 0
    nested = 0
    for index, char in enumerate(body):
        if char == "{":
            nested += 1
        elif char == "}":
            nested -= 1
        elif char == "," and nested == 0:
            choices.append(body[choice_start:index])
            choice_start = index + 1
    choices.append(body[choice_start:])
    expanded = []
    for choice in choices:
        expanded.extend(
            expand_braces(pattern[:start] + choice + pattern[end + 1 :])
        )
    return expanded


attachments = []
profile_line = re.compile(
    r"^profile\s+(?P<label>\S+)(?:\s+(?P<attachment>/\S+))?"
    r"(?:\s+flags=.*)?\s+\{$"
)
for profile_path in sorted(apparmor_dir.iterdir()):
    if not profile_path.is_file():
        continue
    for line in profile_path.read_text(encoding="utf-8").splitlines():
        match = profile_line.match(line)
        if match is None or match.group("attachment") is None:
            continue
        for attachment in expand_braces(match.group("attachment")):
            attachments.append((match.group("label"), attachment))

errors = []
matched = []
for installed_path in expected:
    matching = [
        (label, attachment)
        for label, attachment in attachments
        if fnmatch.fnmatchcase(installed_path, attachment)
    ]
    if len(matching) != 1:
        errors.append(
            f"{installed_path}: expected exactly one attachment, got "
            + (", ".join(f"{label}:{attachment}" for label, attachment in matching)
               if matching else "none")
        )
        continue
    matched.append(f"{installed_path}\t{matching[0][0]}\t{matching[0][1]}")

expected_output.write_text("\n".join(expected) + "\n", encoding="utf-8")
actual_output.write_text("\n".join(sorted(matched)) + "\n", encoding="utf-8")
if len(expected) != 151:
    errors.append(f"expected 151 staged executable wrapper paths, found {len(expected)}")
if errors:
    print("\n".join(errors), file=sys.stderr)
    raise SystemExit(1)
PY
then
  pass "all staged executable wrapper paths have exactly one attachment"
else
  fail "all staged executable wrapper paths have exactly one attachment"
fi

if python3 - "$ROOT_DIR" "$expected_paths" <<'PY'
from pathlib import Path
import re
import sys

root = Path(sys.argv[1])
exact_paths = set(Path(sys.argv[2]).read_text(encoding="utf-8").splitlines())
hooks_root = root / "d-i/forky/hooks"

non_executable_sources = {
    "d-i/forky/hooks/shared/target/data/config/podman/templates/podbin/images/runtime/entrypoint.sh.tmpl",
    "d-i/forky/hooks/shared/target/etc/default/grub-profiles.tmpl",
    "d-i/forky/hooks/shared/target/etc/initramfs-tools/scripts/installer-health-common",
    "d-i/forky/hooks/shared/target/etc/profile.d/tpm2-enroll-prompt.sh",
    "d-i/forky/hooks/shared/target/usr/libexec/install-tools/system-log.sh",
    "d-i/forky/hooks/role/desktop/target/usr/local/share/labwc-greeter/autostart",
}
destination_overrides = {
    "d-i/forky/hooks/shared/target/etc/initramfs-tools/scripts/local-top/tpm2-cryptroot":
        "/etc/initramfs-tools/scripts/local-top/00-tpm2-cryptroot",
    "d-i/forky/hooks/shared/target/usr/local/sbin/nft-policy-generate.py":
        "/usr/local/sbin/nft-policy-generate",
}

shebang_sources = []
errors = []
for source_path in sorted(hooks_root.rglob("*")):
    if not source_path.is_file() or "/target/" not in source_path.as_posix():
        continue
    with source_path.open("rb") as source_file:
        first_line = source_file.readline(512)
    if not first_line.startswith(b"#!"):
        continue
    relative_source = source_path.relative_to(root).as_posix()
    shebang_sources.append(relative_source)
    if relative_source in non_executable_sources:
        continue
    installed_path = destination_overrides.get(relative_source)
    if installed_path is None:
        installed_path = "/" + source_path.as_posix().split("/target/", 1)[1]
        if installed_path.endswith(".tmpl"):
            installed_path = installed_path[:-5]
    if installed_path not in exact_paths:
        errors.append(
            f"{relative_source}: executable destination lacks an exact attachment: "
            f"{installed_path}"
        )

podman_script = (root / "d-i/forky/scripts/late/podman.sh").read_text(
    encoding="utf-8"
)
core_script = (root / "d-i/forky/scripts/late/core.sh").read_text(
    encoding="utf-8"
)
crypto_script = (root / "d-i/forky/scripts/late/crypto.sh").read_text(
    encoding="utf-8"
)
storage_script = (
    root / "d-i/forky/scripts/late/storage-maintenance.sh"
).read_text(encoding="utf-8")
desktop_components_script = (
    root / "d-i/forky/scripts/desktop/components.sh"
).read_text(encoding="utf-8")
btrfs_script = (root / "d-i/forky/scripts/late/btrfs-family.sh").read_text(
    encoding="utf-8"
)
f2fs_script = (root / "d-i/forky/scripts/late/f2fs-family.sh").read_text(
    encoding="utf-8"
)

required_non_executable_contracts = (
    (
        podman_script,
        'entrypoint.sh.tmpl)" "${PODBIN_TEMPLATE_DIR}/images/runtime/entrypoint.sh" 0644',
        "Podbin image entrypoint is non-executable host build input",
    ),
    (
        core_script,
        'installer-health-common)" "${FILE_INITRAMFS_HEALTH_COMMON}" 0644',
        "initramfs health common library is sourced, not executed",
    ),
    (
        crypto_script,
        re.compile(
            r"etc/profile[.]d/tpm2-enroll-prompt[.]sh.*?"
            r"/etc/profile[.]d/tpm2-enroll-prompt[.]sh.*?0644",
            re.DOTALL,
        ),
        "TPM2 login prompt is sourced, not executed",
    ),
    (
        storage_script,
        'system-log.sh)" "/usr/libexec/install-tools/system-log.sh" 0644',
        "system log helper is sourced, not executed",
    ),
    (
        desktop_components_script,
        "usr/local/share/labwc-greeter/autostart "
        "/usr/local/share/labwc-greeter/autostart 0644",
        "greeter autostart source is installed as non-executable runtime input",
    ),
)
for script_text, contract, description in required_non_executable_contracts:
    matched = (
        contract.search(script_text) is not None
        if isinstance(contract, re.Pattern)
        else contract in script_text
    )
    if not matched:
        errors.append(description)

grub_fetch = (
    'fetch_hook "$(installer_repo_join_var DIR_HOOKS_SHARED_TARGET '
    'etc/default/grub-profiles.tmpl)" "$TMP_ENV_DIR/grub-profiles"'
)
if grub_fetch not in btrfs_script or grub_fetch not in f2fs_script:
    errors.append("GRUB profile helpers must remain installer-only sourced input")

if len(shebang_sources) != 156:
    errors.append(
        f"expected 156 shebang-bearing hook assets, found {len(shebang_sources)}"
    )
if len(non_executable_sources) != 6:
    errors.append("expected six explicit non-executable shebang source contracts")
if errors:
    print("\n".join(errors), file=sys.stderr)
    raise SystemExit(1)
PY
then
  pass "every shebang-bearing hook asset is attached or explicitly staged as non-executable data"
else
  fail "every shebang-bearing hook asset is attached or explicitly staged as non-executable data"
fi

if python3 - "$ROOT_DIR" "$APPARMOR_DIR" "$MODE_CONFIG" "$PROFILE" <<'PY'
from pathlib import Path
import ast
import fnmatch
import re
import sys

root = Path(sys.argv[1])
apparmor_dir = Path(sys.argv[2])
mode_config = Path(sys.argv[3])
wrapper_profile = Path(sys.argv[4])


def expand_braces(pattern: str) -> list[str]:
    start = pattern.find("{")
    if start < 0:
        return [pattern]
    depth = 0
    end = -1
    for index in range(start, len(pattern)):
        if pattern[index] == "{":
            depth += 1
        elif pattern[index] == "}":
            depth -= 1
            if depth == 0:
                end = index
                break
    if end < 0:
        raise SystemExit(f"unbalanced AppArmor braces: {pattern}")
    body = pattern[start + 1:end]
    choices = []
    choice_start = 0
    nested = 0
    for index, character in enumerate(body):
        if character == "{":
            nested += 1
        elif character == "}":
            nested -= 1
        elif character == "," and nested == 0:
            choices.append(body[choice_start:index])
            choice_start = index + 1
    choices.append(body[choice_start:])
    expanded = []
    for choice in choices:
        expanded.extend(
            expand_braces(pattern[:start] + choice + pattern[end + 1:])
        )
    return expanded


profile_text = "\n".join(
    profile_path.read_text(encoding="utf-8")
    for profile_path in sorted(apparmor_dir.iterdir())
    if profile_path.is_file()
)
profile_labels = set()
attachments = []
for line in profile_text.splitlines():
    match = re.match(
        r"^profile\s+(?P<label>\S+)(?:\s+(?P<attachment>/\S+))?"
        r"(?:\s+flags=.*)?\s+\{$",
        line,
    )
    if match is None:
        continue
    profile_labels.add(match.group("label"))
    if match.group("attachment") is not None:
        attachments.extend(
            (match.group("label"), attachment)
            for attachment in expand_braces(match.group("attachment"))
        )

wrapper_text = wrapper_profile.read_text(encoding="utf-8")
managed_app_rules = []
for managed_profile_name in (
    "managed-labwc-managed-app",
    "managed-labwc-managed-wayland-compat-app",
):
    managed_app_match = re.search(
        rf"^profile {managed_profile_name} .*?^}}\n",
        wrapper_text,
        re.MULTILINE | re.DOTALL,
    )
    if managed_app_match is None:
        raise SystemExit(f"{managed_profile_name} profile is missing")
    for match in re.finditer(
        r"^[ \t]+(?P<path>/\S+) (?P<access>[A-Za-z]+)"
        r"(?: -> (?P<target>[^,]+))?,$",
        managed_app_match.group(0),
        re.MULTILINE,
    ):
        if "x" not in match.group("access"):
            continue
        for rule_path in expand_braces(match.group("path")):
            managed_app_rules.append(
                (rule_path, match.group("access"), match.group("target"))
            )

managed_mode_probes = set()
for line in mode_config.read_text(encoding="utf-8").splitlines():
    fields = line.split()
    if len(fields) == 4 and not fields[0].startswith("#") and fields[3].startswith("/"):
        managed_mode_probes.add(fields[3])

profiles_path = (
    root
    / "d-i/forky/hooks/role/desktop/target/usr/local/lib/python3.14/"
    "dist-packages/labwc_managed_app/profiles.py"
)
syntax_tree = ast.parse(profiles_path.read_text(encoding="utf-8"))
apps_node = None
for statement in syntax_tree.body:
    if (
        isinstance(statement, ast.Assign)
        and any(isinstance(target, ast.Name) and target.id == "APPS"
                for target in statement.targets)
    ):
        apps_node = statement.value
        break
if not isinstance(apps_node, ast.Dict):
    raise SystemExit("managed application APPS catalog is missing")

application_paths = []
for app_key, app_value in zip(apps_node.keys, apps_node.values):
    app_name = ast.literal_eval(app_key)
    if not isinstance(app_value, ast.Dict):
        raise SystemExit(f"{app_name}: application policy is not a dictionary")
    for key_node, value_node in zip(app_value.keys, app_value.values):
        key = ast.literal_eval(key_node)
        if key == "exec":
            application_paths.append((app_name, ast.literal_eval(value_node)))
        elif key == "exec_candidates":
            for candidate in ast.literal_eval(value_node):
                application_paths.append((app_name, candidate))

errors = []
for app_name, executable in application_paths:
    exact = [
        label
        for label, attachment in attachments
        if fnmatch.fnmatchcase(executable, attachment)
    ]
    transitions = [
        (access, target)
        for rule_path, access, target in managed_app_rules
        if fnmatch.fnmatchcase(executable, rule_path)
    ]
    invalid_targets = [
        target
        for _access, target in transitions
        if target is not None and target not in profile_labels
    ]
    if invalid_targets:
        errors.append(
            f"{app_name}: unresolved named transition for {executable}: "
            + ", ".join(invalid_targets)
        )
        continue
    if not exact and not transitions and executable not in managed_mode_probes:
        errors.append(f"{app_name}: unmanaged application executable: {executable}")

desktop_entries = []
for desktop_path in sorted((root / "d-i/forky/hooks").rglob("*.desktop*")):
    if (
        not desktop_path.is_file()
        or desktop_path.name.endswith(".desktop.in")
        or not desktop_path.name.endswith((".desktop", ".desktop.tmpl"))
    ):
        continue
    for line in desktop_path.read_text(encoding="utf-8").splitlines():
        if not line.startswith("Exec="):
            continue
        command = line[5:].split(None, 1)[0]
        if command == "__INSTALLER_LABWC_MANAGED_APP_DEFAULT_EXEC__":
            command = "/usr/local/bin/labwc-managed-app"
        desktop_entries.append((desktop_path.relative_to(root), command))

for desktop_path, executable in desktop_entries:
    matching = [
        label
        for label, attachment in attachments
        if fnmatch.fnmatchcase(executable, attachment)
    ]
    if len(matching) != 1:
        errors.append(
            f"{desktop_path}: desktop Exec has {len(matching)} exact attachments: "
            f"{executable}"
        )

if len(application_paths) != 26:
    errors.append(
        f"expected 26 managed application executable paths, found "
        f"{len(application_paths)}"
    )
if len(desktop_entries) != 16:
    errors.append(f"expected 16 managed desktop Exec entries, found {len(desktop_entries)}")
if errors:
    print("\n".join(errors), file=sys.stderr)
    raise SystemExit(1)
PY
then
  pass "managed applications and desktop Exec launchers resolve an attachment, named transition, or declared package profile"
else
  fail "managed applications and desktop Exec launchers resolve an attachment, named transition, or declared package profile"
fi

if python3 - "$ROOT_DIR" "$APPARMOR_DIR" "$PROFILE" <<'PY'
from pathlib import Path
import fnmatch
import re
import sys

root = Path(sys.argv[1])
apparmor_dir = Path(sys.argv[2])
wrapper_profile = Path(sys.argv[3])


def expand_braces(pattern: str) -> list[str]:
    start = pattern.find("{")
    if start < 0:
        return [pattern]
    depth = 0
    end = -1
    for index in range(start, len(pattern)):
        if pattern[index] == "{":
            depth += 1
        elif pattern[index] == "}":
            depth -= 1
            if depth == 0:
                end = index
                break
    if end < 0:
        raise SystemExit(f"unbalanced AppArmor braces: {pattern}")
    body = pattern[start + 1:end]
    choices = []
    choice_start = 0
    nested = 0
    for index, character in enumerate(body):
        if character == "{":
            nested += 1
        elif character == "}":
            nested -= 1
        elif character == "," and nested == 0:
            choices.append(body[choice_start:index])
            choice_start = index + 1
    choices.append(body[choice_start:])
    expanded = []
    for choice in choices:
        expanded.extend(
            expand_braces(pattern[:start] + choice + pattern[end + 1:])
        )
    return expanded


profile_text = "\n".join(
    profile_path.read_text(encoding="utf-8")
    for profile_path in sorted(apparmor_dir.iterdir())
    if profile_path.is_file()
)
profile_labels = set()
attachments = []
for line in profile_text.splitlines():
    match = re.match(
        r"^profile\s+(?P<label>\S+)(?:\s+(?P<attachment>/\S+))?"
        r"(?:\s+flags=.*)?\s+\{$",
        line,
    )
    if match is None:
        continue
    profile_labels.add(match.group("label"))
    if match.group("attachment") is not None:
        attachments.extend(
            (match.group("label"), attachment)
            for attachment in expand_braces(match.group("attachment"))
        )

exact_paths = [
    "/usr/local/bin/adb",
    "/usr/local/bin/fastboot",
    *(
        f"/usr/local/lib/android-sdk/platform-tools/{name}"
        for name in (
            "adb",
            "etc1tool",
            "fastboot",
            "hprof-conv",
            "make_f2fs",
            "make_f2fs_casefold",
            "mke2fs",
            "sqlite3",
        )
    ),
    "/usr/local/bin/samloader",
    "/usr/local/lib/samloader/samloader",
    "/usr/local/bin/pdfcpu",
    "/usr/local/lib/pdfcpu/pdfcpu",
    "/usr/local/bin/typst",
    "/usr/local/lib/typst/typst",
    "/usr/local/lib/digital-assets/bin/pdf2docx",
    "/usr/local/lib/digital-assets/pipx/venvs/pdf2docx/bin/pdf2docx",
    "/usr/local/lib/digital-assets/pipx/venvs/pdf2docx/bin/python",
    "/usr/local/bin/waypaper",
    "/opt/waypaper/bin/waypaper",
    "/opt/waypaper/pipx/venvs/waypaper/bin/waypaper",
    "/usr/local/libexec/satty/satty",
    "/usr/local/lib/bazelisk/bazel",
    "/usr/local/lib/rustup/bin/rustup-init",
    "/usr/local/libexec/aptly-publishing",
    "/usr/local/libexec/aptly-publishing-bin/aptly",
    "/usr/local/libexec/aptly-publishing-bin/aptly-publish-local",
    "/usr/local/libexec/aptly-publishing-bin/dpkg-buildpackage",
    "/usr/local/libexec/obs-publishing",
    "/usr/local/libexec/obs-publishing-bin/obs-checkout-source",
    "/usr/local/libexec/obs-publishing-bin/obs-publish-source",
    "/usr/local/libexec/obs-publishing-bin/osc",
    "/data/codex/share/bin/codex",
    "/data/codex/share/bin/future-helper",
    "/data/llama/lib/llama",
    "/data/llama/bin/llama-bench",
    "/data/llama/bin/llama-cli",
    "/data/llama/bin/llama-gguf-split",
    "/data/llama/bin/llama-quantize",
    "/data/llama/bin/llama-server",
]
for node_version in (22, 24, 26):
    exact_paths.extend(
        f"/usr/local/lib/node-{node_version}/bin/{name}"
        for name in ("node", "npm", "npx", "corepack", "pnpm", "yarn")
    )
exact_paths.extend(
    (
        "/pool/cache/desktop/cargo/bin/cargo",
        "/pool/db/desktop/rustup/toolchains/nightly-x86_64-unknown-linux-gnu/bin/rustc",
        "/pool/db/desktop/bazelisk/downloads/bazelbuild/bazel-9/bin/bazel",
        "/pool/db/desktop/mise/data/installs/node/22/bin/node",
        "/pool/build/desktop/cargo/install/bin/cargo-tool",
        "/pool/build/desktop/cargo/target/debug/project-binary",
        "/pool/build/desktop/npm-global/bin/npm-tool",
        "/pool/build/desktop/pnpm/bin/pnpm-tool",
        "/pool/build/desktop/yarn-global/bin/yarn-tool",
        "/usr/local/bin/whisper-cli",
        "/data/whisper/bin/whisper-cli",
        "/usr/local/bin/whisper-server",
        "/data/whisper/bin/whisper-server",
        "/opt/postman/app/Postman",
        "/opt/postman/app/postman",
        "/opt/ledger-live/AppRun",
        "/opt/tuta-mail/AppRun",
    )
)

errors = []
for executable in exact_paths:
    matching = [
        (label, attachment)
        for label, attachment in attachments
        if fnmatch.fnmatchcase(executable, attachment)
    ]
    if len(matching) != 1:
        errors.append(
            f"{executable}: expected one downloaded-tool attachment, got "
            + (
                ", ".join(f"{label}:{attachment}" for label, attachment in matching)
                if matching
                else "none"
            )
        )

expected_labels = {
    "managed-android-platform-tools",
    "managed-samloader",
    "managed-digital-assets-release-tools",
    "managed-digital-assets-python-runtime",
    "managed-codex-runtime",
    "managed-devops-publishing",
    "managed-devops-toolchain",
    "managed-satty-runtime",
    "whisper-cli",
    "whisper-server",
}
missing_labels = sorted(expected_labels - profile_labels)
if missing_labels:
    errors.append("missing downloaded-tool profiles: " + ", ".join(missing_labels))

wrapper_text = wrapper_profile.read_text(encoding="utf-8")
adb_self_network_rule = "  @{PROC}/@{pid}/net/{tcp,tcp6,udp,udp6} r,"
if adb_self_network_rule not in wrapper_text:
    errors.append(
        "missing self-PID-only ADB network namespace table access: "
        + adb_self_network_rule.strip()
    )
for forbidden_rule in (
    "owner @{PROC}/@{pid}/net/",
    "@{PROC}/[0-9]*/net/",
    "@{PROC}/**/net/",
):
    if forbidden_rule in wrapper_text:
        errors.append(
            "ADB procfs access is owner-qualified or broader than the current "
            f"process: {forbidden_rule}"
        )

required_rules = (
    "/{bin,usr/bin}/{adb,fastboot} rPx -> managed-android-platform-tools,",
    "/usr/local/bin/{adb,fastboot} rPx -> managed-android-platform-tools,",
    "/usr/local/lib/android-sdk/platform-tools/{adb,fastboot} rPx -> managed-android-platform-tools,",
    "/{bin,usr/bin}/samloader rPx -> managed-samloader,",
    "/usr/local/bin/samloader rPx -> managed-samloader,",
    "/usr/local/lib/samloader/samloader rPx -> managed-samloader,",
    "/usr/local/bin/{pdfcpu,typst} rPx -> managed-digital-assets-release-tools,",
    "/usr/local/lib/{pdfcpu/pdfcpu,typst/typst} rPx -> managed-digital-assets-release-tools,",
    "/opt/glibc/2.44-1/satty/{lib,lib64,usr/lib}/**/ld-linux-x86-64.so.2 rPx -> managed-satty-runtime,",
    "/usr/local/lib/digital-assets/pipx/venvs/pdf2docx/bin/python rix,",
    "/usr/local/bin/whisper-cli rix,",
    "/data/whisper/bin/whisper-cli rix,",
    "/usr/local/bin/whisper-server rix,",
    "/data/whisper/bin/whisper-server rix,",
    "/data/codex/share/bin/codex rPx -> managed-codex-runtime,",
    "/data/codex/share/bin/* mrix,",
    "deny /data/codex/config.schema.json wkl,",
    "/data/llama/lib/llama rix,",
    "/data/llama/bin/{llama-bench,llama-cli,llama-gguf-split,llama-quantize,llama-server} mrix,",
)
for required_rule in required_rules:
    if f"  {required_rule}" not in wrapper_text:
        errors.append(f"missing strict downloaded-tool execution rule: {required_rule}")

for forbidden_rule in (
    "/usr/local/bin/{adb,fastboot,samloader} pux,",
    "/usr/local/lib/android-sdk/platform-tools/{adb,fastboot} pux,",
    "/usr/local/lib/samloader/samloader pux,",
    "/usr/local/bin/{pdfcpu,typst} pix,",
    "/opt/glibc/2.44-1/satty/{lib,lib64,usr/lib}/**/ld-linux-x86-64.so.2 pux,",
):
    if forbidden_rule in wrapper_text:
        errors.append(f"downloaded-tool fallback execution remains: {forbidden_rule}")

source_fragments = {
    "d-i/forky/scripts/desktop/android-platform-tools.sh": (
        "make_f2fs_casefold",
        "ln -sfn ../lib/android-sdk/platform-tools/adb /target/usr/local/bin/adb",
        "ln -sfn ../lib/android-sdk/platform-tools/fastboot /target/usr/local/bin/fastboot",
    ),
    "d-i/forky/scripts/desktop/samloader.sh": (
        "install -m 0755 \"$samloader_binary_host\" \"${samloader_staged_host}/samloader\"",
        "ln -sfn ../lib/samloader/samloader /target/usr/local/bin/samloader",
    ),
    "d-i/forky/scripts/desktop/digital-assets.sh": (
        "pdfcpu \\",
        "typst \\",
        "digital_assets_python=\"${digital_assets_pipx_home}/venvs/pdf2docx/bin/python\"",
    ),
    "d-i/forky/scripts/desktop/satty.sh": (
        "install -m 0755 \"$satty_extract_host/satty\" /target/usr/local/libexec/satty/satty",
    ),
    "d-i/forky/scripts/late/devops.sh": (
        "[ \"$install_dir\" = /usr/local/lib/bazelisk ]",
        "[ \"$install_dir\" = /usr/local/lib/rustup ]",
        "[ \"$install_dir\" = \"/usr/local/lib/node-${major_version}\" ]",
        "aptly_publishing_program=/usr/local/libexec/aptly-publishing",
        "obs_publishing_program=/usr/local/libexec/obs-publishing",
    ),
    "d-i/forky/scripts/late/llama.sh": (
        "--required-binary llama-bench",
        "mv -- \"$extract_dir/bin\" \"$LLAMA_BINARY_DIR\"",
        "target/data/llama/lib/llama",
    ),
    "d-i/forky/hooks/role/desktop/target/data/llama/lib/llama": (
        "llama_exec llama-cli",
        "llama_exec llama-server",
    ),
    "d-i/forky/scripts/late/whisper.sh": (
        "for binary_name in whisper-cli whisper-server; do",
        "--required-binary whisper-cli",
        "ln -sfn \"${WHISPER_BINARY_DIR}/whisper-server\" \"$stable_server\"",
    ),
    "d-i/forky/scripts/late/software.sh": (
        "postman_install_dir=/opt/postman",
        "ledger_install_dir=/opt/ledger-live",
        "tuta_install_dir=/opt/tuta-mail",
    ),
}
for relative_path, fragments in source_fragments.items():
    source_text = (root / relative_path).read_text(encoding="utf-8")
    for fragment in fragments:
        if fragment not in source_text:
            errors.append(f"{relative_path}: missing managed executable contract: {fragment}")

if errors:
    print("\n".join(errors), file=sys.stderr)
    raise SystemExit(1)
PY
then
  pass "downloaded release and retained development executable paths have exact or explicitly inherited managed domains"
else
  fail "downloaded release and retained development executable paths have exact or explicitly inherited managed domains"
fi

if python3 - "$ROOT_DIR" "$APPARMOR_DIR" <<'PY'
from pathlib import Path
from xml.etree import ElementTree
import fnmatch
import re
import shlex
import sys

root = Path(sys.argv[1])
apparmor_dir = Path(sys.argv[2])


def expand_braces(pattern: str) -> list[str]:
    start = pattern.find("{")
    if start < 0:
        return [pattern]
    depth = 0
    end = -1
    for index in range(start, len(pattern)):
        if pattern[index] == "{":
            depth += 1
        elif pattern[index] == "}":
            depth -= 1
            if depth == 0:
                end = index
                break
    if end < 0:
        raise SystemExit(f"unbalanced AppArmor braces: {pattern}")
    body = pattern[start + 1:end]
    choices = []
    choice_start = 0
    nested = 0
    for index, character in enumerate(body):
        if character == "{":
            nested += 1
        elif character == "}":
            nested -= 1
        elif character == "," and nested == 0:
            choices.append(body[choice_start:index])
            choice_start = index + 1
    choices.append(body[choice_start:])
    expanded = []
    for choice in choices:
        expanded.extend(
            expand_braces(pattern[:start] + choice + pattern[end + 1:])
        )
    return expanded


attachments = []
for profile_path in sorted(apparmor_dir.iterdir()):
    if not profile_path.is_file():
        continue
    for line in profile_path.read_text(encoding="utf-8").splitlines():
        match = re.match(
            r"^profile\s+(?P<label>\S+)(?:\s+(?P<attachment>/\S+))?"
            r"(?:\s+flags=.*)?\s+\{$",
            line,
        )
        if match is None or match.group("attachment") is None:
            continue
        attachments.extend(
            (match.group("label"), attachment)
            for attachment in expand_braces(match.group("attachment"))
        )

labwc_root = (
    root / "d-i/forky/hooks/role/desktop/target/etc/skel/.config/labwc"
)
commands = []
for xml_path in (
    labwc_root / "menu.xml",
    labwc_root / "rc.xml.tmpl",
):
    document = ElementTree.parse(xml_path)
    for element in document.iter():
        attribute_command = element.attrib.get("command")
        if attribute_command is not None:
            commands.append((xml_path.relative_to(root), attribute_command.strip()))
        if element.tag.rsplit("}", 1)[-1] == "command" and element.text:
            commands.append((xml_path.relative_to(root), element.text.strip()))

package_commands = {
    "featherpad",
    "focuswriter",
    "gnote",
    "gnumeric",
    "kdiff3",
    "labwc-tweaks",
    "liferea",
    "nwg-look",
    "pavucontrol",
    "qalculate-qt",
    "qimgv",
    "qt6ct",
    "retroarch",
    "spotify",
    "systemctl",
    "thunar",
    "wdisplays",
    "wpctl",
    "xarchiver",
    "xournalpp",
    "zathura",
}
placeholder = "__INSTALLER_LABWC_AUDIO_CONTROL_COMMAND__"
errors = []
for xml_path, command in commands:
    if command == placeholder:
        continue
    argv = shlex.split(command)
    if not argv:
        errors.append(f"{xml_path}: empty Labwc command")
        continue
    executable = argv[0]
    basename = Path(executable).name
    if basename in package_commands:
        continue
    candidate_paths = (
        (executable,)
        if executable.startswith("/")
        else (f"/usr/local/bin/{executable}",)
    )
    matching = {
        (label, attachment)
        for candidate_path in candidate_paths
        for label, attachment in attachments
        if fnmatch.fnmatchcase(candidate_path, attachment)
    }
    if len(matching) != 1:
        errors.append(
            f"{xml_path}: Labwc command has {len(matching)} managed attachments: "
            f"{command}"
        )

command_values = [command for _path, command in commands]
if any(command.startswith("sh -c ") for command in command_values):
    errors.append("Labwc screenshot bindings must not bypass managed wrappers through sh -c")
for required_command in (
    "labwc-capture screenshot-full",
    "labwc-capture screenshot-box",
):
    if required_command not in command_values:
        errors.append(f"Labwc command is missing: {required_command}")

components_text = (
    root / "d-i/forky/scripts/desktop/components.sh"
).read_text(encoding="utf-8")
if (
    'LABWC_AUDIO_CONTROL_COMMAND "$(desktop_xml_attribute_escape '
    '"${LABWC_AUDIO_CONTROL_COMMAND:-pavucontrol}")"'
    not in components_text
):
    errors.append("Labwc audio command placeholder lacks a bounded renderer")

profile_values = set()
profile_count = 0
for profile_path in sorted((root / "d-i/forky/hosts/profiles").rglob("*.env")):
    profile_text = profile_path.read_text(encoding="utf-8")
    match = re.search(
        r'^LABWC_AUDIO_CONTROL_COMMAND="([^"]+)"$',
        profile_text,
        re.MULTILINE,
    )
    if match is not None:
        profile_count += 1
        profile_values.add(match.group(1))
if profile_count != 13 or profile_values != {"pavucontrol"}:
    errors.append(
        "Labwc audio placeholder must resolve to pavucontrol in all 13 desktop profiles"
    )

if len(commands) != 77:
    errors.append(f"expected 77 Labwc command entries, found {len(commands)}")
if len(set(command_values)) != 48:
    errors.append(
        f"expected 48 distinct Labwc command entries, found "
        f"{len(set(command_values))}"
    )
if errors:
    print("\n".join(errors), file=sys.stderr)
    raise SystemExit(1)
PY
then
  pass "every Labwc XML command resolves a managed wrapper or declared package launch contract"
else
  fail "every Labwc XML command resolves a managed wrapper or declared package launch contract"
fi

if python3 - "$ROOT_DIR" "$APPARMOR_DIR" <<'PY'
from pathlib import Path
import fnmatch
import re
import sys

root = Path(sys.argv[1])
apparmor_dir = Path(sys.argv[2])


def expand_braces(pattern: str) -> list[str]:
    start = pattern.find("{")
    if start < 0:
        return [pattern]
    depth = 0
    end = -1
    for index in range(start, len(pattern)):
        if pattern[index] == "{":
            depth += 1
        elif pattern[index] == "}":
            depth -= 1
            if depth == 0:
                end = index
                break
    if end < 0:
        raise SystemExit(f"unbalanced AppArmor braces: {pattern}")
    body = pattern[start + 1:end]
    choices = []
    choice_start = 0
    nested = 0
    for index, character in enumerate(body):
        if character == "{":
            nested += 1
        elif character == "}":
            nested -= 1
        elif character == "," and nested == 0:
            choices.append(body[choice_start:index])
            choice_start = index + 1
    choices.append(body[choice_start:])
    expanded = []
    for choice in choices:
        expanded.extend(
            expand_braces(pattern[:start] + choice + pattern[end + 1:])
        )
    return expanded


attachments = []
for profile_path in sorted(apparmor_dir.iterdir()):
    if not profile_path.is_file():
        continue
    for line in profile_path.read_text(encoding="utf-8").splitlines():
        match = re.match(
            r"^profile\s+(?P<label>\S+)\s+(?P<attachment>/\S+)"
            r"(?:\s+flags=.*)?\s+\{$",
            line,
        )
        if match is None:
            continue
        attachments.extend(
            (match.group("label"), attachment)
            for attachment in expand_braces(match.group("attachment"))
        )

placeholder_paths = {
    "__INSTALLER_FILE_BOOTPROFILE_APPLY__":
        "/usr/libexec/install-tools/bootprofile-apply",
    "__INSTALLER_FILE_SWAP_FALLBACK_HELPER__":
        "/usr/local/libexec/swap-fallback-setup",
    "__INSTALLER_FILE_TMPFS_PRE_CLEAN__":
        "/usr/local/libexec/tmpfs-pre-clean",
    "__INSTALLER_FILE_ZRAM_SETUP_HELPER__":
        "/usr/local/libexec/zram-device-setup",
    "__INSTALLER_FILE_ZRAM_WRITEBACK_HELPER__":
        "/usr/local/libexec/zram-writeback",
}
managed_prefixes = (
    "/usr/local/bin/",
    "/usr/local/sbin/",
    "/usr/local/libexec/",
    "/usr/libexec/install-tools/",
    "/etc/kernel/",
    "/etc/initramfs-tools/",
    "/etc/timeshift/",
    "/pool/",
)
directive_pattern = re.compile(
    r"^(ExecStart|ExecStartPre|ExecStartPost|ExecStop|ExecStopPost|ExecReload)="
)
absolute_path_pattern = re.compile(
    r"(?<![A-Za-z0-9_])"
    r"(/[A-Za-z0-9_.+@%{}*,:=-]+(?:/[A-Za-z0-9_.+@%{}*,:=-]+)*)"
)
interpreter_bypass_pattern = re.compile(
    r"/(?:usr/)?bin/(?:ba|da)?sh(?:\s+-[^\s]+)*\s+"
    r"/(?:usr/local|usr/libexec/install-tools|etc/(?:kernel|initramfs-tools|timeshift)|pool)/"
)

directive_count = 0
managed_paths = set()
errors = []
for unit_path in sorted((root / "d-i/forky/hooks").rglob("*")):
    if not unit_path.is_file():
        continue
    try:
        unit_text = unit_path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        continue
    for line_number, line in enumerate(unit_text.splitlines(), 1):
        if directive_pattern.match(line) is None or line.endswith("="):
            continue
        directive_count += 1
        raw_command = line.split("=", 1)[1]
        if interpreter_bypass_pattern.search(raw_command):
            errors.append(
                f"{unit_path.relative_to(root)}:{line_number}: "
                "interpreter invocation bypasses repository script attachment"
            )
        for placeholder, installed_path in placeholder_paths.items():
            if placeholder in raw_command:
                managed_paths.add(installed_path)
        for installed_path in absolute_path_pattern.findall(raw_command):
            installed_path = installed_path.rstrip("'\"")
            if installed_path.startswith(managed_prefixes):
                managed_paths.add(installed_path)

for installed_path in sorted(managed_paths):
    matching = [
        (label, attachment)
        for label, attachment in attachments
        if fnmatch.fnmatchcase(installed_path, attachment)
    ]
    if len(matching) != 1:
        errors.append(
            f"systemd executable {installed_path}: expected one attachment, got "
            + (
                ", ".join(f"{label}:{attachment}" for label, attachment in matching)
                if matching else "none"
            )
        )

if directive_count != 87:
    errors.append(f"expected 87 systemd execution directives, found {directive_count}")
if len(managed_paths) != 39:
    errors.append(
        f"expected 39 repository-managed systemd executable paths, found "
        f"{len(managed_paths)}"
    )
if errors:
    print("\n".join(errors), file=sys.stderr)
    raise SystemExit(1)
PY
then
  pass "every repository-managed systemd executable enters an exact attachment without interpreter bypass"
else
  fail "every repository-managed systemd executable enters an exact attachment without interpreter bypass"
fi

profile_count=$(
  cat "$PROFILE" "$SYSTEM_PROFILE" |
    grep -c '^profile managed-'
)
local_include_count=$(
  cat "$PROFILE" "$SYSTEM_PROFILE" |
    grep -Ec '^  include if exists <local/(data[.]codex[.]|usr[.]bin[.](slirp4netns-(codex|chatgpt|wayland-compat)|curl[.]ai-copilots-model-download)|usr[.]local[.]|usr[.]libexec[.]|usr[.]sbin[.]|opt[.]xwayland[.]bin[.]bwrap|pool[.]|home[.]labwc[.]|etc[.]initramfs-tools[.]|managed-secure-boot-kernel-hooks)'
)
labels_unique=true
awk '
  /^profile managed-/ { seen[$2]++ }
  END {
    for (name in seen) {
      if (seen[name] != 1) {
        exit 1
      }
    }
  }
  ' "$PROFILE" "$SYSTEM_PROFILE" || labels_unique=false
if [ "$profile_count" -gt 0 ] &&
   [ "$local_include_count" -eq "$profile_count" ] &&
   [ "$labels_unique" = true ]; then
  pass "desktop and system wrapper profile labels and local override hooks are unique"
else
  fail "desktop and system wrapper profile labels and local override hooks are unique"
fi

requested_profiles='
managed-labwc-autostart-hook
managed-labwc-shutdown-hook
managed-waypaper
managed-android-platform-tools
managed-samloader
managed-labwc-autostart
managed-labwc-fuzzel
managed-labwc-greeter-output
managed-labwc-greeter-client
managed-labwc-greeter-session
managed-labwc-kanshi
managed-labwc-lock
managed-labwc-ocr
managed-labwc-plans
managed-telbot
managed-labwc-output-watch
managed-labwc-run
managed-labwc-session
managed-labwc-swaybg
managed-labwc-swayidle
managed-satty
managed-xssh-retrieve
managed-xssh-send
managed-labwc-adb-menu
managed-labwc-capture
managed-labwc-display-configuration
managed-labwc-digital-assets
managed-labwc-digital-assets-action
managed-labwc-ai-copilots
managed-labwc-ai-copilots-action
managed-labwc-ai-model-install-root
managed-labwc-ai-model-info
managed-labwc-ai-llama-server
managed-digital-assets-release-tools
managed-digital-assets-python-runtime
managed-codex-wrapper
managed-codex-runtime
managed-devops-toolchain
managed-labwc-logout
managed-labwc-show-desktop
managed-labwc-security-action
managed-labwc-security-action-root
managed-labwc-firewall-action
managed-labwc-firewall-menu
managed-labwc-firewall-action-root
managed-apparmor-managed-modes
managed-apparmor-rule-generator
managed-bluetooth-controller-init
managed-greetd-power-action
managed-labwc-notify
managed-satty-runtime
managed-managed-clamav-signature-update
managed-managed-discord-distro
managed-managed-external-software-update
managed-incus-host-managed
managed-tpm2-enroll-launch
managed-tpm2-enroll
'
requested_ok=true
for requested_profile in $requested_profiles; do
  grep -q "^profile ${requested_profile} " "$PROFILE" || requested_ok=false
done
if [ "$requested_ok" = true ]; then
  pass "every explicitly requested wrapper has a dedicated profile"
else
  fail "every explicitly requested wrapper has a dedicated profile"
fi

ai_launcher_profile=$(profile_block managed-labwc-ai-copilots)
ai_action_profile=$(profile_block managed-labwc-ai-copilots-action)
ai_root_profile=$(profile_block managed-labwc-ai-model-install-root)
ai_download_profile=$(profile_block managed-ai-copilots-model-download)
ai_info_profile=$(profile_block managed-labwc-ai-model-info)
ai_server_profile=$(profile_block managed-labwc-ai-llama-server)
forbidden_ai_home_model_pattern='\.local/share/labwc-ai-copilots/'\
'(llama|whisper)/models'
if printf '%s\n' "$ai_launcher_profile" |
     grep -Fqx '  /dev/tty rw,' &&
   printf '%s\n' "$ai_launcher_profile" |
     grep -Fqx '  /usr/bin/{find,fzf,id,sed,sort} rix,' &&
   printf '%s\n' "$ai_launcher_profile" |
     grep -Fqx '  owner @{PROC}/@{pid}/mountinfo r,' &&
   printf '%s\n' "$ai_launcher_profile" |
     grep -Fqx '  owner @{HOME}/.config/fzf/default-opts r,' &&
   ! printf '%s\n' "$ai_launcher_profile" |
     grep -Fq '@{PROC}/[0-9]*/mountinfo' &&
   ! printf '%s\n' "$ai_launcher_profile" |
     grep -Fq '@{HOME}/.config/fzf/**' &&
   printf '%s\n' "$ai_launcher_profile" |
     grep -Fqx '  /usr/local/bin/labwc-terminal rPx -> managed-labwc-terminal,' &&
   printf '%s\n' "$ai_action_profile" |
     grep -Fqx '  /pool/cache/llama/models/*.gguf r,' &&
   printf '%s\n' "$ai_action_profile" |
     grep -Fqx '  /pool/cache/whisper/models/*.bin r,' &&
   ! printf '%s\n' "$ai_action_profile" |
     grep -Eq '^  /pool/cache/.*[[:space:]][^,]*w[^,]*,$' &&
   ! printf '%s\n' "$ai_action_profile" |
     grep -Eq '^  network([[:space:]]|,)' &&
   printf '%s\n' "$ai_root_profile" |
     grep -Fqx '  capability chown,' &&
   printf '%s\n' "$ai_root_profile" |
     grep -Fqx '  /pool/cache/llama/models/*.gguf rwk,' &&
   printf '%s\n' "$ai_root_profile" |
     grep -Fqx '  /pool/cache/llama/models/.*.gguf.lock rwk,' &&
   printf '%s\n' "$ai_root_profile" |
     grep -Fqx '  /pool/cache/llama/models/.*.gguf.partial.* rwk,' &&
   printf '%s\n' "$ai_root_profile" |
     grep -Fqx '  /pool/cache/whisper/models/*.bin rwk,' &&
   printf '%s\n' "$ai_root_profile" |
     grep -Fqx '  /pool/cache/whisper/models/.*.bin.lock rwk,' &&
   printf '%s\n' "$ai_root_profile" |
     grep -Fqx '  /pool/cache/whisper/models/.*.bin.partial.* rwk,' &&
   ! printf '%s\n' "$ai_root_profile" |
     grep -Eq '^  network([[:space:]]|,)' &&
   printf '%s\n' "$ai_download_profile" |
     grep -Fqx '  network inet stream,' &&
   printf '%s\n' "$ai_download_profile" |
     grep -Fqx '  network inet6 stream,' &&
   printf '%s\n' "$ai_download_profile" |
     grep -Fqx '  /pool/cache/llama/models/.*.gguf.partial.* rw,' &&
   printf '%s\n' "$ai_download_profile" |
     grep -Fqx '  /pool/cache/whisper/models/.*.bin.partial.* rw,' &&
   ! printf '%s\n' "$ai_download_profile" |
     grep -Eq '^  /pool/cache/(llama/models/[*][.]gguf|whisper/models/[*][.]bin)[[:space:]]' &&
   ! printf '%s\n' "$ai_info_profile" |
     grep -Eq '^  /pool/cache/.*[[:space:]][^,]*w[^,]*,$' &&
   printf '%s\n' "$ai_server_profile" |
     grep -Fqx '  #include <abstractions/managed-wrapper-perl>' &&
   printf '%s\n' "$ai_server_profile" |
     grep -Fqx '  #include <abstractions/managed-desktop-graphics>' &&
   printf '%s\n' "$ai_server_profile" |
     grep -Fqx '  network unix stream,' &&
   printf '%s\n' "$ai_server_profile" |
     grep -Fqx '  network inet stream,' &&
   ! printf '%s\n' "$ai_server_profile" |
     grep -Fqx '  network inet6 stream,' &&
   printf '%s\n' "$ai_server_profile" |
     grep -Fqx '  /usr/local/libexec/labwc-ai-llama-server rix,' &&
   printf '%s\n' "$ai_server_profile" |
     grep -Fqx '  /data/llama/lib/llama rix,' &&
   printf '%s\n' "$ai_server_profile" |
     grep -Fqx '  /data/llama/bin/llama-server mrix,' &&
   printf '%s\n' "$ai_server_profile" |
     grep -Fqx '  /pool/cache/llama/models/*.gguf mr,' &&
   ! printf '%s\n' "$ai_server_profile" |
     grep -Eq '^  /pool/cache/.*[[:space:]][^,]*w[^,]*,$' &&
   ! printf '%s\n' "$ai_server_profile" |
     grep -Eq '/opt/xwayland|/usr/bin/Xwayland|owner @\{HOME\}/\*\*' &&
   ! grep -Eq "$forbidden_ai_home_model_pattern" "$PROFILE"; then
  pass "AI model access is read-only for the desktop user and writable only through the fixed privileged transport"
else
  fail "AI model access is read-only for the desktop user and writable only through the fixed privileged transport"
fi
unset \
  ai_launcher_profile \
  ai_action_profile \
  ai_root_profile \
  ai_download_profile \
  ai_info_profile \
  ai_server_profile \
  forbidden_ai_home_model_pattern

if grep -qx '#include <abstractions/base>' "$ABSTRACTION_DIR/managed-wrapper-base" &&
   grep -qx '#include <abstractions/managed-wrapper-base>' "$ABSTRACTION_DIR/managed-wrapper-desktop" &&
   [ ! -e "$ABSTRACTION_DIR/managed-wrapper-process-control" ] &&
   grep -qx '#include <abstractions/managed-wrapper-desktop>' "$ABSTRACTION_DIR/managed-wrapper-wayland" &&
   grep -qx '#include <abstractions/managed-wrapper-wayland>' "$ABSTRACTION_DIR/managed-wrapper-gui" &&
   grep -qx '#include <abstractions/managed-desktop-graphics>' "$ABSTRACTION_DIR/managed-wrapper-gui" &&
   grep -qx '#include <abstractions/managed-wrapper-base>' "$ABSTRACTION_DIR/managed-wrapper-python" &&
   grep -Fqx '/etc/{group,nsswitch.conf,passwd} r,' "$ABSTRACTION_DIR/managed-wrapper-base" &&
   grep -Fqx '@{PROC}/[0-9]*/cgroup r,' "$ABSTRACTION_DIR/managed-wrapper-base" &&
   grep -Fqx '@{sys}/fs/cgroup/**/cpu.max r,' "$ABSTRACTION_DIR/managed-wrapper-base" &&
   grep -qx '/usr/bin/python3 rix,' "$ABSTRACTION_DIR/managed-wrapper-python" &&
   grep -Fqx '/usr/bin/python3.[0-9]* rix,' "$ABSTRACTION_DIR/managed-wrapper-python" &&
   grep -qx 'deny owner @{HOME}/.local/lib/python[*]/[*][*] mrwkl,' "$ABSTRACTION_DIR/managed-wrapper-python" &&
   grep -Fqx 'deny /root/ r,' "$ABSTRACTION_DIR/managed-wrapper-python" &&
   ! grep -Eq '<abstractions/(dbus-session|dconf|fonts|freedesktop[.]org|gtk|xdg-desktop)>' \
     "$ABSTRACTION_DIR/managed-wrapper-desktop" \
     "$ABSTRACTION_DIR/managed-wrapper-gui" \
     "$ABSTRACTION_DIR/managed-wrapper-wayland" &&
   ! grep -Eq '^[[:space:]]*(network([[:space:]]|,)|(owner[[:space:]]+)?@\{HOME\}|(owner[[:space:]]+)?/home/)' \
     "$ABSTRACTION_DIR/managed-wrapper-base" \
     "$ABSTRACTION_DIR/managed-wrapper-desktop" &&
   ! grep -Eq 'labwc-(autostart|session)[.]lock' \
     "$ABSTRACTION_DIR/managed-wrapper-desktop"; then
  pass "base wrappers add no network or home access while GUI wrappers opt into shared graphics"
else
  fail "base wrappers add no network or home access while GUI wrappers opt into shared graphics"
fi

fuzzel_profile=$(profile_block managed-labwc-fuzzel)
if printf '%s\n' "$fuzzel_profile" |
     grep -Fqx '  /usr/bin/{awk,cat,flock,gawk,mawk,mktemp,nawk,rm,rmdir,sed} rix,' &&
   printf '%s\n' "$fuzzel_profile" |
     grep -Fqx '  signal (send) peer=unconfined,' &&
   printf '%s\n' "$fuzzel_profile" |
     grep -Fqx '  owner /run/user/[0-9]*/labwc-fuzzel.{lock,pid} rwk,' &&
   ! printf '%s\n' "$fuzzel_profile" |
     grep -Eq '@\{PROC\}|ptrace|managed-wrapper-process-control|/usr/bin/.*(pgrep|pkill|ps)' &&
   grep -Fxq 'MENU_FAILURE_STATUS=2' "$FUZZEL_WRAPPER" &&
   grep -Fq 'if ! /usr/bin/flock -w 5 8; then' "$FUZZEL_WRAPPER" &&
   grep -Fq "fatal 'unable to acquire the Fuzzel launcher lock within five seconds'" "$FUZZEL_WRAPPER" &&
   ! grep -Fq '/usr/bin/flock -w 5 8 || exit 0' "$FUZZEL_WRAPPER" &&
   grep -Fq 'pid_path="${runtime_root%/}/labwc-fuzzel.pid"' "$FUZZEL_WRAPPER" &&
   grep -q '^run_fuzzel() {$' "$FUZZEL_WRAPPER" &&
   grep -Fq 'fuzzel "$@" <&7 >&1 2>&2 8>&- &' "$FUZZEL_WRAPPER" &&
   ! grep -Fq 'id -u' "$FUZZEL_WRAPPER" &&
   ! grep -Eq '(^|[^[:alnum:]_])(pgrep|pkill|pidof)([^[:alnum:]_]|$)' "$FUZZEL_WRAPPER" &&
   ! grep -Eq '(start_background|flock|labwc-[a-z-]+[.]lock)' "$AUTOSTART_WRAPPER" &&
   ! printf '%s\n' "$fuzzel_profile" |
     grep -Fq 'managed-wrapper-process-control' &&
   ! grep -Eq '(^|[^[:alnum:]_])(pgrep|pkill|pidof)([^[:alnum:]_]|$)' "$AUTOSTART_WRAPPER"
then
  pass "managed Fuzzel keeps its owned runtime lock while autostart delegates persistent components without procfs discovery"
else
  fail "managed Fuzzel keeps its owned runtime lock while autostart delegates persistent components without procfs discovery"
fi
unset fuzzel_profile

display_configuration_profile=$(profile_block managed-labwc-display-configuration)
computer_management_profile=$(profile_block managed-labwc-computer-management)
if printf '%s\n' "$display_configuration_profile" |
     grep -Fqx '  #include <abstractions/managed-wrapper-wayland>' &&
   printf '%s\n' "$display_configuration_profile" |
     grep -Fqx '  /usr/local/bin/labwc-display-configuration rix,' &&
   printf '%s\n' "$display_configuration_profile" |
     grep -Fqx '  /usr/bin/wdisplays pux,' &&
   printf '%s\n' "$computer_management_profile" |
     grep -Fqx '  /usr/local/bin/labwc-display-configuration rPx,' &&
   ! printf '%s\n' "$computer_management_profile" |
     grep -Fq '/usr/bin/{pavucontrol,wdisplays} pux,' &&
   grep -Fxq 'GDK_BACKEND=wayland' "$DISPLAY_CONFIGURATION_WRAPPER" &&
   grep -Fxq 'GTK_CSD=0' "$DISPLAY_CONFIGURATION_WRAPPER" &&
   grep -Fxq 'exec /usr/bin/wdisplays "$@"' "$DISPLAY_CONFIGURATION_WRAPPER" &&
   ! grep -Fq 'run_command wdisplays' "$COMPUTER_MANAGEMENT_WRAPPER" &&
   /bin/sh -n "$DISPLAY_CONFIGURATION_WRAPPER"; then
  pass "Display Configuration enters a dedicated Wayland wrapper without a duplicate direct wdisplays launcher"
else
  fail "Display Configuration enters a dedicated Wayland wrapper without a duplicate direct wdisplays launcher"
fi
unset display_configuration_profile computer_management_profile

bluetooth_profile=$(profile_block managed-labwc-bluetooth)
brightness_profile=$(profile_block managed-labwc-brightness-control)
capture_profile=$(profile_block managed-labwc-capture)
fuzzel_profile=$(profile_block managed-labwc-fuzzel)
session_profile=$(profile_block managed-labwc-session)
output_watch_profile=$(profile_block managed-labwc-output-watch)
output_refresh_profile=$(profile_block managed-labwc-output-refresh)
if grep -Fq '[ "${LABWC_SESSION_OWNER:-}" = desktop ]' "$BLUETOOTH_WRAPPER" &&
   grep -Fq 'runtime_uid=${runtime_root#/run/user/}' "$BLUETOOTH_WRAPPER" &&
   grep -Fq "''|0*|*[!0-9]*)" "$BLUETOOTH_WRAPPER" &&
   ! grep -Fq 'id -u' "$BLUETOOTH_WRAPPER" &&
   ! printf '%s\n' "$bluetooth_profile" |
     grep -Eq '/usr/bin/(\{[^}]*,)?id([,}]|[[:space:]])' &&
   grep -Fq '[ "${LABWC_SESSION_OWNER:-}" = desktop ]' "$BRIGHTNESS_WRAPPER" &&
   grep -Fq 'runtime_uid=${runtime_root#/run/user/}' "$BRIGHTNESS_WRAPPER" &&
   ! grep -Fq 'id -u' "$BRIGHTNESS_WRAPPER" &&
   ! printf '%s\n' "$brightness_profile" |
     grep -Eq '/usr/bin/(\{[^}]*,)?id([,}]|[[:space:]])' &&
   grep -Fq '[ "${LABWC_SESSION_OWNER:-}" = desktop ]' "$CAPTURE_WRAPPER" &&
   grep -Fq 'desktop_uid=${runtime_root#/run/user/}' "$CAPTURE_WRAPPER" &&
   ! grep -Fq 'id -u' "$CAPTURE_WRAPPER" &&
   grep -Fq '[ "${1:-status}" = status ]' "$CAPTURE_WRAPPER" &&
   ! printf '%s\n' "$capture_profile" |
     grep -Eq '/usr/bin/(\{[^}]*,)?id([,}]|[[:space:]])' &&
   grep -Fq 'fuzzel "$@" <&7 >&1 2>&2 8>&- &' "$FUZZEL_WRAPPER" &&
   ! printf '%s\n' "$fuzzel_profile" |
     grep -Eq '/usr/bin/(\{[^}]*,)?id([,}]|[[:space:]])' &&
   grep -Fq 'expected_runtime_dir="/run/user/${current_uid}"' "$SESSION_WRAPPER" &&
    grep -Fq 'exec 9>"$lock_path"' "$SESSION_WRAPPER" &&
    grep -Fq '/usr/bin/flock --nonblock 9 || exit 0' "$SESSION_WRAPPER" &&
    grep -Fq '"$systemctl_cmd" --user --wait start labwc-compositor.service 9>&- || labwc_status=$?' "$SESSION_WRAPPER" &&
    ! grep -Fq '/usr/bin/labwc 9>&-' "$SESSION_WRAPPER" &&
    ! grep -Fq 'trap cleanup_labwc_session EXIT' "$SESSION_WRAPPER" &&
    ! grep -Fq '"$systemctl_cmd" --user stop labwc-session.target' "$SESSION_WRAPPER" &&
    ! grep -Fq '/usr/bin/true' "$SESSION_WRAPPER" &&
    ! printf '%s\n' "$session_profile" |
      grep -Fq '/usr/bin/true' &&
    ! printf '%s\n' "$session_profile" |
      grep -Fq '/usr/bin/labwc' &&
    printf '%s\n' "$session_profile" |
      grep -Fqx '  /usr/bin/{loginctl,systemctl,timeout} pux,' &&
    printf '%s\n' "$session_profile" |
      grep -Fqx '  /usr/bin/{flock,id,jq,sleep,stat} rix,' &&
    printf '%s\n' "$session_profile" |
      grep -Fqx '  @{PROC}/uptime r,' &&
    ! printf '%s\n' "$session_profile" |
      grep -Fq 'dbus-update-activation-environment' &&
    grep -Fq 'current_uid=$(/usr/bin/id -u)' "$SESSION_WRAPPER" &&
    printf '%s\n' "$session_profile" |
      grep -Eq '/usr/bin/(\{[^}]*,)?id([,}]|[[:space:]])' &&
   ! grep -Eq '(start_background|flock|labwc-[a-z-]+[.]lock)' "$AUTOSTART_WRAPPER" &&
   grep -Fq 'sleep 0.15 9>&-' "$KEYBOARD_WRAPPER" &&
   grep -Fq 'labwc --reconfigure 9>&- >/dev/null 2>&1 || true' "$KEYBOARD_WRAPPER" &&
   grep -Fq 'swaylock -f -c "$config_path" --image "$lock_background_path" --scaling fill "$@" 9>&-' "$LOCK_WRAPPER" &&
   ! printf '%s\n' "$output_watch_profile" |
     grep -Fq 'labwc-output-watch.lock' &&
   ! printf '%s\n' "$output_refresh_profile" |
     grep -Fq 'labwc-kanshi.lock'; then
  pass "status wrappers and singleton locks retain bounded user-manager session cleanup without null profiles or inherited descriptors"
else
  fail "status wrappers and singleton locks retain bounded user-manager session cleanup without null profiles or inherited descriptors"
fi
unset bluetooth_profile brightness_profile capture_profile fuzzel_profile session_profile output_watch_profile output_refresh_profile

network_profile_policy_ok=true
python3 - "$PROFILE" <<'PY' || network_profile_policy_ok=false
from pathlib import Path
import re
import sys

profile_path = Path(sys.argv[1])
allowed_network_profiles = {
    "managed-waypaper",
    "managed-android-platform-tools",
    "managed-samloader",
    "managed-labwc-plans",
    "managed-telpoll",
    "managed-telbot",
    "managed-digital-assets-release-tools",
    "managed-devops-toolchain",
    "managed-bluetooth-controller-init",
    "managed-codex-slirp4netns",
    "managed-chatgpt-slirp4netns",
    "managed-wayland-compat-slirp4netns",
    "managed-ai-copilots-model-download",
    "managed-labwc-ai-llama-server",
    "whisper-http-client",
    "whisper-server",
    "managed-whisper-record-toggle",
    "managed-incus-host-managed",
}
allowed_global_profiles = {
    "managed-devops-toolchain",
}
profile_stack = []
errors = []
for line_number, line in enumerate(
    profile_path.read_text(encoding="utf-8").splitlines(),
    start=1,
):
    profile_match = re.match(
        r"^(?P<indent> *)profile\s+(?P<label>\S+).*\{$",
        line,
    )
    if profile_match is not None:
        profile_stack.append(
            (
                len(profile_match.group("indent")),
                profile_match.group("label"),
            )
        )
        continue
    if not profile_stack:
        continue
    current_profile = profile_stack[-1][1]
    if re.match(r"^\s*network(?:\s|,)", line):
        if current_profile not in allowed_network_profiles:
            errors.append(
                f"{line_number}: unexpected network grant in {current_profile}"
            )
    if re.match(r"^\s*/(?:usr|opt|etc|proc|sys)/\*\*", line):
        if current_profile not in allowed_global_profiles:
            errors.append(
                f"{line_number}: unexpected global tree grant in {current_profile}"
            )
    close_match = re.match(r"^(?P<indent> *)\}$", line)
    if (
        close_match is not None
        and len(close_match.group("indent")) == profile_stack[-1][0]
    ):
        profile_stack.pop()
if errors:
    print("\n".join(errors), file=sys.stderr)
    raise SystemExit(1)
PY

system_unconfined_exec_policy_ok=true
python3 - "$SYSTEM_PROFILE" <<'PY' || system_unconfined_exec_policy_ok=false
from pathlib import Path
import re
import sys

profile_path = Path(sys.argv[1])
allowed_rules = {
    ("managed-secondboot-cleanup", "/usr/bin/systemctl", "PUx"),
}
current_profile = None
depth = 0
seen_rules = set()
errors = []
for line_number, line in enumerate(
    profile_path.read_text(encoding="utf-8").splitlines(),
    start=1,
):
    match = re.match(r"^profile\s+(\S+).*\{$", line)
    if match is not None and current_profile is None:
        current_profile = match.group(1)
        depth = 1
        continue
    if current_profile is None:
        continue
    rule_match = re.match(r"^\s*(\S+)\s+([A-Za-z]+x),$", line)
    if rule_match is not None and "u" in rule_match.group(2).lower():
        rule = (current_profile, rule_match.group(1), rule_match.group(2))
        seen_rules.add(rule)
        if rule not in allowed_rules:
            errors.append(
                f"{line_number}: unexpected unconfined execution fallback "
                f"in {current_profile}: {rule_match.group(1)} "
                f"{rule_match.group(2)}"
            )
    depth += line.count("{") - line.count("}")
    if depth == 0:
        current_profile = None
missing_rules = allowed_rules - seen_rules
for profile_name, executable, mode in sorted(missing_rules):
    errors.append(
        f"missing reviewed unconfined execution fallback in {profile_name}: "
        f"{executable} {mode}"
    )
if errors:
    print("\n".join(errors), file=sys.stderr)
    raise SystemExit(1)
PY

plans_profile=$(profile_block managed-labwc-plans)
telpoll_profile=$(profile_block managed-telpoll)
if ! grep -Eq 'flags=.*(complain|default_allow|unconfined)' "$PROFILE" "$SYSTEM_PROFILE" &&
   ! grep -Eq '^[[:space:]]*(owner[[:space:]]+)?/[*][*][[:space:]]' "$PROFILE" "$SYSTEM_PROFILE" &&
   ! grep -Eq '^[[:space:]]*(owner[[:space:]]+)?/home/[*][*][[:space:]]+rw' "$PROFILE" &&
   [ "$network_profile_policy_ok" = true ] &&
   [ "$system_unconfined_exec_policy_ok" = true ] &&
   grep -qx '  network bluetooth raw,' "$PROFILE" &&
   [ "$(printf '%s\n' "$plans_profile" | grep -Ec '^  network (inet|inet6) (stream|dgram),$')" -eq 4 ] &&
   [ "$(printf '%s\n' "$telpoll_profile" | grep -Ec '^  network (inet|inet6) (stream|dgram),$')" -eq 4 ] &&
   printf '%s\n' "$plans_profile" |
     grep -Fqx '  owner @{HOME}/Syncthing/sleek/*.txt r,' &&
   printf '%s\n' "$plans_profile" |
     grep -Fqx '  owner @{HOME}/.local/state/labwc-plans/** rwkl,' &&
   printf '%s\n' "$telpoll_profile" |
     grep -Fqx '  /etc/telpoll/telpoll.conf r,' &&
   printf '%s\n' "$telpoll_profile" |
     grep -Fqx '  /etc/default/labwc-plans r,' &&
   printf '%s\n' "$telpoll_profile" |
     grep -Fqx '  owner @{HOME}/Downloads/telegram/** rwkl,' &&
   ! printf '%s\n' "$plans_profile" |
     grep -Eq 'owner @\{HOME\}/\*\*|^[[:space:]]*/(usr|etc|proc|sys)/\*\*' &&
   ! printf '%s\n' "$telpoll_profile" |
     grep -Eq 'owner @\{HOME\}/\*\*|^[[:space:]]*/(usr|etc|proc|sys)/\*\*' &&
   ! grep -Eq '^[[:space:]]*/(usr/)?(bin|sbin)/[*][*][[:space:]]+[pP]?[uU]?x' "$PROFILE" "$SYSTEM_PROFILE"; then
  pass "wrapper profiles avoid global filesystem and unconfined executable fallback grants"
else
  fail "wrapper profiles avoid global filesystem and unconfined executable fallback grants"
fi
unset plans_profile telpoll_profile

labwc_session_profile=$(profile_block managed-labwc-session)
incus_host_profile=$(profile_block managed-incus-host-managed)
if ! grep -R -Fq '/etc/skel' "$APPARMOR_DIR" &&
   printf '%s\n' "$labwc_session_profile" |
     grep -Fqx '  owner @{HOME}/.profile.d/ r,' &&
   printf '%s\n' "$labwc_session_profile" |
     grep -Fqx '  owner @{HOME}/.profile.d/* r,' &&
   ! printf '%s\n' "$incus_host_profile" |
     grep -Fq '/etc/skel'; then
  pass "managed AppArmor profiles read installed user profile fragments and never reference /etc/skel"
else
  fail "managed AppArmor profiles read installed user profile fragments and never reference /etc/skel"
fi
unset labwc_session_profile incus_host_profile

if grep -q '^  /usr/local/bin/labwc-fuzzel rPx -> managed-labwc-fuzzel,$' "$PROFILE" &&
   grep -q '^  /usr/local/bin/satty rPx -> managed-satty,$' "$PROFILE" &&
   grep -q '^  /usr/local/sbin/greetd-power-action rPx -> managed-greetd-power-action,$' "$PROFILE" &&
   grep -q '^  /usr/local/sbin/labwc-notify rix,$' "$PROFILE" &&
   grep -q '^  /usr/local/bin/labwc-terminal rPx -> managed-labwc-terminal,$' "$PROFILE" &&
   grep -q '^  /usr/local/libexec/labwc-security-action-root rix,$' "$PROFILE" &&
   grep -q '^  /usr/local/libexec/apparmor-generate-rules rPx -> managed-apparmor-rule-generator,$' "$PROFILE" &&
   grep -q '^  /usr/local/libexec/apparmor-managed-modes-run rPx -> managed-apparmor-managed-modes,$' "$PROFILE" &&
   grep -q '^  /usr/bin/{notify-send,pkexec} PUx,$' "$PROFILE" &&
   profile_block managed-labwc-managed-app |
     grep -Fqx '  /usr/bin/bwrap rCx -> managed-app-bwrap,' &&
   profile_block managed-labwc-managed-app |
     grep -Fqx '  /usr/bin/xdg-dbus-proxy pux,' &&
   ! profile_block managed-labwc-managed-app |
     grep -Fq '/usr/bin/busctl' &&
   ! profile_block managed-labwc-managed-app |
     grep -Fq 'path=/org/freedesktop/secrets' &&
   ! profile_block managed-labwc-managed-app |
     grep -Fq 'systemctl' &&
   profile_block managed-labwc-managed-app |
     grep -Fqx '  /opt/Bitwarden/bitwarden rpx -> bitwarden,' &&
   profile_block managed-labwc-managed-app |
     grep -Fqx '  /opt/Filen/Filen rpx -> filen,' &&
   profile_block managed-labwc-managed-app |
     grep -Fqx '  /opt/Obsidian/obsidian rpx -> obsidian,' &&
   profile_block managed-labwc-managed-app |
     grep -Fqx '  /opt/postman/app/Postman rpx -> postman,' &&
   profile_block managed-labwc-managed-app |
     grep -Fqx '  /opt/sleek/sleek rpx -> sleek,' &&
   profile_block managed-labwc-managed-app |
     grep -Fqx '  /opt/vivaldi/{vivaldi,vivaldi-bin} rPx,' &&
   profile_block managed-labwc-managed-app |
     grep -Fqx '  /usr/bin/code rpx -> code,' &&
   profile_block managed-labwc-managed-app |
     grep -Fqx '  /usr/share/code/{bin/code,code} rpx -> code,' &&
   profile_block managed-labwc-managed-app |
     grep -Fqx '  /usr/bin/{filen,filen-desktop} rpx -> filen,' &&
   profile_block managed-labwc-managed-app |
     grep -Fqx '  /usr/bin/obsidian rpx -> obsidian,' &&
   profile_block managed-labwc-managed-app |
     grep -Fqx '  owner @{HOME}/Syncthing/obsidian-md/ rw,' &&
   profile_block managed-labwc-managed-app |
     grep -Fqx '  owner @{HOME}/Syncthing/obsidian-md/** rwkl,' &&
   profile_block managed-labwc-managed-app |
     grep -Fqx '  owner @{HOME}/Syncthing/.stignore rwkl,' &&
   profile_block managed-labwc-managed-app |
     grep -Fqx '  /usr/local/share/labwc-managed-app/ r,' &&
   profile_block managed-labwc-managed-app |
     grep -Fqx '  /usr/local/share/labwc-managed-app/gridline-gtk.css r,' &&
   ! profile_block managed-labwc-managed-app |
     grep -Fq '  /etc/skel/' &&
   profile_block managed-labwc-managed-app |
     grep -Fqx '  /usr/bin/sleek rpx -> sleek,' &&
   profile_block managed-labwc-managed-app |
     grep -Fqx '  /usr/bin/spotify rpx -> spotify,' &&
   profile_block managed-labwc-managed-app |
     grep -Fqx '  /usr/share/spotify/spotify rpx -> spotify,' &&
   profile_block managed-labwc-managed-app |
     grep -Fqx '  /usr/bin/{chromium,keepassxc,microsoft-edge-stable,mullvad-browser,qbittorrent,retroarch,telegram-desktop,vivaldi-stable} rPx,' &&
   profile_block managed-app-bwrap |
     grep -Fqx '    #include <abstractions/managed-bwrap-common>' &&
   profile_block managed-app-bwrap |
     grep -Fqx '    #include <abstractions/managed-bwrap-desktop-runtime>' &&
   profile_block managed-app-bwrap |
     grep -Fqx '    /opt/{Bitwarden,Filen,Obsidian,ledger-live,postman,sleek,tuta-mail}/** mrix,' &&
   profile_block managed-app-bwrap |
     grep -Fqx '    /opt/Bitwarden/bitwarden rix,' &&
   profile_block managed-app-bwrap |
     grep -Fqx '    /opt/tuta-mail/AppRun rix,' &&
   profile_block managed-app-bwrap |
     grep -Fqx '    /usr/bin/{chromium,code,keepassxc,microsoft-edge-stable,mullvad-browser,qbittorrent,retroarch,telegram-desktop,vivaldi-stable} rix,' &&
   profile_block managed-app-bwrap |
     grep -Fqx '    /proc/self/exe rix,' &&
   profile_block managed-app-bwrap |
     grep -Fqx '    /usr/share/spotify/spotify rix,' &&
   grep -Fqx '  /proc/self/exe rix,' "$SPOTIFY_PROFILE" &&
   profile_block managed-satty-runtime |
     grep -Fqx '  /usr/bin/bwrap rCx -> satty-bwrap,' &&
   profile_block managed-satty-runtime |
     grep -Fqx '  signal (send) set=(kill) peer=managed-satty-runtime//satty-bwrap,' &&
   profile_block satty-bwrap |
     grep -Fqx '    #include <abstractions/managed-bwrap-common>' &&
   profile_block satty-bwrap |
     grep -Fqx '    signal (receive) set=(kill) peer=managed-satty-runtime,' &&
   profile_block satty-bwrap |
     grep -Fqx '    /usr/bin/true rix,' &&
   profile_block satty-bwrap |
     grep -Fqx '    /usr/libexec/glycin-loaders/2+/{glycin-image-rs,glycin-svg} rix,' &&
   profile_block satty-bwrap |
     grep -Fqx '    owner /run/user/[0-9]*/labwc-capture/satty-source.*.png r,' &&
   profile_block managed-labwc-managed-app |
     grep -Fqx '  deny /opt/xwayland/** rxm,' &&
   profile_block managed-labwc-managed-app |
     grep -Fqx '  deny /usr/bin/Xwayland rxm,' &&
   profile_block managed-labwc-managed-app |
     grep -Fqx '  deny /tmp/.X11-unix/** rw,' &&
   profile_block managed-labwc-managed-app |
     grep -Fqx '  deny /usr/local/lib/python3.14/dist-packages/labwc_managed_app/wayland_compat{,_runtime}.py r,' &&
   ! profile_block managed-labwc-managed-app |
     grep -Eq '^  /opt/(xwayland|discord|zoom)|^  /usr/bin/(Xwayland|zoom)' &&
   profile_block managed-app-bwrap |
     grep -Fqx '    deny /opt/xwayland/** rxm,' &&
   profile_block managed-app-bwrap |
     grep -Fqx '    deny /usr/bin/Xwayland rxm,' &&
   profile_block managed-app-bwrap |
     grep -Fqx '    deny /tmp/.X11-unix/** rw,' &&
   ! profile_block managed-app-bwrap |
     grep -Eq '^    /opt/(xwayland|discord|zoom)|^    /usr/bin/(Xwayland|zoom)' &&
   profile_block managed-labwc-zoom-discord-compat-runtime |
     grep -Fqx '  deny /usr/local/lib/python3.14/dist-packages/labwc_managed_app/wayland_compat_runtime.py r,' &&
   profile_block managed-labwc-zoom-discord-compat-runtime |
     grep -Fqx '  deny /opt/xwayland/** rxm,' &&
   profile_block managed-labwc-zoom-discord-compat-runtime |
     grep -Fqx '  deny /usr/bin/Xwayland rxm,' &&
   profile_block managed-labwc-managed-wayland-compat-app |
     grep -Fqx '  /usr/bin/bwrap rCx -> managed-wayland-compat-app-bwrap,' &&
   profile_block managed-labwc-managed-wayland-compat-app |
     grep -Fqx '  /usr/bin/slirp4netns rPx -> managed-wayland-compat-slirp4netns,' &&
   profile_block managed-labwc-managed-wayland-compat-app |
     grep -Fqx '  /usr/bin/cage r,' &&
   profile_block managed-labwc-managed-wayland-compat-app |
     grep -Fqx '  /usr/bin/xdg-dbus-proxy rCx -> managed-wayland-compat-dbus-proxy,' &&
   profile_block managed-labwc-managed-wayland-compat-app |
     grep -Fqx '  signal (send) set=(kill term) peer=managed-labwc-managed-wayland-compat-app//managed-wayland-compat-dbus-proxy,' &&
   profile_block managed-labwc-managed-wayland-compat-app |
     grep -Fqx '  signal (send) set=(exists kill term) peer=managed-wayland-compat-slirp4netns,' &&
   profile_block managed-labwc-managed-wayland-compat-app |
     grep -Fqx '  owner @{PROC}/@{pid}/fd/ r,' &&
   profile_block managed-wayland-compat-slirp4netns |
     grep -Fqx '  ptrace (read) peer=managed-labwc-managed-wayland-compat-app//managed-wayland-compat-app-bwrap,' &&
   profile_block managed-wayland-compat-slirp4netns |
     grep -Fqx '  signal (receive) set=(exists kill term) peer=managed-labwc-managed-wayland-compat-app,' &&
   profile_block managed-wayland-compat-slirp4netns |
     grep -Fqx '  /dev/net/tun rw,' &&
   profile_block managed-wayland-compat-slirp4netns |
     grep -Fqx '  /run/systemd/resolve/stub-resolv.conf r,' &&
   profile_block managed-wayland-compat-slirp4netns |
     grep -Fqx '  owner /run/user/[0-9]*/labwc-{discord,zoom}-sandbox-*/slirp4netns.stderr rw,' &&
   profile_block managed-wayland-compat-slirp4netns |
     grep -Fqx '  owner /tmp/labwc-{discord,zoom}-sandbox-*/slirp4netns.stderr rw,' &&
   profile_block managed-labwc-managed-wayland-compat-app |
     grep -Fqx '  /opt/xwayland/usr/bin/Xwayland r,' &&
   profile_block managed-labwc-managed-wayland-compat-app |
     grep -Fqx '  /opt/xwayland/usr/bin/xkbcomp r,' &&
   ! profile_block managed-labwc-managed-wayland-compat-app |
     grep -Fqx '  /usr/bin/xkbcomp r,' &&
   profile_block managed-labwc-managed-wayland-compat-app |
     grep -Fqx '  /opt/xwayland/usr/lib/xkbcomp-overlay/ r,' &&
   profile_block managed-labwc-managed-wayland-compat-app |
     grep -Fqx '  /opt/xwayland/usr/lib/xkbcomp-overlay/xkbcomp r,' &&
   profile_block managed-labwc-managed-wayland-compat-app |
     grep -Fqx '  /opt/xwayland/usr/lib/xorg/protocol.txt r,' &&
   ! grep -Fqx '  /tmp/.X11-unix/ r,' "$PROFILE" &&
   ! grep -Fqx '  owner /tmp/.X11-unix/X[0-9]* r,' "$PROFILE" &&
   profile_block managed-wayland-compat-app-bwrap |
     grep -Fqx '    #include <abstractions/managed-bwrap-desktop-runtime>' &&
   profile_block managed-wayland-compat-app-bwrap |
     grep -Fqx '    #include <abstractions/managed-pipewire-audio>' &&
   profile_block managed-wayland-compat-app-bwrap |
     grep -Fqx '    capability dac_read_search,' &&
   profile_block managed-wayland-compat-app-bwrap |
     grep -Fqx '    signal (send, receive) peer=managed-labwc-managed-wayland-compat-app//managed-wayland-compat-app-bwrap,' &&
   profile_block managed-wayland-compat-app-bwrap |
     grep -Fqx '    /run/dbus/system_bus_socket rw,' &&
   profile_block managed-wayland-compat-app-bwrap |
     grep -Fqx '    /dev/{media,video}[0-9]* rw,' &&
   profile_block managed-wayland-compat-app-bwrap |
     grep -Fqx '    /dev/v4l-subdev[0-9]* rw,' &&
   profile_block managed-wayland-compat-app-bwrap |
     grep -Fqx '    /dev/console rw,' &&
   profile_block managed-wayland-compat-app-bwrap |
     grep -Fqx '    owner /run/user/[0-9]*/pulse/ rw,' &&
   profile_block managed-wayland-compat-app-bwrap |
     grep -Fqx '    owner @{HOME}/.config/pulse/ rw,' &&
   profile_block managed-wayland-compat-app-bwrap |
     grep -Fqx '    owner @{HOME}/.config/ rw,' &&
   profile_block managed-wayland-compat-app-bwrap |
     grep -Fqx '    owner @{HOME}/.config/\#* rwkl,' &&
   profile_block managed-wayland-compat-app-bwrap |
     grep -Fqx '    owner @{HOME}/.config/zoomus.conf* rwkl,' &&
   profile_block managed-wayland-compat-app-bwrap |
     grep -Fqx '    owner @{PROC}/[0-9]*/mem r,' &&
   profile_block managed-wayland-compat-app-bwrap |
     grep -Fqx '    owner /tmp/.X11-unix/ rw,' &&
   profile_block managed-wayland-compat-app-bwrap |
     grep -Fqx '    owner /tmp/.X11-unix/X[0-9]* rw,' &&
   profile_block managed-wayland-compat-app-bwrap |
     grep -Fqx '    owner /run/user/[0-9]*/wayland-[0-9]*.lock rwk,' &&
   ! profile_block managed-wayland-compat-app-bwrap |
     grep -Fq '/tmp-overlay-work-' &&
   profile_block managed-wayland-compat-app-bwrap |
     grep -Fqx '    /opt/xwayland/usr/bin/Xwayland rix,' &&
   profile_block managed-wayland-compat-app-bwrap |
     grep -Fqx '    /opt/xwayland/usr/bin/xkbcomp r,' &&
   profile_block managed-wayland-compat-app-bwrap |
     grep -Fqx '    /opt/xwayland/usr/lib/xkbcomp-overlay/ r,' &&
   profile_block managed-wayland-compat-app-bwrap |
     grep -Fqx '    /opt/xwayland/usr/lib/xkbcomp-overlay/xkbcomp r,' &&
   profile_block managed-wayland-compat-app-bwrap |
     grep -Fqx '    /usr/bin/xkbcomp rix,' &&
   profile_block managed-wayland-compat-app-bwrap |
     grep -Fqx '    /usr/bin/{bwrap,cage,pacmd,pactl,true} rix,' &&
   profile_block managed-wayland-compat-app-bwrap |
     grep -Fqx '    /usr/lib/x86_64-linux-gnu/libdecor/ r,' &&
   profile_block managed-wayland-compat-app-bwrap |
     grep -Fqx '    /usr/lib/x86_64-linux-gnu/libdecor/plugins-1/ r,' &&
   profile_block managed-wayland-compat-app-bwrap |
     grep -Fqx '    /usr/lib/x86_64-linux-gnu/libdecor/plugins-1/libdecor-gtk.so mr,' &&
   profile_block managed-wayland-compat-app-bwrap |
     grep -Fqx '    /usr/local/libexec/labwc-zoom-discord-compat-runtime rix,' &&
   profile_block managed-wayland-compat-app-bwrap |
     grep -Fqx '    deny /usr/bin/Xwayland rxm,' &&
   ! profile_block managed-wayland-compat-app-bwrap |
     grep -Eq '/opt/xwayland/usr/bin/Xwayland[[:space:]]+r[PpCc]x[[:space:]]+->' &&
   ! profile_block managed-wayland-compat-app-bwrap |
     grep -Eq '^    profile [^ ]+' &&
   profile_block labwc-cage-direct-exec-deny |
     grep -Fqx 'profile labwc-cage-direct-exec-deny /usr/bin/cage flags=(attach_disconnected, mediate_deleted) {' &&
   profile_block labwc-cage-direct-exec-deny |
     grep -Fqx '  deny /usr/bin/cage mr,' &&
   profile_block labwc-xwayland-direct-exec-deny |
     grep -Fqx 'profile labwc-xwayland-direct-exec-deny /{opt/xwayland/usr,usr}/bin/Xwayland flags=(attach_disconnected, mediate_deleted) {' &&
   profile_block labwc-xwayland-direct-exec-deny |
     grep -Fqx '  deny /{opt/xwayland/usr,usr}/bin/Xwayland mr,' &&
   profile_block labwc-xkbcomp-direct-exec-deny |
     grep -Fqx 'profile labwc-xkbcomp-direct-exec-deny /opt/xwayland/usr/{bin,lib/xkbcomp-overlay}/xkbcomp flags=(attach_disconnected, mediate_deleted) {' &&
   profile_block labwc-xkbcomp-direct-exec-deny |
     grep -Fqx '  deny /opt/xwayland/usr/{bin,lib/xkbcomp-overlay}/xkbcomp mr,' &&
   ! grep -Fq 'managed-labwc-private-xwayland' "$PROFILE" &&
   ! profile_block managed-wayland-compat-app-bwrap |
     grep -Fq '/tmp/.X11-unix/**' &&
   private_xwayland_library_rules_present &&
   profile_block managed-wayland-compat-app-bwrap |
     grep -Fqx '    /usr/lib/xorg/protocol.txt r,' &&
   ! profile_block managed-app-bwrap |
     grep -Eq '[[:space:]][pP]ux,' &&
   ! profile_block managed-app-bwrap |
     grep -Eq -- '-> (bitwarden|filen|obsidian|ledger-live|postman|sleek|tuta-mail|usr\.bin\.zoom|keepassxc|qbittorrent|retroarch|telegram-desktop|labwc-microsoft-edge-launcher|labwc-mullvad-browser-launcher),' &&
   profile_block managed-labwc-keyboard-layout |
     grep -Fqx '  /usr/bin/{flock,install,mv,rm,sleep} rix,' &&
   profile_block managed-labwc-keyboard-layout |
     grep -Fqx '  owner @{HOME}/.local/state/labwc/{keyboard-layout,keyboard-layout-waybar.lock} rwkl,' &&
   profile_block managed-labwc-keyboard-layout |
     grep -Fqx '  owner @{HOME}/.local/state/labwc/keyboard-layout.* rwkl,' &&
   profile_block labwc-microsoft-edge-launcher |
     grep -Fqx '  /dev/tty rw,' &&
   profile_block labwc-microsoft-edge-launcher |
     grep -Fqx '  owner @{HOME}/.local/share/mimeapps.list rwk,' &&
   profile_block labwc-microsoft-edge-launcher |
     grep -Fqx '  owner @{PROC}/@{pid}/fd/[0-9]* rw,' &&
   profile_block labwc-chromium-launcher |
     grep -Fqx '  owner @{HOME}/ r,' &&
   ! profile_block labwc-chromium-launcher |
     grep -Fq 'owner @{HOME}/**' &&
   profile_block labwc-mullvad-browser-launcher |
     grep -Fqx '  /dev/tty rw,' &&
   ! profile_block labwc-microsoft-edge-launcher |
     grep -Fq 'labwc-session.lock' &&
   ! profile_block labwc-mullvad-browser-launcher |
     grep -Fq 'labwc-session.lock' &&
   profile_block managed-labwc-freerdp-askpass |
     grep -Fqx '  /usr/bin/bwrap rCx -> freerdp-bwrap,' &&
    profile_block managed-labwc-podman-menu |
      grep -Fqx '  /etc/subuid r,' &&
    profile_block managed-labwc-autostart |
      grep -Fqx '  /usr/bin/{sleep,stat} rix,' &&
    profile_block managed-labwc-autostart |
      grep -Fqx '  /usr/bin/{dbus-update-activation-environment,systemctl} pux,' &&
   ! profile_block managed-labwc-autostart |
     grep -Eq 'xwayland|Xwayland|X11-unix|libxcb-cursor' &&
   ! profile_block managed-labwc-autostart |
     grep -Fq 'labwc-autostart.lock' &&
   ! profile_block managed-labwc-autostart |
     grep -Fq 'labwc-{kanshi,mako,output-watch,polkit-agent,swaybg,swayidle,waybar}.lock' &&
   profile_block managed-labwc-kanshi |
     grep -Fqx '  /usr/bin/kanshi pux,' &&
   profile_block managed-labwc-swaybg |
     grep -Fqx '  /usr/bin/swaybg pux,' &&
   ! profile_block managed-waypaper |
     grep -Fqx '  /usr/bin/swaybg pux,' &&
   profile_block managed-labwc-swayidle |
     grep -Fqx '  /usr/bin/swayidle pux,' &&
   profile_block managed-labwc-wallpaper-save |
     grep -Fqx '  /etc/magic r,' &&
   profile_block managed-labwc-wallpaper-save |
     grep -Fqx '  /usr/bin/systemctl pux,' &&
   profile_block managed-labwc-wallpaper-save |
     grep -Fqx '  owner @{HOME}/.local/state/labwc/.wallpaper.* rwk,' &&
   profile_block managed-satty |
     grep -Fqx '  owner @{HOME}/ r,' &&
   profile_block managed-satty |
     grep -Fqx '  /opt/glibc/2.44-1/satty/** r,' &&
   profile_block managed-satty |
     grep -Fqx '  /opt/glibc/2.44-1/satty/{lib,lib64,usr/lib}/**/ld-linux-x86-64.so.2 rPx -> managed-satty-runtime,' &&
   profile_block managed-satty-runtime |
     grep -Fqx '  /usr/local/libexec/satty/satty mr,' &&
   profile_block managed-labwc-security-action-root |
     grep -Fqx '  #include <abstractions/managed-wrapper-perl>' &&
   profile_block managed-labwc-security-action-root |
     grep -Fqx '  /usr/local/lib/perl5/site_perl/labwc-security-action/ r,' &&
   profile_block managed-labwc-security-action-root |
     grep -Fqx '  /usr/local/lib/perl5/site_perl/labwc-security-action/** r,' &&
   ! profile_block managed-labwc-security-action-root |
     grep -Fq '/usr/bin/python3' &&
   profile_block managed-labwc-chatgpt-log-runner |
     grep -Fqx '  #include <abstractions/managed-wrapper-perl>' &&
   profile_block managed-labwc-chatgpt-log-runner |
     grep -Fqx '  /usr/bin/setsid rix,' &&
   profile_block managed-labwc-chatgpt-log-runner |
     grep -Fqx '  /usr/local/bin/labwc-managed-app rPx -> managed-labwc-chatgpt,' &&
   profile_block managed-labwc-chatgpt-log-runner |
     grep -Fqx '  /run/rsyslog/managed-openai/ r,' &&
   profile_block managed-labwc-chatgpt-log-runner |
     grep -Fqx '  /run/rsyslog/managed-openai/chatgpt.sock w,' &&
   profile_block managed-labwc-chatgpt-log-runner |
     grep -Fqx '  deny /dev/log rw,' &&
   profile_block managed-labwc-chatgpt-log-runner |
     grep -Fqx '  deny /{,var/}run/systemd/journal/** rw,' &&
   profile_block managed-labwc-chatgpt-log-runner |
     grep -Fqx '  deny /var/log/managed/openai/** rwkl,' &&
   profile_block managed-labwc-chatgpt |
     grep -Fqx 'profile managed-labwc-chatgpt /usr/local/bin/chatgpt flags=(attach_disconnected, mediate_deleted) {' &&
   profile_block managed-labwc-chatgpt |
     grep -Fqx '  /usr/local/bin/chatgpt rix,' &&
   ! profile_block managed-labwc-chatgpt |
     grep -Fq '/usr/local/bin/labwc-chatgpt' &&
   profile_block managed-labwc-chatgpt |
     grep -Fqx '  /usr/local/libexec/labwc-chatgpt-log-runner rPx -> managed-labwc-chatgpt-log-runner,' &&
   ! profile_block managed-labwc-chatgpt |
     grep -Fqx '  /run/rsyslog/managed-openai/chatgpt.sock w,' &&
   profile_block managed-labwc-chatgpt |
     grep -Fqx '  deny /dev/log rw,' &&
   profile_block managed-labwc-chatgpt |
     grep -Fqx '  deny /{,var/}run/systemd/journal/** rw,' &&
   profile_block managed-labwc-chatgpt |
     grep -Fqx '  deny /run/rsyslog/managed-openai/** rw,' &&
   profile_block managed-labwc-chatgpt |
     grep -Fqx '  /var/log/managed/openai/chatgpt/ r,' &&
   profile_block managed-labwc-chatgpt |
     grep -Fqx '  deny /var/log/managed/openai/chatgpt/ wkl,' &&
   profile_block managed-labwc-chatgpt |
     grep -Fqx '  owner /var/log/managed/openai/chatgpt/runtime/ rw,' &&
   profile_block managed-labwc-chatgpt |
     grep -Fqx '  owner /var/log/managed/openai/chatgpt/runtime/** rwkl,' &&
   profile_block managed-labwc-chatgpt |
     grep -Fqx '  deny /var/log/managed/openai/codex/** rwkl,' &&
   profile_block managed-labwc-chatgpt |
     grep -Fqx '  deny /var/log/managed/openai/chatgpt/chatgpt.log rwkl,' &&
   [ "$(profile_block managed-labwc-chatgpt |
     grep -Fxc '    deny /dev/log rw,')" -eq 2 ] &&
   [ "$(profile_block managed-labwc-chatgpt |
     grep -Fxc '    deny /{,var/}run/systemd/journal/** rw,')" -eq 2 ] &&
   [ "$(profile_block managed-labwc-chatgpt |
     grep -Fxc '    deny /run/rsyslog/managed-openai/** rw,')" -eq 2 ] &&
   [ "$(profile_block managed-labwc-chatgpt |
     grep -Fxc '    deny /var/log/managed/openai/** rwkl,')" -eq 1 ] &&
   [ "$(profile_block managed-labwc-chatgpt |
     grep -Fxc '    /var/log/managed/openai/chatgpt/ r,')" -eq 1 ] &&
   [ "$(profile_block managed-labwc-chatgpt |
     grep -Fxc '    deny /var/log/managed/openai/chatgpt/ wkl,')" -eq 1 ] &&
   [ "$(profile_block managed-labwc-chatgpt |
     grep -Fxc '    owner /var/log/managed/openai/chatgpt/runtime/ rw,')" -eq 1 ] &&
   [ "$(profile_block managed-labwc-chatgpt |
     grep -Fxc '    deny /var/log/managed/openai/codex/** rwkl,')" -eq 1 ] &&
   [ "$(profile_block managed-labwc-chatgpt |
     grep -Fxc '    deny /var/log/managed/openai/chatgpt/chatgpt.log rwkl,')" -eq 1 ] &&
   profile_block managed-labwc-chatgpt |
     grep -Fqx '  /usr/bin/bwrap rCx -> chatgpt-bwrap,' &&
   profile_block managed-labwc-chatgpt |
     grep -Fqx '  /usr/bin/slirp4netns rPx -> managed-chatgpt-slirp4netns,' &&
   profile_block managed-labwc-chatgpt |
     grep -Fqx '  /usr/bin/xdg-dbus-proxy rCx -> chatgpt-dbus-proxy,' &&
   profile_block managed-labwc-chatgpt |
     grep -Fqx '  signal (send) set=(exists kill term) peer=managed-chatgpt-slirp4netns,' &&
   profile_block managed-labwc-chatgpt |
     grep -Fqx '  /run/resolvconf/resolv.conf r,' &&
   profile_block managed-chatgpt-slirp4netns |
     grep -Fqx '  ptrace (read) peer=managed-labwc-chatgpt//chatgpt-bwrap,' &&
   profile_block managed-chatgpt-slirp4netns |
     grep -Fqx '  signal (receive) set=(exists kill term) peer=managed-labwc-chatgpt,' &&
   profile_block managed-chatgpt-slirp4netns |
     grep -Fqx '  /dev/net/tun rw,' &&
   profile_block managed-chatgpt-slirp4netns |
     grep -Fqx '  @{PROC}/[0-9]*/ns/{net,user} r,' &&
   ! profile_block managed-chatgpt-slirp4netns |
     grep -Fq '/data/codex/runtime/.control/' &&
   profile_block chatgpt-dbus-proxy |
     grep -Fqx '    owner /run/user/[0-9]*/labwc-chatgpt-sandbox-*/{session-bus,system-bus} rw,' &&
   profile_block managed-codex-wrapper |
     grep -Fqx '  owner @{HOME}/.profile.d/{71-devops-de.sh,72-incus.sh,75-firmware-workspace.sh} r,' &&
   profile_block managed-codex-wrapper |
     grep -Fqx '  /usr/bin/{mise,pwsh,sccache} rix,' &&
   profile_block managed-codex-wrapper |
     grep -Fqx '  /usr/lib/llvm-24/bin/{clang,clang++,ld.lld,lld,lldb,llvm-config} rix,' &&
   ! profile_block managed-codex-wrapper |
     grep -Fq '/usr/local/bin/bazel' &&
   profile_block managed-codex-wrapper |
     grep -Fqx '    /usr/local/lib/bazelisk/bazel rPx -> managed-devops-toolchain,' &&
   profile_block managed-codex-wrapper |
     grep -Fqx '  /opt/ r,' &&
   profile_block managed-codex-wrapper |
     grep -Fqx '  /data/codex/log/ rw,' &&
   profile_block managed-codex-wrapper |
     grep -Fqx '  /data/codex/sqlite/ rw,' &&
   profile_block managed-codex-wrapper |
     grep -Fqx '  /data/codex/ rw,' &&
   profile_block managed-codex-wrapper |
     grep -Fqx '  /data/downloads/ rw,' &&
   profile_block managed-codex-wrapper |
     grep -Fqx '  owner /var/log/managed/openai/codex/ rw,' &&
   profile_block managed-codex-wrapper |
     grep -Fqx '  owner /var/log/managed/openai/codex/** rwkl,' &&
   profile_block managed-codex-wrapper |
     grep -Fqx '  deny /var/log/managed/openai/chatgpt/** rwkl,' &&
   profile_block managed-codex-wrapper |
     grep -Fqx '  deny /var/log/managed/openai/chatgpt/chatgpt.log rwkl,' &&
   profile_block managed-codex-wrapper |
     grep -Fqx '    owner /var/log/managed/openai/codex/ rw,' &&
   profile_block managed-codex-wrapper |
     grep -Fqx '    owner /var/log/managed/openai/codex/** rwkl,' &&
   profile_block managed-codex-wrapper |
     grep -Fqx '    deny /var/log/managed/openai/chatgpt/** rwkl,' &&
   profile_block managed-codex-wrapper |
     grep -Fqx '  owner @{HOME}/.cmake/packages/ r,' &&
   profile_block managed-codex-wrapper |
     grep -Fqx '  owner @{HOME}/.config/cargo/config.toml r,' &&
   profile_block managed-codex-wrapper |
     grep -Fqx '  owner @{HOME}/.config/Code/User/{keybindings.json,settings.json} r,' &&
   profile_block managed-codex-wrapper |
     grep -Fqx '  owner /run/user/[0-9]*/ r,' &&
   profile_block managed-codex-wrapper |
     grep -Fqx '  /sys/bus/scsi/devices/ r,' &&
   profile_block managed-codex-wrapper |
     grep -Fqx '  /sys/class/{block,dmi,net,nvme}/ r,' &&
   profile_block managed-codex-wrapper |
     grep -Fqx '  /sys/devices/virtual/{block,dmi,net}/ r,' &&
   profile_block managed-codex-wrapper |
     grep -Fqx '  owner @{HOME}/{Downloads,Workspace}/ rw,' &&
   profile_block managed-codex-wrapper |
     grep -Fqx '  /pool/ rw,' &&
   profile_block managed-codex-wrapper |
     grep -Fqx '  /pool/** rw,' &&
   ! profile_block managed-codex-wrapper |
     grep -Fq 'owner @{HOME}/.ssh' &&
   profile_block managed-labwc-chatgpt |
     grep -Fqx '  owner @{HOME}/.profile.d/{71-devops-de.sh,72-incus.sh,75-firmware-workspace.sh} r,' &&
   profile_block managed-labwc-chatgpt |
     grep -Fqx '  /usr/bin/{mise,pwsh,sccache} rix,' &&
   profile_block managed-labwc-chatgpt |
     grep -Fqx '  /usr/lib/llvm-24/bin/{clang,clang++,ld.lld,lld,lldb,llvm-config} rix,' &&
   profile_block managed-labwc-chatgpt |
     grep -Fqx '  /dev/accel/** r,' &&
   ! profile_block managed-labwc-chatgpt |
     grep -Fq '/usr/local/bin/bazel' &&
   profile_block managed-labwc-chatgpt |
     grep -Fqx '  /opt/ r,' &&
   profile_block managed-labwc-chatgpt |
     grep -Fqx '  owner @{HOME}/.cmake/packages/ r,' &&
   profile_block managed-labwc-chatgpt |
     grep -Fqx '  owner @{HOME}/.config/{bat,bazel,clangd,direnv,featherpad,fzf,git,micro,mise,nano,nvim,pip,powershell,retroarch,satty,sleek,task,vim,yamllint}/ r,' &&
   profile_block managed-labwc-chatgpt |
     grep -Fqx '  owner @{HOME}/.config/cargo/config.toml r,' &&
   profile_block managed-labwc-chatgpt |
     grep -Fqx '  owner @{HOME}/.config/containers/{containers.conf,mounts.conf,policy.json,registries.conf,seccomp.json,storage.conf} r,' &&
   profile_block managed-labwc-chatgpt |
     grep -Fqx '  owner @{HOME}/.config/Code/User/{keybindings.json,settings.json} r,' &&
   profile_block managed-labwc-chatgpt |
     grep -Fqx '  owner @{HOME}/.local/share/powershell/Modules/ r,' &&
   profile_block managed-labwc-chatgpt |
     grep -Fqx '  /pool/ rw,' &&
   profile_block managed-labwc-chatgpt |
     grep -Fqx '  /pool/** rwkl,' &&
   profile_block managed-labwc-chatgpt |
     grep -Fqx '  /var/cache/apt/ r,' &&
   profile_block managed-labwc-chatgpt |
     grep -Fqx '  /var/lib/apt/lists/ r,' &&
   profile_block managed-labwc-chatgpt |
     grep -Fqx '  /var/lib/dpkg/ r,' &&
   ! profile_block managed-labwc-chatgpt |
     grep -Fq 'owner @{HOME}/.ssh' &&
   ! profile_block managed-labwc-chatgpt |
     grep -Eq 'owner @\{HOME\}/[.]config/(age|npm|sccache|sops)(/|[[:space:]])' &&
   ! profile_block managed-labwc-chatgpt |
     grep -Fqx '  owner @{HOME}/.config/** r,' &&
   ! grep -Fq 'profile managed-bazel-wrapper ' "$PROFILE" &&
   profile_block chatgpt-bwrap |
     grep -Fqx '    /usr/local/lib/bazelisk/bazel rPx -> managed-devops-toolchain,' &&
   profile_block chatgpt-bwrap |
     grep -Fqx '    /usr/bin/chatgpt rix,' &&
   profile_block chatgpt-bwrap |
     grep -Fqx '    /usr/bin/xdg-open rix,' &&
   profile_block chatgpt-bwrap |
     grep -Fqx '    deny /etc/opt/ w,' &&
   profile_block chatgpt-bwrap |
     grep -Fqx '    deny /etc/opt/chrome/ w,' &&
   profile_block chatgpt-bwrap |
     grep -Fqx '    deny /etc/opt/chrome/native-messaging-hosts/ w,' &&
   grep -Fqx '#include <abstractions/managed-desktop-runtime>' "$ABSTRACTION_DIR/managed-desktop-application" &&
   grep -Fqx '/usr/bin/xdg-open rpux,' "$ABSTRACTION_DIR/managed-desktop-application" &&
   ! grep -Fq 'xdg-open' "$ABSTRACTION_DIR/managed-desktop-runtime" &&
   profile_block chatgpt-bwrap |
     grep -Fqx '    /pool/ rw,' &&
   profile_block chatgpt-bwrap |
     grep -Fqx '    /pool/** rwklm,' &&
   profile_block chatgpt-bwrap |
     grep -Fqx '    /pool/** rix,' &&
   profile_block managed-incus-host-managed |
     grep -Fqx '  /etc/default/incus-host-managed r,' &&
   profile_block managed-incus-host-managed |
     grep -Fqx '  /var/lib/incus/unix.socket rw,' &&
   profile_block managed-incus-host-managed |
     grep -Fqx '  /var/lib/incus/unix.socket.user r,' &&
   profile_block managed-incus-host-managed |
     grep -Fqx '  network unix stream,' &&
   ! profile_block managed-incus-host-managed |
     grep -Eqi 'libvirt|vagrant|lxcfs|virt-manager' &&
   profile_block managed-labwc-chatgpt |
     grep -Fqx '  owner @{HOME}/{Downloads,Workspace}/** rwkl,' &&
   profile_block managed-labwc-chatgpt |
     grep -Fqx '  /data/{codex,downloads}/** rwkl,' &&
   profile_block managed-labwc-chatgpt |
     grep -Fqx '  /data/llama/** r,' &&
   ! profile_block managed-labwc-chatgpt |
     grep -Fq '/data/{codex,downloads,llama}/' &&
   profile_block managed-labwc-chatgpt |
     grep -Fqx '    owner @{HOME}/{Downloads,Workspace}/** rwklm,' &&
   profile_block managed-labwc-chatgpt |
     grep -Fqx '    owner @{HOME}/{Downloads,Workspace}/** rix,' &&
   profile_block managed-labwc-chatgpt |
     grep -Fqx '    /data/codex/** rwklm,' &&
   profile_block managed-labwc-chatgpt |
     grep -Fqx '    /data/downloads/** rwkl,' &&
   profile_block managed-labwc-chatgpt |
     grep -Fqx '    /data/llama/** mr,' &&
   ! profile_block managed-labwc-chatgpt |
     grep -Fqx '    /data/llama/** rwklm,' &&
   profile_block managed-labwc-chatgpt |
     grep -Fqx '    deny /usr/bin/Xwayland rxm,' &&
   profile_block managed-labwc-chatgpt |
     grep -Fqx '    deny /tmp/.X11-unix/** rw,' &&
   profile_block managed-labwc-chatgpt |
     grep -Fqx '    deny /run/rsyslog/managed-openai/** rw,' &&
   profile_block managed-labwc-chatgpt |
     grep -Fqx '    /var/log/managed/openai/chatgpt/ r,' &&
   profile_block managed-labwc-chatgpt |
     grep -Fqx '    deny /var/log/managed/openai/chatgpt/ wkl,' &&
   profile_block managed-labwc-chatgpt |
     grep -Fqx '    owner /var/log/managed/openai/chatgpt/runtime/ rw,' &&
   profile_block managed-labwc-chatgpt |
     grep -Fqx '    owner /var/log/managed/openai/chatgpt/runtime/** rwkl,' &&
   profile_block managed-labwc-chatgpt |
     grep -Fqx '    deny /var/log/managed/openai/codex/** rwkl,' &&
   profile_block managed-labwc-chatgpt |
     grep -Fqx '    deny /var/log/managed/openai/chatgpt/chatgpt.log rwkl,' &&
   grep -Fqx 'profile chatgpt /{usr/bin/chatgpt,usr/lib/chatgpt/{ChatGPT,browser_crashpad_handler,codex-launcher,resources/{codex,codex-code-mode-host}}} flags=(attach_disconnected, mediate_deleted) {' "$CHATGPT_PROFILE" &&
   ! grep -Eq 'flags=.*(unconfined|complain|userns)' "$CHATGPT_PROFILE" &&
   grep -Fqx '  deny /tmp/.X11-unix/** rw,' "$CHATGPT_PROFILE" &&
   grep -q '^  /usr/bin/{scp,test} pux,$' "$PROFILE"; then
  pass "wrapper chaining is strict and managed applications enter exact profiles"
else
  fail "wrapper chaining is strict and managed applications enter exact profiles"
fi

if python3 - \
     "$PROFILE" \
     "$SYSTEM_PROFILE" \
     "$APPARMOR_DIR/usr.sbin.aa-status" \
     "$APPARMOR_DIR/usr.sbin.tailscaled" <<'PY'
from pathlib import Path
import re
import sys

profile_text = "\n".join(
    Path(profile_path).read_text(encoding="utf-8")
    for profile_path in sys.argv[1:]
)
attachments = {
    match.group("path"): match.group("label")
    for match in re.finditer(
        r"^profile (?P<label>[^ ]+) (?P<path>/[^ ]+) flags=",
        profile_text,
        re.MULTILINE,
    )
}
transition_count = 0
errors = []
for block_match in re.finditer(
    r"^profile (?P<label>managed-[^ ]+) (?P<path>/[^ ]+) flags=.*?^}\n",
    profile_text,
    re.MULTILINE | re.DOTALL,
):
    source_path = block_match.group("path")
    for rule_match in re.finditer(
        r"^[ \t]+(?P<path>/[^ ]+) "
        r"(?P<access>[A-Za-z]+)(?: -> (?P<target>[^,]+))?,$",
        block_match.group(0),
        re.MULTILINE,
    ):
        target_path = rule_match.group("path")
        if target_path == source_path or target_path not in attachments:
            continue
        access = rule_match.group("access")
        if not any(marker in access for marker in ("p", "P", "c", "C")):
            continue
        transition_count += 1
        expected_target = attachments[target_path]
        actual_target = rule_match.group("target")
        automatic_fanout = actual_target is None and (
            source_path == "/usr/local/bin/labwc-computer-management"
            or target_path == "/opt/xwayland/bin/bwrap"
        )
        chatgpt_logging_transition = (
            source_path == "/usr/local/libexec/labwc-chatgpt-log-runner"
            and target_path == "/usr/local/bin/labwc-managed-app"
            and actual_target == "managed-labwc-chatgpt"
        )
        if access != "rPx" or (
            not automatic_fanout
            and not chatgpt_logging_transition
            and actual_target != expected_target
        ):
            errors.append(
                f"{source_path}: {target_path} uses "
                f"{access} -> {actual_target or 'automatic'}; "
                f"expected rPx -> {expected_target}"
            )

if not attachments:
    errors.append("expected at least one managed wrapper attachment")
if transition_count == 0:
    errors.append("expected at least one managed wrapper transition")
if errors:
    print("\n".join(errors), file=sys.stderr)
    raise SystemExit(1)
PY
then
  pass "all managed wrapper transitions resolve exact attachments and permit bounded preflight reads"
else
  fail "all managed wrapper transitions resolve exact attachments and permit bounded preflight reads"
fi

if grep -q '^  owner @{HOME}/Documents/OCR/[*][*] rwkl,$' "$PROFILE" &&
   grep -q '^  /etc/nftables/firewall-security.rules r,$' "$PROFILE" &&
   grep -q '^  /etc/apparmor/managed-modes.conf rw,$' "$PROFILE" &&
   profile_block managed-labwc-computer-management |
     grep -Fqx '  /usr/bin/systemctl pux,' &&
	   profile_block managed-labwc-admin-action |
	     grep -Fqx '  /usr/bin/{flock,id,stat} rix,' &&
	   profile_block managed-labwc-admin-action |
	     grep -Fqx '  /usr/bin/{notify-send,pkexec} PUx,' &&
	   profile_block managed-labwc-admin-action |
	     grep -Fqx '  owner /run/user/[0-9]*/labwc-admin-action.lock rwk,' &&
   profile_block managed-labwc-admin-action |
     grep -Fqx '  /usr/local/libexec/labwc-admin-action-root rix,' &&
   ! profile_block managed-labwc-admin-action |
     grep -Fq '/usr/bin/busctl' &&
   ! profile_block managed-labwc-admin-action |
     grep -Fq 'systemd-inhibit' &&
   profile_block managed-labwc-admin-action |
     grep -Fqx '  /usr/local/bin/labwc-admin-action rix,' &&
   profile_block managed-labwc-admin-action-root |
     grep -Fqx '  /usr/local/libexec/labwc-admin-action-root rix,' &&
   profile_block managed-labwc-admin-action-root |
	     grep -Fqx '  /usr/bin/{getent,id} rix,' &&
   profile_block managed-labwc-admin-action-root |
     grep -Fqx '  /usr/bin/systemctl PUx,' &&
   profile_block managed-labwc-admin-action-worker |
     grep -Fqx '  /usr/local/libexec/labwc-admin-action-worker rix,' &&
   profile_block managed-labwc-admin-action-worker |
     grep -Fqx '  /usr/bin/{getent,id,timeout} rix,' &&
   profile_block managed-labwc-admin-action-worker |
     grep -Fqx '  /usr/bin/systemctl PUx,' &&
   grep -Fqx 'AppArmorProfile=managed-labwc-admin-action-worker' "$LABWC_ADMIN_WORKER_UNIT" &&
   ! profile_block managed-labwc-admin-action |
     grep -Fq '@{HOME}/.config/labwc/shutdown' &&
   profile_block managed-mullvad-vpn |
     grep -Fqx '  #include <abstractions/managed-wrapper-desktop>' &&
   profile_block managed-mullvad-vpn |
     grep -Fqx '  /usr/bin/timeout rix,' &&
   profile_block managed-mullvad-vpn |
     grep -Fqx '  /usr/bin/{pkexec,systemctl} PUx,' &&
   profile_block managed-mullvad-vpn |
     grep -Fqx '  /usr/local/libexec/mullvad-daemon-start rix,' &&
   profile_block managed-mullvad-vpn |
     grep -Fqx '  "/opt/Mullvad VPN/mullvad-vpn" pux,' &&
   profile_block managed-mullvad-daemon-start |
     grep -Fqx '  #include <abstractions/managed-wrapper-base>' &&
   profile_block managed-mullvad-daemon-start |
     grep -Fqx '  /usr/bin/{getent,id} rix,' &&
   profile_block managed-mullvad-daemon-start |
     grep -Fqx '  /usr/bin/systemctl PUx,' &&
   /bin/sh -n "$MULLVAD_VPN_WRAPPER" &&
   /bin/sh -n "$MULLVAD_DAEMON_START" &&
   profile_block managed-labwc-health-notify |
     grep -Fqx '  @{PROC}/meminfo r,' &&
   profile_block managed-labwc-health-notify |
     grep -Fqx '  /sys/devices/**/power_supply/*/{capacity,status,type} r,' &&
   profile_block managed-labwc-health-notify |
     grep -Fqx '  /run/reboot-required r,' &&
   profile_block managed-labwc-health-notify |
     grep -Fqx '  /usr/bin/sleep rix,' &&
   profile_block managed-labwc-health-notify |
     grep -Fqx '  owner /run/user/[0-9]*/wayland-[0-9]* r,' &&
   ! grep -Fq 'managed-labwc-session-child' "$PROFILE" &&
   [ ! -e "$APPARMOR_DIR/local/managed-labwc-session-child" ] &&
   profile_block managed-labwc-health-notify |
     grep -Fqx '  signal (receive) set=(hup int kill term) peer=unconfined,' &&
   profile_block managed-labwc-health-notify |
     grep -Fqx '  signal (send) set=(term) peer=managed-labwc-health-notify,' &&
   profile_block managed-labwc-security-action-root |
     grep -Fqx '  /usr/bin/{aa-easyprof,aa-enabled,aa-features-abi} PUx,' &&
   profile_block managed-labwc-security-action-root |
     grep -Fqx '  /usr/sbin/{aa-audit,aa-autodep,aa-genprof,aa-logprof,aa-remove-unknown,aa-unconfined,apparmor_parser,visudo} PUx,' &&
   profile_block managed-labwc-security-action |
     grep -Fqx '  /usr/sbin/apparmor_parser PUx,' &&
   profile_block managed-labwc-security-action |
     grep -Fqx '  /var/lib/apparmor/drafts/** r,' &&
   profile_block managed-labwc-security-action |
     grep -Fqx '  /var/lib/apparmor/easyprof/** r,' &&
   profile_block managed-labwc-security-action |
     grep -Fqx '  /dev/log w,' &&
   profile_block managed-labwc-security-action |
     grep -Fqx '  /run/rsyslog/managed-security-scanners/ r,' &&
   profile_block managed-labwc-security-action |
     grep -Fqx '  /run/rsyslog/managed-security-scanners/scanner.sock w,' &&
   profile_block managed-labwc-security-action-root |
     grep -Fqx '  /etc/apparmor.d/* rw,' &&
   profile_block managed-labwc-security-action-root |
     grep -Fqx '  /dev/log w,' &&
   profile_block managed-labwc-security-action-root |
     grep -Fqx '  /run/rsyslog/managed-security-scanners/ r,' &&
   profile_block managed-labwc-security-action-root |
     grep -Fqx '  /run/rsyslog/managed-security-scanners/scanner.sock w,' &&
   system_profile_block managed-rsyslog-managed-openai-socket |
     grep -Fqx '  capability chown,' &&
   system_profile_block managed-rsyslog-managed-openai-socket |
     grep -Fqx '  capability fowner,' &&
   system_profile_block managed-rsyslog-managed-openai-socket |
     grep -Fqx '  /usr/local/libexec/rsyslog-managed-openai-socket rix,' &&
   system_profile_block managed-rsyslog-managed-openai-socket |
     grep -Fqx '  /usr/bin/{chmod,chown,getent,sleep} rix,' &&
   system_profile_block managed-rsyslog-managed-openai-socket |
     grep -Fqx '  /run/rsyslog/managed-openai/chatgpt.sock rw,' &&
   profile_block managed-labwc-security-action-root |
     grep -Fqx '  /var/lib/apparmor/backup/** rwkl,' &&
   profile_block managed-labwc-security-action-root |
     grep -Fqx '  /var/lib/apparmor/easyprof/** rwkl,' &&
   profile_block managed-labwc-security-action-root |
     grep -Fqx '  /var/lib/apparmor/drafts/** rwkl,' &&
   profile_block managed-labwc-security-action-root |
     grep -Fqx '  /var/log/managed/apparmor/apparmor.log r,' &&
   profile_block managed-apparmor-rule-generator |
     grep -Fqx '  #include <abstractions/managed-wrapper-perl>' &&
   profile_block managed-apparmor-rule-generator |
     grep -Fqx '  /usr/sbin/apparmor_parser PUx,' &&
   profile_block managed-apparmor-rule-generator |
     grep -Fqx '  /etc/apparmor.d/local/ rw,' &&
   profile_block managed-apparmor-rule-generator |
     grep -Fqx '  /etc/apparmor.d/local/** rwkl,' &&
   profile_block managed-apparmor-rule-generator |
     grep -Fqx '  /var/log/managed/apparmor/apparmor.log r,' &&
   profile_block managed-apparmor-rule-generator |
     grep -Fqx '  /var/lib/apparmor/ r,' &&
   ! profile_block managed-apparmor-rule-generator |
     grep -Fqx '  /var/lib/apparmor/ rw,' &&
   profile_block managed-apparmor-rule-generator |
     grep -Fqx '  /var/lib/apparmor/generated-rule-backups/** rwkl,' &&
   profile_block managed-apparmor-managed-modes |
     grep -Fqx '  /etc/apparmor.d/** rwkl,' &&
   profile_block managed-apparmor-managed-modes |
     grep -Fqx '  #include <abstractions/managed-wrapper-perl>' &&
   profile_block managed-apparmor-managed-modes |
     grep -Fqx '  /usr/local/lib/perl5/site_perl/apparmor-managed-modes/ r,' &&
   profile_block managed-apparmor-managed-modes |
     grep -Fqx '  /usr/local/lib/perl5/site_perl/apparmor-managed-modes/** r,' &&
   ! profile_block managed-apparmor-managed-modes |
     grep -Fqx '  /usr/bin/{cat,grep,head,install,ln,mktemp,mv,readlink,rm,stat,wc} rix,' &&
   profile_block managed-apparmor-managed-modes |
     grep -Fqx '  /usr/sbin/{aa-audit,aa-complain,aa-enforce,apparmor_parser} PUx,' &&
   profile_block managed-apparmor-managed-modes |
     grep -Fqx '  /sys/kernel/security/apparmor/profiles r,' &&
   profile_block managed-apparmor-managed-modes |
     grep -Fqx '  /tmp/apparmor-unload.* rw,' &&
   grep -q '^  /dev/rfkill r,$' "$PROFILE" &&
   grep -q '^  /sys/class/bluetooth/hci[*] r,$' "$PROFILE" &&
   grep -q '^  /var/lib/software/[*][*] rwkl,$' "$PROFILE" &&
    grep -q '^  /usr/local/lib/crypto/tpm2-enroll.complete rwk,$' "$PROFILE" &&
    grep -q '^  owner @{HOME}/[*][*] r,$' "$PROFILE" &&
    profile_block managed-labwc-session |
      grep -Fqx '  /usr/bin/{flock,id,jq,sleep,stat} rix,' &&
   ! profile_block managed-labwc-session |
     grep -Eq 'xwayland|Xwayland|X11-unix|libxcb-cursor' &&
    profile_block managed-labwc-session |
      grep -Fqx '  owner @{HOME}/.profile r,'; then
  pass "representative wrapper data grants are job-specific and bounded"
else
  fail "representative wrapper data grants are job-specific and bounded"
fi

whisper_toggle_profile=$(profile_block managed-whisper-record-toggle)
whisper_http_profile=$(profile_block whisper-http-client)
whisper_server_profile=$(profile_block whisper-server)
whisper_record_profile=$(profile_block whisper-record)
if printf '%s\n' "$whisper_toggle_profile" |
     grep -Fqx '  /usr/local/bin/whisper-server rix,' &&
   printf '%s\n' "$whisper_toggle_profile" |
     grep -Fqx '  /data/whisper/bin/whisper-server rix,' &&
   printf '%s\n' "$whisper_toggle_profile" |
     grep -Fqx '  /usr/bin/curl rix,' &&
   printf '%s\n' "$whisper_toggle_profile" |
     grep -Fqx '  /usr/bin/pw-record rCx -> whisper-record,' &&
   printf '%s\n' "$whisper_toggle_profile" |
     grep -Fqx '  /usr/bin/pw-cat rix,' &&
   printf '%s\n' "$whisper_http_profile" |
     grep -Fqx '    network inet stream,' &&
   printf '%s\n' "$whisper_server_profile" |
     grep -Fqx '    owner @{PROC}/@{pid}/cmdline r,' &&
   printf '%s\n' "$whisper_server_profile" |
     grep -Fqx '    network inet stream,' &&
   printf '%s\n' "$whisper_record_profile" |
     grep -Fqx '    /usr/bin/pw-cat rix,' &&
   ! printf '%s\n' "$whisper_toggle_profile" |
     grep -Eq 'whisper-(server|http-client|record).*r[Pp]x'; then
  pass "Whisper control inherits NNP HTTP/server execution while retaining the recorder child domain"
else
  fail "Whisper control inherits NNP HTTP/server execution while retaining the recorder child domain"
fi
unset whisper_http_profile whisper_record_profile whisper_server_profile whisper_toggle_profile

bluetooth_profile_block=$(profile_block managed-bluetooth-controller-init)
if printf '%s\n' "$bluetooth_profile_block" |
     grep -Fqx '  capability net_admin,' &&
   printf '%s\n' "$bluetooth_profile_block" |
     grep -Fqx '  capability net_raw,' &&
   printf '%s\n' "$bluetooth_profile_block" |
     grep -Fqx '  network bluetooth raw,' &&
   printf '%s\n' "$bluetooth_profile_block" |
     grep -Fqx '  /usr/bin/btmgmt rix,' &&
   printf '%s\n' "$bluetooth_profile_block" |
     grep -Fqx '  /usr/{bin,sbin}/rfkill rix,' &&
   printf '%s\n' "$bluetooth_profile_block" |
     grep -Fqx '  signal (send, receive) peer=managed-bluetooth-controller-init,' &&
   ! printf '%s\n' "$bluetooth_profile_block" |
     grep -Eq '[[:space:]][pP][uU]x,'; then
  pass "Bluetooth controller initialization stays confined with its exact capabilities and socket family"
else
  fail "Bluetooth controller initialization stays confined with its exact capabilities and socket family"
fi
unset bluetooth_profile_block

if grep -q '^managed-desktop-wrappers$' "$SECURITY_SCRIPT" &&
   grep -q '^managed-system-wrappers$' "$SECURITY_SCRIPT" &&
   grep -q '^stage_target_system_apparmor_profiles() {$' "$SECURITY_SCRIPT" &&
   grep -q '^  stage_target_system_apparmor_profiles$' "$SECURITY_SCRIPT" &&
   grep -q 'etc/apparmor.d/abstractions/managed-wrapper-base' "$SECURITY_SCRIPT" &&
   grep -q 'etc/apparmor.d/abstractions/managed-wrapper-desktop' "$SECURITY_SCRIPT" &&
   grep -q 'etc/apparmor.d/abstractions/managed-wrapper-gui' "$SECURITY_SCRIPT" &&
   grep -q 'etc/apparmor.d/abstractions/managed-desktop-runtime' "$SECURITY_SCRIPT" &&
   grep -q 'etc/apparmor.d/abstractions/managed-webkit-runtime' "$SECURITY_SCRIPT" &&
   grep -q 'etc/apparmor.d/abstractions/managed-desktop-graphics' "$SECURITY_SCRIPT" &&
   grep -q 'etc/apparmor.d/abstractions/managed-devops-toolchain-runtime' "$SECURITY_SCRIPT" &&
   grep -q 'etc/apparmor.d/abstractions/managed-codex-runtime' "$SECURITY_SCRIPT" &&
   grep -q 'etc/apparmor.d/local/managed-desktop-wrappers-nvidia' "$SECURITY_SCRIPT" &&
   grep -q 'etc/apparmor.d/abstractions/managed-wrapper-python' "$SECURITY_SCRIPT" &&
   grep -q 'etc/apparmor.d/abstractions/managed-wrapper-wayland' "$SECURITY_SCRIPT" &&
   grep -q 'installer_selected_class_reference_is_selected addon/devops' "$SECURITY_SCRIPT" &&
   grep -q "printf '%s\\\\n' chatgpt" "$SECURITY_SCRIPT" &&
   grep -qx '__DESKTOP_APPARMOR_STATE__ if-executable chatgpt /usr/lib/chatgpt/ChatGPT' "$MODE_CONFIG" &&
   [ "$(grep -Fc 'include if exists <local/managed-desktop-wrappers-nvidia>' "$PROFILE")" -eq 8 ] &&
   grep -Fqx '  /dev/{accel,dri,nvidia-caps}/ r,' "$PROFILE" &&
   grep -Fqx '  /dev/{accel,dri,nvidia-caps}/** r,' "$PROFILE" &&
   grep -Fqx '  /dev/{kfd,nvidiactl,nvidia-modeset,nvidia-uvm,nvidia-uvm-tools} r,' "$PROFILE" &&
   grep -Fqx '  /dev/nvidia[0-9]* r,' "$PROFILE" &&
   grep -qx '/dev/nvidia\[0-9\]\* rw,' "$NVIDIA_WRAPPER_LOCAL" &&
   grep -qx '/dev/nvidia-caps/\*\* rw,' "$NVIDIA_WRAPPER_LOCAL" &&
   grep -qx '/dev/nvidia-uvm rw,' "$NVIDIA_WRAPPER_LOCAL" &&
   grep -q '/usr/local/libexec/apparmor-managed-modes-run' "$SECURITY_SCRIPT" &&
   grep -q '^ExecStart=/usr/local/libexec/crowdsec-firstboot$' "$CROWDSEC_UNIT" &&
   grep -q '^ExecStartPre=/usr/local/libexec/managed-syncthing-configure --prepare$' "$MANAGED_SYNCTHING_UNIT"; then
  pass "late security stages universal wrapper policy and units enter exact attachments"
else
  fail "late security stages universal wrapper policy and units enter exact attachments"
fi

if grep -Fqx '  /tmp/apparmor-profile-names.*/** rwkl,' "$PROFILE" &&
   [ "$(grep -Fxc '  include if exists <local/managed-desktop-wrappers-nvidia>' "$PROFILE")" -eq 4 ] &&
   [ "$(grep -Fxc '    include if exists <local/managed-desktop-wrappers-nvidia>' "$PROFILE")" -eq 4 ] &&
   grep -Fqx '    /opt/tuta-mail/AppRun rix,' "$PROFILE"; then
  pass "wrapper policy keeps inherited Tuta execution and depth-specific NVIDIA include policy"
else
  fail "wrapper policy keeps inherited Tuta execution and depth-specific NVIDIA include policy"
fi

if awk '
     /^[[:space:]]*(#|$)/ {
       next
     }
     {
       rows++
       if (NF != 4 || $1 != "__DESKTOP_APPARMOR_STATE__") {
         invalid = 1
       }
     }
     END {
       exit(rows == 64 && !invalid ? 0 : 1)
     }
   ' "$MODE_CONFIG" &&
   ! grep -Eq '^(enforce|complain|disable)[[:space:]]' "$MODE_CONFIG" &&
   grep -qx '__DESKTOP_APPARMOR_STATE__ required managed-desktop-wrappers -' "$MODE_CONFIG" &&
   grep -qx '__DESKTOP_APPARMOR_STATE__ required managed-system-wrappers -' "$MODE_CONFIG" &&
   grep -qx '__DESKTOP_APPARMOR_STATE__ required usr.sbin.aa-status -' "$MODE_CONFIG" &&
   [ "$(grep -c ' managed-desktop-wrappers ' "$MODE_CONFIG")" -eq 1 ] &&
   [ "$(grep -c ' managed-system-wrappers ' "$MODE_CONFIG")" -eq 1 ] &&
   [ "$(grep -c ' usr.sbin.aa-status ' "$MODE_CONFIG")" -eq 1 ]; then
  pass "managed AppArmor source template uses the desktop-state placeholder for all 64 rows"
else
  fail "managed AppArmor source template uses the desktop-state placeholder for all 64 rows"
fi

desktop_profile_paths="$TMP_DIR/desktop-profile-paths"
find "$ROOT_DIR/d-i/forky/hosts/profiles" -type f -name '*.env' -print |
  while IFS= read -r desktop_profile_path; do
    if grep -qx 'LABWC_DESKTOP_ENABLE="true"' "$desktop_profile_path"; then
      printf '%s\n' "$desktop_profile_path"
    fi
  done |
  LC_ALL=C sort >"$desktop_profile_paths"

complain_config="$TMP_DIR/managed-modes-complain.conf"
enforce_config="$TMP_DIR/managed-modes-enforce.conf"
invalid_config="$TMP_DIR/managed-modes-invalid.conf"
invalid_stderr="$TMP_DIR/managed-modes-invalid.stderr"
unset_stderr="$TMP_DIR/managed-modes-unset.stderr"
disable_stderr="$TMP_DIR/managed-modes-disable.stderr"
fixed_mode_config="$TMP_DIR/managed-modes-fixed-mode.conf"
fixed_mode_stderr="$TMP_DIR/managed-modes-fixed-mode.stderr"
malformed_config="$TMP_DIR/managed-modes-malformed.conf"
malformed_stderr="$TMP_DIR/managed-modes-malformed.stderr"
mode_fields_expected="$TMP_DIR/managed-modes-fields.expected"
mode_fields_complain="$TMP_DIR/managed-modes-fields.complain"
mode_fields_enforce="$TMP_DIR/managed-modes-fields.enforce"
cp "$MODE_CONFIG" "$complain_config"
cp "$MODE_CONFIG" "$enforce_config"
cp "$MODE_CONFIG" "$invalid_config"
cp "$MODE_CONFIG" "$malformed_config"
awk '
  BEGIN {
    changed = 0
  }
  !changed && $0 !~ /^[[:space:]]*(#|$)/ {
    $1 = "enforce"
    changed = 1
  }
  {
    print
  }
  END {
    exit(changed ? 0 : 1)
  }
' "$MODE_CONFIG" >"$fixed_mode_config"
printf '%s\n' 'complain required malformed-profile - extra-field' >>"$malformed_config"
awk '$0 !~ /^[[:space:]]*(#|$)/ { print $2, $3, $4 }' \
  "$MODE_CONFIG" >"$mode_fields_expected"

if (
     installer_fatal() {
       printf 'fatal: %s\n' "$*" >&2
       exit 1
     }
     installer_info() {
       :
     }
     # shellcheck disable=SC1090
     . "$SECURITY_SCRIPT"
     DESKTOP_APPARMOR_STATE=complain
     apparmor_apply_desktop_state "$complain_config"
     DESKTOP_APPARMOR_STATE=enforce
     apparmor_apply_desktop_state "$enforce_config"
   ) &&
   [ "$(wc -l <"$desktop_profile_paths")" -eq 13 ] &&
   grep -qx 'DESKTOP_APPARMOR_STATE="complain"' \
     "$ROOT_DIR/d-i/forky/hosts/profiles/override/btrfs-de-main.env" &&
   while IFS= read -r desktop_profile_path; do
     [ "$(grep -Ec '^DESKTOP_APPARMOR_STATE="complain"$' "$desktop_profile_path")" -eq 1 ] ||
       exit 1
   done <"$desktop_profile_paths" &&
   awk '
     $0 !~ /^[[:space:]]*(#|$)/ {
       rows++
       if ($1 != "complain") {
         exit 1
       }
     }
     END { exit(rows == 64 ? 0 : 1) }
   ' "$complain_config" &&
   awk '
     $0 !~ /^[[:space:]]*(#|$)/ {
       rows++
       if ($1 != "enforce") {
         exit 1
       }
     }
     END { exit(rows == 64 ? 0 : 1) }
   ' "$enforce_config" &&
   awk '$0 !~ /^[[:space:]]*(#|$)/ { print $2, $3, $4 }' \
     "$complain_config" >"$mode_fields_complain" &&
   awk '$0 !~ /^[[:space:]]*(#|$)/ { print $2, $3, $4 }' \
     "$enforce_config" >"$mode_fields_enforce" &&
   cmp -s "$mode_fields_expected" "$mode_fields_complain" &&
   cmp -s "$mode_fields_expected" "$mode_fields_enforce" &&
   grep -qx 'complain required managed-desktop-wrappers -' "$complain_config" &&
   grep -qx 'complain required managed-system-wrappers -' "$complain_config" &&
   grep -qx 'complain required usr.sbin.aa-status -' "$complain_config" &&
   grep -qx 'enforce required managed-desktop-wrappers -' "$enforce_config" &&
   grep -qx 'enforce required managed-system-wrappers -' "$enforce_config" &&
   grep -qx 'enforce required usr.sbin.aa-status -' "$enforce_config" &&
   grep -qx 'complain required usr.bin.pwsh -' "$complain_config" &&
   grep -qx 'complain required usr.sbin.apt-cacher-ng -' "$complain_config" &&
   grep -qx 'complain optional msedge -' "$complain_config" &&
   grep -qx 'enforce required usr.bin.pwsh -' "$enforce_config" &&
   grep -qx 'enforce required usr.sbin.apt-cacher-ng -' "$enforce_config" &&
   grep -qx 'enforce optional msedge -' "$enforce_config" &&
   grep -qx 'complain if-executable nvidia_modprobe /usr/bin/nvidia-modprobe' "$complain_config" &&
   grep -qx 'enforce if-executable nvidia_modprobe /usr/bin/nvidia-modprobe' "$enforce_config" &&
   ! grep -q '^apparmor_desktop_state_profile_files()' "$SECURITY_SCRIPT" &&
   ! grep -q '^apparmor_apply_nvidia_mode_policy()' "$SECURITY_SCRIPT" &&
   grep -q 'DIR_HOOKS_SHARED_TARGET etc/apparmor/managed-modes.conf.tmpl' "$SECURITY_SCRIPT" &&
   ! grep -q 'DIR_HOOKS_SHARED_TARGET etc/apparmor/managed-modes.conf)"' "$SECURITY_SCRIPT" &&
   grep -q 'apparmor_apply_desktop_state /target/etc/apparmor/managed-modes.conf' "$SECURITY_SCRIPT" &&
   ! grep -q 'apparmor_apply_nvidia_mode_policy /target/etc/apparmor/managed-modes.conf' "$SECURITY_SCRIPT" &&
   grep -q 'desktop_validate_apparmor_state' "$ROOT_DIR/d-i/forky/scripts/desktop/detect.sh" &&
   grep -q '^DESKTOP_APPARMOR_STATE=__INSTALLER_DESKTOP_APPARMOR_STATE__$' \
     "$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/default/labwc-desktop.tmpl" &&
   grep -q 'DESKTOP_APPARMOR_STATE "$(desktop_shell_config_value ' \
     "$ROOT_DIR/d-i/forky/scripts/desktop/components.sh" &&
   ! grep -q 'write_shell_config_var DESKTOP_APPARMOR_STATE' \
     "$ROOT_DIR/d-i/forky/scripts/desktop/detect.sh" &&
   ! (
     installer_fatal() {
       printf 'fatal: %s\n' "$*" >&2
       exit 1
     }
     installer_info() {
       :
     }
     # shellcheck disable=SC1090
     . "$SECURITY_SCRIPT"
     DESKTOP_APPARMOR_STATE=audit
     apparmor_apply_desktop_state "$invalid_config"
   ) 2>"$invalid_stderr" &&
   grep -q 'DESKTOP_APPARMOR_STATE must be enforce or complain' "$invalid_stderr" &&
   ! (
     installer_fatal() {
       printf 'fatal: %s\n' "$*" >&2
       exit 1
     }
     installer_info() {
       :
     }
     # shellcheck disable=SC1090
     . "$SECURITY_SCRIPT"
     unset DESKTOP_APPARMOR_STATE
     apparmor_apply_desktop_state "$invalid_config"
   ) 2>"$unset_stderr" &&
   grep -q 'DESKTOP_APPARMOR_STATE must be set by every desktop host profile' "$unset_stderr" &&
   ! (
     installer_fatal() {
       printf 'fatal: %s\n' "$*" >&2
       exit 1
     }
     installer_info() {
       :
     }
     # shellcheck disable=SC1090
     . "$SECURITY_SCRIPT"
     DESKTOP_APPARMOR_STATE=disable
     apparmor_apply_desktop_state "$invalid_config"
   ) 2>"$disable_stderr" &&
   grep -q 'DESKTOP_APPARMOR_STATE must be enforce or complain' "$disable_stderr" &&
   ! (
     installer_fatal() {
       printf 'fatal: %s\n' "$*" >&2
       exit 1
     }
     installer_info() {
       :
     }
     # shellcheck disable=SC1090
     . "$SECURITY_SCRIPT"
     DESKTOP_APPARMOR_STATE=complain
     apparmor_apply_desktop_state "$fixed_mode_config"
   ) 2>"$fixed_mode_stderr" &&
   grep -q 'every declared managed AppArmor profile' "$fixed_mode_stderr" &&
   ! (
     installer_fatal() {
       printf 'fatal: %s\n' "$*" >&2
       exit 1
     }
     installer_info() {
       :
     }
     # shellcheck disable=SC1090
     . "$SECURITY_SCRIPT"
     DESKTOP_APPARMOR_STATE=complain
     apparmor_apply_desktop_state "$malformed_config"
   ) 2>"$malformed_stderr" &&
   grep -q 'every declared managed AppArmor profile' "$malformed_stderr"; then
  pass "installer renders all 64 placeholder rows and rejects fixed or unsupported source states"
else
  fail "installer renders all 64 placeholder rows and rejects fixed or unsupported source states"
fi

if grep -q '^NoNewPrivileges=yes$' "$BLUETOOTH_UNIT" &&
   grep -q '^NoNewPrivileges=yes$' "$HEALTH_NOTIFY_UNIT" &&
   grep -q '^NoNewPrivileges=yes$' "$PLANS_NOTIFY_UNIT" &&
   grep -q '^NoNewPrivileges=yes$' "$SOFTWARE_NOTIFY_UNIT" &&
   ! profile_block managed-bluetooth-controller-init | grep -Eq '[[:space:]][pP][uU]x,' &&
   profile_block managed-bluetooth-controller-init |
     grep -Fqx '  /sys/devices/**/rfkill[0-9]*/name r,' &&
   ! profile_block managed-labwc-health-notify | grep -Eq '[[:space:]][pP][uU]x,' &&
   ! profile_block managed-labwc-plans | grep -Eq '[[:space:]][pP][uU]x,' &&
   ! profile_block managed-managed-external-software-notify | grep -Eq '[[:space:]][pP][uU]x,' &&
   grep -q '^ExecStart=/usr/local/libexec/apparmor-managed-modes-run$' "$APPARMOR_MODE_UNIT" &&
   grep -q '^ExecReload=/usr/local/libexec/apparmor-managed-modes-run$' "$APPARMOR_MODE_UNIT" &&
   grep -q '^NoNewPrivileges=false$' "$APPARMOR_MODE_UNIT" &&
   grep -q '^ReadWritePaths=/sys/kernel/security/apparmor$' "$APPARMOR_MODE_UNIT" &&
   grep -q '^NoNewPrivileges=false$' "$SECONDBOOT_UNIT" &&
   system_profile_block managed-secondboot-cleanup |
     grep -Fqx '  /usr/sbin/update-initramfs rPx -> managed-update-initramfs,' &&
   system_profile_block managed-secondboot-cleanup |
     grep -Fqx '  /usr/bin/systemctl PUx,' &&
   system_profile_block managed-update-initramfs |
     grep -Fqx '  /usr/sbin/update-initramfs rix,' &&
   grep -q '^NoNewPrivileges=false$' "$CLAMAV_UPDATE_UNIT" &&
   grep -q '^NoNewPrivileges=false$' "$SOFTWARE_UPDATE_UNIT" &&
   grep -q '^ReadWritePaths=/sys/kernel/security/apparmor /var/cache/apparmor$' "$SOFTWARE_UPDATE_UNIT" &&
   grep -q '^NoNewPrivileges=true$' "$INCUS_HOST_UNIT" &&
   profile_block managed-apparmor-managed-modes |
     grep -Fqx '  /usr/sbin/{aa-audit,aa-complain,aa-enforce,apparmor_parser} PUx,' &&
   profile_block managed-managed-clamav-signature-update |
     grep -Fqx '  /usr/bin/{fangfrisch,freshclam} PUx,' &&
   profile_block managed-managed-external-software-update |
     grep -Fqx '  /usr/bin/{apt-get,curl,dpkg,dpkg-deb,dpkg-divert,dpkg-query,gtk-update-icon-cache,update-desktop-database} PUx,' &&
   profile_block managed-managed-external-software-update |
     grep -Fqx '  /usr/local/libexec/apparmor-managed-modes-run rPx -> managed-apparmor-managed-modes,' &&
   profile_block managed-managed-external-software-update |
     grep -Fqx '  unix,' &&
   profile_block managed-managed-external-software-update |
     grep -Fq 'gpg,gpg-agent,gpgv' &&
   profile_block managed-managed-external-software-update |
     grep -Fqx '  /etc/apt/keyrings/managed-external-software.gpg{,.tmp.*} rw,' &&
   profile_block managed-managed-external-software-update |
     grep -Fqx '  /run/user/0/ rw,' &&
   profile_block managed-managed-external-software-update |
     grep -Fqx '  /run/user/0/gnupg/** rwkl,' &&
   profile_block managed-managed-external-software-update |
     grep -Fqx '  /var/lib/software/** rwkl,' &&
   profile_block managed-incus-host-managed |
     grep -Fqx '  /usr/bin/{curl,date,grep,incus,readlink,sleep,stat,systemd-tmpfiles} rix,'; then
  pass "systemd execution settings preserve managed AppArmor transitions without filesystem namespace interference"
else
  fail "systemd execution settings preserve managed AppArmor transitions without filesystem namespace interference"
fi

if [ -x /usr/sbin/apparmor_parser ]; then
  if /usr/sbin/apparmor_parser \
       --config-file "$APPARMOR_PARSER_TEST_CONFIG" \
       -q -Q -K -T \
       -I "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d" \
       -I /etc/apparmor.d \
       -I /usr/share/apparmor \
       "$PROFILE" &&
     /usr/sbin/apparmor_parser \
       --config-file "$APPARMOR_PARSER_TEST_CONFIG" \
       -q -Q -K -T \
       -I "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d" \
       -I /etc/apparmor.d \
       -I /usr/share/apparmor \
       "$SYSTEM_PROFILE" &&
     /usr/sbin/apparmor_parser \
       --config-file "$APPARMOR_PARSER_TEST_CONFIG" \
       -q -Q -K -T \
       -I "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d" \
       -I /etc/apparmor.d \
       -I /usr/share/apparmor \
       "$CHATGPT_PROFILE"; then
    pass "AppArmor parser accepts every desktop and system wrapper attachment and transition"
  else
    fail "AppArmor parser accepts every desktop and system wrapper attachment and transition"
  fi
else
  pass "AppArmor parser is unavailable; target late-command performs the required syntax check"
fi

python_profile_coverage_ok=true
for python_wrapper in \
  labwc-freerdp-askpass \
  labwc-greeter-power \
  labwc-managed-app \
  labwc-qbittorrent \
  labwc-remote-desktop \
  labwc-sync-application-launchers \
  labwc-samsung-firmware-extract
do
  awk -v expected_profile="managed-${python_wrapper}" '
    $1 == "profile" && $2 == expected_profile { in_profile = 1 }
    in_profile && /#include <abstractions\/managed-wrapper-python>/ { found = 1 }
    in_profile && /^}/ { exit(found ? 0 : 1) }
    END { if (!in_profile) exit 1 }
  ' "$PROFILE" || python_profile_coverage_ok=false
done
perl_security_profile_ok=true
awk '
  $1 == "profile" && $2 == "managed-labwc-security-action-root" { in_profile = 1 }
  in_profile && /#include <abstractions\/managed-wrapper-perl>/ { perl_abstraction = 1 }
  in_profile && /\/usr\/local\/lib\/perl5\/site_perl\/labwc-security-action\/\*\* r,/ { module_tree = 1 }
  in_profile && /^}/ { exit(perl_abstraction && module_tree ? 0 : 1) }
  END { if (!in_profile) exit 1 }
' "$PROFILE" || perl_security_profile_ok=false
if [ "$python_profile_coverage_ok" = true ] &&
   [ "$perl_security_profile_ok" = true ]; then
  pass "Python wrappers remain isolated while the Perl security root helper can read only its module tree"
else
  fail "Python wrappers remain isolated while the Perl security root helper can read only its module tree"
fi

python_shebangs_ok=true
for python_source in \
  "$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-freerdp-askpass" \
  "$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-greeter-power" \
  "$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-managed-app" \
  "$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-qbittorrent" \
  "$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-remote-desktop" \
  "$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-sync-application-launchers" \
  "$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/libexec/labwc-samsung-firmware-extract"
do
  IFS= read -r python_shebang <"$python_source" || python_shebangs_ok=false
  [ "${python_shebang:-}" = '#!/usr/bin/python3 -I' ] ||
    python_shebangs_ok=false
done
if [ "$python_shebangs_ok" = true ]; then
  pass "Python wrappers ignore ambient Python paths before their policy code runs"
else
  fail "Python wrappers ignore ambient Python paths before their policy code runs"
fi

python_isolation_dir="$TMP_DIR/python-isolation"
mkdir -p "$python_isolation_dir"
cat >"$python_isolation_dir/argparse.py" <<'PY'
raise SystemExit(97)
PY
if PYTHONPATH="$python_isolation_dir" \
   /usr/bin/python3 -I -c 'import argparse' &&
   grep -Fqx '#!/usr/bin/python3 -I' \
     "$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-managed-app" &&
   grep -Fqx 'sys.path.insert(0, str(PACKAGE_ROOT))' \
     "$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-managed-app" &&
   ! grep -Fq 'PYTHONPATH' \
     "$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-managed-app"; then
  pass "isolated Python startup ignores writable PYTHONPATH before the wrapper adds its trusted package root"
else
  fail "isolated Python startup ignores writable PYTHONPATH before the wrapper adds its trusted package root"
fi

xssh_send="$ROOT_DIR/d-i/forky/hooks/shared/target/usr/local/bin/xssh-send"
if grep -q '^#!/bin/bash -p$' "$xssh_send" &&
   grep -q '^#!/bin/bash -p$' "$ROOT_DIR/d-i/forky/hooks/shared/target/usr/local/bin/xssh-retrieve" &&
   grep -q '^  /usr/bin/{scp,test} pux,$' "$PROFILE" &&
   grep -q '^  /usr/bin/{cat,id} rix,$' "$PROFILE" &&
   grep -q '^  /usr/bin/test -e "\$local_path" ||$' "$xssh_send" &&
   ! awk '
     $1 == "profile" && $2 == "managed-xssh-send" { in_profile = 1 }
     in_profile && /@\{HOME\}|\/data\/|\/media\/|\/mnt\/|\/run\/media\// { found = 1 }
     in_profile && /^}/ { exit(found ? 1 : 0) }
     END { if (!in_profile) exit 1 }
   ' "$PROFILE"; then
  fail "xssh-send path validation avoids pre-script Bash home access"
elif grep -q '^  /usr/bin/{scp,test} pux,$' "$PROFILE" &&
     grep -q '^  /usr/bin/test -e "\$local_path" ||$' "$xssh_send" &&
     awk '
       $1 == "profile" && $2 == "managed-xssh-send" { in_profile = 1 }
       in_profile && /@\{HOME\}|\/data\/|\/media\/|\/mnt\/|\/run\/media\// { exit 1 }
       in_profile && /^}/ { exit 0 }
       END { if (!in_profile) exit 1 }
     ' "$PROFILE"; then
  pass "xssh-send path validation avoids pre-script Bash home access"
else
  fail "xssh-send path validation avoids pre-script Bash home access"
fi

bash_isolation_dir="$TMP_DIR/bash-isolation"
mkdir -p "$bash_isolation_dir"
printf '%s\n' 'exit 96' >"$bash_isolation_dir/bash-env"
cp "$xssh_send" "$bash_isolation_dir/xssh-send"
chmod 0755 "$bash_isolation_dir/xssh-send"
if BASH_ENV="$bash_isolation_dir/bash-env" \
   "$bash_isolation_dir/xssh-send" --help >/dev/null 2>&1; then
  pass "privileged Bash parsing ignores an ambient BASH_ENV payload"
else
  fail "privileged Bash parsing ignores an ambient BASH_ENV payload"
fi

waypaper_process_policy_ok=true
python3 - "$PROFILE" <<'PY' || waypaper_process_policy_ok=false
from pathlib import Path
import re
import sys

profile_path = Path(sys.argv[1])
allowed_process_metadata_rules = {
    ("waypaper-ps", "@{PROC}/{cpuinfo,meminfo,stat} r,"),
    ("waypaper-ps", "@{PROC}/[0-9]*/{cmdline,environ,stat,status} r,"),
    ("managed-satty-runtime", "owner @{PROC}/@{pid}/cmdline r,"),
    ("whisper-server", "owner @{PROC}/@{pid}/cmdline r,"),
    ("managed-whisper-record-toggle", "owner @{PROC}/@{pid}/cmdline r,"),
}
allowed_ps_rules = {
    ("managed-waypaper", "/usr/bin/ps rCx -> waypaper-ps,"),
    ("waypaper-ps", "/usr/bin/ps mr,"),
    (
        "managed-wayland-compat-app-bwrap",
        "/usr/bin/{gsettings,ls,lscpu,lspci,pgrep,pipewire} rix,",
    ),
}
seen_ps_rules = set()
seen_process_metadata_rules = set()
profile_stack = []
errors = []

for line_number, line in enumerate(
    profile_path.read_text(encoding="utf-8").splitlines(),
    start=1,
):
    profile_match = re.match(r"^(?P<indent> *)profile\s+(?P<label>\S+).*\{$", line)
    if profile_match is not None:
        profile_stack.append(
            (len(profile_match.group("indent")), profile_match.group("label"))
        )
        continue
    if not profile_stack:
        continue

    current_profile = profile_stack[-1][1]
    stripped = line.strip()
    if re.search(r"@\{PROC\}.*(?:cmdline|environ|stat|status)", line):
        rule = (current_profile, stripped)
        seen_process_metadata_rules.add(rule)
        if rule not in allowed_process_metadata_rules:
            errors.append(
                f"{line_number}: unexpected broad process metadata grant "
                f"in {current_profile}: {stripped}"
            )

    if re.search(
        r"/usr/bin/(?:\{[^}]*,)?(?:pgrep|ps)(?:[,}\s])",
        stripped,
    ):
        rule = (current_profile, stripped)
        seen_ps_rules.add(rule)
        if rule not in allowed_ps_rules:
            errors.append(
                f"{line_number}: unexpected ps/pgrep rule in "
                f"{current_profile}: {stripped}"
            )

    close_match = re.match(r"^(?P<indent> *)\}$", line)
    if (
        close_match is not None
        and len(close_match.group("indent")) == profile_stack[-1][0]
    ):
        profile_stack.pop()

for profile_name, rule in sorted(allowed_ps_rules - seen_ps_rules):
    errors.append(f"missing reviewed process helper rule in {profile_name}: {rule}")
for profile_name, rule in sorted(
    allowed_process_metadata_rules - seen_process_metadata_rules
):
    errors.append(
        f"missing reviewed process metadata rule in {profile_name}: {rule}"
    )

if errors:
    print("\n".join(errors), file=sys.stderr)
    raise SystemExit(1)
PY

if [ ! -e "$ABSTRACTION_DIR/managed-wrapper-process-control" ] &&
   [ "$(grep -c '^  signal (send) peer=unconfined,$' "$PROFILE")" -eq 5 ] &&
   grep -Fqx '  signal (send) set=(kill term) peer=managed-labwc-managed-wayland-compat-app//managed-wayland-compat-dbus-proxy,' "$PROFILE" &&
   grep -q '^  signal (send) peer=managed-labwc-greeter-output,$' "$PROFILE" &&
   grep -q '^  signal (send) peer=managed-labwc-greeter-power,$' "$PROFILE" &&
   grep -q '^  signal (send, receive) peer=managed-bluetooth-controller-init,$' "$PROFILE" &&
   profile_block managed-wayland-compat-dbus-proxy |
     grep -Fqx '    /run/dbus/system_bus_socket rw,' &&
   profile_block managed-wayland-compat-dbus-proxy |
     grep -Fqx '    owner /run/user/[0-9]*/bus rw,' &&
   profile_block managed-wayland-compat-dbus-proxy |
     grep -Fqx '    owner /run/user/[0-9]*/labwc-{discord,zoom}-sandbox-*/{session-bus,system-bus} rw,' &&
   grep -q '^  owner /run/user/\[0-9\]\*/pipewire-\[0-9\]\* rw,$' "$PROFILE" &&
   grep -Fqx '  owner @{PROC}/[0-9]*/task/[0-9]*/comm rw,' "$PROFILE" &&
   ! profile_block managed-labwc-shutdown-hook |
     grep -Eq '^  /usr/(bin|sbin)/' &&
   [ "$(grep -Ec '/usr/bin/.*pkill' "$PROFILE")" -eq 0 ] &&
   [ "$waypaper_process_policy_ok" = true ] &&
   ! grep -Eq 'managed-wrapper-process-control' "$PROFILE" &&
   grep -Fqx '  capability sys_ptrace,' "$PROFILE" &&
   grep -Fqx '  ptrace (read) peer=managed-codex-wrapper//codex-bwrap,' "$PROFILE"; then
  pass "managed wrappers avoid broad procfs discovery while the shutdown hook performs no teardown commands"
else
  fail "managed wrappers avoid broad procfs discovery while the shutdown hook performs no teardown commands"
fi

wireguard_apparmor_ok=true
for network_profile_name in \
  managed-labwc-network-control-menu \
  managed-labwc-network-control-action \
  managed-labwc-network-control-action-root
do
  network_profile_block=$(profile_block "$network_profile_name")
  for wireguard_rule in \
    '  /data/ r,' \
    '  /data/config/ r,' \
    '  /data/config/network/ r,' \
    '  /data/config/network/wireguard/ r,' \
    '  /data/config/network/wireguard/*.conf r,'
  do
    printf '%s\n' "$network_profile_block" |
      grep -Fqx "$wireguard_rule" || wireguard_apparmor_ok=false
  done
done
network_action_profile_block=$(profile_block managed-labwc-network-control-action)
if [ "$wireguard_apparmor_ok" = true ] &&
   printf '%s\n' "$network_action_profile_block" |
     grep -Fqx '  owner @{HOME}/*.ovpn r,' &&
   ! printf '%s\n' "$network_action_profile_block" |
     grep -Fq '@{HOME}/*.conf'; then
  pass "network wrapper profiles read WireGuard imports only from the managed data root"
else
  fail "network wrapper profiles read WireGuard imports only from the managed data root"
fi
unset \
  network_action_profile_block \
  network_profile_block \
  network_profile_name \
  wireguard_apparmor_ok \
  wireguard_rule

if system_profile_block managed-firstboot |
     grep -Fqx '  /usr/{bin,sbin}/ip rix,' &&
   system_profile_block managed-podbin |
     grep -Fqx '  /usr/sbin/runuser rix,' &&
   system_profile_block managed-aptly-managed |
     grep -Fqx '  /usr/sbin/runuser rix,' &&
   system_profile_block managed-gitlab-runner-managed |
     grep -Fqx '  /usr/sbin/runuser rix,' &&
   system_profile_block managed-glab-helper |
     grep -Fqx '  /usr/sbin/runuser rix,' &&
   system_profile_block managed-glab-helper |
     grep -Fqx '  /usr/bin/{cat,getent,id,journalctl,loginctl,podman,sleep,sudo,systemctl} rix,' &&
   system_profile_block managed-aptly-prepare-env |
     grep -Fqx '  /usr/bin/aptly r,' &&
   system_profile_block managed-zram-device-setup |
     grep -Fqx '  /usr/sbin/{blkid,blockdev,cryptsetup,mkswap,modprobe,swapoff,swapon,wipefs,zramctl} rix,' &&
   ! system_profile_block managed-podbin |
     grep -Eq '/usr/bin/[^[:space:]]*runuser' &&
   ! system_profile_block managed-aptly-managed |
     grep -Eq '/usr/bin/[^[:space:]]*runuser' &&
   ! system_profile_block managed-gitlab-runner-managed |
     grep -Eq '/usr/bin/[^[:space:]]*runuser' &&
   ! system_profile_block managed-glab-helper |
     grep -Eq '/usr/bin/[^[:space:]]*runuser' &&
   profile_block managed-labwc-maintenance-menu |
     grep -Fqx '  /usr/{bin,sbin}/ip pux,' &&
   profile_block managed-labwc-network-scan-menu |
     grep -Fqx '  /usr/{bin,sbin}/ip PUx,' &&
   profile_block managed-labwc-network-control-action-root |
     grep -Fqx '  /usr/{bin,sbin}/ip PUx,' &&
   profile_block managed-labwc-network-control-action-root |
     grep -Fqx '  /usr/sbin/rfkill PUx,' &&
   profile_block managed-labwc-network-scan-action-root |
     grep -Fqx '  /usr/{bin,sbin}/ip PUx,' &&
   profile_block managed-labwc-recovery-action-root |
     grep -Fqx '  /usr/sbin/swapon PUx,' &&
   profile_block managed-labwc-security-action-root |
     grep -Fqx '  /usr/sbin/{chkrootkit,lynis} PUx,' &&
   profile_block managed-labwc-system-action-root |
     grep -Fqx '  /usr/{bin,sbin}/ip PUx,' &&
   profile_block managed-labwc-system-action-root |
     grep -Fqx '  /usr/sbin/{nvme,smartctl,swapon,zramctl} PUx,'; then
  pass "Forky package-owned command paths have exact executable grants"
else
  fail "Forky package-owned command paths have exact executable grants"
fi

if python3 - "$ROOT_DIR" "$WIFI_REGDOM_RULE" <<'PY'
from pathlib import Path
import re
import sys

root = Path(sys.argv[1])
wifi_rule = Path(sys.argv[2])
run_contracts = []
for rule_path in sorted((root / "d-i/forky/hooks").rglob("*.rules")):
    if not rule_path.is_file() or "/target/etc/udev/rules.d/" not in rule_path.as_posix():
        continue
    for line_number, line in enumerate(
        rule_path.read_text(encoding="utf-8").splitlines(),
        1,
    ):
        for match in re.finditer(r'RUN(?:\+)?="([^"]+)"', line):
            run_contracts.append(
                (
                    rule_path.relative_to(root).as_posix(),
                    line_number,
                    match.group(1),
                )
            )

expected = [
    (
        wifi_rule.relative_to(root).as_posix(),
        1,
        "/usr/sbin/iw reg set SE",
    )
]
if run_contracts != expected:
    raise SystemExit(
        "unexpected udev executable contracts: "
        + repr(run_contracts)
    )

stage_script = (
    root / "d-i/forky/scripts/late/btrfs-family.sh"
).read_text(encoding="utf-8")
stage_contract = (
    'stage_target_asset_if_path '
    '"${CPU_HOOK_ROOT}/target/etc/udev/rules.d/85-wifi-regdom.rules" '
    '"${FILE_UDEV_REGDOM_RULE:-}" '
    '"${DIR_UDEV_RULES}/85-wifi-regdom.rules" 0644'
)
if stage_contract not in stage_script:
    raise SystemExit("Wi-Fi regulatory-domain udev rule is not staged as data")
PY
then
  pass "udev RUN launchers have an explicit package-owned executable contract"
else
  fail "udev RUN launchers have an explicit package-owned executable contract"
fi

if python3 - \
     "$ROOT_DIR" \
     "$PROFILE" \
     "$SYSTEM_PROFILE" \
     "$APPARMOR_DIR/timeshift" \
     "$APPARMOR_DIR" <<'PY'
from pathlib import Path
import ast
import fnmatch
import re
import sys

root = Path(sys.argv[1])
apparmor_dir = Path(sys.argv[5])
profile_text = "\n".join(
    Path(profile_path).read_text(encoding="utf-8")
    for profile_path in sys.argv[2:5]
)
profile_matches = tuple(re.finditer(
    r"^profile (?P<label>[^ ]+) (?P<attachment>/[^ ]+)"
    r"(?: flags=[^{]+)? \{.*?^}\n",
    profile_text,
    re.MULTILINE | re.DOTALL,
))


def expand_braces(pattern):
    start = pattern.find("{")
    if start < 0:
        return [pattern]
    depth = 0
    end = -1
    for index in range(start, len(pattern)):
        if pattern[index] == "{":
            depth += 1
        elif pattern[index] == "}":
            depth -= 1
            if depth == 0:
                end = index
                break
    if end < 0:
        raise SystemExit(f"unbalanced AppArmor braces: {pattern}")
    body = pattern[start + 1:end]
    choices = []
    choice_start = 0
    nested = 0
    for index, character in enumerate(body):
        if character == "{":
            nested += 1
        elif character == "}":
            nested -= 1
        elif character == "," and nested == 0:
            choices.append(body[choice_start:index])
            choice_start = index + 1
    choices.append(body[choice_start:])
    expanded = []
    for choice in choices:
        expanded.extend(
            expand_braces(pattern[:start] + choice + pattern[end + 1:])
        )
    return expanded


profile_blocks = {}
for match in profile_matches:
    attachment_pattern = match.group("attachment")
    for attachment in {attachment_pattern, *expand_braces(attachment_pattern)}:
        profile_blocks[attachment] = match.group(0)


def expand_repository_includes(policy_text, seen=None):
    seen = set() if seen is None else seen
    expanded = [policy_text]
    for include_name in re.findall(
        r"^[ \t]*(?:#include|include(?: if exists)?)"
        r"[ \t]+<([^>]+)>",
        policy_text,
        re.MULTILINE,
    ):
        include_path = apparmor_dir / include_name
        if include_path in seen or not include_path.is_file():
            continue
        seen.add(include_path)
        expanded.append(
            expand_repository_includes(
                include_path.read_text(encoding="utf-8"),
                seen,
            )
        )
    return "\n".join(expanded)


def file_rules(policy_text):
    rules = []
    for match in re.finditer(
        r"^[ \t]*(?:owner[ \t]+)?(?P<path>/\S+)"
        r"[ \t]+(?P<access>[A-Za-z]+)"
        r"(?:[ \t]+->[ \t]+[^,]+)?,$",
        policy_text,
        re.MULTILINE,
    ):
        rules.extend(
            (rule_path, match.group("access"))
            for rule_path in expand_braces(match.group("path"))
        )
    return rules


def executable_rules(policy_text):
    return [
        rule_path
        for rule_path, access in file_rules(policy_text)
        if "x" in access.lower()
    ]

contracts = []
for source_path in sorted((root / "d-i/forky/hooks").rglob("*")):
    if not source_path.is_file():
        continue
    source_text_path = source_path.as_posix()
    marker = "/target/usr/local/"
    if marker not in source_text_path:
        continue
    installed_path = source_text_path.split("/target", 1)[1]
    if not installed_path.startswith(
        ("/usr/local/bin/", "/usr/local/sbin/", "/usr/local/libexec/")
    ):
        continue
    if installed_path == "/usr/local/sbin/nft-policy-generate.py":
        installed_path = "/usr/local/sbin/nft-policy-generate"
    elif installed_path == "/usr/local/libexec/timeshift-managed-snapshot":
        installed_path = "/{usr/bin/timeshift,usr/bin/timeshift-gtk,usr/bin/timeshift-launcher,usr/local/libexec/timeshift-managed-snapshot,etc/timeshift/backup-hooks.d/90-grub-btrfs-refresh}"
    elif installed_path.endswith(".tmpl"):
        installed_path = installed_path[:-5]
    contracts.append((source_path, (installed_path,)))

contracts.extend(
    (
        (
            root / "d-i/forky/scripts/firstboot/firstboot.sh",
            ("/usr/local/libexec/firstboot.sh",),
        ),
        (
            root / "d-i/forky/hooks/shared/target/usr/libexec/install-tools/bootprofile-apply.tmpl",
            ("/usr/libexec/install-tools/bootprofile-apply",),
        ),
        (
            root / "d-i/forky/hooks/shared/target/usr/libexec/install-tools/secure-boot-tool.tmpl",
            ("/usr/libexec/install-tools/secure-boot-tool",),
        ),
        (
            root / "d-i/forky/hooks/services/gitlab-runner/target/pool/aptly/bin/aptly",
            ("/pool/aptly/bin/aptly",),
        ),
        (
            root / "d-i/forky/hooks/services/gitlab-runner/target/pool/aptly/bin/aptly-bridge",
            ("/pool/aptly/bin/aptly-bridge",),
        ),
        (
            root / "d-i/forky/hooks/services/gitlab-runner/target/pool/aptly/bin/prepare-aptly-env.sh",
            ("/pool/aptly/bin/prepare-aptly-env.sh",),
        ),
    )
)

for module_path in sorted(
    (
        root
        / "d-i/forky/hooks/shared/target/usr/local/lib/perl5/site_perl/managed-network"
    ).rglob("*.pm")
):
    contracts.append((module_path, ("/usr/local/libexec/managed-network-run",)))
for module_path in sorted(
    (
        root
        / "d-i/forky/hooks/shared/target/usr/local/lib/perl5/site_perl/zram-writeback"
    ).rglob("*.pm")
):
    contracts.append(
        (
            module_path,
            (
                "/usr/local/libexec/zram-device-setup",
                "/usr/local/libexec/zram-writeback",
            ),
        )
    )
for module_path in sorted(
    (
        root
        / "d-i/forky/hooks/shared/target/usr/local/lib/perl5/site_perl/timeshift-managed"
    ).rglob("*.pm")
):
    contracts.append(
        (
            module_path,
            (
                "/usr/local/libexec/grub-btrfs-refresh",
                "/{usr/bin/timeshift,usr/bin/timeshift-gtk,usr/bin/timeshift-launcher,usr/local/libexec/timeshift-managed-snapshot,etc/timeshift/backup-hooks.d/90-grub-btrfs-refresh}",
            ),
        )
    )

command_patterns = (
    re.compile(r"""command -v ["']?([A-Za-z0-9_.+-]+)"""),
    re.compile(r"""require_command ["']?([A-Za-z0-9_.+-]+)"""),
    re.compile(r"""find_command\(["']([A-Za-z0-9_.+-]+)["']\)"""),
    re.compile(r"""run_optional\(["']([A-Za-z0-9_.+-]+)["']"""),
    re.compile(r"""shutil\.which\(["']([A-Za-z0-9_.+-]+)["']\)"""),
    re.compile(r"""\$\(\s*([A-Za-z][A-Za-z0-9_.+-]*)(?=[\s)])"""),
    re.compile(r"""\$\(\s*(?:/[A-Za-z0-9_.+-]+)+/([A-Za-z0-9_.+-]+)(?=[\s)])"""),
)
ignored_commands = {
    "case", "command", "do", "done", "echo", "else", "esac", "exit",
    "export", "false", "fi", "field", "for", "if", "printf", "read",
    "return", "set", "shift", "test", "then", "trap", "true", "unset",
    "while",
}
forky_command_paths = {
    "chkrootkit": ("/usr/sbin/chkrootkit",),
    "ip": ("/usr/bin/ip", "/usr/sbin/ip"),
    "lynis": ("/usr/sbin/lynis",),
    "mkswap": ("/usr/sbin/mkswap",),
    "nvme": ("/usr/sbin/nvme",),
    "rfkill": ("/usr/sbin/rfkill",),
    "runuser": ("/usr/sbin/runuser",),
    "smartctl": ("/usr/sbin/smartctl",),
    "swapoff": ("/usr/sbin/swapoff",),
    "swapon": ("/usr/sbin/swapon",),
    "zramctl": ("/usr/sbin/zramctl",),
}
indirect_command_contracts = {
    (
        "d-i/forky/hooks/services/gitlab-runner/target/pool/aptly/bin/"
        "prepare-aptly-env.sh",
        "aptly",
    ): {
        "read": ("/usr/bin/aptly", "/pool/aptly/bin/aptly"),
        "execute": (),
    },
    (
        "d-i/forky/hooks/shared/target/usr/local/bin/tpm2-enroll-launch",
        "sudo",
    ): {
        "read": ("/usr/bin/sudo", "/usr/local/sbin/tpm2-enroll.sh"),
        "execute": ("/usr/local/bin/labwc-terminal",),
    },
}
missing = []
shared_shell_functions = set(
    re.findall(
        r"^([A-Za-z_][A-Za-z0-9_]*)\(\)\s*[\{\(]",
        (
            root
            / "d-i/forky/hooks/services/gitlab-runner/target/pool/aptly/bin/prepare-aptly-env.sh"
        ).read_text(encoding="utf-8"),
        re.MULTILINE,
    )
)
def dotted_name(node):
    if isinstance(node, ast.Name):
        return node.id
    if isinstance(node, ast.Attribute):
        prefix = dotted_name(node.value)
        return f"{prefix}.{node.attr}" if prefix else node.attr
    return ""


def resolved_string(node, constants):
    if isinstance(node, ast.Constant) and isinstance(node.value, str):
        return node.value
    if isinstance(node, ast.Name):
        return constants.get(node.id)
    return None


for source_path, owner_attachments in sorted(
    contracts,
    key=lambda contract: str(contract[0]),
):
    if b"\0" in source_path.read_bytes():
        continue
    source_text = source_path.read_text(encoding="utf-8")
    installed_path = owner_attachments[0]
    profile_block = "\n".join(
        profile_blocks.get(owner_attachment, "")
        for owner_attachment in owner_attachments
    )
    if not profile_block:
        missing.append(
            f"{source_path.relative_to(root)}: missing owner profile "
            + ", ".join(owner_attachments)
        )
        continue
    expanded_policy = expand_repository_includes(profile_block)
    allowed_files = file_rules(expanded_policy)
    allowed_executables = executable_rules(expanded_policy)
    functions = set(
        re.findall(
            r"^([A-Za-z_][A-Za-z0-9_]*)\(\)\s*[\{\(]",
            source_text,
            re.MULTILINE,
        )
    )
    functions.update(shared_shell_functions)
    source_key = source_path.relative_to(root).as_posix()
    commands = set()
    for command_pattern in command_patterns:
        commands.update(command_pattern.findall(source_text))
    if "python3" in source_text.splitlines()[0]:
        syntax_tree = ast.parse(source_text, filename=str(source_path))
        constants = {}
        for statement in syntax_tree.body:
            if isinstance(statement, ast.Assign):
                value = resolved_string(statement.value, constants)
                targets = statement.targets
            elif isinstance(statement, ast.AnnAssign):
                value = resolved_string(statement.value, constants)
                targets = (statement.target,)
            else:
                continue
            if value is None:
                continue
            for target in targets:
                if isinstance(target, ast.Name):
                    constants[target.id] = value
        for node in ast.walk(syntax_tree):
            if not isinstance(node, ast.Call):
                continue
            call_name = dotted_name(node.func)
            if call_name == "shutil.which" and node.args:
                executable = resolved_string(node.args[0], constants)
            elif call_name in {
                "os.execl",
                "os.execlp",
                "os.execv",
                "os.execve",
                "os.execvp",
                "os.execvpe",
                "subprocess.call",
                "subprocess.check_call",
                "subprocess.check_output",
                "subprocess.Popen",
                "subprocess.run",
            } and node.args:
                command_node = node.args[0]
                if isinstance(command_node, (ast.List, ast.Tuple)) and command_node.elts:
                    command_node = command_node.elts[0]
                executable = resolved_string(command_node, constants)
            else:
                continue
            if executable:
                commands.add(Path(executable).name)
    for command_loop in re.finditer(
        r"""for (?:command_name|required_command) in[ \t]*(.*?)(?:\n[ \t]*do|;[ \t]*do)""",
        source_text,
        re.DOTALL,
    ):
        for command_token in re.findall(
            r"""(?:/[A-Za-z0-9_.+-]+)+|(?<![$])\b[A-Za-z][A-Za-z0-9_.+-]*\b""",
            command_loop.group(1),
        ):
            commands.add(command_token.rsplit("/", 1)[-1])
    for perl_program in re.findall(
        r"""(?:system\s*\(\s*|_program\s*\(\s*)["']([^"']+)["']""",
        source_text,
    ):
        commands.add(Path(perl_program).name)
    for command in sorted(commands - ignored_commands - functions):
        indirect_contract = indirect_command_contracts.get(
            (source_key, command)
        )
        if indirect_contract is not None:
            uncovered_read_paths = [
                required_path
                for required_path in indirect_contract["read"]
                if not any(
                    "r" in access.lower()
                    and fnmatch.fnmatchcase(required_path, allowed_path)
                    for allowed_path, access in allowed_files
                )
            ]
            uncovered_execute_paths = [
                required_path
                for required_path in indirect_contract["execute"]
                if not any(
                    fnmatch.fnmatchcase(required_path, allowed_path)
                    for allowed_path in allowed_executables
                )
            ]
            if uncovered_read_paths or uncovered_execute_paths:
                missing.append(
                    f"{source_key} [{', '.join(owner_attachments)}]: "
                    f"{command} indirect contract lacks "
                    + ", ".join(
                        uncovered_read_paths + uncovered_execute_paths
                    )
                )
            continue
        required_paths = forky_command_paths.get(command)
        if required_paths is not None:
            uncovered_paths = [
                required_path
                for required_path in required_paths
                if not any(
                    fnmatch.fnmatchcase(required_path, allowed_path)
                    for allowed_path in allowed_executables
                )
            ]
            if uncovered_paths:
                missing.append(
                    f"{source_path.relative_to(root)} "
                    f"[{', '.join(owner_attachments)}]: {command} requires "
                    + ", ".join(uncovered_paths)
                )
            continue
        if not any(
            fnmatch.fnmatchcase(
                command,
                allowed_path.rsplit("/", 1)[-1],
            )
            for allowed_path in allowed_executables
        ):
            missing.append(
                f"{source_path.relative_to(root)} "
                f"[{', '.join(owner_attachments)}]: {command}"
            )

if missing:
    print("literal wrapper commands missing from AppArmor profiles:", file=sys.stderr)
    print("\n".join(missing), file=sys.stderr)
    raise SystemExit(1)
PY
then
  pass "literal wrapper command dependencies have executable path grants in their profile"
else
  fail "literal wrapper command dependencies have executable path grants in their profile"
fi

firstboot_profile_block=$(system_profile_block managed-firstboot)
apt_refresh_profile_block=$(system_profile_block managed-apt-refresh-lists)
swap_fallback_profile_block=$(system_profile_block managed-swap-fallback-setup)
aptly_managed_profile_block=$(system_profile_block managed-aptly-managed)
gitlab_runner_profile_block=$(system_profile_block managed-gitlab-runner-managed)
aptly_env_profile_block=$(system_profile_block managed-aptly-prepare-env)
if grep -Fq 'stage_target_asset "$(installer_repo_join_var DIR_SCRIPTS_FIRSTBOOT "${firstboot_stage}")" "${DIR_FIRSTBOOT_LIB}/${firstboot_stage}" 0755' \
     "$FIRSTBOOT_STAGE_SCRIPT" &&
   grep -Fqx '  "$script_path" >>"$FIRSTBOOT_LOG_FILE" 2>&1' "$FIRSTBOOT_WRAPPER" &&
   printf '%s\n' "$firstboot_profile_block" |
     grep -Fqx '  /usr/local/lib/firstboot.d/{01-early,02-collect,03-network,04-validation,05-cleanup}.sh rix,' &&
   printf '%s\n' "$firstboot_profile_block" |
     grep -Fqx '  /usr/local/lib/firstboot.d/logging.sh r,' &&
   grep -Fqx 'LOG_HELPER="/usr/libexec/install-tools/system-log.sh"' "$APT_REFRESH_WRAPPER" &&
   grep -Fqx 'LOG_HELPER="/usr/libexec/install-tools/system-log.sh"' "$SWAP_FALLBACK_WRAPPER" &&
   printf '%s\n' "$apt_refresh_profile_block" |
     grep -Fqx '  /usr/libexec/install-tools/system-log.sh r,' &&
   printf '%s\n' "$swap_fallback_profile_block" |
     grep -Fqx '  /usr/libexec/install-tools/system-log.sh r,' &&
   grep -Fq 'source /pool/aptly/bin/prepare-aptly-env.sh' "$APTLY_MANAGED_WRAPPER" &&
   grep -Fq 'source /pool/aptly/bin/prepare-aptly-env.sh' "$GITLAB_RUNNER_MANAGED_WRAPPER" &&
   printf '%s\n' "$aptly_managed_profile_block" |
     grep -Fqx '  /pool/aptly/bin/prepare-aptly-env.sh r,' &&
   printf '%s\n' "$gitlab_runner_profile_block" |
     grep -Fqx '  /pool/aptly/bin/prepare-aptly-env.sh r,' &&
   printf '%s\n' "$aptly_env_profile_block" |
     grep -Fqx '  /pool/aptly/bin/prepare-aptly-env.sh rix,' &&
   grep -q '^profile timeshift /{usr/bin/timeshift,usr/bin/timeshift-gtk,usr/bin/timeshift-launcher,usr/local/libexec/timeshift-managed-snapshot,etc/timeshift/backup-hooks.d/90-grub-btrfs-refresh} ' \
     "$TIMESHIFT_PROFILE" &&
   grep -Fqx '/** rix,' "$TIMESHIFT_RUNTIME" &&
   grep -Fqx 'if ! systemctl --no-block start grub-btrfs-refresh.service; then' \
     "$TIMESHIFT_GRUB_HOOK" &&
   grep -Fqx 'ExecStart=/usr/local/libexec/grub-btrfs-refresh --wait' \
     "$GRUB_BTRFS_REFRESH_UNIT" &&
   grep -q '^profile managed-grub-btrfs-refresh /usr/local/libexec/grub-btrfs-refresh ' \
     "$SYSTEM_PROFILE"; then
  pass "staged child helpers have explicit confined inheritance or exact transition contracts"
else
  fail "staged child helpers have explicit confined inheritance or exact transition contracts"
fi
unset \
  aptly_env_profile_block \
  aptly_managed_profile_block \
  apt_refresh_profile_block \
  firstboot_profile_block \
  gitlab_runner_profile_block \
  swap_fallback_profile_block

if python3 - "$PROFILE" <<'PY' &&
from pathlib import Path
import re
import sys

profile_path = Path(sys.argv[1])
for line_number, line in enumerate(
    profile_path.read_text(encoding="utf-8").splitlines(),
    1,
):
    match = re.search(r"/usr/bin/\{([^}]*)\}", line)
    if match is None:
        continue
    commands = set(match.group(1).split(","))
    if "awk" in commands and not {"awk", "gawk", "mawk", "nawk"} <= commands:
        raise SystemExit(f"{profile_path}:{line_number}: incomplete awk alternatives")
PY
   profile_block managed-labwc-output-watch |
     grep -Fqx '  /usr/bin/wayland-info pux,' &&
   profile_block managed-labwc-output-refresh |
     grep -Fqx '  /usr/bin/{systemctl,wlopm,wlr-randr} pux,' &&
   profile_block managed-labwc-output-refresh |
     grep -Fqx '  owner /run/user/[0-9]*/labwc-fuzzel.{lock,pid} rwk,' &&
   profile_block managed-labwc-brightness-control |
     grep -Fqx '  /usr/bin/{awk,gawk,mawk,nawk} rix,' &&
   profile_block managed-labwc-chatgpt |
     grep -Fqx '  /usr/bin/{chmod,id,mkdir,readlink,stat} rix,' &&
   grep -Fqx '/usr/lib/@{multiarch}/webkit2gtk-4.1/WebKit{Network,Web}Process rix,' \
     "$WEBKIT_RUNTIME" &&
   grep -Fqx '  #include <abstractions/managed-webkit-runtime>' "$GRIDLINE_PROFILE" &&
   grep -Fqx '  /usr/bin/bwrap rCx -> webkit-bwrap,' "$GRIDLINE_PROFILE" &&
   grep -Fqx '  profile webkit-bwrap flags=(attach_disconnected, mediate_deleted) {' "$GRIDLINE_PROFILE" &&
   grep -Fqx '    #include <abstractions/managed-bwrap-common>' "$GRIDLINE_PROFILE" &&
   grep -Fqx '    #include <abstractions/managed-webkit-runtime>' "$GRIDLINE_PROFILE" &&
   grep -Fqx '  #include <abstractions/managed-webkit-runtime>' "$QOREDB_PROFILE" &&
   profile_block managed-wayland-compat-app-bwrap |
     grep -Fqx '    /usr/bin/{env,expr,xdg-open} rix,' &&
   profile_block managed-wayland-compat-app-bwrap |
     grep -Fqx '    deny /usr/bin/chromium rx,' &&
   grep -Fqx '/usr/bin/{awk,basename,cat,cut,dbus-send,dirname,gawk,getconf,getopt,grep,head,lsb_release,mawk,mkdir,mv,nawk,readlink,realpath,sed,sort,touch,tr,uname,xdg-mime,xdg-settings,xprop} rix,' \
     "$ABSTRACTION_DIR/managed-desktop-runtime" &&
   ! grep -R -Fq '//null' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d" &&
   ! grep -Fq 'Gtk.Image.new_from_icon_name' \
     "$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-greeter-power"; then
  pass "observed Debian helper executables avoid complain-mode null profiles"
else
  fail "observed Debian helper executables avoid complain-mode null profiles"
fi

GREETER_SOURCE="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-greeter-session.tmpl"
GREETER_CLIENT_SOURCE="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/libexec/labwc-greeter-client"
GREETER_OUTPUT_SOURCE="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-greeter-output"
greeter_profile_block=$(
  profile_block managed-labwc-greeter-session
)
greeter_client_profile_block=$(profile_block managed-labwc-greeter-client)
greeter_output_profile_block=$(profile_block managed-labwc-greeter-output)
greeter_power_profile_block=$(profile_block managed-labwc-greeter-power)
if grep -Fqx 'greeter_uid=$(id -u)' "$GREETER_SOURCE" &&
   grep -Fqx 'greeter_session_root=$(mktemp -d "${greeter_runtime_parent}/labwc-greeter.${greeter_uid}.XXXXXX")' "$GREETER_SOURCE" &&
   grep -Fqx 'install -d -m 0700 \' "$GREETER_SOURCE" &&
   ! grep -Fq 'greeter_start_delay' "$GREETER_SOURCE" &&
   grep -Fqx 'use IO::Select;' "$GREETER_OUTPUT_SOURCE" &&
   printf '%s\n' "$greeter_profile_block" |
     grep -Fqx '  /usr/bin/{cat,chmod,id,install,mktemp,rm} rix,' &&
   printf '%s\n' "$greeter_profile_block" |
     grep -Fqx '  /usr/bin/labwc pux,' &&
   printf '%s\n' "$greeter_profile_block" |
     grep -Fqx '  /usr/local/share/labwc-greeter/{autostart,rc.xml} r,' &&
   printf '%s\n' "$greeter_profile_block" |
     grep -Fqx '  /run/user/[0-9]*/labwc-greeter.*/ rw,' &&
   printf '%s\n' "$greeter_profile_block" |
     grep -Fqx '  /run/user/[0-9]*/labwc-greeter.*/** rwkl,' &&
   printf '%s\n' "$greeter_profile_block" |
     grep -Fqx '  /tmp/labwc-greeter.*/ rw,' &&
   printf '%s\n' "$greeter_profile_block" |
     grep -Fqx '  /tmp/labwc-greeter.*/** rwkl,' &&
   printf '%s\n' "$greeter_output_profile_block" |
     grep -Fqx '  /run/user/[0-9]*/labwc-greeter.*/state/** rwkl,' &&
   printf '%s\n' "$greeter_output_profile_block" |
     grep -Fqx '  /tmp/labwc-greeter.*/state/** rwkl,' &&
   printf '%s\n' "$greeter_output_profile_block" |
     grep -Fqx '  #include <abstractions/managed-wrapper-perl>' &&
   printf '%s\n' "$greeter_power_profile_block" |
     grep -Fqx '  /run/user/[0-9]*/labwc-greeter.*/{cache,config,data,gnupg,home,state,tmp}/** rwkl,' &&
   printf '%s\n' "$greeter_power_profile_block" |
     grep -Fqx '  /tmp/labwc-greeter.*/{cache,config,data,gnupg,home,state,tmp}/** rwkl,' &&
   grep -Fqx '/usr/bin/gtkgreet -l -s /etc/greetd/gtkgreet.css -c "$LABWC_GREETER_SESSION_COMMAND"' \
     "$GREETER_CLIENT_SOURCE" &&
   printf '%s\n' "$greeter_client_profile_block" |
     grep -Fqx '  /usr/bin/gtkgreet pux,' &&
   printf '%s\n' "$greeter_client_profile_block" |
     grep -Fqx '  /usr/local/bin/labwc-greeter-output rPx -> managed-labwc-greeter-output,' &&
   printf '%s\n' "$greeter_client_profile_block" |
     grep -Fqx '  /usr/local/bin/labwc-greeter-power rPx -> managed-labwc-greeter-power,' &&
   printf '%s\n' "$greeter_client_profile_block" |
     grep -Fqx '  signal (send) peer=managed-labwc-greeter-output,' &&
   printf '%s\n' "$greeter_client_profile_block" |
     grep -Fqx '  signal (send) peer=managed-labwc-greeter-power,' &&
   printf '%s\n' "$greeter_output_profile_block" |
     grep -Fqx '  signal (receive) peer=managed-labwc-greeter-client,' &&
   printf '%s\n' "$greeter_power_profile_block" |
     grep -Fqx '  signal (receive) peer=managed-labwc-greeter-client,' &&
   printf '%s\n' "$greeter_power_profile_block" |
     grep -Fqx '  /usr/local/sbin/greetd-power-action rPx -> managed-greetd-power-action,'; then
  pass "greeter wrapper profiles cover startup helpers and their private runtime tree"
else
  fail "greeter wrapper profiles cover startup helpers and their private runtime tree"
fi
unset greeter_output_profile_block greeter_power_profile_block greeter_profile_block

INCUS_UNIT="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/systemd/system/incus-host-managed.service"
QEMU_LATE="$ROOT_DIR/d-i/forky/scripts/late/qemu.sh"
if grep -q '^profile managed-incus-host-managed /usr/local/libexec/incus-host-managed ' "$PROFILE" &&
   grep -q '^profile managed-tpm2-enroll-launch /usr/local/bin/tpm2-enroll-launch ' "$PROFILE" &&
   grep -q '^profile managed-tpm2-enroll /usr/local/sbin/tpm2-enroll[.]sh ' "$PROFILE" &&
   grep -q '^ExecStart=/usr/local/libexec/incus-host-managed$' "$INCUS_UNIT" &&
   grep -q 'run_in_target "prepare direct QEMU and Incus storage roots"' "$QEMU_LATE" &&
   ! grep -q 'ExecStart=/bin/sh /usr/local/libexec/incus-host-managed' "$INCUS_UNIT"; then
  pass "desktop sbin and TPM helpers enter their profiles through direct execution"
else
  fail "desktop sbin and TPM helpers enter their profiles through direct execution"
fi

[ "$FAIL_COUNT" -eq 0 ]
