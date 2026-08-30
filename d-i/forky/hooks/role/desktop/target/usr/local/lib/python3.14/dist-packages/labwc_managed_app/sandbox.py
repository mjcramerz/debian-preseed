"""D-Bus mediation and Bubblewrap launch paths for managed applications."""

from __future__ import annotations

import fcntl
import hashlib
import json
import os
import pathlib
import re
import select
import shutil
import signal
import socket
import stat
import subprocess
import tempfile
import time
import uuid

from .commands import build_argv, normalize_managed_arguments, resolved_executable, validate_managed_arguments
from .environment import build_environment, resolve_home_relative_path
from .profiles import (
    APPS,
    NOTIFICATIONS_DBUS_NAME,
    PERSISTENT_SANDBOX_CONFIG,
    PORTAL_DBUS_BROADCAST_RULE,
    PORTAL_DBUS_NAMESPACE,
    WAYLAND_COMPAT_APPS,
    WAYLAND_COMPAT_RUNTIME_ROOT,
)
from .runtime import (
    ANGLE_GL_ARGS,
    MANAGED_WAYLAND_OPENGL_ENVIRONMENT,
    current_user_home,
    current_user_name,
    current_user_runtime_socket,
    fail,
    managed_subprocess_environment,
    require_root_owned_executable,
    validate_absolute_path,
    validate_runtime_entry_name,
    validate_session_bus_address,
    wayland_ozone_args,
)

SYSTEM_BUS_SOCKET_PATH = "/run/dbus/system_bus_socket"
SYSTEM_BUS_ADDRESS = f"unix:path={SYSTEM_BUS_SOCKET_PATH}"
BWRAP_INFO_MAX_BYTES = 16_384
BWRAP_NETWORK_SETUP_TIMEOUT_SECONDS = 15
SLIRP4NETNS_BINARY = "/usr/bin/slirp4netns"
SLIRP4NETNS_DIAGNOSTIC_MAX_BYTES = 4_096
SLIRP4NETNS_DNS_ADDRESS = "10.0.2.3"
SLIRP4NETNS_MTU = 65_520
SLIRP4NETNS_STOP_TIMEOUT_SECONDS = 2
SLIRP4NETNS_TAP_NAME = "tap0"
PRIVATE_TEMPORARY_DIRECTORIES = ("/tmp", "/var/tmp", "/dev/shm")
PRIVATE_X11_SOCKET_DIRECTORY = "/tmp/.X11-unix"
PRIVATE_XWAYLAND_BINARY = (
    f"{WAYLAND_COMPAT_RUNTIME_ROOT}/usr/bin/Xwayland"
)
PRIVATE_XWAYLAND_LIBRARY_DIRECTORY = (
    f"{WAYLAND_COMPAT_RUNTIME_ROOT}/usr/lib/x86_64-linux-gnu"
)
PRIVATE_XKBCOMP_SOURCE = f"{WAYLAND_COMPAT_RUNTIME_ROOT}/usr/bin/xkbcomp"
PRIVATE_XKBCOMP_OVERLAY_DIRECTORY = (
    f"{WAYLAND_COMPAT_RUNTIME_ROOT}/usr/lib/xkbcomp-overlay"
)
PRIVATE_XKBCOMP_DESTINATION = "/usr/bin/xkbcomp"
OUTER_WAYLAND_DISPLAY_ENVIRONMENT = (
    "LABWC_MANAGED_OUTER_WAYLAND_DISPLAY"
)
CAGE_WLROOTS_ENVIRONMENT = {
    "WLR_BACKENDS": "wayland",
    "WLR_WL_OUTPUTS": "1",
}
MANAGED_CODEX_HOME = "/data/codex/usr/home"
MANAGED_CODEX_INSTALLATION_ID = f"{MANAGED_CODEX_HOME}/installation_id"
HOST_MACHINE_ID_PATH = "/etc/machine-id"
MAX_HOST_MACHINE_ID_BYTES = 64
CHATGPT_LIFECYCLE_LOCK_NAME = "labwc-chatgpt-launch.lock"
CHATGPT_SINGLETON_PROFILE_PATH = ".config/Codex"
CHATGPT_SINGLETON_NAMES = (
    "SingletonCookie",
    "SingletonLock",
    "SingletonSocket",
)
MAX_SINGLETON_LINK_BYTES = 4096
SYNTHETIC_IDENTITY_DOMAIN = b"labwc-managed-app/chatgpt-identity/v1"


def start_filtered_dbus_proxy(
    temp_root: str,
    proxy_name: str,
    bus_address: str,
    policy_arguments: tuple[str, ...],
) -> tuple[subprocess.Popen | None, str | None, socket.socket | None]:
    if not re.fullmatch(r"[A-Za-z0-9._-]{1,64}", proxy_name):
        fail(f"invalid D-Bus proxy name: {proxy_name or 'unset'}")

    proxy_binary = require_root_owned_executable(
        "xdg-dbus-proxy",
        "/usr/bin/xdg-dbus-proxy",
    )

    proxy_socket = os.path.join(temp_root, proxy_name)
    readiness_parent, readiness_child = socket.socketpair()
    readiness_parent.settimeout(5)
    proxy_argv = [
        proxy_binary,
        f"--fd={readiness_child.fileno()}",
        bus_address,
        proxy_socket,
        "--filter",
        *policy_arguments,
    ]
    proxy = subprocess.Popen(
        proxy_argv,
        cwd="/",
        env=managed_subprocess_environment(),
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        pass_fds=[readiness_child.fileno()],
        text=True,
    )
    readiness_child.close()

    try:
        readiness_parent.recv(16)
    except TimeoutError:
        stderr_pipe = proxy.stderr
        stop_dbus_proxy(proxy, readiness_parent)
        stderr_output = stderr_pipe.read().strip() if stderr_pipe is not None else ""
        fail(stderr_output or "xdg-dbus-proxy did not become ready before timeout")

    if proxy.poll() is not None:
        stderr_output = proxy.stderr.read().strip() if proxy.stderr is not None else ""
        if proxy.stderr is not None:
            proxy.stderr.close()
        readiness_parent.close()
        fail(stderr_output or "xdg-dbus-proxy exited before becoming ready")
    try:
        proxy_socket_stat = os.lstat(proxy_socket)
    except OSError as exc:
        stop_dbus_proxy(proxy, readiness_parent)
        fail(f"xdg-dbus-proxy did not create its sandbox socket: {proxy_socket}: {exc}")
    if (
        stat.S_ISLNK(proxy_socket_stat.st_mode)
        or not stat.S_ISSOCK(proxy_socket_stat.st_mode)
        or proxy_socket_stat.st_uid != os.getuid()
    ):
        stop_dbus_proxy(proxy, readiness_parent)
        fail(f"xdg-dbus-proxy created an unsafe sandbox socket: {proxy_socket}")
    return proxy, proxy_socket, readiness_parent


def start_session_bus_proxy(
    temp_root: str,
    additional_talk_names: tuple[str, ...] = (),
    additional_own_names: tuple[str, ...] = (),
    *,
    required: bool = False,
) -> tuple[subprocess.Popen | None, str | None, socket.socket | None]:
    raw_bus_address = os.environ.get("DBUS_SESSION_BUS_ADDRESS", "")
    if not raw_bus_address:
        if required:
            fail("DBUS_SESSION_BUS_ADDRESS is required for the managed secret-storage sandbox")
        return None, None, None

    bus_address = validate_session_bus_address(raw_bus_address)
    policy_arguments = (
        f"--talk={NOTIFICATIONS_DBUS_NAME}",
        f"--see={PORTAL_DBUS_NAMESPACE}",
        f"--talk={PORTAL_DBUS_NAMESPACE}",
        f"--call={PORTAL_DBUS_NAMESPACE}=*",
        f"--broadcast={PORTAL_DBUS_NAMESPACE}={PORTAL_DBUS_BROADCAST_RULE}",
        *(f"--talk={bus_name}" for bus_name in additional_talk_names),
        *(f"--own={bus_name}" for bus_name in additional_own_names),
    )
    return start_filtered_dbus_proxy(
        temp_root,
        "session-bus",
        bus_address,
        policy_arguments,
    )


def start_system_bus_proxy(
    temp_root: str,
    additional_talk_names: tuple[str, ...] = (),
    *,
    required: bool = False,
) -> tuple[subprocess.Popen | None, str | None, socket.socket | None]:
    try:
        system_bus_stat = os.lstat(SYSTEM_BUS_SOCKET_PATH)
    except FileNotFoundError:
        if required:
            fail(f"system D-Bus socket is unavailable: {SYSTEM_BUS_SOCKET_PATH}")
        return None, None, None
    except OSError as exc:
        fail(f"cannot inspect system D-Bus socket: {SYSTEM_BUS_SOCKET_PATH}: {exc}")
    if (
        stat.S_ISLNK(system_bus_stat.st_mode)
        or not stat.S_ISSOCK(system_bus_stat.st_mode)
    ):
        fail(
            "system D-Bus socket must be a socket, not a symlink: "
            f"{SYSTEM_BUS_SOCKET_PATH}"
        )

    policy_arguments = tuple(
        f"--talk={bus_name}" for bus_name in additional_talk_names
    )
    return start_filtered_dbus_proxy(
        temp_root,
        "system-bus",
        SYSTEM_BUS_ADDRESS,
        policy_arguments,
    )


def stop_dbus_proxy(
    proxy_process: subprocess.Popen | None,
    proxy_lifecycle: socket.socket | None,
) -> None:
    if proxy_lifecycle is not None:
        proxy_lifecycle.close()
    if proxy_process and proxy_process.poll() is None:
        proxy_process.send_signal(signal.SIGTERM)
        try:
            proxy_process.wait(timeout=2)
        except subprocess.TimeoutExpired:
            proxy_process.kill()
            proxy_process.wait(timeout=2)


def stop_dbus_proxies(
    proxies: list[tuple[subprocess.Popen | None, socket.socket | None]],
) -> None:
    for proxy_process, proxy_lifecycle in reversed(proxies):
        stop_dbus_proxy(proxy_process, proxy_lifecycle)


def _close_file_descriptor(file_descriptor: int | None) -> None:
    if file_descriptor is None:
        return
    try:
        os.close(file_descriptor)
    except OSError:
        pass


def _stop_subprocess(process: subprocess.Popen | None) -> None:
    if process is None or process.poll() is not None:
        return
    try:
        process.terminate()
    except ProcessLookupError:
        pass
    try:
        process.wait(timeout=SLIRP4NETNS_STOP_TIMEOUT_SECONDS)
    except subprocess.TimeoutExpired:
        try:
            process.kill()
        except ProcessLookupError:
            pass
        try:
            process.wait(timeout=SLIRP4NETNS_STOP_TIMEOUT_SECONDS)
        except subprocess.TimeoutExpired:
            pass


def _read_bwrap_sandbox_pid(
    info_fd: int,
    bwrap_process: subprocess.Popen,
) -> int:
    deadline = time.monotonic() + BWRAP_NETWORK_SETUP_TIMEOUT_SECONDS
    payload = bytearray()

    while True:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            status = bwrap_process.poll()
            if status is not None:
                fail(
                    "Bubblewrap exited before reporting a sandbox process ID "
                    f"(status {status})"
                )
            fail("Bubblewrap did not report a sandbox process ID before timeout")

        try:
            readable, _, _ = select.select(
                [info_fd],
                [],
                [],
                min(remaining, 0.25),
            )
        except InterruptedError:
            continue
        if not readable:
            status = bwrap_process.poll()
            if status is not None:
                fail(
                    "Bubblewrap exited before reporting a sandbox process ID "
                    f"(status {status})"
                )
            continue

        remaining_bytes = BWRAP_INFO_MAX_BYTES + 1 - len(payload)
        if remaining_bytes <= 0:
            fail("Bubblewrap sandbox information exceeds the managed size limit")
        try:
            chunk = os.read(info_fd, min(4_096, remaining_bytes))
        except InterruptedError:
            continue
        if not chunk:
            break
        payload.extend(chunk)
        if len(payload) > BWRAP_INFO_MAX_BYTES:
            fail("Bubblewrap sandbox information exceeds the managed size limit")

    if not payload:
        fail("Bubblewrap returned empty sandbox information")
    try:
        information = json.loads(payload.decode("utf-8"))
    except (UnicodeError, json.JSONDecodeError):
        fail("Bubblewrap returned invalid sandbox information")
    if not isinstance(information, dict):
        fail("Bubblewrap sandbox information must be a JSON object")

    sandbox_pid = information.get("child-pid")
    if (
        isinstance(sandbox_pid, bool)
        or not isinstance(sandbox_pid, int)
        or sandbox_pid <= 1
    ):
        fail("Bubblewrap returned an invalid sandbox process ID")
    if bwrap_process.poll() is not None:
        fail(
            "Bubblewrap exited while preparing the isolated network namespace "
            f"(status {bwrap_process.returncode})"
        )
    return sandbox_pid


def _slirp4netns_diagnostic(stderr_handle) -> str:
    try:
        stderr_handle.flush()
        stderr_handle.seek(0)
        payload = stderr_handle.read(SLIRP4NETNS_DIAGNOSTIC_MAX_BYTES + 1)
    except OSError:
        return ""
    truncated = len(payload) > SLIRP4NETNS_DIAGNOSTIC_MAX_BYTES
    payload = payload[:SLIRP4NETNS_DIAGNOSTIC_MAX_BYTES]
    message = " ".join(payload.decode("utf-8", errors="replace").split())
    if truncated:
        message = f"{message} [truncated]" if message else "[truncated]"
    return message


def _slirp4netns_exit_message(
    status: int,
    stderr_handle,
    context: str,
) -> str:
    diagnostic = _slirp4netns_diagnostic(stderr_handle)
    suffix = f": {diagnostic}" if diagnostic else ""
    return f"slirp4netns exited {context} (status {status}){suffix}"


def _wait_for_slirp4netns_ready(
    ready_fd: int,
    bwrap_process: subprocess.Popen,
    slirp_process: subprocess.Popen,
    stderr_handle,
) -> None:
    deadline = time.monotonic() + BWRAP_NETWORK_SETUP_TIMEOUT_SECONDS

    while True:
        bwrap_status = bwrap_process.poll()
        if bwrap_status is not None:
            fail(
                "Bubblewrap exited before isolated network setup completed "
                f"(status {bwrap_status})"
            )
        slirp_status = slirp_process.poll()
        if slirp_status is not None:
            fail(
                _slirp4netns_exit_message(
                    slirp_status,
                    stderr_handle,
                    "before configuring the isolated network namespace",
                )
            )

        remaining = deadline - time.monotonic()
        if remaining <= 0:
            fail(
                "slirp4netns did not configure the isolated network namespace "
                "before timeout"
            )
        try:
            readable, _, _ = select.select(
                [ready_fd],
                [],
                [],
                min(remaining, 0.25),
            )
        except InterruptedError:
            continue
        if not readable:
            continue
        try:
            readiness = os.read(ready_fd, 2)
        except InterruptedError:
            continue
        if readiness != b"1":
            try:
                slirp_status = slirp_process.wait(timeout=0.1)
            except subprocess.TimeoutExpired:
                slirp_status = None
            if slirp_status is not None:
                fail(
                    _slirp4netns_exit_message(
                        slirp_status,
                        stderr_handle,
                        "before configuring the isolated network namespace",
                    )
                )
            fail("slirp4netns returned an invalid readiness marker")
        return


def _wait_for_bwrap_with_slirp4netns(
    bwrap_process: subprocess.Popen,
    slirp_process: subprocess.Popen,
    stderr_handle,
) -> int:
    while True:
        slirp_status = slirp_process.poll()
        if slirp_status is not None:
            fail(
                _slirp4netns_exit_message(
                    slirp_status,
                    stderr_handle,
                    "while the managed application sandbox was running",
                )
            )
        try:
            bwrap_status = bwrap_process.wait(timeout=0.25)
        except subprocess.TimeoutExpired:
            continue
        slirp_status = slirp_process.poll()
        if slirp_status is not None:
            fail(
                _slirp4netns_exit_message(
                    slirp_status,
                    stderr_handle,
                    "while the managed application sandbox was running",
                )
            )
        return bwrap_status


def run_slirp4netns_sandbox(
    command: list[str],
    payload_argv: list[str],
    temp_root: str,
    inherited_fds: tuple[int, ...],
) -> int:
    slirp_binary = require_root_owned_executable(
        "slirp4netns",
        SLIRP4NETNS_BINARY,
    )

    info_read_fd = None
    info_write_fd = None
    block_read_fd = None
    block_write_fd = None
    ready_read_fd = None
    ready_write_fd = None
    exit_read_fd = None
    exit_write_fd = None
    bwrap_process = None
    slirp_process = None
    stderr_handle = None

    try:
        info_read_fd, info_write_fd = os.pipe()
        block_read_fd, block_write_fd = os.pipe()
        ready_read_fd, ready_write_fd = os.pipe()
        exit_read_fd, exit_write_fd = os.pipe()

        bwrap_command = [
            *command,
            "--info-fd",
            str(info_write_fd),
            "--block-fd",
            str(block_read_fd),
            *payload_argv,
        ]
        bwrap_pass_fds = tuple(
            dict.fromkeys(
                (*inherited_fds, info_write_fd, block_read_fd)
            )
        )
        bwrap_process = subprocess.Popen(
            bwrap_command,
            cwd="/",
            env=managed_subprocess_environment(),
            pass_fds=bwrap_pass_fds,
        )
        _close_file_descriptor(info_write_fd)
        info_write_fd = None
        _close_file_descriptor(block_read_fd)
        block_read_fd = None

        sandbox_pid = _read_bwrap_sandbox_pid(
            info_read_fd,
            bwrap_process,
        )
        _close_file_descriptor(info_read_fd)
        info_read_fd = None

        stderr_path = os.path.join(temp_root, "slirp4netns.stderr")
        stderr_handle = open(stderr_path, "w+b", buffering=0)
        os.chmod(stderr_path, 0o600)
        slirp_process = subprocess.Popen(
            [
                slirp_binary,
                "--configure",
                f"--mtu={SLIRP4NETNS_MTU}",
                "--disable-host-loopback",
                "--ready-fd",
                str(ready_write_fd),
                "--exit-fd",
                str(exit_read_fd),
                str(sandbox_pid),
                SLIRP4NETNS_TAP_NAME,
            ],
            cwd="/",
            env=managed_subprocess_environment(),
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=stderr_handle,
            pass_fds=(ready_write_fd, exit_read_fd),
        )
        _close_file_descriptor(ready_write_fd)
        ready_write_fd = None
        _close_file_descriptor(exit_read_fd)
        exit_read_fd = None

        _wait_for_slirp4netns_ready(
            ready_read_fd,
            bwrap_process,
            slirp_process,
            stderr_handle,
        )
        _close_file_descriptor(ready_read_fd)
        ready_read_fd = None
        try:
            os.write(block_write_fd, b"1")
        except (BrokenPipeError, OSError):
            status = bwrap_process.poll()
            suffix = f" (status {status})" if status is not None else ""
            fail(f"cannot release the configured Bubblewrap sandbox{suffix}")
        _close_file_descriptor(block_write_fd)
        block_write_fd = None

        return _wait_for_bwrap_with_slirp4netns(
            bwrap_process,
            slirp_process,
            stderr_handle,
        )
    finally:
        if bwrap_process is not None and bwrap_process.poll() is None:
            _stop_subprocess(bwrap_process)
        for file_descriptor in (
            info_read_fd,
            info_write_fd,
            block_read_fd,
            block_write_fd,
            ready_read_fd,
            ready_write_fd,
            exit_read_fd,
        ):
            _close_file_descriptor(file_descriptor)
        _close_file_descriptor(exit_write_fd)
        if slirp_process is not None and slirp_process.poll() is None:
            try:
                slirp_process.wait(timeout=SLIRP4NETNS_STOP_TIMEOUT_SECONDS)
            except subprocess.TimeoutExpired:
                _stop_subprocess(slirp_process)
        if stderr_handle is not None:
            stderr_handle.close()


def add_dir_chain(command: list[str], path: str) -> None:
    parts = pathlib.PurePosixPath(path).parts
    current = ""
    for part in parts:
        if part == "/":
            current = "/"
            continue
        current = os.path.join(current, part) if current != "/" else f"/{part}"
        command.extend(["--dir", current])


def add_private_tmpfs_mounts(command: list[str]) -> None:
    for directory in PRIVATE_TEMPORARY_DIRECTORIES:
        command.extend(["--tmpfs", directory, "--chmod", "01777", directory])


def add_optional_bind(command: list[str], option: str, source: str, destination: str) -> None:
    if os.path.exists(source):
        add_dir_chain(command, os.path.dirname(destination))
        command.extend([option, source, destination])


def add_gpu_device_binds(command: list[str], mode: str) -> None:
    if mode not in {"intel", "nvidia"}:
        return

    device_paths = [
        pathlib.Path("/dev/dri"),
        pathlib.Path("/dev/kfd"),
        pathlib.Path("/dev/accel"),
    ]
    if mode == "nvidia":
        device_paths.extend(
            (
                pathlib.Path("/dev/nvidia-caps"),
                pathlib.Path("/dev/nvidiactl"),
                pathlib.Path("/dev/nvidia-modeset"),
                pathlib.Path("/dev/nvidia-uvm"),
                pathlib.Path("/dev/nvidia-uvm-tools"),
            )
        )
        device_paths.extend(sorted(pathlib.Path("/dev").glob("nvidia[0-9]*")))
    for device_path in device_paths[:64]:
        try:
            metadata = device_path.lstat()
        except FileNotFoundError:
            continue
        except OSError as exc:
            fail(f"cannot inspect managed accelerator device {device_path}: {exc}")
        if stat.S_ISLNK(metadata.st_mode) or not (
            stat.S_ISDIR(metadata.st_mode) or stat.S_ISCHR(metadata.st_mode)
        ):
            fail(
                "managed accelerator path must be a directory or character "
                f"device: {device_path}"
            )
        if metadata.st_uid != 0:
            fail(f"managed accelerator path must remain root-owned: {device_path}")
        command.extend(["--dev-bind", str(device_path), str(device_path)])


def add_video_device_binds(command: list[str], enabled: bool) -> None:
    if not enabled:
        return

    camera_devices = sorted(
        {
            device_path
            for pattern in ("media[0-9]*", "v4l-subdev[0-9]*", "video[0-9]*")
            for device_path in pathlib.Path("/dev").glob(pattern)
        }
    )
    for device_path in camera_devices[:64]:
        try:
            metadata = device_path.lstat()
        except OSError as exc:
            fail(f"cannot inspect managed camera device {device_path}: {exc}")
        if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISCHR(metadata.st_mode):
            fail(f"managed camera device must be a character device: {device_path}")
        command.extend(["--dev-bind", str(device_path), str(device_path)])


def add_system_bus_proxy_bind(command: list[str], proxy_socket: str) -> None:
    validate_absolute_path("system D-Bus proxy socket", proxy_socket)
    add_dir_chain(command, os.path.dirname(SYSTEM_BUS_SOCKET_PATH))
    command.extend(["--bind", proxy_socket, SYSTEM_BUS_SOCKET_PATH])


def validate_no_host_audio_device_binds(app_name: str, command: list[str]) -> None:
    bind_options = {
        "--bind",
        "--bind-try",
        "--dev-bind",
        "--dev-bind-try",
        "--ro-bind",
        "--ro-bind-try",
    }
    for index, argument in enumerate(command):
        if argument not in bind_options:
            continue
        if index + 2 >= len(command):
            fail(f"malformed bubblewrap bind while launching {app_name}")
        for raw_path in command[index + 1 : index + 3]:
            normalized_path = os.path.normpath(raw_path)
            if normalized_path == "/dev/snd" or normalized_path.startswith("/dev/snd/"):
                fail(
                    f"bubblewrap forbids direct ALSA device access for {app_name}: "
                    f"{raw_path}"
                )


def validate_pure_privacy_device_isolation(app_name: str, command: list[str]) -> None:
    validate_no_host_audio_device_binds(app_name, command)
    bind_options = {
        "--bind",
        "--bind-try",
        "--dev-bind",
        "--dev-bind-try",
        "--ro-bind",
        "--ro-bind-try",
    }
    for index, argument in enumerate(command):
        if argument not in bind_options:
            continue
        if index + 2 >= len(command):
            fail(f"malformed bubblewrap bind while launching {app_name}")
        for path in command[index + 1 : index + 3]:
            if (
                path == "/dev/dri"
                or path.startswith("/dev/dri/")
                or path == "/dev/kfd"
                or path == "/dev/accel"
                or path.startswith("/dev/accel/")
                or path.startswith("/dev/nvidia")
            ):
                fail(f"PurePrivacy forbids hardware GPU device access for {app_name}: {path}")


def resolve_home_relative_file(
    home_dir: str,
    relative_path: str,
    *,
    writable: bool = False,
) -> str:
    relative = pathlib.PurePosixPath(relative_path)
    if not relative_path or relative.is_absolute() or ".." in relative.parts:
        fail(f"invalid HOME-relative file path: {relative_path or 'unset'}")
    source_path = os.path.join(home_dir, relative_path)
    validate_absolute_path("HOME-relative source path", source_path)
    home_real = os.path.realpath(home_dir)
    source_real = os.path.realpath(source_path)
    if os.path.commonpath((home_real, source_real)) != home_real:
        fail(f"HOME-relative file escapes HOME: {source_path}")
    if source_real != source_path:
        fail(f"HOME-relative file must not traverse symlinks: {source_path}")
    try:
        metadata = os.lstat(source_path)
    except OSError as exc:
        fail(f"required HOME-relative file is unavailable: {source_path}: {exc}")
    if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISREG(metadata.st_mode):
        fail(f"HOME-relative file must be a regular file, not a symlink: {source_path}")
    if metadata.st_uid != os.getuid() or not os.access(source_path, os.R_OK):
        fail(f"HOME-relative file must be readable and owned by the current user: {source_path}")
    if not writable and metadata.st_mode & 0o022:
        fail(f"HOME-relative file must not be writable by group or other: {source_path}")
    if writable and not os.access(source_path, os.W_OK):
        fail(f"HOME-relative file must be writable by the current user: {source_path}")
    return source_path


def resolve_optional_home_relative_directory(
    home_dir: str,
    relative_path: str,
    *,
    writable: bool = False,
) -> str | None:
    source_path = resolve_home_relative_path(home_dir, relative_path)
    source_real = os.path.realpath(source_path)
    if source_real != source_path:
        fail(f"HOME-relative directory must not traverse symlinks: {source_path}")
    try:
        metadata = os.lstat(source_path)
    except FileNotFoundError:
        return None
    except OSError as exc:
        fail(f"cannot inspect HOME-relative directory {source_path}: {exc}")
    if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISDIR(metadata.st_mode):
        fail(f"HOME-relative directory must be a real directory: {source_path}")
    required_access = os.R_OK | os.X_OK
    if writable:
        required_access |= os.W_OK
    if metadata.st_uid != os.getuid() or not os.access(source_path, required_access):
        access_description = (
            "readable, searchable, and writable"
            if writable
            else "readable and searchable"
        )
        fail(
            "HOME-relative directory must be "
            f"{access_description} and owned by the current user: {source_path}"
        )
    if not writable and metadata.st_mode & 0o022:
        fail(f"HOME-relative directory must not be writable by group or other: {source_path}")
    return source_path


def add_home_directory_binds(
    command: list[str],
    home_dir: str,
    relative_paths: tuple[str, ...],
    option: str,
) -> None:
    if option not in {"--bind", "--ro-bind"}:
        fail(f"unsupported HOME directory bind option: {option}")
    for relative_path in relative_paths:
        source_path = resolve_optional_home_relative_directory(
            home_dir,
            relative_path,
            writable=option == "--bind",
        )
        if source_path is None:
            continue
        destination_path = os.path.join(home_dir, relative_path)
        add_dir_chain(command, destination_path)
        command.extend([option, source_path, destination_path])


def add_optional_home_file_binds(
    command: list[str],
    home_dir: str,
    relative_paths: tuple[str, ...],
) -> None:
    for relative_path in relative_paths:
        source_path = resolve_home_relative_path(home_dir, relative_path)
        source_real = os.path.realpath(source_path)
        if source_real != source_path:
            fail(f"HOME-relative file must not traverse symlinks: {source_path}")
        try:
            metadata = os.lstat(source_path)
        except FileNotFoundError:
            continue
        except OSError as exc:
            fail(f"cannot inspect HOME-relative file {source_path}: {exc}")
        if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISREG(metadata.st_mode):
            fail(f"HOME-relative file must be a regular file: {source_path}")
        if metadata.st_uid != os.getuid() or not os.access(source_path, os.R_OK):
            fail(
                "HOME-relative file must be readable and owned by the current "
                f"user: {source_path}"
            )
        if metadata.st_mode & 0o022:
            fail(f"HOME-relative file must not be writable by group or other: {source_path}")
        destination_path = os.path.join(home_dir, relative_path)
        add_dir_chain(command, os.path.dirname(destination_path))
        command.extend(["--ro-bind", source_path, destination_path])


def add_absolute_directory_binds(
    command: list[str],
    paths: tuple[str, ...],
    option: str,
    *,
    required: bool = True,
    require_user_private: bool = False,
) -> None:
    if option not in {"--bind", "--ro-bind"}:
        fail(f"unsupported absolute directory bind option: {option}")
    for path in paths:
        validate_absolute_path("absolute sandbox directory", path)
        try:
            metadata = os.lstat(path)
        except FileNotFoundError:
            if required:
                fail(f"required sandbox directory is unavailable: {path}")
            continue
        except OSError as exc:
            fail(f"required sandbox directory is unavailable: {path}: {exc}")
        if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISDIR(metadata.st_mode):
            fail(f"required sandbox directory must be a real directory: {path}")
        if require_user_private:
            if metadata.st_uid != os.getuid() or stat.S_IMODE(metadata.st_mode) != 0o700:
                fail(
                    "required private sandbox directory must be current-user-owned "
                    f"and mode 0700: {path}"
                )
        elif metadata.st_uid not in {0, os.getuid()} or metadata.st_mode & stat.S_IWOTH:
            fail(f"required sandbox directory has unsafe ownership or mode: {path}")
        required_access = os.R_OK | os.X_OK
        if option == "--bind":
            required_access |= os.W_OK
        if not os.access(path, required_access):
            fail(f"required sandbox directory is not accessible as requested: {path}")
        add_dir_chain(command, path)
        command.extend([option, path, path])


def add_absolute_directory_bind_pairs(
    command: list[str],
    path_pairs: tuple[tuple[str, str], ...],
    option: str,
) -> None:
    if option not in {"--bind", "--ro-bind"}:
        fail(f"unsupported absolute directory bind-pair option: {option}")
    for path_pair in path_pairs:
        if (
            not isinstance(path_pair, tuple)
            or len(path_pair) != 2
            or not all(isinstance(path, str) for path in path_pair)
        ):
            fail("absolute directory bind pair must contain two path strings")
        source_path, destination_path = path_pair
        if source_path == destination_path:
            fail(f"absolute directory bind pair must use distinct paths: {source_path}")
        for label, path in (
            ("absolute sandbox bind source directory", source_path),
            ("absolute sandbox bind destination directory", destination_path),
        ):
            validate_absolute_path(label, path)
            if (
                path == "/"
                or os.path.normpath(path) != path
                or any(character in path for character in ("\n", "\r", "\0"))
                or os.path.realpath(path) != path
            ):
                fail(f"{label} must be a direct normalized path: {path}")
            try:
                metadata = os.lstat(path)
            except OSError as exc:
                fail(f"{label} is unavailable: {path}: {exc}")
            if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISDIR(metadata.st_mode):
                fail(f"{label} must be a real directory: {path}")
            if metadata.st_uid not in {0, os.getuid()} or metadata.st_mode & stat.S_IWOTH:
                fail(f"{label} has unsafe ownership or mode: {path}")
            required_access = os.R_OK | os.X_OK
            if option == "--bind":
                required_access |= os.W_OK
            if not os.access(path, required_access):
                fail(f"{label} is not accessible as requested: {path}")
        command.extend([option, source_path, destination_path])


def add_persistent_directory_binds(
    command: list[str],
    home_dir: str,
    path_pairs: tuple[tuple[str, str], ...],
) -> None:
    for source_relative, destination_relative in path_pairs:
        source_path = persistent_app_directory(home_dir, source_relative)
        destination_path = resolve_home_relative_path(
            home_dir,
            destination_relative,
        )
        add_dir_chain(command, destination_path)
        command.extend(["--bind", source_path, destination_path])


def filtered_resolv_conf() -> str:
    lines: list[str] = []
    try:
        with open("/etc/resolv.conf", encoding="utf-8") as handle:
            for raw_line in handle:
                line = raw_line.strip()
                if not line or line.startswith("#"):
                    continue
                if line.startswith("nameserver ") or line.startswith("options "):
                    lines.append(line)
    except OSError:
        pass
    if not lines:
        lines.append("nameserver 1.1.1.1")
    return "\n".join(lines) + "\n"


def slirp4netns_resolv_conf() -> str:
    return (
        f"nameserver {SLIRP4NETNS_DNS_ADDRESS}\n"
        "options timeout:2 attempts:3\n"
    )


def create_slirp4netns_resolver_file(temp_root: str) -> str:
    validate_absolute_path("slirp4netns temporary root", temp_root)
    resolver_path = os.path.join(temp_root, "slirp4netns-resolv.conf")
    try:
        with open(resolver_path, "x", encoding="utf-8") as handle:
            handle.write(slirp4netns_resolv_conf())
        os.chmod(resolver_path, 0o600)
    except OSError as exc:
        fail(f"cannot create the private slirp4netns resolver policy: {exc}")
    return resolver_path


def reserve_outer_wayland_socket_name(
    command: list[str],
    temp_root: str,
    sandbox_runtime_dir: str,
    wayland_display: str,
) -> int:
    validate_absolute_path("Wayland socket reservation root", temp_root)
    validate_absolute_path("sandbox runtime directory", sandbox_runtime_dir)
    wayland_display = validate_runtime_entry_name(
        "outer Wayland socket",
        wayland_display,
    )
    reservation_path = os.path.join(temp_root, "outer-wayland-display.lock")
    sandbox_lock_path = os.path.join(
        sandbox_runtime_dir,
        f"{wayland_display}.lock",
    )
    open_flags = os.O_CREAT | os.O_EXCL | os.O_RDWR | os.O_CLOEXEC
    if hasattr(os, "O_NOFOLLOW"):
        open_flags |= os.O_NOFOLLOW
    reservation_fd: int | None = None
    try:
        reservation_fd = os.open(reservation_path, open_flags, 0o600)
        os.fchmod(reservation_fd, 0o600)
        fcntl.flock(reservation_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError as exc:
        _close_file_descriptor(reservation_fd)
        fail(f"cannot reserve the outer Wayland socket name: {exc}")
    command.extend(["--bind", reservation_path, sandbox_lock_path])
    return reservation_fd


def pure_privacy_environment(app_name: str) -> dict[str, str]:
    env = build_environment(app_name, "launch")
    sandbox_home = "/home/user"
    sandbox_runtime = f"/run/user/{os.getuid()}"
    env.update(
        {
            "USER": "user",
            "LOGNAME": "user",
            "HOME": sandbox_home,
            "LANG": "C.UTF-8",
            "LC_ALL": "C.UTF-8",
            "TZ": "UTC",
            "XDG_RUNTIME_DIR": sandbox_runtime,
            "XDG_CONFIG_HOME": f"{sandbox_home}/.config",
            "XDG_CACHE_HOME": f"{sandbox_home}/.cache",
            "XDG_DATA_HOME": f"{sandbox_home}/.local/share",
            "XDG_STATE_HOME": f"{sandbox_home}/.local/state",
            "TMPDIR": f"{sandbox_home}/.tmp",
        }
    )
    env.update(MANAGED_WAYLAND_OPENGL_ENVIRONMENT)
    for name in tuple(env):
        if name.startswith(("VK_", "__VK_", "MESA_VK_")):
            env.pop(name)
    env.pop("COLORTERM", None)
    env.pop("DBUS_SYSTEM_BUS_ADDRESS", None)
    if app_name == "mullvad-browser":
        env["MOZ_WEBRENDER"] = "1"
        env["MOZ_WEBRENDER_SOFTWARE"] = "1"
        env["MOZ_CRASHREPORTER_DISABLE"] = "1"
    return env


def pure_privacy_argv(app_name: str, extra_args: list[str]) -> list[str]:
    app = APPS[app_name]
    executable = resolved_executable(app_name, "pure-privacy")
    extra_args = normalize_managed_arguments(app_name, extra_args)
    validate_managed_arguments("pure-privacy", extra_args)
    if app_name in {"chromium", "microsoft-edge", "vivaldi"}:
        argv = [
            executable,
            *wayland_ozone_args(
                enable_features=("UseOzonePlatform",),
                disable_features=(
                    "InterestGroupStorage",
                    "TopicsAPI",
                    "VaapiVideoDecoder",
                    "VaapiVideoEncoder",
                    "UseChromeOSDirectVideoDecoder",
                ),
            ),
            "--ignore-gpu-blocklist",
            "--enable-gpu-rasterization",
            *ANGLE_GL_ARGS,
            "--disable-accelerated-2d-canvas",
            "--disable-accelerated-video-decode",
            "--disable-accelerated-video-encode",
            "--disable-background-networking",
            "--no-pings",
            "--no-default-browser-check",
            "--disable-crash-reporter",
            "--disable-breakpad",
            "--disable-sync",
        ]
        argv.extend(extra_args)
        return argv
    argv = [
        executable,
        *PERSISTENT_SANDBOX_CONFIG.get(app_name, {}).get("inner_sandbox_args", ()),
    ]
    argv.extend(app.get("privacy_args", app["args"]))
    argv.extend(extra_args)
    return argv


def run_pure_privacy(app_name: str, extra_args: list[str]) -> int:
    if not APPS[app_name].get("pure_privacy", False):
        fail(f"pure-privacy mode is not supported for {app_name}")

    bwrap = require_root_owned_executable("bubblewrap", "/usr/bin/bwrap")

    env = pure_privacy_environment(app_name)
    host_runtime_dir = env["XDG_RUNTIME_DIR"]
    sandbox_runtime_dir = env["XDG_RUNTIME_DIR"]
    home_dir = env["HOME"]
    validate_absolute_path("host XDG_RUNTIME_DIR", host_runtime_dir)
    validate_absolute_path("sandbox HOME", home_dir)

    argv = pure_privacy_argv(app_name, extra_args)
    wayland_display = env["WAYLAND_DISPLAY"]
    host_wayland_socket = current_user_runtime_socket("Wayland socket", wayland_display)
    sandbox_wayland_socket = os.path.join(sandbox_runtime_dir, wayland_display)

    temp_root = tempfile.mkdtemp(prefix=f"labwc-{app_name}-privacy-", dir=host_runtime_dir if os.path.isdir(host_runtime_dir) else None)
    machine_id_path = os.path.join(temp_root, "machine-id")
    hostname_path = os.path.join(temp_root, "hostname")
    passwd_path = os.path.join(temp_root, "passwd")
    group_path = os.path.join(temp_root, "group")
    hosts_path = os.path.join(temp_root, "hosts")
    resolv_path = os.path.join(temp_root, "resolv.conf")
    nsswitch_path = os.path.join(temp_root, "nsswitch.conf")
    fake_machine_id = uuid.uuid4().hex
    fake_hostname = f"pure-{uuid.uuid4().hex[:12]}"
    with open(machine_id_path, "w", encoding="utf-8") as handle:
        handle.write(fake_machine_id + "\n")
    with open(hostname_path, "w", encoding="utf-8") as handle:
        handle.write(fake_hostname + "\n")
    with open(passwd_path, "w", encoding="utf-8") as handle:
        handle.write(f"user:x:{os.getuid()}:{os.getgid()}:Sandbox User:{home_dir}:/bin/sh\n")
    with open(group_path, "w", encoding="utf-8") as handle:
        handle.write(f"user:x:{os.getgid()}:\n")
    with open(hosts_path, "w", encoding="utf-8") as handle:
        handle.write(f"127.0.0.1 localhost\n::1 localhost\n127.0.1.1 {fake_hostname}\n")
    with open(resolv_path, "w", encoding="utf-8") as handle:
        handle.write(filtered_resolv_conf())
    with open(nsswitch_path, "w", encoding="utf-8") as handle:
        handle.write(
            "passwd: files\n"
            "group: files\n"
            "shadow: files\n"
            "gshadow: files\n"
            "hosts: files dns\n"
            "networks: files dns\n"
            "protocols: files\n"
            "services: files\n"
            "ethers: files\n"
            "rpc: files\n"
            "netgroup: files\n"
        )

    proxy_process = None
    proxy_socket = None
    proxy_lifecycle = None
    try:
        proxy_process, proxy_socket, proxy_lifecycle = start_session_bus_proxy(
            temp_root,
            APPS[app_name].get("privacy_dbus_names", ()),
        )
    except BaseException:
        stop_dbus_proxy(proxy_process, proxy_lifecycle)
        shutil.rmtree(temp_root, ignore_errors=True)
        raise

    command = [
        bwrap,
        "--unshare-all",
        "--new-session",
        "--die-with-parent",
        "--clearenv",
        "--uid",
        str(os.getuid()),
        "--gid",
        str(os.getgid()),
        "--hostname",
        fake_hostname,
        "--proc",
        "/proc",
        "--dev",
        "/dev",
        "--chdir",
        home_dir,
    ]
    if APPS[app_name].get("privacy_share_net", True):
        command.insert(2, "--share-net")
    add_dir_chain(command, os.path.dirname(home_dir))
    command.extend(["--tmpfs", home_dir, "--chmod", "0700", home_dir])
    add_dir_chain(command, os.path.dirname(sandbox_runtime_dir))
    command.extend(["--dir", sandbox_runtime_dir])
    add_dir_chain(command, "/var/lib/dbus")
    command.extend(["--dir", "/etc"])
    add_private_tmpfs_mounts(command)

    for source, destination in (
        ("/usr", "/usr"),
        ("/bin", "/bin"),
        ("/lib", "/lib"),
    ):
        command.extend(["--ro-bind", source, destination])
    for source, destination in (
        ("/sbin", "/sbin"),
        ("/lib64", "/lib64"),
        ("/lib32", "/lib32"),
        ("/opt", "/opt"),
    ):
        add_optional_bind(command, "--ro-bind", source, destination)
    for path in (
        "/etc/ssl",
        "/etc/ca-certificates",
        "/etc/chromium",
        "/etc/chromium.d",
        "/etc/pki",
        "/etc/fonts",
        "/etc/alternatives",
        "/etc/ld.so.cache",
        "/etc/ld.so.conf",
        "/etc/ld.so.conf.d",
        "/etc/mime.types",
        "/etc/xdg",
    ):
        add_optional_bind(command, "--ro-bind", path, path)

    command.extend(
        [
            "--ro-bind",
            machine_id_path,
            "/etc/machine-id",
            "--ro-bind",
            machine_id_path,
            "/var/lib/dbus/machine-id",
            "--ro-bind",
            hostname_path,
            "/etc/hostname",
            "--ro-bind",
            passwd_path,
            "/etc/passwd",
            "--ro-bind",
            group_path,
            "/etc/group",
            "--ro-bind",
            hosts_path,
            "/etc/hosts",
            "--ro-bind",
            resolv_path,
            "/etc/resolv.conf",
            "--ro-bind",
            nsswitch_path,
            "/etc/nsswitch.conf",
            "--bind",
            host_wayland_socket,
            sandbox_wayland_socket,
        ]
    )

    if proxy_socket:
        bus_socket = os.path.join(sandbox_runtime_dir, "bus")
        command.extend(["--bind", proxy_socket, bus_socket])
        env["DBUS_SESSION_BUS_ADDRESS"] = f"unix:path={bus_socket}"
    else:
        env.pop("DBUS_SESSION_BUS_ADDRESS", None)

    host_home_dir = current_user_home()
    for relative_path in APPS[app_name].get("privacy_home_ro_paths", ()):
        source_path = resolve_home_relative_file(host_home_dir, relative_path)
        destination_path = os.path.join(home_dir, relative_path)
        add_dir_chain(command, os.path.dirname(destination_path))
        command.extend(["--ro-bind", source_path, destination_path])

    if APPS[app_name].get("bind_workspace", False):
        workspace_source = os.path.join(host_home_dir, "Workspace")
        workspace_destination = os.path.join(home_dir, "Workspace")
        add_optional_bind(command, "--bind", workspace_source, workspace_destination)
        add_optional_bind(command, "--ro-bind", os.path.join(host_home_dir, ".gitconfig"), os.path.join(home_dir, ".gitconfig"))

    for directory in (
        env["XDG_CONFIG_HOME"],
        env["XDG_CACHE_HOME"],
        env["XDG_DATA_HOME"],
        env["XDG_STATE_HOME"],
        env["TMPDIR"],
    ):
        add_dir_chain(command, directory)

    validate_pure_privacy_device_isolation(app_name, command)
    for key, value in env.items():
        command.extend(["--setenv", key, value])
    command.extend(argv)

    try:
        completed = subprocess.run(
            command,
            check=False,
            cwd="/",
            env=managed_subprocess_environment(),
        )
        return completed.returncode
    finally:
        stop_dbus_proxy(proxy_process, proxy_lifecycle)
        shutil.rmtree(temp_root, ignore_errors=True)


def persistent_app_directory(home_dir: str, relative_path: str) -> str:
    if not relative_path or relative_path.startswith("/") or ".." in pathlib.PurePosixPath(relative_path).parts:
        fail(f"invalid persistent sandbox path: {relative_path or 'unset'}")
    directory = os.path.join(home_dir, relative_path)
    validate_absolute_path("persistent sandbox directory", directory)
    os.makedirs(directory, mode=0o700, exist_ok=True)
    home_real = os.path.realpath(home_dir)
    directory_real = os.path.realpath(directory)
    if os.path.commonpath((home_real, directory_real)) != home_real:
        fail(f"persistent sandbox directory escapes HOME: {directory}")
    directory_stat = os.lstat(directory)
    if not stat.S_ISDIR(directory_stat.st_mode) or stat.S_ISLNK(directory_stat.st_mode):
        fail(f"persistent sandbox path must be a real directory: {directory}")
    if directory_stat.st_uid != os.getuid():
        fail(f"persistent sandbox directory is not owned by the current user: {directory}")
    os.chmod(directory, 0o700)
    return directory


def persistent_runtime_directory(runtime_dir: str, entry_name: str) -> str:
    validate_absolute_path("persistent runtime directory root", runtime_dir)
    entry_name = validate_runtime_entry_name(
        "persistent runtime directory name",
        entry_name,
    )
    directory = os.path.join(runtime_dir, entry_name)
    validate_absolute_path("persistent runtime directory", directory)
    runtime_real = os.path.realpath(runtime_dir)
    directory_real = os.path.realpath(directory)
    if os.path.commonpath((runtime_real, directory_real)) != runtime_real:
        fail(f"persistent runtime directory escapes XDG_RUNTIME_DIR: {directory}")
    try:
        os.mkdir(directory, mode=0o700)
    except FileExistsError:
        pass
    except OSError as exc:
        fail(f"cannot create persistent runtime directory {directory}: {exc}")
    try:
        directory_stat = os.lstat(directory)
    except OSError as exc:
        fail(f"cannot inspect persistent runtime directory {directory}: {exc}")
    if (
        stat.S_ISLNK(directory_stat.st_mode)
        or not stat.S_ISDIR(directory_stat.st_mode)
        or directory_stat.st_uid != os.getuid()
    ):
        fail(
            "persistent runtime directory must be a real directory owned by "
            f"the current user: {directory}"
        )
    os.chmod(directory, 0o700)
    return directory


def open_chatgpt_lifecycle_lock(runtime_dir: str) -> tuple[int, bool]:
    lock_path = os.path.join(runtime_dir, CHATGPT_LIFECYCLE_LOCK_NAME)
    validate_absolute_path("managed ChatGPT lifecycle lock", lock_path)
    flags = os.O_RDWR | os.O_CREAT | os.O_CLOEXEC
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    try:
        lock_fd = os.open(lock_path, flags, 0o600)
    except OSError as exc:
        fail(f"cannot open managed ChatGPT lifecycle lock {lock_path}: {exc}")
    try:
        lock_stat = os.fstat(lock_fd)
        if (
            not stat.S_ISREG(lock_stat.st_mode)
            or lock_stat.st_uid != os.getuid()
            or lock_stat.st_nlink != 1
        ):
            fail(
                "managed ChatGPT lifecycle lock must be a current-user-owned "
                f"regular file with one link: {lock_path}"
            )
        os.fchmod(lock_fd, 0o600)
        stale_cleanup_allowed = False
        try:
            fcntl.flock(lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            stale_cleanup_allowed = True
        except BlockingIOError:
            fcntl.flock(lock_fd, fcntl.LOCK_SH)
        return lock_fd, stale_cleanup_allowed
    except BaseException:
        os.close(lock_fd)
        raise


def remove_stale_chatgpt_singletons(home_dir: str) -> None:
    profile_directory = persistent_app_directory(
        home_dir,
        CHATGPT_SINGLETON_PROFILE_PATH,
    )
    directory_flags = os.O_RDONLY | os.O_CLOEXEC
    if hasattr(os, "O_DIRECTORY"):
        directory_flags |= os.O_DIRECTORY
    if hasattr(os, "O_NOFOLLOW"):
        directory_flags |= os.O_NOFOLLOW
    try:
        directory_fd = os.open(profile_directory, directory_flags)
    except OSError as exc:
        fail(
            "cannot open managed ChatGPT profile directory for stale-lock "
            f"cleanup: {profile_directory}: {exc}"
        )
    try:
        stale_entries: set[str] = set()
        for entry_name in CHATGPT_SINGLETON_NAMES:
            try:
                entry_stat = os.stat(
                    entry_name,
                    dir_fd=directory_fd,
                    follow_symlinks=False,
                )
            except FileNotFoundError:
                continue
            except OSError as exc:
                fail(
                    "cannot inspect managed ChatGPT singleton entry "
                    f"{profile_directory}/{entry_name}: {exc}"
                )
            if (
                not stat.S_ISLNK(entry_stat.st_mode)
                or entry_stat.st_uid != os.getuid()
            ):
                fail(
                    "managed ChatGPT singleton entry must be a symlink owned "
                    f"by the current user: {profile_directory}/{entry_name}"
                )
            try:
                target = os.readlink(entry_name, dir_fd=directory_fd)
            except OSError as exc:
                fail(
                    "cannot read managed ChatGPT singleton entry "
                    f"{profile_directory}/{entry_name}: {exc}"
                )
            if (
                not target
                or len(os.fsencode(target)) > MAX_SINGLETON_LINK_BYTES
                or any(character in target for character in ("\n", "\r", "\0"))
            ):
                fail(
                    "managed ChatGPT singleton entry has an unsafe target: "
                    f"{profile_directory}/{entry_name}"
                )
            stale_entries.add(entry_name)
        for entry_name in (
            "SingletonSocket",
            "SingletonCookie",
            "SingletonLock",
        ):
            if entry_name not in stale_entries:
                continue
            try:
                os.unlink(entry_name, dir_fd=directory_fd)
            except OSError as exc:
                fail(
                    "cannot remove stale managed ChatGPT singleton entry "
                    f"{profile_directory}/{entry_name}: {exc}"
                )
    finally:
        os.close(directory_fd)


def add_runtime_bind(
    command: list[str],
    host_runtime_dir: str,
    sandbox_runtime_dir: str,
    relative_path: str,
    expected_kind: str,
    *,
    required: bool = False,
) -> None:
    relative = pathlib.PurePosixPath(relative_path)
    if (
        not relative_path
        or relative.is_absolute()
        or ".." in relative.parts
        or "\0" in relative_path
    ):
        fail(f"invalid runtime bind path: {relative_path or 'unset'}")

    source_path = os.path.join(host_runtime_dir, relative_path)
    destination_path = os.path.join(sandbox_runtime_dir, relative_path)
    host_runtime_real = os.path.realpath(host_runtime_dir)
    source_real = os.path.realpath(source_path)
    if os.path.commonpath((host_runtime_real, source_real)) != host_runtime_real:
        fail(f"runtime bind escapes XDG_RUNTIME_DIR: {source_path}")
    try:
        source_stat = os.lstat(source_path)
    except FileNotFoundError:
        if required:
            fail(f"required runtime {expected_kind} is unavailable: {source_path}")
        return
    except OSError as exc:
        fail(f"cannot inspect runtime bind source {source_path}: {exc}")

    if stat.S_ISLNK(source_stat.st_mode):
        fail(f"runtime bind source must not be a symlink: {source_path}")
    if source_stat.st_uid != os.getuid():
        fail(f"runtime bind source must be owned by the current user: {source_path}")
    if expected_kind == "directory":
        if not stat.S_ISDIR(source_stat.st_mode):
            fail(f"runtime directory bind is not a directory: {source_path}")
    elif expected_kind == "socket":
        if not stat.S_ISSOCK(source_stat.st_mode):
            fail(f"runtime bind source is not a socket: {source_path}")
    else:
        fail(f"unsupported runtime bind kind: {expected_kind}")

    add_dir_chain(command, os.path.dirname(destination_path))
    command.extend(["--bind", source_path, destination_path])


def require_root_owned_directory(label: str, path: str) -> str:
    validate_absolute_path(label, path)
    try:
        metadata = os.lstat(path)
    except OSError as exc:
        fail(f"{label} is unavailable: {path}: {exc}")
    if (
        stat.S_ISLNK(metadata.st_mode)
        or not stat.S_ISDIR(metadata.st_mode)
        or metadata.st_uid != 0
        or metadata.st_mode & 0o022
    ):
        fail(
            f"{label} must be a root-owned directory not writable by group "
            f"or others: {path}"
        )
    return path


def require_root_owned_regular_file(
    label: str,
    path: str,
    *,
    executable: bool = False,
) -> str:
    validate_absolute_path(label, path)
    try:
        metadata = os.lstat(path)
    except OSError as exc:
        fail(f"{label} is unavailable: {path}: {exc}")
    if (
        stat.S_ISLNK(metadata.st_mode)
        or not stat.S_ISREG(metadata.st_mode)
        or metadata.st_uid != 0
        or metadata.st_mode & 0o022
        or (executable and not metadata.st_mode & stat.S_IXUSR)
    ):
        suffix = " executable" if executable else ""
        fail(
            f"{label} must be a root-owned regular{suffix} file not writable "
            f"by group or others: {path}"
        )
    return path


def add_system_usr_mount(command: list[str]) -> None:
    command.extend(["--ro-bind", "/usr", "/usr"])


def require_private_xkbcomp_overlay(path: str) -> str:
    if path != PRIVATE_XKBCOMP_OVERLAY_DIRECTORY:
        fail("private XKB compiler overlay is outside the managed runtime")
    if os.path.lexists(PRIVATE_XKBCOMP_DESTINATION):
        fail("system XKB compiler must remain absent outside the managed sandbox")
    require_root_owned_directory("private XKB compiler overlay", path)
    try:
        overlay_metadata = os.lstat(path)
        overlay_entries = tuple(sorted(entry.name for entry in os.scandir(path)))
    except OSError as exc:
        fail(f"private XKB compiler overlay is unavailable: {path}: {exc}")
    if stat.S_IMODE(overlay_metadata.st_mode) != 0o555:
        fail("private XKB compiler overlay must be mode 0555")
    if overlay_entries != ("xkbcomp",):
        fail(
            "private XKB compiler overlay must contain only the managed "
            "xkbcomp entry"
        )
    overlay_entry = os.path.join(path, "xkbcomp")
    require_root_owned_regular_file(
        "private XKB compiler",
        PRIVATE_XKBCOMP_SOURCE,
        executable=True,
    )
    require_root_owned_regular_file(
        "private XKB compiler overlay entry",
        overlay_entry,
        executable=True,
    )
    try:
        same_file = os.path.samefile(PRIVATE_XKBCOMP_SOURCE, overlay_entry)
    except OSError as exc:
        fail(f"cannot compare private XKB compiler overlay entry: {exc}")
    if not same_file:
        fail("private XKB compiler overlay entry must hard-link the private binary")
    return path


def add_private_xkbcomp_overlay(command: list[str], overlay_directory: str) -> None:
    overlay_directory = require_private_xkbcomp_overlay(overlay_directory)
    command.extend(
        [
            "--overlay-src",
            "/usr/bin",
            "--overlay-src",
            overlay_directory,
            "--ro-overlay",
            "/usr/bin",
        ]
    )


def create_synthetic_identity_files(
    temp_root: str,
    home_dir: str,
    *,
    resolv_conf: str | None = None,
    shell_path: str = "/bin/sh",
) -> dict[str, str]:
    if shell_path not in {"/bin/sh", "/bin/zsh"}:
        fail(f"unsupported synthetic account shell: {shell_path}")
    machine_id_path = require_root_owned_regular_file(
        "host machine ID",
        HOST_MACHINE_ID_PATH,
    )
    try:
        with open(machine_id_path, encoding="ascii") as handle:
            host_machine_id_text = handle.read(MAX_HOST_MACHINE_ID_BYTES + 1)
    except (OSError, UnicodeError) as exc:
        fail(f"cannot read host machine ID: {exc}")
    if len(host_machine_id_text) > MAX_HOST_MACHINE_ID_BYTES:
        fail("host machine ID exceeds the managed size limit")
    host_machine_id = host_machine_id_text.strip()
    if re.fullmatch(r"[0-9a-f]{32}", host_machine_id) is None:
        fail("host machine ID must contain 32 lowercase hexadecimal characters")

    identity_seed = hashlib.sha256(
        SYNTHETIC_IDENTITY_DOMAIN
        + b"\0"
        + bytes.fromhex(host_machine_id)
        + b"\0"
        + os.getuid().to_bytes(8, byteorder="big", signed=False)
    ).digest()
    machine_id = hashlib.sha256(identity_seed + b"\0machine-id").hexdigest()[:32]
    boot_id = str(
        uuid.UUID(
            bytes=hashlib.sha256(identity_seed + b"\0boot-id").digest()[:16],
            version=5,
        )
    )
    installation_id = str(
        uuid.UUID(
            bytes=hashlib.sha256(
                identity_seed + b"\0installation-id"
            ).digest()[:16],
            version=5,
        )
    )
    hostname = f"chatgpt-{machine_id[:12]}"
    identity = {
        "machine_id": os.path.join(temp_root, "machine-id"),
        "boot_id": os.path.join(temp_root, "boot-id"),
        "installation_id": os.path.join(temp_root, "installation_id"),
        "hostname": os.path.join(temp_root, "hostname"),
        "passwd": os.path.join(temp_root, "passwd"),
        "group": os.path.join(temp_root, "group"),
        "hosts": os.path.join(temp_root, "hosts"),
        "resolv": os.path.join(temp_root, "resolv.conf"),
        "nsswitch": os.path.join(temp_root, "nsswitch.conf"),
        "cmdline": os.path.join(temp_root, "cmdline"),
        "empty": os.path.join(temp_root, "empty"),
        "hostname_value": hostname,
    }
    if resolv_conf is None:
        resolv_conf = filtered_resolv_conf()
    if (
        not resolv_conf
        or len(resolv_conf.encode("utf-8")) > 4_096
        or "\0" in resolv_conf
    ):
        fail("synthetic resolver policy is invalid")

    content = {
        "machine_id": f"{machine_id}\n",
        "boot_id": f"{boot_id}\n",
        "installation_id": installation_id,
        "hostname": f"{hostname}\n",
        "passwd": (
            "root:x:0:0:root:/root:/usr/sbin/nologin\n"
            f"developer:x:{os.getuid()}:{os.getgid()}:Managed Developer:{home_dir}:{shell_path}\n"
        ),
        "group": (
            "root:x:0:\n"
            f"developer:x:{os.getgid()}:developer\n"
        ),
        "hosts": (
            "127.0.0.1 localhost\n"
            f"127.0.1.1 {hostname}\n"
            "::1 localhost ip6-localhost ip6-loopback\n"
        ),
        "resolv": resolv_conf,
        "nsswitch": (
            "passwd: files\n"
            "group: files\n"
            "shadow: files\n"
            "gshadow: files\n"
            "hosts: files dns\n"
            "networks: files dns\n"
            "protocols: files\n"
            "services: files\n"
            "ethers: files\n"
            "rpc: files\n"
            "netgroup: files\n"
        ),
        "cmdline": "root=/dev/mapper/managed-root ro quiet\n",
        "empty": "",
    }
    for name, value in content.items():
        with open(identity[name], "w", encoding="utf-8") as handle:
            handle.write(value)
        os.chmod(identity[name], 0o644 if name == "installation_id" else 0o600)
    return identity


def add_synthetic_codex_installation_id_mount(
    command: list[str],
    installation_id_path: str,
) -> None:
    validate_absolute_path(
        "synthetic Codex installation id",
        installation_id_path,
    )
    try:
        installation_id_stat = os.lstat(installation_id_path)
    except OSError as exc:
        fail(f"cannot inspect synthetic Codex installation id: {exc}")
    if (
        stat.S_ISLNK(installation_id_stat.st_mode)
        or not stat.S_ISREG(installation_id_stat.st_mode)
        or installation_id_stat.st_uid != os.getuid()
        or stat.S_IMODE(installation_id_stat.st_mode) != 0o644
    ):
        fail(
            "synthetic Codex installation id must be a current-user-owned "
            f"regular file with mode 0644: {installation_id_path}"
        )
    command.extend(
        [
            "--bind",
            installation_id_path,
            MANAGED_CODEX_INSTALLATION_ID,
        ]
    )


def add_synthetic_identity_mounts(
    command: list[str],
    identity: dict[str, str],
) -> None:
    add_dir_chain(command, "/var/lib/dbus")
    for source_name, destination in (
        ("machine_id", "/etc/machine-id"),
        ("machine_id", "/var/lib/dbus/machine-id"),
        ("hostname", "/etc/hostname"),
        ("passwd", "/etc/passwd"),
        ("group", "/etc/group"),
        ("hosts", "/etc/hosts"),
        ("resolv", "/etc/resolv.conf"),
        ("nsswitch", "/etc/nsswitch.conf"),
        ("boot_id", "/proc/sys/kernel/random/boot_id"),
        ("hostname", "/proc/sys/kernel/hostname"),
        ("cmdline", "/proc/cmdline"),
    ):
        command.extend(["--ro-bind", identity[source_name], destination])
    for destination in (
        "/proc/diskstats",
        "/proc/interrupts",
        "/proc/iomem",
        "/proc/ioports",
        "/proc/kallsyms",
        "/proc/modules",
        "/proc/partitions",
    ):
        if os.path.exists(destination):
            command.extend(["--ro-bind", identity["empty"], destination])


def add_synthetic_sysfs_masks(command: list[str]) -> None:
    for path in (
        "/sys/block",
        "/sys/bus/scsi/devices",
        "/sys/class/block",
        "/sys/class/dmi/id",
        "/sys/class/net",
        "/sys/class/nvme",
        "/sys/devices/virtual/block",
        "/sys/devices/virtual/dmi/id",
        "/sys/devices/virtual/net",
        "/sys/firmware",
    ):
        if os.path.isdir(path) and not os.path.islink(path):
            command.extend(["--tmpfs", path])


def persistent_sandbox_argv(
    app_name: str,
    mode: str,
    extra_args: list[str],
    home_dir: str,
) -> list[str]:
    sandbox = PERSISTENT_SANDBOX_CONFIG.get(app_name)
    if sandbox is None:
        fail(f"persistent sandbox mode is not supported for {app_name}")

    argv = build_argv(app_name, mode, extra_args)
    argv[1:1] = [
        *(
            argument.replace("{HOME}", home_dir)
            for argument in sandbox["config_args"]
        ),
        *sandbox.get("inner_sandbox_args", ()),
    ]
    return argv


def select_persistent_sandbox_chdir(
    home_dir: str,
    sandbox: dict[str, object],
) -> str:
    fallback = os.path.join(home_dir, str(sandbox["chdir"]))
    validate_absolute_path("persistent sandbox working directory", fallback)
    if not os.path.isdir(fallback):
        fail(f"persistent sandbox working directory is unavailable: {fallback}")
    if not sandbox.get("preserve_working_directory", False):
        return fallback

    try:
        host_cwd = os.getcwd()
    except OSError as exc:
        fail(f"cannot resolve the physical working directory: {exc}")
    validate_absolute_path("physical working directory", host_cwd)
    if "\n" in host_cwd or "\r" in host_cwd:
        fail("physical working directory contains unsupported characters")
    if os.path.realpath(host_cwd) != host_cwd:
        fail(f"physical working directory must not traverse symlinks: {host_cwd}")

    allowed_roots = (
        *(
            os.path.join(home_dir, relative_path)
            for relative_path in sandbox.get("rw_bind_home_directories", ())
        ),
        *sandbox.get("rw_bind_paths", ()),
    )
    for allowed_root in allowed_roots:
        validate_absolute_path(
            "persistent sandbox writable working-directory root",
            allowed_root,
        )
        if allowed_root == "/" or os.path.normpath(allowed_root) != allowed_root:
            fail(
                "persistent sandbox writable working-directory root is unsafe: "
                f"{allowed_root}"
            )
        if host_cwd == allowed_root or host_cwd.startswith(f"{allowed_root}/"):
            return host_cwd
    return fallback


def _run_persistent_sandbox(
    app_name: str,
    mode: str,
    extra_args: list[str],
    *,
    payload_argv_prefix: tuple[str, ...] = (),
    private_xwayland_binary: str | None = None,
    private_xkbcomp_overlay_directory: str | None = None,
) -> int:
    sandbox = PERSISTENT_SANDBOX_CONFIG.get(app_name)
    if sandbox is None:
        fail(f"persistent sandbox mode is not supported for {app_name}")
    share_net = sandbox.get("share_net")
    slirp4netns_enabled = sandbox.get("slirp4netns", False)
    if not isinstance(share_net, bool):
        fail(f"persistent sandbox network-sharing policy is invalid for {app_name}")
    if not isinstance(slirp4netns_enabled, bool):
        fail(f"persistent sandbox slirp4netns policy is invalid for {app_name}")
    if share_net and slirp4netns_enabled:
        fail(
            f"persistent sandbox cannot share the host network and use slirp4netns: {app_name}"
        )
    if private_xwayland_binary is not None and app_name not in WAYLAND_COMPAT_APPS:
        fail(f"private Xwayland is not permitted for {app_name}")
    if private_xwayland_binary is not None and (
        not payload_argv_prefix or payload_argv_prefix[-1] != "--"
    ):
        fail("private Xwayland requires a bounded lifecycle-helper prefix")
    if private_xwayland_binary is not None:
        if private_xwayland_binary != PRIVATE_XWAYLAND_BINARY:
            fail("private Xwayland executable is outside the managed runtime")
        if private_xkbcomp_overlay_directory is None:
            fail("private Xwayland requires the managed XKB compiler")
        require_root_owned_regular_file(
            "private Xwayland executable",
            private_xwayland_binary,
            executable=True,
        )
    elif private_xkbcomp_overlay_directory is not None:
        fail("private XKB compiler is restricted to the private Xwayland sandbox")

    env = build_environment(app_name, mode)
    env.pop("DBUS_SYSTEM_BUS_ADDRESS", None)
    home_dir = env["HOME"]
    host_runtime_dir = env["XDG_RUNTIME_DIR"]
    validate_absolute_path("sandbox HOME", home_dir)
    validate_absolute_path("host XDG_RUNTIME_DIR", host_runtime_dir)
    home_stat = os.lstat(home_dir)
    if stat.S_ISLNK(home_stat.st_mode) or not stat.S_ISDIR(home_stat.st_mode) or home_stat.st_uid != os.getuid():
        fail(f"sandbox HOME is not a directory owned by the current user: {home_dir}")

    bwrap = require_root_owned_executable("bubblewrap", "/usr/bin/bwrap")

    persistent_directories = [
        persistent_app_directory(home_dir, relative_path)
        for relative_path in sandbox["persistent_paths"]
    ]
    shared_temp_directory = None
    shared_temp_entry = sandbox.get("shared_temp_directory")
    if shared_temp_entry is not None:
        if not isinstance(shared_temp_entry, str):
            fail(f"persistent sandbox shared temp name is invalid for {app_name}")
        shared_temp_directory = persistent_runtime_directory(
            host_runtime_dir,
            shared_temp_entry,
        )
        env["TMPDIR"] = shared_temp_directory
    sandbox_chdir = select_persistent_sandbox_chdir(home_dir, sandbox)
    wayland_display = env["WAYLAND_DISPLAY"]
    if private_xwayland_binary is not None:
        env.update(CAGE_WLROOTS_ENVIRONMENT)
        env["LD_LIBRARY_PATH"] = PRIVATE_XWAYLAND_LIBRARY_DIRECTORY
        env["WLR_XWAYLAND"] = private_xwayland_binary
        env[OUTER_WAYLAND_DISPLAY_ENVIRONMENT] = wayland_display
    host_wayland_socket = current_user_runtime_socket("Wayland socket", wayland_display)

    temp_root = tempfile.mkdtemp(
        prefix=f"labwc-{app_name}-sandbox-",
        dir=host_runtime_dir if os.path.isdir(host_runtime_dir) else None,
    )
    synthetic_identity = (
        create_synthetic_identity_files(
            temp_root,
            home_dir,
            resolv_conf=(
                slirp4netns_resolv_conf()
                if slirp4netns_enabled
                else None
            ),
            shell_path=env["SHELL"],
        )
        if sandbox.get("synthetic_identity", False)
        else None
    )
    slirp4netns_resolver_path = (
        create_slirp4netns_resolver_file(temp_root)
        if slirp4netns_enabled and synthetic_identity is None
        else None
    )
    proxy_processes: list[
        tuple[subprocess.Popen | None, socket.socket | None]
    ] = []
    session_proxy_socket = None
    system_proxy_socket = None
    try:
        (
            session_proxy_process,
            session_proxy_socket,
            session_proxy_lifecycle,
        ) = start_session_bus_proxy(
            temp_root,
            sandbox["dbus_names"],
            sandbox.get("dbus_own_names", ()),
            required=sandbox.get("require_session_bus", False),
        )
        if session_proxy_process is not None:
            proxy_processes.append(
                (session_proxy_process, session_proxy_lifecycle)
            )
        if (
            "system_dbus_names" in sandbox
            or sandbox.get("require_system_bus", False)
        ):
            (
                system_proxy_process,
                system_proxy_socket,
                system_proxy_lifecycle,
            ) = start_system_bus_proxy(
                temp_root,
                sandbox.get("system_dbus_names", ()),
                required=sandbox.get("require_system_bus", False),
            )
            if system_proxy_process is not None:
                proxy_processes.append(
                    (system_proxy_process, system_proxy_lifecycle)
                )
    except BaseException:
        stop_dbus_proxies(proxy_processes)
        shutil.rmtree(temp_root, ignore_errors=True)
        raise
    argv = persistent_sandbox_argv(app_name, mode, extra_args, home_dir)
    command = [
        bwrap,
        "--unshare-all",
    ]
    if share_net:
        command.append("--share-net")
    command.extend(
        [
            "--new-session",
            "--die-with-parent",
            "--clearenv",
            "--uid",
            str(os.getuid()),
            "--gid",
            str(os.getgid()),
            *(
                (
                    "--hostname",
                    synthetic_identity["hostname_value"],
                    "--cap-drop",
                    "ALL",
                )
                if synthetic_identity is not None
                else ()
            ),
            "--proc",
            "/proc",
            "--dev",
            "/dev",
            "--chdir",
            sandbox_chdir,
        ]
    )
    add_private_tmpfs_mounts(command)
    inherited_fds: tuple[int, ...] = ()
    if private_xwayland_binary is not None:
        command.extend(
            [
                "--dir",
                PRIVATE_X11_SOCKET_DIRECTORY,
                "--chmod",
                "01777",
                PRIVATE_X11_SOCKET_DIRECTORY,
            ]
        )

    add_dir_chain(command, "/etc")
    add_dir_chain(command, "/opt")
    add_dir_chain(command, os.path.dirname(home_dir))

    add_system_usr_mount(command)
    if private_xkbcomp_overlay_directory is not None:
        add_private_xkbcomp_overlay(command, private_xkbcomp_overlay_directory)
    for source, destination in (
        ("/bin", "/bin"),
        ("/lib", "/lib"),
        ("/sys", "/sys"),
    ):
        command.extend(["--ro-bind", source, destination])
    for source in sandbox["ro_bind_paths"]:
        add_optional_bind(command, "--ro-bind", source, source)
    for source, destination in (
        ("/sbin", "/sbin"),
        ("/lib64", "/lib64"),
        ("/lib32", "/lib32"),
    ):
        add_optional_bind(command, "--ro-bind", source, destination)
    synthetic_etc_paths = {
        "/etc/group",
        "/etc/hostname",
        "/etc/hosts",
        "/etc/machine-id",
        "/etc/nsswitch.conf",
        "/etc/passwd",
        "/etc/resolv.conf",
    }
    for path in (
        "/etc/alternatives",
        "/etc/ca-certificates",
        "/etc/fonts",
        "/etc/group",
        "/etc/hosts",
        "/etc/ld.so.cache",
        "/etc/ld.so.conf",
        "/etc/ld.so.conf.d",
        "/etc/localtime",
        "/etc/machine-id",
        "/etc/mime.types",
        "/etc/nsswitch.conf",
        "/etc/passwd",
        "/etc/pki",
        "/etc/resolv.conf",
        "/etc/ssl",
    ):
        if synthetic_identity is not None and path in synthetic_etc_paths:
            continue
        if slirp4netns_resolver_path is not None and path == "/etc/resolv.conf":
            continue
        add_optional_bind(command, "--ro-bind", path, path)
    if synthetic_identity is not None:
        add_synthetic_identity_mounts(command, synthetic_identity)
        add_synthetic_sysfs_masks(command)
    elif slirp4netns_resolver_path is not None:
        command.extend(
            ["--ro-bind", slirp4netns_resolver_path, "/etc/resolv.conf"]
        )

    command.extend(["--tmpfs", home_dir, "--chmod", "0700", home_dir])
    for directory in persistent_directories:
        add_dir_chain(command, directory)
        command.extend(["--bind", directory, directory])
    add_persistent_directory_binds(
        command,
        home_dir,
        sandbox.get("persistent_directory_binds", ()),
    )
    for relative_path in sandbox.get("ro_bind_home_paths", ()):
        source_path = resolve_home_relative_file(home_dir, relative_path)
        destination_path = os.path.join(home_dir, relative_path)
        add_dir_chain(command, os.path.dirname(destination_path))
        command.extend(["--ro-bind", source_path, destination_path])
    for relative_path in sandbox.get("rw_bind_home_paths", ()):
        source_path = resolve_home_relative_file(
            home_dir,
            relative_path,
            writable=True,
        )
        destination_path = os.path.join(home_dir, relative_path)
        add_dir_chain(command, os.path.dirname(destination_path))
        command.extend(["--bind", source_path, destination_path])
    add_optional_home_file_binds(
        command,
        home_dir,
        sandbox.get("ro_bind_home_optional_files", ()),
    )
    add_home_directory_binds(
        command,
        home_dir,
        sandbox.get("ro_bind_home_directories", ()),
        "--ro-bind",
    )
    add_home_directory_binds(
        command,
        home_dir,
        sandbox.get("rw_bind_home_directories", ()),
        "--bind",
    )
    add_absolute_directory_binds(
        command,
        sandbox.get("ro_bind_directory_paths", ()),
        "--ro-bind",
    )
    add_absolute_directory_binds(
        command,
        sandbox.get("rw_bind_paths", ()),
        "--bind",
    )
    add_absolute_directory_bind_pairs(
        command,
        sandbox.get("rw_bind_directory_pairs", ()),
        "--bind",
    )
    runtime_socket_paths = sandbox["runtime_sockets"]
    sandbox_runtime_dir = f"/run/user/{os.getuid()}"
    add_dir_chain(command, os.path.dirname(sandbox_runtime_dir))
    command.extend(["--dir", sandbox_runtime_dir, "--chmod", "0700", sandbox_runtime_dir])
    if shared_temp_directory is not None:
        add_dir_chain(command, shared_temp_directory)
        command.extend(
            [
                "--bind",
                shared_temp_directory,
                shared_temp_directory,
            ]
        )
    command.extend(["--bind", host_wayland_socket, os.path.join(sandbox_runtime_dir, wayland_display)])

    for relative_runtime_path in sandbox["runtime_directories"]:
        add_runtime_bind(
            command,
            host_runtime_dir,
            sandbox_runtime_dir,
            relative_runtime_path,
            "directory",
        )
    for relative_runtime_path in runtime_socket_paths:
        add_runtime_bind(
            command,
            host_runtime_dir,
            sandbox_runtime_dir,
            relative_runtime_path,
            "socket",
            required=relative_runtime_path
            in sandbox.get("required_runtime_sockets", ()),
        )

    add_video_device_binds(command, sandbox.get("camera_devices", False))
    add_gpu_device_binds(command, mode)

    if session_proxy_socket:
        sandbox_bus_socket = os.path.join(sandbox_runtime_dir, "bus")
        command.extend(["--bind", session_proxy_socket, sandbox_bus_socket])
        env["DBUS_SESSION_BUS_ADDRESS"] = f"unix:path={sandbox_bus_socket}"
    else:
        env.pop("DBUS_SESSION_BUS_ADDRESS", None)

    if system_proxy_socket:
        add_system_bus_proxy_bind(command, system_proxy_socket)
        env["DBUS_SYSTEM_BUS_ADDRESS"] = SYSTEM_BUS_ADDRESS
    else:
        env.pop("DBUS_SYSTEM_BUS_ADDRESS", None)

    if synthetic_identity is not None:
        env.update(
            {
                "USER": "developer",
                "LOGNAME": "developer",
                "HOSTNAME": synthetic_identity["hostname_value"],
            }
        )
    validate_no_host_audio_device_binds(app_name, command)

    outer_wayland_lock_fd: int | None = None
    lifecycle_lock_fd: int | None = None
    try:
        if private_xwayland_binary is not None:
            outer_wayland_lock_fd = reserve_outer_wayland_socket_name(
                command,
                temp_root,
                sandbox_runtime_dir,
                wayland_display,
            )
        if app_name == "chatgpt":
            if synthetic_identity is None:
                fail("ChatGPT requires a synthetic identity")
            lifecycle_lock_fd, stale_cleanup_allowed = (
                open_chatgpt_lifecycle_lock(host_runtime_dir)
            )
            if stale_cleanup_allowed:
                remove_stale_chatgpt_singletons(home_dir)
                fcntl.flock(lifecycle_lock_fd, fcntl.LOCK_SH)
            add_synthetic_codex_installation_id_mount(
                command,
                synthetic_identity["installation_id"],
            )
        for key, value in env.items():
            command.extend(["--setenv", key, value])
        payload_argv = [*payload_argv_prefix, *argv]
        if slirp4netns_enabled:
            return run_slirp4netns_sandbox(
                command,
                payload_argv,
                temp_root,
                inherited_fds,
            )
        command.extend(payload_argv)
        completed = subprocess.run(
            command,
            check=False,
            cwd="/",
            env=managed_subprocess_environment(),
            pass_fds=inherited_fds,
        )
        return completed.returncode
    finally:
        _close_file_descriptor(outer_wayland_lock_fd)
        if lifecycle_lock_fd is not None:
            os.close(lifecycle_lock_fd)
        stop_dbus_proxies(proxy_processes)
        shutil.rmtree(temp_root, ignore_errors=True)


def run_persistent_sandbox(app_name: str, mode: str, extra_args: list[str]) -> int:
    if app_name in WAYLAND_COMPAT_APPS:
        fail(
            f"{app_name} must use the dedicated native-Wayland compatibility entrypoint"
        )
    return _run_persistent_sandbox(app_name, mode, extra_args)
