The host env contract is split into concrete profiles plus shared cross-role policy:

- `hosts/profiles/<family>/<role>.env`
- `hosts/profiles/override/<name>.env`
- `hosts/shared/identity.env`
- `hosts/shared/account.env`
- `hosts/shared/runtime.env`
- `hosts/shared/server.env` for server-only addon policy
- `hosts/shared/layout.env`
- `hosts/shared/layout-btrfs.env` or `hosts/shared/layout-f2fs.env`
- `hosts/shared/boot.env`
- optional profile override envs under `hosts/profiles/override/<name>.env`

The loader assembles the concrete host policy env in this order:

1. `hosts/profiles/<family>/<role>.env` or `hosts/profiles/override/<name>.env`
2. `hosts/shared/identity.env`
3. `hosts/shared/runtime.env`
4. `hosts/shared/server.env` for server profiles only
5. `hosts/shared/layout.env`
6. `hosts/shared/layout-<storage-family>.env`
7. `hosts/shared/boot.env`

Account policy is loaded separately from `hosts/shared/account.env`.
Desktop profiles own their complete Labwc and desktop-addon policy directly;
there is no shared desktop env layer.

When the optional `profile` class group is selected, the matching
`hosts/profiles/override/<name>.env` replaces the normal
`hosts/profiles/<family>/<role>.env` source while the remaining shared
cross-role and layout layers continue to load in the same order.

The concrete profile loads first because shared env files derive tmpfs, zram,
device, GRUB, server addon policy, sysctl, and installed static
networking policy from the role-specific `SIZE_*`, `BOOTPROFILE_*`, `GRUB_*`,
`WIFI_*`, `TAILSCALE_*`, `SYNCTHING_*`, and slot values owned by the selected
profile. Installed-system log levels are shared policy in `shared/runtime.env`.
For the `tailscale` addon, the concrete profile owns the node-side Tailscale
policy defaults such as tag advertisement, route advertisement, operator user,
approval-sensitive auth-key requirements, daemon retry behavior, and the
managed bootstrap timeout. Shipped profiles require an injected auth key so
unattended installs cannot silently leave Tailscale stopped.
`hosts/shared/layout.env` carries only cross-family mount primitives and
tmpfs/dm-crypt backing policy; `layout-btrfs.env` and `layout-f2fs.env` own
their layout labels, mount, mkfs, formatter sizing, and GRUB root policy.
In the F2FS family, `/pool` remains ext4 and therefore uses `MNT_EXT4_POOL_OPTS`.
Static target IPv4/IPv6 addresses are no longer stored in host profiles. The
installed static network handoff now derives its concrete address, netmask,
gateway, and nameserver values directly from installer kernel cmdline answers
(`netcfg/get_*` plus optional `ipv6_*`).
Installed-system log defaults in `shared/runtime.env` are intentionally sparse:
nftables defaults to `none`, while zram and systemd/network helpers default to
`error`.
`NFTABLES_LOG_LEVEL` controls generator diagnostic output only; packet logging
is controlled by nftables profile or service overlay `logging.*.enabled`
fields, not by log level.
`NFTABLES_LOG_LEVEL`, `ZRAM_LOG_LEVEL`, and `SYSTEMD_LOG_LEVEL` accept
`none|error|warning|info|debug`.
These installed-system log levels are independent from the selected `debug`
installer class, which only controls d-i installation log capture.

The selected installer classes remain authoritative, and the storage-family
split is intentionally strict:

- `disk=nvme` selects `hosts/profiles/btrfs/<desktop|server>.env` for the Btrfs/XFS bare-metal baseline. This class also covers fixed non-removable SATA-style bare-metal hosts when no VM or eMMC class is detected.
- `disk=vm` selects `hosts/profiles/vm/<desktop|server>.env`.
- `disk=emmc` selects `hosts/profiles/f2fs/<desktop|server>.env` and does not share the Btrfs hook family.
- selecting a manifest-declared `profile` class such as `btrfs-de`,
  `btrfs-de-dual`, `btrfs-de-main`, `btrfs-de-dual-main`,
  `btrfs-de-flex`, `btrfs-de-dual-flex`, `f2fs-de`, `f2fs-de-dual`,
  `f2fs-de-cbook`, `f2fs-de-dual-cbook`,
  `btrfs-gitlab-runner-srv`, `btrfs-gitlab-runner-srv-dual`, or
  `f2fs-pihole-srv` switches the concrete profile source to
  `hosts/profiles/override/<name>.env`
- the `*-dual` overrides are intended to pair with `classes=...,dualboot`
  when the install should reuse an existing ESP and preserve pre-Debian slots

The `disk` class is auto-detected unless it is explicitly supplied in
`classes=`. Auto-detection prefers real NVMe namespaces or NVMe PCI
controllers first, then dedicated eMMC devices, then VM storage, and finally
falls back to the generic fixed bare-metal Btrfs/XFS class.

Current family intent:

- `profiles/btrfs/desktop.env` uses the desktop Btrfs/XFS size floors and targets.
- `profiles/btrfs/server.env` keeps the same slot contract but reserves a larger `/pool`.
- `profiles/f2fs/desktop.env` keeps a dedicated `/home` partition and can insert a dedicated encrypted `/var/lib/shim-signed` partition when `SECURE_BOOT_STATE_MODE=luks`.
- `profiles/f2fs/server.env` keeps `/home` on the root filesystem, does not allocate a separate home partition, and can insert the same encrypted Secure Boot state partition when `SECURE_BOOT_STATE_MODE=luks`.
- `profiles/vm/desktop.env` keeps the Btrfs/XFS storage contract for virtual machines.
- `profiles/vm/server.env` uses the same guest storage family with guest-oriented GRUB and module policy.
- every desktop profile and desktop override owns the complete Labwc,
  Waybar, launcher, output, and desktop-addon policy block
- `LABWC_MANAGED_APP_DEFAULT_EXEC` is required in every desktop profile and
  desktop override; the software addon and launcher synchronizer render it
  into the default `Exec=` command for every managed application launcher
- every desktop profile and desktop override also owns the complete
  `DEVOPS_CARGO_*` policy used to render the managed Cargo config template;
  hardware-specific overrides may tune `DEVOPS_CARGO_TARGET_CPU`, while
  untuned profiles keep the portable `generic` target

Storage sysctl layering:

- `hooks/shared/target/etc/sysctl.d/10-*.conf` and `20-*.conf` stay common across every host.
- `hosts/shared/runtime.env` owns the shared `FILE_SYSCTL_*` target paths.
- `hooks/shared/target/etc/sysctl.d/25-storage-static.conf.tmpl` renders storage overrides from the assembled host policy env.
- `hooks/shared/target/etc/sysctl.d/profiles/*/40-*.conf` remains the shared bootprofile baseline.
- `hooks/shared/target/etc/sysctl.d/profiles/*/40-*.conf` renders disk- and role-specific bootprofile placeholders directly into the managed profile files that `bootprofile-apply` syncs into `/run/sysctl.d`.
