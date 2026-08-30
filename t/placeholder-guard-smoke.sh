#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)

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

printf '1..%s\n' "$TEST_COUNT"

common_lib="$ROOT_DIR/d-i/forky/scripts/common/lib.sh"
target_assets="$ROOT_DIR/d-i/forky/scripts/late/target-assets.sh"
templates="$ROOT_DIR/d-i/forky/scripts/late/templates.sh"
ssh_helper="$ROOT_DIR/d-i/forky/scripts/common/ssh.sh"
account_helper="$ROOT_DIR/d-i/forky/scripts/late/account.sh"
dbus_helper="$ROOT_DIR/d-i/forky/scripts/late/dbus-broker.sh"
ch341a_helper="$ROOT_DIR/d-i/forky/scripts/late/ch341a.sh"
gitlab_runner_helper="$ROOT_DIR/d-i/forky/scripts/late/gitlab-runner.sh"
desktop_helper="$ROOT_DIR/d-i/forky/scripts/desktop/components.sh"
qemu_helper="$ROOT_DIR/d-i/forky/scripts/late/qemu.sh"
tailscale_helper="$ROOT_DIR/d-i/forky/scripts/late/tailscale.sh"

if grep -q '^installer_assert_no_unresolved_installer_placeholders() {$' "$common_lib" &&
   grep -q "__INSTALLER_\\[A-Z0-9_\\]\\\\+__" "$common_lib"; then
  pass "common installer library defines a reusable unresolved-placeholder assertion helper"
else
  fail "common installer library defines a reusable unresolved-placeholder assertion helper"
fi

if grep -q '^render_target_asset_with_placeholder_map() {$' "$target_assets" &&
   grep -q 'target_asset_assert_no_unresolved_installer_placeholders \\' "$target_assets" &&
   grep -q '"rendered target asset \${repo_path}"' "$target_assets"; then
  pass "shared placeholder-map renderer aborts when a final target asset still contains installer placeholders"
else
  fail "shared placeholder-map renderer aborts when a final target asset still contains installer placeholders"
fi

if grep -q '^render_target_template() {$' "$templates" &&
   grep -q 'installer_assert_no_unresolved_installer_placeholders "\$dest" "rendered template \${src}"' "$templates"; then
  pass "shared template renderer checks for unresolved installer placeholders after all post-processing passes"
else
  fail "shared template renderer checks for unresolved installer placeholders after all post-processing passes"
fi

if grep -q 'installer_assert_no_unresolved_installer_placeholders "\$dest" "SSH template \${src}"' "$ssh_helper" &&
   grep -q 'installer_assert_no_unresolved_installer_placeholders "\$dest" "SSH user template \${src}"' "$ssh_helper" &&
   grep -q 'installer_assert_no_unresolved_installer_placeholders "\$sudoers_tmp" "account sudoers template \${TMP_ENV_DIR}/account.sudoers.tmpl"' "$account_helper"; then
  pass "SSH and account helper renders now fail fast on unresolved placeholders"
else
  fail "SSH and account helper renders now fail fast on unresolved placeholders"
fi

if grep -q 'installer_assert_no_unresolved_installer_placeholders "\$tmp_rendered" "D-Bus template \${repo_path}"' "$dbus_helper" &&
   grep -q 'installer_assert_no_unresolved_installer_placeholders "\$tmp_rendered" "ch341a template \${repo_path}"' "$ch341a_helper" &&
   grep -q 'installer_assert_no_unresolved_installer_placeholders "\$rendered_tmp" "gitlab-runner unit template \${template_src}"' "$gitlab_runner_helper"; then
  pass "custom D-Bus, ch341a, and GitLab Runner renderers now fail fast on unresolved placeholders"
else
  fail "custom D-Bus, ch341a, and GitLab Runner renderers now fail fast on unresolved placeholders"
fi

if grep -q 'target_asset_assert_no_unresolved_installer_placeholders' "$desktop_helper" &&
   grep -Fq "grep -Eq '__INSTALLER_[A-Z0-9_]+__'" "$qemu_helper" &&
   grep -Fq "grep -Eq '__INSTALLER_[A-Z0-9_]+__'" "$tailscale_helper"; then
  pass "desktop, qemu, and tailscale renderers keep explicit unresolved-placeholder guards"
else
  fail "desktop, qemu, and tailscale renderers keep explicit unresolved-placeholder guards"
fi

missing_guards=
for helper_path in $(cd "$ROOT_DIR" && rg -l 'installer_apply_scalar_placeholders' d-i/forky/scripts | sort); do
  case "$helper_path" in
    d-i/forky/scripts/common/lib.sh)
      continue
      ;;
    d-i/forky/scripts/late/storage-maintenance.sh|d-i/forky/scripts/late/volatile-storage.sh)
      continue
      ;;
    d-i/forky/scripts/late/software.sh)
      if grep -Fq 'if installer_contains_unresolved_installer_placeholders "$tmp_rendered"; then' "$ROOT_DIR/$helper_path" &&
         grep -Fq 'software_fatal "rendered software template has unresolved installer placeholders: ${repo_path}"' "$ROOT_DIR/$helper_path"
      then
        continue
      fi
      ;;
  esac

  helper_abspath="$ROOT_DIR/$helper_path"
  if grep -q 'installer_assert_no_unresolved_installer_placeholders' "$helper_abspath" ||
     grep -q 'target_asset_assert_no_unresolved_installer_placeholders' "$helper_abspath" ||
     grep -Fq "grep -Eq '__INSTALLER_[A-Z0-9_]+__'" "$helper_abspath"; then
    continue
  fi
  missing_guards="${missing_guards}${missing_guards:+ }${helper_path}"
done

if [ -z "$missing_guards" ] &&
   grep -q 'installer_assert_no_unresolved_installer_placeholders "\$dest" "rendered template \${src}"' "$templates"; then
  pass "every direct scalar-placeholder renderer is either guarded locally or finalized by the shared template renderer"
else
  fail "every direct scalar-placeholder renderer is either guarded locally or finalized by the shared template renderer"
fi

[ "$FAIL_COUNT" -eq 0 ]
