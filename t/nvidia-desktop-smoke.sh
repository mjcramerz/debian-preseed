#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/nvidia-desktop-smoke.XXXXXX")
trap 'rm -rf "$TMP_DIR"' EXIT HUP INT TERM

TEST_COUNT=15
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
  if [ "$#" -gt 1 ] && [ -n "${2:-}" ] && [ -r "$2" ]; then
    sed 's/^/# /' "$2"
  fi
}

printf '1..%s\n' "$TEST_COUNT"

nvidia_modprobe_fallback_removes_assets() {
  awk '
    $0 ~ /^[[:space:]]*if \[ "\$target_enable_nvidia" = true \]; then$/ {
      in_nvidia_block = 1
      next
    }
    in_nvidia_block && $0 ~ /^[[:space:]]*else$/ {
      in_fallback = 1
      next
    }
    in_fallback && /rm -f/ {
      removes_assets = 1
    }
    in_fallback && /"\$\{DIR_MODPROBE_D\}\/50-nouveau-blacklist\.conf"/ {
      removes_nouveau_blacklist = 1
    }
    in_fallback && /"\$\{DIR_MODPROBE_D\}\/nvidia\.conf"/ {
      removes_nvidia_config = 1
    }
    in_fallback && $0 ~ /^[[:space:]]*fi$/ {
      if (removes_assets && removes_nouveau_blacklist && removes_nvidia_config) {
        exit 0
      }
      exit 1
    }
    END {
      if (in_fallback && removes_assets && removes_nouveau_blacklist && removes_nvidia_config) {
        exit 0
      }
      exit 1
    }
  ' "$1"
}

nvidia_class="$ROOT_DIR/d-i/forky/classes/class-addon/nvidia.cfg"
nvidia_legacy_class="$ROOT_DIR/d-i/forky/classes/class-addon/nvidia-legacy.cfg"
cuda_class="$ROOT_DIR/d-i/forky/classes/class-addon/cuda.cfg"
nvidia_legacy_pref="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apt/preferences.d/desktop/nvidia-legacy.pref"
addons_cfg="$ROOT_DIR/d-i/forky/classes/configs/addons.cfg"
nvidia_pci_root="$TMP_DIR/pci-nvidia"
mkdir -p "$nvidia_pci_root/0000:01:00.0"
printf '0x10de\n' >"$nvidia_pci_root/0000:01:00.0/vendor"
printf '0x030000\n' >"$nvidia_pci_root/0000:01:00.0/class"
if grep -Eq '(^|[[:space:]])nvidia-dkms-595([[:space:]]|$)' "$nvidia_class" &&
   grep -Eq '(^|[[:space:]])nvidia-kernel-common-595([[:space:]]|$)' "$nvidia_class" &&
   ! grep -Eq '(^|[[:space:]])nvidia-suspend-common([[:space:]]|$)' "$nvidia_class" &&
   grep -Eq '(^|[[:space:]])nvidia-vaapi-driver([[:space:]]|$)' "$nvidia_class" &&
   grep -Eq '(^|[[:space:]])libgl1([[:space:]]|$)' "$nvidia_class" &&
   grep -Eq '(^|[[:space:]])libegl1([[:space:]]|$)' "$nvidia_class" &&
   grep -Eq '(^|[[:space:]])libgles2([[:space:]]|$)' "$nvidia_class" &&
   grep -Eq '(^|[[:space:]])libvulkan1([[:space:]]|$)' "$nvidia_class" &&
   ! grep -Eq '(^|[[:space:]])mesa-vulkan-drivers([[:space:]]|$)' "$nvidia_class" &&
   ! grep -Eq '(^|[[:space:]])vulkan-tools([[:space:]]|$)' "$nvidia_class" &&
   grep -Eq '(^|[[:space:]])libnvidia-gl-595([[:space:]]|$)' "$nvidia_class" &&
   grep -Eq '(^|[[:space:]])libnvidia-egl-wayland1([[:space:]]|$)' "$nvidia_class" &&
   grep -Eq '(^|[[:space:]])nvidia-kernel-source-595([[:space:]]|$)' "$nvidia_class" &&
   ! grep -Eq '(^|[[:space:]])bumblebee([[:space:]]|$)' "$nvidia_class" &&
   grep -q '^DebianAptPreferences: nvidia, x11$' "$addons_cfg"; then
  pass "nvidia addon keeps the loader ABI while staging the managed Wayland and media stack"
else
  fail "nvidia addon keeps the loader ABI while staging the managed Wayland and media stack"
fi

if grep -Eq '(^|[[:space:]])cuda-cudart-13-1([[:space:]]|$)' "$cuda_class" &&
   grep -Eq '(^|[[:space:]])cuda-cudart-dev-13-1([[:space:]]|$)' "$cuda_class" &&
   grep -Eq '(^|[[:space:]])cuda-nvcc-13-1([[:space:]]|$)' "$cuda_class" &&
   grep -Eq '(^|[[:space:]])libcublas-13-1([[:space:]]|$)' "$cuda_class" &&
   grep -Eq '(^|[[:space:]])libcublas-dev-13-1([[:space:]]|$)' "$cuda_class" &&
   grep -q '^d-i apt-setup/local13/key string https://developer.download.nvidia.com/compute/cuda/repos/debian13/x86_64/8793F200.pub$' "$cuda_class" &&
   grep -q '^RequiresClasses: addon/nvidia, arch/amd64$' "$addons_cfg" &&
   grep -q '^DebianAptPreferences: cuda, nvidia, x11$' "$addons_cfg"; then
  pass "cuda addon is opt-in, build-capable, requires nvidia on amd64, and declares deterministic apt pinning"
else
  fail "cuda addon is opt-in, build-capable, requires nvidia on amd64, and declares deterministic apt pinning"
fi

if grep -Eq '(^|[[:space:]])pahole([[:space:]]|$)' "$nvidia_legacy_class" &&
   grep -Eq '(^|[[:space:]])clang([[:space:]]|$)' "$nvidia_legacy_class" &&
   grep -Eq '(^|[[:space:]])lld([[:space:]]|$)' "$nvidia_legacy_class" &&
   grep -Eq '(^|[[:space:]])llvm([[:space:]]|$)' "$nvidia_legacy_class" &&
   grep -Eq '(^|[[:space:]])pahole([[:space:]]|$)' "$nvidia_legacy_class" &&
   grep -Eq '(^|[[:space:]])nvidia-dkms-580([[:space:]]|$)' "$nvidia_legacy_class" &&
   grep -Eq '(^|[[:space:]])libvulkan1([[:space:]]|$)' "$nvidia_legacy_class" &&
   ! grep -Eq '(^|[[:space:]])mesa-vulkan-drivers([[:space:]]|$)' "$nvidia_legacy_class" &&
   ! grep -Eq '(^|[[:space:]])vulkan-tools([[:space:]]|$)' "$nvidia_legacy_class" &&
   grep -Eq '(^|[[:space:]])libnvidia-gl-580([[:space:]]|$)' "$nvidia_legacy_class" &&
   grep -q '^Pin: release o=xanmod$' "$nvidia_legacy_pref"; then
  pass "legacy nvidia addon keeps the loader ABI without Vulkan drivers or tools"
else
  fail "legacy nvidia addon keeps the loader ABI without Vulkan drivers or tools"
fi

desktop_packages="$ROOT_DIR/d-i/forky/classes/class-select/role/desktop.cfg"
if grep -Eq '(^|[[:space:]])mesa-utils([[:space:]]|$)' "$desktop_packages" &&
   ! grep -Eq '(^|[[:space:]])mesa-va-drivers([[:space:]]|$)' "$desktop_packages" &&
   ! grep -Eq '(^|[[:space:]])mesa-vdpau-drivers([[:space:]]|$)' "$desktop_packages" &&
   grep -Eq '(^|[[:space:]])libgl1([[:space:]]|$)' "$desktop_packages" &&
   grep -Eq '(^|[[:space:]])libegl1([[:space:]]|$)' "$desktop_packages" &&
   grep -Eq '(^|[[:space:]])libgles2([[:space:]]|$)' "$desktop_packages" &&
   grep -Eq '(^|[[:space:]])libgbm1([[:space:]]|$)' "$desktop_packages" &&
   grep -Eq '(^|[[:space:]])libdrm2([[:space:]]|$)' "$desktop_packages" &&
   grep -Eq '(^|[[:space:]])libgl1-mesa-dri([[:space:]]|$)' "$desktop_packages" &&
   grep -Eq '(^|[[:space:]])vainfo([[:space:]]|$)' "$desktop_packages" &&
   grep -Eq '(^|[[:space:]])libva-wayland2([[:space:]]|$)' "$desktop_packages" &&
   ! grep -Eq '(^|[[:space:]])libvulkan1([[:space:]]|$)' "$desktop_packages" &&
   ! grep -Eq '(^|[[:space:]])mesa-vulkan-drivers([[:space:]]|$)' "$desktop_packages" &&
   ! grep -Eq '(^|[[:space:]])vulkan-tools([[:space:]]|$)' "$desktop_packages"; then
  pass "desktop role leaves the loader ABI to GPU classes and excludes Vulkan drivers"
else
  fail "desktop role leaves the loader ABI to GPU classes and excludes Vulkan drivers"
fi

nvidia_grub="$ROOT_DIR/d-i/forky/hooks/hardware/gpu/nvidia/target/etc/default/grub.d/87-gpu-nvidia.cfg"
if grep -q 'nvidia-drm.modeset=1 nvidia-drm.fbdev=1 pci=realloc=on' "$nvidia_grub" &&
   [ "$(grep -c 'pci=realloc=on' "$nvidia_grub")" -eq 3 ]; then
  pass "nvidia GRUB policy forces PCI resource reallocation for the managed desktop profiles"
else
  fail "nvidia GRUB policy forces PCI resource reallocation for the managed desktop profiles"
fi

intel_gpu_class="$ROOT_DIR/d-i/forky/classes/class-auto/gpu/intel-uhd.cfg"
if grep -Eq '(^|[[:space:]])firmware-intel-graphics([[:space:]]|$)' "$intel_gpu_class" &&
   grep -Eq '(^|[[:space:]])intel-media-va-driver-non-free([[:space:]]|$)' "$intel_gpu_class" &&
   grep -Eq '(^|[[:space:]])mesa-utils([[:space:]]|$)' "$intel_gpu_class" &&
   grep -Eq '(^|[[:space:]])mesa-utils-extra([[:space:]]|$)' "$intel_gpu_class" &&
   grep -Eq '(^|[[:space:]])libgl1([[:space:]]|$)' "$intel_gpu_class" &&
   grep -Eq '(^|[[:space:]])libegl1([[:space:]]|$)' "$intel_gpu_class" &&
   grep -Eq '(^|[[:space:]])libgles2([[:space:]]|$)' "$intel_gpu_class" &&
   grep -Eq '(^|[[:space:]])libgbm1([[:space:]]|$)' "$intel_gpu_class" &&
   grep -Eq '(^|[[:space:]])libdrm2([[:space:]]|$)' "$intel_gpu_class" &&
   grep -Eq '(^|[[:space:]])libgl1-mesa-dri([[:space:]]|$)' "$intel_gpu_class" &&
   grep -Eq '(^|[[:space:]])libvulkan1([[:space:]]|$)' "$intel_gpu_class" &&
   ! grep -Eq '(^|[[:space:]])mesa-vulkan-drivers([[:space:]]|$)' "$intel_gpu_class" &&
   ! grep -Eq '(^|[[:space:]])vulkan-tools([[:space:]]|$)' "$intel_gpu_class" &&
   ! grep -Eq '(^|[[:space:]])igt-gpu-tools([[:space:]]|$)' "$intel_gpu_class" &&
   ! grep -Eq '(^|[[:space:]])intel-opencl-icd([[:space:]]|$)' "$intel_gpu_class" &&
   ! grep -Eq '(^|[[:space:]])libze1([[:space:]]|$)' "$intel_gpu_class" &&
   ! grep -Eq '(^|[[:space:]])libze-intel-gpu1([[:space:]]|$)' "$intel_gpu_class" &&
   ! grep -Eq '(^|[[:space:]])libze-intel-gpu-raytracing([[:space:]]|$)' "$intel_gpu_class" &&
   ! grep -Eq '(^|[[:space:]])intel-ocloc([[:space:]]|$)' "$intel_gpu_class"; then
  pass "intel auto-GPU class ships the loader ABI with OpenGL and media runtimes"
else
  fail "intel auto-GPU class ships the loader ABI with OpenGL and media runtimes"
fi

thinkpad_acpi_modprobe="$ROOT_DIR/d-i/forky/hooks/hardware/cpu/intel/target/etc/modprobe.d/thinkpad-acpi.conf"
intel_i915_modprobe="$ROOT_DIR/d-i/forky/hooks/hardware/gpu/intel-uhd/target/etc/modprobe.d/i915.conf"
intel_gpu_grub="$ROOT_DIR/d-i/forky/hooks/hardware/gpu/intel-uhd/target/etc/default/grub.d/85-gpu-intel.cfg"
btrfs_family="$ROOT_DIR/d-i/forky/scripts/late/btrfs-family.sh"
if ! grep -q 'enable_guc' "$intel_i915_modprobe" &&
   ! grep -q 'enable_guc' "$intel_gpu_grub" &&
   grep -q '^options thinkpad_acpi fan_control=1 brightness_enable=1$' "$thinkpad_acpi_modprobe" &&
   grep -q 'FILE_MODPROBE_THINKPAD_ACPI' "$btrfs_family" &&
   grep -q 'FILE_MODPROBE_THINKPAD_ACPI' "$ROOT_DIR/d-i/forky/scripts/late/f2fs-family.sh" &&
   grep -q 'thinkpad-acpi.conf' "$btrfs_family" &&
   grep -q 'thinkpad-acpi.conf' "$ROOT_DIR/d-i/forky/scripts/late/f2fs-family.sh" &&
   ! grep -q 'target_enable_vfio=true' "$btrfs_family"; then
  pass "desktop Intel policy keeps ThinkPad fan control enabled without forcing GuC or bare-metal VFIO"
else
  fail "desktop Intel policy keeps ThinkPad fan control enabled without forcing GuC or bare-metal VFIO"
fi

f2fs_family="$ROOT_DIR/d-i/forky/scripts/late/f2fs-family.sh"
nouveau_blacklist="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/modprobe.d/50-nouveau-blacklist.conf"
fallback_nvidia_blacklist="$ROOT_DIR/d-i/forky/hooks/hardware/blacklist/nvidia.conf"
if grep -q 'if \[ "$NVIDIA_ADDON_SELECTED" = true \] && \[ "$NVIDIA_GPU_DETECTED" = true \]; then' "$btrfs_family" &&
   grep -q 'if \[ "$NVIDIA_ADDON_SELECTED" = true \] && \[ "$NVIDIA_GPU_DETECTED" = true \]; then' "$f2fs_family" &&
   grep -q 'if \[ "$target_enable_nvidia" = true \]; then' "$btrfs_family" &&
   grep -q 'if \[ "$target_enable_nvidia" = true \]; then' "$f2fs_family" &&
   grep -q 'etc/modprobe.d/50-nouveau-blacklist.conf' "$btrfs_family" &&
   grep -q 'etc/modprobe.d/50-nouveau-blacklist.conf' "$f2fs_family" &&
   grep -q '^blacklist nouveau$' "$nouveau_blacklist" &&
   ! grep -q '^options nouveau modeset=0$' "$nouveau_blacklist" &&
   ! grep -q '^blacklist nouveau$' "$fallback_nvidia_blacklist" &&
   ! grep -q '^options nouveau modeset=0$' "$fallback_nvidia_blacklist" &&
   grep -q '^blacklist nvidia$' "$fallback_nvidia_blacklist" &&
   grep -q '^blacklist nvidia_drm$' "$fallback_nvidia_blacklist" &&
   grep -q '^blacklist nvidia_modeset$' "$fallback_nvidia_blacklist" &&
   grep -q '^blacklist nvidia_uvm$' "$fallback_nvidia_blacklist" &&
   grep -q '^blacklist nvidia_peermem$' "$fallback_nvidia_blacklist" &&
   nvidia_modprobe_fallback_removes_assets "$btrfs_family" &&
   nvidia_modprobe_fallback_removes_assets "$f2fs_family"; then
  pass "selected-and-detected NVIDIA stages modprobe policy; unavailable targets remove it and the fallback blacklist stays NVIDIA-only"
else
  fail "selected-and-detected NVIDIA stages modprobe policy; unavailable targets remove it and the fallback blacklist stays NVIDIA-only"
fi

nvidia_pref="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apt/preferences.d/desktop/nvidia.pref"
if grep -q '^Pin: release o=xanmod$' "$nvidia_pref" &&
   grep -q '^Pin-Priority: 900$' "$nvidia_pref" &&
   grep -q '^Package: nvidia-dkms-595 nvidia-kernel-common-595 nvidia-utils-595 libnvidia-gl-595 libnvidia-compute-595 nvidia-compute-utils-595 nvidia-vaapi-driver libnvidia-egl-wayland1 nvidia-firmware-595-595.84 libnvidia-common-595 libnvidia-encode-595 libnvidia-decode-595 libnvidia-extra-595 libnvidia-fbc1-595 nvidia-kernel-source-595$' "$nvidia_pref"; then
  pass "nvidia apt preference prefers the XanMod NVIDIA driver set"
else
  fail "nvidia apt preference prefers the XanMod NVIDIA driver set"
fi

cuda_pref="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apt/preferences.d/desktop/cuda.pref"
if grep -q '^Pin: release o=NVIDIA,l=NVIDIA CUDA$' "$cuda_pref" &&
   grep -q '^Pin-Priority: 900$' "$cuda_pref" &&
   grep -q '^Package: cuda-cudart-13-1 cuda-nvrtc-13-1 cuda-opencl-13-1 libcublas-13-1 libcufft-13-1 libcufile-13-1 libcuobjclient-13-1 libcurand-13-1 libcusolver-13-1 libcusparse-13-1 libnpp-13-1 libnvjitlink-13-1 libnvfatbin-13-1 libnvjpeg-13-1 libnccl2$' "$cuda_pref"; then
  pass "cuda apt preference prefers the NVIDIA CUDA userspace runtime set"
else
  fail "cuda apt preference prefers the NVIDIA CUDA userspace runtime set"
fi

prefs_out="$TMP_DIR/prefs.out"
prefs_err="$TMP_DIR/prefs.err"
if (
  set -eu
  INSTALLER_SOURCE_ROOT="$ROOT_DIR/d-i/forky"
  INSTALLER_RUNTIME_DIR="$TMP_DIR/runtime-prefs"
  INSTALLER_PCI_DEVICES_ROOT="$nvidia_pci_root"
  INSTALLER_SELECTED_CLASS_REFS='addon/nvidia'
  export INSTALLER_SOURCE_ROOT INSTALLER_RUNTIME_DIR INSTALLER_PCI_DEVICES_ROOT INSTALLER_SELECTED_CLASS_REFS
  # shellcheck disable=SC1090
  . "$ROOT_DIR/d-i/forky/scripts/common/lib.sh"
  installer_configured_apt_preferences | paste -sd, -
) >"$prefs_out" 2>"$prefs_err"; then
  if [ "$(cat "$prefs_out")" = "forky.pref,trixie.pref,sid.pref,experimental.pref,cramerz.pref,dbus.pref,x11.pref,vulkan.pref,nvidia.pref" ]; then
    pass "nvidia addon resolves the dedicated apt preference file"
  else
    fail "nvidia addon resolves the dedicated apt preference file" "$prefs_out"
  fi
else
  fail "nvidia addon resolves the dedicated apt preference file" "$prefs_err"
fi

hybrid_out="$TMP_DIR/hybrid.out"
hybrid_err="$TMP_DIR/hybrid.err"
if (
  set -eu
  answers_file=$(
    INSTALLER_RUNTIME_DIR="$TMP_DIR/runtime-hybrid" \
    INSTALLER_SOURCE_ROOT="$ROOT_DIR/d-i/forky" \
    INSTALLER_CMDLINE='classes=lab,desktop,standard,dhcp,software,nvidia,cuda,arch/amd64,cpu/intel,gpu/intel-uhd,disk/vm primary_user=user primary_password=secret root_password=root fruux_username=alice fruux_password=token' \
      sh "$ROOT_DIR/d-i/forky/scripts/preseed/answers.sh" render "$ROOT_DIR/d-i/forky" 2>"$hybrid_err"
  )
  printf '%s\n' "$answers_file" >"$hybrid_out"
); then
  hybrid_answers=$(sed -n '1p' "$hybrid_out")
  if grep -Eq '(^|[[:space:]])firmware-intel-graphics([[:space:]]|$)' "$hybrid_answers" &&
     grep -Eq '(^|[[:space:]])intel-media-va-driver-non-free([[:space:]]|$)' "$hybrid_answers" &&
     grep -Eq '(^|[[:space:]])mesa-utils([[:space:]]|$)' "$hybrid_answers" &&
     grep -Eq '(^|[[:space:]])mesa-utils-extra([[:space:]]|$)' "$hybrid_answers" &&
     grep -Eq '(^|[[:space:]])libgl1([[:space:]]|$)' "$hybrid_answers" &&
     grep -Eq '(^|[[:space:]])libegl1([[:space:]]|$)' "$hybrid_answers" &&
     grep -Eq '(^|[[:space:]])libgles2([[:space:]]|$)' "$hybrid_answers" &&
     grep -Eq '(^|[[:space:]])libgbm1([[:space:]]|$)' "$hybrid_answers" &&
     grep -Eq '(^|[[:space:]])libdrm2([[:space:]]|$)' "$hybrid_answers" &&
     grep -Eq '(^|[[:space:]])libgl1-mesa-dri([[:space:]]|$)' "$hybrid_answers" &&
     grep -Eq '(^|[[:space:]])libvulkan1([[:space:]]|$)' "$hybrid_answers" &&
     ! grep -Eq '(^|[[:space:]])mesa-vulkan-drivers([[:space:]]|$)' "$hybrid_answers" &&
     ! grep -Eq '(^|[[:space:]])vulkan-tools([[:space:]]|$)' "$hybrid_answers" &&
     ! grep -Eq '(^|[[:space:]])igt-gpu-tools([[:space:]]|$)' "$hybrid_answers" &&
     ! grep -Eq '(^|[[:space:]])intel-opencl-icd([[:space:]]|$)' "$hybrid_answers" &&
     ! grep -Eq '(^|[[:space:]])libze-intel-gpu1([[:space:]]|$)' "$hybrid_answers" &&
     ! grep -Eq '(^|[[:space:]])intel-ocloc([[:space:]]|$)' "$hybrid_answers"; then
    pass "hybrid Intel and NVIDIA renders retain the loader ABI without Vulkan drivers or tools"
  else
    fail "hybrid Intel and NVIDIA renders retain the loader ABI without Vulkan drivers or tools" "$hybrid_answers"
  fi
else
  fail "hybrid Intel and NVIDIA renders retain the loader ABI without Vulkan drivers or tools" "$hybrid_err"
fi

legacy_out="$TMP_DIR/legacy.out"
legacy_err="$TMP_DIR/legacy.err"
if (
  set -eu
  answers_file=$(
    INSTALLER_PCI_DEVICES_ROOT="$nvidia_pci_root" \
    INSTALLER_RUNTIME_DIR="$TMP_DIR/runtime-legacy" \
    INSTALLER_SOURCE_ROOT="$ROOT_DIR/d-i/forky" \
    INSTALLER_CMDLINE='classes=lab,desktop,standard,dhcp,software,nvidia-legacy,cuda-legacy,arch/amd64,cpu/intel,gpu/generic,disk/nvme primary_user=user primary_password=secret root_password=root fruux_username=alice fruux_password=token' \
      sh "$ROOT_DIR/d-i/forky/scripts/preseed/answers.sh" render "$ROOT_DIR/d-i/forky" 2>"$legacy_err"
  )
  printf '%s\n' "$answers_file" >"$legacy_out"
); then
  legacy_answers=$(sed -n '1p' "$legacy_out")
  if grep -Eq '(^|[[:space:]])linux-xanmod-x64v3([[:space:]]|$)' "$legacy_answers" &&
     grep -Eq '(^|[[:space:]])pahole([[:space:]]|$)' "$legacy_answers" &&
     grep -Eq '(^|[[:space:]])nvidia-dkms-580([[:space:]]|$)' "$legacy_answers" &&
     grep -Eq '(^|[[:space:]])cuda-cudart-12-8([[:space:]]|$)' "$legacy_answers" &&
     grep -Eq '(^|[[:space:]])cuda-cudart-12-9([[:space:]]|$)' "$legacy_answers" &&
     ! grep -Eq '(^|[[:space:]])linux-image-amd64([[:space:]]|$)' "$legacy_answers"; then
    pass "legacy NVIDIA and CUDA renders keep the XanMod kernel while pulling the Pascal CUDA 12.8/12.9 stacks"
  else
    fail "legacy NVIDIA and CUDA renders keep the XanMod kernel while pulling the Pascal CUDA 12.8/12.9 stacks" "$legacy_answers"
  fi
else
  fail "legacy NVIDIA and CUDA renders keep the XanMod kernel while pulling the Pascal CUDA 12.8/12.9 stacks" "$legacy_err"
fi

waybar_template="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/waybar/config.tmpl"
waybar_style_template="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/waybar/style.css.tmpl"
desktop_detect="$ROOT_DIR/d-i/forky/scripts/desktop/detect.sh"
desktop_components="$ROOT_DIR/d-i/forky/scripts/desktop/components.sh"
software_late_helper="$ROOT_DIR/d-i/forky/scripts/late/software.sh"
if grep -q '"custom/launcher"' "$waybar_template" &&
   grep -q '"group/apps"' "$waybar_template" &&
   grep -q '"click-to-reveal": true' "$waybar_template" &&
   grep -q '"format": ""' "$waybar_template" &&
   grep -q '"custom/app-terminal"' "$waybar_template" &&
   grep -q '"custom/app-files"' "$waybar_template" &&
   grep -q '"custom/app-tuta"' "$waybar_template" &&
   grep -q '"custom/app-notes"' "$waybar_template" &&
   grep -q '"custom/app-sleek"' "$waybar_template" &&
   grep -q '"format": ""' "$waybar_template" &&
   grep -q '"format": ""' "$waybar_template" &&
   grep -q '"format": ""' "$waybar_template" &&
   grep -q '"format": ""' "$waybar_template" &&
   grep -q '"format": ""' "$waybar_template" &&
   grep -q '"on-click": "__INSTALLER_LABWC_MANAGED_APP_DEFAULT_EXEC__ tutanota"' "$waybar_template" &&
   grep -q '"on-click": "__INSTALLER_LABWC_MANAGED_APP_DEFAULT_EXEC__ sleek"' "$waybar_template" &&
   ! grep -q 'labwc-managed-app nvidia' "$waybar_template" &&
   grep -q '^desktop_resolve_managed_app_default_exec() {$' "$desktop_detect" &&
   grep -q 'desktop_resolve_managed_app_default_exec' "$software_late_helper" &&
   grep -q 'LABWC_MANAGED_APP_DEFAULT_EXEC "$(desktop_double_quote_escape' "$desktop_components" &&
   ! grep -q '"custom/tasks"' "$waybar_template" &&
   ! grep -q '"image#app-' "$waybar_template" &&
   ! grep -q '"custom/files"' "$waybar_template" &&
   ! grep -q '"custom/terminal"' "$waybar_template" &&
   ! grep -q '#custom-sandbox-menu' "$waybar_style_template" &&
   ! grep -q '#custom-sandbox-state' "$waybar_style_template" &&
   ! grep -q 'background-image:' "$waybar_style_template"; then
  pass "Waybar keeps the Apps drawer glyph-only while resolving GPU shortcuts from validated acceleration policy"
else
  fail "Waybar keeps the Apps drawer glyph-only while resolving GPU shortcuts from validated acceleration policy"
fi

chromium_flags="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/chromium.d/90-performance-flags.tmpl"
managed_app_wrapper="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-managed-app"
managed_app_package_parent="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/lib/python3.14/dist-packages"
managed_app_package="$managed_app_package_parent/labwc_managed_app"
managed_app="$TMP_DIR/labwc-managed-app-package.py"
cat "$managed_app_wrapper" "$managed_app_package"/*.py >"$managed_app"
launcher_sync="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-sync-application-launchers"
if grep -q '^CHROMIUM_FLAGS=.*--ozone-platform=wayland' "$chromium_flags" &&
   grep -q '^CHROMIUM_FLAGS=.*--enable-wayland-ime' "$chromium_flags" &&
   grep -q '^CHROMIUM_FLAGS=.*--enable-features=UseOzonePlatform' "$chromium_flags" &&
   ! grep -q '^CHROMIUM_FLAGS=.*VaapiVideoDecoder' "$chromium_flags" &&
   ! grep -q '^CHROMIUM_FLAGS=.*--enable-zero-copy' "$chromium_flags" &&
   grep -q '^CHROMIUM_FLAGS=.*--use-gl=angle' "$chromium_flags" &&
   ! grep -q '^CHROMIUM_FLAGS=.*--use-angle=vulkan' "$chromium_flags" &&
   grep -q '^CHROMIUM_FLAGS=.*--use-angle=gl' "$chromium_flags" &&
   grep -q '^CHROMIUM_FLAGS=.*WaylandWpColorManagerV1' "$chromium_flags" &&
   grep -q '^BROWSER_PROFILES = {$' "$managed_app" &&
   grep -q 'VaapiIgnoreDriverChecks' "$managed_app" &&
   grep -q '"--enable-zero-copy"' "$managed_app" &&
   grep -q '"--disable-gpu-driver-bug-workarounds"' "$managed_app" &&
   grep -q '"--use-gl=angle"' "$managed_app" &&
   grep -q '"--use-angle=gl"' "$managed_app" &&
   ! grep -q '"--use-angle=vulkan"' "$managed_app" &&
   grep -q '^VULKAN_DISABLE_FEATURES = ($' "$managed_app" &&
   grep -q '"DefaultANGLEVulkan"' "$managed_app" &&
   grep -q '"VulkanFromANGLE"' "$managed_app" &&
   grep -q 'args.extend(profile.get("launch_extra_args", ()))' "$managed_app" &&
   grep -q '^def validate_managed_arguments(mode: str, extra_args: list\[str\]) -> None:$' "$managed_app" &&
   grep -q '"DRI_PRIME": "0"' "$managed_app" &&
   grep -q '__NV_PRIME_RENDER_OFFLOAD' "$managed_app" &&
   grep -q '__GLX_VENDOR_LIBRARY_NAME' "$managed_app" &&
   grep -q 'LIBVA_DRIVER_NAME' "$managed_app" &&
   grep -q 'NVD_BACKEND' "$managed_app" &&
   grep -q 'MOZ_DISABLE_RDD_SANDBOX' "$managed_app" &&
   grep -q '"IntelAccelerated": ("intel", "IntelAccelerated")' "$launcher_sync" &&
   grep -q '"NvidiaAccelerated": ("nvidia", "NvidiaAccelerated")' "$launcher_sync" &&
   grep -q '"microsoft-edge.desktop"' "$launcher_sync" &&
   grep -q '"microsoft-edge-stable.desktop"' "$launcher_sync" &&
   grep -q '"com.microsoft.Edge.desktop"' "$launcher_sync" &&
   grep -q '"vivaldi-stable.desktop"' "$launcher_sync" &&
   grep -q '"bitwarden.desktop"' "$launcher_sync" &&
   grep -q '"tuta-mail.desktop"' "$launcher_sync" &&
   grep -q '"Filen.desktop"' "$launcher_sync" &&
   grep -q '"discord.desktop"' "$launcher_sync" &&
   python3 - "$managed_app_package_parent" <<'PY'
import sys

sys.path.insert(0, sys.argv[1])
from labwc_managed_app.commands import build_argv
from labwc_managed_app.electron import ELECTRON_OLD_SPACE_SIZE_MB

for mode in ("launch", "intel", "nvidia"):
    discord_argv = build_argv("discord", mode, [])
    assert "--ozone-platform=wayland" in discord_argv
    for forbidden_argument in (
        "--disable-gpu",
        "--disable-software-rasterizer",
        "--no-sandbox",
    ):
        assert forbidden_argument not in discord_argv
for app_name in ("chromium", "microsoft-edge", "vivaldi", *ELECTRON_OLD_SPACE_SIZE_MB):
    for mode in ("launch", "intel", "nvidia"):
        argv = build_argv(app_name, mode, [])
        disabled_features = next(
            argument for argument in argv if argument.startswith("--disable-features=")
        )
        for feature_name in ("Vulkan", "DefaultANGLEVulkan", "VulkanFromANGLE"):
            assert feature_name in disabled_features
        assert "--use-angle=vulkan" not in argv
PY
then
  pass "managed GPU actions keep Chromium and Electron on ANGLE GL with Vulkan disabled"
else
  fail "managed GPU actions keep Chromium and Electron on ANGLE GL with Vulkan disabled"
fi

[ "$FAIL_COUNT" -eq 0 ]
