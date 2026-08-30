#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/class-plan-smoke.XXXXXX")
trap 'rm -rf "$TMP_DIR"' EXIT HUP INT TERM

TEST_COUNT=14
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

install_conf="$ROOT_DIR/d-i/forky/classes/install.conf"
if grep -q '^ManifestVersion: 6$' "$install_conf" &&
   grep -q '^ClassTokenFormats: bare, group/class, group:class, group.class$' "$install_conf" &&
   grep -q '^Config: classes/configs/groups.cfg$' "$install_conf" &&
   grep -q '^Config: classes/configs/profile.cfg$' "$install_conf" &&
   grep -q '^Config: classes/configs/addons.cfg$' "$install_conf" &&
   grep -q '^Config: classes/configs/apps.cfg$' "$install_conf"; then
  pass "install.conf declares manifest metadata and config sources"
else
  fail "install.conf declares manifest metadata and config sources"
fi

runtime_dir="$TMP_DIR/runtime"
plan_out="$TMP_DIR/plan.out"
if (
  set -eu
  INSTALLER_SOURCE_ROOT="$ROOT_DIR/d-i/forky"
  INSTALLER_RUNTIME_DIR="$runtime_dir"
  export INSTALLER_SOURCE_ROOT INSTALLER_RUNTIME_DIR
  # shellcheck disable=SC1090
  . "$ROOT_DIR/d-i/forky/scripts/common/lib.sh"
  installer_classes_cache_ensure
  printf '%s\n' "$(installer_classes_plan_path)"
  printf '%s\n' "$(installer_classes_conf_path)"
) >"$plan_out"; then
  plan_path=$(sed -n '1p' "$plan_out")
  state_path=$(sed -n '2p' "$plan_out")
  if [ -s "$plan_path" ] && [ -s "$state_path" ]; then
    pass "class planner materializes plan.tsv and generated state config"
  else
    fail "class planner materializes plan.tsv and generated state config"
  fi
else
  fail "class planner materializes plan.tsv and generated state config"
fi

plan_path=$(sed -n '1p' "$plan_out")
if grep -q '^manifest	version	6$' "$plan_path" &&
   grep -q '^group	disk	true	__EMPTY__	90	storage	class-auto	auto-detected storage family and host profile derivation$' "$plan_path" &&
   grep -q '^group	profile	false	__EMPTY__	95	host-profile-override	class-profile	optional concrete host profile override env$' "$plan_path" &&
   grep -q '^group	apps	false	true	105	apps	class-apps	operator-provided per-application desktop archive fragments$' "$plan_path" &&
   ! grep -q '^group	debug	' "$plan_path" &&
   ! grep -q '^class	debug	debug	' "$plan_path" &&
   grep -q '^class	apps	microsoft-edge	Microsoft Edge archive and package' "$plan_path" &&
   grep -q '^class	apps	vivaldi	Vivaldi Browser archive, package, and managed desktop policy' "$plan_path" &&
   grep -q '^class	apps	retroarch	RetroArch package, assets, and managed desktop configuration' "$plan_path" &&
   grep -q '^class	addon	timeshift	opt-in Timeshift Btrfs snapshots with managed GRUB snapshot integration' "$plan_path"; then
  pass "generated plan.tsv contains active manifest, group, and class rows without the retired debug selector"
else
  fail "generated plan.tsv contains active manifest, group, and class rows without the retired debug selector"
fi

nvme_cfg="$ROOT_DIR/d-i/forky/classes/class-auto/disk/nvme.cfg"
emmc_cfg="$ROOT_DIR/d-i/forky/classes/class-auto/disk/emmc.cfg"
storage_cfg="$ROOT_DIR/d-i/forky/classes/configs/storage.cfg"
if grep -q '^d-i anna/choose_modules multiselect partman-btrfs partman-xfs$' "$nvme_cfg" &&
   grep -Eq '(^|[[:space:]])nvme-cli([[:space:]]|$)' "$nvme_cfg" &&
   grep -Eq '(^|[[:space:]])btrfsmaintenance([[:space:]]|$)' "$nvme_cfg" &&
   ! grep -q 'f2fs-tools' "$nvme_cfg" &&
   grep -q '^d-i anna/choose_modules multiselect f2fs-modules f2fs-tools-udeb$' "$emmc_cfg" &&
   grep -Eq '(^|[[:space:]])f2fs-tools([[:space:]]|$)' "$emmc_cfg" &&
   ! grep -q 'partman-btrfs' "$emmc_cfg" &&
   ! grep -q 'partman-xfs' "$emmc_cfg" &&
   ! grep -q 'nvme-cli' "$emmc_cfg" &&
   grep -q '^Description: NVMe and fixed bare-metal Btrfs/XFS storage family$' "$storage_cfg" &&
   grep -q '^Description: dedicated eMMC F2FS storage family$' "$storage_cfg"; then
  pass "nvme and emmc storage classes keep separate partman modules, package sets, and metadata"
else
  fail "nvme and emmc storage classes keep separate partman modules, package sets, and metadata"
fi

context_runtime="$TMP_DIR/context-runtime"
context_out="$TMP_DIR/context.out"
if (
  set -eu
  INSTALLER_SOURCE_ROOT="$ROOT_DIR/d-i/forky"
  INSTALLER_RUNTIME_DIR="$context_runtime"
  export INSTALLER_SOURCE_ROOT INSTALLER_RUNTIME_DIR
  # shellcheck disable=SC1090
  . "$ROOT_DIR/d-i/forky/scripts/common/lib.sh"
  installer_auto_class_tokens() {
    printf '%s\n' amd64
    printf '%s\n' intel
    printf '%s\n' generic
    printf '%s\n' nvme
  }
  installer_cmdline_value() {
    case "$1" in
      auto-install/classes|classes)
        printf '%s\n' 'lab,desktop,standard,dhcp,timeshift'
        ;;
    esac
  }
  installer_debconf_value() { return 1; }
  installer_write_context "$ROOT_DIR/d-i/forky" >/dev/null
  sed -n 's/^selected_class_refs=//p' "$(installer_runtime_install_conf_path)"
) >"$context_out"; then
  if grep -qx 'site/lab role/desktop arch/amd64 cpu/intel gpu/generic security/standard network/dhcp disk/nvme addon/timeshift' "$context_out"; then
    pass "runtime install.conf is generated from the config-backed class plan and no longer injects the monolithic software addon for desktop selections"
  else
    fail "runtime install.conf is generated from the config-backed class plan and no longer injects the monolithic software addon for desktop selections"
  fi
else
  fail "runtime install.conf is generated from the config-backed class plan and no longer injects the monolithic software addon for desktop selections"
fi

default_runtime="$TMP_DIR/default-runtime"
default_out="$TMP_DIR/default.out"
if (
  set -eu
  INSTALLER_SOURCE_ROOT="$ROOT_DIR/d-i/forky"
  INSTALLER_RUNTIME_DIR="$default_runtime"
  export INSTALLER_SOURCE_ROOT INSTALLER_RUNTIME_DIR
  # shellcheck disable=SC1090
  . "$ROOT_DIR/d-i/forky/scripts/common/lib.sh"
  # shellcheck disable=SC1090
  . "$ROOT_DIR/d-i/forky/repo.env"
  default_disk_class=nvme
  case ",${DEBIAN_DEFAULT_CLASSES:-}," in
    *,default-f2fs,*) default_disk_class=emmc ;;
  esac
  installer_auto_class_tokens() {
    printf '%s\n' amd64
    printf '%s\n' intel
    printf '%s\n' generic
    printf '%s\n' "$default_disk_class"
  }
  installer_cmdline_value() {
    case "$1" in
      auto-install/classes|classes)
        printf '%s\n' 'default'
        ;;
    esac
  }
  installer_debconf_value() { return 1; }
  installer_write_context "$ROOT_DIR/d-i/forky" >/dev/null
  {
    sed -n 's/^classes_raw=//p' "$(installer_runtime_install_conf_path)"
    sed -n 's/^selected_class_refs=//p' "$(installer_runtime_install_conf_path)"
  }
) >"$default_out"; then
  expected_default_raw=$(
    set -eu
    # shellcheck disable=SC1090
    . "$ROOT_DIR/d-i/forky/repo.env"
    default_disk_class=nvme
    case ",${DEBIAN_DEFAULT_CLASSES:-}," in
      *,f2fs-de,*) default_disk_class=emmc ;;
    esac
    printf '%s,%s\n' "$(printf '%s' "$DEBIAN_DEFAULT_CLASSES" | tr ';' ',')" "amd64,intel,generic,$default_disk_class"
  )
  expected_default_profile=$(printf '%s\n' "$expected_default_raw" | tr ',' '\n' | sed -n 's/^\(\(btrfs\|f2fs\)-[^[:space:]]*\)$/\1/p' | head -n 1)
  expected_default_disk=$(printf '%s\n' "$expected_default_raw" | tr ',' '\n' | sed -n 's/^\(nvme\|emmc\|vm\)$/\1/p' | tail -n 1)
  if grep -qx "$expected_default_raw" "$default_out" &&
     grep -q "^site/prod role/desktop arch/amd64 cpu/intel gpu/generic security/standard network/static disk/${expected_default_disk} profile/${expected_default_profile} " "$default_out" &&
     ! grep -q ' debug/debug ' "$default_out" &&
     grep -q ' addon/software ' "$default_out"; then
    pass "classes=default expands from repo.env without the retired debug selector and preserves the normal selected-class pipeline"
  else
    fail "classes=default expands from repo.env without the retired debug selector and preserves the normal selected-class pipeline"
  fi
else
  fail "classes=default expands from repo.env before auto classes and preserves the normal selected-class pipeline"
fi

profile_runtime="$TMP_DIR/profile-runtime"
profile_out="$TMP_DIR/profile.out"
if (
  set -eu
  INSTALLER_SOURCE_ROOT="$ROOT_DIR/d-i/forky"
  INSTALLER_RUNTIME_DIR="$profile_runtime"
  export INSTALLER_SOURCE_ROOT INSTALLER_RUNTIME_DIR
  # shellcheck disable=SC1090
  . "$ROOT_DIR/d-i/forky/scripts/common/lib.sh"
  installer_auto_class_tokens() {
    printf '%s\n' amd64
    printf '%s\n' intel
    printf '%s\n' generic
    printf '%s\n' nvme
  }
  installer_cmdline_value() {
    case "$1" in
      auto-install/classes|classes)
        printf '%s\n' 'lab,desktop,standard,dhcp,btrfs-de'
        ;;
    esac
  }
  installer_debconf_value() { return 1; }
  installer_write_context "$ROOT_DIR/d-i/forky" >/dev/null
  sed -n '/^\[selected\]$/,/^\[/p' "$(installer_runtime_install_conf_path)"
) >"$profile_out"; then
  if grep -q '^host_profile=override-btrfs-de$' "$profile_out" &&
     grep -q '^host_profile_env_dir=override$' "$profile_out" &&
     grep -q '^host_profile_env_name=btrfs-de$' "$profile_out" &&
     grep -q '^host_family=btrfs$' "$profile_out" &&
     grep -q '^hook_family=btrfs$' "$profile_out"; then
    pass "profile override classes redirect the concrete host env through hosts/profiles/override"
  else
    fail "profile override classes redirect the concrete host env through hosts/profiles/override"
  fi
else
  fail "profile override classes redirect the concrete host env through hosts/profiles/override"
fi

profile_btrfs_direct_runtime="$TMP_DIR/profile-btrfs-direct-runtime"
profile_btrfs_direct_out="$TMP_DIR/profile-btrfs-direct.out"
if (
  set -eu
  INSTALLER_SOURCE_ROOT="$ROOT_DIR/d-i/forky"
  INSTALLER_RUNTIME_DIR="$profile_btrfs_direct_runtime"
  export INSTALLER_SOURCE_ROOT INSTALLER_RUNTIME_DIR
  # shellcheck disable=SC1090
  . "$ROOT_DIR/d-i/forky/scripts/common/lib.sh"
  installer_auto_class_tokens() {
    printf '%s\n' amd64
    printf '%s\n' intel
    printf '%s\n' generic
    printf '%s\n' nvme
  }
  installer_cmdline_value() {
    case "$1" in
      auto-install/classes|classes)
        printf '%s\n' 'lab,desktop,standard,dhcp'
        ;;
    esac
  }
  installer_debconf_value() { return 1; }
  installer_write_context "$ROOT_DIR/d-i/forky" >/dev/null
  sed -n '/^\[selected\]$/,/^\[/p' "$(installer_runtime_install_conf_path)"
) >"$profile_btrfs_direct_out"; then
  if grep -q '^host_profile=btrfs-desktop$' "$profile_btrfs_direct_out" &&
     grep -q '^host_profile_env_dir=btrfs$' "$profile_btrfs_direct_out" &&
     grep -q '^host_profile_env_name=desktop$' "$profile_btrfs_direct_out" &&
     grep -q '^host_family=btrfs$' "$profile_btrfs_direct_out" &&
     grep -q '^hook_family=btrfs$' "$profile_btrfs_direct_out" &&
     grep -q '^storage_class=nvme$' "$profile_btrfs_direct_out"; then
    pass "desktop role on nvme keeps the direct btrfs desktop profile and hook family"
  else
    fail "desktop role on nvme keeps the direct btrfs desktop profile and hook family"
  fi
else
  fail "desktop role on nvme keeps the direct btrfs desktop profile and hook family"
fi

profile_f2fs_runtime="$TMP_DIR/profile-f2fs-runtime"
profile_f2fs_out="$TMP_DIR/profile-f2fs.out"
if (
  set -eu
  INSTALLER_SOURCE_ROOT="$ROOT_DIR/d-i/forky"
  INSTALLER_RUNTIME_DIR="$profile_f2fs_runtime"
  export INSTALLER_SOURCE_ROOT INSTALLER_RUNTIME_DIR
  # shellcheck disable=SC1090
  . "$ROOT_DIR/d-i/forky/scripts/common/lib.sh"
  installer_auto_class_tokens() {
    printf '%s\n' amd64
    printf '%s\n' intel
    printf '%s\n' generic
    printf '%s\n' emmc
  }
  installer_cmdline_value() {
    case "$1" in
      auto-install/classes|classes)
        printf '%s\n' 'lab,desktop,standard,dhcp,f2fs-de'
        ;;
    esac
  }
  installer_debconf_value() { return 1; }
  installer_write_context "$ROOT_DIR/d-i/forky" >/dev/null
  sed -n '/^\[selected\]$/,/^\[/p' "$(installer_runtime_install_conf_path)"
) >"$profile_f2fs_out"; then
  if grep -q '^host_profile=override-f2fs-de$' "$profile_f2fs_out" &&
     grep -q '^host_profile_env_dir=override$' "$profile_f2fs_out" &&
     grep -q '^host_profile_env_name=f2fs-de$' "$profile_f2fs_out" &&
     grep -q '^host_family=f2fs$' "$profile_f2fs_out" &&
     grep -q '^hook_family=f2fs$' "$profile_f2fs_out" &&
     grep -q '^storage_class=emmc$' "$profile_f2fs_out"; then
    pass "default-f2fs override keeps the desktop eMMC profile on the f2fs hook family"
  else
    fail "default-f2fs override keeps the desktop eMMC profile on the f2fs hook family"
  fi
else
  fail "default-f2fs override keeps the desktop eMMC profile on the f2fs hook family"
fi

profile_f2fs_direct_runtime="$TMP_DIR/profile-f2fs-direct-runtime"
profile_f2fs_direct_out="$TMP_DIR/profile-f2fs-direct.out"
if (
  set -eu
  INSTALLER_SOURCE_ROOT="$ROOT_DIR/d-i/forky"
  INSTALLER_RUNTIME_DIR="$profile_f2fs_direct_runtime"
  export INSTALLER_SOURCE_ROOT INSTALLER_RUNTIME_DIR
  # shellcheck disable=SC1090
  . "$ROOT_DIR/d-i/forky/scripts/common/lib.sh"
  installer_auto_class_tokens() {
    printf '%s\n' amd64
    printf '%s\n' intel
    printf '%s\n' generic
    printf '%s\n' emmc
  }
  installer_cmdline_value() {
    case "$1" in
      auto-install/classes|classes)
        printf '%s\n' 'lab,desktop,standard,dhcp'
        ;;
    esac
  }
  installer_debconf_value() { return 1; }
  installer_write_context "$ROOT_DIR/d-i/forky" >/dev/null
  sed -n '/^\[selected\]$/,/^\[/p' "$(installer_runtime_install_conf_path)"
) >"$profile_f2fs_direct_out"; then
  if grep -q '^host_profile=f2fs-desktop$' "$profile_f2fs_direct_out" &&
     grep -q '^host_profile_env_dir=f2fs$' "$profile_f2fs_direct_out" &&
     grep -q '^host_profile_env_name=desktop$' "$profile_f2fs_direct_out" &&
     grep -q '^host_family=f2fs$' "$profile_f2fs_direct_out" &&
     grep -q '^hook_family=f2fs$' "$profile_f2fs_direct_out" &&
     grep -q '^storage_class=emmc$' "$profile_f2fs_direct_out"; then
    pass "desktop role on emmc keeps the direct f2fs desktop profile and hook family"
  else
    fail "desktop role on emmc keeps the direct f2fs desktop profile and hook family"
  fi
else
  fail "desktop role on emmc keeps the direct f2fs desktop profile and hook family"
fi

profile_f2fs_server_runtime="$TMP_DIR/profile-f2fs-server-runtime"
profile_f2fs_server_out="$TMP_DIR/profile-f2fs-server.out"
if (
  set -eu
  INSTALLER_SOURCE_ROOT="$ROOT_DIR/d-i/forky"
  INSTALLER_RUNTIME_DIR="$profile_f2fs_server_runtime"
  export INSTALLER_SOURCE_ROOT INSTALLER_RUNTIME_DIR
  # shellcheck disable=SC1090
  . "$ROOT_DIR/d-i/forky/scripts/common/lib.sh"
  installer_auto_class_tokens() {
    printf '%s\n' amd64
    printf '%s\n' intel
    printf '%s\n' generic
    printf '%s\n' emmc
  }
  installer_cmdline_value() {
    case "$1" in
      auto-install/classes|classes)
        printf '%s\n' 'lab,server,standard,dhcp'
        ;;
    esac
  }
  installer_debconf_value() { return 1; }
  installer_write_context "$ROOT_DIR/d-i/forky" >/dev/null
  sed -n '/^\[selected\]$/,/^\[/p' "$(installer_runtime_install_conf_path)"
) >"$profile_f2fs_server_out"; then
  if grep -q '^host_profile=f2fs-server$' "$profile_f2fs_server_out" &&
     grep -q '^host_profile_env_dir=f2fs$' "$profile_f2fs_server_out" &&
     grep -q '^host_profile_env_name=server$' "$profile_f2fs_server_out" &&
     grep -q '^host_family=f2fs$' "$profile_f2fs_server_out" &&
     grep -q '^hook_family=f2fs$' "$profile_f2fs_server_out" &&
     grep -q '^storage_class=emmc$' "$profile_f2fs_server_out"; then
    pass "server role on eMMC keeps the direct f2fs server profile and hook family"
  else
    fail "server role on eMMC keeps the direct f2fs server profile and hook family"
  fi
else
  fail "server role on eMMC keeps the direct f2fs server profile and hook family"
fi

profile_render_out="$TMP_DIR/profile-render.out"
profile_render_err="$TMP_DIR/profile-render.err"
if (
  set -eu
  nvidia_pci_root="$TMP_DIR/profile-render-pci"
  mkdir -p "$nvidia_pci_root"
  INSTALLER_SOURCE_ROOT="$ROOT_DIR/d-i/forky"
  INSTALLER_RUNTIME_DIR="$TMP_DIR/profile-render-runtime"
  INSTALLER_CMDLINE='classes=lab,desktop,standard,dhcp,btrfs-de primary_user=user primary_password=secret root_password=root fruux_username=alice fruux_password=token'
  INSTALLER_PCI_DEVICES_ROOT="$nvidia_pci_root"
  export INSTALLER_SOURCE_ROOT INSTALLER_RUNTIME_DIR INSTALLER_CMDLINE INSTALLER_PCI_DEVICES_ROOT
  sh "$ROOT_DIR/d-i/forky/scripts/preseed/answers.sh" render "$ROOT_DIR/d-i/forky"
) >"$profile_render_out" 2>"$profile_render_err"; then
  pass "empty class-profile fragments stay metadata-only and do not break preseed answer rendering"
else
  fail "empty class-profile fragments stay metadata-only and do not break preseed answer rendering" "$profile_render_err"
fi

apps_conflict_err="$TMP_DIR/apps-conflict.err"
if (
  set -eu
  INSTALLER_SOURCE_ROOT="$ROOT_DIR/d-i/forky"
  INSTALLER_RUNTIME_DIR="$TMP_DIR/apps-conflict-runtime"
  export INSTALLER_SOURCE_ROOT INSTALLER_RUNTIME_DIR
  # shellcheck disable=SC1090
  . "$ROOT_DIR/d-i/forky/scripts/common/lib.sh"
  installer_auto_class_tokens() {
    printf '%s\n' amd64
    printf '%s\n' intel
    printf '%s\n' generic
    printf '%s\n' nvme
  }
  installer_cmdline_value() {
    case "$1" in
      auto-install/classes|classes)
        printf '%s\n' 'lab,desktop,standard,dhcp,software,microsoft-edge'
        ;;
    esac
  }
  installer_debconf_value() { return 1; }
  installer_write_context "$ROOT_DIR/d-i/forky" >/dev/null
) >"$TMP_DIR/apps-conflict.out" 2>"$apps_conflict_err"; then
  fail "software bundle and class-apps selections are mutually exclusive"
elif grep -q 'selected class apps/microsoft-edge rejects class addon/software' "$apps_conflict_err"; then
  pass "software bundle and class-apps selections are mutually exclusive"
else
  fail "software bundle and class-apps selections are mutually exclusive"
fi

reject_root="$TMP_DIR/reject-root"
mkdir -p "$reject_root"
cp "$ROOT_DIR/d-i/forky/repo.env" "$reject_root/repo.env"
cp -a "$ROOT_DIR/d-i/forky/classes" "$reject_root/classes"
cat >>"$reject_root/classes/configs/addons.cfg" <<'EOF'

Type: class
Group: addon
Name: rejectpod
Description: reject podman when both are selected
RejectedClasses: addon/podman
EOF
cat >"$reject_root/classes/class-addon/rejectpod.cfg" <<'EOF'
d-i pkgsel/include string
d-i pkgsel/include seen true
EOF
reject_err="$TMP_DIR/reject.err"
if (
  set -eu
  INSTALLER_SOURCE_ROOT="$reject_root"
  INSTALLER_RUNTIME_DIR="$TMP_DIR/reject-runtime"
  export INSTALLER_SOURCE_ROOT INSTALLER_RUNTIME_DIR
  # shellcheck disable=SC1090
  . "$ROOT_DIR/d-i/forky/scripts/common/lib.sh"
  installer_auto_class_tokens() {
    printf '%s\n' amd64
    printf '%s\n' intel
    printf '%s\n' generic
    printf '%s\n' nvme
  }
  installer_cmdline_value() {
    case "$1" in
      auto-install/classes|classes)
        printf '%s\n' 'lab,desktop,standard,dhcp,podman,rejectpod'
        ;;
    esac
  }
  installer_debconf_value() { return 1; }
  installer_write_context "$reject_root" >/dev/null
) >"$TMP_DIR/reject.out" 2>"$reject_err"; then
  fail "config-backed rejected class rules are enforced"
elif grep -q 'selected class addon/rejectpod rejects class addon/podman' "$reject_err"; then
  pass "config-backed rejected class rules are enforced"
else
  fail "config-backed rejected class rules are enforced"
fi

[ "$FAIL_COUNT" -eq 0 ]
