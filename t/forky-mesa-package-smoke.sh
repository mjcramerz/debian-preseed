#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)

TEST_COUNT=5
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

vulkan_policy_semantics() {
  sed \
    -e '/^[[:space:]]*#/d' \
    -e '/^[[:space:]]*$/d' \
    -- "$1"
}

desktop_class="$ROOT_DIR/d-i/forky/classes/class-select/role/desktop.cfg"
intel_gpu_class="$ROOT_DIR/d-i/forky/classes/class-auto/gpu/intel-uhd.cfg"
nvidia_addon="$ROOT_DIR/d-i/forky/classes/class-addon/nvidia.cfg"
nvidia_legacy_addon="$ROOT_DIR/d-i/forky/classes/class-addon/nvidia-legacy.cfg"
desktop_vulkan_pref="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apt/preferences.d/desktop/vulkan.pref"
server_vulkan_pref="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apt/preferences.d/server/vulkan.pref"

if grep -Eq '(^|[[:space:]])mesa-utils([[:space:]]|$)' "$desktop_class" &&
   ! grep -Eq '(^|[[:space:]])mesa-va-drivers([[:space:]]|$)' "$desktop_class" &&
   grep -Eq '(^|[[:space:]])libgl1([[:space:]]|$)' "$desktop_class" &&
   grep -Eq '(^|[[:space:]])libegl1([[:space:]]|$)' "$desktop_class" &&
   grep -Eq '(^|[[:space:]])libgles2([[:space:]]|$)' "$desktop_class" &&
   grep -Eq '(^|[[:space:]])libgbm1([[:space:]]|$)' "$desktop_class" &&
   grep -Eq '(^|[[:space:]])libgl1-mesa-dri([[:space:]]|$)' "$desktop_class" &&
   ! grep -Eq '(^|[[:space:]])libvulkan1([[:space:]]|$)' "$desktop_class" &&
   ! grep -Eq '(^|[[:space:]])mesa-vulkan-drivers([[:space:]]|$)' "$desktop_class" &&
   ! grep -Eq '(^|[[:space:]])vulkan-tools([[:space:]]|$)' "$desktop_class" &&
   grep -Eq '(^|[[:space:]])vainfo([[:space:]]|$)' "$desktop_class" &&
   grep -Eq '(^|[[:space:]])libva-wayland2([[:space:]]|$)' "$desktop_class"; then
  pass "desktop role keeps the managed OpenGL stack free of Vulkan packages"
else
  fail "desktop role keeps the managed OpenGL stack free of Vulkan packages"
fi

if grep -Eq '(^|[[:space:]])intel-media-va-driver-non-free([[:space:]]|$)' "$intel_gpu_class" &&
   grep -Eq '(^|[[:space:]])libgbm1([[:space:]]|$)' "$intel_gpu_class" &&
   grep -Eq '(^|[[:space:]])libegl1([[:space:]]|$)' "$intel_gpu_class" &&
   grep -Eq '(^|[[:space:]])libgles2([[:space:]]|$)' "$intel_gpu_class" &&
   grep -Eq '(^|[[:space:]])libgl1-mesa-dri([[:space:]]|$)' "$intel_gpu_class" &&
   grep -Eq '(^|[[:space:]])libvulkan1([[:space:]]|$)' "$intel_gpu_class" &&
   ! grep -Eq '(^|[[:space:]])mesa-vulkan-drivers([[:space:]]|$)' "$intel_gpu_class" &&
   ! grep -Eq '(^|[[:space:]])vulkan-tools([[:space:]]|$)' "$intel_gpu_class"; then
  pass "intel auto-GPU class stages the loader ABI with managed OpenGL and media runtimes"
else
  fail "intel auto-GPU class stages the loader ABI with managed OpenGL and media runtimes"
fi

if ! grep -R -E \
     '(^|[[:space:]])(mesa-vulkan-drivers|vulkan-tools|libvulkan-dev|vulkan-validationlayers|nvidia-vulkan-icd|primus-vk)([[:space:]]|$)' \
     "$ROOT_DIR/d-i/forky/classes" >/dev/null 2>&1 &&
   ! grep -Eq '(^|[[:space:]])libvulkan1([[:space:]]|$)' "$desktop_class" &&
   ! grep -Eq '(^|[[:space:]])mesa-vulkan-drivers([[:space:]]|$)' "$desktop_class" &&
   ! grep -Eq '(^|[[:space:]])vulkan-tools([[:space:]]|$)' "$desktop_class" &&
   grep -Eq '(^|[[:space:]])libvulkan1([[:space:]]|$)' "$nvidia_addon" &&
   ! grep -Eq '(^|[[:space:]])mesa-vulkan-drivers([[:space:]]|$)' "$nvidia_addon" &&
   ! grep -Eq '(^|[[:space:]])vulkan-tools([[:space:]]|$)' "$nvidia_addon" &&
   grep -Eq '(^|[[:space:]])libvulkan1([[:space:]]|$)' "$nvidia_legacy_addon" &&
   ! grep -Eq '(^|[[:space:]])mesa-vulkan-drivers([[:space:]]|$)' "$nvidia_legacy_addon" &&
   ! grep -Eq '(^|[[:space:]])vulkan-tools([[:space:]]|$)' "$nvidia_legacy_addon" &&
   grep -q '^Package: mesa-vulkan-drivers vulkan-tools libvulkan-dev vulkan-validationlayers vulkan-validationlayers-dev vulkan-utility-libraries-dev vulkan-headers$' "$desktop_vulkan_pref" &&
   grep -q '^Package: mesa-vulkan-drivers vulkan-tools libvulkan-dev vulkan-validationlayers vulkan-validationlayers-dev vulkan-utility-libraries-dev vulkan-headers$' "$server_vulkan_pref" &&
   grep -q '^Package: nvidia-vulkan-icd nvidia-primus-vk-common nvidia-primus-vk-wrapper primus-vk libprimus-vk1$' "$desktop_vulkan_pref" &&
   [ "$(grep -c '^Pin-Priority: -1$' "$desktop_vulkan_pref")" -eq 2 ] &&
   [ "$(vulkan_policy_semantics "$desktop_vulkan_pref")" = "$(vulkan_policy_semantics "$server_vulkan_pref")" ] &&
   grep -q '^DEBIAN_APT_PREFERENCES="forky,trixie,sid,experimental,cramerz,dbus,x11,vulkan"$' "$ROOT_DIR/d-i/forky/repo.env"; then
  pass "GPU classes retain the loader ABI while both target policies semantically block Vulkan drivers and tools"
else
  fail "GPU classes retain the loader ABI while both target policies semantically block Vulkan drivers and tools"
fi

mesa_policy=$(apt-cache policy mesa-libgallium libgbm1 mesa-va-drivers 2>/dev/null || true)
mesa_show=$(apt-cache show mesa-libgallium mesa-va-drivers libgbm1 2>/dev/null || true)
mesa_candidate=$(printf '%s\n' "$mesa_policy" | awk '/^mesa-libgallium:$/ { found=1; next } found && $1 == "Candidate:" { print $2; exit }')
libgbm_candidate=$(printf '%s\n' "$mesa_policy" | awk '/^libgbm1:$/ { found=1; next } found && $1 == "Candidate:" { print $2; exit }')

if printf '%s\n' "$mesa_policy" | grep -q '^mesa-libgallium:$' &&
   [ -n "$mesa_candidate" ] &&
   [ "$mesa_candidate" != '(none)' ] &&
   printf '%s\n' "$mesa_policy" | grep -q '^mesa-va-drivers:$' &&
   printf '%s\n' "$mesa_policy" | grep -q 'mesa-va-drivers:[[:space:]]*$' &&
   printf '%s\n' "$mesa_show" | grep -q '^Package: mesa-libgallium$' &&
   printf '%s\n' "$mesa_show" | grep -q '^Provides: libglapi-mesa, mesa-va-drivers, mesa-vdpau-drivers, va-driver$' &&
   printf '%s\n' "$mesa_show" | grep -q '^Breaks: mesa-va-drivers ' &&
   printf '%s\n' "$mesa_show" | grep -q '^Package: mesa-va-drivers$' &&
   printf '%s\n' "$mesa_show" | grep -q '^Depends: mesa-libgallium (= ' ; then
  pass "local apt metadata shows Forky folds VA drivers into mesa-libgallium while Trixie still carries the old standalone package"
else
  fail "local apt metadata shows Forky folds VA drivers into mesa-libgallium while Trixie still carries the old standalone package"
fi

if printf '%s\n' "$mesa_policy" | grep -q '^libgbm1:$' &&
   [ "$libgbm_candidate" = "$mesa_candidate" ] &&
   printf '%s\n' "$mesa_show" | grep -q '^Package: libgbm1$' &&
   printf '%s\n' "$mesa_show" | grep -Fq "Depends: mesa-libgallium (= ${mesa_candidate})" ; then
  pass "libgbm1 stays tied to the same mesa-libgallium version family, confirming why the mixed candidate set broke"
else
  fail "libgbm1 stays tied to the same mesa-libgallium version family, confirming why the mixed candidate set broke"
fi

[ "$FAIL_COUNT" -eq 0 ]
