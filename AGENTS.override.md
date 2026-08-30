# Repository Override Guidelines

## Project Structure and Ownership

- Treat `d-i/forky/` as installer source. Start at `preseed.cfg`; keep static answers in `common.cfg` and `fragments/*.cfg`.
- Keep class metadata in `classes/install.conf` and `classes/configs/*.cfg`; implementations live under the `class-*` directories.
- Keep authoritative profile policy in `hosts/profiles/**` and shared defaults in `hosts/shared/*.env`.
- Keep stage logic separated under `scripts/{preseed,early,partman,late,firstboot,runtime}/`.
- Treat `hooks/{shared,hardware,role,services}/**/target/**` as tracked runtime-mirror sources. Strip the `target/` prefix for the installed path; for example, `hooks/shared/target/etc/zram-writeback.conf` installs as `/etc/zram-writeback.conf`. Files ending in `.tmpl` are authoritative templates and render to the corresponding path without `.tmpl`.
- Avoid tests under `t/` unless requested. Do not invent packaging or release surfaces for installer-only changes.
- You are NOT allowed to include verification of content in config files or services inside the verfiy.sh script! Tests must be adapted to code base and NOT vice versa!!

## Protected Waybar Power-Button Shutdown Contract

- The shutdown behavior reached from either rendered Waybar `custom/power` button is a protected invariant and MUST NOT be changed, removed, renamed, refactored, regenerated, rewired, or "cleaned up" unless the user explicitly requests a change to that exact behavior in the current request.
- The protected scope includes the `custom/power` module and click handler, `labwc-power-menu`, `labwc-admin-action`, Labwc logout and shutdown hooks, the GVfs Labwc-session drop-in, and all related renderer or staging code, systemd, Polkit, AppArmor, documentation, and test coverage. Adjacent desktop, session, cleanup, verification, or security work must preserve this flow exactly; broad requests do not imply permission to touch it.

## Fresh-Install and Evidence Model

- Serve this read-only tree to remote hosts. Treat every run as a fresh installation into a new `/target`; create all managed files, accounts, packages, directories, and service links each time. Do not implement upgrades, migrations, or reliance on earlier target state.
- Never use the current development host—its `/etc`, installed packages, services, logs, caches, or command output—as source of truth. Tracked repository files define intended state.
- When repository evidence is insufficient for package or configuration facts, use web search only and prefer official Debian or upstream documentation. Do not query local `apt`, `dpkg`, or system files; record the external source used.

## Generated Files and Mirrors

- Never edit or commit installer runtime output under `/tmp/install-runtime/**`, including `state/plan.tsv`, `cache/classes.state.conf`, and `runtime.env`.
- Update tracked class, profile, template, and renderer or staging sources together. Never patch runtime `/target/**`.

## Branch and Mutation Rules

- Work only on `mcr/main`; verify with `git branch --show-current`.
- No `gitlab/*` or `github/*` refs currently exist. If either namespace appears, treat those branches as read-only mirrors and keep work on `mcr/main`. In mirror mode, limit direct edits to `.gitlab-ci.yml`, `Makefile`, `scripts/release/**`, `debian/**`, `.bazelversion`, `.bazelignore`, `.bazelrc`, and `bazel/**`.
- Preserve untracked `logs/` and all unrelated user changes. Never add plaintext passwords, tokens, bootstrap secrets, private keys, or real kernel-command-line credentials.
