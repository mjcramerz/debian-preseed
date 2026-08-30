#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/apt-local-repos-smoke.XXXXXX")
trap 'rm -rf "$TMP_DIR"' EXIT HUP INT TERM

TEST_COUNT=17
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

render_answers() {
  case_name=$1
  classes=$2
  output_path=$3
  error_path=$4
  pci_root=${5:-}

  runtime_dir="$TMP_DIR/runtime-$case_name"
  cmdline="classes=$classes primary_user=user primary_password=secret root_password=root fruux_username=alice fruux_password=token"

  if answers_file=$(
    INSTALLER_RUNTIME_DIR="$runtime_dir" \
    INSTALLER_SOURCE_ROOT="$ROOT_DIR/d-i/forky" \
    INSTALLER_CMDLINE="$cmdline" \
    INSTALLER_PCI_DEVICES_ROOT="$pci_root" \
      sh "$ROOT_DIR/d-i/forky/scripts/preseed/answers.sh" render "$ROOT_DIR/d-i/forky" 2>"$error_path"
  ); then
    printf '%s\n' "$answers_file" >"$output_path"
    return 0
  fi

  return 1
}

answers_path() {
  sed -n '1p' "$1"
}

pkgsel_line() {
  sed -n 's/^d-i pkgsel\/include string //p' "$1" | head -n 1
}

word_list_has() {
  words=$1
  needle=$2
  case " $words " in
    *" $needle "*) return 0 ;;
  esac
  return 1
}

printf '1..%s\n' "$TEST_COUNT"

nvidia_pci_root="$TMP_DIR/nvidia-pci"
mkdir -p "$nvidia_pci_root/0000:01:00.0"
printf '0x10de\n' >"$nvidia_pci_root/0000:01:00.0/vendor"
printf '0x030000\n' >"$nvidia_pci_root/0000:01:00.0/class"

amd64_classes='lab,desktop,standard,dhcp,software,arch/amd64,cpu/intel,gpu/generic,disk/vm'
amd64_out="$TMP_DIR/amd64.out"
amd64_err="$TMP_DIR/amd64.err"
if render_answers amd64 "$amd64_classes" "$amd64_out" "$amd64_err"; then
  amd64_answers=$(answers_path "$amd64_out")
  if grep -q '^d-i apt-setup/local3/repository string https://downloadcontent.opensuse.org/repositories/home:/cramerz:/debian/Debian_Unstable/ /$' "$amd64_answers" &&
     grep -q '^d-i apt-setup/local3/key string https://downloadcontent.opensuse.org/repositories/home:cramerz:debian/Debian_Unstable/Release.key$' "$amd64_answers"; then
    pass "desktop software render keeps the OBS archive on the next consecutive local slot"
  else
    fail "desktop software render keeps the OBS archive on the next consecutive local slot" "$amd64_answers"
  fi
else
  fail "desktop software render keeps the OBS archive on the next consecutive local slot" "$amd64_err"
fi

if [ -n "${amd64_answers:-}" ] &&
   grep -q '^d-i apt-setup/local4/repository string https://deb.debian.org/debian experimental main$' "$amd64_answers" &&
   grep -q '^d-i apt-setup/local5/repository string https://wayscriber.com/apt stable main$' "$amd64_answers" &&
   grep -q '^d-i apt-setup/local6/repository string https://packages.microsoft.com/repos/code stable main$' "$amd64_answers" &&
   grep -q '^d-i apt-setup/local7/repository string https://packages.microsoft.com/repos/edge stable main$' "$amd64_answers" &&
   grep -q '^d-i apt-setup/local8/repository string https://packages.microsoft.com/debian/13/prod trixie main$' "$amd64_answers" &&
   grep -q '^d-i apt-setup/local9/repository string https://repository.mullvad.net/deb/stable stable main$' "$amd64_answers" &&
   grep -q '^d-i apt-setup/local10/repository string https://repo.mysql.com/apt/debian trixie mysql-9.7-lts mysql-tools$' "$amd64_answers" &&
   grep -q '^d-i apt-setup/local10/key string https://repo.mysql.com/RPM-GPG-KEY-mysql-2025$' "$amd64_answers" &&
   grep -q '^d-i apt-setup/local11/repository string https://repository.spotify.com stable non-free$' "$amd64_answers" &&
   grep -q '^d-i apt-setup/local12/repository string https://repo.vivaldi.com/archive/deb stable main$' "$amd64_answers" &&
   grep -q '^d-i apt-setup/local12/key string https://repo.vivaldi.com/archive/linux_signing_key.pub$' "$amd64_answers"; then
  pass "desktop and software archives stay consecutive after Experimental and Wayscriber"
else
  fail "desktop and software archives stay consecutive after Experimental and Wayscriber" "${amd64_answers:-$amd64_err}"
fi

if [ -n "${amd64_answers:-}" ]; then
  amd64_pkgsel=$(pkgsel_line "$amd64_answers")
  if word_list_has "$amd64_pkgsel" code &&
     word_list_has "$amd64_pkgsel" microsoft-edge-stable &&
     word_list_has "$amd64_pkgsel" vivaldi-stable &&
     word_list_has "$amd64_pkgsel" mullvad-browser &&
     ! word_list_has "$amd64_pkgsel" mullvad-vpn &&
     ! word_list_has "$amd64_pkgsel" systemd-resolved &&
     ! word_list_has "$amd64_pkgsel" resolvconf &&
     ! grep -q '^resolvconf ' "$amd64_answers" &&
     word_list_has "$amd64_pkgsel" qbittorrent; then
    pass "explicit software addon defers resolver and VPN installation beyond pkgsel while retaining browser support"
  else
    fail "explicit software addon defers resolver and VPN installation beyond pkgsel while retaining browser support" "$amd64_answers"
  fi
else
  fail "explicit software addon defers resolver and VPN installation beyond pkgsel while retaining browser support" "$amd64_err"
fi

desktop_only_classes='lab,desktop,standard,dhcp,software,arch/amd64,cpu/intel,gpu/generic,disk/vm'
desktop_only_out="$TMP_DIR/desktop-only.out"
desktop_only_err="$TMP_DIR/desktop-only.err"
if render_answers desktop-only "$desktop_only_classes" "$desktop_only_out" "$desktop_only_err"; then
  desktop_only_answers=$(answers_path "$desktop_only_out")
  if grep -q '^d-i apt-setup/local3/repository string https://downloadcontent.opensuse.org/repositories/home:/cramerz:/debian/Debian_Unstable/ /$' "$desktop_only_answers" &&
     grep -q '^d-i apt-setup/local4/repository string https://deb.debian.org/debian experimental main$' "$desktop_only_answers" &&
     grep -q '^d-i apt-setup/local5/repository string https://wayscriber.com/apt stable main$' "$desktop_only_answers" &&
     grep -q '^d-i apt-setup/local6/repository string https://packages.microsoft.com/repos/code stable main$' "$desktop_only_answers" &&
     grep -q '^d-i apt-setup/local7/repository string https://packages.microsoft.com/repos/edge stable main$' "$desktop_only_answers" &&
     grep -q '^d-i apt-setup/local8/repository string https://packages.microsoft.com/debian/13/prod trixie main$' "$desktop_only_answers" &&
     grep -q '^d-i apt-setup/local9/repository string https://repository.mullvad.net/deb/stable stable main$' "$desktop_only_answers" &&
     grep -q '^d-i apt-setup/local10/repository string https://repo.mysql.com/apt/debian trixie mysql-9.7-lts mysql-tools$' "$desktop_only_answers" &&
     grep -q '^d-i apt-setup/local11/repository string https://repository.spotify.com stable non-free$' "$desktop_only_answers" &&
     grep -q '^d-i apt-setup/local12/repository string https://repo.vivaldi.com/archive/deb stable main$' "$desktop_only_answers"; then
    pass "desktop software archives follow Experimental and Wayscriber without GitLab Runner"
  else
    fail "desktop software archives follow Experimental and Wayscriber without GitLab Runner" "$desktop_only_answers"
  fi
else
  fail "desktop software archives follow Experimental and Wayscriber without GitLab Runner" "$desktop_only_err"
fi

vivaldi_only_classes='lab,desktop,standard,dhcp,vivaldi,arch/amd64,cpu/intel,gpu/generic,disk/vm'
vivaldi_only_out="$TMP_DIR/vivaldi-only.out"
vivaldi_only_err="$TMP_DIR/vivaldi-only.err"
if render_answers vivaldi-only "$vivaldi_only_classes" "$vivaldi_only_out" "$vivaldi_only_err"; then
  vivaldi_only_answers=$(answers_path "$vivaldi_only_out")
  vivaldi_only_pkgsel=$(pkgsel_line "$vivaldi_only_answers")
  if grep -q '^d-i apt-setup/local6/repository string https://repo.vivaldi.com/archive/deb stable main$' "$vivaldi_only_answers" &&
     grep -q '^d-i apt-setup/local6/key string https://repo.vivaldi.com/archive/linux_signing_key.pub$' "$vivaldi_only_answers" &&
     word_list_has "$vivaldi_only_pkgsel" vivaldi-stable &&
     ! word_list_has "$vivaldi_only_pkgsel" microsoft-edge-stable &&
     ! word_list_has "$vivaldi_only_pkgsel" retroarch &&
     ! word_list_has "$vivaldi_only_pkgsel" code; then
    pass "Vivaldi can be selected without the monolithic software bundle"
  else
    fail "Vivaldi can be selected without the monolithic software bundle" "$vivaldi_only_answers"
  fi
else
  fail "Vivaldi can be selected without the monolithic software bundle" "$vivaldi_only_err"
fi

retroarch_only_classes='lab,desktop,standard,dhcp,retroarch,arch/amd64,cpu/intel,gpu/generic,disk/vm'
retroarch_only_out="$TMP_DIR/retroarch-only.out"
retroarch_only_err="$TMP_DIR/retroarch-only.err"
if render_answers retroarch-only "$retroarch_only_classes" "$retroarch_only_out" "$retroarch_only_err"; then
  retroarch_only_answers=$(answers_path "$retroarch_only_out")
  retroarch_only_pkgsel=$(pkgsel_line "$retroarch_only_answers")
  if word_list_has "$retroarch_only_pkgsel" retroarch &&
     word_list_has "$retroarch_only_pkgsel" retroarch-assets &&
     ! word_list_has "$retroarch_only_pkgsel" vivaldi-stable &&
     ! word_list_has "$retroarch_only_pkgsel" microsoft-edge-stable &&
     ! grep -q 'repo.vivaldi.com' "$retroarch_only_answers"; then
    pass "RetroArch and its assets can be selected without the software bundle"
  else
    fail "RetroArch and its assets can be selected without the software bundle" "$retroarch_only_answers"
  fi
else
  fail "RetroArch and its assets can be selected without the software bundle" "$retroarch_only_err"
fi

split_apps_classes='lab,desktop,standard,dhcp,microsoft-edge,vivaldi,mullvad,retroarch,arch/amd64,cpu/intel,gpu/generic,disk/vm'
split_apps_out="$TMP_DIR/split-apps.out"
split_apps_err="$TMP_DIR/split-apps.err"
if render_answers split-apps "$split_apps_classes" "$split_apps_out" "$split_apps_err"; then
  split_apps_answers=$(answers_path "$split_apps_out")
  split_apps_pkgsel=$(pkgsel_line "$split_apps_answers")
  if grep -q '^d-i apt-setup/local3/repository string https://downloadcontent.opensuse.org/repositories/home:/cramerz:/debian/Debian_Unstable/ /$' "$split_apps_answers" &&
     grep -q '^d-i apt-setup/local4/repository string https://deb.debian.org/debian experimental main$' "$split_apps_answers" &&
     grep -q '^d-i apt-setup/local5/repository string https://wayscriber.com/apt stable main$' "$split_apps_answers" &&
     grep -q '^d-i apt-setup/local6/repository string https://packages.microsoft.com/repos/edge stable main$' "$split_apps_answers" &&
     grep -q '^d-i apt-setup/local7/repository string https://repository.mullvad.net/deb/stable stable main$' "$split_apps_answers" &&
     grep -q '^d-i apt-setup/local8/repository string https://repo.vivaldi.com/archive/deb stable main$' "$split_apps_answers" &&
     grep -q '^d-i apt-setup/local8/key string https://repo.vivaldi.com/archive/linux_signing_key.pub$' "$split_apps_answers" &&
     word_list_has "$split_apps_pkgsel" microsoft-edge-stable &&
     word_list_has "$split_apps_pkgsel" vivaldi-stable &&
     word_list_has "$split_apps_pkgsel" mullvad-browser &&
     ! word_list_has "$split_apps_pkgsel" mullvad-vpn &&
     ! word_list_has "$split_apps_pkgsel" systemd-resolved &&
     ! word_list_has "$split_apps_pkgsel" resolvconf &&
     ! grep -q '^resolvconf ' "$split_apps_answers" &&
     word_list_has "$split_apps_pkgsel" retroarch &&
     word_list_has "$split_apps_pkgsel" retroarch-assets &&
     ! word_list_has "$split_apps_pkgsel" code; then
    pass "class-apps selections defer resolver and Mullvad VPN installation while staging their policy and archives"
  else
    fail "class-apps selections defer resolver and Mullvad VPN installation while staging their policy and archives" "$split_apps_answers"
  fi
else
  fail "class-apps selections defer resolver and Mullvad VPN installation while staging their policy and archives" "$split_apps_err"
fi

split_apps_conflict_out="$TMP_DIR/split-apps-conflict.out"
split_apps_conflict_err="$TMP_DIR/split-apps-conflict.err"
if render_answers split-apps-conflict 'lab,desktop,standard,dhcp,software,microsoft-edge,arch/amd64,cpu/intel,gpu/generic,disk/vm' "$split_apps_conflict_out" "$split_apps_conflict_err"; then
  fail "class-apps selections reject the monolithic software addon" "$split_apps_conflict_err"
elif grep -q 'selected class apps/microsoft-edge rejects class addon/software' "$split_apps_conflict_err" ||
     [ ! -s "$split_apps_conflict_out" ]; then
  pass "class-apps selections reject the monolithic software addon"
else
  fail "class-apps selections reject the monolithic software addon" "$split_apps_conflict_err"
fi

gitlab_only_classes='lab,server,standard,dhcp,service/gitlab-runner,arch/amd64,cpu/intel,gpu/generic,disk/vm'
gitlab_only_out="$TMP_DIR/gitlab-only.out"
gitlab_only_err="$TMP_DIR/gitlab-only.err"
if render_answers gitlab-only "$gitlab_only_classes" "$gitlab_only_out" "$gitlab_only_err"; then
  gitlab_only_answers=$(answers_path "$gitlab_only_out")
  if grep -q '^d-i apt-setup/local4/repository string https://deb.debian.org/debian experimental main$' "$gitlab_only_answers" &&
     grep -q '^d-i apt-setup/local5/repository string https://packages.gitlab.com/runner/gitlab-runner/debian trixie main$' "$gitlab_only_answers" &&
     grep -q '^d-i apt-setup/local6/repository string https://storage.googleapis.com/bazel-apt stable jdk1.8$' "$gitlab_only_answers"; then
    pass "gitlab-runner render stays consecutive after Experimental"
  else
    fail "gitlab-runner render stays consecutive after Experimental" "$gitlab_only_answers"
  fi
else
  fail "gitlab-runner render stays consecutive after Experimental" "$gitlab_only_err"
fi

obs_gitlab_classes='lab,server,standard,dhcp,service/gitlab-runner,arch/amd64,cpu/intel,gpu/generic,disk/vm'
obs_gitlab_out="$TMP_DIR/obs-gitlab.out"
obs_gitlab_err="$TMP_DIR/obs-gitlab.err"
if render_answers obs-gitlab "$obs_gitlab_classes" "$obs_gitlab_out" "$obs_gitlab_err"; then
  obs_gitlab_answers=$(answers_path "$obs_gitlab_out")
  if grep -q '^d-i apt-setup/local3/repository string https://downloadcontent.opensuse.org/repositories/home:/cramerz:/debian/Debian_Unstable/ /$' "$obs_gitlab_answers" &&
     grep -q '^d-i apt-setup/local4/repository string https://deb.debian.org/debian experimental main$' "$obs_gitlab_answers" &&
     grep -q '^d-i apt-setup/local5/repository string https://packages.gitlab.com/runner/gitlab-runner/debian trixie main$' "$obs_gitlab_answers"; then
    pass "gitlab-runner render stays behind OBS and Experimental when software is not selected"
  else
    fail "gitlab-runner render stays behind OBS and Experimental when software is not selected" "$obs_gitlab_answers"
  fi
else
  fail "gitlab-runner render stays behind OBS and Experimental when software is not selected" "$obs_gitlab_err"
fi

desktop_gitlab_classes='lab,desktop,standard,dhcp,software,service/gitlab-runner,arch/amd64,cpu/intel,gpu/generic,disk/vm'
desktop_gitlab_out="$TMP_DIR/desktop-gitlab.out"
desktop_gitlab_err="$TMP_DIR/desktop-gitlab.err"
if render_answers desktop-gitlab "$desktop_gitlab_classes" "$desktop_gitlab_out" "$desktop_gitlab_err"; then
  desktop_gitlab_answers=$(answers_path "$desktop_gitlab_out")
  if grep -q '^d-i apt-setup/local4/repository string https://deb.debian.org/debian experimental main$' "$desktop_gitlab_answers" &&
     grep -q '^d-i apt-setup/local5/repository string https://wayscriber.com/apt stable main$' "$desktop_gitlab_answers" &&
     grep -q '^d-i apt-setup/local6/repository string https://packages.gitlab.com/runner/gitlab-runner/debian trixie main$' "$desktop_gitlab_answers" &&
     grep -q '^d-i apt-setup/local7/repository string https://storage.googleapis.com/bazel-apt stable jdk1.8$' "$desktop_gitlab_answers"; then
    pass "gitlab-runner render follows desktop Experimental and Wayscriber archives"
  else
    fail "gitlab-runner render follows desktop Experimental and Wayscriber archives" "$desktop_gitlab_answers"
  fi
else
  fail "gitlab-runner render follows desktop Experimental and Wayscriber archives" "$desktop_gitlab_err"
fi

gitlab_classes='lab,desktop,standard,dhcp,software,service/gitlab-runner,arch/amd64,cpu/intel,gpu/generic,disk/vm'
gitlab_out="$TMP_DIR/gitlab.out"
gitlab_err="$TMP_DIR/gitlab.err"
if render_answers gitlab "$gitlab_classes" "$gitlab_out" "$gitlab_err"; then
  gitlab_answers=$(answers_path "$gitlab_out")
  if grep -q '^d-i apt-setup/local3/repository string https://downloadcontent.opensuse.org/repositories/home:/cramerz:/debian/Debian_Unstable/ /$' "$gitlab_answers" &&
     grep -q '^d-i apt-setup/local4/repository string https://deb.debian.org/debian experimental main$' "$gitlab_answers" &&
     grep -q '^d-i apt-setup/local5/repository string https://wayscriber.com/apt stable main$' "$gitlab_answers" &&
     grep -q '^d-i apt-setup/local6/repository string https://packages.gitlab.com/runner/gitlab-runner/debian trixie main$' "$gitlab_answers" &&
     grep -q '^d-i apt-setup/local7/repository string https://storage.googleapis.com/bazel-apt stable jdk1.8$' "$gitlab_answers" &&
     grep -q '^d-i apt-setup/local8/repository string https://packages.microsoft.com/repos/code stable main$' "$gitlab_answers" &&
     grep -q '^d-i apt-setup/local9/repository string https://packages.microsoft.com/repos/edge stable main$' "$gitlab_answers" &&
     grep -q '^d-i apt-setup/local10/repository string https://packages.microsoft.com/debian/13/prod trixie main$' "$gitlab_answers" &&
     grep -q '^d-i apt-setup/local11/repository string https://repository.mullvad.net/deb/stable stable main$' "$gitlab_answers" &&
     grep -q '^d-i apt-setup/local12/repository string https://repo.mysql.com/apt/debian trixie mysql-9.7-lts mysql-tools$' "$gitlab_answers" &&
     grep -q '^d-i apt-setup/local13/repository string https://repository.spotify.com stable non-free$' "$gitlab_answers" &&
     grep -q '^d-i apt-setup/local14/repository string https://repo.vivaldi.com/archive/deb stable main$' "$gitlab_answers"; then
    pass "render preserves Experimental, Wayscriber, GitLab Runner, and software archive order"
  else
    fail "render preserves Experimental, Wayscriber, GitLab Runner, and software archive order" "$gitlab_answers"
  fi
else
  fail "render preserves Experimental, Wayscriber, GitLab Runner, and software archive order" "$gitlab_err"
fi

cuda_only_classes='lab,server,standard,dhcp,nvidia,cuda,arch/amd64,cpu/intel,gpu/generic,disk/vm'
cuda_only_out="$TMP_DIR/cuda-only.out"
cuda_only_err="$TMP_DIR/cuda-only.err"
if render_answers cuda-only "$cuda_only_classes" "$cuda_only_out" "$cuda_only_err" "$nvidia_pci_root"; then
  cuda_only_answers=$(answers_path "$cuda_only_out")
  if grep -q '^d-i apt-setup/local4/repository string https://deb.debian.org/debian experimental main$' "$cuda_only_answers" &&
     grep -q '^d-i apt-setup/local5/repository string https://developer.download.nvidia.com/compute/cuda/repos/debian13/x86_64/ /$' "$cuda_only_answers"; then
    pass "cuda render shifts its upstream archive after Experimental"
  else
    fail "cuda render shifts its upstream archive after Experimental" "$cuda_only_answers"
  fi
else
  fail "cuda render shifts its upstream archive after Experimental" "$cuda_only_err"
fi

desktop_cuda_gitlab_classes='lab,desktop,standard,dhcp,software,service/gitlab-runner,nvidia,cuda,arch/amd64,cpu/intel,gpu/generic,disk/vm'
desktop_cuda_gitlab_out="$TMP_DIR/desktop-cuda-gitlab.out"
desktop_cuda_gitlab_err="$TMP_DIR/desktop-cuda-gitlab.err"
if render_answers desktop-cuda-gitlab "$desktop_cuda_gitlab_classes" "$desktop_cuda_gitlab_out" "$desktop_cuda_gitlab_err" "$nvidia_pci_root"; then
  desktop_cuda_gitlab_answers=$(answers_path "$desktop_cuda_gitlab_out")
  if grep -q '^d-i apt-setup/local4/repository string https://deb.debian.org/debian experimental main$' "$desktop_cuda_gitlab_answers" &&
     grep -q '^d-i apt-setup/local5/repository string https://wayscriber.com/apt stable main$' "$desktop_cuda_gitlab_answers" &&
     grep -q '^d-i apt-setup/local6/repository string https://packages.gitlab.com/runner/gitlab-runner/debian trixie main$' "$desktop_cuda_gitlab_answers" &&
     grep -q '^d-i apt-setup/local7/repository string https://storage.googleapis.com/bazel-apt stable jdk1.8$' "$desktop_cuda_gitlab_answers" &&
     grep -q '^d-i apt-setup/local8/repository string https://developer.download.nvidia.com/compute/cuda/repos/debian13/x86_64/ /$' "$desktop_cuda_gitlab_answers"; then
    pass "cuda render follows Experimental, Wayscriber, and GitLab Runner archives"
  else
    fail "cuda render follows Experimental, Wayscriber, and GitLab Runner archives" "$desktop_cuda_gitlab_answers"
  fi
else
  fail "cuda render follows Experimental, Wayscriber, and GitLab Runner archives" "$desktop_cuda_gitlab_err"
fi

legacy_cuda_only_classes='lab,server,standard,dhcp,nvidia-legacy,cuda-legacy,arch/amd64,cpu/intel,gpu/generic,disk/emmc'
legacy_cuda_only_out="$TMP_DIR/legacy-cuda-only.out"
legacy_cuda_only_err="$TMP_DIR/legacy-cuda-only.err"
if render_answers legacy-cuda-only "$legacy_cuda_only_classes" "$legacy_cuda_only_out" "$legacy_cuda_only_err" "$nvidia_pci_root"; then
  legacy_cuda_only_answers=$(answers_path "$legacy_cuda_only_out")
  legacy_cuda_only_pkgsel=$(pkgsel_line "$legacy_cuda_only_answers")
  if ! grep -q 'developer.download.nvidia.com/compute/cuda/repos/debian12/x86_64' "$legacy_cuda_only_answers" &&
     word_list_has "$legacy_cuda_only_pkgsel" cuda-cudart-12-8 &&
     word_list_has "$legacy_cuda_only_pkgsel" cuda-cudart-12-9 &&
     word_list_has "$legacy_cuda_only_pkgsel" nvidia-dkms-580 &&
     word_list_has "$legacy_cuda_only_pkgsel" linux-xanmod-x64v2; then
    pass "legacy CUDA render keeps the managed Debian 12 NVIDIA 12.8/12.9 toolkit packages while omitting apt-setup local source emission"
  else
    fail "legacy CUDA render keeps the managed Debian 12 NVIDIA 12.8/12.9 toolkit packages while omitting apt-setup local source emission" "$legacy_cuda_only_answers"
  fi
else
  fail "legacy CUDA render keeps the managed Debian 12 NVIDIA 12.8/12.9 toolkit packages while omitting apt-setup local source emission" "$legacy_cuda_only_err"
fi

legacy_cuda_desktop_classes='lab,desktop,standard,dhcp,software,service/gitlab-runner,nvidia-legacy,cuda-legacy,arch/amd64,cpu/intel,gpu/generic,disk/emmc'
legacy_cuda_desktop_out="$TMP_DIR/legacy-cuda-desktop.out"
legacy_cuda_desktop_err="$TMP_DIR/legacy-cuda-desktop.err"
if render_answers legacy-cuda-desktop "$legacy_cuda_desktop_classes" "$legacy_cuda_desktop_out" "$legacy_cuda_desktop_err" "$nvidia_pci_root"; then
  legacy_cuda_desktop_answers=$(answers_path "$legacy_cuda_desktop_out")
  if ! grep -q 'developer.download.nvidia.com/compute/cuda/repos/debian12/x86_64' "$legacy_cuda_desktop_answers"; then
    pass "legacy CUDA desktop render omits apt-setup local source emission after the managed base repos"
  else
    fail "legacy CUDA desktop render omits apt-setup local source emission after the managed base repos" "$legacy_cuda_desktop_answers"
  fi
else
  fail "legacy CUDA desktop render omits apt-setup local source emission after the managed base repos" "$legacy_cuda_desktop_err"
fi

arm64_classes='lab,desktop,standard,dhcp,software,arch/arm64,cpu/amd,gpu/generic,disk/vm'
arm64_out="$TMP_DIR/arm64.out"
arm64_err="$TMP_DIR/arm64.err"
if render_answers arm64 "$arm64_classes" "$arm64_out" "$arm64_err"; then
  arm64_answers=$(answers_path "$arm64_out")
  arm64_pkgsel=$(pkgsel_line "$arm64_answers")
  if word_list_has "$arm64_pkgsel" code &&
     word_list_has "$arm64_pkgsel" vivaldi-stable &&
     ! word_list_has "$arm64_pkgsel" microsoft-edge-stable; then
    pass "desktop non-amd64 package set skips Microsoft Edge while keeping Vivaldi"
  else
    fail "desktop non-amd64 package set skips Microsoft Edge while keeping Vivaldi" "$arm64_answers"
  fi
else
  fail "desktop non-amd64 package set skips Microsoft Edge while keeping Vivaldi" "$arm64_err"
fi

[ "$FAIL_COUNT" -eq 0 ]
