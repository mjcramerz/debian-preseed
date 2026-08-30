#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)

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
taskrc="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/task/taskrc"
components="$ROOT_DIR/d-i/forky/scripts/desktop/components.sh"
desktop_verify="$ROOT_DIR/d-i/forky/scripts/desktop/verify.sh"
firstboot_validation="$ROOT_DIR/d-i/forky/scripts/firstboot/04-validation.sh"
profile="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.profile"
zshenv="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.zshenv"
waybar_config="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/waybar/config.tmpl"
waybar_style="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/waybar/style.css.tmpl"

printf '1..%s\n' "$TEST_COUNT"

if grep -Eq '(^|[[:space:]])taskwarrior([[:space:]]|$)' "$desktop_class" &&
   grep -Eq '(^|[[:space:]])taskwarrior-tui([[:space:]]|$)' "$desktop_class"; then
  pass "desktop role installs Taskwarrior and taskwarrior-tui"
else
  fail "desktop role installs Taskwarrior and taskwarrior-tui"
fi

if grep -q '^data.location=~/.local/share/task$' "$taskrc" &&
   grep -q '^hooks.location=~/.local/share/task/hooks$' "$taskrc" &&
   grep -q '^default.command=pending$' "$taskrc" &&
   grep -q '^uda.taskwarrior-tui.task-report.next.filter=pending$' "$taskrc" &&
   grep -Fq 'export TASKRC="${TASKRC:-$XDG_CONFIG_HOME/task/taskrc}"' "$profile" &&
   grep -Fq 'export TASKDATA="${TASKDATA:-$XDG_DATA_HOME/task}"' "$profile" &&
   grep -Fq 'export TASKRC="${TASKRC:-$XDG_CONFIG_HOME/task/taskrc}"' "$zshenv" &&
   grep -Fq 'export TASKDATA="${TASKDATA:-$XDG_DATA_HOME/task}"' "$zshenv"; then
  pass "Taskwarrior and taskwarrior-tui share the managed XDG configuration"
else
  fail "Taskwarrior and taskwarrior-tui share the managed XDG configuration"
fi

if grep -q '^report.pending.description=Pending$' "$taskrc" &&
   grep -q '^report.pending.filter=status:pending -ACTIVE$' "$taskrc" &&
   grep -q '^report.inprogress.description=In Progress$' "$taskrc" &&
   grep -q '^report.inprogress.filter=status:pending +ACTIVE$' "$taskrc" &&
   grep -q '^report.completed.description=Completed$' "$taskrc" &&
   grep -q '^report.completed.filter=status:completed$' "$taskrc" &&
   grep -q '^color.active=bold black on yellow$' "$taskrc" &&
   grep -q '^uda.taskwarrior-tui.style.report.selection=bold black on yellow$' "$taskrc" &&
   ! grep -q '^uda.taskwarrior-tui.style.report.completion-pane' "$taskrc"; then
  pass "Taskwarrior reports and TUI theme cover pending, active, and completed work"
else
  fail "Taskwarrior reports and TUI theme cover pending, active, and completed work"
fi

if grep -q 'etc/skel/.config/task/taskrc /etc/skel/.config/task/taskrc 0644' "$components" &&
   grep -q 'install -d -m 0700 /target/etc/skel/.local/share/task /target/etc/skel/.local/share/task/hooks' "$components" &&
   grep -q '\.config/task \\' "$components" &&
   grep -q '"\$account_home/.local/share/task" \\' "$components" &&
   grep -q '"\$account_home/.local/share/task/hooks" \\' "$components" &&
   grep -q '/etc/skel/.config/task/taskrc' "$desktop_verify" &&
   grep -q '"\$account_home/.config/task/taskrc"' "$desktop_verify" &&
   grep -q 'Taskwarrior data directory mode is not 0700' "$desktop_verify" &&
   grep -q 'Taskwarrior hooks directory mode is not 0700' "$desktop_verify" &&
   grep -q '  task \\' "$desktop_verify" &&
   grep -q '  taskwarrior-tui \\' "$desktop_verify" &&
   grep -q '    task \\' "$firstboot_validation" &&
   grep -q '    taskwarrior-tui \\' "$firstboot_validation"; then
  pass "desktop staging and validation install taskrc for the primary desktop user"
else
  fail "desktop staging and validation install taskrc for the primary desktop user"
fi

if python3 - "$waybar_config" <<'PY' >/dev/null 2>&1
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    config = handle.read()

assert (
    '"modules": [\n'
    '      "custom/apps",\n'
    '      "custom/app-terminal",\n'
    '      "custom/app-files",\n'
    '      "custom/app-tuta",\n'
    '      "custom/app-notes",\n'
    '      "custom/app-sleek"'
) in config
assert '"custom/tasks"' not in config
assert '"on-click": "labwc-terminal -e taskwarrior-tui"' not in config
assert (
    '"custom/wayscriber": {\n'
    '    "format": "",\n'
    '    "tooltip": true,\n'
    '    "tooltip-format": "Wayscriber",\n'
    '    "on-click": "labwc-wayscriber-toggle"\n'
    "  }"
) in config
PY
   grep -Fq '"custom/launcher", "ext/workspaces", "custom/wayscriber", "group/apps", "wlr/taskbar"' "$components" &&
   ! grep -q '^#custom-tasks' "$waybar_style" &&
   grep -q '^#custom-wayscriber {$' "$waybar_style"; then
  pass "Taskwarrior remains installed without occupying Waybar"
else
  fail "Taskwarrior remains installed without occupying Waybar"
fi
