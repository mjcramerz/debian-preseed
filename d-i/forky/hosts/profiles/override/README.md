# Forky override profiles

To create your own profiles:
[mcramer] [LPL-469] [~/Workspace/debian-preseed-di-new] [git:mcr/main] *? > git status -sb
## mcr/main...origin/mcr/main
 M README.md
 M d-i/forky/classes/configs/profile.cfg
 M d-i/forky/hosts/README.md
 M t/late-policy-smoke.sh
?? d-i/forky/classes/class-profile/btrfs-de-dual-flex.cfg
?? d-i/forky/classes/class-profile/btrfs-de-dual-main.cfg
?? d-i/forky/classes/class-profile/btrfs-de-flex.cfg
?? d-i/forky/classes/class-profile/btrfs-de-main.cfg
?? d-i/forky/classes/class-profile/f2fs-de-cbook.cfg
?? d-i/forky/classes/class-profile/f2fs-de-dual-cbook.cfg
?? d-i/forky/hosts/profiles/override/README.md
?? d-i/forky/hosts/profiles/override/btrfs-de-dual-flex.env
?? d-i/forky/hosts/profiles/override/btrfs-de-dual-main.env
?? d-i/forky/hosts/profiles/override/btrfs-de-flex.env
?? d-i/forky/hosts/profiles/override/btrfs-de-main.env
?? d-i/forky/hosts/profiles/override/f2fs-de-cbook.env
?? d-i/forky/hosts/profiles/override/f2fs-de-dual-cbook.env

Override profiles are selected by adding the profile name to `classes=`. The
matching record in `classes/configs/profile.cfg` redirects the concrete host
policy to `hosts/profiles/override/<name>.env`. Desktop overrides own their
complete desktop policy directly; shared identity, runtime, layout, and boot
policy is still layered afterward.

Disk figures are approximate hardware or Debian-budget targets, not exact
device-size requirements. Runtime sizing uses the measured disk and preserved
partition sizes, keeps the profile safety margin unallocated, clamps swap and
raw ZRAM backing sizes, fills named targets in order, and gives the remaining
budget to `/`. Always validate dual-boot slot numbers and the rendered recipe
in a VM before using the profile on physical media.

## Hardware-specific desktop profiles

| Profile | Storage target | Usable RAM target | Effective ZRAM target | Notes |
| --- | --- | ---: | ---: | --- |
| `btrfs-de-main` | 466-500 GiB NVMe, centered near 479 GiB | 47935 MiB | about 11984 MiB, 5992 MiB memory limit | High-memory primary workstation; 1 GiB layout reserve, about 6 GiB fallback swap, and at most 16 GiB raw writeback backing. |
| `btrfs-de-dual-main` | 466-500 GiB NVMe with about 100 GiB preserved; about 365-399 GiB remains for Debian | 47935 MiB | about 11984 MiB, 5992 MiB memory limit | Select with `dualboot` and explicit `dualboot_efi` / `dualboot_debian` slots. |
| `btrfs-de-flex` | 466-500 GiB NVMe, centered near 479 GiB | 7489 MiB | about 7489 MiB, 4494 MiB memory limit | Lower-memory workstation; earlier pressure handling, about 1872 MiB fallback swap, and at most 16 GiB raw writeback backing. |
| `btrfs-de-dual-flex` | 466-500 GiB NVMe with about 100 GiB preserved; about 365-399 GiB remains for Debian | 7489 MiB | about 7489 MiB, 4494 MiB memory limit | Select with `dualboot` and explicit `dualboot_efi` / `dualboot_debian` slots. |
| `f2fs-de-cbook` | 29-33 GiB eMMC, centered near 32 GiB | 3424 MiB | about 3424 MiB, 1712 MiB memory limit | Chromebook layout keeps a 256 MiB reserve, 2 GiB fallback swap, a 2.0-2.8 GiB raw writeback tier, and at least 12 GiB for `/`. |
| `f2fs-de-dual-cbook` | 29-33 GiB eMMC with about 10 GiB preserved; roughly 19-23 GiB remains for Debian | 3424 MiB | about 3424 MiB, 1712 MiB memory limit | The reduced 10 GiB root and 3 GiB home floors keep the 29 GiB edge installable. Select with `dualboot` and explicit slot arguments. |

### AI runtime release policy

The hardware-specific Btrfs profiles install checksum- and byte-pinned binary
releases instead of compiling llama.cpp or whisper.cpp during installation.
The shipped executables are x86-64 ELF files; the `addon/devops` and
`addon/whisper` manifests therefore require `arch/amd64`.
Both `*-main` profiles select the CUDA release archives and require
`addon/cuda-legacy`, which retains the CUDA 12.8 and 12.9 runtimes, headers,
and `nvcc`; the pinned AI release archives remain linked to CUDA 12.8.
Both `*-flex` profiles select the RAM release archives and require no CUDA
class. Llama installs `llama-bench`, `llama-cli`, `llama-gguf-split`,
`llama-quantize`, and `llama-server` with the archive `metadata/` and `share/`
trees; Whisper installs `whisper-cli`, `whisper-server`, and `metadata/`.

| Profiles | Llama release | Whisper release | Required runtime class |
| --- | --- | --- | --- |
| `btrfs-de-main`, `btrfs-de-dual-main` | `llama-cuda.tar.gz` | `whisper-cuda.tar.gz` | `addon/cuda-legacy` |
| `btrfs-de-flex`, `btrfs-de-dual-flex` | `llama-ram.tar.gz` | `whisper-ram.tar.gz` | none |

The ZRAM figures above use the stated RAM targets. Actual ZRAM size is computed
at boot from `ZRAM_PCT`, then clamped by `ZRAM_MIN_MIB` and `ZRAM_MAX_MIB`.
The memory limit is a cap on compressed ZRAM memory consumption, not
preallocated RAM. All concrete profiles use `ZRAM_MAX_COMP_STREAMS=0`; the
setup helper converts that policy value to the current online CPU count before
zram is initialized.

## General override profiles

These profiles remain dynamic baselines without a single hardware-specific
disk or RAM recommendation:

| Profile | Family | Intended use |
| --- | --- | --- |
| `btrfs-de` | Btrfs/XFS on NVMe | Default desktop override. |
| `btrfs-de-dual` | Btrfs/XFS on NVMe | Default dual-boot desktop override. |
| `f2fs-de` | F2FS on eMMC | Default desktop override. |
| `f2fs-de-dual` | F2FS on eMMC | Default dual-boot desktop override. |
| `btrfs-gitlab-runner-srv` | Btrfs/XFS on NVMe | GitLab Runner server override. |
| `btrfs-gitlab-runner-srv-dual` | Btrfs/XFS on NVMe | Dual-boot GitLab Runner server override. |
| `f2fs-pihole-srv` | F2FS on eMMC | Pi-hole server override. |

## Selection examples

```text
classes=lab,desktop,standard,dhcp,btrfs-de-main
classes=lab,desktop,standard,dhcp,btrfs-de-dual-flex,dualboot dualboot_efi=1 dualboot_debian=3
classes=lab,desktop,standard,dhcp,f2fs-de-cbook
classes=lab,desktop,standard,dhcp,f2fs-de-dual-cbook,dualboot dualboot_efi=1 dualboot_debian=3
```
