"""Inner Cage application supervisor, executed only inside Bubblewrap."""

from __future__ import annotations

import os
import re
import signal
import stat
import subprocess
import sys
from typing import NoReturn

ALLOWED_APPLICATIONS = {
    "discord": "/opt/discord/Discord",
    "zoom": "/usr/bin/zoom",
}
ALLOWED_MODES = {"launch", "intel", "nvidia"}
SYSTEM_OWNER_ANCHOR = "/usr"
PRIVATE_RUNTIME_ROOT = "/opt/xwayland"
PRIVATE_RUNTIME_LIBRARY_DIRECTORY = (
    f"{PRIVATE_RUNTIME_ROOT}/usr/lib/x86_64-linux-gnu"
)
XWAYLAND_BINARY = f"{PRIVATE_RUNTIME_ROOT}/usr/bin/Xwayland"
XWAYLAND_PROTOCOL = f"{PRIVATE_RUNTIME_ROOT}/usr/lib/xorg/protocol.txt"
XKBCOMP_BINARY = "/usr/bin/xkbcomp"
OUTER_WAYLAND_DISPLAY_ENVIRONMENT = "LABWC_MANAGED_OUTER_WAYLAND_DISPLAY"
EXPECTED_CAGE_WLROOTS_ENVIRONMENT = {
    "WLR_BACKENDS": "wayland",
    "WLR_WL_OUTPUTS": "1",
}
PRIVATE_RUNTIME_LIBRARY_NAMES = (
    "libXau.so.6",
    "libXdmcp.so.6",
    "libXfont2.so.2",
    "libfontenc.so.1",
    "libxcb-cursor.so.0",
    "libxcb-image.so.0",
    "libxcb-render-util.so.0",
    "libxcb-render.so.0",
    "libxcb-shm.so.0",
    "libxcb-util.so.1",
    "libxcb.so.1",
    "libxcvt.so.0",
    "libxshmfence.so.1",
)
PRIVATE_APPLICATION_LIBRARY_DIRECTORIES = {
    "discord": (PRIVATE_RUNTIME_LIBRARY_DIRECTORY, "/opt/discord"),
    "zoom": (PRIVATE_RUNTIME_LIBRARY_DIRECTORY,),
}
DYNAMIC_LOADER_ENVIRONMENT_TO_CLEAR = (
    "LD_AUDIT",
    "LD_DEBUG",
    "LD_PRELOAD",
)
FORBIDDEN_INHERITED_X11_ENVIRONMENT = (
    "DESKTOP_STARTUP_ID",
    "SESSION_MANAGER",
    "WINDOWID",
    "XAUTHORITY",
    "XWAYLAND",
    "XWAYLAND_FORCE_SCALE",
    "XWAYLAND_NO_GLAMOR",
    "XWAYLAND_PATH",
    "XWAYLAND_RESTART_DELAY",
    "_XWAYLAND_GLOBAL_OUTPUT_SCALE",
)
APPLICATION_X11_CONTROL_ENVIRONMENT_TO_CLEAR = (
    OUTER_WAYLAND_DISPLAY_ENVIRONMENT,
    "WLR_XWAYLAND",
    *EXPECTED_CAGE_WLROOTS_ENVIRONMENT,
    *FORBIDDEN_INHERITED_X11_ENVIRONMENT,
)
X11_SOCKET_DIRECTORY = "/tmp/.X11-unix"
MAX_DISPLAY_NUMBER = 65535
TERMINATION_TIMEOUT_SECONDS = 3.0

_active_processes: list[subprocess.Popen[bytes]] = []
_received_signal: int | None = None


class CompatibilityRuntimeError(RuntimeError):
    """A bounded failure suitable for the outer managed launcher."""


def fail(message: str) -> NoReturn:
    raise CompatibilityRuntimeError(message)


def sandbox_system_owner() -> tuple[int, int]:
    try:
        metadata = os.lstat(SYSTEM_OWNER_ANCHOR)
    except OSError as exc:
        fail(f"private compatibility system owner is unavailable: {exc}")
    if (
        stat.S_ISLNK(metadata.st_mode)
        or not stat.S_ISDIR(metadata.st_mode)
        or metadata.st_mode & 0o022
    ):
        fail("private compatibility system owner is unsafe")
    return metadata.st_uid, metadata.st_gid


def require_system_owned_file(
    label: str,
    path: str,
    *,
    system_owner: tuple[int, int],
    executable: bool = False,
) -> None:
    try:
        metadata = os.lstat(path)
    except OSError as exc:
        fail(f"{label} is unavailable: {path}: {exc}")
    if (
        stat.S_ISLNK(metadata.st_mode)
        or not stat.S_ISREG(metadata.st_mode)
        or (metadata.st_uid, metadata.st_gid) != system_owner
        or metadata.st_mode & 0o022
        or not os.access(path, os.R_OK)
        or (executable and not os.access(path, os.X_OK))
    ):
        fail(
            f"{label} must be a system-owned regular file not writable by "
            f"group or others: {path}"
        )


def require_system_owned_symlink(
    label: str,
    path: str,
    expected_target: str,
    *,
    system_owner: tuple[int, int],
) -> None:
    try:
        metadata = os.lstat(path)
    except OSError as exc:
        fail(f"{label} is unavailable: {path}: {exc}")
    if (
        not stat.S_ISLNK(metadata.st_mode)
        or (metadata.st_uid, metadata.st_gid) != system_owner
        or os.path.realpath(path) != expected_target
    ):
        fail(f"{label} is unsafe: {path}")
    require_system_owned_file(
        f"{label} target",
        expected_target,
        system_owner=system_owner,
    )


def require_private_runtime_library(
    library_name: str,
    *,
    system_owner: tuple[int, int],
) -> None:
    if (
        not library_name
        or "/" in library_name
        or library_name in {".", ".."}
    ):
        fail(f"private compatibility library name is invalid: {library_name!r}")
    library_path = os.path.join(PRIVATE_RUNTIME_LIBRARY_DIRECTORY, library_name)
    try:
        metadata = os.lstat(library_path)
    except OSError as exc:
        fail(f"private compatibility library is unavailable: {library_path}: {exc}")
    if stat.S_ISREG(metadata.st_mode):
        require_system_owned_file(
            "private compatibility library",
            library_path,
            system_owner=system_owner,
        )
        return
    if not stat.S_ISLNK(metadata.st_mode):
        fail(f"private compatibility library entry is unsafe: {library_path}")

    library_target = os.path.realpath(library_path)
    if (
        os.path.commonpath((PRIVATE_RUNTIME_LIBRARY_DIRECTORY, library_target))
        != PRIVATE_RUNTIME_LIBRARY_DIRECTORY
    ):
        fail(
            "private compatibility library target escapes its managed "
            f"directory: {library_target}"
        )
    require_system_owned_symlink(
        "private compatibility library",
        library_path,
        library_target,
        system_owner=system_owner,
    )


def application_process_environment(app_name: str) -> dict[str, str]:
    environment = dict(os.environ)
    for name in (
        *DYNAMIC_LOADER_ENVIRONMENT_TO_CLEAR,
        *APPLICATION_X11_CONTROL_ENVIRONMENT_TO_CLEAR,
    ):
        environment.pop(name, None)
    library_directories = PRIVATE_APPLICATION_LIBRARY_DIRECTORIES.get(app_name)
    if library_directories is None:
        fail(
            "private compatibility runtime rejected library policy for "
            f"{app_name}"
        )
    environment["LD_LIBRARY_PATH"] = os.pathsep.join(library_directories)
    return environment


def validate_wayland_socket_name(label: str, value: str) -> str:
    if (
        not value
        or len(value) > 128
        or re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]*", value) is None
    ):
        fail(f"private compatibility runtime received an invalid {label}")
    return value


def require_user_wayland_socket(runtime_directory: str, socket_name: str) -> None:
    socket_path = os.path.join(runtime_directory, socket_name)
    try:
        metadata = os.lstat(socket_path)
    except OSError as exc:
        fail(f"private compatibility Wayland socket is unavailable: {exc}")
    if (
        stat.S_ISLNK(metadata.st_mode)
        or not stat.S_ISSOCK(metadata.st_mode)
        or metadata.st_uid != os.getuid()
    ):
        fail("private compatibility Wayland socket is unsafe")


def require_cage_wayland_socket() -> None:
    runtime_directory = f"/run/user/{os.getuid()}"
    if os.environ.get("XDG_RUNTIME_DIR") != runtime_directory:
        fail("private compatibility runtime received an unexpected XDG_RUNTIME_DIR")
    for name, expected_value in EXPECTED_CAGE_WLROOTS_ENVIRONMENT.items():
        if os.environ.get(name) != expected_value:
            fail(
                "private compatibility runtime received an unexpected "
                f"{name}"
            )
    outer_wayland_display = validate_wayland_socket_name(
        "outer Wayland socket name",
        os.environ.get(OUTER_WAYLAND_DISPLAY_ENVIRONMENT, ""),
    )
    cage_wayland_display = validate_wayland_socket_name(
        "Cage Wayland socket name",
        os.environ.get("WAYLAND_DISPLAY", ""),
    )
    if cage_wayland_display == outer_wayland_display:
        fail("private compatibility runtime did not receive Cage's nested Wayland socket")
    require_user_wayland_socket(runtime_directory, outer_wayland_display)
    require_user_wayland_socket(runtime_directory, cage_wayland_display)


def require_cage_x11_display() -> str:
    if os.environ.get("WLR_XWAYLAND") != XWAYLAND_BINARY:
        fail("private compatibility runtime received an unexpected WLR_XWAYLAND")
    inherited_x11_names = tuple(
        name
        for name in FORBIDDEN_INHERITED_X11_ENVIRONMENT
        if os.environ.get(name)
    )
    if inherited_x11_names:
        fail(
            "private compatibility runtime rejected inherited X11 state: "
            + ", ".join(inherited_x11_names)
        )
    display = os.environ.get("DISPLAY", "")
    display_match = re.fullmatch(r":(0|[1-9][0-9]{0,4})", display)
    if display_match is None or int(display_match.group(1)) > MAX_DISPLAY_NUMBER:
        fail("private compatibility runtime received an invalid Cage DISPLAY")
    return display_match.group(1)


def require_private_x11_socket_directory() -> None:
    try:
        metadata = os.lstat(X11_SOCKET_DIRECTORY)
    except OSError as exc:
        fail(f"cannot validate the private compatibility socket directory: {exc}")
    if (
        stat.S_ISLNK(metadata.st_mode)
        or not stat.S_ISDIR(metadata.st_mode)
        or metadata.st_uid != os.getuid()
        or stat.S_IMODE(metadata.st_mode) != 0o1777
    ):
        fail("private compatibility socket directory is unsafe")


def require_private_x11_socket(display_number: str) -> None:
    socket_path = os.path.join(X11_SOCKET_DIRECTORY, f"X{display_number}")
    try:
        metadata = os.lstat(socket_path)
    except OSError as exc:
        fail(f"cannot validate the private compatibility socket: {exc}")
    if (
        stat.S_ISLNK(metadata.st_mode)
        or not stat.S_ISSOCK(metadata.st_mode)
        or metadata.st_uid != os.getuid()
    ):
        fail("private compatibility socket is unsafe")


def stop_process(process: subprocess.Popen[bytes] | None) -> None:
    if process is None or process.poll() is not None:
        return
    process.terminate()
    try:
        process.wait(timeout=TERMINATION_TIMEOUT_SECONDS)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait(timeout=TERMINATION_TIMEOUT_SECONDS)


def handle_signal(signum: int, _frame: object) -> None:
    global _received_signal
    _received_signal = signum
    for process in reversed(_active_processes):
        if process.poll() is None:
            try:
                process.send_signal(signum)
            except ProcessLookupError:
                pass


def register_signal_handlers() -> None:
    for signum in (signal.SIGHUP, signal.SIGINT, signal.SIGTERM):
        signal.signal(signum, handle_signal)


def parse_arguments(arguments: list[str]) -> tuple[str, str, list[str]]:
    if len(arguments) < 4 or arguments[2] != "--":
        fail("private compatibility runtime received malformed arguments")
    app_name, mode = arguments[0], arguments[1]
    child_argv = arguments[3:]
    expected_executable = ALLOWED_APPLICATIONS.get(app_name)
    if expected_executable is None or mode not in ALLOWED_MODES:
        fail("private compatibility runtime rejected the requested application")
    if not child_argv or child_argv[0] != expected_executable:
        fail("private compatibility runtime rejected the application executable")
    return app_name, mode, child_argv


def run(arguments: list[str]) -> int:
    app_name, _mode, child_argv = parse_arguments(arguments)
    if os.geteuid() == 0:
        fail("private compatibility runtime must not run as root")

    system_owner = sandbox_system_owner()
    require_cage_wayland_socket()
    display_number = require_cage_x11_display()
    require_private_x11_socket_directory()
    require_private_x11_socket(display_number)
    require_system_owned_file(
        "private compatibility Xwayland executable",
        XWAYLAND_BINARY,
        system_owner=system_owner,
        executable=True,
    )
    require_system_owned_file(
        "private compatibility Xwayland protocol data",
        XWAYLAND_PROTOCOL,
        system_owner=system_owner,
    )
    require_system_owned_file(
        "private compatibility XKB compiler",
        XKBCOMP_BINARY,
        system_owner=system_owner,
        executable=True,
    )
    for library_name in PRIVATE_RUNTIME_LIBRARY_NAMES:
        require_private_runtime_library(
            library_name,
            system_owner=system_owner,
        )

    register_signal_handlers()
    application: subprocess.Popen[bytes] | None = None
    try:
        application_environment = application_process_environment(app_name)
        expected_display = f":{display_number}"
        if application_environment.get("DISPLAY") != expected_display:
            fail("private compatibility runtime lost Cage's DISPLAY")
        application = subprocess.Popen(
            child_argv,
            env=application_environment,
            stdin=None,
            stdout=None,
            stderr=None,
            close_fds=True,
        )
        _active_processes.append(application)
        returncode = application.wait()
        if returncode < 0:
            return 128 + -returncode
        return returncode
    finally:
        stop_process(application)
        _active_processes.clear()


def main(arguments: list[str] | None = None) -> int:
    try:
        return run(list(arguments if arguments is not None else sys.argv[1:]))
    except CompatibilityRuntimeError as exc:
        print(f"fatal: {exc}", file=sys.stderr)
        if _received_signal is not None:
            return 128 + _received_signal
        return 1
    except (OSError, UnicodeError, ValueError) as exc:
        print(
            f"fatal: private Zoom/Discord compatibility runtime failed: {exc}",
            file=sys.stderr,
        )
        if _received_signal is not None:
            return 128 + _received_signal
        return 1
