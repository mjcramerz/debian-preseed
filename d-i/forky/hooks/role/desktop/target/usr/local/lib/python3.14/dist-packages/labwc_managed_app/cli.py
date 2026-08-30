"""Command-line entrypoint for managed Labwc applications."""

from __future__ import annotations

import argparse
import os

from .commands import build_argv, resolved_executable, validate_required_runtime_files
from .environment import (
    build_environment,
    ensure_discord_managed_settings,
    ensure_managed_runtime_state,
    ensure_obsidian_registry,
    load_managed_launch_policy,
    validate_acceleration_mode,
)
from .profiles import APPS, WAYLAND_COMPAT_APPS
from .runtime import MANAGED_DEFAULTS_PATH, current_user_home, fail
from .sandbox import (
    run_persistent_sandbox,
    run_pure_privacy,
)


def main(*, wayland_compat: bool = False) -> int:
    if wayland_compat:
        program_name = "labwc-managed-wayland-compat-app"
        application_choices = WAYLAND_COMPAT_APPS
        mode_choices = ("auto", "launch", "intel", "nvidia")
    else:
        program_name = "labwc-managed-app"
        application_choices = tuple(
            sorted(set(APPS).difference(WAYLAND_COMPAT_APPS))
        )
        mode_choices = ("auto", "launch", "intel", "nvidia", "pure-privacy")

    parser = argparse.ArgumentParser(prog=program_name)
    parser.add_argument(
        "mode",
        choices=mode_choices,
    )
    parser.add_argument("application", choices=application_choices)
    parser.add_argument("args", nargs=argparse.REMAINDER)
    options = parser.parse_args()

    if os.geteuid() == 0:
        fail(
            "managed desktop applications must run as the configured desktop "
            "user, never root"
        )

    acceleration_availability, default_mode = load_managed_launch_policy(
        MANAGED_DEFAULTS_PATH
    )
    mode = default_mode if options.mode == "auto" else options.mode
    validate_acceleration_mode(mode, acceleration_availability)

    app = APPS[options.application]
    executable = resolved_executable(options.application, mode)
    if not os.path.isfile(executable) or not os.access(executable, os.X_OK):
        fail(f"application executable is missing or not executable: {executable}")

    validate_required_runtime_files(options.application)
    if mode != "pure-privacy":
        home_dir = current_user_home()
        ensure_managed_runtime_state(
            options.application,
            home_dir,
        )
        if options.application == "discord":
            ensure_discord_managed_settings(home_dir)
        if options.application == "obsidian":
            ensure_obsidian_registry(home_dir)
    if mode == "pure-privacy":
        return run_pure_privacy(options.application, options.args)
    if wayland_compat:
        from .wayland_compat import run_wayland_compat_sandbox

        return run_wayland_compat_sandbox(
            options.application,
            mode,
            options.args,
        )
    if app.get("persistent_sandbox", False):
        return run_persistent_sandbox(options.application, mode, options.args)

    env = build_environment(options.application, mode)
    argv = build_argv(options.application, mode, options.args)
    os.execvpe(argv[0], argv, env)
    return 0
