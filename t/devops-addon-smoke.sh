#!/bin/sh
# shellcheck disable=SC2016
# This smoke test intentionally matches literal generated-shell expressions.
set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)

TEST_COUNT=38
TEST_INDEX=0
FAIL_COUNT=0
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/devops-addon-smoke.XXXXXX")
trap 'rm -rf -- "$TMP_DIR"' EXIT HUP INT TERM

pass() {
  TEST_INDEX=$((TEST_INDEX + 1))
  printf 'ok %s - %s\n' "$TEST_INDEX" "$1"
}

fail() {
  TEST_INDEX=$((TEST_INDEX + 1))
  FAIL_COUNT=$((FAIL_COUNT + 1))
  printf 'not ok %s - %s\n' "$TEST_INDEX" "$1"
}

word_list_has() {
  words=$1
  needle=$2

  case " $words " in
    *" $needle "*) return 0 ;;
  esac
  return 1
}

devops_profile_unsets_variables() {
  python3 - "$@" <<'PY'
import pathlib
import sys

lines = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8").splitlines()
for variable in sys.argv[2:]:
    expected = f"    {variable} " + chr(92)
    if lines.count(expected) != 1:
        raise AssertionError(
            f"managed DevOps unset block does not contain exactly one {variable!r}"
        )
PY
}

devops_nested_shell_works() {
  python3 - "$1" "$TMP_DIR" <<'PY'
import errno
import os
import pathlib
import pty
import pwd
import select
import shutil
import signal
import sys
import time

source_path = pathlib.Path(sys.argv[1]).resolve()
temp_root = pathlib.Path(sys.argv[2]).resolve() / "nested-shell"
temp_root.mkdir(mode=0o700)
runtime_dir = temp_root / "runtime"
runtime_dir.mkdir(mode=0o700)
runtime_dir.chmod(0o700)
home_dir = temp_root / "home"
home_dir.mkdir(mode=0o700)
profile_path = temp_root / "71-devops-de.sh"
account_name = pwd.getpwuid(os.getuid()).pw_name
pool_root = temp_root / "pool"
pool_root.mkdir(mode=0o2775)
pool_root.chmod(0o2775)
for storage_name in ("build", "cache", "db"):
    storage_root = pool_root / storage_name
    storage_root.mkdir(mode=0o2770)
    storage_root.chmod(0o2770)
    account_root = storage_root / account_name
    account_root.mkdir(mode=0o2770)
    account_root.chmod(0o2770)

child_assertions = r'''
[ "${DEVOPS_DE_ACTIVE:-}" = 1 ]
[ "$RUSTUP_TOOLCHAIN" = nightly ]
devops_de_test_tool_paths=$DEVOPS_DE_TEST_TOOL_PATHS
while [ -n "$devops_de_test_tool_paths" ]; do
  case "$devops_de_test_tool_paths" in
    *:*)
      devops_de_test_tool_path=${devops_de_test_tool_paths%%:*}
      devops_de_test_tool_paths=${devops_de_test_tool_paths#*:}
      ;;
    *)
      devops_de_test_tool_path=$devops_de_test_tool_paths
      devops_de_test_tool_paths=
      ;;
  esac
  case ":$PATH:" in
    *":${devops_de_test_tool_path}:"*) ;;
    *) exit 1 ;;
  esac
done
unset devops_de_test_tool_path devops_de_test_tool_paths
[ "$PYTHONPYCACHEPREFIX" = "$DEVOPS_DE_TEST_RUNTIME_DIR/python/pycache" ]
[ "$PYTHONUSERBASE" = "$DEVOPS_DE_TEST_POOL_ROOT/build/$USER/python" ]
[ "$PYTHON_HISTORY" = "$DEVOPS_DE_TEST_POOL_ROOT/db/$USER/python/history" ]
[ "$PYTHONSAFEPATH" = 1 ]
[ "$PYTHONUTF8" = 1 ]
[ "$PYTHONWARNDEFAULTENCODING" = 1 ]
[ -z "${PYTHONDONTWRITEBYTECODE+x}" ]
[ -z "${PYTHONHASHSEED+x}" ]
[ -z "${PYTHONHOME+x}" ]
[ -z "${PYTHONINSPECT+x}" ]
[ -z "${PYTHONOPTIMIZE+x}" ]
[ -z "${PYTHONPATH+x}" ]
[ -z "${PYTHONSTARTUP+x}" ]
[ -z "${PYTHONWARNINGS+x}" ]
[ -z "${VIRTUAL_ENV+x}" ]
[ -z "${VIRTUAL_ENV_PROMPT+x}" ]
[ "$PIP_CACHE_DIR" = "$DEVOPS_DE_TEST_POOL_ROOT/cache/$USER/pip" ]
[ "$UV_CACHE_DIR" = "$DEVOPS_DE_TEST_POOL_ROOT/cache/$USER/uv" ]
[ "$UV_TOOL_DIR" = "$DEVOPS_DE_TEST_POOL_ROOT/db/$USER/uv/tools" ]
[ "$UV_TOOL_BIN_DIR" = "$DEVOPS_DE_TEST_POOL_ROOT/build/$USER/uv/bin" ]
[ "$ANSIBLE_HOME" = "$DEVOPS_DE_TEST_POOL_ROOT/db/$USER/ansible" ]
[ "$ANSIBLE_GALAXY_CACHE_DIR" = "$DEVOPS_DE_TEST_POOL_ROOT/cache/$USER/ansible/galaxy" ]
[ "$ANSIBLE_LOCAL_TEMP" = "$DEVOPS_DE_TEST_RUNTIME_DIR/ansible/tmp" ]
[ "$ANSIBLE_PERSISTENT_CONTROL_PATH_DIR" = "$DEVOPS_DE_TEST_RUNTIME_DIR/ansible/pc" ]
[ "$ANSIBLE_SSH_CONTROL_PATH_DIR" = "$DEVOPS_DE_TEST_RUNTIME_DIR/ansible/ssh" ]
[ "$TF_PLUGIN_CACHE_DIR" = "$DEVOPS_DE_TEST_POOL_ROOT/cache/$USER/hashicorp/terraform/plugin-cache" ]
[ "$PACKER_CACHE_DIR" = "$DEVOPS_DE_TEST_POOL_ROOT/cache/$USER/hashicorp/packer/cache" ]
[ "$PACKER_CONFIG_DIR" = "$DEVOPS_DE_TEST_POOL_ROOT/cache/$USER/hashicorp/packer.d" ]
[ "$PACKER_CONFIG_PATH" = "$PACKER_CONFIG_DIR/config.json" ]
[ "$PACKER_CONFIG" = "$PACKER_CONFIG_PATH" ]
[ "$PACKER_PLUGIN_PATH" = "$PACKER_CONFIG_DIR/plugins" ]
[ "$DEVOPS_DATABASE_HOME" = "$DEVOPS_DE_TEST_POOL_ROOT/db/$USER" ]
[ "$PGDATA" = "$DEVOPS_DATABASE_HOME/postgresql/data" ]
[ "$PGSERVICEFILE" = "$DEVOPS_DATABASE_HOME/postgresql/pg_service.conf" ]
[ "$PGPASSFILE" = "$DEVOPS_DATABASE_HOME/postgresql/pgpass" ]
[ "$PSQL_HISTORY" = "$DEVOPS_DATABASE_HOME/postgresql/psql_history" ]
[ "$MYSQL_HOME" = "$DEVOPS_DATABASE_HOME/mysql/config" ]
[ "$MYSQL_HISTFILE" = "$DEVOPS_DATABASE_HOME/mysql/history" ]
[ "$MYSQLSH_USER_CONFIG_HOME" = "$DEVOPS_DATABASE_HOME/mysql-shell" ]
[ "$SQLITE_HISTORY" = "$DEVOPS_DATABASE_HOME/sqlite/history" ]
[ "$DUCKDB_HISTORY" = "$DEVOPS_DATABASE_HOME/duckdb/history" ]
[ "$REDISCLI_HISTFILE" = "$DEVOPS_DATABASE_HOME/redis-compatible/history" ]
[ "$USQL_CONFIG_FILE" = "$DEVOPS_DATABASE_HOME/usql/config.yaml" ]
[ "$QOREDB_CONFIG_DIR" = "$DEVOPS_DATABASE_HOME/qoredb/config" ]
[ "$GRIDLINE_DATA_HOME" = "$DEVOPS_DATABASE_HOME/gridline" ]
[ -z "${DEVOPS_DE_COMPLETIONS_ENABLED+x}" ]
printf '%s\n' entered >"$DEVOPS_DE_TEST_CHILD_MARKER"
case "${DEVOPS_DE_TEST_MODE:-}" in
  success)
    devops
    printf '%s\n' leaked >"$DEVOPS_DE_TEST_AFTER_DEACTIVATE"
    exit 91
    ;;
  failure)
    exit 42
    ;;
  *) exit 64 ;;
esac
'''

(home_dir / ".bashrc").write_text(
    '. "$DEVOPS_DE_TEST_PROFILE"\n' + child_assertions,
    encoding="utf-8",
)
(home_dir / ".zshrc").write_text(
    """devops_de_test_source_profile() {
  emulate -L sh
  . "$DEVOPS_DE_TEST_PROFILE"
}
devops_de_test_source_profile
unset -f devops_de_test_source_profile
"""
    + child_assertions,
    encoding="utf-8",
)

profile_source = source_path.read_text(encoding="utf-8")
rustup_bin_path = temp_root / "rustup" / "bin"
rustup_bin_path.mkdir(mode=0o755, parents=True)
rustup_init_path = rustup_bin_path / "rustup-init"
rustup_init_path.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
rustup_init_path.chmod(0o755)
if profile_source.count("/usr/local/lib/rustup/bin") != 2:
    raise AssertionError("unexpected managed Rustup bin reference count")
profile_source = profile_source.replace(
    "/usr/local/lib/rustup/bin",
    str(rustup_bin_path),
)

managed_tool_paths = []
for managed_path, relative_path in (
    ("/usr/local/lib/opentufo/bin", "opentufo/bin"),
    ("/usr/local/lib/wrangler/node_modules/.bin", "wrangler/node_modules/.bin"),
    ("/usr/local/lib/aptly/bin", "aptly/bin"),
    ("/usr/local/lib/osc/bin", "osc/bin"),
    ("/usr/local/lib/obs-build/bin", "obs-build/bin"),
):
    staged_path = temp_root / relative_path
    staged_path.mkdir(mode=0o755, parents=True)
    if profile_source.count(managed_path) != 2:
        raise AssertionError(f"unexpected managed tool-path reference count: {managed_path}")
    profile_source = profile_source.replace(managed_path, str(staged_path))
    managed_tool_paths.append(str(staged_path))

for managed_root, relative_root, expected_count, executable_name in (
    ("/usr/local/lib/ansible", "ansible", 5, "ansible"),
    ("/usr/local/lib/hashicorp/terraform", "hashicorp/terraform", 4, "terraform"),
    ("/usr/local/lib/hashicorp/packer", "hashicorp/packer", 4, "packer"),
):
    staged_root = temp_root / relative_root
    staged_bin = staged_root / "bin"
    staged_bin.mkdir(mode=0o755, parents=True)
    staged_executable = staged_bin / executable_name
    staged_executable.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
    staged_executable.chmod(0o755)
    if profile_source.count(managed_root) != expected_count:
        raise AssertionError(f"unexpected managed tool-root reference count: {managed_root}")
    profile_source = profile_source.replace(managed_root, str(staged_root))
    managed_tool_paths.append(str(staged_bin))

runtime_literal = '"/run/user/${devops_de_runtime_uid}"'
if profile_source.count(runtime_literal) != 1:
    raise AssertionError("unexpected managed runtime-directory check count")
profile_source = profile_source.replace(
    runtime_literal,
    '"$DEVOPS_DE_TEST_RUNTIME_DIR"',
)
pool_literal = "devops_de_pool_root=/pool"
if profile_source.count(pool_literal) != 1:
    raise AssertionError("unexpected managed pool-root assignment count")
profile_source = profile_source.replace(
    pool_literal,
    f"devops_de_pool_root={pool_root}",
)
profile_path.write_text(profile_source, encoding="utf-8")

parent_shells = ["/bin/sh", shutil.which("bash"), shutil.which("zsh")]
child_shells = [shutil.which("bash"), shutil.which("zsh")]
if any(not shell_path for shell_path in [*parent_shells, *child_shells]):
    raise AssertionError("POSIX sh, Bash, and Zsh are required for nested-shell coverage")

def run_in_pty(shell_path, command, environment, timeout_seconds=8):
    child_pid, master_fd = pty.fork()
    if child_pid == 0:
        os.execve(
            shell_path,
            [shell_path, "-c", command, "devops-nested-shell", str(profile_path)],
            environment,
        )

    output = bytearray()
    deadline = time.monotonic() + timeout_seconds
    child_status = None
    try:
        while time.monotonic() < deadline:
            readable, _, _ = select.select([master_fd], [], [], 0.1)
            if readable:
                try:
                    chunk = os.read(master_fd, 65536)
                except OSError as error:
                    if error.errno != errno.EIO:
                        raise
                    chunk = b""
                if chunk:
                    output.extend(chunk)

            waited_pid, waited_status = os.waitpid(child_pid, os.WNOHANG)
            if waited_pid == child_pid:
                child_status = waited_status
                break

        if child_status is None:
            os.kill(child_pid, signal.SIGKILL)
            _, child_status = os.waitpid(child_pid, 0)
            raise AssertionError(
                f"{shell_path} nested-shell test timed out: "
                f"{output.decode(errors='replace')!r}"
            )
    finally:
        os.close(master_fd)

    return os.waitstatus_to_exitcode(child_status), output.decode(errors="replace")


def assert_title_lifecycle(label, output):
    title_push = output.find("\x1b[22;0t")
    devops_title = output.find("\x1b]0;[devops]\x07")
    title_restore = output.rfind("\x1b[23;0t")
    if not 0 <= title_push < devops_title < title_restore:
        raise AssertionError(f"{label} did not push, set, and restore its title: {output!r}")


def assert_private_runtime_directories(label):
    runtime_entries = {entry.name for entry in runtime_dir.iterdir()}
    if runtime_entries != {"ansible", "python"}:
        raise AssertionError(
            f"{label} left unexpected runtime state behind: {sorted(runtime_entries)!r}"
        )
    private_directories = (
        runtime_dir / "python",
        runtime_dir / "ansible",
        runtime_dir / "ansible/tmp",
        runtime_dir / "ansible/pc",
        runtime_dir / "ansible/ssh",
    )
    for private_directory in private_directories:
        if (
            not private_directory.is_dir()
            or (private_directory.stat().st_mode & 0o777) != 0o700
        ):
            raise AssertionError(
                f"{label} did not retain a private mode-0700 directory: "
                f"{private_directory}"
            )
    database_root = pool_root / "db" / account_name
    private_database_directories = (
        "postgresql",
        "postgresql/data",
        "mysql",
        "mysql/config",
        "mysql-shell",
        "sqlite",
        "duckdb",
        "redis-compatible",
        "usql",
        "qoredb",
        "qoredb/config",
        "gridline",
    )
    for relative_path in private_database_directories:
        private_directory = database_root / relative_path
        if (
            not private_directory.is_dir()
            or (private_directory.stat().st_mode & 0o777) != 0o700
        ):
            raise AssertionError(
                f"{label} did not retain a private database directory: "
                f"{private_directory}"
            )


for parent_index, parent_shell in enumerate(parent_shells):
    for child_index, child_shell in enumerate(child_shells):
        label = f"{pathlib.Path(parent_shell).name}->{pathlib.Path(child_shell).name}"
        marker_suffix = f"{parent_index}.{child_index}"
        parent_marker = temp_root / f"parent.{marker_suffix}"
        child_marker = temp_root / f"child.{marker_suffix}"
        after_deactivate = temp_root / f"after-deactivate.{marker_suffix}"
        environment = {
            "HOME": str(home_dir),
            "USER": account_name,
            "LOGNAME": account_name,
            "PATH": "/usr/bin:/bin",
            "PYTHONPATH": "/untrusted/python-path",
            "SHELL": child_shell,
            "TERM": "xterm",
            "ZDOTDIR": str(home_dir),
            "XDG_RUNTIME_DIR": str(runtime_dir),
            "DEVOPS_DE_TEST_PROFILE": str(profile_path),
            "DEVOPS_DE_TEST_RUNTIME_DIR": str(runtime_dir),
            "DEVOPS_DE_TEST_POOL_ROOT": str(pool_root),
            "DEVOPS_DE_TEST_TOOL_PATHS": ":".join(
                [str(rustup_bin_path), *managed_tool_paths]
            ),
            "DEVOPS_DE_TEST_PARENT_MARKER": str(parent_marker),
            "DEVOPS_DE_TEST_CHILD_MARKER": str(child_marker),
            "DEVOPS_DE_TEST_AFTER_DEACTIVATE": str(after_deactivate),
            "DEVOPS_DE_COMPLETIONS_ENABLED": "1",
            "PYTHONDONTWRITEBYTECODE": "1",
            "PYTHONHASHSEED": "0",
            "PYTHONHOME": "/untrusted/python-home",
            "PYTHONINSPECT": "1",
            "PYTHONOPTIMIZE": "2",
            "PYTHONSTARTUP": "/untrusted/python-startup",
            "PYTHONWARNINGS": "ignore",
            "VIRTUAL_ENV": "/untrusted/virtual-env",
            "VIRTUAL_ENV_PROMPT": "(untrusted)",
        }

        environment["DEVOPS_DE_TEST_MODE"] = "success"
        status, output = run_in_pty(
            parent_shell,
            '. "$1"; devops_de_test_path=$PATH; '
            'devops_de_test_pythonpath=$PYTHONPATH; '
            'devops || exit 91; '
            '[ "$PATH" = "$devops_de_test_path" ] || exit 92; '
            '[ "$PYTHONPATH" = "$devops_de_test_pythonpath" ] || exit 93; '
            '[ "${DEVOPS_DE_COMPLETIONS_ENABLED:-}" = 1 ] || exit 94; '
            '[ -z "${DEVOPS_DE_ACTIVE+x}" ] || exit 95; '
            'printf resumed >"$DEVOPS_DE_TEST_PARENT_MARKER"',
            environment,
        )
        if status != 0:
            raise AssertionError(f"{label} successful nested shell exited {status}: {output!r}")
        assert_title_lifecycle(label, output)
        if parent_marker.read_text(encoding="utf-8") != "resumed":
            raise AssertionError(f"{label} did not resume its ordinary parent shell")
        if child_marker.read_text(encoding="utf-8") != "entered\n":
            raise AssertionError(f"{label} did not enter its activated child shell")
        if after_deactivate.exists():
            raise AssertionError(f"{label} continued after active-shell deactivation")
        assert_private_runtime_directories(label)

        parent_marker.unlink()
        child_marker.unlink()
        environment["DEVOPS_DE_TEST_MODE"] = "failure"
        status, output = run_in_pty(
            parent_shell,
            '. "$1"; devops_de_test_path=$PATH; '
            'devops_de_test_pythonpath=$PYTHONPATH; '
            'if devops; then exit 96; else devops_de_test_status=$?; fi; '
            '[ "$devops_de_test_status" -eq 42 ] || exit 97; '
            '[ "$PATH" = "$devops_de_test_path" ] || exit 98; '
            '[ "$PYTHONPATH" = "$devops_de_test_pythonpath" ] || exit 99; '
            '[ "${DEVOPS_DE_COMPLETIONS_ENABLED:-}" = 1 ] || exit 100; '
            '[ -z "${DEVOPS_DE_ACTIVE+x}" ] || exit 101; '
            'printf usable >"$DEVOPS_DE_TEST_PARENT_MARKER"',
            environment,
        )
        if status != 0:
            raise AssertionError(f"{label} failed child session exited {status}: {output!r}")
        assert_title_lifecycle(label, output)
        if parent_marker.read_text(encoding="utf-8") != "usable":
            raise AssertionError(f"{label} failed child did not leave its parent usable")
        if child_marker.read_text(encoding="utf-8") != "entered\n":
            raise AssertionError(f"{label} failing child shell never entered")
        if after_deactivate.exists():
            raise AssertionError(f"{label} created an impossible post-deactivation marker")
        assert_private_runtime_directories(label)
PY
}

devops_rc_completion_order_is_valid() {
  python3 - "$1" "$2" <<'PY'
import pathlib
import sys

bash_lines = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8").splitlines()
zsh_lines = pathlib.Path(sys.argv[2]).read_text(encoding="utf-8").splitlines()

def line_index(lines, value):
    matches = [index for index, line in enumerate(lines) if line == value]
    if len(matches) != 1:
        raise AssertionError(f"expected one startup call for {value!r}, got {matches!r}")
    return matches[0]

assert line_index(bash_lines, "bashrc_init_completion") < line_index(
    bash_lines, "bashrc_init_fzf"
) < line_index(bash_lines, "bashrc_init_devops_completions")
assert line_index(zsh_lines, "zshrc_init_completion") < line_index(
    zsh_lines, "zshrc_init_fzf"
) < line_index(zsh_lines, "zshrc_init_devops_completions")
PY
}

devops_shell_completions_work() {
  python3 - "$1" "$2" "$3" "$TMP_DIR" <<'PY'
import os
import pathlib
import pwd
import shutil
import subprocess
import sys

profile_source = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
bashrc_source = pathlib.Path(sys.argv[2]).read_text(encoding="utf-8")
zshrc_source = pathlib.Path(sys.argv[3]).read_text(encoding="utf-8")
temp_root = pathlib.Path(sys.argv[4]).resolve() / "shell-completions"
temp_root.mkdir(mode=0o700)

ansible_root = temp_root / "usr-local-lib" / "ansible"
terraform_root = temp_root / "usr-local-lib" / "hashicorp" / "terraform"
packer_root = temp_root / "usr-local-lib" / "hashicorp" / "packer"
replacements = {
    "/usr/local/lib/ansible": str(ansible_root),
    "/usr/local/lib/hashicorp/terraform": str(terraform_root),
    "/usr/local/lib/hashicorp/packer": str(packer_root),
}
for original, replacement in replacements.items():
    if original not in profile_source:
        raise AssertionError(f"completion profile path is missing: {original}")
    profile_source = profile_source.replace(original, replacement)

for root, command in (
    (ansible_root, "ansible"),
    (terraform_root, "terraform"),
    (packer_root, "packer"),
):
    binary = root / "bin" / command
    binary.parent.mkdir(mode=0o755, parents=True)
    binary.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
    binary.chmod(0o755)

bash_completion = ansible_root / "share/bash-completion/completions/ansible"
bash_completion.parent.mkdir(mode=0o755, parents=True)
bash_completion.write_text(
    'DEVOPS_TEST_ANSIBLE_COMPLETION_LOADS=$(( '
    '${DEVOPS_TEST_ANSIBLE_COMPLETION_LOADS:-0} + 1 ))\n'
    'complete -W "inventory playbook" ansible\n',
    encoding="utf-8",
)
zsh_completion = ansible_root / "share/zsh/site-functions/_ansible-managed"
zsh_completion.parent.mkdir(mode=0o755, parents=True)
zsh_completion.write_text(
    'DEVOPS_TEST_ANSIBLE_COMPLETION_LOADS=$(( '
    '${DEVOPS_TEST_ANSIBLE_COMPLETION_LOADS:-0} + 1 ))\n'
    '_ansible_managed_test() { _message managed-ansible; }\n'
    'compdef _ansible_managed_test ansible\n',
    encoding="utf-8",
)

account_name = pwd.getpwuid(os.getuid()).pw_name

def run_shell(label, executable, arguments, command, rc_source):
    home = temp_root / label
    profile_dir = home / ".profile.d"
    profile_dir.mkdir(mode=0o700, parents=True)
    (profile_dir / "71-devops-de.sh").write_text(profile_source, encoding="utf-8")
    (home / rc_source[0]).write_text(rc_source[1], encoding="utf-8")
    environment = {
        "DEVOPS_DE_ACTIVE": "1",
        "HOME": str(home),
        "LOGNAME": account_name,
        "PATH": "/usr/bin:/bin",
        "TERM": "dumb",
        "USER": account_name,
        "ZDOTDIR": str(home),
    }
    result = subprocess.run(
        [executable, *arguments, command],
        check=False,
        env=environment,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    if result.returncode != 0:
        raise AssertionError(
            f"{label} completion validation failed with {result.returncode}: "
            f"stdout={result.stdout!r} stderr={result.stderr!r}"
        )

bash = shutil.which("bash")
zsh = shutil.which("zsh")
if not bash or not zsh:
    raise AssertionError("Bash and Zsh are required for completion validation")

run_shell(
    "bash",
    bash,
    ["--noprofile", "--rcfile", str(temp_root / "bash/.bashrc"), "-i", "-c"],
    'test "${DEVOPS_DE_COMPLETIONS_ENABLED:-}" = 1 && '
    'test "${DEVOPS_TEST_ANSIBLE_COMPLETION_LOADS:-0}" = 1 && '
    'test -z "${devops_de_ansible_completion+x}" && '
    'complete -p ansible terraform packer >/dev/null && '
    'devops_de_enable_shell_completions && '
    'test "${DEVOPS_TEST_ANSIBLE_COMPLETION_LOADS:-0}" = 1 && '
    '! declare -F bashrc_init_devops_completions >/dev/null',
    (".bashrc", bashrc_source),
)
run_shell(
    "zsh",
    zsh,
    ["-d", "-i", "-c"],
    '(( ${DEVOPS_DE_COMPLETIONS_ENABLED:-0} == 1 )) && '
    '(( ${DEVOPS_TEST_ANSIBLE_COMPLETION_LOADS:-0} == 1 )) && '
    '(( ! ${+parameters[devops_de_ansible_completion]} )) && '
    '[[ ${_comps[ansible]-} = _ansible_managed_test ]] && '
    'complete -p terraform packer >/dev/null && '
    'devops_de_enable_shell_completions && '
    '(( ${DEVOPS_TEST_ANSIBLE_COMPLETION_LOADS:-0} == 1 )) && '
    '(( ! ${+functions[zshrc_init_devops_completions]} ))',
    (".zshrc", zshrc_source),
)
PY
}

devops_invalid_runtime_fails_before_mutation() {
  invalid_home="$TMP_DIR/invalid-runtime-home"
  invalid_runtime="$TMP_DIR/invalid-runtime"
  mkdir -m 0700 -- "$invalid_home" "$invalid_runtime"

  env -i \
    HOME="$invalid_home" \
    USER="$(id -un)" \
    LOGNAME="$(id -un)" \
    PATH=/usr/bin:/bin \
    PYTHONPATH=/untrusted/python-path \
    XDG_RUNTIME_DIR="$invalid_runtime" \
    /bin/sh -eu -c '
      . "$1"
      original_path=$PATH
      original_pythonpath=$PYTHONPATH
      if devops_de_apply_environment >/dev/null 2>&1; then
        exit 1
      fi
      [ "$PATH" = "$original_path" ]
      [ "$PYTHONPATH" = "$original_pythonpath" ]
    ' sh "$1"
}

publishing_templates_validate() {
  python3 - "$1" "$2" "$3" <<'PY'
import configparser
import json
import pathlib
import sys

aptly_path, osc_path, osc_metadata_path = map(pathlib.Path, sys.argv[1:])
replacements = {
    "__INSTALLER_ACCOUNT_USERNAME__": "developer",
    "__INSTALLER_DEVOPS_APTLY_ROOT_DIR__": "/pool/db/developer/aptly",
    "__INSTALLER_DEVOPS_APTLY_R2_ENDPOINT_NAME__": "r2",
    "__INSTALLER_DEVOPS_APTLY_R2_BUCKET__": "cf-aptly-r2-prod",
    "__INSTALLER_DEVOPS_APTLY_R2_ENDPOINT_URL__": "https://79cc1f5f831fb7f414638c3e758e9710.r2.cloudflarestorage.com",
    "__INSTALLER_DEVOPS_APTLY_R2_STORAGE_PREFIX__": "debian/",
    "__INSTALLER_DEVOPS_APTLY_DISTRIBUTIONS__": "stable testing",
    "__INSTALLER_DEVOPS_APTLY_COMPONENT__": "main",
    "__INSTALLER_DEVOPS_APTLY_PUBLISH_TARGET__": "s3:r2:",
    "__INSTALLER_DEVOPS_APTLY_WORKER_ROUTE__": "apt",
    "__INSTALLER_DEVOPS_APTLY_WORKER_ZONE__": "jcramer.xyz",
    "__INSTALLER_DEVOPS_APTLY_PUBLIC_BASE_URL__": "https://apt.jcramer.xyz",
    "__INSTALLER_DEVOPS_APTLY_REPOSITORY_KEY_FINGERPRINT__": "33808BDA7507EE103BADC3BCF575BD768D94A3470EFD5D17DC2C048ED01A93DC",
    "__INSTALLER_DEVOPS_APTLY_CREDENTIALS_BACKEND__": "keyring.backends.SecretService.Keyring",
    "__INSTALLER_DEVOPS_OBS_API_URL__": "https://api.opensuse.org",
    "__INSTALLER_DEVOPS_OSC_PACKAGE_CACHE_DIR__": "/pool/cache/developer/osc/packages",
    "__INSTALLER_DEVOPS_OSC_BUILD_ROOT__": "/pool/build/developer/osc/build-root",
    "__INSTALLER_DEVOPS_OSC_COOKIE_JAR__": "/pool/db/developer/osc/cookiejar",
    "__INSTALLER_DEVOPS_OSC_WORKDIR__": "/pool/build/developer/osc",
    "__INSTALLER_DEVOPS_OBS_PROJECT__": "home:cramerz:debian",
    "__INSTALLER_DEVOPS_OBS_REPOSITORY__": "Debian_Unstable",
    "__INSTALLER_DEVOPS_OSC_CREDENTIALS_BACKEND__": "keyring.backends.SecretService.Keyring",
}

def render(path):
    text = path.read_text()
    for key, value in replacements.items():
        text = text.replace(key, value)
    if "__INSTALLER_" in text:
        raise SystemExit(f"unresolved placeholder in {path}")
    return text

aptly = json.loads(render(aptly_path))
assert aptly["rootDir"] == "/pool/db/developer/aptly"
assert aptly["architectures"] == ["amd64", "source"]
assert aptly["managedLocalPublishing"] == {
    "schemaVersion": 1,
    "distributions": "stable testing",
    "component": "main",
    "publishTarget": "s3:r2:",
    "workerRoute": "apt",
    "workerZone": "jcramer.xyz",
    "publicBaseURL": "https://apt.jcramer.xyz",
    "signingKeyFingerprint": "33808BDA7507EE103BADC3BCF575BD768D94A3470EFD5D17DC2C048ED01A93DC",
    "credentialsBackend": "keyring.backends.SecretService.Keyring",
}
assert aptly["S3PublishEndpoints"]["r2"] == {
    "region": "auto",
    "bucket": "cf-aptly-r2-prod",
    "endpoint": "https://79cc1f5f831fb7f414638c3e758e9710.r2.cloudflarestorage.com",
    "awsAccessKeyID": "",
    "awsSecretAccessKey": "",
    "prefix": "debian/",
    "acl": "none",
    "storageClass": "STANDARD",
    "encryptionMethod": "",
    "plusWorkaround": False,
    "disableMultiDel": False,
    "forceSigV2": False,
    "debug": False,
}

osc = configparser.ConfigParser(interpolation=None)
osc.read_string(render(osc_path))
assert set(osc.sections()) == {"general", "https://api.opensuse.org"}
assert osc.get("general", "apiurl") == "https://api.opensuse.org"
assert osc.get("general", "packagecachedir") == "/pool/cache/developer/osc/packages"
assert osc.get("general", "build-root").startswith("/pool/build/developer/osc/build-root/")
assert osc.get("general", "build_repository") == "Debian_Unstable"
assert osc.get("general", "cookiejar") == "/pool/db/developer/osc/cookiejar"
assert osc.getint("general", "http_retries") == 3
for option in (
    "use_keyring",
    "checkout_rooted",
    "checkout_no_colon",
    "check_filelist",
    "do_package_tracking",
    "show_download_progress",
    "buildlog_strip_time",
    "builtin_signature_check",
):
    assert osc.getboolean("general", option)
for option in (
    "quiet",
    "verbose",
    "debug",
    "http_debug",
    "http_full_debug",
    "http_manual_approve",
    "traceback",
    "post_mortem",
    "local_service_run",
    "status_mtime_heuristic",
    "no_verify",
):
    assert not osc.getboolean("general", option)
assert osc.getboolean("https://api.opensuse.org", "sslcertck")
assert not osc.getboolean("https://api.opensuse.org", "allow_http")
assert all(
    not osc.has_option(section, option)
    for section in osc.sections()
    for option in ("user", "pass", "passx", "password")
)

osc_metadata = json.loads(render(osc_metadata_path))
assert osc_metadata == {
    "apiURL": "https://api.opensuse.org",
    "credentialsBackend": "keyring.backends.SecretService.Keyring",
    "project": "home:cramerz:debian",
    "repository": "Debian_Unstable",
    "schemaVersion": 1,
    "workspace": "/pool/build/developer/osc",
}
PY
}

publishing_wrapper_validate() {
  python3 - "$1" "$2" "$TMP_DIR" <<'PY'
import pathlib
import os
import stat
import sys
import types

aptly_source_path = pathlib.Path(sys.argv[1])
obs_source_path = pathlib.Path(sys.argv[2])
temp_root = pathlib.Path(sys.argv[3]) / "publishing-wrapper"
temp_root.mkdir(mode=0o700)

module = types.ModuleType("managed_aptly_publishing_test")
module.__file__ = str(aptly_source_path)
sys.modules[module.__name__] = module
exec(
    compile(aptly_source_path.read_text(), str(aptly_source_path), "exec"),
    module.__dict__,
)

obs_module = types.ModuleType("managed_obs_publishing_test")
obs_module.__file__ = str(obs_source_path)
sys.modules[obs_module.__name__] = obs_module
exec(
    compile(obs_source_path.read_text(), str(obs_source_path), "exec"),
    obs_module.__dict__,
)
assert hasattr(module, "run_aptly")
assert not hasattr(module, "run_osc")
assert hasattr(obs_module, "run_osc")
assert not hasattr(obs_module, "run_aptly")
assert str(module.APTLY_BINARY) == "/usr/local/lib/aptly/bin/aptly"
assert str(obs_module.OSC_BINARY) == "/usr/local/lib/osc/bin/osc"
assert module.COMMAND_TIMEOUT_SECONDS == obs_module.COMMAND_TIMEOUT_SECONDS == 3600

fingerprint = "33808BDA7507EE103BADC3BCF575BD768D94A3470EFD5D17DC2C048ED01A93DC"
context = module.AptlyContext(
    config=temp_root / "aptly.conf",
    state_dir=temp_root,
    endpoint_name="r2",
    endpoint_url="https://79cc1f5f831fb7f414638c3e758e9710.r2.cloudflarestorage.com",
    bucket="cf-aptly-r2-prod",
    service="aptly-r2:test",
    signing_key=fingerprint,
    credentials_backend="keyring.backends.SecretService.Keyring",
    distributions=("stable", "testing"),
    component="main",
    publish_target="s3:r2:",
    public_base_url="https://apt.jcramer.xyz",
)

def colon_record(record_type, fingerprint="", capabilities="", token=""):
    fields = [""] * 16
    fields[0] = record_type
    fields[9] = fingerprint
    fields[11] = capabilities
    fields[14] = token
    return ":".join(fields)


real_subprocess_run = module.subprocess.run
module.subprocess.run = lambda *args, **kwargs: types.SimpleNamespace(
    returncode=0,
    stdout="\n".join(
        (
            colon_record("sec", capabilities="c", token="#"),
            colon_record("fpr", fingerprint=fingerprint),
            colon_record("ssb", capabilities="s", token="+"),
            colon_record("fpr", fingerprint="C" * 40),
        )
    ),
)
module.require_aptly_signing_key(context)
module.subprocess.run = lambda *args, **kwargs: types.SimpleNamespace(
    returncode=0,
    stdout="\n".join(
        (
            colon_record("sec", capabilities="s", token="#"),
            colon_record("fpr", fingerprint=fingerprint),
        )
    ),
)
try:
    module.require_aptly_signing_key(context)
except module.PublishingError:
    pass
else:
    raise AssertionError("managed Aptly publication accepted a stub-only signing key")
module.subprocess.run = real_subprocess_run

module.require_aptly_signing_key = lambda _context: None
arguments = module.aptly_arguments_with_managed_signing(
    context,
    ["publish", "snapshot", "local-stable-snapshot", "s3:r2:"],
)
assert f"-gpg-key={fingerprint}" in arguments
assert "-acquire-by-hash" in arguments
assert module.aptly_publish_mutates_remote(["publish", "repo", "local-stable", "s3:r2:"])

descriptor = temp_root / "local-package_1.0.dsc"
descriptor.write_text("signed source package fixture")
descriptor.chmod(0o600)
module.subprocess.run = lambda *args, **kwargs: types.SimpleNamespace(
    returncode=0,
    stdout=f"[GNUPG:] VALIDSIG {fingerprint} 0 0 0 0 0 0 0 0 {fingerprint}\n",
)
module.require_signed_source_descriptors(context, [str(descriptor)])
module.subprocess.run = lambda *args, **kwargs: types.SimpleNamespace(
    returncode=0,
    stdout="[GNUPG:] VALIDSIG " + ("C" * 40) + " 0 0 0 0 0 0 0 0 " + ("C" * 40) + "\n",
)
try:
    module.require_signed_source_descriptors(context, [str(descriptor)])
except module.PublishingError:
    pass
else:
    raise AssertionError("managed Aptly publication accepted a differently signed .dsc")
module.subprocess.run = real_subprocess_run

try:
    module.aptly_arguments_with_managed_signing(
        context,
        ["publish", "snapshot", "-skip-signing", "snapshot", "s3:r2:"],
    )
except module.PublishingError:
    pass
else:
    raise AssertionError("managed Aptly publication accepted -skip-signing")
try:
    module.aptly_arguments_with_managed_signing(
        context,
        ["publish", "snapshot", "--skip-signing", "snapshot", "s3:r2:"],
    )
except module.PublishingError:
    pass
else:
    raise AssertionError("managed Aptly publication accepted --skip-signing")
try:
    module.aptly_arguments_with_managed_signing(
        context,
        [
            "publish",
            "snapshot",
            "--acquire-by-hash=false",
            "snapshot",
            "s3:r2:",
        ],
    )
except module.PublishingError:
    pass
else:
    raise AssertionError("managed Aptly publication accepted disabled Acquire-By-Hash")
try:
    module.run_aptly(["--config=/tmp/alternate-aptly.conf", "repo", "list"])
except module.PublishingError:
    pass
else:
    raise AssertionError("managed Aptly publication accepted a double-dash config override")

class FakeKeyring:
    def __init__(self):
        self.values = {(context.service, "access-key-id"): "a" * 32}

    def get_password(self, service, username):
        return self.values.get((service, username))

    def set_password(self, service, username, value):
        self.values[(service, username)] = value

pending_dir = temp_root / ".credentials.pending"
pending_dir.mkdir(mode=0o700)
secret_path = pending_dir / "cf-r2-secret-key"
secret_path.write_text("b" * 64)
secret_path.chmod(0o600)
assert stat.S_IMODE(secret_path.stat().st_mode) == 0o600

fake_keyring = FakeKeyring()
module.load_keyring = lambda _backend: fake_keyring
environment = module.aptly_environment_with_credentials(context)
assert environment["AWS_ACCESS_KEY_ID"] == "a" * 32
assert environment["AWS_SECRET_ACCESS_KEY"] == "b" * 64
assert not secret_path.exists()

captured_build = {}
module.load_aptly_context = lambda: context
module.require_aptly_signing_key = lambda _context: None
module.os.execve = lambda path, argv, env: captured_build.update(
    path=path,
    argv=argv,
    env=env,
)
module.run_dpkg_buildpackage(["-S"])
assert captured_build["path"] == "/usr/bin/dpkg-buildpackage"
assert captured_build["env"]["DEB_SIGN_KEYID"] == fingerprint
assert "DEB_SIGN_KEYFILE" not in captured_build["env"]

def reject_exec(*_args, **_kwargs):
    raise OSError("fixture exec failure")


module.os.execve = reject_exec
try:
    module.run_dpkg_buildpackage(["-S"])
except module.PublishingError:
    pass
else:
    raise AssertionError("managed dpkg-buildpackage leaked an exec failure")
try:
    module.run_dpkg_buildpackage(["--unsigned-source"])
except module.PublishingError:
    pass
else:
    raise AssertionError("managed dpkg-buildpackage accepted unsigned source output")

obs_state = temp_root / "osc"
obs_workspace = temp_root / "osc-workspace"
obs_state.mkdir(mode=0o700)
obs_workspace.mkdir(mode=0o700)
obs_pending = obs_state / ".credentials.pending"
obs_pending.mkdir(mode=0o700)
obs_username_path = obs_pending / "obs-username"
obs_password_path = obs_pending / "obs-password"
obs_username_path.write_text("obs-user")
obs_password_path.write_text("obs-password")
obs_username_path.chmod(0o600)
obs_password_path.chmod(0o600)
obs_context = obs_module.OscContext(
    config=obs_state / "oscrc",
    state_dir=obs_state,
    apiurl="https://api.opensuse.org",
    service="api.opensuse.org",
    credentials_backend="keyring.backends.SecretService.Keyring",
    project="home:cramerz:debian",
    repository="Debian_Unstable",
    workspace=obs_workspace,
)
obs_keyring = FakeKeyring()
obs_module.current_account = lambda: ("developer", os.getuid())
obs_module.load_keyring = lambda backend: obs_keyring
obs_environment = obs_module.osc_environment_with_credentials(obs_context)
assert obs_keyring.values[("managed-osc:api.opensuse.org", "username")] == "obs-user"
assert obs_keyring.values[("api.opensuse.org", "obs-user")] == "obs-password"
assert obs_environment["OSC_USERNAME"] == "obs-user"
assert obs_environment["OSC_CREDENTIALS_MGR_CLASS"] == (
    "osc.credentials.KeyringCredentialsManager:keyring.backends.SecretService.Keyring"
)
assert "OSC_PASSWORD" not in obs_environment
assert not obs_username_path.exists()
assert not obs_password_path.exists()
try:
    obs_module.run_osc(["-Ahttps://example.invalid", "list"])
except obs_module.PublishingError:
    pass
else:
    raise AssertionError("managed osc publication accepted a compact API URL override")
PY
}

aptly_signing_key_contract_is_safe() {
  signing_copy_test_root="${TMP_DIR}/aptly-signing-copy"
  signing_copy_script="${signing_copy_test_root}/copy.sh"
  signing_path_validation_script="${signing_copy_test_root}/validate-path.sh"
  signing_fingerprint_validation_script="${signing_copy_test_root}/validate-fingerprint.sh"
  signing_copy_valid_source="${signing_copy_test_root}/valid.asc"
  signing_copy_valid_target="${signing_copy_test_root}/valid.target"
  signing_copy_oversized_source="${signing_copy_test_root}/oversized.asc"
  signing_copy_oversized_target="${signing_copy_test_root}/oversized.target"

  install -d -m 0700 "$signing_copy_test_root"
  python3 - \
    "$devops_late" \
    "$devops_readme" \
    "$signing_copy_script" \
    "$signing_path_validation_script" \
    "$signing_fingerprint_validation_script" \
    "$signing_copy_valid_source" \
    "$signing_copy_oversized_source" <<'PY'
from pathlib import Path
import sys
import textwrap

source = Path(sys.argv[1]).read_text(encoding="utf-8")
readme = Path(sys.argv[2]).read_text(encoding="utf-8")
layout_start = source.index("devops_prepare_publishing_layout() {\n")
layout_end = source.index("\ndevops_render_aptly_config() {\n", layout_start)
layout = source[layout_start:layout_end]
function_start = source.index("devops_import_aptly_signing_key() (\n")
function_end = source.index("\ndevops_render_osc_config() {\n", function_start)
block = source[function_start:function_end]

for required in (
    "for required_command in chmod getent id install; do",
    '[ ! -L "$private_path" ] || {',
    '[ -d "$private_path" ] && [ ! -L "$private_path" ] || {',
    "private publication path is a symlink",
    "private publication path is not a direct directory",
    'chmod a-s -- "$private_path"',
    'chmod 0700 -- "$private_path"',
):
    assert required in layout, required

private_symlink_position = layout.index('[ ! -L "$private_path" ] || {')
private_install_position = layout.index(
    'install -d -m 0700 -o "$account_uid" -g "$account_gid" -- "$private_path"'
)
private_directory_position = layout.index(
    '[ -d "$private_path" ] && [ ! -L "$private_path" ] || {'
)
private_clear_position = layout.index('chmod a-s -- "$private_path"')
private_mode_position = layout.index('chmod 0700 -- "$private_path"')
assert (
    private_symlink_position
    < private_install_position
    < private_directory_position
    < private_clear_position
    < private_mode_position
)

for required in (
    "signing_device=/dev/sda2",
    "signing_profile_path=$DEVOPS_APTLY_GPG_SIGNING_KEY",
    "signing_key_name=${signing_profile_path##*/}",
    "signing_maximum_bytes=1048576",
    "signing_copy_block_bytes=4096",
    "trap 'devops_cleanup_aptly_signing_key \"$?\"' EXIT",
    "for required_command in chown cmp dd mktemp mount readlink tr umount wc; do",
    'mount -o ro,nosuid,nodev,noexec "$signing_device" "$signing_mountpoint"',
    'for required_option in ro nosuid nodev noexec; do',
    '[ -d "$signing_directory" ] && [ ! -L "$signing_directory" ]',
    '[ -f "$signing_source_key" ] &&',
    '[ ! -L "$signing_source_key" ] &&',
    'readlink -f -- "$signing_source_key"',
    'signing_source_key="${signing_mountpoint}${signing_profile_path}"',
    '"${signing_directory_real}/${signing_key_name}"',
    "-----BEGIN PGP PRIVATE KEY BLOCK-----",
    '${target_root}${APTLY_ROOT_DIR}/.aptly-signing-key.XXXXXX',
    "signing_maximum_bytes / signing_copy_block_bytes + 1",
    'if="$signing_source_key"',
    'of="$staged_host_key"',
    'bs="$signing_copy_block_bytes"',
    'count="$signing_copy_block_count"',
    'staged_key_bytes_raw=$(wc -c <"$staged_host_key")',
    "tr -d '[:space:]'",
    "bounded Aptly signing key",
    'chown "$account_ids" "$staged_host_key"',
    'cmp "$signing_source_key" "$staged_host_key"',
    'rm -f -- "$staged_host_key"',
    'umount "$signing_mountpoint"',
    "# BEGIN: managed Aptly signing-key target import",
    'gnupg_home="${account_home}/.gnupg"',
    '--import-options show-only',
    'expected_summary="1:sec:${expected_fingerprint}"',
    "aptly_signing_capability_count()",
    "aptly_available_signing_material_count()",
    "source does not contain signing-capable secret-key material",
    '--list-secret-keys "$expected_fingerprint"',
    "matching Aptly secret key is unavailable after import",
    "matching Aptly key has no local signing-capable secret material after import",
    '"$DEVOPS_APTLY_REPOSITORY_KEY_FINGERPRINT"',
    "# END: managed Aptly signing-key target import",
):
    assert required in block, required

for required in (
    ': "${DEVOPS_APTLY_GPG_SIGNING_KEY:?DEVOPS_APTLY_GPG_SIGNING_KEY must be set before DevOps provisioning}"',
    "devops_validate_aptly_signing_key_path",
    "devops_validate_openpgp_fingerprint",
    '"DEVOPS_APTLY_GPG_SIGNING_KEY"',
    '"$DEVOPS_APTLY_GPG_SIGNING_KEY"',
    '"DEVOPS_APTLY_REPOSITORY_KEY_FINGERPRINT"',
    '"$DEVOPS_APTLY_REPOSITORY_KEY_FINGERPRINT"',
):
    assert required in source, required

assert "cf_r2_gpg_key" not in source
assert "DEVOPS_CF_R2_GPG_KEY" not in source

installer_side = block[: block.index("# BEGIN: managed Aptly signing-key target import")]
assert " stat " not in installer_side
assert "stat -c" not in installer_side
assert '$1 == \\"pub\\" || \\$1 == \\"sec\\"' in block
copy_position = block.index('staged_host_key=$(mktemp ')
unmount_position = block.index(
    'if ! umount "$signing_mountpoint"; then', copy_position
)
target_import_position = block.index(
    'devops_run_as_account "inspect and import the managed Aptly signing key"',
    unmount_position,
)
assert copy_position < unmount_position < target_import_position

main = source[source.index('install -d -m 0700 "$tmp_env_dir"\n'):]
render_position = main.index("devops_render_aptly_config\n")
import_position = main.index("devops_import_aptly_signing_key\n")
unset_position = main.index("unset \\\n")
initialize_position = main.index("devops_initialize_aptly_repositories\n")
assert render_position < import_position < unset_position < initialize_position

for documented in (
    "DEVOPS_APTLY_GPG_SIGNING_KEY",
    "DEVOPS_APTLY_REPOSITORY_KEY_FINGERPRINT",
    "sole expected",
    "/aptly-signing/aptly-jcramer.xyz-gpg.asc",
    "/dev/sda2",
    "ro,nosuid,nodev,noexec",
    "$HOME/.gnupg",
    "no armored source copy",
):
    assert documented in readme, documented

copy_start = block.index("  signing_copy_block_count=$((\n")
copy_end = block.index('  chmod 0600 "$staged_host_key"\n', copy_start)
copy_body = textwrap.dedent(block[copy_start:copy_end])

def shell_function(name: str) -> str:
    start = source.index(f"{name}() {{\n")
    end = source.index("\n}\n", start) + len("\n}\n")
    return source[start:end]

Path(sys.argv[3]).write_text(
    "#!/bin/sh\n"
    "set -eu\n"
    "devops_fatal() { printf 'fatal: %s\\n' \"$*\" >&2; exit 1; }\n"
    "signing_source_key=$1\n"
    "staged_host_key=$2\n"
    "signing_maximum_bytes=$3\n"
    "signing_copy_block_bytes=4096\n"
    + copy_body,
    encoding="utf-8",
)
Path(sys.argv[4]).write_text(
    "#!/bin/sh\n"
    "set -eu\n"
    "devops_fatal() { printf 'fatal: %s\\n' \"$*\" >&2; exit 1; }\n"
    + shell_function("devops_validate_abs_path")
    + shell_function("devops_validate_aptly_signing_key_path")
    + "devops_validate_aptly_signing_key_path DEVOPS_APTLY_GPG_SIGNING_KEY \"$1\"\n",
    encoding="utf-8",
)
Path(sys.argv[5]).write_text(
    "#!/bin/sh\n"
    "set -eu\n"
    "devops_fatal() { printf 'fatal: %s\\n' \"$*\" >&2; exit 1; }\n"
    + shell_function("devops_validate_openpgp_fingerprint")
    + "devops_validate_openpgp_fingerprint DEVOPS_APTLY_REPOSITORY_KEY_FINGERPRINT \"$1\"\n",
    encoding="utf-8",
)
header = b"-----BEGIN PGP PRIVATE KEY BLOCK-----\n"
maximum = 1_048_576
Path(sys.argv[6]).write_bytes(header + b"A" * (maximum - len(header)))
Path(sys.argv[7]).write_bytes(header + b"B" * (maximum + 1 - len(header)))
PY
  chmod 0700 \
    "$signing_copy_script" \
    "$signing_path_validation_script" \
    "$signing_fingerprint_validation_script"
  signing_private_parent="${signing_copy_test_root}/private-parent"
  signing_private_state="${signing_private_parent}/aptly"
  install -d -m 2770 "$signing_private_parent"
  install -d -m 0700 "$signing_private_state"
  [ "$(stat -c '%a' -- "$signing_private_state")" = 2700 ] || return 1
  chmod a-s -- "$signing_private_state"
  chmod 0700 -- "$signing_private_state"
  [ "$(stat -c '%a' -- "$signing_private_state")" = 700 ] || return 1
  /bin/sh -n "$signing_copy_script" || return 1
  /bin/sh -n "$signing_path_validation_script" || return 1
  /bin/sh -n "$signing_fingerprint_validation_script" || return 1
  for valid_signing_path in \
    /aptly-signing/aptly-jcramer.xyz-gpg.asc \
    /aptly-signing/custom-private-key.asc \
    /aptly-signing/signing-key
  do
    /bin/sh "$signing_path_validation_script" "$valid_signing_path" || return 1
  done
  maximum_signing_name=$(python3 -c 'print("a" * 255)') || return 1
  /bin/sh \
    "$signing_path_validation_script" \
    "/aptly-signing/${maximum_signing_name}" ||
    return 1
  for invalid_signing_path in \
    '' \
    aptly-signing/private.asc \
    /other/private.asc \
    /aptly-signing/ \
    /aptly-signing/. \
    /aptly-signing/subdirectory/private.asc \
    /aptly-signing/../private.asc
  do
    if /bin/sh "$signing_path_validation_script" "$invalid_signing_path" \
         >"${signing_copy_test_root}/invalid-path.stdout" \
         2>"${signing_copy_test_root}/invalid-path.stderr"
    then
      return 1
    fi
  done
  oversized_signing_name=$(python3 -c 'print("a" * 256)') || return 1
  if /bin/sh \
       "$signing_path_validation_script" \
       "/aptly-signing/${oversized_signing_name}" \
       >"${signing_copy_test_root}/oversized-path.stdout" \
       2>"${signing_copy_test_root}/oversized-path.stderr"
  then
    return 1
  fi
  unset maximum_signing_name oversized_signing_name
  for valid_fingerprint in \
    0123456789ABCDEF0123456789ABCDEF01234567 \
    33808BDA7507EE103BADC3BCF575BD768D94A3470EFD5D17DC2C048ED01A93DC
  do
    /bin/sh \
      "$signing_fingerprint_validation_script" \
      "$valid_fingerprint" ||
      return 1
  done
  for invalid_fingerprint in \
    '' \
    0123456789ABCDEF0123456789ABCDEF0123456 \
    0123456789ABCDEF0123456789ABCDEF012345678 \
    0123456789abcdef0123456789abcdef01234567 \
    0123456789ABCDEF0123456789ABCDEF0123456G
  do
    if /bin/sh \
         "$signing_fingerprint_validation_script" \
         "$invalid_fingerprint" \
         >"${signing_copy_test_root}/invalid-fingerprint.stdout" \
         2>"${signing_copy_test_root}/invalid-fingerprint.stderr"
    then
      return 1
    fi
  done
  /bin/sh \
    "$signing_copy_script" \
    "$signing_copy_valid_source" \
    "$signing_copy_valid_target" \
    1048576 ||
    return 1
  cmp "$signing_copy_valid_source" "$signing_copy_valid_target" || return 1
  if /bin/sh \
       "$signing_copy_script" \
       "$signing_copy_oversized_source" \
       "$signing_copy_oversized_target" \
       1048576 \
       >"${signing_copy_test_root}/oversized.stdout" \
       2>"${signing_copy_test_root}/oversized.stderr"
  then
    return 1
  fi
  grep -Fqx \
    'fatal: Aptly signing-key source must be between 1 and 1048576 bytes' \
    "${signing_copy_test_root}/oversized.stderr" ||
    return 1
  [ "$(wc -c <"$signing_copy_oversized_target")" -le 1052672 ]
}

aptly_first_primary_secret_fingerprint() {
  /usr/bin/gpg \
    --batch \
    --no-options \
    --homedir "$1" \
    --with-colons \
    --list-secret-keys "$2" 2>/dev/null |
    /usr/bin/awk -F: '
      $1 == "sec" {
        want_fingerprint = 1
        next
      }
      want_fingerprint && $1 == "fpr" {
        print toupper($10)
        exit
      }
    '
}

aptly_signing_key_target_import_works() {
  signing_test_root="${TMP_DIR}/aptly-signing-key"
  target_import_script="${signing_test_root}/target-import.sh"
  source_home="${signing_test_root}/source-home"
  first_batch="${signing_test_root}/first.batch"
  second_batch="${signing_test_root}/second.batch"

  install -d -m 0700 "$signing_test_root" "$source_home"
  python3 - "$devops_late" "$target_import_script" <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1]).read_text(encoding="utf-8")
marker = source.index("# BEGIN: managed Aptly signing-key target import\n")
command = source.index("/bin/sh -eu -c '\n", marker)
body_start = source.index("\n", command) + 1
body_end = source.index("\n' sh \\\n", body_start)
body = source[body_start:body_end]
Path(sys.argv[2]).write_text("#!/bin/sh\nset -eu\n" + body + "\n", encoding="utf-8")
PY
  /bin/sh -n "$target_import_script" || return 1

  cat >"$first_batch" <<'EOF'
Key-Type: RSA
Key-Length: 2048
Key-Usage: sign
Name-Real: Aptly Import Smoke One
Name-Email: aptly-import-one@example.invalid
Expire-Date: 0
Passphrase: aptly-smoke-passphrase
%commit
EOF
  cat >"$second_batch" <<'EOF'
Key-Type: RSA
Key-Length: 2048
Key-Usage: sign
Name-Real: Aptly Import Smoke Two
Name-Email: aptly-import-two@example.invalid
Expire-Date: 0
Passphrase: aptly-smoke-passphrase
%commit
EOF
  /usr/bin/gpg \
    --batch \
    --no-options \
    --pinentry-mode loopback \
    --passphrase aptly-smoke-passphrase \
    --homedir "$source_home" \
    --generate-key "$first_batch" >/dev/null 2>&1 ||
    return 1
  /usr/bin/gpg \
    --batch \
    --no-options \
    --pinentry-mode loopback \
    --passphrase aptly-smoke-passphrase \
    --homedir "$source_home" \
    --generate-key "$second_batch" >/dev/null 2>&1 ||
    return 1

  first_fingerprint=$(aptly_first_primary_secret_fingerprint \
    "$source_home" aptly-import-one@example.invalid) ||
    return 1
  second_fingerprint=$(aptly_first_primary_secret_fingerprint \
    "$source_home" aptly-import-two@example.invalid) ||
    return 1
  [ -n "$first_fingerprint" ] && [ -n "$second_fingerprint" ] &&
    [ "$first_fingerprint" != "$second_fingerprint" ] ||
    return 1

  valid_home="${signing_test_root}/valid-home"
  valid_aptly="${signing_test_root}/valid-aptly"
  valid_key="${valid_aptly}/.aptly-signing-key.valid"
  install -d -m 0700 "$valid_home" "$valid_aptly"
  /usr/bin/gpg \
    --batch \
    --no-options \
    --pinentry-mode loopback \
    --passphrase aptly-smoke-passphrase \
    --homedir "$source_home" \
    --armor \
    --export-secret-keys "$first_fingerprint" >"$valid_key" ||
    return 1
  chmod 0600 "$valid_key"
  /usr/bin/env -i \
    HOME="$valid_home" \
    LOGNAME="$(id -un)" \
    PATH=/usr/bin:/bin \
    USER="$(id -un)" \
    /bin/sh -eu "$target_import_script" \
      "$valid_key" \
      "$valid_home" \
      "$valid_aptly" \
      "$first_fingerprint" \
      1048576 ||
    return 1
  imported_fingerprint=$(aptly_first_primary_secret_fingerprint \
    "${valid_home}/.gnupg" "$first_fingerprint") ||
    return 1
  [ "$imported_fingerprint" = "$first_fingerprint" ] || return 1
  [ "$(stat -c '%a' -- "${valid_home}/.gnupg")" = 700 ] || return 1

  mismatch_home="${signing_test_root}/mismatch-home"
  mismatch_aptly="${signing_test_root}/mismatch-aptly"
  mismatch_key="${mismatch_aptly}/.aptly-signing-key.mismatch"
  install -d -m 0700 "$mismatch_home" "$mismatch_aptly"
  cp "$valid_key" "$mismatch_key"
  chmod 0600 "$mismatch_key"
  if /usr/bin/env -i \
       HOME="$mismatch_home" \
       LOGNAME="$(id -un)" \
       PATH=/usr/bin:/bin \
       USER="$(id -un)" \
       /bin/sh -eu "$target_import_script" \
         "$mismatch_key" \
         "$mismatch_home" \
         "$mismatch_aptly" \
         "$second_fingerprint" \
         1048576 \
         >"${signing_test_root}/mismatch.stdout" \
         2>"${signing_test_root}/mismatch.stderr"
  then
    return 1
  fi
  if /usr/bin/gpg \
       --batch \
       --no-options \
       --homedir "${mismatch_home}/.gnupg" \
       --with-colons \
       --list-secret-keys 2>/dev/null |
       grep -q '^sec:'
  then
    return 1
  fi

  multiple_home="${signing_test_root}/multiple-home"
  multiple_aptly="${signing_test_root}/multiple-aptly"
  multiple_key="${multiple_aptly}/.aptly-signing-key.multiple"
  install -d -m 0700 "$multiple_home" "$multiple_aptly"
  /usr/bin/gpg \
    --batch \
    --no-options \
    --pinentry-mode loopback \
    --passphrase aptly-smoke-passphrase \
    --homedir "$source_home" \
    --armor \
    --export-secret-keys "$first_fingerprint" "$second_fingerprint" >"$multiple_key" ||
    return 1
  chmod 0600 "$multiple_key"
  if /usr/bin/env -i \
       HOME="$multiple_home" \
       LOGNAME="$(id -un)" \
       PATH=/usr/bin:/bin \
       USER="$(id -un)" \
       /bin/sh -eu "$target_import_script" \
         "$multiple_key" \
         "$multiple_home" \
         "$multiple_aptly" \
         "$first_fingerprint" \
         1048576 \
         >"${signing_test_root}/multiple.stdout" \
         2>"${signing_test_root}/multiple.stderr"
  then
    return 1
  fi
}

codex_class_defaults_accept_cached_profile() {
  functions_file="${TMP_DIR}/codex-policy-functions.sh"
  profile_block="${TMP_DIR}/codex-profile-current.sh"
  cached_profile="${TMP_DIR}/codex-profile-cached.sh"
  validation_target="${TMP_DIR}/codex-policy-target"

  sed -n '1,/^devops_target_passwd_ids() {/p' "$devops_late" |
    sed '$d' >"$functions_file"
  awk '
    /^# Optional managed Codex policy/ { capture = 1 }
    capture { print }
    /^DEVOPS_CODEX_BWRAP_MAX_USER_NAMESPACES=/ { exit }
  ' "$ROOT_DIR/d-i/forky/hosts/profiles/btrfs/desktop.env" >"$profile_block"
  grep -v '^DEVOPS_CODEX_BWRAP_' "$profile_block" >"$cached_profile"
  install -d -m 0700 "$validation_target"

  /usr/bin/env -i PATH=/usr/bin:/bin /bin/sh -eu -c '
    # shellcheck disable=SC1090
    . "$2"
    # shellcheck disable=SC1090
    . "$3"
    devops_validate_codex_policy
    [ "$DEVOPS_CODEX_BWRAP_USERNS_CLONE" = 1 ]
    [ "$DEVOPS_CODEX_BWRAP_MAX_USER_NAMESPACES" = 1024 ]
  ' sh "$validation_target" "$functions_file" "$cached_profile"
}

codex_truncated_commit_is_rejected() {
  functions_file="${TMP_DIR}/codex-commit-functions.sh"
  profile_block="${TMP_DIR}/codex-commit-profile.sh"
  truncated_profile="${TMP_DIR}/codex-commit-truncated.sh"
  validation_target="${TMP_DIR}/codex-commit-target"
  validation_stderr="${TMP_DIR}/codex-commit.stderr"

  sed -n '1,/^devops_target_passwd_ids() {/p' "$devops_late" |
    sed '$d' >"$functions_file"
  awk '
    /^# Optional managed Codex policy/ { capture = 1 }
    capture { print }
    /^DEVOPS_CODEX_BWRAP_MAX_USER_NAMESPACES=/ { exit }
  ' "$ROOT_DIR/d-i/forky/hosts/profiles/btrfs/desktop.env" >"$profile_block"
  awk '
    /^DEVOPS_CODEX_REPOSITORY_COMMIT=/ {
      print "DEVOPS_CODEX_REPOSITORY_COMMIT=\"3728a8d7da3da809f51c23757be65bcdccc13aa\""
      next
    }
    { print }
  ' "$profile_block" >"$truncated_profile"
  install -d -m 0700 "$validation_target"

  if /usr/bin/env -i PATH=/usr/bin:/bin /bin/sh -eu -c '
    # shellcheck disable=SC1090
    . "$2"
    # shellcheck disable=SC1090
    . "$3"
    devops_validate_codex_policy
  ' sh "$validation_target" "$functions_file" "$truncated_profile" \
    >"${TMP_DIR}/codex-commit.stdout" 2>"$validation_stderr"
  then
    return 1
  fi

  grep -Fqx \
    'fatal: DEVOPS_CODEX_REPOSITORY_COMMIT must contain exactly 40 lowercase hexadecimal characters (got 39)' \
    "$validation_stderr"
}

codex_tmpfiles_template_renders() {
  rendered_tmpfiles="${TMP_DIR}/80-codex-storage.conf"

  /bin/sh -eu -c '
    # shellcheck disable=SC1090
    . "$1"
    installer_apply_scalar_placeholders \
      "$2" \
      "$3" \
      ACCOUNT_USERNAME desktop \
      DEVOPS_CODEX_ROOT /data/codex \
      DEVOPS_CODEX_BINARY_PATH /data/codex/share/bin/codex \
      DEVOPS_CODEX_WRAPPER_PATH /data/codex/lib/codex \
      DEVOPS_CODEX_USER_ROOT /data/codex/usr \
      DEVOPS_CODEX_SYSTEM_CONFIG_DIR /etc/codex \
      DEVOPS_CODEX_LOG_DIR /data/codex/log \
      DEVOPS_CODEX_SQLITE_HOME /data/codex/sqlite \
      DEVOPS_CODEX_RUNTIME_ROOT /data/codex/runtime \
      DEVOPS_CODEX_AGENTS /data/codex/usr/agents \
      DEVOPS_CODEX_HOME /data/codex/usr/home \
      DEVOPS_CODEX_SKILLS /data/codex/usr/skills
    installer_assert_no_unresolved_installer_placeholders \
      "$3" \
      "Codex tmpfiles smoke-test render"
  ' sh \
    "$ROOT_DIR/d-i/forky/scripts/common/lib.sh" \
    "$codex_tmpfiles_template" \
    "$rendered_tmpfiles" ||
    return 1

  LC_ALL=C awk '
    /^[[:space:]]*($|#)/ { next }
    {
      if (NF < 6 || $2 !~ /^\//) {
        exit 1
      }
    }
  ' "$rendered_tmpfiles" &&
    grep -Fqx 'd /data/codex 3770 root devops -' "$rendered_tmpfiles" &&
    grep -Fqx 'd /data/codex/usr 0750 desktop devops -' "$rendered_tmpfiles" &&
    grep -Fqx 'd /data/codex/usr/home 2770 desktop devops -' "$rendered_tmpfiles" &&
    grep -Fqx 'd /data/codex/usr/home/memories 2770 desktop devops -' "$rendered_tmpfiles" &&
    grep -Fqx 'd /data/codex/log 2770 desktop devops -' "$rendered_tmpfiles" &&
    grep -Fqx 'd /var/log/managed/openai/codex 2770 desktop devops -' "$rendered_tmpfiles" &&
    grep -Fqx 'd /data/codex/sqlite 2770 desktop devops -' "$rendered_tmpfiles" &&
    grep -Fqx 'd /data/codex/runtime 2770 desktop devops -' "$rendered_tmpfiles" &&
    grep -Fqx 'd /data/codex/runtime/.control 0700 desktop devops -' "$rendered_tmpfiles" &&
    awk '
      $2 ~ "^/data/codex/" && ($4 == "root" || $5 == "root") {
        unsafe_transition = 1
      }
      END {
        exit unsafe_transition ? 1 : 0
      }
    ' "$rendered_tmpfiles"
}

codex_installer_clears_inherited_special_bits() {
  helper_file="${TMP_DIR}/codex-mode-helper.sh"
  group_helper_file="${TMP_DIR}/codex-group-mode-helper.sh"
  mode_root="${TMP_DIR}/codex-mode-root"
  share_path="${mode_root}/share"
  user_path="${mode_root}/usr"
  private_path="${mode_root}/runtime"
  shared_path="${mode_root}/shared"
  binary_path="${mode_root}/codex"

  awk '
    /^codex_chmod_without_special_bits\(\) \{/ {
      capture = 1
    }
    capture {
      print
    }
    capture && /^}/ {
      exit
    }
  ' "$devops_late" >"$helper_file"
  awk '
    /^codex_chmod_group_shared\(\) \{/ {
      capture = 1
    }
    capture {
      print
    }
    capture && /^}/ {
      exit
    }
  ' "$devops_late" >"$group_helper_file"

  grep -Fq 'codex_chmod_without_special_bits() {' "$helper_file" &&
    grep -Fq 'chmod a-s -- "$@"' "$helper_file" &&
    grep -Fq 'codex_chmod_group_shared() {' "$group_helper_file" &&
    grep -Fq 'chmod g+s -- "$@"' "$group_helper_file" ||
    return 1

  mkdir -p "$share_path" "$user_path" "$private_path" "$shared_path"
  : >"$binary_path"
  chmod 3770 "$mode_root"
  chmod 2755 "$share_path"
  chmod 2750 "$user_path"
  chmod 2700 "$private_path"
  chmod 6770 "$shared_path"
  chmod 6755 "$binary_path"

  /usr/bin/env -i PATH=/usr/bin:/bin /bin/sh -eu -c '
    codex_fatal() {
      printf "fatal: %s\n" "$*" >&2
      exit 1
    }

    # shellcheck disable=SC1090
    . "$1"
    # shellcheck disable=SC1090
    . "$2"
    codex_chmod_without_special_bits 0755 "$3" "$6"
    codex_chmod_without_special_bits 0750 "$4"
    codex_chmod_without_special_bits 0700 "$5"
    codex_chmod_group_shared "$7"
  ' sh \
    "$helper_file" \
    "$group_helper_file" \
    "$share_path" \
    "$user_path" \
    "$private_path" \
    "$binary_path" \
    "$shared_path" ||
    return 1

  [ "$(stat -c '%a' -- "$mode_root")" = 3770 ] &&
    [ "$(stat -c '%a' -- "$share_path")" = 755 ] &&
    [ "$(stat -c '%a' -- "$user_path")" = 750 ] &&
    [ "$(stat -c '%a' -- "$private_path")" = 700 ] &&
    [ "$(stat -c '%a' -- "$shared_path")" = 2770 ] &&
    [ "$(stat -c '%a' -- "$binary_path")" = 755 ] &&
    grep -Fq 'find "$user_root" -xdev -type d -exec chmod a-s,go-w -- {} +' "$devops_late" &&
    grep -Fq 'find "$user_root" -xdev -type f -exec chmod a-s,go-w -- {} +' "$devops_late" &&
    grep -Fq 'find "$config_staging" -xdev -type d -exec chmod a-s,go-w -- {} +' "$devops_late" &&
    grep -Fq 'find "$config_staging" -xdev -type f -exec chmod a-s,go-w -- {} +' "$devops_late" &&
    grep -Fq 'codex_chmod_without_special_bits 0755 "$config_staging"' "$devops_late" &&
    grep -Fq 'codex_chmod_without_special_bits 0750 "$user_root"' "$devops_late" &&
    grep -Fq 'find "$home_path" -xdev -type d -exec chmod a-s,g=u,o=,g+s -- {} +' "$devops_late" &&
    grep -Fq 'find "$home_path" -xdev -type f -exec chmod a-s,g=u,o= -- {} +' "$devops_late" &&
    grep -Fq 'codex_chmod_group_shared "$home_path" "$memories_path"' "$devops_late" &&
    grep -Eq '^codex_chmod_without_special_bits 0755[[:space:]]*\\$' "$devops_late" &&
    grep -Fq 'codex_chmod_group_shared "$log_dir" "$sqlite_home" "$runtime_root"' "$devops_late"
}

cargo_template_renders() {
  rendered_cargo_config="${TMP_DIR}/cargo-config.toml"

  /bin/sh -eu -c '
    # shellcheck disable=SC1090
    . "$1"
    installer_apply_scalar_placeholders \
      "$2" \
      "$3" \
      DEVOPS_CARGO_RUSTC_WRAPPER sccache \
      DEVOPS_CARGO_TARGET_TRIPLE x86_64-unknown-linux-gnu \
      DEVOPS_CARGO_TARGET_LINKER clang-24 \
      DEVOPS_CARGO_TARGET_CPU skylake \
      DEVOPS_CARGO_LINKER_ARGUMENT -fuse-ld=mold
    installer_assert_no_unresolved_installer_placeholders \
      "$3" \
      "Cargo config smoke-test render"
  ' sh \
    "$ROOT_DIR/d-i/forky/scripts/common/lib.sh" \
    "$cargo_config_template" \
    "$rendered_cargo_config" ||
    return 1

  python3 - "$rendered_cargo_config" <<'PY'
from pathlib import Path
import sys
import tomllib

cargo = tomllib.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
assert cargo["build"] == {
    "rustc-wrapper": "sccache",
}
assert cargo["target"]["x86_64-unknown-linux-gnu"] == {
    "linker": "clang-24",
    "rustflags": [
        "-C",
        "target-cpu=skylake",
        "-C",
        "link-arg=-fuse-ld=mold",
    ],
}
PY
}

codex_wrapper_mount_helpers_work() {
  wrapper_library="${TMP_DIR}/codex-wrapper-library"
  sed '$d' "$codex_wrapper" >"$wrapper_library"

  /usr/bin/env -i PATH=/usr/bin:/bin /bin/bash -Eeuo pipefail -c '
    # shellcheck disable=SC1090
    . "$1"

    test_root=$2
    source_file="${test_root}/source"
    destination_file="${test_root}/destination"
    destination_link="${test_root}/destination-link"
    present_directory="${test_root}/present-directory"
    missing_directory="${test_root}/missing-directory"

    install -d -m 0700 "${test_root}"
    printf "source\n" >"${source_file}"
    printf "destination\n" >"${destination_file}"
    ln -s "${destination_file}" "${destination_link}"
    install -d -m 0700 "${present_directory}"

    BWRAP_ARGS=()
    codex_append_required_ro_bind_to_existing_path \
      "test synthetic file" \
      "${source_file}" \
      "${destination_link}"
    [[ "${#BWRAP_ARGS[@]}" -eq 3 ]]
    [[ "${BWRAP_ARGS[0]}" == "--ro-bind" ]]
    [[ "${BWRAP_ARGS[1]}" == "${source_file}" ]]
    [[ "${BWRAP_ARGS[2]}" == "${destination_file}" ]]

    BWRAP_ARGS=()
    codex_append_tmpfs_parent_dirs /run/systemd/resolve/stub-resolv.conf
    [[ "${#BWRAP_ARGS[@]}" -eq 4 ]]
    [[ "${BWRAP_ARGS[0]}" == "--dir" ]]
    [[ "${BWRAP_ARGS[1]}" == "/run/systemd" ]]
    [[ "${BWRAP_ARGS[2]}" == "--dir" ]]
    [[ "${BWRAP_ARGS[3]}" == "/run/systemd/resolve" ]]

    BWRAP_ARGS=()
    codex_append_tmpfs_if_present "${missing_directory}"
    [[ "${#BWRAP_ARGS[@]}" -eq 0 ]]
    codex_append_tmpfs_if_present "${present_directory}"
    [[ "${#BWRAP_ARGS[@]}" -eq 2 ]]
    [[ "${BWRAP_ARGS[0]}" == "--tmpfs" ]]
    [[ "${BWRAP_ARGS[1]}" == "${present_directory}" ]]
  ' bash "$wrapper_library" "${TMP_DIR}/codex-mount-helper"
}

codex_wrapper_generates_synthetic_installation_ids() {
  wrapper_library="${TMP_DIR}/codex-wrapper-identity-library"
  runtime_root="${TMP_DIR}/codex-runtime"
  identity_home="${TMP_DIR}/codex-identity-home"

  sed \
    -e "s|readonly CODEX_RUNTIME_ROOT=\"/data/codex/runtime\"|readonly CODEX_RUNTIME_ROOT=\"${runtime_root}\"|" \
    -e '$d' \
    "$codex_wrapper" >"$wrapper_library"
  install -d -m 0700 "$identity_home"

  /usr/bin/env -i PATH=/usr/bin:/bin HOME="$identity_home" PWD=/tmp \
    /bin/bash -Eeuo pipefail -c '
      # shellcheck disable=SC1090
      . "$1"

      install -d -m 0700 "$CODEX_CONTROL_ROOT"
      CODEX_SANDBOX_PATH=/usr/bin:/bin

      codex_prepare_identity_files "$(id -u)" "$(id -g)"
      first_control_dir=$CODEX_CONTROL_DIR
      first_installation_id=$(cat "$first_control_dir/installation_id")
      [[ "$first_installation_id" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]
      [[ "$(wc -c <"$first_control_dir/installation_id")" == 36 ]]
      [[ "$(wc -l <"$first_control_dir/installation_id")" == 0 ]]
      [[ "$(stat -c "%a" "$first_control_dir/installation_id")" == 644 ]]
      rm -rf -- "$first_control_dir"

      codex_prepare_identity_files "$(id -u)" "$(id -g)"
      second_control_dir=$CODEX_CONTROL_DIR
      second_installation_id=$(cat "$second_control_dir/installation_id")
      [[ "$second_installation_id" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]
      [[ "$first_installation_id" != "$second_installation_id" ]]
      rm -rf -- "$second_control_dir"
    ' bash "$wrapper_library"
}

codex_archive_validator_rejects_unsafe_members() {
  fixture_root="${TMP_DIR}/codex-archive-fixtures"
  install -d -m 0700 "$fixture_root"

  python3 - "$fixture_root" <<'PY'
from __future__ import annotations

from io import BytesIO
from pathlib import Path
import sys
import tarfile


root = Path(sys.argv[1])
binaries = (
    "codex",
    "codex-app-server",
    "future-helper",
)


def regular(name: str, data: bytes, mode: int) -> tuple[str, bytes, int, bytes, str]:
    return (name, data, mode, tarfile.REGTYPE, "")


def build_fixture(variant: str) -> None:
    entries = [
        regular(f"bin/{name}", b"x", 0o755)
        for name in binaries
    ]
    entries.extend(
        (
            regular("config.schema.json", b"{}\n", 0o644),
            regular("SHA256SUMS", b"sums\n", 0o644),
            regular("build-manifest.json", b"{}\n", 0o644),
            regular("metadata/README.txt", b"metadata\n", 0o644),
        )
    )

    if variant == "duplicate":
        entries[1] = entries[0]
    elif variant == "absolute":
        entries[-1] = regular("/build-manifest.json", b"{}\n", 0o644)
    elif variant == "traversal":
        entries[-1] = regular("../build-manifest.json", b"{}\n", 0o644)
    elif variant == "non-normalized":
        entries[-1] = regular("./build-manifest.json", b"{}\n", 0o644)
    elif variant == "symlink":
        entries[0] = ("bin/codex", b"", 0o755, tarfile.SYMTYPE, "codex-app-server")
    elif variant == "hardlink":
        entries[0] = ("bin/codex", b"", 0o755, tarfile.LNKTYPE, "bin/codex-app-server")
    elif variant == "device":
        entries[0] = ("bin/codex", b"", 0o755, tarfile.CHRTYPE, "")
    elif variant == "fifo":
        entries[0] = ("bin/codex", b"", 0o755, tarfile.FIFOTYPE, "")
    elif variant == "empty":
        entries[0] = regular("bin/codex", b"", 0o755)
    elif variant == "missing-schema":
        entries = [entry for entry in entries if entry[0] != "config.schema.json"]
    elif variant == "missing-binary":
        entries = [entry for entry in entries if not entry[0].startswith("bin/")]
    elif variant == "overflow":
        entries[0] = regular("bin/codex", b"x" * 1025, 0o755)
    elif variant not in ("positive", "pax"):
        raise ValueError(variant)

    archive_format = tarfile.PAX_FORMAT if variant == "pax" else tarfile.GNU_FORMAT
    with tarfile.open(root / f"{variant}.tar.gz", "w:gz", format=archive_format) as archive:
        directory = tarfile.TarInfo("bin")
        directory.type = tarfile.DIRTYPE
        directory.mode = 0o2755
        archive.addfile(directory)
        metadata_directory = tarfile.TarInfo("metadata")
        metadata_directory.type = tarfile.DIRTYPE
        metadata_directory.mode = 0o755
        archive.addfile(metadata_directory)
        for name, data, mode, member_type, linkname in entries:
            member = tarfile.TarInfo(name)
            member.type = member_type
            member.mode = mode
            member.linkname = linkname
            member.size = len(data) if member_type == tarfile.REGTYPE else 0
            if variant == "pax" and name == "bin/codex":
                member.pax_headers = {"comment": "unsupported"}
            archive.addfile(
                member,
                BytesIO(data) if member_type == tarfile.REGTYPE else None,
            )


for fixture_variant in (
    "positive",
    "duplicate",
    "absolute",
    "traversal",
    "non-normalized",
    "symlink",
    "hardlink",
    "device",
    "fifo",
    "empty",
    "pax",
    "missing-schema",
    "missing-binary",
    "overflow",
):
    build_fixture(fixture_variant)
PY

  positive_output="${fixture_root}/positive-output"
  install -d -m 0700 "$positive_output"
  python3 "$codex_archive_helper" \
    --archive "${fixture_root}/positive.tar.gz" \
    --output-directory "$positive_output" \
    --binary-directory bin \
    --schema-member config.schema.json \
    --maximum-extracted-bytes 1024 ||
    return 1

  extracted_files=$(
    find "$positive_output" -type f -printf '%P\n' |
      LC_ALL=C sort
  )
  [ "$extracted_files" = "bin/codex
bin/codex-app-server
bin/future-helper
config.schema.json" ] &&
    [ "$(stat -c '%a' "$positive_output/bin/codex")" = 755 ] &&
    [ "$(stat -c '%a' "$positive_output/bin/future-helper")" = 755 ] &&
    [ "$(stat -c '%a' "$positive_output/config.schema.json")" = 644 ] ||
    return 1

  for rejected_variant in \
    duplicate \
    absolute \
    traversal \
    non-normalized \
    symlink \
    hardlink \
    device \
    fifo \
    empty \
    pax \
    missing-schema \
    missing-binary \
    overflow
  do
    rejected_output="${fixture_root}/${rejected_variant}-output"
    install -d -m 0700 "$rejected_output"
    if python3 "$codex_archive_helper" \
      --archive "${fixture_root}/${rejected_variant}.tar.gz" \
      --output-directory "$rejected_output" \
      --binary-directory bin \
      --schema-member config.schema.json \
      --maximum-extracted-bytes 1024 \
      >"${fixture_root}/${rejected_variant}.stdout" \
      2>"${fixture_root}/${rejected_variant}.stderr"
    then
      return 1
    fi
  done

  aggregate_output="${fixture_root}/aggregate-output"
  install -d -m 0700 "$aggregate_output"
  if python3 "$codex_archive_helper" \
    --archive "${fixture_root}/positive.tar.gz" \
    --output-directory "$aggregate_output" \
    --binary-directory bin \
    --schema-member config.schema.json \
    --maximum-extracted-bytes 4 \
    >"${fixture_root}/aggregate.stdout" \
    2>"${fixture_root}/aggregate.stderr"
  then
    return 1
  fi
}

codex_wrapper_kernel_release_bounds_work() {
  wrapper_library="${TMP_DIR}/codex-wrapper-kernel-library"
  sed '$d' "$codex_wrapper" >"$wrapper_library"

  /usr/bin/env -i PATH=/usr/bin:/bin /bin/bash -Eeuo pipefail -c '
    # shellcheck disable=SC1090
    . "$1"

    codex_generate_uuid() {
      printf "%s\n" 00000000-0000-0000-0000-000000000000
    }
    codex_random_bounded() {
      case "$1" in
        3) printf "%s\n" "$TEST_FAMILY" ;;
        6) printf "%s\n" "$TEST_PATCH" ;;
        13) printf "%s\n" "$TEST_MINOR" ;;
        100) printf "%s\n" "$TEST_PATCH" ;;
        *) return 1 ;;
      esac
    }

    TEST_FAMILY=0 TEST_MINOR=0 TEST_PATCH=0
    [[ "$(codex_random_kernel_release)" == 6.7.0-codex-00000000-amd64 ]]
    TEST_FAMILY=0 TEST_MINOR=12 TEST_PATCH=99
    [[ "$(codex_random_kernel_release)" == 6.19.99-codex-00000000-amd64 ]]
    TEST_FAMILY=1 TEST_MINOR=0 TEST_PATCH=99
    [[ "$(codex_random_kernel_release)" == 7.0.99-codex-00000000-amd64 ]]
    TEST_FAMILY=2 TEST_MINOR=0 TEST_PATCH=5
    [[ "$(codex_random_kernel_release)" == 7.1.5-codex-00000000-amd64 ]]
  ' bash "$wrapper_library"
}

codex_wrapper_persistent_state_guards_fail_closed() {
  wrapper_library="${TMP_DIR}/codex-wrapper-state-library"
  state_root="${TMP_DIR}/codex-state"
  user_root="${state_root}/usr"
  runtime_home="${user_root}/home"
  memory_root="${runtime_home}/memories"
  guard_path="${memory_root}/.git"
  guard_target="${state_root}/guard-target"
  current_group=$(id -gn)

  sed \
    -e "s|readonly CODEX_USER_ROOT=\"/data/codex/usr\"|readonly CODEX_USER_ROOT=\"${user_root}\"|" \
    -e "s|readonly CODEX_RUNTIME_HOME=\"/data/codex/usr/home\"|readonly CODEX_RUNTIME_HOME=\"${runtime_home}\"|" \
    -e "s|readonly CODEX_DEVOPS_GROUP=\"devops\"|readonly CODEX_DEVOPS_GROUP=\"${current_group}\"|" \
    -e '$d' \
    "$codex_wrapper" >"$wrapper_library"

  install -d -m 0750 -- "$user_root"
  install -d -m 2770 -- "$runtime_home" "$memory_root" "$guard_path"
  if /usr/bin/env -i PATH=/usr/bin:/bin /bin/bash -Eeuo pipefail -c '
       # shellcheck disable=SC1090
       . "$1"
       codex_prepare_memory_guard
     ' bash "$wrapper_library" >/dev/null 2>&1; then
    return 1
  fi
  [ -d "$guard_path" ] || return 1

  rmdir -- "$guard_path"
  : >"$guard_target"
  ln -s -- "$guard_target" "$guard_path"
  if /usr/bin/env -i PATH=/usr/bin:/bin /bin/bash -Eeuo pipefail -c '
       # shellcheck disable=SC1090
       . "$1"
       codex_prepare_memory_guard
     ' bash "$wrapper_library" >/dev/null 2>&1; then
    return 1
  fi
  [ -L "$guard_path" ] || return 1

  rm -f -- "$guard_path"
  chmod 0750 -- "$memory_root"
  if /usr/bin/env -i PATH=/usr/bin:/bin /bin/bash -Eeuo pipefail -c '
       # shellcheck disable=SC1090
       . "$1"
       codex_require_devops_shared_account_directory "test shared directory" "$2"
     ' bash "$wrapper_library" "$memory_root" >/dev/null 2>&1; then
    return 1
  fi
  chmod 2770 -- "$memory_root"
  /usr/bin/env -i PATH=/usr/bin:/bin /bin/bash -Eeuo pipefail -c '
    # shellcheck disable=SC1090
    . "$1"
    codex_require_devops_shared_account_directory "test shared directory" "$2"
  ' bash "$wrapper_library" "$memory_root"
}

codex_wrapper_path_boundaries_work() {
  wrapper_library="${TMP_DIR}/codex-wrapper-path-library"
  test_root="${TMP_DIR}/codex-paths"
  test_home="${test_root}/home"
  workspace="${test_home}/Workspace"
  workspace_project="${workspace}/project"
  sed '$d' "$codex_wrapper" >"$wrapper_library"
  install -d -m 0777 -- "$test_home" "$test_home/.config" "$test_home/.config/bazel" "$test_home/Downloads" "$workspace" "$workspace_project"

  /usr/bin/env -i HOME="$test_home" USER="$(id -un)" PATH=/usr/bin:/bin \
    /bin/bash -Eeuo pipefail -c '
      . "$1"
      codex_require_account_owned_home_directory HOME "$HOME"
      codex_require_account_owned_home_directory "managed Workspace directory" "$HOME/Workspace"
      BWRAP_ARGS=()
      codex_append_home_ro_bind_if_present .config/bazel
      [[ "${BWRAP_ARGS[${#BWRAP_ARGS[@]} - 3]}" == --ro-bind ]]
      cd "$2"
      [[ "$(codex_select_sandbox_cwd)" == "$2" ]]
    ' bash "$wrapper_library" "$workspace_project" || return 1

  ln -s -- "$test_home/.config/bazel" "$test_home/.config/bazel-link"
  if /usr/bin/env -i HOME="$test_home" PATH=/usr/bin:/bin \
       /bin/bash -Eeuo pipefail -c '. "$1"; BWRAP_ARGS=(); codex_append_home_ro_bind_if_present .config/bazel-link' \
       bash "$wrapper_library" >/dev/null 2>&1; then
    return 1
  fi
}

codex_wrapper_work_area_guards_work() {
  wrapper_library="${TMP_DIR}/codex-wrapper-pool-library"
  test_root="${TMP_DIR}/codex-pool-storage"
  direct_path="${test_root}/direct"
  readonly_path="${test_root}/readonly"
  real_parent="${test_root}/real-parent"
  linked_parent="${test_root}/linked-parent"
  linked_path="${test_root}/linked"
  current_uid=$(id -u)
  current_group=

  sed '$d' "$codex_wrapper" >"$wrapper_library"
  python3 - "$codex_wrapper" <<'PY' || return 1
from pathlib import Path
import sys

wrapper = Path(sys.argv[1]).read_text(encoding="utf-8")
main_start = wrapper.index("main() {\n")
work_area_preflight = wrapper.index(
    "  codex_require_managed_work_areas\n",
    main_start,
)
direct_mode = wrapper.index(
    "  if ((CODEX_USE_BWRAP == 0)); then\n",
    main_start,
)
assert work_area_preflight < direct_mode
assert "IFS=' ' read -r -a current_group_ids" in wrapper
assert '"${pool_root}/${USER}"' in wrapper
assert 'declare -a DEVOPS_READ_WRITE_HOME_DIRECTORIES=(\n  Downloads\n  Workspace\n)' in wrapper
assert '"${CODEX_POOL_ROOT}/cache"' in wrapper
assert '"${CODEX_POOL_ROOT}/build"' in wrapper
assert '"${CODEX_POOL_ROOT}/db"' in wrapper
assert '"${CODEX_STORAGE_ROOT}"' in wrapper
assert '"${CODEX_SHARED_DOWNLOADS_ROOT}"' in wrapper
assert 'codex_require_directory "pool cache root" /pool/cache' not in wrapper
assert 'codex_require_directory "pool build root" /pool/build' not in wrapper
assert 'codex_require_directory "pool database root" /pool/db' not in wrapper
assert 'codex_require_account_owned_home_directory' in wrapper
assert '"managed ${home_directory} directory"' in wrapper
assert '    0 \\\n    devops \\\n    2775 \\\n    1' in wrapper
assert "      0 \\\n      devops \\\n      2770 \\\n      1" in wrapper
assert '"${account_uid}" \\\n      devops \\\n      2770 \\\n      1' in wrapper
assert '    0 \\\n    devops \\\n    3770 \\\n    1' in wrapper
assert '"${account_uid}" \\\n    "${USER}" \\\n    2750 \\\n    1' in wrapper
PY

  install -d -m 2770 -- "$direct_path"
  install -d -m 0550 -- "$readonly_path"
  install -d -m 0755 -- "$real_parent"
  install -d -m 2770 -- "${real_parent}/nested"
  ln -s -- "$real_parent" "$linked_parent"
  ln -s -- "$direct_path" "$linked_path"
  current_group=$(stat -c '%G' -- "$direct_path") ||
    return 1

  /usr/bin/env -i PATH=/usr/bin:/bin /bin/bash -Eeuo pipefail -c '
    # shellcheck disable=SC1090
    . "$1"
    codex_require_managed_directory \
      "test managed work directory" \
      "$2" \
      "$3" \
      "$4" \
      2770 \
      1
  ' bash \
    "$wrapper_library" \
    "$direct_path" \
    "$current_uid" \
    "$current_group" ||
    return 1

  for invalid_case in \
    "missing:${test_root}/missing:${current_uid}:${current_group}:2770:1" \
    "symlink:${linked_path}:${current_uid}:${current_group}:2770:1" \
    "ancestor-symlink:${linked_parent}/nested:${current_uid}:${current_group}:2770:1" \
    "owner:${direct_path}:$((current_uid + 1)):${current_group}:2770:1" \
    "group:${direct_path}:${current_uid}:not-the-current-group:2770:1" \
    "mode:${direct_path}:${current_uid}:${current_group}:2750:1" \
    "writable:${readonly_path}:${current_uid}:${current_group}:550:1"
  do
    IFS=: read -r _ invalid_path expected_uid expected_group expected_mode require_write <<EOF
${invalid_case}
EOF
    if /usr/bin/env -i PATH=/usr/bin:/bin /bin/bash -Eeuo pipefail -c '
         # shellcheck disable=SC1090
         . "$1"
         codex_require_managed_directory \
           "invalid managed work directory" \
           "$2" \
           "$3" \
           "$4" \
           "$5" \
           "$6"
       ' bash \
         "$wrapper_library" \
         "$invalid_path" \
         "$expected_uid" \
         "$expected_group" \
         "$expected_mode" \
         "$require_write" \
         >/dev/null 2>&1; then
      return 1
    fi
  done
}

codex_wrapper_mount_and_cleanup_contract_work() {
  wrapper_library="${TMP_DIR}/codex-wrapper-contract-library"
  control_dir="${TMP_DIR}/codex-cleanup-control"
  bash_env_payload="${TMP_DIR}/codex-wrapper-bash-env"
  bash_env_marker="${TMP_DIR}/codex-wrapper-bash-env.loaded"
  sed '$d' "$codex_wrapper" >"$wrapper_library"

  python3 - "$codex_wrapper" <<'PY'
from pathlib import Path
import re
import sys

wrapper = Path(sys.argv[1]).read_text(encoding="utf-8")
assert wrapper.startswith("#!/bin/bash -p\n")
assert 'readonly CODEX_HOST_LOG_ROOT="/var/log/managed/openai/codex"' in wrapper


def position(fragment: str) -> int:
    value = wrapper.find(fragment)
    assert value >= 0, fragment
    return value


root_ro = position("    --ro-bind / /\n")
data_ro = position("    --ro-bind /data /data\n")
pool_rw = position(
    '    --bind "${CODEX_POOL_ROOT}" "${CODEX_POOL_ROOT}"\n'
)
sys_ro = position("    --ro-bind /sys /sys\n")
codex_storage_rw = position(
    '    --bind "${CODEX_STORAGE_ROOT}" "${CODEX_STORAGE_ROOT}"\n'
)
shared_downloads_rw = position(
    '    --bind "${CODEX_SHARED_DOWNLOADS_ROOT}" '
    '"${CODEX_SHARED_DOWNLOADS_ROOT}"\n'
)
runtime_home_rw = position(
    '    --bind "${CODEX_RUNTIME_HOME}" "${CODEX_RUNTIME_HOME}"\n'
)
installation_id = position(
    '    --bind "${CODEX_CONTROL_DIR}/installation_id" '
    '"${CODEX_RUNTIME_HOME}/installation_id"\n'
)
log_rw = position(
    '    --bind "${CODEX_HOST_LOG_ROOT}" "${CODEX_LOG_ROOT}"\n'
)
sqlite_rw = position(
    '    --bind "${CODEX_SQLITE_ROOT}" "${CODEX_SQLITE_ROOT}"\n'
)
runtime_tmpfs = position('    --tmpfs "${CODEX_RUNTIME_ROOT}"\n')
memory_guard = position(
    '    --ro-bind "${CODEX_MEMORY_GIT_GUARD}" "${CODEX_MEMORY_GIT_GUARD}"\n'
)
selective_home = position("  codex_append_selective_home_access\n")
accelerator_devices = position("  codex_append_accelerator_device_binds\n")
assert root_ro < data_ro < pool_rw < sys_ro < codex_storage_rw
assert codex_storage_rw < shared_downloads_rw < runtime_home_rw
assert data_ro < runtime_home_rw < installation_id < log_rw < sqlite_rw
assert sqlite_rw < runtime_tmpfs < memory_guard < selective_home
assert selective_home < accelerator_devices
assert (
    '  codex_require_devops_shared_account_directory \\\n'
    '    "managed Codex host log directory" \\\n'
    '    "${CODEX_HOST_LOG_ROOT}"\n'
) in wrapper
assert "local -a device_paths=(" in wrapper
assert "local -a nvidia_device_paths=()" in wrapper
assert "nvidia_device_paths=(/dev/nvidia[0-9]*)" in wrapper
assert "shopt -s nullglob" in wrapper
assert "shopt -u nullglob" in wrapper
assert 'for device_path in "${device_paths[@]}"; do' in wrapper
assert wrapper.count(
    '    --bind "${CODEX_RUNTIME_HOME}" "${CODEX_RUNTIME_HOME}"\n'
) == 1
for redundant in (
    '${CODEX_RUNTIME_HOME}/sessions',
    '${CODEX_RUNTIME_HOME}/history.jsonl',
    '${CODEX_RUNTIME_HOME}/session_index.jsonl',
):
    assert f'--bind "{redundant}" "{redundant}"' not in wrapper
assert 'rm -rf -- "${CODEX_MEMORY_GIT_GUARD}"' not in wrapper
assert "sandbox_cwd=$(codex_select_sandbox_cwd)" in wrapper
unset_environment = re.search(
    r"declare -a SANDBOX_UNSET_ENV_NAMES=\(\n(?P<body>.*?)\n\)",
    wrapper,
    re.DOTALL,
)
assert unset_environment is not None
unset_names = {
    line.strip()
    for line in unset_environment.group("body").splitlines()
    if line.strip()
}
ambient_x11_environment = re.search(
    r"declare -ar AMBIENT_X11_ENV_NAMES=\(\n(?P<body>.*?)\n\)",
    wrapper,
    re.DOTALL,
)
assert ambient_x11_environment is not None
ambient_x11_names = {
    line.strip()
    for line in ambient_x11_environment.group("body").splitlines()
    if line.strip()
}
assert ambient_x11_names == {
    "DESKTOP_STARTUP_ID",
    "DISPLAY",
    "SESSION_MANAGER",
    "WINDOWID",
    "WLR_XWAYLAND",
    "XAUTHORITY",
    "XWAYLAND",
    "XWAYLAND_FORCE_SCALE",
    "XWAYLAND_NO_GLAMOR",
    "XWAYLAND_PATH",
    "XWAYLAND_RESTART_DELAY",
    "_XWAYLAND_GLOBAL_OUTPUT_SCALE",
}
assert ambient_x11_names <= unset_names
assert {
    "BASHOPTS",
    "BASH_ENV",
    "ENV",
    "LD_AUDIT",
    "LD_DEBUG",
    "LD_LIBRARY_PATH",
    "LD_PRELOAD",
    "PYTHONHOME",
    "PYTHONINSPECT",
    "PYTHONPATH",
    "PYTHONSTARTUP",
    "PYTHONUSERBASE",
    "SHELLOPTS",
} <= unset_names
direct_start = wrapper.index('  if ((CODEX_USE_BWRAP == 0)); then\n')
direct_end = wrapper.index(
    '  fi\n\n  codex_require_devops_shared_account_directory \\\n'
    '    "managed Codex host log directory"',
    direct_start,
)
direct_block = wrapper[direct_start:direct_end]
assert 'for env_name in "${AMBIENT_X11_ENV_NAMES[@]}"; do' in direct_block
assert 'unset "${env_name}"' in direct_block
assert direct_block.index('unset "${env_name}"') < direct_block.index(
    'exec "${CODEX_RAW_BINARY}"'
)
PY

  cat >"$bash_env_payload" <<EOF
printf '%s\n' loaded >"$bash_env_marker"
exit 86
EOF
  chmod 0600 -- "$bash_env_payload"
  set +e
  /usr/bin/env -i \
    BASH_ENV="$bash_env_payload" \
    HOME="$TMP_DIR" \
    LOGNAME="$(id -un)" \
    PATH=/usr/bin:/bin \
    USER="$(id -un)" \
    "$codex_wrapper" --no-bwrap \
    >/dev/null 2>&1
  wrapper_status=$?
  set -e
  [ "$wrapper_status" -ne 86 ] &&
    [ ! -e "$bash_env_marker" ] ||
    return 1

  install -d -m 0700 -- "$control_dir"
  /usr/bin/env -i PATH=/usr/bin:/bin /bin/bash -Eeuo pipefail -c '
    # shellcheck disable=SC1090
    . "$1"

    codex_parse_arguments alpha --no-bwrap beta
    [[ "${CODEX_USE_BWRAP}" == 0 ]]
    [[ "${#CODEX_ARGS[@]}" == 2 ]]
    [[ "${CODEX_ARGS[0]}" == alpha ]]
    [[ "${CODEX_ARGS[1]}" == beta ]]

    CODEX_CONTROL_DIR=$2
    set +e
    false
    codex_cleanup
    cleanup_status=$?
    set -e
    [[ "${cleanup_status}" == 1 ]]
    [[ ! -e "$2" ]]
  ' bash "$wrapper_library" "$control_dir"
}

codex_wrapper_activates_managed_devops() {
  wrapper_library="${TMP_DIR}/codex-wrapper-devops-library"
  test_home="${TMP_DIR}/codex-devops-home"
  test_runtime="${TMP_DIR}/codex-devops-runtime"
  profile_dir="${test_home}/.profile.d"
  profile_path="${profile_dir}/71-devops-de.sh"
  current_user=$(id -un)

  sed '$d' "$codex_wrapper" >"$wrapper_library"
  /bin/bash -Eeuo pipefail -c '
    # shellcheck disable=SC1090
    source "$1"

    test_home=$2
    install -d -m 0700 -- \
      "$test_home" \
      "$test_home/Downloads" \
      "$test_home/Workspace"
    for relative_path in "${DEVOPS_READ_ONLY_HOME_DIRECTORIES[@]}"; do
      install -d -m 0700 -- "${test_home}/${relative_path}"
    done
    for relative_path in "${DEVOPS_READ_ONLY_HOME_FILES[@]}"; do
      install -d -m 0700 -- "$(dirname -- "${test_home}/${relative_path}")"
      : >"${test_home}/${relative_path}"
      chmod 0600 -- "${test_home}/${relative_path}"
    done
  ' bash "$wrapper_library" "$test_home"
  install -d -m 0700 -- "$test_runtime"

  install -d -m 0700 -- \
    "${test_home}/.cache" \
    "${test_home}/.config/age" \
    "${test_home}/.config/npm" \
    "${test_home}/.config/sccache" \
    "${test_home}/.config/sops" \
    "${test_home}/.gnupg" \
    "${test_home}/.ssh"
  for sensitive_file in \
    .bash_history \
    .git-credentials \
    .npmrc \
    .zsh_history \
    .config/containers/auth.json \
    .ssh/config
  do
    install -d -m 0700 -- "$(dirname -- "${test_home}/${sensitive_file}")"
    : >"${test_home}/${sensitive_file}"
    chmod 0600 -- "${test_home}/${sensitive_file}"
  done
  cat >"$profile_path" <<'SH'
devops_de_apply_environment() {
  unset DEVOPS_PROFILE_REMOVED
  export DEVOPS_DE_ACTIVE=1
  export DEVOPS_PROFILE_ONLY=from-profile
  export PYTHONUSERBASE=/profile/python
  export XDG_CONFIG_HOME="${HOME}/.config"
  PATH=/opt/profile-only/bin:/usr/local/bin:/usr/bin:/bin:/data/codex/lib
  export PATH
}
SH
  chmod 0600 "$profile_path"

  /usr/bin/env -i \
    HOME="$test_home" \
    USER="$current_user" \
    LOGNAME="$current_user" \
    DEVOPS_PROFILE_REMOVED=stale \
    XDG_RUNTIME_DIR="$test_runtime" \
    PATH=/usr/bin:/bin \
    PWD="${test_home}/Workspace" \
    /bin/bash -Eeuo pipefail -c '
      # shellcheck disable=SC1090
      . "$1"

      args_contain_triplet() {
        local first=$1
        local second=$2
        local third=$3
        local index

        for ((index = 0; index + 2 < ${#BWRAP_ARGS[@]}; index++)); do
          if [[ "${BWRAP_ARGS[index]}" == "$first" &&
                "${BWRAP_ARGS[index + 1]}" == "$second" &&
                "${BWRAP_ARGS[index + 2]}" == "$third" ]]; then
            return 0
          fi
        done
        return 1
      }

      args_contain_value() {
        local expected=$1
        local argument

        for argument in "${BWRAP_ARGS[@]}"; do
          [[ "${argument}" == "${expected}" ]] && return 0
        done
        return 1
      }

      codex_prepare_environment
      [[ "${DEVOPS_DE_ACTIVE}" == 1 ]]
      [[ "${DEVOPS_PROFILE_ONLY}" == from-profile ]]
      [[ -z "${DEVOPS_PROFILE_REMOVED+x}" ]]
      [[ "${XDG_CONFIG_HOME}" == "${HOME}/.config" ]]
      [[ "${PYTHONUSERBASE}" == /profile/python ]]
      [[ "${CODEX_SANDBOX_PATH}" == /opt/profile-only/bin:/usr/local/bin:/usr/bin:/bin:/data/codex/share/bin ]]
      [[ "${PATH}" == "/usr/sbin:/usr/bin:/sbin:/bin" ]]
      [[ "${SHELL}" == /bin/zsh ]]

      BWRAP_ARGS=()
      codex_append_devops_environment
      args_contain_triplet --setenv DEVOPS_PROFILE_ONLY from-profile
      args_contain_triplet --setenv PYTHONUSERBASE /profile/python
      ! args_contain_value DEVOPS_PROFILE_REMOVED

      BWRAP_ARGS=()
      codex_append_selective_home_access
      for relative_path in "${DEVOPS_READ_WRITE_HOME_DIRECTORIES[@]}"; do
        args_contain_triplet \
          --bind \
          "${HOME}/${relative_path}" \
          "${HOME}/${relative_path}"
      done
      for relative_path in "${DEVOPS_READ_ONLY_HOME_DIRECTORIES[@]}"; do
        args_contain_triplet \
          --ro-bind \
          "${HOME}/${relative_path}" \
          "${HOME}/${relative_path}"
      done
      for relative_path in "${DEVOPS_READ_ONLY_HOME_FILES[@]}"; do
        args_contain_triplet \
          --ro-bind \
          "${HOME}/${relative_path}" \
          "${HOME}/${relative_path}"
      done
      for forbidden_path in \
        "${HOME}/.cache" \
        "${HOME}/.config/age" \
        "${HOME}/.config/npm" \
        "${HOME}/.config/sccache" \
        "${HOME}/.config/sops" \
        "${HOME}/.gnupg" \
        "${HOME}/.ssh" \
        "${HOME}/.bash_history" \
        "${HOME}/.git-credentials" \
        "${HOME}/.npmrc" \
        "${HOME}/.zsh_history" \
        "${HOME}/.config/containers/auth.json" \
        "${HOME}/.ssh/config"
      do
        ! args_contain_value "${forbidden_path}"
      done
    ' bash "$wrapper_library"
}

codex_chatgpt_devops_allowlists_match() {
  python3 - "$codex_wrapper" "$managed_app_profiles" <<'PY'
import ast
from pathlib import Path
import re
import sys

wrapper_path = Path(sys.argv[1])
profiles_path = Path(sys.argv[2])
wrapper = wrapper_path.read_text(encoding="utf-8")
profiles_source = profiles_path.read_text(encoding="utf-8")


def bash_array(name: str) -> tuple[str, ...]:
    match = re.search(
        rf"declare -a {re.escape(name)}=\(\n(?P<body>.*?)\n\)",
        wrapper,
        re.DOTALL,
    )
    assert match is not None, name
    return tuple(
        line.strip()
        for line in match.group("body").splitlines()
        if line.strip()
    )


module = ast.parse(profiles_source)
assignments = {}
for node in module.body:
    if not isinstance(node, ast.Assign):
        continue
    for target in node.targets:
        if isinstance(target, ast.Name):
            assignments[target.id] = node.value

expected_home_directories = (
    ".cmake/packages",
    ".config/Code/User/snippets",
    ".config/bat",
    ".config/bazel",
    ".config/clangd",
    ".config/direnv",
    ".config/featherpad",
    ".config/fzf",
    ".config/git",
    ".config/micro",
    ".config/mise",
    ".config/nano",
    ".config/nvim",
    ".config/pip",
    ".config/powershell",
    ".config/retroarch",
    ".config/satty",
    ".config/sleek",
    ".config/task",
    ".config/vim",
    ".config/yamllint",
    ".local/bin",
    ".local/lib",
    ".local/share/powershell/Modules",
)
expected_home_files = (
    ".bash_aliases",
    ".bash_logout",
    ".bash_profile",
    ".bashrc",
    ".config/Code/User/keybindings.json",
    ".config/Code/User/settings.json",
    ".config/cargo/config.toml",
    ".config/containers/containers.conf",
    ".config/containers/mounts.conf",
    ".config/containers/policy.json",
    ".config/containers/registries.conf",
    ".config/containers/seccomp.json",
    ".config/containers/storage.conf",
    ".config/gh/config.yml",
    ".config/go/env",
    ".config/mimeapps.list",
    ".config/obsidian/obsidian.json",
    ".config/starship.toml",
    ".config/user-dirs.dirs",
    ".config/uv/uv.toml",
    ".config/xdg-terminals.list",
    ".dircolors",
    ".gitconfig",
    ".gitlint",
    ".lldbinit",
    ".markdownlint-cli2.cjs",
    ".markdownlint-cli2.jsonc",
    ".markdownlint-cli2.mjs",
    ".markdownlint-cli2.yaml",
    ".markdownlint.json",
    ".markdownlint.yaml",
    ".markdownlint.yml",
    ".profile",
    ".profile.d/71-devops-de.sh",
    ".profile.d/72-incus.sh",
    ".profile.d/75-firmware-workspace.sh",
    ".recoll/recoll.conf",
    ".ripgreprc",
    ".rustfmt.toml",
    ".shellcheckrc",
    ".vimrc",
    ".zlogin",
    ".zlogout",
    ".zprofile",
    ".zsh_aliases",
    ".zshenv",
    ".zshrc",
)

codex_directories = bash_array("DEVOPS_READ_ONLY_HOME_DIRECTORIES")
codex_files = bash_array("DEVOPS_READ_ONLY_HOME_FILES")
codex_rw_home_directories = bash_array("DEVOPS_READ_WRITE_HOME_DIRECTORIES")
chatgpt_directories = ast.literal_eval(
    assignments["CHATGPT_DEVOPS_READ_ONLY_HOME_DIRECTORIES"]
)
chatgpt_files = ast.literal_eval(
    assignments["CHATGPT_DEVOPS_READ_ONLY_HOME_FILES"]
)
chatgpt_rw_home_directories = ast.literal_eval(
    assignments["CHATGPT_DEVOPS_READ_WRITE_HOME_DIRECTORIES"]
)
chatgpt_rw_paths = ast.literal_eval(
    assignments["CHATGPT_DEVOPS_READ_WRITE_PATHS"]
)

assert codex_directories == expected_home_directories
assert chatgpt_directories == expected_home_directories
assert codex_files == expected_home_files
assert chatgpt_files == expected_home_files
assert codex_directories == chatgpt_directories
assert codex_files == chatgpt_files
assert codex_rw_home_directories == ("Downloads", "Workspace")
assert chatgpt_rw_home_directories == ("Downloads", "Workspace")
assert codex_rw_home_directories == chatgpt_rw_home_directories
assert chatgpt_rw_paths == (
    "/pool",
    "/data/codex",
    "/data/downloads",
)

for path in (*codex_directories, *codex_files):
    assert path not in {
        ".cache",
        ".gnupg",
        ".npmrc",
        ".ssh",
        ".bash_history",
        ".git-credentials",
        ".zsh_history",
    }
    assert not path.startswith((".cache/", ".gnupg/", ".ssh/"))
    assert path not in {
        ".config/age",
        ".config/npm",
        ".config/sccache",
        ".config/sops",
        ".config/containers/auth.json",
    }

assert (
    '"rw_bind_home_directories": CHATGPT_DEVOPS_READ_WRITE_HOME_DIRECTORIES,'
    in profiles_source
)
assert 'for home_directory in "${DEVOPS_READ_WRITE_HOME_DIRECTORIES[@]}"; do' in wrapper
assert '--bind "${CODEX_POOL_ROOT}" "${CODEX_POOL_ROOT}"' in wrapper
assert '--bind "${CODEX_STORAGE_ROOT}" "${CODEX_STORAGE_ROOT}"' in wrapper
assert (
    '--bind "${CODEX_SHARED_DOWNLOADS_ROOT}" '
    '"${CODEX_SHARED_DOWNLOADS_ROOT}"'
    in wrapper
)
assert ".config/bazel" in codex_directories
assert ".config/cargo/config.toml" in codex_files
assert ".config/powershell" in codex_directories
assert ".local/share/powershell/Modules" in codex_directories
assert ".cmake/packages" in codex_directories
assert ".bash_logout" in codex_files
assert ".zlogin" in codex_files
assert "/usr/local/bin/bazel" not in wrapper
assert "/usr/local/bin/bazel" not in profiles_source
assert '"bazel": {' not in profiles_source
PY
}

llama_launcher_works() {
  wrapper_root="${TMP_DIR}/llama-runtime"
  wrapper_bin="${wrapper_root}/bin"
  wrapper_path="${wrapper_root}/lib/llama"
  wrapper_config_dir="${TMP_DIR}/llama-config"
  wrapper_config="${wrapper_config_dir}/llama.conf"
  fake_binary="${TMP_DIR}/fake-llama-binary"
  wrapper_log="${TMP_DIR}/llama-wrapper.log"
  expected_log="${TMP_DIR}/llama-wrapper.expected"
  current_uid=$(id -u)
  current_gid=$(id -g)

  install -d -m 0755 \
    "$wrapper_root" \
    "${wrapper_root}/share" \
    "$wrapper_bin" \
    "$(dirname "$wrapper_path")" \
    "$wrapper_config_dir"
  sed \
    -e "s|/etc/llama|${wrapper_config_dir}|g" \
    -e "s|/data/llama|${wrapper_root}|g" \
    -e "s|0:0:|${current_uid}:${current_gid}:|g" \
    "$llama_launcher" >"$wrapper_path"
  chmod 0755 "$wrapper_path"
  /bin/sh -n "$wrapper_path"

  sed \
    -e 's|__LLAMA_MODEL__|/pool/cache/llama/models/test.gguf|g' \
    -e 's|__LLAMA_RUNTIME_CONTEXT__|4096|g' \
    -e 's|__LLAMA_RUNTIME_BATCH__|128|g' \
    -e 's|__LLAMA_RUNTIME_UBATCH__|64|g' \
    -e 's|__LLAMA_RUNTIME_THREADS__|4|g' \
    -e 's|__LLAMA_RUNTIME_THREADS_BATCH__|3|g' \
    -e 's|__LLAMA_RUNTIME_GPU_LAYERS__|0|g' \
    -e 's|__LLAMA_RUNTIME_KV_OFFLOAD__|0|g' \
    -e 's|__LLAMA_RUNTIME_PARALLEL__|1|g' \
    -e 's|__LLAMA_SERVER_HOST__|127.0.0.1|g' \
    -e 's|__LLAMA_SERVER_PORT__|8080|g' \
    "$llama_runtime_template" >"$wrapper_config"
  chmod 0644 "$wrapper_config"

  cat >"$fake_binary" <<'SH'
#!/bin/sh
set -eu

{
  printf 'binary=%s\n' "${0##*/}"
  printf 'model=%s\n' "${LLAMA_ARG_MODEL-}"
  printf 'context=%s\n' "${LLAMA_ARG_CTX_SIZE-}"
  printf 'threads=%s\n' "${LLAMA_ARG_THREADS-}"
  printf 'parallel=%s\n' "${LLAMA_ARG_N_PARALLEL-}"
  printf 'host=%s\n' "${LLAMA_ARG_HOST-}"
  printf 'port=%s\n' "${LLAMA_ARG_PORT-}"
  for argument do
    printf 'arg=%s\n' "$argument"
  done
} >"$LLAMA_WRAPPER_TEST_LOG"
SH
  chmod 0755 "$fake_binary"
  cp "$fake_binary" "$wrapper_bin/llama-cli"
  cp "$fake_binary" "$wrapper_bin/llama-server"
  chmod 0755 "$wrapper_bin/llama-cli" "$wrapper_bin/llama-server"

  /usr/bin/env -i \
    PATH=/usr/bin:/bin \
    LLAMA_WRAPPER_TEST_LOG="$wrapper_log" \
    "$wrapper_path" prompt
  cat >"$expected_log" <<'EOF'
binary=llama-cli
model=/pool/cache/llama/models/test.gguf
context=4096
threads=4
parallel=1
host=
port=
arg=--threads-batch
arg=3
arg=prompt
EOF
  cmp -s "$expected_log" "$wrapper_log" || return 1

  /usr/bin/env -i \
    PATH=/usr/bin:/bin \
    LLAMA_WRAPPER_TEST_LOG="$wrapper_log" \
    LLAMA_ARG_THREADS=6 \
    LLAMA_ARG_THREADS_BATCH=7 \
    "$wrapper_path" cli --verbose
  grep -Fqx 'binary=llama-cli' "$wrapper_log" &&
    grep -Fqx 'threads=6' "$wrapper_log" &&
    grep -Fqx 'arg=7' "$wrapper_log" &&
    grep -Fqx 'arg=--verbose' "$wrapper_log" ||
    return 1

  /usr/bin/env -i \
    PATH=/usr/bin:/bin \
    LLAMA_WRAPPER_TEST_LOG="$wrapper_log" \
    "$wrapper_path" cli --threads-batch 9 --verbose
  cat >"$expected_log" <<'EOF'
binary=llama-cli
model=/pool/cache/llama/models/test.gguf
context=4096
threads=4
parallel=1
host=
port=
arg=--threads-batch
arg=9
arg=--verbose
EOF
  cmp -s "$expected_log" "$wrapper_log" || return 1

  /usr/bin/env -i \
    PATH=/usr/bin:/bin \
    LLAMA_WRAPPER_TEST_LOG="$wrapper_log" \
    "$wrapper_path" server --verbose
  grep -Fqx 'binary=llama-server' "$wrapper_log" &&
    grep -Fqx 'host=127.0.0.1' "$wrapper_log" &&
    grep -Fqx 'port=8080' "$wrapper_log" &&
    grep -Fqx 'arg=3' "$wrapper_log" &&
    grep -Fqx 'arg=--verbose' "$wrapper_log" ||
    return 1

  /usr/bin/env -i \
    PATH=/usr/bin:/bin \
    LLAMA_WRAPPER_TEST_LOG="$wrapper_log" \
    LLAMA_ARG_HOST=0.0.0.0 \
    LLAMA_ARG_PORT=65535 \
    "$wrapper_path" server --verbose
  grep -Fqx 'binary=llama-server' "$wrapper_log" &&
    grep -Fqx 'host=127.0.0.1' "$wrapper_log" &&
    grep -Fqx 'port=8080' "$wrapper_log" ||
    return 1

  chmod 0666 "$wrapper_config"
  if /usr/bin/env -i \
       PATH=/usr/bin:/bin \
       LLAMA_WRAPPER_TEST_LOG="$wrapper_log" \
       "$wrapper_path" prompt >/dev/null 2>&1
  then
    return 1
  fi
  chmod 0644 "$wrapper_config"

  printf '%s\n' 'LLAMA_THREADS=9' >>"$wrapper_config"
  if /usr/bin/env -i \
       PATH=/usr/bin:/bin \
       LLAMA_WRAPPER_TEST_LOG="$wrapper_log" \
       "$wrapper_path" prompt >/dev/null 2>&1
  then
    return 1
  fi
  sed -i '$d' "$wrapper_config"

  printf '%s\n' 'LLAMA_BINARY_DIR=/tmp/llama-bin' >>"$wrapper_config"
  if /usr/bin/env -i \
       PATH=/usr/bin:/bin \
       LLAMA_WRAPPER_TEST_LOG="$wrapper_log" \
       "$wrapper_path" prompt >/dev/null 2>&1
  then
    return 1
  fi
  sed -i '$d' "$wrapper_config"

  mv "$wrapper_bin/llama-cli" "$wrapper_bin/llama-cli.real"
  ln -s llama-cli.real "$wrapper_bin/llama-cli"
  if /usr/bin/env -i \
       PATH=/usr/bin:/bin \
       LLAMA_WRAPPER_TEST_LOG="$wrapper_log" \
       "$wrapper_path" prompt >/dev/null 2>&1
  then
    return 1
  fi
  rm -f "$wrapper_bin/llama-cli"
  mv "$wrapper_bin/llama-cli.real" "$wrapper_bin/llama-cli"
}

llama_profile_policy_validates() {
  llama_policy_functions="${TMP_DIR}/llama-policy-functions.sh"

  sed -n '1,/^llama_target_require_command() {/p' "$llama_late" |
    sed '$d' >"$llama_policy_functions"
  [ -s "$llama_policy_functions" ] || return 1

  for profile_relpath in $desktop_profiles; do
    profile_path="$ROOT_DIR/$profile_relpath"
    /usr/bin/env -i \
      PATH=/usr/bin:/bin \
      /bin/sh -eu -c '
        policy_functions=$1
        profile_path=$2
        set -- --target-install
        # shellcheck disable=SC1090
        . "$policy_functions"
        # shellcheck disable=SC1090
        . "$profile_path"
        llama_validate_policy
      ' sh "$llama_policy_functions" "$profile_path" ||
      return 1
  done
}

ai_runtime_archive_validator_works() {
  python3 - "$ai_runtime_archive_helper" "$TMP_DIR" <<'PY'
import io
from pathlib import Path
import stat
import subprocess
import sys
import tarfile

helper = Path(sys.argv[1]).resolve()
test_root = Path(sys.argv[2]).resolve() / "ai-runtime-archive"
test_root.mkdir(mode=0o700)

required_binaries = (
    "llama-bench",
    "llama-cli",
    "llama-gguf-split",
    "llama-quantize",
    "llama-server",
)


def directory(name: str) -> tarfile.TarInfo:
    member = tarfile.TarInfo(name)
    member.type = tarfile.DIRTYPE
    member.mode = 0o755
    return member


def regular(name: str, payload: bytes = b"payload\n") -> tuple[tarfile.TarInfo, io.BytesIO]:
    member = tarfile.TarInfo(name)
    member.size = len(payload)
    member.mode = 0o777
    return member, io.BytesIO(payload)


def base_members(root: str = "llama-ram") -> list[tuple[tarfile.TarInfo, io.BytesIO | None]]:
    members: list[tuple[tarfile.TarInfo, io.BytesIO | None]] = [
        (directory(root), None),
        (directory(f"{root}/bin"), None),
        (directory(f"{root}/metadata"), None),
        (directory(f"{root}/share"), None),
        (directory(f"{root}/share/llama-ui"), None),
    ]
    members.extend(regular(f"{root}/bin/{name}") for name in required_binaries)
    members.append(regular(f"{root}/metadata/SHA256SUMS"))
    members.append(regular(f"{root}/share/llama-ui/bundle-info.txt"))
    return members


def write_archive(name: str, members: list[tuple[tarfile.TarInfo, io.BytesIO | None]]) -> Path:
    archive_path = test_root / f"{name}.tar.gz"
    with tarfile.open(archive_path, mode="w:gz", format=tarfile.USTAR_FORMAT) as archive:
        for member, payload in members:
            archive.addfile(member, payload)
    return archive_path


def command(archive_path: Path, output_directory: Path, **overrides: str) -> list[str]:
    arguments = [
        "/usr/bin/python3",
        str(helper),
        "--archive",
        str(archive_path),
        "--output-directory",
        str(output_directory),
        "--archive-root",
        "llama-ram",
        "--required-directory",
        "bin",
        "--required-directory",
        "metadata",
        "--required-directory",
        "share",
    ]
    for binary_name in required_binaries:
        arguments.extend(("--required-binary", binary_name))
    arguments.extend(
        (
            "--maximum-extracted-bytes",
            overrides.get("maximum_extracted_bytes", "1048576"),
            "--maximum-members",
            overrides.get("maximum_members", "32"),
        )
    )
    return arguments


def output_directory(name: str) -> Path:
    output = test_root / name
    output.mkdir(mode=0o700)
    output.chmod(0o700)
    return output


def expect_failure(
    name: str,
    members: list[tuple[tarfile.TarInfo, io.BytesIO | None]],
    **overrides: str,
) -> None:
    output = output_directory(f"{name}-output")
    result = subprocess.run(
        command(write_archive(name, members), output, **overrides),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    if result.returncode == 0:
        raise AssertionError(f"{name}: unsafe archive was accepted")
    if any(output.iterdir()):
        raise AssertionError(f"{name}: failed validation wrote output files")


valid_archive = write_archive("valid", base_members())
valid_output = output_directory("valid-output")
subprocess.run(command(valid_archive, valid_output), check=True)
for binary_name in required_binaries:
    binary_path = valid_output / "bin" / binary_name
    if not binary_path.is_file() or stat.S_IMODE(binary_path.stat().st_mode) != 0o755:
        raise AssertionError(f"invalid extracted binary metadata: {binary_path}")
for data_path in (
    valid_output / "metadata" / "SHA256SUMS",
    valid_output / "share" / "llama-ui" / "bundle-info.txt",
):
    if not data_path.is_file() or stat.S_IMODE(data_path.stat().st_mode) != 0o644:
        raise AssertionError(f"invalid extracted data metadata: {data_path}")

traversal_members = base_members()
traversal_members.append(regular("llama-ram/../escape"))
expect_failure("traversal", traversal_members)

symlink_members = base_members()
symlink = tarfile.TarInfo("llama-ram/metadata/link")
symlink.type = tarfile.SYMTYPE
symlink.linkname = "/etc/passwd"
symlink_members.append((symlink, None))
expect_failure("symlink", symlink_members)

unexpected_binary_members = base_members()
unexpected_binary_members.append(regular("llama-ram/bin/unexpected"))
expect_failure("unexpected-binary", unexpected_binary_members)

duplicate_members = base_members()
duplicate_members.append(regular("llama-ram/metadata/SHA256SUMS"))
expect_failure("duplicate", duplicate_members)

expect_failure("member-overflow", base_members(), maximum_members="8")
expect_failure("byte-overflow", base_members(), maximum_extracted_bytes="1")
PY
}

llama_release_rollback_works() {
  rollback_functions="${TMP_DIR}/llama-release-rollback-functions.sh"
  rollback_root="${TMP_DIR}/llama-release-rollback"

  sed -n \
    '/^llama_target_rollback_release_publication() {/,/^llama_target_download_and_install_release() {/p' \
    "$llama_late" | sed '$d' >"$rollback_functions"
  [ -s "$rollback_functions" ] || return 1

  /usr/bin/env -i PATH=/usr/bin:/bin /bin/sh -eu -c '
    functions_file=$1
    LLAMA_ROOT=$2
    LLAMA_BINARY_DIR="${LLAMA_ROOT}/bin"
    LLAMA_METADATA_DIR="${LLAMA_ROOT}/metadata"
    LLAMA_SHARE_DIR="${LLAMA_ROOT}/share"
    # shellcheck disable=SC1090
    . "$functions_file"

    mkdir -p "$LLAMA_BINARY_DIR" "$LLAMA_METADATA_DIR" "$LLAMA_SHARE_DIR"
    : >"${LLAMA_ROOT}/.installer-release"
    llama_release_publish_in_progress=1
    llama_target_rollback_release_publication
    [ "$llama_release_publish_in_progress" = 0 ]
    [ ! -e "$LLAMA_BINARY_DIR" ]
    [ ! -e "$LLAMA_METADATA_DIR" ]
    [ ! -e "$LLAMA_SHARE_DIR" ]
    [ ! -e "${LLAMA_ROOT}/.installer-release" ]

    mkdir -p "$LLAMA_BINARY_DIR" "$LLAMA_METADATA_DIR" "$LLAMA_SHARE_DIR"
    : >"${LLAMA_ROOT}/.installer-release"
    llama_release_publish_in_progress=0
    llama_target_rollback_release_publication
    [ -d "$LLAMA_BINARY_DIR" ]
    [ -d "$LLAMA_METADATA_DIR" ]
    [ -d "$LLAMA_SHARE_DIR" ]
    [ -f "${LLAMA_ROOT}/.installer-release" ]
  ' sh "$rollback_functions" "$rollback_root"
}

llama_release_class_selection_works() {
  selection_functions="${TMP_DIR}/llama-release-class-functions.sh"
  selection_error="${TMP_DIR}/llama-release-class.error"
  main_profile="$ROOT_DIR/d-i/forky/hosts/profiles/override/btrfs-de-main.env"
  flex_profile="$ROOT_DIR/d-i/forky/hosts/profiles/override/btrfs-de-flex.env"

  sed -n '1,/^llama_target_require_command() {/p' "$llama_late" |
    sed '$d' >"$selection_functions"
  [ -s "$selection_functions" ] || return 1

  run_selection() {
    selected_refs=$1
    profile_path=$2
    /usr/bin/env -i PATH=/usr/bin:/bin /bin/sh -eu -c '
      selected_refs=$1
      functions_file=$2
      profile_path=$3
      installer_selected_class_reference_is_selected() {
        case " $selected_refs " in
          *" $1 "*) return 0 ;;
        esac
        return 1
      }
      set -- --target-install
      # shellcheck disable=SC1090
      . "$functions_file"
      # shellcheck disable=SC1090
      . "$profile_path"
      llama_validate_policy
      llama_validate_release_class_selection
    ' sh "$selected_refs" "$selection_functions" "$profile_path"
  }

  run_selection 'addon/cuda-legacy' "$main_profile" || return 1
  run_selection '' "$flex_profile" || return 1
  if run_selection '' "$main_profile" >/dev/null 2>"$selection_error"; then
    return 1
  fi
  grep -Fq 'llama-cuda requires the addon/cuda-legacy runtime class' "$selection_error"
}

llama_verification_stays_target_local() {
  target_install_block="${TMP_DIR}/llama-target-install.block"
  installer_tail_block="${TMP_DIR}/llama-installer-tail.block"

  sed -n '/^llama_target_install() {/,/^if \[ "$llama_target_mode" = 1 \]; then$/p' \
    "$llama_late" >"$target_install_block"
  sed -n '/^run_llama_install_in_target "download and install selected llama.cpp runtime"/,$p' \
    "$llama_late" >"$installer_tail_block"

  grep -Fq 'No source checkout or compilation is performed.' "$target_install_block" &&
    grep -Fq 'llama_target_download_and_install_release' "$target_install_block" &&
    grep -Fq 'llama_target_verify_runtime' "$target_install_block" &&
    grep -Fq "metadata_actual=\$(stat -c '%u:%g:%a'" "$llama_late" &&
    grep -Fq 'managed llama configuration must contain exactly 11 runtime records' "$llama_late" &&
    grep -Fq 'managed llama configuration must not define the fixed binary directory' "$llama_late" &&
    grep -Fq 'The target helper verifies every installed artifact before returning.' "$installer_tail_block" ||
    return 1

  if grep -Eq '(^|[[:space:]/])stat([[:space:]]|$)' "$installer_tail_block" ||
     grep -Fq '$(stat ' "$installer_tail_block" ||
     grep -Eq '(^|[[:space:]/])grep([[:space:]]|$)' "$installer_tail_block"
  then
    return 1
  fi
}

llama_streamed_target_runner_works() {
  stream_root="${TMP_DIR}/llama-streamed-target"
  stream_functions="${stream_root}/functions.sh"
  stream_harness="${stream_root}/harness.sh"
  stream_success="${stream_root}/success"
  stream_failure="${stream_root}/failure"

  install -d -m 0700 "$stream_root" "$stream_success" "$stream_failure"
  sed -n \
    '/^llama_stream_target_output() {/,/^installer_selected_class_reference_is_selected addon\/devops/p' \
    "$llama_late" | sed '$d' >"$stream_functions"
  [ -s "$stream_functions" ] || return 1

  cat >"$stream_harness" <<'SH'
#!/bin/sh
set -eu

test_root=$1
emit_info=$2
shift 2

installer_runtime_temp_log_path() {
  printf '%s/%s\n' "$test_root" "$1"
}
target_log_should_emit() {
  case "$1:$emit_info" in
    info:1|error:*) return 0 ;;
  esac
  return 1
}
installer_info() {
  printf 'info:%s\n' "$*" >>"$test_root/events"
}
installer_error() {
  printf 'error:%s\n' "$*" >&2
}
target_log_command_start() {
  printf 'start:%s\n' "$1" >>"$test_root/events"
}
target_log_command_complete() {
  printf 'complete:%s\n' "$1" >>"$test_root/events"
  cp "$2" "$test_root/completed-output"
}
target_log_command_failure() {
  printf 'failure:%s:%s\n' "$1" "$2" >>"$test_root/events"
  cp "$4" "$test_root/failed-output"
}
target_exec() {
  "$@"
}
print_command() {
  printf 'command:'
  printf ' <%s>' "$@"
  printf '\n'
}

# shellcheck disable=SC1090
. "$test_root/functions.sh"
run_llama_install_in_target "test llama release install" "$@"
SH
  chmod 0700 "$stream_harness"
  cp "$stream_functions" "$stream_success/functions.sh"
  cp "$stream_functions" "$stream_failure/functions.sh"

  printf '[1/2] download\n[2/2] extract\n' >"$stream_success/expected"
  "$stream_harness" \
    "$stream_success" \
    1 \
    /bin/sh -c 'printf "[1/2] download\n[2/2] extract\n"' \
    >"$stream_success/stdout" \
    2>"$stream_success/stderr" || return 1
  cmp -s "$stream_success/stdout" "$stream_success/expected" || return 1
  cmp -s "$stream_success/completed-output" "$stream_success/expected" || return 1
  [ ! -s "$stream_success/stderr" ] || return 1
  grep -Fqx 'complete:test llama release install' "$stream_success/events" || return 1

  if "$stream_harness" \
       "$stream_failure" \
       0 \
       /bin/sh -c 'printf "download failed\n" >&2; exit 17' \
       >"$stream_failure/stdout" \
       2>"$stream_failure/stderr"
  then
    return 1
  else
    stream_failure_status=$?
  fi
  [ "$stream_failure_status" -eq 17 ] || return 1
  [ ! -s "$stream_failure/stdout" ] || return 1
  printf 'download failed\n' >"$stream_failure/expected"
  cmp -s "$stream_failure/failed-output" "$stream_failure/expected" || return 1
  grep -Fqx 'failure:test llama release install:17' "$stream_failure/events" || return 1
  grep -Fq 'in-target failed during test llama release install (status 17)' \
    "$stream_failure/stderr" || return 1
  grep -Fqx 'download failed' "$stream_failure/stderr"
}

llama_target_runtime_verifier_works() {
  verifier_functions="${TMP_DIR}/llama-target-verifier-functions.sh"
  verifier_root="${TMP_DIR}/llama-verify-runtime"
  verifier_bin="${verifier_root}/bin"
  verifier_metadata="${verifier_root}/metadata"
  verifier_share="${verifier_root}/share"
  verifier_ui="${verifier_share}/llama-ui"
  verifier_release_record="${verifier_root}/.installer-release"
  verifier_wrapper_dir="${verifier_root}/lib"
  verifier_wrapper="${verifier_wrapper_dir}/llama"
  verifier_model_dir="${TMP_DIR}/llama-verify-models"
  verifier_model="${verifier_model_dir}/test.gguf"
  verifier_config_dir="${TMP_DIR}/llama-verify-config"
  verifier_config="${verifier_config_dir}/llama.conf"
  verifier_command_dir="${TMP_DIR}/llama-verify-commands"
  verifier_error="${TMP_DIR}/llama-verify-error"
  verifier_uid=$(id -u)
  verifier_gid=$(id -g)

  sed -n \
    '/^llama_target_verify_metadata() {/,/^llama_target_install() {/p' \
    "$llama_late" |
    sed '$d' |
    sed \
      -e "s|/etc/llama|${verifier_config_dir}|g" \
      -e "s|0:0:|${verifier_uid}:${verifier_gid}:|g" \
      -e 's|0:${runtime_verify_devops_gid}:|'"${verifier_uid}"':${runtime_verify_devops_gid}:|g' \
      >"$verifier_functions"
  [ -s "$verifier_functions" ] || return 1

  install -d -m 0755 \
    "$verifier_command_dir" \
    "$verifier_root" \
    "$verifier_bin" \
    "$verifier_metadata" \
    "$verifier_share" \
    "$verifier_ui" \
    "$verifier_wrapper_dir" \
    "$verifier_model_dir" \
    "$verifier_config_dir"
  cat >"${verifier_command_dir}/getent" <<'SH'
#!/bin/sh
set -eu

[ "$#" -eq 2 ] && [ "$1" = group ] && [ "$2" = devops ] || exit 2
case "${VERIFIER_DEVOPS_GID:-}" in
  ''|*[!0-9]*) exit 2 ;;
esac
printf 'devops:x:%s:\n' "$VERIFIER_DEVOPS_GID"
SH
  chmod 0755 "${verifier_command_dir}/getent"
  chmod 2750 "$verifier_model_dir"
  for verifier_binary in llama-bench llama-cli llama-gguf-split llama-quantize llama-server; do
    printf '#!/bin/sh\nexit 0\n' >"${verifier_bin}/${verifier_binary}"
    chmod 0755 "${verifier_bin}/${verifier_binary}"
  done
  for verifier_metadata_name in LLAMA_CPP_LICENSE SHA256SUMS build-info.txt cmake-command.txt file.txt ldd.txt llama-cli-version.txt llama-server-version.txt; do
    printf 'release metadata\n' >"${verifier_metadata}/${verifier_metadata_name}"
    chmod 0644 "${verifier_metadata}/${verifier_metadata_name}"
  done
  for verifier_ui_name in SHA256SUMS bundle-info.txt dist.tar.gz; do
    printf 'release UI\n' >"${verifier_ui}/${verifier_ui_name}"
    chmod 0644 "${verifier_ui}/${verifier_ui_name}"
  done
  cat >"$verifier_release_record" <<'EOF'
url=https://example.invalid/llama-ram.tar.gz
sha256=0000000000000000000000000000000000000000000000000000000000000000
bytes=123
archive_root=llama-ram
EOF
  chmod 0644 "$verifier_release_record"
  printf '#!/bin/sh\nexit 0\n' >"$verifier_wrapper"
  chmod 0755 "$verifier_wrapper"
  printf 'GGUF-test\n' >"$verifier_model"
  chmod 0640 "$verifier_model"
  cat >"$verifier_config" <<EOF
# Managed by the unattended Debian installer.
# Parsed as strict KEY=VALUE records by /data/llama/lib/llama.
LLAMA_MODEL=${verifier_model}
LLAMA_CONTEXT_SIZE=4096
LLAMA_BATCH_SIZE=128
LLAMA_UBATCH_SIZE=64
LLAMA_THREADS=4
LLAMA_THREADS_BATCH=3
LLAMA_GPU_LAYERS=0
LLAMA_KV_OFFLOAD=0
LLAMA_PARALLEL=1
LLAMA_SERVER_HOST=127.0.0.1
LLAMA_SERVER_PORT=8080
EOF
  chmod 0644 "$verifier_config"

  llama_run_target_verifier() {
    /usr/bin/env -i \
      PATH="${verifier_command_dir}:/usr/bin:/bin" \
      VERIFIER_DEVOPS_GID="${1:-$verifier_gid}" \
      /bin/sh -eu -c '
      # shellcheck disable=SC1090
      . "$1"
      llama_fatal() {
        printf "fatal: %s\n" "$*" >&2
        exit 1
      }
      LLAMA_ROOT=$2
      LLAMA_BINARY_DIR=$3
      LLAMA_METADATA_DIR=$4
      LLAMA_SHARE_DIR=$5
      LLAMA_WRAPPER_PATH=$6
      LLAMA_MODEL_DIR=$7
      LLAMA_RELEASE_URL=https://example.invalid/llama-ram.tar.gz
      LLAMA_RELEASE_SHA256=0000000000000000000000000000000000000000000000000000000000000000
      LLAMA_RELEASE_BYTES=123
      LLAMA_RELEASE_ARCHIVE_ROOT=llama-ram
      LLAMA_DEFAULT_MODEL=test.gguf
      LLAMA_RUNTIME_CONTEXT=4096
      LLAMA_RUNTIME_BATCH=128
      LLAMA_RUNTIME_UBATCH=64
      LLAMA_RUNTIME_THREADS=4
      LLAMA_RUNTIME_THREADS_BATCH=3
      LLAMA_RUNTIME_GPU_LAYERS=0
      LLAMA_RUNTIME_KV_OFFLOAD=0
      LLAMA_RUNTIME_PARALLEL=1
      LLAMA_SERVER_HOST=127.0.0.1
      LLAMA_SERVER_PORT=8080
      llama_target_verify_runtime
    ' sh \
      "$verifier_functions" \
      "$verifier_root" \
      "$verifier_bin" \
      "$verifier_metadata" \
      "$verifier_share" \
      "$verifier_wrapper_dir" \
      "$verifier_model_dir"
  }

  llama_run_target_verifier || return 1

  mv "$verifier_bin/llama-bench" "$verifier_bin/llama-bench.missing"
  if llama_run_target_verifier >/dev/null 2>&1; then
    return 1
  fi
  mv "$verifier_bin/llama-bench.missing" "$verifier_bin/llama-bench"

  chmod 2775 "$verifier_model_dir"
  if llama_run_target_verifier >/dev/null 2>"$verifier_error" ||
     ! grep -Fq "$verifier_model_dir" "$verifier_error"; then
    return 1
  fi
  chmod 2750 "$verifier_model_dir"

  chmod 2757 "$verifier_model_dir"
  if llama_run_target_verifier >/dev/null 2>&1; then
    return 1
  fi
  chmod 2750 "$verifier_model_dir"

  chmod 0644 "$verifier_model"
  if llama_run_target_verifier >/dev/null 2>&1; then
    return 1
  fi
  chmod 0640 "$verifier_model"

  case "$verifier_gid" in
    0) verifier_wrong_gid=1 ;;
    *) verifier_wrong_gid=0 ;;
  esac
  if llama_run_target_verifier "$verifier_wrong_gid" >/dev/null 2>&1; then
    return 1
  fi

  printf '%s\n' 'LLAMA_BINARY_DIR=/tmp/unsafe' >>"$verifier_config"
  if llama_run_target_verifier >/dev/null 2>&1; then
    return 1
  fi
  sed -i '$d' "$verifier_config"

  chmod 0777 "$verifier_wrapper"
  if llama_run_target_verifier >/dev/null 2>&1; then
    return 1
  fi
  chmod 0755 "$verifier_wrapper"
}

printf '1..%s\n' "$TEST_COUNT"

addons_cfg="$ROOT_DIR/d-i/forky/classes/configs/addons.cfg"
devops_class="$ROOT_DIR/d-i/forky/classes/class-addon/devops.cfg"
devops_readme="$ROOT_DIR/d-i/forky/classes/class-addon/README.md"
devops_late="$ROOT_DIR/d-i/forky/scripts/late/devops.sh"
devops_tools="$ROOT_DIR/d-i/forky/scripts/late/devops-tools.py"
devops_rust_tools="$ROOT_DIR/d-i/forky/scripts/late/devops-rust-tools.py"
llama_late="$ROOT_DIR/d-i/forky/scripts/late/llama.sh"
ai_runtime_archive_helper="$ROOT_DIR/d-i/forky/scripts/late/ai-runtime-archive.py"
llama_launcher="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/data/llama/lib/llama"
llama_runtime_template="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/llama/llama.conf.tmpl"
rustup_late_section=$(sed -n '/^devops_install_pinned_rustup() {/,/^devops_prepare_codex_layout() {/p' "$devops_late")
codex_wrapper="$ROOT_DIR/d-i/forky/hooks/shared/target/data/codex/lib/codex"
codex_archive_helper="$ROOT_DIR/d-i/forky/scripts/late/codex-archive.py"
codex_sysctl_template="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/sysctl.d/90-codex-bwrap.conf.tmpl"
codex_tmpfiles_template="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/tmpfiles.d/80-codex-storage.conf.tmpl"
managed_wrapper_apparmor="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/managed-desktop-wrappers"
managed_app_profiles="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/lib/python3.14/dist-packages/labwc_managed_app/profiles.py"
desktop_components="$ROOT_DIR/d-i/forky/scripts/desktop/components.sh"
devops_profile="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.profile.d/71-devops-de.sh"
devops_bashrc="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.bashrc"
devops_zshrc="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.zshrc"
packer_template="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/packer/template.pkr.hcl.tmpl"
aptly_config_template="$ROOT_DIR/d-i/forky/scripts/late/templates/devops/aptly.conf.tmpl"
osc_config_template="$ROOT_DIR/d-i/forky/scripts/late/templates/devops/oscrc.tmpl"
osc_metadata_template="$ROOT_DIR/d-i/forky/scripts/late/templates/devops/oscrc-managed.json.tmpl"
aptly_publishing="$ROOT_DIR/d-i/forky/hooks/shared/target/usr/local/libexec/aptly-publishing"
obs_publishing="$ROOT_DIR/d-i/forky/hooks/shared/target/usr/local/libexec/obs-publishing"
mise_config="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/mise/config.toml"
mise_fragment="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/mise/conf.d/10-managed-tools.toml"
cargo_config_template="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/cargo/config.toml.tmpl"
cargo_config_static="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/cargo/config.toml"
bazelrc_template="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/bazel/bazelrc.tmpl"
node_target_helper="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/libexec/devops-install-nodejs"
bazelisk_target_helper="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/libexec/devops-install-bazelisk"
devops_target_share="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/share/devops"
desktop_profiles='
d-i/forky/hosts/profiles/btrfs/desktop.env
d-i/forky/hosts/profiles/f2fs/desktop.env
d-i/forky/hosts/profiles/vm/desktop.env
d-i/forky/hosts/profiles/override/btrfs-de.env
d-i/forky/hosts/profiles/override/btrfs-de-main.env
d-i/forky/hosts/profiles/override/btrfs-de-flex.env
d-i/forky/hosts/profiles/override/btrfs-de-dual.env
d-i/forky/hosts/profiles/override/btrfs-de-dual-main.env
d-i/forky/hosts/profiles/override/btrfs-de-dual-flex.env
d-i/forky/hosts/profiles/override/f2fs-de.env
d-i/forky/hosts/profiles/override/f2fs-de-cbook.env
d-i/forky/hosts/profiles/override/f2fs-de-dual.env
d-i/forky/hosts/profiles/override/f2fs-de-dual-cbook.env
'
required_cargo_profile_vars='
DEVOPS_CARGO_RUSTC_WRAPPER
DEVOPS_CARGO_TARGET_TRIPLE
DEVOPS_CARGO_TARGET_LINKER
DEVOPS_CARGO_TARGET_CPU
DEVOPS_CARGO_LINKER_ARGUMENT
'
required_bazel_profile_vars='
DEVOPS_BAZELISK_VERSION
DEVOPS_BAZELISK_URL
DEVOPS_BAZELISK_SHA256
DEVOPS_BAZELISK_MINIMUM_BYTES
DEVOPS_BAZELISK_MAXIMUM_BYTES
DEVOPS_BAZELISK_INSTALL_DIR
DEVOPS_BAZELISK_BINARY_PATH
DEVOPS_BAZEL_CACHE_ROOT
DEVOPS_BAZEL_BUILD_ROOT
DEVOPS_BAZEL_DB_ROOT
DEVOPS_BAZEL_CACHE_SUBDIR
DEVOPS_BAZEL_DISK_CACHE_SUBDIR
DEVOPS_BAZEL_REPOSITORY_CACHE_SUBDIR
DEVOPS_BAZEL_OUTPUT_USER_ROOT_SUBDIR
DEVOPS_BAZELISK_HOME_SUBDIR
DEVOPS_BAZEL_DISK_CACHE_SIZE
DEVOPS_BAZEL_DISK_CACHE_MAX_AGE
DEVOPS_BAZEL_DISK_CACHE_GC_IDLE_DELAY
DEVOPS_BAZEL_ACTION_CACHE_MAX_AGE
DEVOPS_BAZEL_ACTION_CACHE_GC_IDLE_DELAY
DEVOPS_BAZEL_ACTION_CACHE_GC_THRESHOLD
DEVOPS_BAZEL_INSTALL_BASE_GC_MAX_AGE
DEVOPS_BAZEL_SERVER_IDLE_SECONDS
DEVOPS_BAZEL_REPOSITORY_DOWNLOADER_RETRIES
'
required_codex_profile_vars='
DEVOPS_CODEX_VERSION
DEVOPS_CODEX_RELEASE_TAG
DEVOPS_CODEX_URL
DEVOPS_CODEX_SHA256
DEVOPS_CODEX_MAXIMUM_BYTES
DEVOPS_CODEX_MAXIMUM_EXTRACTED_BYTES
DEVOPS_CODEX_ARCHIVE_BINARY_DIR
DEVOPS_CODEX_ARCHIVE_SCHEMA_MEMBER
DEVOPS_CODEX_ROOT
DEVOPS_CODEX_BINARY_PATH
DEVOPS_CODEX_SCHEMA_PATH
DEVOPS_CODEX_WRAPPER_PATH
DEVOPS_CODEX_USER_ROOT
DEVOPS_CODEX_SYSTEM_CONFIG_DIR
DEVOPS_CODEX_LOG_DIR
DEVOPS_CODEX_SQLITE_HOME
DEVOPS_CODEX_RUNTIME_ROOT
DEVOPS_CODEX_REPOSITORY_URL
DEVOPS_CODEX_REPOSITORY_BRANCH
DEVOPS_CODEX_REPOSITORY_COMMIT
DEVOPS_CODEX_AGENTS
DEVOPS_CODEX_HOME
DEVOPS_CODEX_SKILLS
DEVOPS_CODEX_BWRAP_USERNS_CLONE
DEVOPS_CODEX_BWRAP_MAX_USER_NAMESPACES
'
required_llama_profile_vars='
LLAMA_RELEASE_URL
LLAMA_RELEASE_SHA256
LLAMA_RELEASE_BYTES
LLAMA_RELEASE_MAXIMUM_EXTRACTED_BYTES
LLAMA_RELEASE_MAXIMUM_MEMBERS
LLAMA_RELEASE_ARCHIVE_ROOT
LLAMA_RELEASE_REQUIRED_CLASS
LLAMA_ROOT
LLAMA_BINARY_DIR
LLAMA_METADATA_DIR
LLAMA_SHARE_DIR
LLAMA_WRAPPER_PATH
LLAMA_MODEL_DIR
LLAMA_FORCE_DOWNLOAD
LLAMA_DOWNLOAD_RETRIES
LLAMA_DOWNLOAD_CONNECT_TIMEOUT_SECONDS
LLAMA_DOWNLOAD_MAX_TIME_SECONDS
LLAMA_DEFAULT_MODEL
LLAMA_DOWNLOAD_URL
LLAMA_MODEL_SHA256
LLAMA_MODEL_BYTES
LLAMA_RUNTIME_CONTEXT
LLAMA_RUNTIME_BATCH
LLAMA_RUNTIME_UBATCH
LLAMA_RUNTIME_THREADS
LLAMA_RUNTIME_THREADS_BATCH
LLAMA_RUNTIME_GPU_LAYERS
LLAMA_RUNTIME_KV_OFFLOAD
LLAMA_RUNTIME_PARALLEL
LLAMA_SERVER_HOST
LLAMA_SERVER_PORT
LLAMA_STRICT_RESOURCES
LLAMA_MIN_MEMORY_MIB
LLAMA_MIN_CPU_CORES
'

if grep -q '^Name: devops$' "$addons_cfg" &&
   grep -Fq 'Description: opt-in AMD64 desktop development toolchain with upstream Deno, yt-dlp with bundled yt-dlp-ejs, Ansible CLI (Ansible Core), OpenTofu, Terraform, Packer, Wrangler, Aptly, osc, and obs-build plus system ffmpeg, local Aptly/R2 and OBS publication, pinned Codex, llama.cpp, Node, LLVM, DotSlash, uv, Rustup/rustfmt, and /pool-backed state' "$addons_cfg" &&
   grep -q '^RequiresClasses: role/desktop arch/amd64 addon/software$' "$addons_cfg" &&
   grep -q '^LateHelper: devops$' "$addons_cfg"; then
  pass "DevOps addon is an AMD64 desktop helper that requires managed software and owns the requested Rust tooling"
else
  fail "DevOps addon is an AMD64 desktop helper that requires managed software and owns the requested Rust tooling"
fi

devops_pkgsel=$(sed -n 's/^d-i pkgsel\/include string //p' "$devops_class")
if grep -Fqx 'd-i apt-setup/local22/repository string https://mise.jdx.dev/deb stable main' "$devops_class" &&
   grep -Fqx 'd-i apt-setup/local22/comment string mise upstream APT archive' "$devops_class" &&
   grep -Fqx 'd-i apt-setup/local22/key string https://mise.jdx.dev/gpg-key.pub' "$devops_class" &&
   grep -Fqx 'd-i apt-setup/local22/source boolean false' "$devops_class" &&
   grep -Fqx 'd-i apt-setup/local23/repository string https://pkg.cloudflare.com/cloudflared any main' "$devops_class" &&
   grep -Fqx 'd-i apt-setup/local23/comment string Cloudflare cloudflared APT archive' "$devops_class" &&
   grep -Fqx 'd-i apt-setup/local23/key string https://pkg.cloudflare.com/cloudflare-main.gpg' "$devops_class" &&
   grep -Fqx 'd-i apt-setup/local23/source boolean false' "$devops_class" &&
   grep -Fq 'https://get.opentofu.org/opentofu.gpg' "$devops_class" &&
   grep -Fqx '# d-i apt-setup/local24/repository string https://packages.opentofu.org/opentofu/tofu/any/ any main' "$devops_class" &&
   grep -Fqx '# d-i apt-setup/local24/key string https://packages.opentofu.org/opentofu/tofu/gpgkey' "$devops_class" &&
   grep -Fqx '# d-i apt-setup/local25/repository string https://apt.releases.hashicorp.com trixie main' "$devops_class" &&
   grep -Fqx '# d-i apt-setup/local25/comment string HashiCorp Terraform and Packer APT archive (disabled)' "$devops_class" &&
   grep -Fqx '# d-i apt-setup/local25/key string https://apt.releases.hashicorp.com/gpg' "$devops_class" &&
   grep -Fqx '# d-i apt-setup/local26/repository string http://repo.aptly.info/release trixie main' "$devops_class" &&
   grep -Fqx '# d-i apt-setup/local26/key string https://www.aptly.info/pubkey.txt' "$devops_class" &&
   grep -Fqx '# d-i apt-setup/local27/repository string http://repo.aptly.info/ci trixie main' "$devops_class" &&
   grep -Fqx '# d-i apt-setup/local27/key string https://www.aptly.info/pubkey.txt' "$devops_class" &&
   [ "$(grep -Ec '^# d-i apt-setup/local(24|25|26|27)/(repository|comment|key|source) ' "$devops_class")" -eq 16 ] &&
   grep -Eq '(^|[[:space:]])mise([[:space:]]|$)' "$devops_class" &&
   ! grep -Eq '(^|[[:space:]])node-corepack([[:space:]]|$)' "$devops_class" &&
   grep -Eq '(^|[[:space:]])clang-24([[:space:]]|$)' "$devops_class" &&
   grep -Eq '(^|[[:space:]])gcc([[:space:]]|$)' "$devops_class" &&
   grep -Eq '(^|[[:space:]])g\+\+([[:space:]]|$)' "$devops_class" &&
   grep -Eq '(^|[[:space:]])gcc-14([[:space:]]|$)' "$devops_class" &&
   grep -Eq '(^|[[:space:]])g\+\+-14([[:space:]]|$)' "$devops_class" &&
   grep -Eq '(^|[[:space:]])llvm-24([[:space:]]|$)' "$devops_class" &&
   grep -Eq '(^|[[:space:]])lld-24([[:space:]]|$)' "$devops_class" &&
   grep -Eq '(^|[[:space:]])lldb-24([[:space:]]|$)' "$devops_class" &&
   ! grep -Eq '(^|[[:space:]])rustup([[:space:]]|$)' "$devops_class" &&
   grep -Eq '(^|[[:space:]])libssl-dev([[:space:]]|$)' "$devops_class" &&
   grep -Eq '(^|[[:space:]])libcap-dev([[:space:]]|$)' "$devops_class" &&
   grep -Eq '(^|[[:space:]])libopenblas-dev([[:space:]]|$)' "$devops_class" &&
   grep -Eq '(^|[[:space:]])mold([[:space:]]|$)' "$devops_class" &&
   grep -Eq '(^|[[:space:]])xz-utils([[:space:]]|$)' "$devops_class" &&
   grep -Eq '(^|[[:space:]])ffmpeg([[:space:]]|$)' "$devops_class" &&
   grep -Eq '(^|[[:space:]])e2fsprogs([[:space:]]|$)' "$devops_class" &&
   grep -Eq '(^|[[:space:]])bubblewrap([[:space:]]|$)' "$devops_class" &&
   grep -Eq '(^|[[:space:]])slirp4netns([[:space:]]|$)' "$devops_class" &&
   ! word_list_has "$devops_pkgsel" cloudflared &&
   ! word_list_has "$devops_pkgsel" opentofu &&
   ! word_list_has "$devops_pkgsel" terraform &&
   ! word_list_has "$devops_pkgsel" packer &&
   ! word_list_has "$devops_pkgsel" ansible &&
   ! word_list_has "$devops_pkgsel" wrangler &&
   ! word_list_has "$devops_pkgsel" aptly &&
   ! word_list_has "$devops_pkgsel" osc &&
   ! word_list_has "$devops_pkgsel" obs-build &&
   grep -Eq '(^|[[:space:]])python3([[:space:]]|$)' "$devops_class" &&
   grep -Eq '(^|[[:space:]])python3-argcomplete([[:space:]]|$)' "$devops_class" &&
   grep -Eq '(^|[[:space:]])python3-cryptography([[:space:]]|$)' "$devops_class" &&
   grep -Eq '(^|[[:space:]])python3-jinja2([[:space:]]|$)' "$devops_class" &&
   grep -Eq '(^|[[:space:]])python3-keyring([[:space:]]|$)' "$devops_class" &&
   grep -Eq '(^|[[:space:]])python3-packaging([[:space:]]|$)' "$devops_class" &&
   grep -Eq '(^|[[:space:]])python3-resolvelib([[:space:]]|$)' "$devops_class" &&
   grep -Eq '(^|[[:space:]])python3-rpm([[:space:]]|$)' "$devops_class" &&
   grep -Eq '(^|[[:space:]])python3-ruamel.yaml([[:space:]]|$)' "$devops_class" &&
   grep -Eq '(^|[[:space:]])python3-secretstorage([[:space:]]|$)' "$devops_class" &&
   grep -Eq '(^|[[:space:]])python3-urllib3([[:space:]]|$)' "$devops_class" &&
   grep -Eq '(^|[[:space:]])python3-yaml([[:space:]]|$)' "$devops_class" &&
   word_list_has "$devops_pkgsel" rpm &&
   word_list_has "$devops_pkgsel" rpm2cpio &&
   word_list_has "$devops_pkgsel" libarchive-tools &&
   word_list_has "$devops_pkgsel" libwww-perl &&
   word_list_has "$devops_pkgsel" libxml-parser-perl &&
   grep -Eq '(^|[[:space:]])devscripts([[:space:]]|$)' "$devops_class" &&
   grep -Eq '(^|[[:space:]])sbuild([[:space:]]|$)' "$devops_class" &&
   grep -Eq '(^|[[:space:]])mmdebstrap([[:space:]]|$)' "$devops_class" &&
   grep -Eq '^d-i pkgsel/include string .*mise.*hyperfine.*python3.*rpm.*mmdebstrap$' "$devops_class" &&
   ! grep -Eq '^d-i pkgsel/include string .*[[:space:]]\\$' "$devops_class" &&
   ! grep -Eq '(^|[[:space:]])(jsonlint|php([[:alnum:].-]*)?)([[:space:]]|$)' "$devops_class" &&
   ! grep -Eq '(^|[[:space:]])(clang|llvm|lld|lldb)-(22|23)([[:space:]]|$)' "$devops_class" &&
   ! grep -Eq '(^|[[:space:]])(python3-venv|python3-pip|gh/trixie|glab)([[:space:]]|$)' "$devops_class"; then
  pass "DevOps package policy keeps only dependencies in pkgsel and records active Cloudflare plus disabled upstream repositories"
else
  fail "DevOps package policy keeps only dependencies in pkgsel and records active Cloudflare plus disabled upstream repositories"
fi

render_runtime="${TMP_DIR}/renderer-runtime"
render_error="${TMP_DIR}/renderer.err"
render_classes='lab,desktop,standard,dhcp,software,devops,podman,qemu,arch/amd64,cpu/intel,gpu/generic,disk/vm'
if rendered_answers=$(
  INSTALLER_RUNTIME_DIR="$render_runtime" \
  INSTALLER_SOURCE_ROOT="$ROOT_DIR/d-i/forky" \
  INSTALLER_CMDLINE="classes=${render_classes} primary_user=user primary_password=secret root_password=root fruux_username=alice fruux_password=token" \
    /bin/sh "$ROOT_DIR/d-i/forky/scripts/preseed/answers.sh" render "$ROOT_DIR/d-i/forky" 2>"$render_error"
); then
  rendered_pkgsel_count=$(grep -c '^d-i pkgsel/include string ' "$rendered_answers")
  rendered_pkgsel=$(sed -n 's/^d-i pkgsel\/include string //p' "$rendered_answers")
  rendered_duplicates=$(printf '%s\n' "$rendered_pkgsel" | tr ' ' '\n' | sort | uniq -d)
  if [ "$rendered_pkgsel_count" -eq 1 ] &&
     [ -z "$rendered_duplicates" ] &&
     word_list_has "$rendered_pkgsel" mise &&
     word_list_has "$rendered_pkgsel" mold &&
     word_list_has "$rendered_pkgsel" clang-24 &&
     word_list_has "$rendered_pkgsel" gcc &&
     word_list_has "$rendered_pkgsel" g++ &&
     word_list_has "$rendered_pkgsel" gcc-14 &&
     word_list_has "$rendered_pkgsel" g++-14 &&
     word_list_has "$rendered_pkgsel" llvm-24 &&
     word_list_has "$rendered_pkgsel" lld-24 &&
     word_list_has "$rendered_pkgsel" lldb-24 &&
     word_list_has "$rendered_pkgsel" libcap-dev &&
     word_list_has "$rendered_pkgsel" ffmpeg &&
     ! word_list_has "$rendered_pkgsel" cloudflared &&
     ! word_list_has "$rendered_pkgsel" opentofu &&
     ! word_list_has "$rendered_pkgsel" terraform &&
     ! word_list_has "$rendered_pkgsel" wrangler &&
     ! word_list_has "$rendered_pkgsel" aptly &&
     ! word_list_has "$rendered_pkgsel" osc &&
     ! word_list_has "$rendered_pkgsel" obs-build &&
     word_list_has "$rendered_pkgsel" python3 &&
     word_list_has "$rendered_pkgsel" python3-cryptography &&
     word_list_has "$rendered_pkgsel" python3-keyring &&
     word_list_has "$rendered_pkgsel" python3-rpm &&
     word_list_has "$rendered_pkgsel" python3-ruamel.yaml &&
     word_list_has "$rendered_pkgsel" python3-urllib3 &&
     word_list_has "$rendered_pkgsel" rpm &&
     word_list_has "$rendered_pkgsel" rpm2cpio &&
     word_list_has "$rendered_pkgsel" libarchive-tools &&
     word_list_has "$rendered_pkgsel" devscripts &&
     word_list_has "$rendered_pkgsel" sbuild &&
     word_list_has "$rendered_pkgsel" mmdebstrap &&
     ! word_list_has "$rendered_pkgsel" clang-22 &&
     ! word_list_has "$rendered_pkgsel" clang-23 &&
     ! word_list_has "$rendered_pkgsel" llvm-22 &&
     ! word_list_has "$rendered_pkgsel" llvm-23 &&
     ! word_list_has "$rendered_pkgsel" lld-22 &&
     ! word_list_has "$rendered_pkgsel" lld-23 &&
     ! word_list_has "$rendered_pkgsel" lldb-22 &&
     ! word_list_has "$rendered_pkgsel" lldb-23 &&
     ! word_list_has "$rendered_pkgsel" jsonlint &&
     ! word_list_has "$rendered_pkgsel" php-cli &&
     ! word_list_has "$rendered_pkgsel" php-common &&
     ! word_list_has "$rendered_pkgsel" node-corepack &&
     ! word_list_has "$rendered_pkgsel" rustup &&
     word_list_has "$rendered_pkgsel" podman &&
     word_list_has "$rendered_pkgsel" qemu-system-x86; then
    pass "DevOps packages merge into one dependency-only, deduplicated pkgsel/include answer without packaged upstream tools"
  else
    fail "DevOps packages merge into one dependency-only, deduplicated pkgsel/include answer without packaged upstream tools"
  fi
else
  fail "DevOps packages merge into one deduplicated final pkgsel/include answer with other selected classes"
fi

publishing_profiles_valid=true
forbidden_pool_root="/pool/$(printf '%s' devops)"
for profile_relpath in $desktop_profiles; do
  profile_path="$ROOT_DIR/$profile_relpath"
  profile_signing_key_count=$(grep -c '^DEVOPS_APTLY_GPG_SIGNING_KEY=' "$profile_path")
  profile_signing_key=$(sed -n 's/^DEVOPS_APTLY_GPG_SIGNING_KEY="\([^"]*\)"$/\1/p' "$profile_path")
  profile_fingerprint_count=$(grep -c '^DEVOPS_APTLY_REPOSITORY_KEY_FINGERPRINT=' "$profile_path")
  profile_fingerprint=$(sed -n 's/^DEVOPS_APTLY_REPOSITORY_KEY_FINGERPRINT="\([^"]*\)"$/\1/p' "$profile_path")
  if [ "$profile_signing_key_count" -ne 1 ]; then
    publishing_profiles_valid=false
    break
  fi
  case "$profile_signing_key" in
    /aptly-signing/*)
      profile_signing_key_name=${profile_signing_key#/aptly-signing/}
      ;;
    *)
      publishing_profiles_valid=false
      break
      ;;
  esac
  case "$profile_signing_key_name" in
    ''|.|..|*/*)
      publishing_profiles_valid=false
      break
      ;;
  esac
  if [ "${#profile_signing_key_name}" -gt 255 ]; then
    publishing_profiles_valid=false
    break
  fi
  if [ "$profile_fingerprint_count" -ne 1 ]; then
    publishing_profiles_valid=false
    break
  fi
  case "${#profile_fingerprint}" in
    40|64) ;;
    *)
      publishing_profiles_valid=false
      break
      ;;
  esac
  case "$profile_fingerprint" in
    *[!0123456789ABCDEF]*)
      publishing_profiles_valid=false
      break
      ;;
  esac
  for expected_line in \
    'DEVOPS_APTLY_ROOT_SUBDIR="aptly"' \
    'DEVOPS_APTLY_R2_ENDPOINT_URL="https://79cc1f5f831fb7f414638c3e758e9710.r2.cloudflarestorage.com"' \
    'DEVOPS_APTLY_R2_ENDPOINT_NAME="r2"' \
    'DEVOPS_APTLY_R2_BUCKET="cf-aptly-r2-prod"' \
    'DEVOPS_APTLY_R2_PREFIX="/debian"' \
    'DEVOPS_APTLY_DISTRIBUTIONS="stable testing"' \
    'DEVOPS_APTLY_COMPONENT="main"' \
    'DEVOPS_APTLY_WORKER_ROUTE="apt"' \
    'DEVOPS_APTLY_WORKER_ZONE="jcramer.xyz"' \
    'DEVOPS_APTLY_PUBLIC_BASE_URL="https://apt.jcramer.xyz"' \
    'DEVOPS_OSC_STATE_SUBDIR="osc"' \
    'DEVOPS_OSC_CACHE_SUBDIR="osc"' \
    'DEVOPS_OSC_BUILD_SUBDIR="osc"' \
    'DEVOPS_OBS_API_URL="https://api.opensuse.org"' \
    'DEVOPS_OBS_PROJECT="home:cramerz:debian"' \
    'DEVOPS_OBS_REPOSITORY="Debian_Unstable"' \
    'DEVOPS_OSC_CREDENTIALS_BACKEND="keyring.backends.SecretService.Keyring"'
  do
    if ! grep -Fqx "$expected_line" "$profile_path"; then
      publishing_profiles_valid=false
      break 2
    fi
  done
  unset \
    profile_signing_key_count \
    profile_signing_key \
    profile_signing_key_name \
    profile_fingerprint_count \
    profile_fingerprint
done

if [ "$publishing_profiles_valid" = true ] &&
   publishing_templates_validate "$aptly_config_template" "$osc_config_template" "$osc_metadata_template" &&
   publishing_wrapper_validate "$aptly_publishing" "$obs_publishing" &&
   aptly_signing_key_contract_is_safe &&
   grep -Fq 'installer_cmdline_value cf_r2_access_key' "$devops_late" &&
   grep -Fq 'installer_cmdline_value cf_r2_secret_key' "$devops_late" &&
   ! grep -Fq 'cf_r2_gpg_key' "$devops_late" &&
   ! grep -Fq 'DEVOPS_CF_R2_GPG_KEY' "$devops_late" &&
   ! grep -R -Fq 'cf_r2_gpg_key' "$ROOT_DIR/d-i/forky" &&
   grep -Fq 'installer_cmdline_value obs_username' "$devops_late" &&
   grep -Fq 'installer_cmdline_value obs_password' "$devops_late" &&
   grep -Fq 'templates/devops/aptly.conf.tmpl' "$devops_late" &&
   grep -Fq 'templates/devops/oscrc.tmpl' "$devops_late" &&
   grep -Fq 'templates/devops/oscrc-managed.json.tmpl' "$devops_late" &&
   [ ! -e "$ROOT_DIR/d-i/forky/hooks/role/desktop/target/pool" ] &&
   grep -Fq 'devops_stage_pending_credentials' "$devops_late" &&
   grep -Fq 'DEVOPS_CF_R2_SECRET_KEY \' "$devops_late" &&
   grep -Fq 'DEVOPS_OBS_PASSWORD' "$devops_late" &&
   [ -r "$devops_tools" ] &&
   python3 -c 'from pathlib import Path; import sys; source = Path(sys.argv[1]); compile(source.read_bytes(), str(source), "exec")' "$devops_tools" &&
   grep -Fq 'devops_install_upstream_tools() {' "$devops_late" &&
   grep -Fq 'installer_repo_join_var DIR_SCRIPTS_LATE devops-tools.py' "$devops_late" &&
   grep -Fq '"$aptly_binary" -config="$aptly_config"' "$devops_late" &&
   grep -Fq 'devops_initialize_aptly_repositories' "$devops_late" &&
   grep -Fq 'aptly-publish-local' "$aptly_publishing" &&
   grep -Fq 'dpkg-buildpackage' "$aptly_publishing" &&
   ! grep -Fq 'obs-publish-source' "$aptly_publishing" &&
   grep -Fq 'obs-checkout-source' "$obs_publishing" &&
   grep -Fq 'obs-publish-source' "$obs_publishing" &&
   ! grep -Fq 'aptly-publish-local' "$obs_publishing" &&
   grep -Fq 'managedLocalPublishing' "$aptly_publishing" &&
   grep -Fq 'expected_state / "managed.json"' "$obs_publishing" &&
   grep -Fq 'credentialsBackend' "$obs_publishing" &&
   grep -Fq 'APTLY_BINARY = pathlib.Path("/usr/local/lib/aptly/bin/aptly")' "$aptly_publishing" &&
   grep -Fq 'OSC_BINARY = pathlib.Path("/usr/local/lib/osc/bin/osc")' "$obs_publishing" &&
   grep -Fq 'COMMAND_TIMEOUT_SECONDS = 3600' "$aptly_publishing" &&
   grep -Fq 'COMMAND_TIMEOUT_SECONDS = 3600' "$obs_publishing" &&
   ! grep -Fq '/usr/bin/aptly' "$aptly_publishing" &&
   ! grep -Fq '/usr/bin/osc' "$obs_publishing" &&
   grep -Fq 'environment["AWS_ACCESS_KEY_ID"] = access_key' "$aptly_publishing" &&
   grep -Fq 'environment["AWS_SECRET_ACCESS_KEY"] = secret_key' "$aptly_publishing" &&
   grep -Fq 'environment["DEB_SIGN_KEYID"] = context.signing_key' "$aptly_publishing" &&
   grep -Fq 'f"-gpg-key={context.signing_key}"' "$aptly_publishing" &&
   grep -Fq 'require_signed_source_descriptors(context, package_paths)' "$aptly_publishing" &&
   grep -Fq '"${OSC_STATE_DIR}/.credentials.pending/obs-username"' "$devops_late" &&
   grep -Fq 'environment["OSC_USERNAME"] = obs_username' "$obs_publishing" &&
   ! grep -Eq 'APTLY_|OSC_|OBS_|DEB_SIGN|cf_r2|obs_username|obs_password|aptly\.conf|oscrc' "$devops_profile" &&
   ! grep -Fq '__INSTALLER_DEVOPS_OBS_USERNAME__' "$osc_config_template" &&
   ! grep -Eq '^[[:space:]]*(user|pass|passx|password)[[:space:]]*=' "$osc_config_template" &&
   ! grep -Eq 'managed_(schema|project|checkout_workspace|credentials_backend)' "$osc_config_template" &&
   grep -Fq 'export GOPATH="${devops_de_build_home}/go"' "$devops_profile" &&
   grep -Fq 'export GOMODCACHE="${devops_de_cache_home}/go-mod"' "$devops_profile" &&
   grep -Fq 'devops_de_prepend_path "${GOPATH}/bin" || return 1' "$devops_profile" &&
   grep -Fq 'devops_de_prepend_path /usr/local/libexec/aptly-publishing-bin || return 1' "$devops_profile" &&
   grep -Fq 'devops_de_prepend_path /usr/local/libexec/obs-publishing-bin || return 1' "$devops_profile" &&
   grep -Fq 'devops_de_append_path /usr/local/lib/opentufo/bin || return 1' "$devops_profile" &&
   grep -Fq 'devops_de_append_path /usr/local/lib/wrangler/node_modules/.bin || return 1' "$devops_profile" &&
   grep -Fq 'devops_de_append_path /usr/local/lib/aptly/bin || return 1' "$devops_profile" &&
   grep -Fq 'devops_de_append_path /usr/local/lib/osc/bin || return 1' "$devops_profile" &&
   grep -Fq 'devops_de_append_path /usr/local/lib/obs-build/bin || return 1' "$devops_profile" &&
   grep -Fq '"$build_root/$account_user/go/bin"' "$devops_late" &&
   grep -Fq '"$cache_root/$account_user/go-mod"' "$devops_late" &&
   grep -Fq 'obs_username=*' "$ROOT_DIR/d-i/forky/scripts/common/lib.sh" &&
   grep -Fq 'obs_username=*' "$ROOT_DIR/d-i/forky/scripts/firstboot/01-early.sh" &&
   ! grep -R -Fq -- "$forbidden_pool_root" "$ROOT_DIR/d-i/forky"; then
  pass "all 13 desktop profiles render account-local Aptly/R2 and Secret Service-backed OBS publication without a shared publication root"
else
  fail "all 13 desktop profiles render account-local Aptly/R2 and Secret Service-backed OBS publication without a shared publication root"
fi

if /bin/bash -n "$codex_wrapper" &&
   [ -r "$codex_archive_helper" ] &&
   python3 -m py_compile "$codex_archive_helper" &&
   [ -x "$codex_wrapper" ] &&
   [ -r "$codex_sysctl_template" ] &&
   [ -r "$codex_tmpfiles_template" ] &&
   grep -Fqx 'kernel.unprivileged_userns_clone=__INSTALLER_DEVOPS_CODEX_BWRAP_USERNS_CLONE__' "$codex_sysctl_template" &&
   grep -Fqx 'user.max_user_namespaces=__INSTALLER_DEVOPS_CODEX_BWRAP_MAX_USER_NAMESPACES__' "$codex_sysctl_template" &&
   grep -Fqx 'd __INSTALLER_DEVOPS_CODEX_ROOT__ 3770 root devops -' "$codex_tmpfiles_template" &&
   grep -Fqx 'd __INSTALLER_DEVOPS_CODEX_USER_ROOT__ 0750 __INSTALLER_ACCOUNT_USERNAME__ devops -' "$codex_tmpfiles_template" &&
   grep -Fqx 'd __INSTALLER_DEVOPS_CODEX_HOME__ 2770 __INSTALLER_ACCOUNT_USERNAME__ devops -' "$codex_tmpfiles_template" &&
   grep -Fqx 'd __INSTALLER_DEVOPS_CODEX_HOME__/memories 2770 __INSTALLER_ACCOUNT_USERNAME__ devops -' "$codex_tmpfiles_template" &&
   ! grep -Fq '__INSTALLER_DEVOPS_CODEX_USER_ROOT__/etc' "$codex_tmpfiles_template" &&
   ! grep -Eq '^(d|f|z|h|a) __INSTALLER_DEVOPS_CODEX_ROOT__/(share|lib).* root root ' "$codex_tmpfiles_template" &&
   grep -Fqx 'd __INSTALLER_DEVOPS_CODEX_LOG_DIR__ 2770 __INSTALLER_ACCOUNT_USERNAME__ devops -' "$codex_tmpfiles_template" &&
   grep -Fqx 'd /var/log/managed/openai/codex 2770 __INSTALLER_ACCOUNT_USERNAME__ devops -' "$codex_tmpfiles_template" &&
   grep -Fqx 'd __INSTALLER_DEVOPS_CODEX_SQLITE_HOME__ 2770 __INSTALLER_ACCOUNT_USERNAME__ devops -' "$codex_tmpfiles_template" &&
   grep -Fqx 'd __INSTALLER_DEVOPS_CODEX_RUNTIME_ROOT__ 2770 __INSTALLER_ACCOUNT_USERNAME__ devops -' "$codex_tmpfiles_template" &&
   grep -Fqx 'd __INSTALLER_DEVOPS_CODEX_RUNTIME_ROOT__/.control 0700 __INSTALLER_ACCOUNT_USERNAME__ devops -' "$codex_tmpfiles_template" &&
   grep -Fq 'devops_render_codex_sysctl()' "$devops_late" &&
   grep -Fq 'devops_render_codex_tmpfiles()' "$devops_late" &&
   grep -Fq 'devops_apply_codex_tmpfiles()' "$devops_late" &&
   grep -Fq '/usr/bin/systemd-tmpfiles' "$devops_late" &&
   grep -Fq 'Codex memories .git guard is not immutable' "$devops_late" &&
   grep -Fq 'codex_verify_stat "0:0:444" "$home_path/memories/.git"' "$devops_late" &&
   grep -Fq 'codex_verify_stat "${account_uid}:${devops_gid}:2770" "$host_log_dir"' "$devops_late" &&
   grep -Fq '"$devops_codex_host_log_dir"' "$devops_late" &&
   grep -Fq 'install -m 0444 -o root -g root /dev/null "$memories_path/.git"' "$devops_late" &&
   grep -Fq 'chattr +i -- "$memories_path/.git"' "$devops_late" &&
   grep -Fq 'chown -R root:root "$user_root/etc"' "$devops_late" &&
   grep -Fq 'codex_chmod_without_special_bits 0755 "$user_root/etc"' "$devops_late" &&
   grep -Fq 'Codex repository etc subtree is not fully root-owned' "$devops_late" &&
   grep -Fq 'cp -a -- "$user_root/etc/." "$config_staging/"' "$devops_late" &&
   grep -Fq 'mv -- "$config_staging" "$system_config_dir"' "$devops_late" &&
   grep -Fq 'chown root:devops "$codex_root"' "$devops_late" &&
   grep -Fq 'chmod 3770 "$codex_root"' "$devops_late" &&
   codex_tmpfiles_template_renders &&
   grep -Fq ': "${DEVOPS_CODEX_BWRAP_USERNS_CLONE:=1}"' "$devops_late" &&
   grep -Fq ': "${DEVOPS_CODEX_BWRAP_MAX_USER_NAMESPACES:=1024}"' "$devops_late" &&
   grep -Fq 'git -C "$repository_staging" fetch' "$devops_late" &&
   grep -Fq '"$repository_commit" ||' "$devops_late" &&
   grep -Fq 'installer_repo_join_var DIR_SCRIPTS_LATE codex-archive.py' "$devops_late" &&
   grep -Fq 'python3 "$archive_helper_path"' "$devops_late" &&
   grep -Fq -- '--maximum-extracted-bytes "$maximum_extracted_bytes"' "$devops_late" &&
   grep -Fq 'mv -- "$extracted_schema_path" "$schema_path"' "$devops_late" &&
   grep -Fq 'mv -- "$extracted_path" "$codex_root/share/bin/$binary_name"' "$devops_late" &&
   grep -Fq 'for extracted_path in "$extracted_binary_dir"/*; do' "$devops_late" &&
   ! grep -Fq 'DEVOPS_CODEX_ARCHIVE_BINARIES' "$devops_late" &&
   ! grep -Fq 'DEVOPS_CODEX_MAXIMUM_MEMBERS' "$devops_late" &&
   ! grep -Fq 'DEVOPS_CODEX_MAXIMUM_PAYLOAD_BYTES' "$devops_late" &&
   ! grep -Fq '0.147.0' "$devops_late" &&
   ! grep -Fq '1534ae4a224590784f1740b08ad34a2f70175fedafa134bc1977f6bc1e526c82' "$devops_late" &&
   ! grep -Fq 'github.com/mjcramerz/codex/releases' "$devops_late" &&
   ! grep -Fq 'tar --extract' "$devops_late" &&
   grep -Fq 'readonly CODEX_RAW_BINARY="/data/codex/share/bin/codex"' "$codex_wrapper" &&
   grep -Fq 'readonly CODEX_WRAPPER_DIRECTORY="/data/codex/lib"' "$codex_wrapper" &&
   grep -Fq 'readonly CODEX_RELEASE_BINARY_DIRECTORY="/data/codex/share/bin"' "$codex_wrapper" &&
   grep -Fq 'readonly CODEX_USER_ROOT="/data/codex/usr"' "$codex_wrapper" &&
   grep -Fq 'readonly CODEX_DEVOPS_GROUP="devops"' "$codex_wrapper" &&
   grep -Fq 'umask 077' "$codex_wrapper" &&
   grep -Fq 'managed DevOps profile must remain owned by the invoking account' "$codex_wrapper" &&
   grep -Fq 'codex_activate_devops_environment' "$codex_wrapper" &&
   grep -Fq 'declare -a CODEX_DEVOPS_ENV_NAMES=()' "$codex_wrapper" &&
   grep -Fq 'codex_collect_devops_environment' "$codex_wrapper" &&
   grep -Fq 'exec /usr/bin/env -0' "$codex_wrapper" &&
   grep -Fq 'codex_append_devops_environment' "$codex_wrapper" &&
   grep -Fq 'source "${profile_path}"' "$codex_wrapper" &&
   grep -Fq 'for env_name in "${CODEX_DEVOPS_ENV_NAMES[@]}"' "$codex_wrapper" &&
   ! grep -Fq 'codex_require_environment_value' "$codex_wrapper" &&
   ! grep -Fq 'codex_validate_devops_environment' "$codex_wrapper" &&
   ! grep -Eq '/usr/local/cuda|/usr/lib/llvm|/usr/local/lib/node|/usr/local/lib/rustup' "$codex_wrapper" &&
   ! grep -Fq '/tmp/codex-pycache' "$codex_wrapper" &&
   grep -Fq 'Codex Runtime:%s:/bin/zsh' "$codex_wrapper" &&
   grep -Fq -- '--setenv SHELL /bin/zsh' "$codex_wrapper" &&
   grep -Fq 'if [[ "${arg}" == "--no-bwrap" ]]' "$codex_wrapper" &&
   grep -Fq 'codex_require_account_owned_directory' "$codex_wrapper" &&
   grep -Fq '"Codex repository root"' "$codex_wrapper" &&
   grep -Fq 'the memories .git guard must remain root-owned with mode 0444' "$codex_wrapper" &&
   grep -Fq 'the memories .git guard must retain its immutable attribute' "$codex_wrapper" &&
   grep -Fq 'codex_require_user_namespace_support' "$codex_wrapper" &&
   grep -Fq -- '--unshare-user' "$codex_wrapper" &&
   grep -Fq -- '--unshare-cgroup' "$codex_wrapper" &&
   grep -Fq -- '--unshare-net' "$codex_wrapper" &&
   grep -Fq -- '--ro-bind /data /data' "$codex_wrapper" &&
   grep -Fq -- '--bind "${CODEX_POOL_ROOT}" "${CODEX_POOL_ROOT}"' "$codex_wrapper" &&
   grep -Fq -- '--ro-bind /sys /sys' "$codex_wrapper" &&
   grep -Fq 'codex_append_accelerator_device_binds' "$codex_wrapper" &&
   grep -Fq 'codex_require_account_owned_home_directory "HOME" "${HOME}"' "$codex_wrapper" &&
   ! grep -Fq 'codex_append_session_libvirt_socket_if_present' "$codex_wrapper" &&
   ! grep -Fq '    --tmpfs /var/lib/AccountsService' "$codex_wrapper" &&
   ! grep -Fq '    --tmpfs /etc/netplan' "$codex_wrapper" &&
   grep -Fq 'codex_append_required_ro_bind_to_existing_path' "$codex_wrapper" &&
   grep -Fq 'codex_append_tmpfs_parent_dirs "${resolved_destination}"' "$codex_wrapper" &&
   grep -Fq 'readlink -e -- "${destination_path}"' "$codex_wrapper" &&
   grep -Fq '"isolated resolver configuration"' "$codex_wrapper" &&
   grep -Fq 'Bubblewrap exited before network setup completed' "$codex_wrapper" &&
   grep -Fq '"${BWRAP_ARGS[@]}" <&0 >&1 2>&2 &' "$codex_wrapper" &&
   grep -Fq '/proc/cmdline' "$codex_wrapper" &&
   grep -Fq '/usr/bin/uname' "$codex_wrapper" &&
   grep -Fq -- '--disable-host-loopback' "$codex_wrapper" &&
   grep -Fq 'CODEX_MEMORY_GIT_GUARD' "$codex_wrapper" &&
   codex_class_defaults_accept_cached_profile; then
  pass "Codex imports the complete profile-owned DevOps environment without duplicating tool policy, keeps the user tree account-owned, and hides host identity surfaces"
else
  fail "Codex imports the complete profile-owned DevOps environment without duplicating tool policy, keeps the user tree account-owned, and hides host identity surfaces"
fi

if codex_installer_clears_inherited_special_bits; then
  pass "Codex installer clears unexpected set-ID bits while preserving required devops-group inheritance"
else
  fail "Codex installer clears unexpected set-ID bits while preserving required devops-group inheritance"
fi

if codex_wrapper_mount_helpers_work; then
  pass "Codex Bubblewrap masks only existing directories and resolves symlinked file destinations"
else
  fail "Codex Bubblewrap masks only existing directories and resolves symlinked file destinations"
fi

if codex_wrapper_path_boundaries_work; then
  pass "Codex accepts canonical account-owned HOME bind parents without imposing HOME permission modes or weakening path ownership and symlink checks"
else
  fail "Codex accepts canonical account-owned HOME bind parents without imposing HOME permission modes or weakening path ownership and symlink checks"
fi

if codex_wrapper_work_area_guards_work; then
  pass "Codex rejects missing, indirect, misowned, misgrouped, mis-moded, or unwritable system-managed work areas before direct or sandboxed launch"
else
  fail "Codex rejects missing, indirect, misowned, misgrouped, mis-moded, or unwritable system-managed work areas before direct or sandboxed launch"
fi

if codex_wrapper_generates_synthetic_installation_ids; then
  pass "Codex Bubblewrap generates a unique newline-free synthetic installation id per launch"
else
  fail "Codex Bubblewrap generates a unique newline-free synthetic installation id per launch"
fi

if [ -r "$codex_archive_helper" ] &&
   python3 -m py_compile "$codex_archive_helper" &&
   codex_archive_validator_rejects_unsafe_members; then
  pass "Codex archive validation dynamically extracts direct binaries and schema while rejecting unsafe fixtures"
else
  fail "Codex archive validation dynamically extracts direct binaries and schema while rejecting unsafe fixtures"
fi

if codex_wrapper_kernel_release_bounds_work; then
  pass "Codex synthetic kernel releases stay within the managed 6.7.0 through 7.1.5 bounds"
else
  fail "Codex synthetic kernel releases stay within the managed 6.7.0 through 7.1.5 bounds"
fi

if codex_wrapper_activates_managed_devops; then
  pass "Codex activates the exact managed DevOps environment and preserves read-write Downloads and Workspace plus the complete development configuration set"
else
  fail "Codex activates the exact managed DevOps environment and preserves read-write Downloads and Workspace plus the complete development configuration set"
fi

if codex_wrapper_persistent_state_guards_fail_closed; then
  pass "Codex validates devops-group-shared persistent state and never mutates malformed memories guard paths"
else
  fail "Codex validates devops-group-shared persistent state and never mutates malformed memories guard paths"
fi

if codex_chatgpt_devops_allowlists_match; then
  pass "Codex and ChatGPT share the complete development-only config allowlist without modeling Bazel as a managed application"
else
  fail "Codex and ChatGPT share the complete development-only config allowlist without modeling Bazel as a managed application"
fi

if codex_wrapper_mount_and_cleanup_contract_work; then
  pass "Codex mount order, privileged Bash startup, explicit bypass parsing, and failure cleanup remain fail-closed"
else
  fail "Codex mount order, privileged Bash startup, explicit bypass parsing, and failure cleanup remain fail-closed"
fi

if grep -Fqx 'd __INSTALLER_DEVOPS_CODEX_HOME__/sessions 2770 __INSTALLER_ACCOUNT_USERNAME__ devops -' "$codex_tmpfiles_template" &&
   grep -Fqx 'd __INSTALLER_DEVOPS_CODEX_HOME__/shell_snapshots 2770 __INSTALLER_ACCOUNT_USERNAME__ devops -' "$codex_tmpfiles_template" &&
   grep -Fqx 'd __INSTALLER_DEVOPS_CODEX_HOME__/archived_sessions 2770 __INSTALLER_ACCOUNT_USERNAME__ devops -' "$codex_tmpfiles_template" &&
   grep -Fqx 'f __INSTALLER_DEVOPS_CODEX_HOME__/history.jsonl 0660 __INSTALLER_ACCOUNT_USERNAME__ devops -' "$codex_tmpfiles_template" &&
   grep -Fqx 'f __INSTALLER_DEVOPS_CODEX_HOME__/session_index.jsonl 0660 __INSTALLER_ACCOUNT_USERNAME__ devops -' "$codex_tmpfiles_template" &&
   grep -Fqx 'f __INSTALLER_DEVOPS_CODEX_HOME__/external_agent_session_imports.json 0660 __INSTALLER_ACCOUNT_USERNAME__ devops -' "$codex_tmpfiles_template" &&
   ! grep -Fq '__INSTALLER_DEVOPS_CODEX_RUNTIME_ROOT__/runs' "$codex_tmpfiles_template" &&
   [ "$(grep -Fc -- '--bind "${CODEX_RUNTIME_HOME}" "${CODEX_RUNTIME_HOME}"' "$codex_wrapper")" -eq 1 ] &&
   ! grep -Fq -- '--bind "${CODEX_RUNTIME_HOME}/sessions" "${CODEX_RUNTIME_HOME}/sessions"' "$codex_wrapper" &&
   ! grep -Fq -- '--bind "${CODEX_RUNTIME_HOME}/history.jsonl" "${CODEX_RUNTIME_HOME}/history.jsonl"' "$codex_wrapper" &&
   ! grep -Fq -- '--bind "${CODEX_RUNTIME_HOME}/session_index.jsonl" "${CODEX_RUNTIME_HOME}/session_index.jsonl"' "$codex_wrapper" &&
   grep -Fq 'installation_id=$(codex_generate_uuid)' "$codex_wrapper" &&
   grep -Fq 'printf '\''%s'\'' "${installation_id}" >"${CODEX_CONTROL_DIR}/installation_id"' "$codex_wrapper" &&
   grep -Fq 'chmod 0644 -- "${CODEX_CONTROL_DIR}/installation_id"' "$codex_wrapper" &&
   grep -Fq -- '--bind "${CODEX_CONTROL_DIR}/installation_id" "${CODEX_RUNTIME_HOME}/installation_id"' "$codex_wrapper" &&
   ! grep -Fq 'installation_id_fd' "$codex_wrapper" &&
   ! grep -Fq -- '--ro-bind-data' "$codex_wrapper" &&
   grep -Fq -- '--bind "${CODEX_SQLITE_ROOT}" "${CODEX_SQLITE_ROOT}"' "$codex_wrapper" &&
   ! grep -Fq '__INSTALLER_DEVOPS_CODEX_HOME__/installation_id' "$codex_tmpfiles_template" &&
   ! grep -Fq 'CODEX_RUNS_ROOT' "$codex_wrapper" &&
   ! grep -Fq 'CODEX_SELECTED_RUN_ROOT' "$codex_wrapper" &&
   ! grep -Fq 'codex_find_resume_run_key' "$codex_wrapper" &&
   ! grep -Fq 'no isolated Codex session is available to resume' "$codex_wrapper"; then
  pass "Codex Bubblewrap preserves native resume state and mounts a per-launch synthetic installation id"
else
  fail "Codex Bubblewrap preserves native resume state and mounts a per-launch synthetic installation id"
fi

if [ -r "$mise_config" ] &&
   [ -r "$mise_fragment" ] &&
   [ -r "$cargo_config_template" ] &&
   [ ! -e "$cargo_config_static" ] &&
   cargo_template_renders &&
   grep -Fq 'node = "26"' "$mise_config" &&
   ! grep -Eq 'mise use[[:space:]].*llvm' "$mise_config" &&
   ! grep -Eq 'mise use[[:space:]].*bazel' "$mise_config" &&
   ! grep -Eq 'prelinked Node and LLVM|Mise.*LLVM.*version' "$mise_fragment" &&
   grep -Fq 'Mise is intentionally **Node-only**' "$devops_readme" &&
   ! grep -Eq 'mise use[[:space:]].*(llvm|bazel)' "$devops_readme" &&
   python3 - "$mise_config" "$mise_fragment" <<'PY'
from pathlib import Path
import sys
import tomllib

mise = tomllib.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
assert mise["tools"] == {"node": "26"}

mise_fragment = tomllib.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
assert mise_fragment == {}
PY
then
  pass "Mise sources and the rendered Cargo template are valid TOML with profile-owned build and linker flags"
else
  fail "Mise sources and the rendered Cargo template are valid TOML with profile-owned build and linker flags"
fi

if /bin/sh -n "$devops_profile" &&
   bash -n "$devops_profile" &&
   zsh -n "$devops_profile" &&
   devops_invalid_runtime_fails_before_mutation "$devops_profile" &&
   grep -Fq 'devops_de_deactivate() {' "$devops_profile" &&
   grep -Fq 'devops_de_set_terminal_title() {' "$devops_profile" &&
   grep -Fq 'devops_de_enable_zsh_terminal_title() {' "$devops_profile" &&
   grep -Fq 'add-zsh-hook precmd devops_de_set_terminal_title || return 1' "$devops_profile" &&
   grep -Fq 'add-zsh-hook preexec devops_de_set_terminal_title || return 1' "$devops_profile" &&
   grep -Fq 'devops_de_enable_zsh_terminal_title' "$devops_profile" &&
   grep -Fq 'devops_de_account_owned_directory_is_mode() (' "$devops_profile" &&
   grep -Fq 'devops_de_validate_runtime_directory() (' "$devops_profile" &&
   grep -Fq 'devops_de_ensure_private_runtime_directory() (' "$devops_profile" &&
   grep -Fq 'devops_de_activate() (' "$devops_profile" &&
   ! grep -Fq 'devops_de_start_virtualization_services' "$devops_profile" &&
   grep -Fq 'DEVOPS_DE_ACTIVE=1' "$devops_profile" &&
   grep -Fq 'XDG_CONFIG_HOME="${HOME}/.config"' "$devops_profile" &&
   grep -Fq 'export XDG_CONFIG_HOME' "$devops_profile" &&
   grep -Fq 'export PYTHONPYCACHEPREFIX="${devops_de_python_runtime_root}/pycache"' "$devops_profile" &&
   grep -Fq 'export PYTHONUSERBASE="${devops_de_build_home}/python"' "$devops_profile" &&
   grep -Fq 'export PYTHON_HISTORY="${devops_de_db_home}/python/history"' "$devops_profile" &&
   grep -Fq 'export PYTHONSAFEPATH=1' "$devops_profile" &&
   grep -Fq 'export PYTHONUTF8=1' "$devops_profile" &&
   grep -Fq 'export PYTHONWARNDEFAULTENCODING=1' "$devops_profile" &&
   devops_profile_unsets_variables \
     "$devops_profile" \
     DEVOPS_DE_COMPLETIONS_ENABLED \
     PYTHONDONTWRITEBYTECODE \
     PYTHONHASHSEED \
     PYTHONHOME \
     PYTHONINSPECT \
     PYTHONOPTIMIZE \
     PYTHONPATH \
     PYTHONSTARTUP \
     PYTHONWARNINGS \
     DENO_DIR \
     DENO_INSTALL_ROOT \
     DENO_REPL_HISTORY \
     DENO_NO_UPDATE_CHECK \
     DEVOPS_DATABASE_HOME \
     PGDATA \
     PGSERVICEFILE \
     PGPASSFILE \
     PSQL_HISTORY \
     MYSQL_HOME \
     MYSQL_HISTFILE \
     MYSQLSH_USER_CONFIG_HOME \
     SQLITE_HISTORY \
     DUCKDB_HISTORY \
     REDISCLI_HISTFILE \
     USQL_CONFIG_FILE \
     QOREDB_CONFIG_DIR \
     VIRTUAL_ENV \
     VIRTUAL_ENV_PROMPT &&
   grep -Fq 'export PIP_CACHE_DIR="${devops_de_cache_home}/pip"' "$devops_profile" &&
   grep -Fq 'export UV_CACHE_DIR="${devops_de_cache_home}/uv"' "$devops_profile" &&
   grep -Fq 'export UV_TOOL_DIR="${devops_de_db_home}/uv/tools"' "$devops_profile" &&
   grep -Fq 'export UV_TOOL_BIN_DIR="${devops_de_build_home}/uv/bin"' "$devops_profile" &&
   grep -Fq 'devops_de_account_owned_directory_is_mode "$devops_de_db_home" 2770' "$devops_profile" &&
   grep -Fq 'export DEVOPS_DATABASE_HOME="$devops_de_db_home"' "$devops_profile" &&
   grep -Fq 'export PGDATA="$devops_de_db_home/postgresql/data"' "$devops_profile" &&
   grep -Fq 'export PGSERVICEFILE="$devops_de_db_home/postgresql/pg_service.conf"' "$devops_profile" &&
   grep -Fq 'export PGPASSFILE="$devops_de_db_home/postgresql/pgpass"' "$devops_profile" &&
   grep -Fq 'export PSQL_HISTORY="$devops_de_db_home/postgresql/psql_history"' "$devops_profile" &&
   grep -Fq 'export MYSQL_HOME="$devops_de_db_home/mysql/config"' "$devops_profile" &&
   grep -Fq 'export MYSQL_HISTFILE="$devops_de_db_home/mysql/history"' "$devops_profile" &&
   grep -Fq 'export MYSQLSH_USER_CONFIG_HOME="$devops_de_db_home/mysql-shell"' "$devops_profile" &&
   grep -Fq 'export SQLITE_HISTORY="$devops_de_db_home/sqlite/history"' "$devops_profile" &&
   grep -Fq 'export DUCKDB_HISTORY="$devops_de_db_home/duckdb/history"' "$devops_profile" &&
   grep -Fq 'export REDISCLI_HISTFILE="$devops_de_db_home/redis-compatible/history"' "$devops_profile" &&
   grep -Fq 'export USQL_CONFIG_FILE="$devops_de_db_home/usql/config.yaml"' "$devops_profile" &&
   grep -Fq 'export QOREDB_CONFIG_DIR="$devops_de_db_home/qoredb/config"' "$devops_profile" &&
   grep -Fq 'export GRIDLINE_DATA_HOME="$devops_de_db_home/gridline"' "$devops_profile" &&
   grep -Fq 'PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin' "$devops_profile" &&
   grep -Fq 'devops_de_account_owned_directory_is_mode "$XDG_RUNTIME_DIR" 700' "$devops_profile" &&
   grep -Fq 'devops_de_expected_runtime_dir="/run/user/${devops_de_runtime_uid}"' "$devops_profile" &&
   [ "$(grep -Fc 'devops_de_validate_runtime_directory || return 1' "$devops_profile")" -eq 2 ] &&
   grep -Fq 'devops_de_ensure_private_runtime_directory "$devops_de_python_runtime_root"' "$devops_profile" &&
   grep -Fq 'export ANSIBLE_HOME="${devops_de_db_home}/ansible"' "$devops_profile" &&
   grep -Fq 'export ANSIBLE_GALAXY_CACHE_DIR="${devops_de_cache_home}/ansible/galaxy"' "$devops_profile" &&
   grep -Fq 'export ANSIBLE_LOCAL_TEMP="${devops_de_ansible_runtime_root}/tmp"' "$devops_profile" &&
   grep -Fq 'export ANSIBLE_PERSISTENT_CONTROL_PATH_DIR="${devops_de_ansible_runtime_root}/pc"' "$devops_profile" &&
   grep -Fq 'export ANSIBLE_SSH_CONTROL_PATH_DIR="${devops_de_ansible_runtime_root}/ssh"' "$devops_profile" &&
   grep -Fq 'export TF_PLUGIN_CACHE_DIR="${devops_de_hashicorp_cache_root}/terraform/plugin-cache"' "$devops_profile" &&
   grep -Fq 'export PACKER_CONFIG_DIR="${devops_de_hashicorp_cache_root}/packer.d"' "$devops_profile" &&
   grep -Fq 'export PACKER_CONFIG_PATH="${PACKER_CONFIG_DIR}/config.json"' "$devops_profile" &&
   grep -Fq 'export PACKER_CONFIG="$PACKER_CONFIG_PATH"' "$devops_profile" &&
   grep -Fq 'export PACKER_PLUGIN_PATH="${PACKER_CONFIG_DIR}/plugins"' "$devops_profile" &&
   grep -Fq 'devops_de_push_terminal_title() {' "$devops_profile" &&
   grep -Fq "printf '\\033[22;0t'" "$devops_profile" &&
   grep -Fq 'devops_de_restore_terminal_title() {' "$devops_profile" &&
   grep -Fq "printf '\\033[23;0t'" "$devops_profile" &&
   grep -Fq 'devops_de_restore_terminal_title_once() {' "$devops_profile" &&
   grep -Fq 'trap '\''devops_de_restore_terminal_title_once'\'' 0' "$devops_profile" &&
   grep -Fq '"$devops_de_shell" -i' "$devops_profile" &&
   grep -Fq 'Entering DevOps environment; run devops or exit to return' "$devops_profile" &&
   grep -Fq "    '') devops_de_activate ;;" "$devops_profile" &&
   ! grep -Eq 'handoff|labwc-terminal|WAYLAND_DISPLAY|devops_de_terminal_pid|devops_de_wait_attempt' "$devops_profile" &&
   grep -Fq 'devops: invalid DevOps activation marker' "$devops_profile" &&
   ! grep -Fq '/usr/share/nodejs/corepack/dist/corepack.js' "$devops_profile" &&
   grep -Fq '[ -x /usr/local/lib/rustup/bin/rustup-init ]' "$devops_profile" &&
   ! grep -Fq 'devops_de_read_rustup_toolchain' "$devops_profile" &&
   ! grep -Fq '/etc/devops/toolchain.conf' "$devops_profile" &&
   grep -Fq 'RUSTUP_TOOLCHAIN=nightly' "$devops_profile" &&
   grep -Fq 'export RUSTUP_TOOLCHAIN' "$devops_profile" &&
   grep -Fq 'devops_de_prepend_path /usr/local/lib/rustup/bin || return 1' "$devops_profile" &&
   grep -Fq 'export MISE_DATA_DIR="${devops_de_db_home}/mise/data"' "$devops_profile" &&
   grep -Fq 'export MISE_TMP_DIR="${devops_de_cache_home}/mise/tmp"' "$devops_profile" &&
   grep -Fq 'export CARGO_HOME="${devops_de_cache_home}/cargo"' "$devops_profile" &&
   grep -Fq 'export RUSTUP_HOME="${devops_de_db_home}/rustup"' "$devops_profile" &&
   grep -Fq 'export SCCACHE_DIR="${devops_de_cache_home}/sccache"' "$devops_profile" &&
   grep -Fq 'export BAZELISK_HOME="${devops_de_db_home}/bazelisk"' "$devops_profile" &&
   grep -Fq 'export PNPM_CONFIG_STORE_DIR="${devops_de_cache_home}/pnpm/store"' "$devops_profile" &&
   grep -Fq 'export PNPM_CONFIG_CACHE_DIR="${devops_de_cache_home}/pnpm/cache"' "$devops_profile" &&
   grep -Fq 'export PNPM_CONFIG_STATE_DIR="${devops_de_db_home}/pnpm/state"' "$devops_profile" &&
   grep -Fq 'export YARN_ENABLE_GLOBAL_CACHE=false' "$devops_profile" &&
   grep -Fq 'devops_de_prepend_path /usr/lib/llvm-24/bin' "$devops_profile" &&
   grep -Fq 'if [ -d /usr/local/cuda-12.8/bin ]; then' "$devops_profile" &&
   grep -Fq 'devops_de_prepend_path /usr/local/cuda-12.8/bin || return 1' "$devops_profile" &&
   grep -Fq 'if [ -d /usr/local/cuda-12.9/bin ]; then' "$devops_profile" &&
   grep -Fq 'devops_de_prepend_path /usr/local/cuda-12.9/bin || return 1' "$devops_profile" &&
   grep -Fq 'if [ -d /usr/local/cuda-13.1/bin ]; then' "$devops_profile" &&
   grep -Fq 'devops_de_prepend_path /usr/local/cuda-13.1/bin || return 1' "$devops_profile" &&
   grep -Fq 'devops_de_prepend_path /usr/local/lib/node-26/bin || return 1' "$devops_profile" &&
   grep -Fq 'devops_de_prepend_path "${MISE_DATA_DIR}/shims" || return 1' "$devops_profile" &&
   grep -Fq 'devops_de_append_path /usr/local/lib/ansible/bin || return 1' "$devops_profile" &&
   grep -Fq 'export DENO_DIR="${devops_de_cache_home}/deno"' "$devops_profile" &&
   grep -Fq 'export DENO_INSTALL_ROOT="${devops_de_build_home}/deno"' "$devops_profile" &&
   grep -Fq 'export DENO_REPL_HISTORY="${devops_de_db_home}/deno/repl_history"' "$devops_profile" &&
   grep -Fq 'export DENO_NO_UPDATE_CHECK=1' "$devops_profile" &&
   grep -Fq 'devops_de_append_path /usr/local/lib/deno/bin || return 1' "$devops_profile" &&
   grep -Fq 'devops_de_append_path "${DENO_INSTALL_ROOT}/bin" || return 1' "$devops_profile" &&
   grep -Fq 'devops_de_append_path /usr/local/lib/yt-dlp/bin || return 1' "$devops_profile" &&
   grep -Fq 'devops_de_append_path /usr/local/lib/hashicorp/terraform/bin || return 1' "$devops_profile" &&
   grep -Fq 'devops_de_append_path /usr/local/lib/hashicorp/packer/bin || return 1' "$devops_profile" &&
   grep -Fq 'devops_de_enable_shell_completions() {' "$devops_profile" &&
   grep -Fq -- '-C /usr/local/lib/hashicorp/terraform/bin/terraform' "$devops_profile" &&
   grep -Fq -- '-C /usr/local/lib/hashicorp/packer/bin/packer' "$devops_profile" &&
   ! grep -Fq 'devops_de_mise_node_exec' "$devops_profile" &&
   ! grep -Fq 'devops_de_corepack_exec' "$devops_profile" &&
   grep -Fq '[ -x /usr/local/lib/bazelisk/bazel ]' "$devops_profile" &&
   ! grep -Fq 'DEVOPS_DE_VAGRANT_ENABLED=' "$devops_profile" &&
   ! grep -Eqi 'virtops|libvirt|vagrant|virsh|incusops|incusui' "$devops_profile" &&
   grep -Fq 'bazel() {' "$devops_profile" &&
   grep -Fq 'command /usr/local/lib/bazelisk/bazel' "$devops_profile" &&
   grep -Fq '"--bazelrc=${XDG_CONFIG_HOME:-${HOME}/.config}/bazel/bazelrc"' "$devops_profile" &&
   ! grep -Fq '/usr/local/bin/bazel' "$devops_profile" &&
   ! grep -Fq 'devops_de_prepend_path /usr/local/lib/bazelisk' "$devops_profile" &&
   grep -Fq 'devops_de_append_path /data/codex/lib || return 1' "$devops_profile" &&
   ! grep -Fq 'devops_de_append_path /data/codex/share/bin' "$devops_profile" &&
   grep -Fq '[ -x /data/llama/lib/llama ]' "$devops_profile" &&
   grep -Fq 'devops_de_append_path /data/llama/lib || return 1' "$devops_profile" &&
   grep -Fq '[ -d /data/llama/bin ]' "$devops_profile" &&
   grep -Fq 'devops_de_append_path /data/llama/bin || return 1' "$devops_profile" &&
   ! grep -Eq 'LLAMA_|/etc/llama|llama-server|DEFAULT_MODEL|MODEL_DIR' "$devops_profile" &&
   ! grep -Eq 'mise exec.*(clang|llvm|lld|bazel)' "$devops_profile" &&
   ! grep -Fq 'eval "$(mise activate' "$devops_profile"; then
  pass "desktop DevOps profile is opt-in, enters a same-terminal nested shell without IPC, keeps state on /pool, contains no virtualization activation, and exports fixed nightly Rustup state"
else
  fail "desktop DevOps profile is opt-in, enters a same-terminal nested shell without IPC, keeps state on /pool, contains no virtualization activation, and exports fixed nightly Rustup state"
fi

if bash -n "$devops_bashrc" &&
   zsh -n "$devops_zshrc" &&
   grep -Fq 'bashrc_init_devops_completions() {' "$devops_bashrc" &&
   grep -Fq 'declare -F devops_de_enable_shell_completions' "$devops_bashrc" &&
   grep -Fq 'zshrc_init_devops_completions() {' "$devops_zshrc" &&
   grep -Fq 'functions[devops_de_enable_shell_completions]' "$devops_zshrc" &&
   devops_rc_completion_order_is_valid "$devops_bashrc" "$devops_zshrc" &&
   devops_shell_completions_work "$devops_profile" "$devops_bashrc" "$devops_zshrc"; then
  pass "Bash and Zsh invoke class-gated DevOps completion registration after their completion frameworks load"
else
  fail "Bash and Zsh invoke class-gated DevOps completion registration after their completion frameworks load"
fi

if [ -r "$packer_template" ] &&
   grep -Fqx '  required_version = "= __INSTALLER_DEVOPS_PACKER_VERSION__"' "$packer_template" &&
   [ "$(grep -c '^      source  = "github.com/hashicorp/' "$packer_template")" -eq 7 ] &&
   grep -Fqx '      source  = "github.com/hashicorp/qemu"' "$packer_template" &&
   grep -Fqx '      version = "= 1.1.6"' "$packer_template" &&
   grep -Fqx '      source  = "github.com/hashicorp/ansible"' "$packer_template" &&
   grep -Fqx '      source  = "github.com/hashicorp/amazon"' "$packer_template" &&
   grep -Fqx '      source  = "github.com/hashicorp/azure"' "$packer_template" &&
   grep -Fqx '      source  = "github.com/hashicorp/docker"' "$packer_template" &&
   grep -Fqx '      source  = "github.com/hashicorp/googlecompute"' "$packer_template" &&
   grep -Fqx '      source  = "github.com/hashicorp/proxmox"' "$packer_template"; then
  pass "managed Packer template pins QEMU, Ansible, Docker, AWS, Azure, GCP, and Proxmox plugins"
else
  fail "managed Packer template pins QEMU, Ansible, Docker, AWS, Azure, GCP, and Proxmox plugins"
fi

if /bin/sh -n "$devops_late" &&
   grep -Fq 'devops_install_pinned_node_runtimes()' "$devops_late" &&
   grep -Fq 'run_in_target "download and install pinned Node runtimes for Mise" /bin/sh -eu -c' "$devops_late" &&
   grep -Fq 'printf "%s\n" "$release_version" |' "$devops_late" &&
   ! grep -Fq 'printf '\''%s\n'\'' "$release_version" |' "$devops_late" &&
   grep -Fq 'install_dir=$8' "$devops_late" &&
   grep -Fq '"$DEVOPS_NODE_22_URL"' "$devops_late" &&
   grep -Fq '"$DEVOPS_NODE_24_URL"' "$devops_late" &&
   grep -Fq '"$DEVOPS_NODE_26_URL"' "$devops_late" &&
   grep -Fq '"$DEVOPS_NODE_22_SHA256"' "$devops_late" &&
   grep -Fq '"$DEVOPS_NODE_24_SHA256"' "$devops_late" &&
   grep -Fq '"$DEVOPS_NODE_26_SHA256"' "$devops_late" &&
   grep -Fq -- '--proto "=https"' "$devops_late" &&
   grep -Fq -- '--max-filesize "$expected_bytes"' "$devops_late" &&
   grep -Fq 'archive_bytes=$(wc -c <"$archive_path" | tr -d "[[:space:]]")' "$devops_late" &&
   grep -Fq 'downloaded Node archive size does not match the profile policy' "$devops_late" &&
   grep -Fq 'Node archive exceeds the configured expanded-byte ceiling' "$devops_late" &&
   grep -Fq 'node_validate_archive' "$devops_late" &&
   grep -Fq 'node_enable_corepack()' "$devops_late" &&
   grep -Fq 'enable --install-directory "$node_bin_dir"' "$devops_late" &&
   grep -Fq 'Node 24 bundled Corepack is unavailable for Node 26 compatibility' "$devops_late" &&
   grep -Fq 'node_enable_corepack "$1" "$8"' "$devops_late" &&
   grep -Fq 'node_enable_corepack "${10}" "${17}"' "$devops_late" &&
   grep -Fq 'node_enable_corepack "${19}" "${26}" "${17}"' "$devops_late" &&
   grep -Fq 'awk chown curl find install ln mktemp mv rmdir sha256sum tar tr wc xz' "$devops_late" &&
   grep -Fq 'Node archive SHA-256 mismatch' "$devops_late" &&
   [ ! -e "$node_target_helper" ]; then
  pass "late DevOps downloads, validates, and installs Node 22, 24, and 26 with Corepack shims without a target helper"
else
  fail "late DevOps downloads, validates, and installs Node 22, 24, and 26 with Corepack shims without a target helper"
fi

if python3 - \
  "$devops_tools" \
  "$devops_late" \
  "$ROOT_DIR/d-i/forky/hosts/profiles/override/btrfs-de-main.env" \
  "$TMP_DIR" \
  "$ROOT_DIR" \
  $desktop_profiles <<'PY'
import dataclasses
import importlib.util
import json
import pathlib
import re
import shlex
import stat
import subprocess
import sys
import tarfile
import zipfile

source = pathlib.Path(sys.argv[1])
late_source = pathlib.Path(sys.argv[2])
profile_source = pathlib.Path(sys.argv[3])
temp_root = pathlib.Path(sys.argv[4]) / "devops-tools-policy"
repo_root = pathlib.Path(sys.argv[5]).resolve()
desktop_profile_paths = tuple(repo_root / item for item in sys.argv[6:])
temp_root.mkdir(mode=0o700)
spec = importlib.util.spec_from_file_location("managed_devops_tools_test", source)
assert spec is not None and spec.loader is not None
module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = module
spec.loader.exec_module(module)

assert len(desktop_profile_paths) == 13
begin_marker = b"# BEGIN: managed upstream DevOps tool policy"
end_marker = b"# END: managed upstream DevOps tool policy"
managed_blocks = []
for desktop_profile_path in desktop_profile_paths:
    profile_bytes = desktop_profile_path.read_bytes()
    assert profile_bytes.count(begin_marker) == 1, desktop_profile_path
    assert profile_bytes.count(end_marker) == 1, desktop_profile_path
    block_start = profile_bytes.index(begin_marker)
    block_end = profile_bytes.index(end_marker, block_start) + len(end_marker)
    managed_blocks.append(profile_bytes[block_start:block_end])
    profile_names = re.findall(rb"(?m)^([A-Z][A-Z0-9_]*)=", profile_bytes)
    assert len(profile_names) == len(set(profile_names)), desktop_profile_path
assert len(set(managed_blocks)) == 1
managed_names = re.findall(rb"(?m)^([A-Z0-9_]+)=", managed_blocks[0])
assert len(managed_names) == 165
assert len(managed_names) == len(set(managed_names))
assert b"DEVOPS_RUSTUP_TOOLCHAIN=" in managed_blocks[0]

desktop_profile_set = {path.resolve() for path in desktop_profile_paths}
for profile_path in (repo_root / "d-i/forky/hosts/profiles").rglob("*.env"):
    if profile_path.resolve() not in desktop_profile_set:
        assert begin_marker not in profile_path.read_bytes(), profile_path

profile_values = {}
for line in profile_source.read_text(encoding="utf-8").splitlines():
    match = re.fullmatch(r"(DEVOPS_[A-Z0-9_]+)=(.*)", line)
    if match is None:
        continue
    parsed = shlex.split(match.group(2), posix=True)
    assert len(parsed) == 1, line
    profile_values[match.group(1)] = parsed[0]
values = {key: profile_values[key] for key in module.POLICY_KEYS}
assert set(values) == module.POLICY_KEYS
assert len(values) == 110
assert values["DEVOPS_UPSTREAM_POLICY_SCHEMA"] == "4"
assert profile_values["DEVOPS_DOTSLASH_SOURCE_BUILD"] == "0"
assert profile_values["DEVOPS_DOTSLASH_URL"] == (
    "https://github.com/facebook/dotslash/releases/download/v0.5.9/"
    "dotslash-linux-musl.x86_64.v0.5.9.tar.gz"
)
assert profile_values["DEVOPS_DOTSLASH_SHA256"] == (
    "4c75c6eb7890ae35993b962073f6d9bbe78b42b81a5691303ad70f63bfbf7196"
)
assert profile_values["DEVOPS_DOTSLASH_BYTES"] == "842816"
assert profile_values["DEVOPS_DOTSLASH_ARCHITECTURE"] == "linux-musl.x86_64"
assert profile_values["DEVOPS_DOTSLASH_ARCHIVE_FILENAME"] == (
    "dotslash-linux-musl.x86_64.v0.5.9.tar.gz"
)
assert profile_values["DEVOPS_DOTSLASH_ARCHIVE_FILES"] == "dotslash"
assert profile_values["DEVOPS_UV_SOURCE_BUILD"] == "0"
assert profile_values["DEVOPS_UV_URL"] == (
    "https://github.com/astral-sh/uv/releases/download/0.12.0/"
    "uv-x86_64-unknown-linux-gnu.tar.gz"
)
assert profile_values["DEVOPS_UV_SHA256"] == (
    "eaf842262aa1c418d8ecc5605f02ee1ebfd369124fa48548e85f9481a47831a9"
)
assert profile_values["DEVOPS_UV_BYTES"] == "21373358"
assert profile_values["DEVOPS_UV_ARCHITECTURE"] == "x86_64-unknown-linux-gnu"
assert profile_values["DEVOPS_UV_ARCHIVE_FILENAME"] == (
    "uv-x86_64-unknown-linux-gnu.tar.gz"
)
assert profile_values["DEVOPS_UV_ARCHIVE_ROOT"] == "uv-x86_64-unknown-linux-gnu"
assert profile_values["DEVOPS_UV_ARCHIVE_FILES"] == "uv uvx"

policy_path = temp_root / "policy.json"
policy_path.write_text(json.dumps(values, sort_keys=True) + "\n", encoding="utf-8")
policy_path.chmod(0o600)
policy = module.load_policy(policy_path)
wrangler_root = temp_root / "wrangler-entrypoint"
wrangler_entrypoint = (
    wrangler_root
    / "node_modules"
    / policy.wrangler_package_name
    / "bin"
    / "wrangler.js"
)
wrangler_entrypoint.parent.mkdir(mode=0o755, parents=True)
wrangler_entrypoint.write_text("#!/usr/bin/env node\n", encoding="utf-8")
wrangler_entrypoint.chmod(0o644)
wrangler_binary = wrangler_root / "node_modules" / ".bin" / "wrangler"
wrangler_binary.parent.mkdir(mode=0o755)
wrangler_binary.symlink_to("../wrangler/bin/wrangler.js")
module.ensure_wrangler_command_executable(policy, wrangler_root)
assert stat.S_IMODE(wrangler_entrypoint.stat().st_mode) == 0o755
wrangler_binary.unlink()
wrangler_escape = temp_root / "wrangler-escape"
wrangler_escape.write_text("#!/usr/bin/env node\n", encoding="utf-8")
wrangler_escape.chmod(0o755)
wrangler_binary.symlink_to(wrangler_escape)
try:
    module.ensure_wrangler_command_executable(policy, wrangler_root)
except module.ToolInstallError:
    pass
else:
    raise AssertionError("escaping Wrangler command entrypoint was accepted")
node_archive_member_counts = {
    "v22.23.2": 5866,
    "v24.19.0": 5779,
    "v26.7.0": 5828,
}
assert profile_values["DEVOPS_NODE_22_VERSION"] in node_archive_member_counts
assert profile_values["DEVOPS_NODE_24_VERSION"] in node_archive_member_counts
assert profile_values["DEVOPS_NODE_26_VERSION"] in node_archive_member_counts
assert policy.max_archive_members == 8192
assert policy.max_archive_members >= max(node_archive_member_counts.values())
assert policy.max_archive_members <= 100_000
assert [artifact.key for artifact in policy.artifacts] == [
    "deno",
    "yt-dlp",
    "ansible-core",
    "opentofu",
    "terraform",
    "packer",
    "wrangler",
    "aptly",
    "osc",
    "obs-build",
]
assert [artifact.key for artifact in policy.download_artifacts] == [
    "deno",
    "yt-dlp",
    "ansible-core",
    "opentofu",
    "terraform",
    "packer",
    "wrangler",
    "aptly",
    "osc",
    "obs-build",
]
assert policy.deno.version == "2.9.6"
assert policy.yt_dlp.version == "2026.08.19"
assert policy.ansible_core.version == "2.21.3"
assert values["DEVOPS_ANSIBLE_CORE_SHA256"] == (
    "9e7dd367f7dc5d5e9fc5ae1baf8af9c4edc09e916a73a40108a3f32e3ad93f10"
)
assert values["DEVOPS_ANSIBLE_CORE_BYTES"] == "2446988"
assert policy.ansible_core.architecture == values["DEVOPS_ANSIBLE_CORE_ARCHITECTURE"]
assert str(policy.ansible_core.install_root) == values["DEVOPS_ANSIBLE_CORE_INSTALL_ROOT"]
assert str(policy.ansible_core.binary_path) == values["DEVOPS_ANSIBLE_CORE_BINARY_PATH"]
assert policy.opentofu.version == values["DEVOPS_OPENTOFU_VERSION"]
assert policy.terraform.version == values["DEVOPS_TERRAFORM_VERSION"]
assert policy.packer.version == values["DEVOPS_PACKER_VERSION"]
assert policy.wrangler.version == values["DEVOPS_WRANGLER_VERSION"]
assert policy.aptly.version == values["DEVOPS_APTLY_RELEASE_VERSION"]
assert policy.osc.version == values["DEVOPS_OSC_RELEASE_VERSION"]
assert policy.obs_build.version == values["DEVOPS_OBS_BUILD_TAG"]
assert all(str(item.install_root).startswith("/usr/local/lib/") for item in policy.artifacts)

def assert_policy_rejected(label, candidate, *, mode=0o600):
    bad_policy = temp_root / f"bad-{label}.json"
    bad_policy.write_text(json.dumps(candidate) + "\n", encoding="utf-8")
    bad_policy.chmod(mode)
    try:
        module.load_policy(bad_policy)
    except module.ToolInstallError:
        return
    raise AssertionError(f"invalid policy was accepted: {label}")


bad_values = dict(values)
bad_values["DEVOPS_OPENTOFU_URL"] = "https://example.invalid/release.zip"
assert_policy_rejected("url", bad_values)

bad_values = dict(values)
bad_values["DEVOPS_DENO_URL"] = "https://example.invalid/deno.zip"
assert_policy_rejected("deno-url", bad_values)

bad_values = dict(values)
bad_values["DEVOPS_DENO_VERSION"] = "2.2.9"
bad_values["DEVOPS_DENO_URL"] = (
    "https://github.com/denoland/deno/releases/download/v2.2.9/"
    "deno-x86_64-unknown-linux-gnu.zip"
)
assert_policy_rejected("deno-ejs-minimum", bad_values)

bad_values = dict(values)
bad_values["DEVOPS_YT_DLP_PAYLOAD_PATH"] = "/usr/local/lib/yt-dlp/../yt-dlp"
assert_policy_rejected("yt-dlp-payload", bad_values)

bad_values = dict(values)
bad_values["DEVOPS_OPENTOFU_SHA256"] = "g" * 64
assert_policy_rejected("digest", bad_values)

bad_values = dict(values)
bad_values["DEVOPS_ANSIBLE_CORE_URL"] = "https://example.invalid/ansible-core.whl"
assert_policy_rejected("ansible-core-url", bad_values)

bad_values = dict(values)
bad_values["DEVOPS_TERRAFORM_INSTALL_ROOT"] = "/usr/local/lib/terraform"
assert_policy_rejected("terraform-root", bad_values)

bad_values = dict(values)
bad_values["DEVOPS_APTLY_INSTALL_ROOT"] = "/tmp/aptly"
assert_policy_rejected("path", bad_values)

bad_values = dict(values)
del bad_values["DEVOPS_OSC_RELEASE_VERSION"]
assert_policy_rejected("missing-key", bad_values)

bad_values = dict(values)
bad_values["DEVOPS_UNSUPPORTED_RELEASE"] = "1.0.0"
assert_policy_rejected("extra-key", bad_values)

assert_policy_rejected("mode", values, mode=0o644)
symlink_policy = temp_root / "bad-symlink.json"
symlink_policy.symlink_to(policy_path)
try:
    module.load_policy(symlink_policy)
except module.ToolInstallError:
    pass
else:
    raise AssertionError("symlinked policy was accepted")

for unsafe_name in ("../escape", "/absolute", "root//double"):
    try:
        module.archive_member_parts(unsafe_name, "fixture")
    except module.ToolInstallError:
        pass
    else:
        raise AssertionError(f"unsafe archive path accepted: {unsafe_name}")

bad_zip = temp_root / "bad.zip"
with zipfile.ZipFile(bad_zip, "w") as archive:
    archive.writestr("../escape", b"payload")
try:
    module.validated_zip_infos(
        bad_zip,
        "bad ZIP",
        policy.max_archive_members,
        policy.max_extracted_bytes,
    )
except module.ToolInstallError:
    pass
else:
    raise AssertionError("traversing ZIP member was accepted")

bad_tar = temp_root / "bad.tar.gz"
with tarfile.open(bad_tar, "w:gz") as archive:
    root = tarfile.TarInfo("root")
    root.type = tarfile.DIRTYPE
    archive.addfile(root)
    link = tarfile.TarInfo("root/link")
    link.type = tarfile.SYMTYPE
    link.linkname = "../../escape"
    archive.addfile(link)
try:
    module.validated_tar_members(
        bad_tar,
        "bad tar",
        "root",
        policy.max_archive_members,
        policy.max_extracted_bytes,
    )
except module.ToolInstallError:
    pass
else:
    raise AssertionError("escaping tar symlink was accepted")

deno_archive = temp_root / "deno-fixture.zip"
with zipfile.ZipFile(deno_archive, "w") as archive:
    archive.writestr("deno", b"managed-deno-fixture")
deno_root = temp_root / "deno-root"
module.prepare_deno(policy, deno_archive, deno_root)
deno_binary = deno_root / "bin/deno"
assert deno_binary.read_bytes() == b"managed-deno-fixture"
assert deno_binary.stat().st_mode & 0o777 == 0o755

bad_deno_archive = temp_root / "deno-extra-member.zip"
with zipfile.ZipFile(bad_deno_archive, "w") as archive:
    archive.writestr("deno", b"managed-deno-fixture")
    archive.writestr("unexpected", b"unexpected")
try:
    module.prepare_deno(policy, bad_deno_archive, temp_root / "bad-deno-root")
except module.ToolInstallError:
    pass
else:
    raise AssertionError("Deno archive with an extra member was accepted")

yt_dlp_payload = temp_root / "yt-dlp-payload"
yt_dlp_payload.write_bytes(b"managed-yt-dlp-fixture")
fixture_policy = dataclasses.replace(
    policy,
    yt_dlp=dataclasses.replace(
        policy.yt_dlp,
        expected_bytes=yt_dlp_payload.stat().st_size,
    ),
)
yt_dlp_root = temp_root / "yt-dlp-root"
module.prepare_yt_dlp(fixture_policy, yt_dlp_payload, yt_dlp_root)
yt_dlp_wrapper = yt_dlp_root / "bin/yt-dlp"
yt_dlp_wrapper_text = yt_dlp_wrapper.read_text(encoding="utf-8")
subprocess.run(["/bin/sh", "-n", str(yt_dlp_wrapper)], check=True)
assert "Official standalone releases bundle yt-dlp-ejs" in yt_dlp_wrapper_text
assert "--no-remote-components" in yt_dlp_wrapper_text
assert "--no-js-runtimes" in yt_dlp_wrapper_text
assert '--js-runtimes "deno:${deno_binary}"' in yt_dlp_wrapper_text
assert "--ffmpeg-location /usr/bin" in yt_dlp_wrapper_text
assert "--format" not in yt_dlp_wrapper_text
yt_dlp_record = (yt_dlp_root / ".managed-upstream-release").read_text(encoding="utf-8")
assert "javascript_component=yt-dlp-ejs-bundled\n" in yt_dlp_record
assert "remote_components=disabled\n" in yt_dlp_record

source_text = source.read_text(encoding="utf-8")
late_text = late_source.read_text(encoding="utf-8")
removed_ansible_distribution_keys = (
    "DEVOPS_ANSIBLE_VERSION",
    "DEVOPS_ANSIBLE_URL",
    "DEVOPS_ANSIBLE_SHA256",
    "DEVOPS_ANSIBLE_BYTES",
    "DEVOPS_ANSIBLE_ARCHITECTURE",
    "DEVOPS_ANSIBLE_ARCHIVE_FILENAME",
    "DEVOPS_ANSIBLE_PACKAGE_ROOT",
    "DEVOPS_ANSIBLE_DIST_INFO_ROOT",
    "DEVOPS_ANSIBLE_MAX_ARCHIVE_MEMBERS",
    "DEVOPS_ANSIBLE_MAX_EXTRACTED_BYTES",
    "DEVOPS_ANSIBLE_INSTALL_ROOT",
    "DEVOPS_ANSIBLE_BINARY_PATH",
)
for removed_key in removed_ansible_distribution_keys:
    assert removed_key not in module.POLICY_KEYS
    assert removed_key not in profile_values
    assert removed_key not in source_text
    assert removed_key not in late_text
assert module.ANSIBLE_CONSOLE_SCRIPTS == {
    "ansible": "ansible.cli.adhoc:main",
    "ansible-config": "ansible.cli.config:main",
    "ansible-console": "ansible.cli.console:main",
    "ansible-doc": "ansible.cli.doc:main",
    "ansible-galaxy": "ansible.cli.galaxy:main",
    "ansible-inventory": "ansible.cli.inventory:main",
    "ansible-playbook": "ansible.cli.playbook:main",
    "ansible-pull": "ansible.cli.pull:main",
    "ansible-test": "ansible_test._util.target.cli.ansible_test_cli_stub:main",
    "ansible-vault": "ansible.cli.vault:main",
}
assert "ansible-community" not in module.ANSIBLE_CONSOLE_SCRIPTS
assert "ansible-community" not in source_text
assert "download_only_artifact" not in source_text
assert "prepare_ansible_core(" in source_text
upstream_function = late_text.split("devops_install_upstream_tools() {", 1)[1].split(
    "\ndevops_install_pinned_rustup() {", 1
)[0]
rendered_pairs = re.findall(
    r'^\s+(DEVOPS_[A-Z0-9_]+) "\$(DEVOPS_[A-Z0-9_]+)"(?: \\)?$',
    upstream_function,
    flags=re.MULTILINE,
)
assert rendered_pairs
assert all(key == variable for key, variable in rendered_pairs)
assert {key for key, _ in rendered_pairs} == module.POLICY_KEYS
assert ".extractall(" not in source_text
assert '"--registry"' in source_text
assert "--proto-redir" in source_text
assert "shutil.rmtree(final_root, ignore_errors=True)" in source_text
assert "load_policy(pathlib.Path(sys.argv[2]))" in source_text
assert "--policy" in late_text
for key in (
    "DEVOPS_NODE_22_VERSION",
    "DEVOPS_NODE_22_URL",
    "DEVOPS_NODE_22_SHA256",
    "DEVOPS_NODE_22_BYTES",
    "DEVOPS_NODE_22_ARCHIVE_FILENAME",
    "DEVOPS_NODE_22_ARCHIVE_ROOT",
    "DEVOPS_NODE_24_VERSION",
    "DEVOPS_NODE_24_URL",
    "DEVOPS_NODE_24_SHA256",
    "DEVOPS_NODE_24_BYTES",
    "DEVOPS_NODE_24_ARCHIVE_FILENAME",
    "DEVOPS_NODE_24_ARCHIVE_ROOT",
    "DEVOPS_NODE_26_VERSION",
    "DEVOPS_NODE_26_URL",
    "DEVOPS_NODE_26_SHA256",
    "DEVOPS_NODE_26_BYTES",
    "DEVOPS_NODE_26_ARCHIVE_FILENAME",
    "DEVOPS_NODE_26_ARCHIVE_ROOT",
    "DEVOPS_DENO_VERSION",
    "DEVOPS_DENO_URL",
    "DEVOPS_DENO_SHA256",
    "DEVOPS_DENO_BYTES",
    "DEVOPS_YT_DLP_VERSION",
    "DEVOPS_YT_DLP_URL",
    "DEVOPS_YT_DLP_SHA256",
    "DEVOPS_YT_DLP_BYTES",
    "DEVOPS_RUSTUP_VERSION",
    "DEVOPS_RUSTUP_URL",
    "DEVOPS_RUSTUP_SHA256",
    "DEVOPS_RUSTUP_BYTES",
    "DEVOPS_DOTSLASH_VERSION",
    "DEVOPS_DOTSLASH_COMMIT",
    "DEVOPS_DOTSLASH_URL",
    "DEVOPS_DOTSLASH_SHA256",
    "DEVOPS_DOTSLASH_BYTES",
    "DEVOPS_UV_VERSION",
    "DEVOPS_UV_URL",
    "DEVOPS_UV_SHA256",
    "DEVOPS_UV_BYTES",
    "DEVOPS_ANSIBLE_CORE_VERSION",
    "DEVOPS_ANSIBLE_CORE_URL",
    "DEVOPS_ANSIBLE_CORE_SHA256",
    "DEVOPS_ANSIBLE_CORE_BYTES",
    "DEVOPS_ANSIBLE_CORE_ARCHIVE_FILENAME",
    "DEVOPS_OPENTOFU_VERSION",
    "DEVOPS_OPENTOFU_URL",
    "DEVOPS_OPENTOFU_SHA256",
    "DEVOPS_OPENTOFU_BYTES",
    "DEVOPS_OPENTOFU_ARCHIVE_FILENAME",
    "DEVOPS_OPENTOFU_ARCHIVE_FILES",
    "DEVOPS_TERRAFORM_VERSION",
    "DEVOPS_TERRAFORM_URL",
    "DEVOPS_TERRAFORM_SHA256",
    "DEVOPS_TERRAFORM_BYTES",
    "DEVOPS_TERRAFORM_ARCHIVE_FILENAME",
    "DEVOPS_TERRAFORM_ARCHIVE_FILES",
    "DEVOPS_PACKER_VERSION",
    "DEVOPS_PACKER_URL",
    "DEVOPS_PACKER_SHA256",
    "DEVOPS_PACKER_BYTES",
    "DEVOPS_PACKER_ARCHIVE_FILENAME",
    "DEVOPS_PACKER_ARCHIVE_FILES",
    "DEVOPS_WRANGLER_VERSION",
    "DEVOPS_WRANGLER_URL",
    "DEVOPS_WRANGLER_SHA512",
    "DEVOPS_WRANGLER_NPM_INTEGRITY",
    "DEVOPS_WRANGLER_BYTES",
    "DEVOPS_WRANGLER_ARCHIVE_FILENAME",
    "DEVOPS_APTLY_RELEASE_VERSION",
    "DEVOPS_APTLY_RELEASE_URL",
    "DEVOPS_APTLY_RELEASE_SHA256",
    "DEVOPS_APTLY_RELEASE_BYTES",
    "DEVOPS_APTLY_RELEASE_ARCHIVE_FILENAME",
    "DEVOPS_APTLY_RELEASE_ARCHIVE_ROOT",
    "DEVOPS_APTLY_RELEASE_ARCHIVE_FILES",
    "DEVOPS_OSC_RELEASE_VERSION",
    "DEVOPS_OSC_RELEASE_URL",
    "DEVOPS_OSC_RELEASE_SHA256",
    "DEVOPS_OSC_RELEASE_BYTES",
    "DEVOPS_OSC_RELEASE_ARCHIVE_FILENAME",
    "DEVOPS_OSC_RELEASE_DIST_INFO_ROOT",
    "DEVOPS_OBS_BUILD_TAG",
    "DEVOPS_OBS_BUILD_COMMIT",
    "DEVOPS_OBS_BUILD_URL",
    "DEVOPS_OBS_BUILD_SHA256",
    "DEVOPS_OBS_BUILD_BYTES",
    "DEVOPS_OBS_BUILD_ARCHIVE_FILENAME",
    "DEVOPS_OBS_BUILD_ARCHIVE_ROOT",
):
    assert profile_values[key] not in source_text, key
    assert profile_values[key] not in late_text, key
PY
then
  pass "profile-owned upstream DevOps policy validates ten isolated roots including Deno and yt-dlp-ejs plus core-only Ansible"
else
  fail "profile-owned upstream DevOps policy validates ten isolated roots including Deno and yt-dlp-ejs plus core-only Ansible"
fi

if python3 - "$devops_rust_tools" \
  "$ROOT_DIR/d-i/forky/hosts/profiles/override/btrfs-de-main.env" \
  "$TMP_DIR" <<'PY'
import importlib.util
import io
import pathlib
import shlex
import stat
import sys
import tarfile

source = pathlib.Path(sys.argv[1])
profile_source = pathlib.Path(sys.argv[2])
temp_root = pathlib.Path(sys.argv[3]) / "devops-rust-tools"
temp_root.mkdir(mode=0o700)

spec = importlib.util.spec_from_file_location("managed_devops_rust_tools_test", source)
assert spec is not None and spec.loader is not None
module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = module
spec.loader.exec_module(module)

profile_values = {}
for line in profile_source.read_text(encoding="utf-8").splitlines():
    if not line.startswith("DEVOPS_") or "=" not in line:
        continue
    key, raw = line.split("=", 1)
    parsed = shlex.split(raw, posix=True)
    assert len(parsed) == 1, line
    profile_values[key] = parsed[0]

arguments = [
    "--install-root", "/pool/build/test/cargo/install",
    "--download-timeout-seconds", "900",
    "--max-archive-members", "8192",
    "--max-extracted-bytes", "4294967296",
    "--dotslash-source-build", profile_values["DEVOPS_DOTSLASH_SOURCE_BUILD"],
    "--dotslash-version", profile_values["DEVOPS_DOTSLASH_VERSION"],
    "--dotslash-url", profile_values["DEVOPS_DOTSLASH_URL"],
    "--dotslash-sha256", profile_values["DEVOPS_DOTSLASH_SHA256"],
    "--dotslash-bytes", profile_values["DEVOPS_DOTSLASH_BYTES"],
    "--dotslash-architecture", profile_values["DEVOPS_DOTSLASH_ARCHITECTURE"],
    "--dotslash-archive-filename", profile_values["DEVOPS_DOTSLASH_ARCHIVE_FILENAME"],
    "--dotslash-archive-files", profile_values["DEVOPS_DOTSLASH_ARCHIVE_FILES"],
    "--uv-source-build", profile_values["DEVOPS_UV_SOURCE_BUILD"],
    "--uv-version", profile_values["DEVOPS_UV_VERSION"],
    "--uv-url", profile_values["DEVOPS_UV_URL"],
    "--uv-sha256", profile_values["DEVOPS_UV_SHA256"],
    "--uv-bytes", profile_values["DEVOPS_UV_BYTES"],
    "--uv-architecture", profile_values["DEVOPS_UV_ARCHITECTURE"],
    "--uv-archive-filename", profile_values["DEVOPS_UV_ARCHIVE_FILENAME"],
    "--uv-archive-root", profile_values["DEVOPS_UV_ARCHIVE_ROOT"],
    "--uv-archive-files", profile_values["DEVOPS_UV_ARCHIVE_FILES"],
]
policy = module.parse_arguments(arguments)
assert [artifact.name for artifact in policy.selected_artifacts] == ["DotSlash", "uv"]

source_arguments = list(arguments)
for option in ("--dotslash-source-build", "--uv-source-build"):
    source_arguments[source_arguments.index(option) + 1] = "1"
assert module.parse_arguments(source_arguments).selected_artifacts == ()


def add_file(archive, name, payload):
    info = tarfile.TarInfo(name)
    info.mode = 0o755
    info.size = len(payload)
    archive.addfile(info, io.BytesIO(payload))


dotslash_archive = temp_root / "dotslash.tar.gz"
with tarfile.open(dotslash_archive, "w:gz") as archive:
    add_file(archive, "dotslash", b"\x7fELFsynthetic-dotslash")

uv_archive = temp_root / "uv.tar.gz"
with tarfile.open(uv_archive, "w:gz") as archive:
    directory = tarfile.TarInfo("uv-x86_64-unknown-linux-gnu")
    directory.type = tarfile.DIRTYPE
    directory.mode = 0o755
    archive.addfile(directory)
    add_file(archive, "uv-x86_64-unknown-linux-gnu/uv", b"\x7fELFsynthetic-uv")
    add_file(archive, "uv-x86_64-unknown-linux-gnu/uvx", b"\x7fELFsynthetic-uvx")

staging_bin = temp_root / "staging-bin"
staging_bin.mkdir(mode=0o700)
module.prepare_artifact(policy, policy.dotslash, dotslash_archive, staging_bin)
module.prepare_artifact(policy, policy.uv, uv_archive, staging_bin)
for binary_name in ("dotslash", "uv", "uvx"):
    binary_path = staging_bin / binary_name
    assert binary_path.read_bytes().startswith(b"\x7fELF")
    assert stat.S_IMODE(binary_path.stat().st_mode) == 0o755

unsafe_archive = temp_root / "unsafe.tar.gz"
with tarfile.open(unsafe_archive, "w:gz") as archive:
    unsafe = tarfile.TarInfo("dotslash")
    unsafe.type = tarfile.SYMTYPE
    unsafe.linkname = "/bin/sh"
    archive.addfile(unsafe)
try:
    module.validated_tar_members(policy, policy.dotslash, unsafe_archive)
except module.RustToolInstallError:
    pass
else:
    raise AssertionError("symlink archive member was accepted")

traversal_archive = temp_root / "traversal.tar.gz"
with tarfile.open(traversal_archive, "w:gz") as archive:
    add_file(archive, "../dotslash", b"\x7fELFsynthetic-dotslash")
try:
    module.validated_tar_members(policy, policy.dotslash, traversal_archive)
except module.RustToolInstallError:
    pass
else:
    raise AssertionError("traversal archive member was accepted")

source_text = source.read_text(encoding="utf-8")
assert ".extractall(" not in source_text
assert "shell=True" not in source_text
assert '"--disable"' in source_text
assert '"--proto-redir"' in source_text
assert "info.issparse()" in source_text
assert "os.replace(staged_binary, destination)" in source_text
PY
then
  pass "prebuilt DotSlash and uv helper validates exact policy and rejects unsafe tar members before atomic publication"
else
  fail "prebuilt DotSlash and uv helper validates exact policy and rejects unsafe tar members before atomic publication"
fi

if /bin/sh -n "$devops_late" &&
   grep -Fq 'addon/devops is restricted to the desktop role' "$devops_late" &&
   grep -Fq 'bootstrap_source_common_support_libs "$seed_base" "$tmp_env_dir" target' "$devops_late" &&
   grep -Fq 'target/etc/skel/.config/cargo/config.toml.tmpl' "$devops_late" &&
   grep -Fq 'devops_render_cargo_config' "$devops_late" &&
   grep -Fq 'rustc --print target-cpus' "$devops_late" &&
   grep -Fq 'chown "$account_ids" "$target_cargo_config"' "$devops_late" &&
   [ ! -e "$devops_target_share" ] &&
   printf '%s\n' "$rustup_late_section" | grep -Fq 'rustup_version=$1' &&
   printf '%s\n' "$rustup_late_section" | grep -Fq 'rustup_url=$2' &&
   printf '%s\n' "$rustup_late_section" | grep -Fq 'expected_sha256=$3' &&
   printf '%s\n' "$rustup_late_section" | grep -Fq 'expected_bytes=$4' &&
   printf '%s\n' "$rustup_late_section" | grep -Fq 'target_triple=$5' &&
   printf '%s\n' "$rustup_late_section" | grep -Fq 'install_dir=$6' &&
   printf '%s\n' "$rustup_late_section" | grep -Fq 'rustup_init_path=$7' &&
   ! printf '%s\n' "$rustup_late_section" | grep -Fq 'rustup_path="${binary_dir}/rustup"' &&
   printf '%s\n' "$rustup_late_section" | grep -Fq 'https://static.rust-lang.org/rustup/archive/${rustup_version}/${target_triple}/rustup-init' &&
   printf '%s\n' "$rustup_late_section" | grep -Fq -- '--proto "=https"' &&
   printf '%s\n' "$rustup_late_section" | grep -Fq -- '--max-filesize "$expected_bytes"' &&
   [ "$(printf '%s\n' "$rustup_late_section" | grep -c '^curl ')" -eq 1 ] &&
   printf '%s\n' "$rustup_late_section" | grep -Fq 'payload_bytes=$(wc -c <"$payload_path" | tr -d "[[:space:]]")' &&
   printf '%s\n' "$rustup_late_section" | grep -Fq 'downloaded Rustup bootstrap size does not match the profile policy' &&
   printf '%s\n' "$rustup_late_section" | grep -Fq 'actual_sha256=$(sha256sum "$payload_path" | awk "{print \$1}")' &&
   printf '%s\n' "$rustup_late_section" | grep -Fq 'Rustup bootstrap SHA-256 mismatch' &&
   printf '%s\n' "$rustup_late_section" | grep -Fq '"$DEVOPS_RUSTUP_VERSION" \' &&
   printf '%s\n' "$rustup_late_section" | grep -Fq '"$DEVOPS_RUSTUP_URL" \' &&
   printf '%s\n' "$rustup_late_section" | grep -Fq '"$DEVOPS_RUSTUP_SHA256" \' &&
   printf '%s\n' "$rustup_late_section" | grep -Fq '"$DEVOPS_RUSTUP_BYTES" \' &&
   printf '%s\n' "$rustup_late_section" | grep -Fq '"$DEVOPS_RUSTUP_INSTALL_ROOT" \' &&
   printf '%s\n' "$rustup_late_section" | grep -Fq '"$DEVOPS_RUSTUP_BINARY_PATH" \' &&
   ! grep -Fq 'devops_render_toolchain_policy' "$devops_late" &&
   ! grep -Fq '/etc/devops/toolchain.conf' "$devops_late" &&
   ! grep -Fq 'DEVOPS_RUSTUP_TOOLCHAIN must remain nightly' "$devops_late" &&
   ! grep -Fq 'DEVOPS_RUSTUP_TOOLCHAIN must be stable, beta, nightly' "$devops_late" &&
   grep -Fq 'RUSTUP_TOOLCHAIN="$DEVOPS_RUSTUP_TOOLCHAIN"' "$devops_late" &&
   ! grep -Fq 'DEVOPS_RUSTUP_TOOLCHAIN=nightly' "$devops_late" &&
   ! grep -Fq 'DEVOPS_DOTSLASH_VERSION=0.5.9' "$devops_late" &&
   ! grep -Fq 'DEVOPS_DOTSLASH_COMMIT=3affd4484c3078348d9dc2dd9c53c598cd12228d' "$devops_late" &&
   ! grep -Fq 'DEVOPS_UV_VERSION=0.12.0' "$devops_late" &&
   [ -r "$devops_rust_tools" ] &&
   python3 -c 'from pathlib import Path; import sys; source = Path(sys.argv[1]); compile(source.read_bytes(), str(source), "exec")' "$devops_rust_tools" &&
   grep -Fq 'devops_install_pinned_rust_cli_binaries() {' "$devops_late" &&
   grep -Fq 'installer_repo_join_var DIR_SCRIPTS_LATE devops-rust-tools.py' "$devops_late" &&
   grep -Fq 'devops_install_pinned_rust_cli_binaries' "$devops_late" &&
   grep -Fq -- '--dotslash-source-build "$DEVOPS_DOTSLASH_SOURCE_BUILD"' "$devops_late" &&
   grep -Fq -- '--uv-source-build "$DEVOPS_UV_SOURCE_BUILD"' "$devops_late" &&
   grep -Fq -- '--dotslash-url "$DEVOPS_DOTSLASH_URL"' "$devops_late" &&
   grep -Fq -- '--uv-url "$DEVOPS_UV_URL"' "$devops_late" &&
   grep -Fq '"$build_root/$account_user/deno"' "$devops_late" &&
   grep -Fq '"$build_root/$account_user/deno/bin"' "$devops_late" &&
   grep -Fq '"$cache_root/$account_user/deno"' "$devops_late" &&
   grep -Fq '"$db_root/$account_user/deno"' "$devops_late" &&
   grep -Fq 'yt-dlp standalone payload with bundled yt-dlp-ejs is missing after installation' "$devops_late" &&
   grep -Fq '"$build_root/$account_user/python/bin"' "$devops_late" &&
   grep -Fq '"$build_root/$account_user/uv/bin"' "$devops_late" &&
   grep -Fq '"$cache_root/$account_user/pip"' "$devops_late" &&
   grep -Fq '"$cache_root/$account_user/uv"' "$devops_late" &&
   grep -Fq '"$db_root/$account_user/python"' "$devops_late" &&
   grep -Fq '"$db_root/$account_user/uv/tools"' "$devops_late" &&
   grep -Fq 'PATH="${CARGO_INSTALL_ROOT}/bin:${CARGO_HOME}/bin:' "$devops_late" &&
   grep -Fq '      -y' "$devops_late" &&
   ! grep -Fq -- '--yes' "$devops_late" &&
   grep -Fq -- '--default-toolchain' "$devops_late" &&
   grep -Fq -- '--no-modify-path' "$devops_late" &&
   grep -Fq -- '--profile' "$devops_late" &&
   grep -Fq '      minimal' "$devops_late" &&
   grep -Fq 'rustup component add rustfmt' "$devops_late" &&
   grep -Fq 'rustup show active-toolchain | grep -Fq -- "$expected_rustup_toolchain"' "$devops_late" &&
   grep -Fq "cargo install \\" "$devops_late" &&
   [ "$(grep -Fc "        --locked \\" "$devops_late")" -eq 2 ] &&
   grep -Fq 'dotslash_source_build=$1' "$devops_late" &&
   grep -Fq 'dotslash_repository_url=$4' "$devops_late" &&
   grep -Fq 'uv_source_build=$5' "$devops_late" &&
   grep -Fq 'if [ "$dotslash_source_build" = 1 ]; then' "$devops_late" &&
   grep -Fq 'if [ "$uv_source_build" = 1 ]; then' "$devops_late" &&
   grep -Fq -- '--git "$dotslash_repository_url"' "$devops_late" &&
   grep -Fq -- '--rev "$dotslash_commit"' "$devops_late" &&
   grep -Fq -- '--version "$uv_version"' "$devops_late" &&
   grep -Fq '"$DEVOPS_DOTSLASH_REPOSITORY_URL" \' "$devops_late" &&
   grep -Fq '        dotslash' "$devops_late" &&
   grep -Fq '        uv' "$devops_late" &&
   grep -Fq 'command -v rustfmt' "$devops_late" &&
   grep -Fq 'command -v dotslash' "$devops_late" &&
   grep -Fq 'command -v uv' "$devops_late" &&
   grep -Fq 'command -v uvx' "$devops_late" &&
   grep -Fq 'rustup component list --installed | grep -Eq "^rustfmt-"' "$devops_late" &&
   grep -Fq 'dotslash --version | grep -Fq "$expected_dotslash_version"' "$devops_late" &&
   grep -Fq 'uv --version | grep -Fq "$expected_uv_version"' "$devops_late" &&
   grep -Fq 'uvx --version | grep -Fq "$expected_uv_version"' "$devops_late" &&
   grep -Fq 'CARGO_NET_RETRY=3' "$devops_late" &&
   grep -Fq 'required Rust tool command is unavailable: /usr/bin/timeout' "$devops_late" &&
   grep -Fq "      3600s \\" "$devops_late" &&
   grep -Fq "      7200s \\" "$devops_late" &&
   ! grep -Fq 'rustup default stable' "$devops_late" &&
   ! grep -Fq 'toolchain install stable' "$devops_late" &&
   grep -Fq 'link preinstalled Node runtimes into Mise' "$devops_late" &&
   grep -Fq '/usr/lib/llvm-24/bin/clang' "$devops_late" &&
   grep -Fq '/usr/lib/llvm-24/bin/clang++' "$devops_late" &&
   grep -Fq '/usr/lib/llvm-24/bin/llvm-config' "$devops_late" &&
   grep -Fq '/usr/lib/llvm-24/bin/lld' "$devops_late" &&
   grep -Fq '/usr/lib/llvm-24/bin/ld.lld' "$devops_late" &&
   grep -Fq '/usr/lib/llvm-24/bin/lldb' "$devops_late" &&
   ! grep -Fq 'for llvm_version in 22 23 24; do' "$devops_late" &&
   grep -Fq 'mise link --force "node@${node_version}"' "$devops_late" &&
   grep -Fq 'mise reshim' "$devops_late" &&
   ! grep -Fq 'mise link --force "llvm' "$devops_late" &&
   ! grep -Fq 'mise link --force "bazel' "$devops_late" &&
   grep -Fq 'devops_install_pinned_bazelisk()' "$devops_late" &&
   grep -Fq 'devops_render_bazelrc()' "$devops_late" &&
   ! grep -Fq '/usr/local/bin/bazel' "$devops_late" &&
   [ ! -e "$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/bazel" ] &&
   grep -Fq 'DEVOPS_BAZELISK_URL must be the HTTPS Linux AMD64 release asset for DEVOPS_BAZELISK_VERSION' "$devops_late" &&
   grep -Fq -- '--max-filesize "$maximum_bytes"' "$devops_late" &&
   grep -Fq 'payload_bytes=$(wc -c <"$payload_path" | tr -d "[[:space:]]")' "$devops_late" &&
   grep -Fq 'Bazelisk SHA-256 mismatch' "$devops_late" &&
   grep -Fq '"$cache_root/$account_user/$bazel_cache_subdir/$bazel_disk_cache_subdir"' "$devops_late" &&
   grep -Fq '"$build_root/$account_user/$bazel_output_user_root_subdir"' "$devops_late" &&
   grep -Fq 'BAZELISK_HOME="$BAZELISK_HOME"' "$devops_late" &&
   grep -Fq 'MISE_TMP_DIR="$MISE_TMP_DIR"' "$devops_late" &&
   grep -Fq '"$cache_root/$account_user/pnpm/store"' "$devops_late" &&
   grep -Fq '"$db_root/$account_user/pnpm/state"' "$devops_late" &&
   ! grep -Fq '/usr/share/nodejs/corepack/dist/corepack.js' "$devops_late" &&
   [ ! -e "$bazelisk_target_helper" ] &&
   ! grep -Fq 'target/usr/local/libexec/devops-install-nodejs' "$devops_late" &&
   ! grep -Fq 'target/usr/local/libexec/devops-install-bazelisk' "$devops_late"; then
  pass "desktop DevOps late helper selects verified DotSlash and uv archives or locked source builds after bounded Rustup initialization"
else
  fail "desktop DevOps late helper selects verified DotSlash and uv archives or locked source builds after bounded Rustup initialization"
fi

if [ -x "$llama_late" ] &&
   /bin/sh -n "$llama_late" &&
   [ -r "$ai_runtime_archive_helper" ] &&
   python3 -c 'from pathlib import Path; import sys; source = Path(sys.argv[1]); compile(source.read_bytes(), str(source), "exec")' "$ai_runtime_archive_helper" &&
   grep -Fq 'for member_count, member in enumerate(archive, start=1):' "$ai_runtime_archive_helper" &&
   ! grep -Fq 'archive.getmembers()' "$ai_runtime_archive_helper" &&
   grep -Fq 'devops_install_llama_runtime() {' "$devops_late" &&
   grep -Fq 'installer_repo_join_var DIR_SCRIPTS_LATE llama.sh' "$devops_late" &&
   grep -Fq 'INSTALLER_LLAMA_TMP_ENV_DIR="${tmp_env_dir}/llama"' "$devops_late" &&
   grep -Fq 'target_helper=/tmp/installer-llama' "$llama_late" &&
   grep -Fq 'target_profile=/tmp/llama-install.env' "$llama_late" &&
   grep -Fq 'target_archive_helper=/tmp/installer-ai-runtime-archive.py' "$llama_late" &&
   grep -Fq 'installer_repo_join_var DIR_SCRIPTS_LATE ai-runtime-archive.py' "$llama_late" &&
   grep -Fq 'run_llama_install_in_target "download and install selected llama.cpp runtime"' "$llama_late" &&
   grep -Fq 'llama_target_managed_dir "$LLAMA_ROOT" runtime' "$llama_late" &&
   grep -Fq 'llama_target_managed_dir "$LLAMA_MODEL_DIR" models' "$llama_late" &&
   grep -Fq 'llama_target_secure_model_directory' "$llama_late" &&
   grep -Fq 'LLAMA_MODEL_DIR must remain /pool/cache/llama/models' "$llama_late" &&
   grep -Fq 'chown "0:${llama_model_gid}" "$LLAMA_MODEL_DIR" "$marker_path"' "$llama_late" &&
   grep -Fq 'chmod 2750 "$LLAMA_MODEL_DIR"' "$llama_late" &&
   grep -Fq 'chown "0:${llama_model_gid}" "$final_model"' "$llama_late" &&
   grep -Fq 'chmod 0640 "$final_model"' "$llama_late" &&
   grep -Fq -- '--max-filesize "$LLAMA_RELEASE_BYTES"' "$llama_late" &&
   grep -Fq '[ "$archive_bytes" = "$LLAMA_RELEASE_BYTES" ]' "$llama_late" &&
   grep -Fq '[ "$archive_sha256" = "$LLAMA_RELEASE_SHA256" ]' "$llama_late" &&
   grep -Fq -- '--required-directory bin' "$llama_late" &&
   grep -Fq -- '--required-directory metadata' "$llama_late" &&
   grep -Fq -- '--required-directory share' "$llama_late" &&
   grep -Fq -- '--required-binary llama-bench' "$llama_late" &&
   grep -Fq -- '--required-binary llama-cli' "$llama_late" &&
   grep -Fq -- '--required-binary llama-gguf-split' "$llama_late" &&
   grep -Fq -- '--required-binary llama-quantize' "$llama_late" &&
   grep -Fq -- '--required-binary llama-server' "$llama_late" &&
   grep -Fq 'mv -- "$extract_dir/bin" "$LLAMA_BINARY_DIR"' "$llama_late" &&
   grep -Fq 'mv -- "$extract_dir/metadata" "$LLAMA_METADATA_DIR"' "$llama_late" &&
   grep -Fq 'mv -- "$extract_dir/share" "$LLAMA_SHARE_DIR"' "$llama_late" &&
   grep -Fq 'llama_release_publish_in_progress=1' "$llama_late" &&
   grep -Fq 'llama_target_rollback_release_publication' "$llama_late" &&
   grep -Fq 'failed to publish the complete llama runtime release' "$llama_late" &&
   llama_release_rollback_works &&
   grep -Fq 'for runtime_verify_binary_name in llama-bench llama-cli llama-gguf-split llama-quantize llama-server; do' "$llama_late" &&
   grep -Fq 'target/etc/llama/llama.conf.tmpl' "$llama_late" &&
   grep -Fq 'target/data/llama/lib/llama' "$llama_late" &&
   grep -Fq 'runtime_conf_dir=/etc/llama' "$llama_late" &&
   grep -Fq 'wrapper_source=/tmp/llama-launcher' "$llama_late" &&
   llama_verification_stays_target_local &&
   llama_streamed_target_runner_works &&
   llama_target_runtime_verifier_works &&
   ! grep -Fq 'cat >"$wrapper_tmp"' "$llama_late" &&
   ! grep -Eq 'LLAMA_(CPP_REPO|CPP_REF|SOURCE_DIR|BUILD_DIR|OUTPUT_DIR|SCCACHE_DIR|DGGML_|CMAKE_|BUILD_JOBS)' "$llama_late" &&
   ! grep -Eq 'run_llama_build_in_target|--target-build|configure_and_build|(^|[[:space:]])(cmake|ninja|sccache)([[:space:]]|$)' "$llama_late" &&
   [ -x "$llama_launcher" ] &&
   /bin/sh -n "$llama_launcher" &&
   grep -Fqx 'LLAMA_MODEL=__LLAMA_MODEL__' "$llama_runtime_template" &&
   ! grep -q '^LLAMA_BINARY_DIR=' "$llama_runtime_template" &&
   grep -Fq 'llama_config_path=/etc/llama/llama.conf' "$llama_launcher" &&
   grep -Fq 'llama_binary_dir=/data/llama/bin' "$llama_launcher" &&
   ! grep -Fq 'LLAMA_BINARY_DIR=*)' "$llama_launcher" &&
   grep -Fq 'done <"$llama_config_path"' "$llama_launcher" &&
   ! grep -Fq '. "$llama_config_path"' "$llama_launcher" &&
   grep -Fq '[ "$llama_server_host" = 127.0.0.1 ]' "$llama_launcher" &&
   grep -Fq 'LLAMA_ARG_HOST=$llama_server_host' "$llama_launcher" &&
   grep -Fq 'LLAMA_ARG_PORT=$llama_server_port' "$llama_launcher" &&
   ! grep -Fq ': "${LLAMA_ARG_HOST:=' "$llama_launcher" &&
   ! grep -Fq ': "${LLAMA_ARG_PORT:=' "$llama_launcher" &&
   grep -Fq 'llama_require_root_file "$llama_binary" 755' "$llama_launcher" &&
   grep -Fq -- '--threads-batch "$LLAMA_ARG_THREADS_BATCH"' "$llama_launcher" &&
   grep -Fq '"$target_runtime_template_host"' "$llama_late" &&
   grep -Fq '"$target_wrapper_source_host"' "$llama_late" &&
   ! grep -Eq '/usr/local/libexec|unsupported pinned llama[.]cpp model definition|qwen2[.]5-coder-' "$llama_late" &&
   ! grep -Eq 'llama-serve([^r]|$)' "$llama_late" &&
   grep -Fq '/etc/llama/llama.conf r,' "$managed_wrapper_apparmor" &&
   grep -Fq '/data/llama/lib/llama rix,' "$managed_wrapper_apparmor" &&
   grep -Fq '/data/llama/bin/llama-server mrix,' "$managed_wrapper_apparmor" &&
   grep -Fq '/data/llama/bin/{llama-cli,llama-server} rix,' "$managed_wrapper_apparmor" &&
   grep -Fq '/data/llama/bin/{llama-bench,llama-cli,llama-gguf-split,llama-quantize,llama-server} mrix,' "$managed_wrapper_apparmor" &&
   ! grep -Fq '/pool/cache/llama/source' "$devops_readme" &&
   ! grep -Fq '/pool/build/llama/output' "$devops_readme" &&
   grep -Fq '/pool/cache/llama/models' "$devops_readme" &&
   grep -Fq '/data/llama/bin' "$devops_readme" &&
   grep -Fq '`llama-bench`, `llama-cli`, `llama-gguf-split`' "$devops_readme" &&
   grep -Fq '/data/llama/metadata' "$devops_readme" &&
   grep -Fq '/data/llama/share' "$devops_readme" &&
   grep -Fq '/data/llama/lib/llama' "$devops_readme" &&
   grep -Fq 'an on-demand `llama-server.service`' "$devops_readme" &&
   grep -Fq 'server to `127.0.0.1` and the profile-configured port' "$devops_readme"; then
  pass "DevOps installs and verifies the complete pinned llama.cpp release without installer-time compilation"
else
  fail "DevOps installs and verifies the complete pinned llama.cpp release without installer-time compilation"
fi

if llama_launcher_works; then
  pass "static llama launcher preserves bounded runtime overrides while fixing server host and port to root-managed policy"
else
  fail "static llama launcher preserves bounded runtime overrides while fixing server host and port to root-managed policy"
fi

if ai_runtime_archive_validator_works; then
  pass "AI runtime extractor accepts the pinned layout and rejects traversal, links, duplicates, unexpected binaries, and configured limit overflows"
else
  fail "AI runtime extractor accepts the pinned layout and rejects traversal, links, duplicates, unexpected binaries, and configured limit overflows"
fi

if grep -Fq 'desktop_render_cargo_config' "$desktop_components" &&
   grep -Fq '"etc/skel/.config/cargo/config.toml.tmpl"' "$desktop_components" &&
   grep -Fq 'DEVOPS_CARGO_TARGET_CPU "$DEVOPS_CARGO_TARGET_CPU"' "$desktop_components" &&
   grep -Fq 'etc/skel/.config/mise/config.toml /etc/skel/.config/mise/config.toml 0644' "$desktop_components" &&
   grep -Fq 'etc/skel/.config/mise/conf.d/10-managed-tools.toml /etc/skel/.config/mise/conf.d/10-managed-tools.toml 0644' "$desktop_components" &&
   grep -Fq ".config/cargo \\" "$desktop_components" &&
   grep -Fq ".config/mise \\" "$desktop_components" &&
   grep -Fq '[ -d /etc/skel/.config/bazel ]' "$desktop_components" &&
   grep -Fq 'src=/etc/skel/.config/bazel' "$desktop_components"; then
  pass "desktop components render and copy managed Cargo policy plus Mise and Bazel configuration trees"
else
  fail "desktop components render and copy managed Cargo policy plus Mise and Bazel configuration trees"
fi

if [ -r "$bazelrc_template" ] &&
   grep -Fqx 'startup --output_user_root=__INSTALLER_DEVOPS_BAZEL_OUTPUT_USER_ROOT__' "$bazelrc_template" &&
   grep -Fqx 'common --disk_cache=__INSTALLER_DEVOPS_BAZEL_DISK_CACHE__' "$bazelrc_template" &&
   grep -Fqx 'common --repository_cache=__INSTALLER_DEVOPS_BAZEL_REPOSITORY_CACHE__' "$bazelrc_template" &&
   grep -Fqx 'common --experimental_repository_cache_hardlinks' "$bazelrc_template" &&
   grep -Fqx 'common --experimental_disk_cache_gc_max_size=__INSTALLER_DEVOPS_BAZEL_DISK_CACHE_SIZE__' "$bazelrc_template" &&
   grep -Fqx 'common --experimental_disk_cache_gc_max_age=__INSTALLER_DEVOPS_BAZEL_DISK_CACHE_MAX_AGE__' "$bazelrc_template" &&
   grep -Fqx 'common --experimental_action_cache_gc_max_age=__INSTALLER_DEVOPS_BAZEL_ACTION_CACHE_MAX_AGE__' "$bazelrc_template" &&
   ! grep -Eq '^common .*--disk_cache_size' "$bazelrc_template"; then
  pass "Bazel skeleton template uses supported pool cache, hardlink, and native garbage-collection flags"
else
  fail "Bazel skeleton template uses supported pool cache, hardlink, and native garbage-collection flags"
fi

cargo_profile_policy_valid=true
cargo_generic_profile_count=0
cargo_skylake_profile_count=0
cargo_tigerlake_profile_count=0
for profile_relpath in $desktop_profiles; do
  profile_path="$ROOT_DIR/$profile_relpath"
  if ! /bin/sh -n "$profile_path" ||
     ! grep -Fqx 'DEVOPS_CARGO_RUSTC_WRAPPER="sccache"' "$profile_path" ||
     ! grep -Fqx 'DEVOPS_CARGO_TARGET_TRIPLE="x86_64-unknown-linux-gnu"' "$profile_path" ||
     ! grep -Fqx 'DEVOPS_CARGO_TARGET_LINKER="clang-24"' "$profile_path" ||
     ! grep -Fqx 'DEVOPS_CARGO_LINKER_ARGUMENT="-fuse-ld=mold"' "$profile_path" ||
     grep -q '^DEVOPS_CARGO_BUILD_JOBS=' "$profile_path"; then
    cargo_profile_policy_valid=false
    break
  fi
  for profile_var in $required_cargo_profile_vars; do
    if ! grep -Eq "^${profile_var}=" "$profile_path"; then
      cargo_profile_policy_valid=false
      break 2
    fi
  done
  cargo_target_cpu=$(sed -n 's/^DEVOPS_CARGO_TARGET_CPU="\([^"]*\)"$/\1/p' "$profile_path")
  case "$cargo_target_cpu" in
    generic)
      cargo_generic_profile_count=$((cargo_generic_profile_count + 1))
      ;;
    skylake)
      cargo_skylake_profile_count=$((cargo_skylake_profile_count + 1))
      ;;
    tigerlake)
      cargo_tigerlake_profile_count=$((cargo_tigerlake_profile_count + 1))
      ;;
    *)
      cargo_profile_policy_valid=false
      break
      ;;
  esac
done
if [ "$cargo_profile_policy_valid" = true ] &&
   [ "$cargo_generic_profile_count" -eq 9 ] &&
   [ "$cargo_skylake_profile_count" -eq 2 ] &&
   [ "$cargo_tigerlake_profile_count" -eq 2 ] &&
   grep -Fqx 'DEVOPS_CARGO_TARGET_CPU="skylake"' "$ROOT_DIR/d-i/forky/hosts/profiles/override/btrfs-de-main.env" &&
   grep -Fqx 'DEVOPS_CARGO_TARGET_CPU="skylake"' "$ROOT_DIR/d-i/forky/hosts/profiles/override/btrfs-de-dual-main.env" &&
   grep -Fqx 'DEVOPS_CARGO_TARGET_CPU="tigerlake"' "$ROOT_DIR/d-i/forky/hosts/profiles/override/btrfs-de-flex.env" &&
   grep -Fqx 'DEVOPS_CARGO_TARGET_CPU="tigerlake"' "$ROOT_DIR/d-i/forky/hosts/profiles/override/btrfs-de-dual-flex.env"; then
  pass "all 13 desktop profiles own Cargo toolchain policy without a managed jobs cap"
else
  fail "all 13 desktop profiles own Cargo toolchain policy without a managed jobs cap"
fi

profile_policy_valid=true
for profile_relpath in $desktop_profiles; do
  profile_path="$ROOT_DIR/$profile_relpath"
  if ! /bin/sh -n "$profile_path" ||
     ! grep -Fqx 'DEVOPS_BAZELISK_VERSION="1.29.0"' "$profile_path" ||
     ! grep -Fqx 'DEVOPS_BAZELISK_URL="https://github.com/bazelbuild/bazelisk/releases/download/v1.29.0/bazelisk-linux-amd64"' "$profile_path" ||
     ! grep -Fqx 'DEVOPS_BAZELISK_SHA256="5a408715e932c0250d28bd84555f12edbf70117de42f9181691c736eacc4a992"' "$profile_path" ||
     ! grep -Fqx 'DEVOPS_BAZEL_CACHE_ROOT="/pool/cache"' "$profile_path" ||
     ! grep -Fqx 'DEVOPS_BAZEL_BUILD_ROOT="/pool/build"' "$profile_path" ||
     ! grep -Fqx 'DEVOPS_BAZEL_DB_ROOT="/pool/db"' "$profile_path" ||
     ! grep -Fq 'DEVOPS_BAZEL_DISK_CACHE_SIZE=' "$profile_path" ||
     ! grep -Fq 'DEVOPS_BAZEL_DISK_CACHE_MAX_AGE=' "$profile_path"; then
    profile_policy_valid=false
    break
  fi
  for profile_var in $required_bazel_profile_vars; do
    if ! grep -Eq "^${profile_var}=" "$profile_path"; then
      profile_policy_valid=false
      break 2
    fi
  done
done
if [ "$profile_policy_valid" = true ]; then
  pass "every concrete desktop profile pins Bazelisk and exposes /pool cache and GC policy controls"
else
  fail "every concrete desktop profile pins Bazelisk and exposes /pool cache and GC policy controls"
fi

codex_profile_policy_valid=true
codex_reference_block="${TMP_DIR}/codex-profile.reference"
: >"$codex_reference_block"
codex_profile_index=0
for profile_relpath in $desktop_profiles; do
  profile_path="$ROOT_DIR/$profile_relpath"
  if ! grep -Eq '^DEVOPS_CODEX_VERSION="[A-Za-z0-9][A-Za-z0-9._+-]*"$' "$profile_path" ||
     ! grep -Eq '^DEVOPS_CODEX_RELEASE_TAG="[A-Za-z0-9][A-Za-z0-9._+-]*"$' "$profile_path" ||
     ! grep -Eq '^DEVOPS_CODEX_URL="https://[^[:space:]"]+"$' "$profile_path" ||
     ! grep -Eq '^DEVOPS_CODEX_SHA256="[0-9a-f]{64}"$' "$profile_path" ||
     ! grep -Eq '^DEVOPS_CODEX_MAXIMUM_BYTES="[1-9][0-9]*"$' "$profile_path" ||
     ! grep -Eq '^DEVOPS_CODEX_MAXIMUM_EXTRACTED_BYTES="[1-9][0-9]*"$' "$profile_path" ||
     ! grep -Fqx 'DEVOPS_CODEX_ARCHIVE_BINARY_DIR="bin"' "$profile_path" ||
     ! grep -Fqx 'DEVOPS_CODEX_ARCHIVE_SCHEMA_MEMBER="config.schema.json"' "$profile_path" ||
     ! grep -Fqx 'DEVOPS_CODEX_SCHEMA_PATH="/data/codex/config.schema.json"' "$profile_path" ||
     ! grep -Eq '^DEVOPS_CODEX_REPOSITORY_COMMIT="[0-9a-f]{40}"$' "$profile_path" ||
     ! grep -Fqx 'DEVOPS_CODEX_BWRAP_USERNS_CLONE="1"' "$profile_path" ||
     ! grep -Fqx 'DEVOPS_CODEX_BWRAP_MAX_USER_NAMESPACES="1024"' "$profile_path"; then
    codex_profile_policy_valid=false
    break
  fi
  for profile_var in $required_codex_profile_vars; do
    if ! grep -Eq "^${profile_var}=" "$profile_path"; then
      codex_profile_policy_valid=false
      break 2
    fi
  done
  codex_profile_block="${TMP_DIR}/codex-profile.${codex_profile_index}"
  awk '
    /^# Optional managed Codex policy/ { capture = 1 }
    /^# Optional DevOps Cargo policy/ { capture = 0 }
    capture {
      if ($0 ~ /^DEVOPS_CODEX_REPOSITORY_COMMIT=/) {
        print "DEVOPS_CODEX_REPOSITORY_COMMIT=\"<profile-pinned>\""
      } else {
        print
      }
    }
  ' "$profile_path" >"$codex_profile_block"
  if [ "$codex_profile_index" -eq 0 ]; then
    cp "$codex_profile_block" "$codex_reference_block"
  elif ! cmp -s "$codex_reference_block" "$codex_profile_block"; then
    codex_profile_policy_valid=false
    break
  fi
  codex_profile_index=$((codex_profile_index + 1))
done
if [ "$codex_profile_policy_valid" = true ] &&
   [ "$codex_profile_index" -eq 13 ]; then
  pass "all 13 desktop profiles carry byte-identical pinned Codex and Bubblewrap prerequisite policy"
else
  fail "all 13 desktop profiles carry byte-identical pinned Codex and Bubblewrap prerequisite policy"
fi

if grep -Fq '[ "${#DEVOPS_CODEX_REPOSITORY_COMMIT}" -eq 40 ]' "$devops_late" &&
   grep -Fq 'DEVOPS_CODEX_REPOSITORY_COMMIT must contain exactly 40 lowercase hexadecimal characters (got ${#DEVOPS_CODEX_REPOSITORY_COMMIT})' "$devops_late" &&
   grep -Fq 'DEVOPS_CODEX_REPOSITORY_COMMIT must contain exactly 40 lowercase hexadecimal characters' "$devops_late" &&
   ! grep -Fq 'DEVOPS_CODEX_REPOSITORY_COMMIT must be a lowercase Git commit id' "$devops_late" &&
   codex_truncated_commit_is_rejected; then
  pass "late DevOps distinguishes a truncated Codex commit from invalid lowercase hexadecimal syntax"
else
  fail "late DevOps distinguishes a truncated Codex commit from invalid lowercase hexadecimal syntax"
fi

llama_profile_policy_valid=true
llama_reference_schema="${TMP_DIR}/llama-profile.schema"
: >"$llama_reference_schema"
llama_profile_index=0
llama_cuda_profile_count=0
llama_ram_profile_count=0
for profile_relpath in $desktop_profiles; do
  profile_path="$ROOT_DIR/$profile_relpath"
  llama_profile_schema="${TMP_DIR}/llama-profile.${llama_profile_index}.schema"
  sed -n 's/^\(LLAMA_[A-Z0-9_]*\)=.*/\1/p' "$profile_path" >"$llama_profile_schema"
  llama_profile_var_count=$(wc -l <"$llama_profile_schema" | tr -d ' ')

  if ! /bin/sh -n "$profile_path" ||
     [ "$llama_profile_var_count" -ne 34 ] ||
     ! grep -Fqx 'LLAMA_ROOT="/data/llama"' "$profile_path" ||
     ! grep -Fqx 'LLAMA_BINARY_DIR="/data/llama/bin"' "$profile_path" ||
     ! grep -Fqx 'LLAMA_METADATA_DIR="/data/llama/metadata"' "$profile_path" ||
     ! grep -Fqx 'LLAMA_SHARE_DIR="/data/llama/share"' "$profile_path" ||
     ! grep -Fqx 'LLAMA_WRAPPER_PATH="/data/llama/lib"' "$profile_path" ||
     ! grep -Fqx 'LLAMA_MODEL_DIR="/pool/cache/llama/models"' "$profile_path" ||
     grep -Eq '^LLAMA_(CPP_REPO|CPP_REF|CPP_COMMIT|SOURCE_DIR|BUILD_DIR|OUTPUT_DIR|SCCACHE_DIR|DGGML_|CMAKE_|BUILD_JOBS|SOURCE_UPDATE|FORCE_SOURCE_RESET)=' "$profile_path"; then
    llama_profile_policy_valid=false
    break
  fi

  for profile_var in $required_llama_profile_vars; do
    if ! grep -Eq "^${profile_var}=" "$profile_path"; then
      llama_profile_policy_valid=false
      break 2
    fi
  done

  if [ "$llama_profile_index" -eq 0 ]; then
    cp "$llama_profile_schema" "$llama_reference_schema"
  elif ! cmp -s "$llama_reference_schema" "$llama_profile_schema"; then
    llama_profile_policy_valid=false
    break
  fi

  case "$profile_relpath" in
    d-i/forky/hosts/profiles/override/btrfs-de-main.env|\
    d-i/forky/hosts/profiles/override/btrfs-de-dual-main.env)
      if ! grep -Fqx 'LLAMA_RELEASE_URL="https://github.com/mjcramerz/llama-labwc/releases/download/llama-labwc-main/llama-cuda.tar.gz"' "$profile_path" ||
         ! grep -Fqx 'LLAMA_RELEASE_SHA256="452e94e6a0b029be050071ab124128ada4ca62deed207c01155283c47d9ef583"' "$profile_path" ||
         ! grep -Fqx 'LLAMA_RELEASE_BYTES="124347063"' "$profile_path" ||
         ! grep -Fqx 'LLAMA_RELEASE_MAXIMUM_EXTRACTED_BYTES="268435456"' "$profile_path" ||
         ! grep -Fqx 'LLAMA_RELEASE_MAXIMUM_MEMBERS="32"' "$profile_path" ||
         ! grep -Fqx 'LLAMA_RELEASE_ARCHIVE_ROOT="llama-cuda"' "$profile_path" ||
         ! grep -Fqx 'LLAMA_RELEASE_REQUIRED_CLASS="addon/cuda-legacy"' "$profile_path" ||
         ! grep -Fqx 'LLAMA_RUNTIME_THREADS=8' "$profile_path" ||
         ! grep -Fqx 'LLAMA_RUNTIME_GPU_LAYERS=8' "$profile_path" ||
         ! grep -Fqx 'LLAMA_RUNTIME_KV_OFFLOAD=0' "$profile_path" ||
         ! grep -Fqx 'LLAMA_DEFAULT_MODEL="qwen2.5-coder-7b-instruct-q4_k_m.gguf"' "$profile_path"; then
        llama_profile_policy_valid=false
        break
      fi
      llama_cuda_profile_count=$((llama_cuda_profile_count + 1))
      ;;
    *)
      if ! grep -Fqx 'LLAMA_RELEASE_URL="https://github.com/mjcramerz/llama-labwc/releases/download/llama-labwc-main/llama-ram.tar.gz"' "$profile_path" ||
         ! grep -Fqx 'LLAMA_RELEASE_SHA256="ccc6027ef73f7119d26517068ffcff6805aa2de853c83b8c663b0f1f4b17e636"' "$profile_path" ||
         ! grep -Fqx 'LLAMA_RELEASE_BYTES="27260290"' "$profile_path" ||
         ! grep -Fqx 'LLAMA_RELEASE_MAXIMUM_EXTRACTED_BYTES="67108864"' "$profile_path" ||
         ! grep -Fqx 'LLAMA_RELEASE_MAXIMUM_MEMBERS="32"' "$profile_path" ||
         ! grep -Fqx 'LLAMA_RELEASE_ARCHIVE_ROOT="llama-ram"' "$profile_path" ||
         ! grep -Fqx 'LLAMA_RELEASE_REQUIRED_CLASS=""' "$profile_path" ||
         ! grep -Fqx 'LLAMA_RUNTIME_GPU_LAYERS=0' "$profile_path"; then
        llama_profile_policy_valid=false
        break
      fi
      llama_ram_profile_count=$((llama_ram_profile_count + 1))
      ;;
  esac

  case "$profile_relpath" in
    d-i/forky/hosts/profiles/override/btrfs-de-flex.env|\
    d-i/forky/hosts/profiles/override/btrfs-de-dual-flex.env)
      if ! grep -Fqx 'LLAMA_RUNTIME_THREADS=4' "$profile_path" ||
         ! grep -Fqx 'LLAMA_DEFAULT_MODEL="qwen2.5-coder-1.5b-instruct-q4_k_m.gguf"' "$profile_path"; then
        llama_profile_policy_valid=false
        break
      fi
      ;;
    d-i/forky/hosts/profiles/override/f2fs-de-cbook.env)
      if ! grep -Fqx 'LLAMA_RUNTIME_THREADS=2' "$profile_path" ||
         ! grep -Fqx 'LLAMA_RUNTIME_CONTEXT=4096' "$profile_path" ||
         ! grep -Fqx 'LLAMA_DEFAULT_MODEL="qwen2.5-coder-0.5b-instruct-q4_k_m.gguf"' "$profile_path"; then
        llama_profile_policy_valid=false
        break
      fi
      ;;
  esac

  llama_profile_index=$((llama_profile_index + 1))
done
if [ "$llama_profile_policy_valid" = true ] &&
   [ "$llama_profile_index" -eq 13 ] &&
   [ "$llama_cuda_profile_count" -eq 2 ] &&
   [ "$llama_ram_profile_count" -eq 11 ] &&
   llama_profile_policy_validates &&
   llama_release_class_selection_works; then
  pass "all 13 desktop profiles pin one validated llama release schema with exact CUDA/RAM artifact and runtime-class mapping"
else
  fail "all 13 desktop profiles pin one validated llama release schema with exact CUDA/RAM artifact and runtime-class mapping"
fi

fake_managed_tools="${TMP_DIR}/fake-managed-tools"
fake_bazelisk_binary="${fake_managed_tools}/bazelisk/bazel"
fake_bazel_home="${fake_managed_tools}/home"
fake_bazel_config_dir="${fake_bazel_home}/.config/bazel"
fake_bazelrc="${fake_bazel_config_dir}/bazelrc"
fake_bazel_log="${fake_managed_tools}/bazel.log"
install -d -m 0700 \
  "$(dirname "$fake_bazelisk_binary")" \
  "$fake_bazel_config_dir"

cat >"$fake_bazelisk_binary" <<'SH'
#!/bin/sh
printf '%s\n' "$@" >"$BAZEL_LOG"
SH
chmod 0755 "$fake_bazelisk_binary"

escaped_fake_bazelisk_binary=$(printf '%s\n' "$fake_bazelisk_binary" | sed 's/[&|\\]/\\&/g')
sed \
  -e "s|/usr/local/lib/bazelisk/bazel|${escaped_fake_bazelisk_binary}|g" \
  "$devops_profile" >"${fake_managed_tools}/71-devops-de.sh"
fake_devops_profile="${fake_managed_tools}/71-devops-de.sh"

cat >"$fake_bazelrc" <<'EOF'
startup --max_idle_secs=60
EOF
chmod 0600 "$fake_bazelrc"

bazel_profile_valid=true
if ! env -i \
     HOME="$fake_bazel_home" \
     USER=developer \
     LOGNAME=developer \
     XDG_CONFIG_HOME="${fake_bazel_home}/.config" \
     BAZEL_LOG="$fake_bazel_log" \
     DEVOPS_DE_BAZELISK_ENABLED=1 \
     PATH=/usr/bin:/bin \
     /bin/sh -c '
       . "$1"
       bazel build //:all
     ' sh "$fake_devops_profile" ||
   ! printf '%s\n' \
     "--bazelrc=${fake_bazelrc}" \
     build \
     //:all |
     cmp -s - "$fake_bazel_log"
then
  bazel_profile_valid=false
fi

profile_runtime_valid=true
for shell_path in /bin/sh "$(command -v bash)" "$(command -v zsh)"; do
  if ! env -i PATH=/usr/bin:/bin "$shell_path" -c '
       . "$1"
       [ -z "${BAZELISK_HOME+x}" ]
       [ -z "${CARGO_HOME+x}" ]
       devops_de_prepend_path /safe
       [ "$PATH" = "/safe:$2" ]
       devops_de_prepend_path ../unsafe && exit 1
       PATH=/usr/bin:/bin
       devops_de_prepend_path /usr/local/lib/node-26/bin
       devops_de_prepend_path /pool/db/developer/mise/data/shims
       [ "$PATH" = "/pool/db/developer/mise/data/shims:/usr/local/lib/node-26/bin:/usr/bin:/bin" ]
       ! command -v devops_de_mise_node_exec >/dev/null 2>&1
       ! command -v devops_de_corepack_exec >/dev/null 2>&1
       ! command -v bazel >/dev/null 2>&1
       devops unexpected >/dev/null 2>&1
       [ "$?" -eq 64 ]
     ' sh "$devops_profile" /usr/bin:/bin
  then
    profile_runtime_valid=false
    break
  fi
done

devops_title_hook_valid=true
devops_title_home="${TMP_DIR}/devops-title-home"
devops_title_output="${TMP_DIR}/devops-title.output"
install -d -m 0700 "$devops_title_home"
if ! env -i \
     HOME="$devops_title_home" \
     USER=developer \
     LOGNAME=developer \
     DEVOPS_DE_ACTIVE=1 \
     PATH=/usr/bin:/bin \
     zsh -f -c '
       . "$1"
       (( ${precmd_functions[(I)devops_de_set_terminal_title]} == 1 ))
       (( ${preexec_functions[(I)devops_de_set_terminal_title]} == 1 ))
     ' zsh "$devops_profile" >"$devops_title_output" ||
   ! printf '\033]0;%s\007' '[devops]' | cmp -s - "$devops_title_output"
then
  devops_title_hook_valid=false
fi

if [ "$profile_runtime_valid" = true ] &&
   [ "$bazel_profile_valid" = true ] &&
   [ "$devops_title_hook_valid" = true ]; then
  pass "sourcing the opt-in DevOps helpers keeps ordinary shells clean, keeps the Zsh [devops] title active, and injects the profile-local Bazel rc"
else
  fail "sourcing the opt-in DevOps helpers keeps ordinary shells clean, keeps the Zsh [devops] title active, and injects the profile-local Bazel rc"
fi

if devops_nested_shell_works "$devops_profile"; then
  pass "DevOps activation nests Bash and Zsh from sh, Bash, and Zsh, restores the terminal title, and preserves the ordinary parent environment"
else
  fail "DevOps activation nests Bash and Zsh from sh, Bash, and Zsh, restores the terminal title, and preserves the ordinary parent environment"
fi

if aptly_signing_key_target_import_works; then
  pass "Aptly signing-key import accepts one matching secret key and rejects mismatched or multiple primary keys"
else
  fail "Aptly signing-key import accepts one matching secret key and rejects mismatched or multiple primary keys"
fi
[ "$FAIL_COUNT" -eq 0 ]
