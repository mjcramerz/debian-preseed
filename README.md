# Debian LAN Installer

This repository is a stripped LAN-hosted Debian 13 installer bundle for automated bare-metal installs. It keeps only the install path needed for installation delivery, runtime partition rendering, storage layout, target fstab rendering, class-selected kernel packages, first-boot storage services, and GRUB profile generation.

- `Balanced`: daily-driver default with security and performance kept in balance.
- `Hardened`: stricter logging, auditing, and runtime restrictions.
- `Performance`: higher-throughput tuning without dropping core security controls.

## Storage Contract

The installer builds a mixed Btrfs, XFS, ext4, LUKS-on-ext4, vfat, tmpfs, and zram layout.

- `/` is Btrfs and uses these subvolumes: `@`, `@root`, `@srv`, `@usr_local`, `@var_spool`; with `addon/crypto` the filesystem is inside a dedicated LUKS2 container.
- `/home` is Btrfs and uses these subvolumes: `@home`, `@home_documents`, `@home_downloads`, `@home_public`, `@home_pictures`, `@home_workspace`, `@home_syncthing`; with `addon/crypto` the filesystem is inside a second dedicated LUKS2 container.
- `/opt` is a dedicated Btrfs filesystem with the `@opt` subvolume.
- `/data` is a dedicated XFS filesystem mounted once at the top level.
- `/data/run` is a `100 MiB` tmpfs mounted below `/data`; shared `/etc/tmpfiles.d/20-data-run.conf` recreates only the common runtime roots, while desktop `/etc/tmpfiles.d/25-desktop-media-runtime.conf` creates `/run/media/<account>` and rewires `/data/run/mnt` to that private media path at boot.
- `/pool` is a dedicated XFS filesystem mounted once at the top level.
- `/var/tmp` and `/var/log/journal` are dedicated ext4 filesystems.
- the managed tmpfiles policy purges `/tmp` at boot, removes `/tmp` entries older than seven days during periodic cleanup, and retains `/var/tmp` entries for thirty days.
- `/var/lib/shim-signed` is a dedicated `100 MiB` LUKS2-encrypted ext4 filesystem for Secure Boot state on Btrfs/VM profiles and on F2FS/eMMC profiles when `SECURE_BOOT_MODE=luks` or `SECURE_BOOT_STATE_MODE=luks`; it is mounted during installation, intentionally omitted from `fstab`, closed again during `finish-install`, and reopened on demand with the shipped `luks-mok-*` helpers. F2FS/eMMC profiles keep the historical direct-on-root state path when `SECURE_BOOT_MODE=direct` or `SECURE_BOOT_STATE_MODE=direct`.
- the last two Debian-owned partitions are left raw and unformatted: slot `11` is opened at boot as the ephemeral plain-dm-crypt mapper `/dev/mapper/swap-fallback` and activated directly as the lower-priority fallback swap partition; slot `12` is opened at boot as `/dev/mapper/zram-writeback` for zram writeback.
- `/data/run`, `/var/log`, `/var/cache`, `/var/lib/apt/lists`, `/var/lib/systemd/coredump`, `/tmp`, and `/dev/shm` are tmpfs mounts.
- `/var/log/journal` stays persistent below the tmpfs-mounted `/var/log`.
- `/var/log` no longer has a dedicated partition.
- `zram0` is enabled from first boot through custom helper and systemd units, and its active size is derived on the target from the configured RAM percentage plus the encrypted writeback mapper capacity.
- the fallback swap partition size is derived from live RAM during installation, then clamped to the dedicated raw swap-partition floor and activated at priority `10` through `/dev/mapper/swap-fallback`.

The storage layout is rendered from the selected concrete profile under `d-i/forky/hosts/profiles/<family>/<role>.env` or, when a manifest-declared `profile` class is selected, from `d-i/forky/hosts/profiles/override/<name>.env`. Shared policy still comes from `d-i/forky/hosts/shared/*.env`, and the filesystem-family runtime helpers still come from `d-i/forky/scripts/runtime/{btrfs,f2fs}.sh`. Secure Boot state mode honors `SECURE_BOOT_MODE` and `SECURE_BOOT_STATE_MODE`; if both are set they must match. When the selected profile resolves that mode to `luks`, the partman recipe declares `/var/lib/shim-signed` directly as an encrypted ext4 partition, seeded through `partman-crypto` so the whole partition is LUKS2-encrypted during partitioning, while the target-side `crypttab` auto-open entry is removed later so the filesystem still stays manual-only after installation. The Btrfs tiers are still reformatted by the finish hook with the explicit `xxhash` checksum profile, and that hook explicitly preloads the Btrfs/hash helpers before the first Btrfs staging mount. The partman finish hook writes tmpfs entries only to the installed target fstab; the installer-facing partman fstab cache deliberately omits tmpfs entries so d-i does not mount volatile tmpfs paths during installation. Late command then cleans the profile-enabled volatile backing paths as its final step before handoff to first boot. On the installed system, `/data/run` is mounted from fstab with `x-systemd.requires-mounts-for=/data` and a fixed `size=100M`, while the other tmpfs mounts use percentage-based `size=%` options. The volatile-directory preparation unit still runs in `sysinit` before `systemd-tmpfiles-setup.service` so `/var/log`, `/var/cache`, and `/var/lib/apt/lists` are already mounted when tmpfiles starts creating boot-time state; shared `20-data-run.conf` creates only the common roots, and the desktop role adds the private media directory and `/data/run/mnt` symlink through `25-desktop-media-runtime.conf`.

Selecting `classes=...,crypto` requires UEFI Secure Boot, a usable TPM2 device,
and a profile with a dedicated non-zero `/home` partition. The generated recipe
uses native `partman-crypto` filesystem stanzas for `/` and `/home`; the
installer's custom automatic-partition action completes pending encrypted-volume
setup before partman validates the root filesystem. This keeps the direct
LUKS-on-filesystem design without any PV, VG, or LV layer, while ensuring that
partman owns the active encrypted mappings. The installer generates one
root-only random bootstrap passphrase from the kernel UUID entropy source,
reuses it across retries, and creates both containers with AES-XTS and a
512-bit XTS key.
After the target packages are installed, the late crypto helper verifies Secure
Boot with `mokutil`, discovers the TPM2 device through `systemd-cryptenroll`,
and enrolls a temporary PCR 7 TPM2 token for root before the first reboot. The
target installs `systemd-cryptsetup` plus `systemd-tpm`, keeps
`initramfs-tools`, and places the custom TPM2 local-top hook ahead of stock
`cryptroot`; that hook embeds `dm_crypt`, the TPM2 kernel drivers, the systemd
TPM2 LUKS token plugin, and its TSS runtime libraries. `/home` is unlocked by a
random key stored at `/etc/cryptsetup-keys.d/crypthome.key` inside encrypted
root; its normal `systemd-cryptsetup@crypthome` activation is generated from
`crypttab` without manually enabling unrelated TPM setup services. On the first
interactive login by the primary user,
`/usr/local/sbin/tpm2-enroll.sh` requires a recovery passphrase of at least 20
characters, explicitly creates its LUKS2 keyslots with Argon2id and a
five-second PBKDF calibration, and asks for a 6-32 digit TPM2 PIN. It replaces
the bootstrap token with TPM2+PIN tokens bound to PCR 7 plus shim/MOK PCR 14,
verifies both TPM2+PIN unlock paths, verifies recovery access and the Argon2id
keyslots, and removes the temporary bootstrap keyslots and passphrase file.
An interrupted enrollment can be rerun with the same recovery passphrase.
Normal boot then asks for the TPM2 PIN once; if firmware, Secure Boot, or MOK
policy changes invalidate PCR policy, the recovery passphrase unlocks root and
the root-contained key unlocks `/home`. A weak or predictable 20-character
phrase is still vulnerable to dictionary guessing; use at least six randomly
generated words or a password-manager-generated random value.

## Serve It On The LAN

Serve the repository tree over HTTP. The explicit directory keeps the seed
reachable even when the command is started from `logs/` or another directory
inside the worktree:

```bash
python3 -m http.server --bind 0.0.0.0 --directory "$(git rev-parse --show-toplevel)" 8000
```

The installer must be able to reach:

```text
http://<lan-host>:8000/d-i/forky/preseed.cfg
```

## Boot The Debian Installer

Boot the Debian installer in expert or advanced mode and append the installation URL plus the early locale answers on the kernel command line:

```text
auto=true priority=critical locale=en_US.UTF-8 language=en country=US url=http://<lan-host>:8000/d-i/forky/preseed.cfg
```

Use `auto=true` literally, not just `auto`. Debian Installer asks localization questions extremely early; `auto=true` is what delays them until after network answer-file automation is available, and the explicit `locale`/`language`/`country` boot parameters provide a second, early-safe answer path.

The served seed base is the containing `d-i/forky/` directory, not the repo
root. With `url=http://<lan-host>:8000/d-i/forky/preseed.cfg`, the runtime
normalizes that to `http://<lan-host>:8000/d-i/forky`; with
`file=/media/usb/d-i/forky/preseed.cfg`, it normalizes to
`/media/usb/d-i/forky`. It then fetches sibling phase entrypoints such as
`scripts/preseed/answers.sh`, `scripts/early/dispatch.sh`,
`scripts/partman/dispatch.sh`, and `scripts/late/dispatch.sh` below that tree
through the shared bootstrap helper.

The class-group contract is defined by `d-i/forky/classes/install.conf` plus the records under `d-i/forky/classes/configs/*.cfg`. During installation the runtime compiles those config files into `state/plan.tsv` and `cache/classes.state.conf`, then resolves the selected class set from that generated plan. Most groups allow at most one selected class; `gpu` and `addon` may select multiple classes. The installer auto-detects `arch`, `cpu`, `gpu`, and `disk` classes through `d-i/forky/scripts/preseed/class-auto.sh` and appends them to the manual `classes=` value. A manual class from an auto group overrides detection for that group. NVIDIA is intentionally not auto-selected; add the `nvidia` addon class when the proprietary NVIDIA stack should be installed on hosts with detected NVIDIA display hardware.

Manual `class-select` groups are:

- `site`: `prod`, `lab`, `dmz`
- `role`: `desktop`, `server`
- `security`: `standard`, `enhanced`
- `network`: `dhcp`, `static`

Auto `class-auto` groups are:

- `arch`: `amd64`, `arm64`
- `cpu`: `intel`, `amd`
- `gpu`: `intel-uhd`, `amd-radeon`, `generic`
- `disk`: `nvme` (generic bare-metal Btrfs/XFS baseline), `emmc`, `vm`

The current optional manual groups are:

- `service`: `web`, `db`, `gitlab-runner`
- `profile`: direct `d-i/forky/classes/class-profile/<name>.cfg` files, including `btrfs-de`, `btrfs-de-dual`, `btrfs-de-main`, `btrfs-de-dual-main`, `btrfs-de-flex`, `btrfs-de-dual-flex`, `f2fs-de`, `f2fs-de-dual`, `f2fs-de-cbook`, `f2fs-de-dual-cbook`, `btrfs-gitlab-runner-srv`, `btrfs-gitlab-runner-srv-dual`, and `f2fs-pihole-srv`
- `debug`: `debug`
- `apps`: direct `d-i/forky/classes/class-apps/<name>.cfg` files, including `microsoft-visual-code`, `microsoft-edge`, `vivaldi`, `powershell`, `mullvad`, `spotify`, and `retroarch`
- `addon`: direct `d-i/forky/classes/class-addon/<name>.cfg` files, including `crypto`, `software`, `crowdsec`, `cuda`, `devops`, `nvidia`, `podman`, `server-suite`, `ssh`, `tailscale`, `timeshift`, and `wifi`

Bare class tokens are resolved across the manifest-declared classes, so the normal compact form is still:

Example:

```text
classes=lab,desktop,standard,dhcp primary_user=<user> primary_password=<user-password> root_password=<root-password> fruux_username=<fruux-user> fruux_password=<fruux-app-password>
```

`classes=default` is a special alias. When `default` appears anywhere in the
manual class list, the installer expands it from `DEBIAN_DEFAULT_CLASSES` in
`d-i/forky/repo.env`, then applies the normal auto-detected `arch`, `cpu`,
`gpu`, and `disk` classes on top of that expanded manual set.

The `desktop` role does not auto-select `addon/software`. The monolithic app bundle
is enabled only when `software` is present in `classes=...`, and the per-app
`apps/*` classes are an alternative to that bundle rather than an additive
layer on top of it. Selecting `apps/vivaldi` installs the Vivaldi archive and
package while the desktop role stages the managed `/etc/vivaldi/policies`
tree. Selecting `apps/retroarch` installs both `retroarch` and
`retroarch-assets` while the desktop role stages the managed RetroArch
configuration. Selecting either `addon/software` or `apps/mullvad` keeps
`mullvad-browser` in `pkgsel`, then installs `resolvconf` and `mullvad-vpn`
during `late_command`. The helper seeds
`resolvconf/linkify-resolvconf=true` directly into the target, installs the
Debian `resolvconf` package, validates the package-saved original resolver,
and republishes it as the installer-only `installer.netcfg` record under
`/run/resolvconf/interface/`. Because Debian Installer's `in-target` helper
temporarily bind-mounts the installer's `/run` over `/target/run`, the resolver
publication runs afterward through a raw chroot and first rejects any remaining
`/target/run` mount. This ensures the record and generated resolver are written
to the target's own run tree instead of disappearing during `in-target`
cleanup. The same raw-chroot path verifies that `/etc/resolv.conf` resolves to
`/run/resolvconf/resolv.conf` and probes Mullvad, Bitwarden, and GitHub before
performing any Mullvad download. It repeats that resolver publication and
validation after installing `mullvad-vpn`, so package triggers cannot leave
later selected-class or desktop downloads without DNS. Isolating resolver
linkification from the shared `pkgsel` transaction prevents it from changing
DNS underneath unrelated package maintainer scripts and gives any resolver
failure an explicit late-command log label. The installer resolver record lives
only under `/run` and does not become persistent first-boot DNS policy.

The installer then downloads Mullvad's official architecture-specific latest
Debian artifact, its matching detached signature, and code-signing key, pins
the published primary key fingerprint, validates package name and architecture,
and only then hands the local package to target APT. This avoids
release-transition failures where the repository index still names a versioned
pool object that has already been removed, while retaining the Mullvad
repository for browser installation and future package updates. The class also
preserves the supported `/etc/resolv.conf` linkification answer and stages the
root-owned
`/etc/systemd/system/mullvad-daemon.service.d/20-managed-dns.conf` drop-in.
That drop-in forces Mullvad's DNS integration to the `resolvconf` backend and
points the daemon at the systemd-managed persistent
`/var/lib/mullvad-version-cache` state directory. It requires
`systemd-tmpfiles-setup.service`, orders the daemon after both that service and
`local-fs.target`, and requires the cache path's backing mount. The dedicated
tmpfiles policy creates the root-owned directory with mode `0755` and
`version-info.json` with mode `0644` before the daemon's first cache read;
Mullvad remains responsible for replacing the file with valid cache data. The
installer stores no Mullvad account identifier, performs no login, and does not
request an automatic VPN connection. The desktop GLib policy also disables
unsolicited GVFS WSDD discovery so it does not probe VPN, Incus, or other
managed interfaces.

AppArmor is enabled globally in enforce mode, while application profiles are
assigned per-profile modes by `/etc/apparmor/managed-modes.conf`. Every desktop
and desktop-override host profile sets `DESKTOP_APPARMOR_STATE` to either
`enforce` or `complain`. Profiles can keep the hardened `enforce` default or
select `complain` while troubleshooting. During target staging, that value is applied consistently to
the default-enforced repository-managed desktop wrappers and application
profiles plus the package-owned Code, Chromium, Microsoft Edge, Mullvad Browser,
and Vivaldi profiles that receive repository-managed local rules. Setting it to `complain`
installs the same policy without blocking operations, so denials can be reviewed
before changing the host profile back to `enforce`. Profiles
using the managed desktop least-privilege abstractions run in the selected mode,
including Bitwarden, QoreDB, Gridline, Filen, KeepassXC, Ledger Live, Postman,
qBittorrent, RetroArch, Spotify, SQLite Browser, Telegram, Totem, Tuta Mail,
and Zoom. The private Zoom/Discord Xwayland child additionally keeps only the
observed inherited helper set, owner-only compiled keymap, Qt shader-cache, and
Zoom atomic configuration paths, plus read-only CPU, PCI, power-supply,
iproute2, and portal metadata. Those compatibility allowances remain inside
the existing Bubblewrap child and add no generic home-tree access, writable
procfs or sysfs access, capability, broad signal rule, or unconfined execution.
The shared desktop abstraction permits desktop IPC, portal-selected files,
Intel/Mesa render nodes, and Debian's maintained NVIDIA graphics interface
without granting DRM primary/control nodes, CUDA/UVM devices, broad system-tree
reads, all-home access, or all removable-media access. Chromium and
Electron-only namespace, `io_uring`, POSIX message-queue, shared-memory, and
same-user process bookkeeping rules live in a separate abstraction. Network,
audio, camera, input, USB, hidraw, trusted application trees, mutable state,
and user-data directories remain limited to the individual applications that
require them. Discord's versioned voice encoder inherits the Discord profile
instead of entering a generated `//null-*` child, and Crashpad memory reads
remain owner-only under the existing same-profile ptrace boundary. Ledger Live
receives its observed PipeWire, HID descriptor, terminal, and legacy
`~/.config/Ledger Wallet` state access. Mullvad Browser has reciprocal,
kill-only signaling with its Bubblewrap child plus exact MIME, cgroup, device
enumeration, cache-parent, and helper permissions. Tuta Mail accelerometer
polling and Chromium attempts to create the root-owned package extension
directory are explicitly denied because neither operation belongs to the
application's functional boundary. The shared desktop policy uses strict local
name lookup only;
networked applications receive IPv4/IPv6 TCP and UDP access explicitly. Sleek
uses that bounded network contract, while SQLite Browser receives only the
datagram and netlink access used for local interface discovery; KeePassXC
remains without network access. Same-owner
temporary-file access is also declared per application instead of inherited by
the shared graphics boundary. Additional user-selected data roots must be
added through the profile's `/etc/apparmor.d/local/*` include instead of
widening the shared policy. PowerShell remains in complain mode because it is
an administrative shell intended to execute arbitrary host commands, and it
does not inherit the desktop or GPU abstractions.
Every repository-owned desktop wrapper under `/usr/local/bin`,
`/usr/local/libexec`, and `/usr/local/sbin`, plus `xssh-send`,
`xssh-retrieve`, the AppArmor mode reconciler, and the TPM2 enrollment
launcher/helper pair, has a distinct attachment in
`/etc/apparmor.d/managed-desktop-wrappers`. Rendered session and privileged
helper templates are covered by their installed paths rather than their
repository `.tmpl` names. Shared wrapper abstractions provide only the
interpreter and required session IPC; they add no network or home-directory
access. Each profile grants its own bounded state, configuration, report,
capture, or administrative paths. Calls between managed wrappers use strict
profile transitions with read access for preflight checks. Named targets are
used except for the large Computer Management fan-out, where AppArmor resolves
the same exact attachments from the executable paths without exceeding its
per-profile named-transition limit. `labwc-session` retains the one compositor
singleton lock in its session wrapper while closing the descriptor in the
Labwc child. Long-running session components use user-systemd singletons bound
to `labwc-session.target` instead of component lock parents.
The frequently polled Bluetooth status wrapper validates the managed non-root
session from `LABWC_SESSION_OWNER` and `XDG_RUNTIME_DIR` with shell built-ins
instead of spawning `id` on every Waybar refresh. The same managed-session
guard now covers the brightness, capture, and system-action wrappers, so their
status and launcher paths also avoid redundant identity helpers. Fuzzel,
swaylock, and the Labwc session keep singleton locks on the wrapper side of
the boundary, preventing package-owned executables from inheriting those lock
descriptors. Meanwhile,
long-running package applications and privileged
system tools leave the short-lived wrapper domain. Managed application
launches use strict profile transitions, including the canonical Code,
Discord, and Vivaldi executable paths, so a missing attachment fails closed
instead of creating an unconfined `//null-*` fallback domain. The enforced set contains 69 installed-path
attachments when `DESKTOP_APPARMOR_STATE=enforce`; the same attachment set is
loaded in complain mode when `DESKTOP_APPARMOR_STATE=complain`.
Code, Chromium, Microsoft Edge, Mullvad Browser, `vivaldi-stable`, and
`vivaldi-bin` retain their package-owned attachment profiles but run in enforce
mode with separate repository-managed `/etc/apparmor.d/local/*` rules for each
application. Vivaldi's short-lived shell wrapper has only the interpreter and
five read-only startup helpers it requires before an explicit transition into
the separately confined `vivaldi-bin`; managed launches disable its optional
per-user codec downloader and use the package-installed root-owned codec.
Long-running application rules grant only the application's installation tree,
state, required network/audio/camera interfaces, shared GPU abstraction, and
explicit user-data roots. `vivaldi-bin` additionally receives read-only access
to `/etc/vivaldi/policies/managed/**` and
`/etc/vivaldi/policies/recommended/**`. Other package-owned browser, service,
container, build-tool, and vendor profiles remain in complain mode until
representative workload `ALLOWED` events have been reviewed, so normal use is
logged rather than blocked. Tailscale's daemon and CLI share a repository-managed
`usr.sbin.tailscaled` attachment in complain mode; it covers their managed state,
local API socket, TUN device, control-plane transport, and router netlink
boundary without interrupting the first-boot join flow while the remaining
workload-specific accesses are observed. The redundant `msedge` alias profile
is disabled so it cannot compete with the `microsoft-edge-stable` attachment.
The mode helper
creates the canonical disable symlink directly instead of asking `aa-disable`
to scan a directory that temporarily contains both exact attachments.
Installer-managed profiles cover every `apps/*` selection plus the managed
software launchers for Bitwarden, Obsidian, Postman, Sleek, Filen, Discord,
Ledger Live, Tuta Mail, Zoom, Telegram, qBittorrent, KeepassXC, and RetroArch.
The
`apparmor-managed-modes.service` unit reapplies and verifies the declared modes
after `apparmor.service` on every boot and whenever AppArmor is reloaded,
including reloads triggered by package upgrades. Reconciliation also removes
temporary per-profile audit flags, preventing successful accesses from
continuing to flood the audit pipeline after a diagnostic session.
The installer recompiles every enabled entry in
`/etc/apparmor/managed-modes.conf` after source-mode reconciliation, including
package-owned profiles with repository-managed local includes.
The parser uses Debian's package-owned
`/usr/share/apparmor-features/features` ABI file. The installer neither pins a
versioned feature snapshot nor overwrites that package-managed path, so AppArmor
package upgrades control the policy feature baseline.

The desktop baseline installs BlueZ, `bluetoothctl`, `btmgmt`, and `rfkill`.
BlueZ remains on its stable D-Bus interfaces over the managed dbus-broker
system bus, auto-enables controllers, and applies secure dual-mode and reconnect
policy from `/etc/bluetooth/main.conf`. BlueZ starts independently of the
optional hardened `bluetooth-controller-init.service`; after `bluetooth.service`
is active, that bounded oneshot requests power-on for at most eight detected
controllers without delaying or failing the BlueZ daemon. Each BlueZ 5.85
`btmgmt` request is wrapped in a separate coreutils timeout because that client
can outlive its own non-interactive timeout; stdin is closed and the whole
oneshot remains bounded. The managed BlueZ configuration omits
`KernelExperimental` so the daemon keeps its disabled default without parsing
`false` as an experimental UUID. Secure Connections, privacy, controller mode,
reconnect, and auto-enable policy remain owned by BlueZ. Waybar places network,
Bluetooth, keyboard-layout, and screenshot modules inside one `quick-controls`
pill while preserving each icon's independent click actions. The Bluetooth
icon-only `` control sits immediately to the right of the network module;
left-click opens interactive `bluetoothctl` immediately with a
`KeyboardDisplay` pairing agent, while right-click opens a compact Fuzzel
action menu with quick scan, pair, connect, and disconnect entries plus nested
device and adapter management.
The keyboard-layout action uses a delayed, non-blocking single-flight lock
before changing layouts. Rapid clicks therefore collapse into one toggle after
Waybar has released the pointer event instead of leaking the action into later
desktop clicks.
The optional initializer never unblocks Bluetooth itself: it preserves hardware
and software rfkill policy, waits briefly for controllers, and leaves later
hotplug to BlueZ.
Controller power changes, pairing readiness, and Bluetooth failures are sent to
Mako. The desktop baseline also disables the vendor `mpris-proxy.service`
default-target autostart, so BlueZ media metadata forwarding does not start
before the rest of the audio session is ready. The brightness button is an
always-visible custom module backed by `brightnessctl`, so systems without a
controllable backlight show `N/A` instead of silently dropping the module.
Brightness scroll, the standard `XF86MonBrightness*` keys, and Super-F5/F6 all
use the same validated helper.

The primary application shortcuts are `Super+F` for Thunar, `Super+B` for
Vivaldi, `Super+T` for the managed Foot terminal, `Super+E` for Tuta Mail,
`Super+P` for Bitwarden, `Super+W` for Wayscriber, `Super+S` for Spotify,
`Super+C` for Qalculate, and `Super+O` for Filen. The existing power menu and
output-refresh actions remain available on `Super+Shift+P` and
`Super+Shift+O`.

The same application actions are also available on
`Ctrl+Alt+F/B/T/E/P/W/S/C/O/A`, including `Super+S` and `Ctrl+Alt+S` for Spotify.
`Ctrl+Alt+Space` opens the Fuzzel application launcher.

Foot and the Kitty fallback render their font family and size from the selected
desktop profile through `LABWC_TERMINAL_FONT_FAMILY` and
`LABWC_TERMINAL_FONT_SIZE`; the managed profiles preserve the existing
`Noto Sans Mono` size `12` baseline.

Each new interactive Bash or Zsh instance in Foot or Kitty sources readable,
non-symlinked `~/.profile.d/[0-9][0-9]-*.sh` fragments in lexical order. Login
shells keep the fragments single-loaded, while non-login terminal shells still
pick up managed addon helpers such as development, firmware, and Incus
commands. Zsh keeps its general completion cache but disables persistent
`DEBS_*` package caches for `apt`, `apt-get`, `apt-cache`, and `apt-mark`, so
`sudo apt install <TAB>` builds candidates once in memory per shell without
re-sourcing a malformed `DEBS_avail` file. Nano uses the managed XDG
configuration at
`~/.config/nano/nanorc`, with line numbers, indentation and navigation
defaults plus the standard, Debian-specific, and extra syntax-color bundles
shipped by the installed `nano` package.

Waybar keeps the existing `LABWC_WAYBAR_*` values as the external/default bar
dimensions and adds `LABWC_WAYBAR_INTERNAL_*` overrides for the internal-output
bar. The internal family covers bar height, taskbar/tray icons, font size, menu,
workspace, taskbar and application buttons, compact status modules, quick
controls, and lock/power button widths and padding.

`Super+M` and `Ctrl+Alt+M` open the searchable **Computer Management**
Fuzzel launcher.
Its folder-style categories are Container Management, Remote Desktop,
Endpoint Security, Digital Assets, Users & Groups, Network Management, Firewall
Security, System Configuration, Phone Management, Backup & Recovery, and
Hardware & Peripherals. The previous
`Ctrl+Super+A`, `Ctrl+Super+N`, `Ctrl+Super+P`, and `Ctrl+Super+R` bindings are
retired so every management workflow has one predictable entrypoint. Each
category can override the shared Fuzzel menu sizing through
`LABWC_FUZZEL_<CATEGORY>_WIDTH`, `LABWC_FUZZEL_<CATEGORY>_LINES`, and
`LABWC_FUZZEL_<CATEGORY>_FONT_SIZE`, where `<CATEGORY>` is
`CONTAINER_MANAGEMENT`, `REMOTE_DESKTOP`, `ENDPOINT_SECURITY`,
`DIGITAL_ASSETS`, `NETWORK_MANAGEMENT`, `SYSTEM_CONFIGURATION`,
`PHONE_MANAGEMENT`, `BACKUP_RECOVERY`, or `HARDWARE_PERIPHERALS`.
**Computer Management → Digital Assets** provides DOCX, PDF, and image
conversion, inspection, metadata, page-manipulation, repair, optimization,
watermark, and extraction actions. It accepts bounded regular files selected
from `~/Downloads`, `~/Documents`, or `~/Desktop`, never overwrites an input,
and writes private results under `~/Documents/Digital-Assets`. Pandoc uses the
pinned `/usr/local/bin/typst` PDF engine, avoiding a LaTeX installation; the
installer also checksum-verifies pinned `pdfcpu` and Typst archives. It builds
the `pdf2docx` and `pymupdf4llm` Pipx environment with a temporary locked
non-root account below `/usr/local/lib/digital-assets`, removes that build
identity and its private state, then seals the shared runtime as `root:root`.
Document actions continue to run as the logged-in desktop user.

PDF content editing is explicitly a reflow workflow: it extracts a Markdown
working copy, opens FocusWriter with its native Wayland backends forced, then
rebuilds the edited PDF with Pandoc and Typst. It cannot preserve original page
geometry, forms, signatures, annotations, or exact layout. PDF bookmark editing
exports a private `bookmarks.json` working copy, opens it in Nano, then imports
the edited bookmark tree into a new validated PDF. Hyperlink and typo editing
instead uses QPDF QDF streams with a bounded literal byte replacement and
`fix-qdf`; that operation invalidates signatures and does not preserve source
encryption.
Read-only inspection and fixed privileged actions are separated, mutating recovery
operations require an explicit confirmation, APT dependency repair refuses
package removals, Timeshift selects
Btrfs or rsync mode from the root filesystem, and pkexec remains limited to
active local sudo users. Labwc suspend, reboot, and power-off use one foreground
`systemctl` request through login1 and Polkit, retaining the single
administrator authentication for the selected power transition. Endpoint
Security no longer
duplicates port inspection or Nmap entries; listening-port, localhost, LAN, and
explicitly authorized WAN scans live under Network Management and use its
single bounded privileged helper. ClamAV
status plus report-only file and recursive folder scans run unprivileged,
reject files above 512 MiB rather than silently skipping them, avoid symlinks
and filesystem crossings, and use 15-minute and 45-minute ceilings. The managed
official plus curated signature refresh runs daily without competing vendor
timers. Security also retrieves SHA-256 and SHA-512 for a selected file,
verifies a file against a validated SHA-256 digest, and creates private
recursive SHA-256 manifests below
`~/.local/state/labwc/security-reports`. Folder manifests stay on one
filesystem, skip symlinks, and are bounded to 50,000 files and 100 GiB.
**Computer Management → Network Management → Network Scanning** opens the
five-category scanner for Wireshark, Dumpcap, tcpdump,
TShark, and private-network Nmap workflows. Its Nmap category also owns
listening TCP/UDP port inspection plus localhost, LAN, specific LAN host, and
explicitly authorized WAN host scanning.

**Computer Management → Users & Groups** owns account-oriented inspection:
user accounts, non-sudo users, groups, sudo administrators, empty password
hashes, and active sudoers policy. These entries are no longer mixed into
Endpoint Security.

**Computer Management → Network Management** also provides saved connection
activation and deactivation, OpenVPN and WireGuard activation/import, and DNS
status, automatic-DNS restoration, IP-only custom DNS configuration, and cache
flush actions. Imported profiles must be canonical, non-symlink, desktop-user
owned files no larger than 1 MiB and must not be group- or other-writable.

**Computer Management → Firewall Security** manages a bounded persistent set
of incoming and outgoing TCP/UDP port rules. Rules can allow or block any
source/destination, allow LAN ranges, or allow one validated IPv4/IPv6
address/CIDR. The privileged helper writes only the dedicated
`/etc/nftables.d/95-firewall-security.nft` fragment, validates the complete
`/etc/nftables.conf`, reloads `nftables.service`, and restores the previous
state and rules if validation or reload fails.
All five top-level tool categories use the same folder-style icon as the
maintenance launcher's Security, System, and Recovery categories.
Debian's `wireshark-common` package is reconfigured noninteractively for
capability-based capture, only `dumpcap` may carry the two capture
capabilities, Wireshark and TShark remain non-setuid capability-free user
binaries, and only the primary desktop account is added to `wireshark`.
Captures are private below `~/Captures/network-scanning`; Wireshark can launch
normally, while the managed `Open Capture` action accepts only files from that
directory. Privileged scans use per-host retry/script ceilings, total wall-clock
timeouts, and conservative packet-rate limits. They accept `/24` through `/32`
private CIDRs or explicitly authorized public WAN IPv4 hosts, while public
CIDRs and special-use destinations remain rejected. Approved-service checks use
separate, range-aware TCP and UDP catalogs covering common infrastructure,
storage, database, messaging, observability, VPN, and application ports. The
desktop role installs Lua 5.5 and validates every managed NSE script with
`luac5.5` on the target.

**Computer Management → Phone Management** opens the managed **Android Debug
Bridge** Fuzzel launcher.
Desktop installation downloads Google's current
`platform-tools-latest-linux.zip` directly over HTTPS, bounds both compressed
and extracted sizes, rejects unsafe or duplicate archive paths and unsupported
node types, verifies the required payload and x86-64 ELF architecture, records
the resolved `Pkg.Revision` plus archive SHA-256, installs the full bundle below
`/usr/local/lib/android-sdk/platform-tools`, and links only `adb` and `fastboot`
into `/usr/local/bin`. The installer never invokes `adb`. It installs an
on-demand, per-user `labwc-adb-server.service`, which starts only when **Start
ADB Server** is selected in the launcher and stops with the Labwc session. An
already-running server that stops responding is restarted only for the current
desktop user with bounded probes. Device actions wait up to 60 seconds for the selected serial to
appear again, reconnect offline transports, and explain USB permission,
offline, and RSA authorization failures. The launcher provides server control,
shell and device inspection, APK and file operations, screenshots, screen
recording, logcat, bugreports, wireless pairing and connection, port forwarding,
confirmed reboot modes, and non-flashing fastboot inspection/reboot actions.
A managed debug-interface-only udev policy covers common Google, Samsung,
Motorola/Lenovo, Sony, LG, HTC, Huawei/Honor, Xiaomi, OPPO/OnePlus, Nokia/HMD,
ZTE, ASUS, Amazon, Fairphone, Qualcomm, and MediaTek identifiers. Preseed only
stages that policy and enrolls the primary desktop account in `plugdev`; it
does not attempt to exercise or verify udev device behavior during installation.
The **Reboot & Recovery** category also provides **Backup Device**, **Download
Official Samsung Firmware**, **Flash Official Firmware (Keep Data)**, and
**Flash Official Firmware (Factory Reset)**. Backups are private, atomic
directories below `~/Android/adb/backups`: they copy all ADB-readable shared
storage, device/package/settings metadata, integrity hashes, a bugreport when
permitted, and a legacy `adb backup` archive when both client and device still
support that deprecated protocol. Android production security prevents ADB from
copying every app's private data, hardware-backed keys, or protected system
partitions, so the launcher states those limits explicitly instead of claiming
an impossible bit-for-bit backup.

Samsung firmware support installs the official `samloader-rs` 2.0.0 Linux
x86-64 release from GitHub, pins its release SHA-256, bounds archive download
and extraction, validates the single `samloader` ELF payload and version, and
links it from `/usr/local/bin`. Official firmware downloads are model-matched
against the selected ADB device, decrypted into the private managed firmware
root, extracted through a traversal/symlink/ZIP-bomb-resistant helper, verified
with both `samloader verify-md5` and recorded SHA-256 values, and accepted for
flashing only with the generated provenance manifest. Flashing revalidates the
selected device model and every firmware component, requires exactly one
supported Samsung Download Mode USB device, and uses strong typed
confirmations. The keep-data action passes `HOME_CSC_*.tar.md5` to
`samloader flash -s`; the factory-reset action passes `CSC_*.tar.md5`. The
factory-reset path is destructive, and HOME_CSC is only a preservation request,
not a backup guarantee.

**Computer Management → Remote Desktop** opens the managed RDP frontend for the
SDL3 client staged by `freerdp-sdl`. The compatibility desktop entry remains
installed with `NoDisplay=true` for MIME associations, while **Computer
Management** is the only searchable management application. The launcher resolves
either `sdl-freerdp` or the older `sdl-freerdp3` binary, always forces SDL's
Wayland video backend, removes the X11 display fallback from the client
environment, and provides a root-owned GTK askpass helper through
`FREERDP_ASKPASS` for masked password entry. It records only client diagnostics
in a private per-user log and reports unreachable-host failures with the saved
target address and log path. Direct
connections expose no local folder; shared connections accept only an existing
directory below the authenticated account's home or matching removable-media
root and redirect it as the `Shared` drive; mutable `HOME` and `USER`
environment values cannot widen that boundary. Saved shared paths remain
manageable while removable media is offline, but the directory is resolved,
authorized, and required to be readable again immediately before launch. The
launcher supports dynamic, fixed, full-screen, and
multi-monitor display modes; dynamic windows use FreeRDP dynamic resolution
without the mutually exclusive smart-sizing flag. Network and audio profiles,
optional clipboard, microphone, printer, and administrative-session redirection,
and normal remote-certificate approval or strict system-trusted validation.
Saved connections use a private mode-0600 JSON store and retain connection
metadata but never passwords; FreeRDP requests credentials through the protected
askpass dialog for each connection. The default certificate policy leaves
`/cert` unset so the SDL3 client shows the remote server certificate and lets
the user trust it temporarily, trust it permanently, or cancel. Strict profiles
add `/cert:deny`. The launcher does not generate a local RDP certificate or key
and does not maintain a parallel TOFU/reset workflow; permanent approvals remain
owned by FreeRDP in the user's configuration.

The desktop role installs Taskwarrior and `taskwarrior-tui` with a shared XDG
configuration at `~/.config/task/taskrc`. Task data is kept under
`~/.local/share/task`, and managed Pending, In Progress, and Completed reports
share the desktop terminal palette with dedicated Taskwarrior TUI styling.
Taskwarrior remains available from the application launcher and managed
terminal without occupying permanent Waybar space.

The desktop package baseline also installs Liferea. Managed GLib defaults use
the system browser for external links, refresh feeds hourly, retain 500 items
per feed, keep JavaScript and WebKit plugins disabled, enable reader mode plus
tracking protection, and send Do Not Track and Global Privacy Control headers.
System and primary-user MIME defaults route RSS, Atom, RDF, and `feed:` links
to Liferea.

Labwc owns the desktop-session readiness boundary through
`labwc-session.target`; greetd's generic graphical session state is not used to
start Waybar. The target disables systemd's default target-after-member
ordering and becomes active before Waybar and the other session-bound user
services. Custom Labwc, KWallet, Whisper, notification, and timer units are
tracked under
`/etc/skel/.config/systemd/user/`, copied only into the managed desktop account,
and enabled through that account's `labwc-session.target.wants/` directory.
Drop-ins for Debian or vendor package units are instead tracked under
`/etc/systemd/user/`, where every user manager sees the same machine policy.
Those global drop-ins require the imported managed-Labwc environment, so the
greeter's separate user manager skips portal, audio, notification, policy-agent,
terminal-server, and related package units before the desktop session is ready.
The D-Bus broker hardening drop-in is also system-wide because it constrains
every user manager. Because systemd drop-ins cannot
remove dependency directives from Debian's vendor unit, the role installs a
complete Waybar user-unit override with no `graphical-session.target`
relationship. It is ordered after and made part of `labwc-session.target`,
without a hard `Requisite=` edge that can turn session-start timing into a
dependency failure, and is not enabled from any user target. The greeter
remains outside this user-service lifecycle. Its Labwc session
client owns the output watcher and power UI child PIDs, terminates both when
gtkgreet exits, and the output watcher terminates its own `udevadm monitor`
child before returning. The watcher also checks its declared greeter-client
parent while waiting for DRM events, so an unexpectedly lost parent cannot
leave an `_greetd` watcher behind across the desktop login.
`labwc-autostart` imports the compositor environment, including `LABWC_PID`,
activates `labwc-session.target`, waits for the KWallet portal, KWallet daemon,
Hyprland polkit agent, selected desktop portals, and a usable output, and only
then requests Waybar when `LABWC_ENABLE_WAYBAR` is enabled. The KWallet and
polkit services start eagerly through the session target; account-local
KWallet D-Bus activation files remain a recovery path rather than the primary
startup mechanism. No Labwc identity is installed through
`/etc/environment.d`; that global path would also affect the greeter, while the
session wrapper and autostart import provide the live compositor-owned values
only after Labwc has created its Wayland socket. `labwc-output-watch.service`
waits for a
usable Wayland output and
applies the initial output policy before session components ordered after it
start, and systemd restarts the watcher if its DRM monitor returns unexpectedly.
The target owns `swaybg.service`, `kanshi.service`, `swayidle.service`, and
`crystal-dock.service`; each is stopped with the session target and has no
persistent component lock. The Waybar logout helper only requests
`labwc --exit`; Labwc then runs the shutdown hook from the compositor lifecycle,
outside Waybar's service cgroup. The compositor wrapper clears imported
compositor variables after Labwc exits but never stops user services or
targets; the systemd user manager remains the sole owner of unit teardown.
The managed Waybar unit uses the rendered config and style paths directly, sets
the custom-helper `PATH`, and stops with the session target without a
direct-process fallback.
Suspend, reboot, and power-off remain in the initiating
`labwc-admin-action` process. The helper validates the managed Wayland runtime,
the active Labwc target, and the active Hyprpolkit listener, then runs the
matching foreground `systemctl suspend`, `systemctl reboot`, or
`systemctl poweroff` request. The power verb follows systemctl's normal
login1/Polkit path, and the managed login1 policy returns `AUTH_ADMIN`, so
Hyprpolkit displays the administrator-password prompt before the transition
starts. A rejected, cancelled, or failed request leaves Labwc and
`labwc-session.target` running and produces a persistent critical Mako
notification. The helper never invokes the Labwc lifecycle hook, acquires a
recursive shutdown inhibitor, pre-stops user units, or starts, stops, or
restarts the authorization agent.
Labwc alone invokes `.config/labwc/shutdown` during compositor termination.
The hook validates its invocation mode and exits without stopping services or
targets, signalling processes, unmounting GVfs/FUSE paths, clearing the
clipboard, or issuing a global `sync`. Labwc launches the hook asynchronously
while compositor termination proceeds; systemd's user manager owns the
resulting ordered unit teardown.
`gvfs-daemon.service` uses `KillMode=mixed` with a 15-second stop ceiling:
GVfs first receives a normal daemon stop so it can release its FUSE and mount
helpers, while systemd retains a bounded final cgroup cleanup if graceful
teardown stalls.
`hyprpolkitagent.service` belongs to the target through `PartOf=`, restarts
failed agent processes with a bounded start-rate policy, and has a ten-second
stop ceiling. An explicit target stop therefore does not restart it after the
compositor begins teardown. `telpoll.service` receives the same target
stop, interrupts a blocking poll on `SIGTERM`, terminates its complete control
group, and retains a five-second stop deadline. Only `btrfs-de-main` enables
the poller, and its per-user nonblocking lock prevents a second local daemon
from sharing that account state. Telegram's `getUpdates` lease is global to
the bot token, however: that token must not be used by any other host, service,
or manual poller. A Telegram HTTP 409 naming another `getUpdates` request is
therefore an external ownership conflict, not an offset or retry failure; stop
the other poller or provision a distinct bot token before restarting Telpoll.
The health notifier installs
its cancellation trap before display preflight and its ten-second coalescing
delay; no separate `ExecCondition` control process can be killed into a failed
state during logout. The package-owned polkit helper keeps upstream exit status
2 and additionally classifies shutdown `SIGTERM` as clean without changing any
authorization rule or result. Whisper recording,
persistent-server, and transcription units verify the active session target
before starting and use five-second stop ceilings. The controller resets
recording or transcription state only when systemd reports that specific unit
failed.
The greeter owns only tty1 and deliberately leaves `Ctrl+Alt+F2` through
`Ctrl+Alt+F6` unbound, so the normal Linux VT path reaches the recovery gettys
on tty2 through tty6. `Ctrl+Alt+F1` consequently returns to the tty1 greeter;
the greeter power helper retains only reboot and power-off actions.

The `desktop` role also installs the pinned Satty `0.21.1` x86-64 release from
GitHub after validating the archive size, member paths and types, expected
payload, ELF architecture, and SHA-256
`63816f3f797950751881147eeb0eb999f14efc8c613adb9937672e6a2df18120`.
Because that upstream binary requires `GLIBC_2.43` while Forky still carries
glibc `2.42`, `apt.cfg` exposes Debian Experimental as `apt-setup/local20`.
Both desktop and server target policies pin that archive by its actual Release
identity (`a=experimental,n=rc-buggy`) at priority `1`, so it does not become a
normal package candidate. The late hook downloads exact amd64 versions of both
`libc6=2.44-1` and its `libc-gconv-modules-extra=2.44-1` dependency from an
immutable Debian Snapshot URL. It enforces HTTPS-only transport and redirects,
bounded retry, timeout, and size limits; validates their package metadata,
dependency contract, sizes, and pinned SHA-256 values; then extracts both into
the versioned per-application runtime `/opt/glibc/2.44-1/satty` with
`dpkg-deb -x`. Private application runtimes therefore share the
`/opt/glibc/<package-version>/<application>` hierarchy instead of creating
separate top-level `/opt` roots.
The target's existing `libgcc-s1` runtime is required and verified; the
`gcc-16-base` package is not needed because it contains no runtime library. The
hook never runs `apt install`, `apt-get install`, or `dpkg -i` for these packages.
`/usr/local/bin/satty` launches the upstream binary through the private loader
and library path; the system `libc6` package is not upgraded or replaced. The
release desktop entry, icon, man page,
documentation, and shell completions are installed under managed system paths,
while `~/.config/satty/config.toml` enables clipboard integration through
`wl-copy` and saves annotated images below `~/Pictures/Screenshots`.

The desktop role installs Wayscriber from the vendor-signed
`https://wayscriber.com/apt stable main` archive through `apt-setup/local21`.
The vendor key is fetched from
`https://wayscriber.com/apt/WAYSCRIBER-GPG-KEY.asc`, and `wayscriber` remains a
normal APT-managed package. Its user service is detached from the vendor's
generic enablement target and attached to `labwc-session.target` with explicit
Wayland-session conditions, bounded restart policy, and clean session teardown.
The Labwc service drop-in disables Wayscriber's vendor tray integration because
Waybar exposes a dedicated glyph immediately to the right of `ext/workspaces`;
the apps drawer follows it and expands to Foot, Thunar, Tuta Mail, FeatherPad,
and Sleek glyph launchers. Tuta Mail and Sleek use their managed
`NvidiaAccelerated` launch mode, while Foot, Thunar, and FeatherPad keep their
direct desktop commands. The drop-in also keeps the unsupported optional
GlobalShortcuts portal probe out of routine logs while preserving daemon error
logging. Tuta's persistent sandbox now receives the primary user's managed
`~/.config/mimeapps.list` read-only so the application can positively detect
that it is the default `mailto` and RFC822 handler.
`/usr/local/bin/labwc-wayscriber-toggle` starts or recovers the daemon when
needed and sends the vendor-supported `wayscriber --daemon-toggle` command with
a bounded readiness retry. Both `Super+S` and the Waybar Wayscriber button use
that helper. Waybar names its eDP, LVDS, and DSI instance `internal`; that bar
uses tighter right-side module margins, padding, and minimum widths while the
external-output bar retains the full-size controls.

Waypaper `2.8` is built with `pipx` under a temporary locked non-root account,
using `--system-site-packages` and `/usr/bin/python3`. The desktop package
baseline supplies `pipx`, `python3-gi`, and
`gir1.2-gtk-3.0`, so the pipx virtual environment reuses Debian's PyGObject
binding instead of attempting a PyPI source build. The installer applies
bounded pip timeouts and retries, isolates the builder's home beneath
`/opt/waypaper`, removes the builder identity and private state, then seals
the completed runtime as root-owned, readable by the desktop user (with
executable runtime files executable by that user), and non-group/other-writable
before any desktop session starts. The only managed executable is the root-owned
`/usr/local/bin/waypaper` entry point; no Waypaper executable remains below
the account's home directory. The user-owned launcher remains at
`~/.local/share/applications/waypaper.desktop` and uses that absolute system
path. Editing that user-owned launcher can run a different program only as the
logged-in desktop user: the managed entry point has no `sudo`, `pkexec`, or
setuid transition. Labwc exposes Wayscriber under Productivity and renders
Waypaper under Desktop Settings.
Waypaper is limited to `/usr/share/backgrounds/desktop` and runs with its
selector-only backend. Its post-command atomically records each validated,
non-executable PNG or JPEG selection in
`~/.local/state/labwc/wallpaper`, then asks the user manager to restart the
single systemd-owned `swaybg.service` instance. Labwc restores that selection
on the next session and falls back to the managed
`wallpaper-1920x1080.png` when the state is missing or invalid. Additional
managed wallpapers are validated and extracted from the role archive during
installation, while the archive itself is removed from the target.

Inside the `quick-controls` pill, Waybar places a camera-only button immediately
to the right of the keyboard layout button at the same minimum width. A normal
left-click selects a rectangle with Slurp, captures it with Grim, and opens
Satty, including while a recording is active. Middle-click stops and finalizes
an active recording. Right-click
opens a Fuzzel menu for stopping an active recording, opening Satty on a
full-screen capture, saving a full screenshot, selecting and annotating a
screenshot rectangle, or recording a full output or selected rectangle.
Recordings use wf-recorder's PipeWire backend explicitly, include the default
PipeWire audio source, and are saved below `~/Videos/Recordings` as
Matroska/H.264/AAC, MP4/H.264/AAC, or WebM/VP9/Opus according to the selected
Local, Share, or Website profile. Capture, recording, and finalization results
are sent to Mako, while wf-recorder diagnostics are retained in
`~/.local/state/labwc-capture/recording.log`.

FocusWriter uses its native DOCX writer as the default format for new
documents, restores the previous session so its periodic recovery cache remains
available after an interruption, and starts with the managed `managed-word`
theme. The theme presents a centered white 900-pixel writing page with dark
gray surroundings, dark document text, page padding, a restrained shadow, and
the header, footer, scrollbar, and text-labeled toolbar visible. FocusWriter's
recovery cache remains its internal FODT cache by upstream design; saved
documents use DOCX for the strongest available Microsoft Word interoperability.

When `software` is selected, qBittorrent is installed with a managed desktop
launcher. The launcher refuses to start until
`/run/media/<primary-user>/bittorrent` exists, then creates `active`,
`completed`, `torrents-active`, `torrents-completed`, and a private
content-addressed `.torrent` import directory below that root. Local `.torrent`
files are accepted only as bounded regular files, copied at mode `0600` into
the managed profile, and then opened from inside the bubblewrap namespace;
magnet and HTTP(S) inputs remain supported. The sandbox exposes no other
writable persistent host path. The managed qBittorrent profile fixes TCP/UDP
peer port `50309`, enables IPv4 and IPv6 BitTorrent, announces across all
configured tracker tiers and trackers, validates HTTPS trackers, retains SSRF
mitigation, disables DHT, PeX, LSD, random ports, and automatic port
forwarding, and keeps unlimited seeding. The nftables late hook automatically
opens TCP and UDP port `50309` whenever `addon/software` is selected on a
desktop. Routers or VPN services still need an external mapping for `50309`
when inbound Internet reachability is required.

The same `software` addon adds Vivaldi through Vivaldi's stable Debian archive
and installs Bitwarden Desktop, Obsidian, Postman, Sleek, Ledger Wallet (Ledger
Live), and Tuta Mail during the selected-class late
phase on `amd64`. Bitwarden is downloaded through Bitwarden's stable Linux
Debian endpoint, validated as an `amd64` `bitwarden` package, and installed with
APT so its dependency set and package database state remain consistent.
Obsidian `1.12.7` is downloaded from the official GitHub release URL, required
to be exactly `85,762,386` bytes, verified against SHA-256
`3644e3ef19bcd23db4d17f7c73311b5245429391a2a48b361da93375f59712b0`,
validated as the amd64 `obsidian` package with `/opt/Obsidian/obsidian` and its
vendor desktop entry, and then installed through APT.
Postman is downloaded from `https://dl.pstmn.io/download/latest/linux64` with
bounded HTTPS transport, then its gzip tar archive is rejected unless every
member remains below the single `Postman/` root, paths are unique and
traversal-free, the archive stays within the managed member and extracted-size
ceilings, and the required amd64 executable, Chromium sandbox, package metadata,
and bundled `Postman/app/resources/app/assets/icon.png` are present. Its bounded
JSON parser accepts both formatted and minified vendor package metadata while
still requiring a numeric Postman version. The validated payload is normalized
into root-owned `/opt/postman`, only the bundled
Chromium sandbox receives setuid-root mode, release provenance is recorded, and
publication replaces any prior installation atomically. The class stages a
validated system desktop entry whose absolute icon path uses that bundled image.
Sleek `2.0.26` is downloaded from its official GitHub release as the
`107,065,664`-byte amd64 Debian package, verified against SHA-256
`f2531c41b70c04bbafc27af83e195aa9268845a58d3ead4b58fa58b301223fcb`,
validated for the `sleek` package, `/opt/sleek/sleek`, and
`/usr/share/applications/sleek.desktop`, and installed through APT before its
launcher is replaced with the managed native-Wayland entry using the packaged
`sleek` icon and the registered `Office` menu category.
Ledger is downloaded from the supplied
`https://download.live.ledger.com/latest/linux` alias while the official
`latest-linux.yml` defines the expected stable version, versioned x86-64
filename, release size, and metadata SHA-512. Those values, Ledger's signed
SHA-512 manifest, and the pinned Ledger public-key fingerprint must all agree
before the AppImage is extracted atomically into root-owned
`/opt/ledger-live`. Only the bundled Chromium sandbox receives setuid-root
mode; the managed Wayland launcher omits the vendor desktop file's
`--no-sandbox` switch and selects KWallet 6 for Electron password storage.
The desktop role always installs `fido2-tools` and `libfido2-1`, and stages
`53-ledger-wallet.rules` independently of the optional `software` addon.
Native Chromium can therefore use the Ledger Stax Security Key app for
FIDO2/WebAuthn login approval through active local-seat USB and hidraw ACLs
without installing the unrelated PC/SC `libccid` driver.
The rule also grants the primary `plugdev` account access to current Ledger
devices and firmware-update re-enumeration at `0660`; it deliberately rejects
the vendor rule's world-writable hidraw policy. This integration does not
configure PAM, sudo, or any other system-authorization path. Tuta's
AppImage and detached signature are downloaded over HTTPS with retry, timeout,
redirect, and size ceilings. The AppImage is accepted only after SHA-512/RSA
verification against the pinned Tuta public key, then extracted atomically into
root-owned `/opt/tuta-mail`; the AppDir root is normalized to mode `0755` so
desktop users can traverse and execute the verified application while writes
remain root-only. Its launcher icon comes from that verified artifact. The
managed Tuta launcher runs inside bubblewrap with an ephemeral
home view plus dedicated persistent Tuta config/cache/data/state directories,
mediated portal/notification D-Bus access, a filtered session-bus allowlist for
the standard FreeDesktop Secret Service name, the active Wayland socket, and optional managed
GPU device access. It receives no system-bus socket. The normal persistent
sandbox also mounts the managed XDG Desktop, Documents, Music, Pictures, Public,
Templates, and Videos directories read-only for outbound attachments, while
Downloads remains writable for attachment downloads. The extracted AppImage receives its
`APPDIR` path explicitly and uses Electron's `gnome-libsecret` Secret Service
frontend. That Electron flag selects the standardized Secret Service API; it
does not install or expose a GNOME keyring daemon. Tuta disables Electron's
nested Chromium sandbox only inside that already isolated bubblewrap namespace
in normal and accelerated modes so the extracted AppImage can
start without a conflicting second user namespace. Initial installation,
managed updates, and interrupted-publication recovery normalize every AppDir
directory to mode `0755`, preserve root-only writes, and remove unused set-ID
bits before `AppRun` is exposed to desktop users.
Vivaldi, Bitwarden, Obsidian, Postman, Sleek, Ledger, Tuta, Filen,
Discord, Zoom, Telegram Desktop, KeePassXC, RetroArch, qBittorrent, Chromium,
Microsoft Edge, Mullvad Browser, and Visual Studio Code receive managed native
Wayland launchers with `IntelAccelerated`, `NvidiaAccelerated`, and
`PurePrivacy` actions where their device-access contract permits them. Ledger
keeps only its normal managed launcher so the hardware signer remains
available; Obsidian, Postman, Sleek, Discord, and Tuta Mail expose the two
hardware-acceleration actions without misleading file-isolating PurePrivacy
actions.
Primary managed desktop entries—the entries consumed by Crystal Dock and other
desktop launchers—and managed Labwc application hotkeys start through the
`nvidia` mode. The Intel, NVIDIA, and PurePrivacy Desktop Actions remain
separate explicit choices for applications that expose them. Chromium-family
and Electron clients use ANGLE OpenGL in Intel, NVIDIA, and PurePrivacy modes.
Every managed Chromium/Electron launch explicitly disables the Chromium Vulkan,
Default ANGLE Vulkan, and ANGLE-from-Vulkan features; no managed launch selects
a Vulkan ICD, passes a Vulkan ANGLE backend, or exposes a Vulkan
driver-selection variable. Every Electron client has one unique V8 old-space
limit below 2024 MiB for its accelerated and PurePrivacy launch paths; every
managed Electron launch selects the `gnome-libsecret` Secret Service frontend.
Package-style Electron clients also receive a fixed root-owned application
directory as their complete `LD_LIBRARY_PATH`. Per-application runtime
contracts require Bitwarden, Code, Filen, Obsidian, Postman, and Sleek to
contain their expected `libffmpeg.so`; installer-time, managed-update, and
launcher validation enforce those requirements at their respective boundaries.
Discord keeps `/usr/share/discord` as its fixed library directory without
requiring or verifying `libffmpeg.so`.
The Labwc KWallet services remain D-Bus activated through session-gated systemd
units to implement the FreeDesktop Secret Service API. Their managed activation
files are copied into the desktop account's
`~/.local/share/dbus-1/services/`, which takes precedence over the package data
directories for that user's session bus. Package activation files under
`/usr/share/dbus-1/services/` are not diverted or rewritten, so the greeter
cannot resolve desktop-only KWallet units from global metadata. The private
session-stopping marker blocks teardown-time D-Bus reactivation, and the
compatibility daemon remains ordered after its secret-portal backend so
shutdown reverses that order and stops the daemon first. No GNOME keyring
daemon is installed or exposed to managed applications.
The managed launcher rebuilds an allowlisted environment with a fixed system
`PATH`, then uses non-scrubbing AppArmor `px` transitions only for these named
package applications. This preserves their exact root-owned library directory;
using `Px` would invoke secure loader execution and discard the required
package-relative loader state.
Repository-owned `/usr/local/bin/discord` and `/usr/local/bin/zoom` command
wrappers reject root execution and enter the normal managed launcher path.
Manual command-line starts therefore receive the same Wayland environment and
Discord GPU-safe launch arguments as desktop entries, while root cannot create
or update client state below `/root`, including through a direct package-binary
invocation.
Every managed Chromium/Electron launch disables the
`WaylandWindowDecorations` client-side fallback, and Debian Chromium receives
the same disablement in its wrapper flags. Chromium, Microsoft Edge, and
Vivaldi profiles are seeded with `browser.custom_chrome_frame=false`.
Obsidian's global application registry is seeded with `frame=native`, an empty
vault registry, and no pre-approved external URI schemes. The desktop role
installs a private default vault at `~/Syncthing/obsidian-md`; the managed
launcher reads no `/etc/skel` content at runtime. It validates the already
installed user-owned vault and global registry under `$HOME`, derives a
deterministic per-user 16-character vault identifier from the absolute path,
and atomically registers the vault before first launch without replacing other
registered vaults. The vault contains inbox, daily-note, template, attachment, archive, bookmark,
graph, property-type, hotkey, and core-plugin defaults. Community plugins,
Publish, Obsidian Sync, Web viewer, slides, and audio recording remain disabled,
while local file recovery stays enabled. The managed Syncthing `.stignore`
keeps only per-device `workspace*.json` layout state out of synchronization;
notes, settings, themes, attachments, templates, and local trash remain
synchronized. Its local `Evergreen Notes` theme and
`managed-ux` snippet provide dark and light palettes, installed Noto fonts,
reduced-motion handling, visible focus, print styling, and managed editor,
navigation, graph, Canvas, table, code, tag, callout, and terminal-adjacent
colors without downloading a community theme. Visual Studio Code is seeded
with `window.titleBarStyle=native`,
`chat.disableAIFeatures=true`, a built-in dark theme, an accessible managed
palette, semantic and syntax token colors, workspace-trust defaults, telemetry
disablement, and editor, file, terminal, and workbench UX defaults. The AI
setting disables Code's bundled Copilot extensions before first launch so it
does not provision Copilot CLI state under `~/.copilot`. Filen exposes no
persistent native-frame preference; its managed
launch therefore relies on the disabled Chromium client-decoration feature and
Labwc's forced server-decoration rule. This removes Chromium's
`WaylandWindowDecorations` fallback, but Filen's vendor UI still hardcodes its
own window-control content; suppressing those controls would require modifying
the Filen application, which this installer intentionally does not do. The
Labwc session exports
`QT_WAYLAND_DISABLE_WINDOWDECORATION=1` and `GTK_CSD=0`, so Qt and GTK clients
request compositor-owned decorations rather than drawing their own borders
when their toolkit supports that contract.
Bitwarden's bundled Chromium sandbox is normalized and verified as root-owned
mode `4755` after both installer-time package installation and managed updates;
Filen receives the same repair when its package ships that helper.
Mullvad Browser's PurePrivacy action additionally forces software WebRender,
passes no OpenGL/ANGLE switches, and fails closed if a DRM or NVIDIA device bind
is introduced. Labwc orders Alt-Tab candidates by focus history, so a tap
returns to the previously focused window while holding Alt-Tab continues
through the focus-ordered switcher.

On `amd64`, the selected `software` addon additionally installs a hardened root
systemd oneshot and weekly timer for Bitwarden, Obsidian, Zoom, Filen, Discord,
Ledger, and Tuta.
The Debian downloads are bounded and package-validated again on every run,
their online versions are compared with the installed `dpkg` versions, and
package removals and downgrades are rejected. Updated packages must still pass
installed-version, executable, desktop-entry, and desktop-database verification.
Obsidian updates parse the official latest stable GitHub release JSON, accept
exactly one version-matched amd64 Debian asset, and require its declared size
and GitHub-provided SHA-256 digest to match before package validation.
Ledger and Tuta use vendor-signed AppImage release paths rather than Debian
packages. The updater repeats Ledger metadata, public-key, signed-manifest,
hash, size, architecture, extracted-payload, and Chromium-sandbox checks before
atomically replacing `/opt/ledger-live`; Tuta compares the verified artifact
SHA-256 before atomically replacing `/opt/tuta-mail`. It repairs the AppDir root to mode
`0755` before version comparison and after publication, including recovery from
an interrupted update. A class-scoped systemd user service and
path unit relay checking, updating, updated, failed, and completion events to
Mako. The root updater stores those events in a root-owned queue so a Labwc user
who was logged out during the weekly run receives them on the next session.
Managed Timeshift snapshot results use the same durable delivery model through
`/var/lib/labwc-notifications/timeshift`: each started, completed, or failed
snapshot is recorded as a bounded root-owned event and delivered by the Labwc
health notifier as soon as the Mako session is available. Persistent timer
catch-up runs are serialized through a bounded lock, and notification-queue
failures never replace the real Timeshift exit status. The same bridge records
`apt-daily-upgrade.service` start, success, and failure results under
`/var/lib/labwc-notifications/unattended-upgrades`. Local root mail, disk,
thermal, memory, battery, restart-required, software-update, unattended-upgrade,
Timeshift, AppArmor-denial, firewall-drop, authentication, USB/hotplug, storage,
Bluetooth, calendar-sync, OCR, desktop-maintenance, Android-device, network-scan,
and screen capture or recording outcomes therefore remain visible through Mako.
Root-originated events do not require the originating system service to access
the user session bus directly. New privileged producers use
`/usr/local/sbin/labwc-notify --summary TEXT [--body TEXT]` rather than calling
`notify-send` as root: the helper accepts bounded printable metadata, queues a
root-owned `root:logreader` event under
`/var/lib/labwc-notifications/system`, and the active Labwc user relays it
through Mako. The system queue is watched by the health path unit and retained
for a logged-out user until the next eligible Labwc session.

The installed `52unattended-upgrades` accepts candidates only from an explicit
allowlist containing the official Debian archives and every approved vendor
repository declared by the Forky installer classes, including the GitLab
Runner archive. A newly configured repository remains ineligible until its
site is reviewed and added to this list. The managed APT pin policy still
selects candidate versions. The package blacklist keeps
UEFI/Secure Boot, bootloaders, kernels, initramfs, DKMS modules, firmware,
NVIDIA/CUDA, Vulkan, OpenGL, EGL, Mesa/GLVND, DRM/GBM, PipeWire, WirePlumber,
Bluetooth audio, ALSA, PulseAudio, and libcamera package families under
explicit manual operator control.
Unattended maintenance keeps the existing obsolete-dependency and unused-kernel
cleanup policy, automatically repairs interrupted `dpkg` configuration state,
keeps the Forky APT resolver fallback enabled, and does not reboot or downgrade
packages.

The installer-time Bitwarden, Zoom, Filen, and Discord APT transactions suspend
only the `needrestart` post-invoke hook with `NEEDRESTART_SUSPEND=1`. The d-i
target is an offline chroot with no target services to restart, and running the
hook there can make its namespace scanner fail with `unshare(1): EPERM`.
`needrestart`, Electron or Chromium sandboxes, and Bubblewrap are not disabled
on the installed system.

That means:

- Adding a manifest-declared class gives you bare-token resolution and optional metadata such as helpers, dependencies, and storage dispatch.
- Adding an additive class does not require dispatcher/code changes: add `d-i/forky/classes/class-addon/<name>.cfg` and select it as `<name>` in `classes=`.
- Adding a `forky` profile override class uses `d-i/forky/classes/class-profile/<name>.cfg`, a matching record in `d-i/forky/classes/configs/profile.cfg`, and `d-i/forky/hosts/profiles/override/<name>.env`; after that the operator selects it as `<name>` in `classes=`.
- Adding a select class group uses `d-i/forky/classes/class-select/<group>/<class>.cfg` and `group/class` in `classes=`.
- Group-qualified tokens also accept `group:class` and `group.class`; prefer `group/class` in manual references and use commas between selected classes on the kernel cmdline because that survives more bootloaders cleanly than semicolons.
- Adding new host/storage behavior should be declared in `d-i/forky/classes/configs/*.cfg`, not inline inside the class fragment. `d-i/forky/classes/install.conf` owns only the manifest-wide metadata and config source list.
- The optional `debug` class remains available for class selection, while the active installer runtime always records its structured diagnostic stream in `/tmp/installer.log` and archives a redacted copy to `/var/lib/installer-state/installer.log` on the target.

Every install accepts `primary_user=`, `primary_password=`,
`primary_gpg_passphrase=`, and `root_password=` on the installer kernel command
line. Any account or root field missing from the kernel command line falls back
to `d-i/forky/hosts/shared/account.env`:
`ACCOUNT_USERNAME` provides the default desktop/server username, while
`ACCOUNT_PASSWORD_CRYPTED` and `ROOT_PASSWORD_CRYPTED` provide the default
hashed user and root passwords. Provided cmdline values override only the
matching field, so mixed cmdline/default combinations are supported. Cmdline
password and GPG-passphrase values must still be single printable tokens
without whitespace, and `primary_user` must match the Debian account-name shape
`^[a-z_][a-z0-9_-]*$`. Desktop GPG bootstrap prefers
`primary_gpg_passphrase=` and otherwise uses the plaintext
`primary_password=` value. If neither is provided, the desktop install stops
rather than creating a GPG key with a passphrase that differs silently from the
desktop credential; a one-way `ACCOUNT_PASSWORD_CRYPTED` value cannot provide
the plaintext needed to protect the secret key. The generated OpenPGP identity
uses GnuPG's modern `future-default` profile (Ed25519 certification/signing with
a Curve25519 encryption subkey), is marked with ultimate owner trust, and is
verified for the exact encryption/trust properties KWallet requires before the
installer continues. Desktop installs also stage the vdirsyncer/khal/todoman
calendar stack for the primary account. Fruux
credentials come from `fruux_username=` / `fruux_password=` on the installer
kernel command line when provided; any missing field falls back independently
to `FRUUX_CALENDAR_USERNAME` / `FRUUX_CALENDAR_PASSWORD` from
`d-i/forky/hosts/shared/account.env`. Cmdline Fruux values must be single
printable tokens without whitespace. They are redacted from the repo's own
installer logs, but kernel command-line values are still visible to the
bootloader and installer runtime, so use deployment-specific account secrets
and a scoped Fruux app password. `primary_gpg_passphrase=` is covered by the
same repository-managed redaction policy.

To use ordinary wired DHCP networking, select the `dhcp` network class without
the `wifi` addon:

```text
classes=lab,desktop,standard,dhcp primary_user=<user> primary_password=<user-password> root_password=<root-password> fruux_username=<fruux-user> fruux_password=<fruux-app-password>
```

The installer still lets d-i use automatic `netcfg` selection for DHCP installs.
DHCP targets do not receive the managed static-network helper or service.

To use static networking, select the `static` network class. The installer and
the installed system now share one deterministic input contract: the installed
Ethernet address is taken directly from `netcfg/get_ipaddress=...`, the IPv4
netmask comes from `netcfg/get_netmask=...`, the IPv4 gateway comes from
`netcfg/get_gateway=...`, and the IPv4 nameserver list comes from
`netcfg/get_nameservers=...`.

```text
classes=lab,desktop,standard,static primary_user=<user> primary_password=<user-password> root_password=<root-password> fruux_username=<fruux-user> fruux_password=<fruux-app-password> netcfg/get_domain=example.test netcfg/get_ipaddress=192.0.2.50 netcfg/get_netmask=255.255.255.0 netcfg/get_gateway=192.0.2.1 netcfg/get_nameservers=192.0.2.53
```

`d-i/forky/classes/class-select/network/static.cfg` still forces manual/static
netcfg mode, and `d-i/forky/scripts/preseed/answers.sh` still appends the
concrete `netcfg/get_domain`, `netcfg/get_ipaddress`, `netcfg/get_netmask`,
`netcfg/get_gateway`, and `netcfg/get_nameservers` values after class fragments
so cmdline-derived answers win for d-i itself. During `late_command`,
`d-i/forky/scripts/late/managed-network-generate.pl` writes
`/etc/network/interfaces`, `/etc/network/interfaces.d/50-managed-network`, and
root-only `/etc/default/managed-network`, then stages MAC-matched
`/etc/systemd/network/10-managed-ethernet.link` and
`/etc/systemd/network/11-managed-wifi.link` when applicable. The installed
Ethernet address is the exact `netcfg/get_ipaddress` value; when a Wi-Fi
adapter is present, the installed Wi-Fi address is always `+1` from that
Ethernet IPv4 address. For example,
`netcfg/get_ipaddress=192.168.50.22` makes Ethernet `192.168.50.22/24` and
Wi-Fi `192.168.50.23/24`.

Static installs stage every detected Ethernet and Wi-Fi adapter with the
deterministic target names `managed-eth0` and `managed-wifi0`. Wi-Fi is never
used during d-i itself. The generated Wi-Fi stanza stays dormant until the
operator later selects an ESSID and brings the adapter up on the installed
system. If no Wi-Fi adapter is present during installation, the handoff remains
Ethernet-only instead of failing the install.

Use all of these kernel parameters for static IPv6: `ipv6_address=.../prefix`,
`ipv6_gateway=...`, and `ipv6_nameservers=...`. `ipv6_address` must use CIDR
notation such as `2001:db8::82/64`; the installer no longer accepts a separate
`ipv6_netmask` kernel parameter. Managed Wi-Fi always derives its host address
as `+1` from the configured base address, so `192.168.50.82` becomes
`192.168.50.83` for Wi-Fi and `2001:9b1:29fd:4e00::82/64` becomes
`2001:9b1:29fd:4e00::83/64`.

```text
ipv6_address=2001:9b1:29fd:4e00::82/64 ipv6_gateway=2001:9b1:29fd:4e00::1 ipv6_nameservers=2001:9b1:29fd:4e00::1
```

Static installs stage `managed-network.service` as a oneshot validation gate.
At boot it does not rewrite networking. It validates the generated ifupdown
files, root-only defaults, adapter MACs, IPv4/IPv6 CIDRs, and any explicitly
seeded Wi-Fi security stanzas before `networking.service`,
`NetworkManager.service`, or `systemd-networkd.service` can continue.

The `wifi` addon now acts only as an explicit compatibility marker for future
manual Wi-Fi onboarding. It no longer makes d-i associate to a wireless
network. Static Wi-Fi target networking still depends on `ifupdown` and
`wpasupplicant`, which are included explicitly because this profile disables
package recommends; `ethtool` is also included so the late-command generated
ifupdown stanzas can apply best-effort adapter offload and queue settings.

To install and enable a hardened OpenSSH server during `late_command`, add the
`ssh` addon class:

```text
classes=lab,desktop,standard,dhcp,ssh primary_user=<user> primary_password=<user-password> root_password=<root-password> ssh_port=<port> fruux_username=<fruux-user> fruux_password=<fruux-app-password>
```

When enabled, `d-i/forky/classes/class-addon/ssh.cfg` adds
`openssh-server` to the selected package set. The shared late-command path then
validates and renders `d-i/forky/ssh/sshd_config`, installs
`d-i/forky/ssh/config` as the target user's `~/.ssh/config`, and writes
`d-i/forky/ssh/lan_ed25519.pub` into that user's `~/.ssh/authorized_keys`. The
target user, home path, `AllowUsers`, and `Port` are rendered from
`primary_user=` or the fallback `ACCOUNT_USERNAME`, plus `ssh_port=` when set
on the kernel command line; SSH login is
limited to that user, root/password/keyboard-interactive auth are
disabled, and the shipped configs restrict public-key, host-key, KEX, cipher,
and MAC algorithms to the hardened Ed25519/Curve25519/AEAD/ETM set. When the
`ssh` addon is selected and nftables staging is enabled, the installer also
merges the `ssh-server` firewall overlay so inbound SSH is allowed on that
rendered port from the managed IPv4 and IPv6 network CIDRs for the selected
host profile and first-boot network handoff.

The `server` and `desktop` roles also install `openssh-client` and stage two
transfer helpers:

```sh
xssh-send --dest-ip <ip address> --port <ssh port> [--user <remote-user>] <local-path> [remote-path]
xssh-retrieve --remote-ip <ip address> --port <ssh port> [--user <remote-user>] <remote-path> [local-path]
```

Both helpers use recursive `scp`, work with files or directories, and print an
explicit completion line on success.

To install Tailscale, Syncthing, and the Tailscale SSH/Syncthing endpoint
policy together, add the `tailscale` addon class:

```text
classes=lab,server,standard,dhcp,tailscale primary_user=<user> primary_password=<user-password> root_password=<root-password> tailscale_authkey=<required-auth-key> fruux_username=<fruux-user> fruux_password=<fruux-app-password>
```

When enabled, `d-i/forky/classes/class-addon/tailscale.cfg` adds
`tailscale` and `syncthing`, stages the official Tailscale stable archives from
`https://pkgs.tailscale.com/stable/debian` for `trixie`, `forky`, and `sid`,
and pins the `tailscale` package to the official upstream `trixie` suite while
blocking the `forky` and `sid` variants. The late helper stages:

- `/etc/default/tailscaled` with the managed TUN interface, direct-connect
  UDP port, and Tailscale's supported `--no-logs-no-support` upload opt-out
- `/etc/default/tailscale-managed` plus
  `/usr/local/libexec/tailscale-managed-up`
- `tailscale-managed-bootstrap.service`
- a hardened `tailscaled.service` drop-in
- `/etc/default/managed-syncthing`
- `/usr/local/libexec/managed-syncthing-configure`
- `managed-syncthing.service`

The staged systemd units and drop-ins are installed as world-readable
configuration (`0644` files below `0755` directories), because systemd exposes
unit metadata through its APIs regardless of filesystem mode. The staged
Tailscale auth key remains `0600` and is truncated and removed after a
successful join or when the node is already enrolled.

Every profile selecting the Tailscale addon receives
`--no-logs-no-support`. Tailscale continues writing local journal diagnostics,
but does not create or upload logtail data. Upstream explicitly states that
this disables Tailscale technical support, and a tailnet that requires
data-plane audit logging will refuse to keep such a node running; that policy
must not be enabled on this image without removing the upload opt-out.

The managed Tailscale bootstrap configures `tailscaled` to use the same TUN
interface and UDP port exposed by the nftables overlay, then issues one bounded
`tailscale up` with `--accept-dns=false`, `--accept-routes=false`,
`--ssh=true`, and `--netfilter-mode=off` by default. The managed defaults
file also stages profile-owned `TAILSCALE_*` policy for:

- `TAILSCALE_ADVERTISE_TAGS` for tailnet ACL/tag identity
- `TAILSCALE_ADVERTISE_ROUTES` and `TAILSCALE_ADVERTISE_EXIT_NODE` for subnet
  router / exit-node offers
- `TAILSCALE_ACCEPT_RISK`, `TAILSCALE_FORCE_REAUTH`, and
  `TAILSCALE_AUTH_KEY_REQUIRED` for operator-safe approval handling
- `TAILSCALE_SHIELDS_UP`, `TAILSCALE_REPORT_POSTURE`,
  `TAILSCALE_SNAT_SUBNET_ROUTES`, and `TAILSCALE_STATEFUL_FILTERING`
- `TAILSCALE_TIMEOUT` to keep first-boot bootstrap bounded instead of waiting
  forever; the managed profiles use a two-minute control-plane deadline

The hardened `tailscaled.service` drop-in leaves Tailscale's control transport
selection intact. Current Tailscale clients automatically try the port `80`
Noise fast path with HTTPS/TCP `443` fallback and move subsequent reconnects to
`443` after a recent failed control connection. The image does not force the
unstable `TS_FORCE_NOISE_443` debugging knob, so a network that disrupts either
transport cannot pin every reconnect to that same path. TCP `80` and `443`
remain permitted by the nftables egress overlay. The daemon is also ordered
after `NetworkManager.service` and `network.target`, which reverses at shutdown
and keeps the physical network available while Tailscale drains its bounded
30-second stop path. Upstream `tailscaled` already performs best-effort DNS and
router cleanup before every daemon start, so the image does not run a duplicate
pre-start cleanup helper and clears the package's redundant post-stop cleanup.
The drop-in discards only upstream's exact missing-`tailscale0` no-op startup
diagnostic and the exact non-fatal closed extension-queue shutdown diagnostic.
Control-plane, DERP, router, and all other daemon failures remain visible.

The concrete host profiles require `tailscale_authkey=` whenever the
`tailscale` addon is selected, so an unattended install fails during late
configuration instead of booting a node whose Tailscale backend remains
stopped. The first-boot bootstrap service waits a bounded period for the local
daemon socket, joins the tailnet once, deletes the staged auth key after a
confirmed `Running` state with a Tailscale address, and leaves subsequent
15-minute retry spacing to systemd without recycling `tailscaled`. This
preserves the daemon's control-dial health and port `80` to HTTPS/TCP `443`
fallback state. Final bootstrap failures append bounded
`tailscale status --json` and
`tailscale netcheck` output, the installed client version, and
`tailscaled.service` journal diagnostics to the managed bootstrap log.
Operators who intentionally want manual enrollment must explicitly override
`TAILSCALE_AUTH_KEY_REQUIRED=false` in the selected profile. When the tailnet
uses device approval, use a pre-approved auth key for unattended bootstrap.
When the tailnet uses tag-based ACLs, either embed the required tags in the
auth key or set `TAILSCALE_ADVERTISE_TAGS` to tags permitted by the tailnet
`tagOwners` policy.

Persistent managed Tailscale helper state lives under
`/usr/local/lib/tailscale/`, including the staged auth key, bootstrap
completion marker, status file, and managed bootstrap log.

When the `tailscale` addon is selected, the image uses Tailscale SSH directly
instead of installing `openssh-server`. Tailscale SSH assumes port `22` on the
Tailscale address, uses the local Unix accounts that the installer already
creates, and relies on tailnet SSH policy for authentication and authorization.
The nftables policy only allows that managed SSH endpoint on the `tailscale0`
interface and Tailscale address space. If you still want a conventional SSH
daemon, select the standalone `ssh` addon explicitly.

Selecting both `tailscale` and `ssh` together is supported. In that combined
mode, Tailscale SSH still handles SSH on the Tailscale address at port `22`,
while the standalone `ssh` addon continues to install and configure
`openssh-server` on its separately configured `ssh_port=` endpoint.

The same addon also stages a managed Syncthing service for the primary account.
It uses `~/Syncthing` as the synced data root, stores runtime state under
`~/.local/state/syncthing`, binds only the managed TCP sync port `35000`, and
disables global discovery, local discovery, relays, NAT traversal, and QUIC so
the only supported remote path is the Tailscale private network.

Tailscale ACL, grants, `tagOwners`, SSH policy, subnet-route approval, and
device approval still remain tailnet-side policy. This repo only stages the
node-side `tailscale up` flags and validates that the requested tags, routes,
and approval-sensitive bootstrap settings are coherent before first boot.
Its strict egress overlay permits TCP `80`/`443` for control and DERP fallback,
UDP `3478` for STUN, and direct peer UDP from the configured Tailscale source
port instead of incorrectly treating that port as a remote destination port.

To install the development and CI toolchain and route interactive build/cache
state to `/pool`, add the `devops` addon class:

```text
classes=lab,desktop,standard,dhcp,devops primary_user=<user> primary_password=<user-password> root_password=<root-password> fruux_username=<fruux-user> fruux_password=<fruux-app-password>
```

When enabled, `d-i/forky/classes/class-addon/devops.cfg` adds the desktop
development package set, including `libcap-dev`, and the class late helper
stages managed upstream Ansible, Terraform, Packer, Node/Corepack,
Rustup/Cargo/rustfmt, uv, LLVM 24, Mise, Bazelisk, Codex, and llama.cpp runtime
contracts. The account-owned `~/.profile.d/71-devops-de.sh` keeps build, cache,
and database state under `/pool/build/<user>`, `/pool/cache/<user>`, and
`/pool/db/<user>`, keeps Python bytecode and Ansible temporary state below
`/run/user/<uid>`, and exposes the isolated upstream binaries only inside the
opt-in environment.
Running `devops` enters a nested Bash or Zsh in the current terminal and
working directory. Running `devops` again, or exiting the nested shell, returns
to the unchanged ordinary shell environment.
Standalone Codex and the managed ChatGPT/Codex desktop application apply that
same deterministic environment on every launch. Both retain read/write access
to the real `~/Workspace` plus `/pool/cache`, `/pool/build`, and `/pool/db`,
and can execute installed tools below `/usr`, `/usr/local`, `/opt`,
`/data/codex`, and `/data/llama`. This includes `/usr/bin/pwsh` and the
PowerShell payload below `/opt/microsoft/powershell/7`. The desktop DevOps
profile provides its account-local `bazel()` helper. The existing read-only
`/usr` mount and selected `$HOME/.config/bazel` bind make the same profile
helper usable from Codex command shells without treating Bazel as a managed
application. Existing development configuration is read only from the
synchronized path-specific allowlist documented in
`d-i/forky/classes/class-addon/README.md`. SSH/GnuPG material, histories,
credential stores, broad home configuration, and broad `$HOME/.cache` are not
mounted; ChatGPT persists only its own `$HOME/.cache/Codex` state.

To install CrowdSec with the nftables bouncer, auditd-driven detection, and
optional console enrollment, add the `crowdsec` addon class:

```text
classes=lab,server,standard,dhcp,crowdsec primary_user=<user> primary_password=<user-password> root_password=<root-password> crowdsec_token=<console-enrollment-token>
```

The standard and enhanced security classes keep auditd's authoritative
`ENRICHED` log at `/var/log/audit/audit.log` for `ausearch`. The audit syslog
dispatcher remains disabled because `/dev/log` is owned by journald; instead,
rsyslog tails auditd's file directly with `imfile` in polling mode so audit log
rotation does not trip the known inotify watch-descriptor warning, and routes
that stream to `/var/log/managed/audit/kernel-audit.log`. AppArmor-specific
records continue to reach the dedicated managed AppArmor log. Security-class staging also masks
`systemd-journald-audit.socket`, preventing both the dispatcher and native
journald audit inputs from duplicating the audit stream in `journalctl`.

When enabled, `d-i/forky/classes/class-addon/crowdsec.cfg` adds the CrowdSec
engine plus the nftables firewall bouncer and stages role-aware acquisition
under `/etc/crowdsec/acquis.d/`, extra auditd execve rules under
`/etc/audit/rules.d/zz-crowdsec.rules`, and an ordering drop-in for
`crowdsec-firewall-bouncer.service` so it waits for both `crowdsec.service`
and `nftables.service`. The nftables late-command path also merges the
`crowdsec` service overlay automatically when the addon is selected, which
preserves the local API listener on loopback and keeps CrowdSec's outbound
console/bootstrap traffic explicit in the generated policy.

The addon stages both `crowdsec-testing.pref` and `crowdsec-stable.pref` into
the target. `crowdsec-testing.pref` now pins CrowdSec packages above normal
installed-policy priority and matches both packagecloud `Origin` and `Label`
metadata, while `crowdsec-stable.pref` stays below installed-policy priority so
the stable CrowdSec archive cannot win accidental same-version or downgrade
resolution during `apt upgrade`. The class keeps the CrowdSec local API enabled
but explicitly defers CAPI registration beyond `pkgsel`; no `cscli` diversion or
replacement binary is installed.

The addon stages a one-shot `crowdsec-firstboot.service` under
`multi-user.target`; it waits for networking and the CrowdSec engine, refreshes
the hub when available, requires the `crowdsecurity/linux` and
`crowdsecurity/auditd` collections, completes CAPI registration, enrolls the
Security Engine when `crowdsec_token=` is present on the installer kernel
command line, rewrites a managed local bouncer API key, and enables the
nftables bouncer only after that key exists. Console enrollment
runs as soon as the local API is ready; a failed enrollment leaves the token in
place, returns a failed service status, and lets `Restart=on-failure` retry
instead of marking an unenrolled engine complete. If `crowdsec_token=` is
omitted, the addon still finishes the local CrowdSec bootstrap and simply skips
enrollment. The console enrollment token is truncated and removed only after
successful enrollment. The persistent
local bouncer API key is operational service state rather than an enrollment
token, so its YAML stays restricted to `0600` while the associated systemd
drop-in remains readable as normal unit configuration.
The CrowdSec bootstrap marker, enrollment token, status file, and bootstrap log
live under `/usr/local/lib/crowdsec/`.

To install the proprietary NVIDIA driver and firmware stack, add the `nvidia`
addon class:

```text
classes=lab,desktop,standard,dhcp,nvidia primary_user=<user> primary_password=<user-password> root_password=<root-password> fruux_username=<fruux-user> fruux_password=<fruux-app-password>
```

When enabled and an NVIDIA PCI display adapter is detected,
`d-i/forky/classes/class-addon/nvidia.cfg` adds the managed NVIDIA
driver/runtime package set, including the DKMS driver, firmware, GL/compute
libraries, and the kernel source package used by the signed Secure Boot flow.
The shared late-command path then stages the NVIDIA modprobe configuration and
initramfs module list. If the addon is selected on a host without detected
NVIDIA display hardware, the installer skips the NVIDIA package fragment and
keeps only the auto-detected GPU classes. Without an effective addon, the
target receives an NVIDIA blacklist so unattended installs do not auto-enable
the proprietary stack.

The generated `NvidiaAccelerated` and `IntelAccelerated` desktop actions use
native Wayland with ANGLE OpenGL. They explicitly disable Chromium/Electron
Vulkan features and do not select an ICD or pass a Vulkan driver-selection
variable. The normal launcher follows the same OpenGL-only policy.

On Intel + NVIDIA hybrid hosts, the auto-detected `gpu/intel-uhd` class owns
Intel firmware, the Intel media driver, and the GL/EGL/GLES runtime needed by
the desktop. The NVIDIA addon classes provide their required NVIDIA
OpenGL/EGL/Wayland userspace and the Vulkan loader ABI required by package
dependencies. The shared APT policy blocks Vulkan ICDs, tools, development
headers, and validation layers on every managed target.

To install the NVIDIA CUDA userspace runtime archive, add both the `nvidia`
and `cuda` addon classes:

```text
classes=lab,desktop,standard,dhcp,nvidia,cuda primary_user=<user> primary_password=<user-password> root_password=<root-password> fruux_username=<fruux-user> fruux_password=<fruux-app-password>
```

The `cuda` addon is opt-in, is restricted to `amd64`, and is rejected unless
`nvidia` is also selected. Its upstream archive is added through
`apt-setup/local*` just like the other optional repositories, and the merged
answers compact the selected `apt-setup/local*` slots so they remain
consecutive regardless of which optional classes are enabled.

To install the desktop virtualization baseline, including direct QEMU/KVM and
confined Incus with its local Web UI, add the `qemu` addon class:

```text
classes=lab,desktop,standard,dhcp,qemu primary_user=<user> primary_password=<user-password> root_password=<root-password> fruux_username=<fruux-user> fruux_password=<fruux-app-password>
```

`qemu.cfg` keeps the package contract explicit: QEMU x86, OpenGL modules,
utilities and block extras, OVMF, swtpm, virtiofsd, passt, Incus, the Incus
client and Canonical UI payload, uidmap, libosinfo, and genisoimage. It adds the
Zabbly Incus Stable `trixie` repository because that is the configured suite
for the managed Incus packages. Libvirt, virt-manager, Vagrant, classic LXC,
and standalone LXCFS are deliberately absent. The late hook verifies the
packages, direct QEMU and Incus executables, packaged systemd units, the
UI-aware Incus wrapper, and `/opt/incus/ui/index.html` before staging policy.

Persistent storage is limited to `/pool/qemu` and `/pool/incus`. The former is
a root-owned, group-`devops` setgid work root; the latter is the root-owned
source for the managed Incus `dir` pool. Direct QEMU may attach only to the
profile-owned Incus bridge, normally `incusbr0`. The qemu nftables overlay
allows DHCP, DNS, forwarding, and masquerading only for that guest bridge. It
does not publish an Incus HTTPS port, and the managed helper fails if
`core.https_address` is set.

The primary account receives only the `kvm` and restricted `incus` groups;
membership in root-equivalent `incus-admin` is rejected. The installer enables
only `incus.socket` and `incus-user.socket`. It removes boot-target links for
the Incus daemon, LXCFS companion, startup helper, restricted user broker, and
the repository-owned `incus-host-managed.service`, so no Incus service process
starts at boot or login. The first restricted client connection activates
`incus-user.service`; its tracked drop-in requires the static managed host
service, which in turn starts the package daemon and shutdown helper, validates
both Unix sockets, and reconciles the host before the confined user broker is
allowed to serve the account.

The root helper creates or verifies the `local` directory pool on
`/pool/incus`, `incusbr0`, and a default profile bound to both with
`security.privileged=false`. It also verifies the packaged Web UI over the
administrator Unix socket and leaves remote API access disabled. The
account-local `incusops` helper runs the normal client, while `incusui` runs
`incus webui` through the local connection; neither requires `incus-admin` or a
network listener. The managed host service has no custom stop command. Reverse
unit ordering leaves orderly instance shutdown to the package-owned
`incus-startup.service` before the daemon stops. Codex and ChatGPT receive no
libvirt/Vagrant environment, directories, or runtime socket injection. The
addon creates no instances; the account manages its confined per-user Incus
project on first use.

To install the hardened rootless Podman baseline, add the `podman` addon
class:

```text
classes=lab,server,standard,dhcp,podman primary_user=<user> primary_password=<user-password> root_password=<root-password>
```

When enabled, `d-i/forky/classes/class-addon/podman.cfg` adds the managed
rootless Podman package set. The shared late-command path then provisions a
locked `podsvc` system account with `/usr/sbin/nologin`, managed rootless
config under `/data/config/podman`, rootless state under `/pool/podman`,
managed subordinate UID/GID ranges in `/etc/subuid` and `/etc/subgid`, Quadlet
user drop-ins under the managed containers config, and nftables-backed
rootless network configuration. Persistent container data stays under
`/pool/podman`, while `runroot` and libpod temporary state stay below
`/run/user/<uid>`. The storage driver is selected without FUSE: native `btrfs`
is used on Btrfs-backed `/pool`, and native kernel `overlay` is used on
supported non-Btrfs filesystems. The package set and rendered storage configs
do not install or configure `fuse-overlayfs`. On the `server` role, the
installer also stages
the rootless Podman API socket path so Docker-compatible clients can target
`unix:///run/user/<uid>/podman/podman.sock` through `DOCKER_HOST` or
`CONTAINER_HOST` once the server-side linger bootstrap has activated the user
manager. The managed `/etc/pam.d/systemd-user` stack recognizes system
accounts through `pam_usertype`, so password-locked service users can start
their manager while regular login-class users still pass through Debian's
`common-account` expiry policy.

The addon also installs `/usr/local/sbin/podbin` and renders its managed
defaults under `/etc/default/podbin`. During install it creates the ed25519 key
pair `/data/pki/ssh/podbin/podbin_ed25519` and
`/data/pki/ssh/podbin/podbin_ed25519.pub`. `podbin --create-user <username>`
creates a locked system Podman user with per-user rootless config/state under
the managed Podman roots; `podbin --import-user <username>` can instead adopt
an existing locked system container account outside `/home` without moving
its existing rootless storage. The reserved `podsvc` service account remains
the installer-managed Podman service user and is not a podbin workload account.
By default, `podbin --create-container <username> [container]` builds or reuses the managed
local image `localhost/podbin-runtime:trixie`, which provisions a fixed non-root
container login user `poduser` with shell `/bin/sh`, home `/home/poduser`,
read-only root login disabled in `sshd`, and writable tmpfs-backed home and
`/workspace` paths while the root filesystem stays read-only by default. The
managed image sets `USER` to the poduser UID/GID, and the generated Quadlet also
sets `[Container] User=<poduser-uid>:<poduser-gid>` so the container service
process starts as `poduser` rather than as container root.
Container creation from **Computer Management → Container Management** collects
the validated container name in Fuzzel before opening the terminal-backed
Podbin action. The remaining prompts cover only the image, SSH/high-port
mapping, bind address, and read-only rootfs policy; the container SSH user, authorized-keys
path, and runtime shell stay fixed to the managed non-root contract unless root
intentionally selects a custom image that matches it. `podbin --start-container`
and `--connect-container` remain the daily-user path via the account sudoers
delegation, while `--create-user`, `--create-container`, `--open-container`,
`--delete-container`, and the broader management commands stay on the
root-admin path; `--open-container` still
execs into the selected container as the managed runtime UID/GID, not as root.
The connect path records host keys in the managed podbin known-hosts file
instead of the normal root SSH profile. Root can also import existing
containers into Podbin metadata with
`podbin --import-containers <username> [container]`, diagnose a user with
`podbin --diagnose-user <username>`, list containers, images, volumes, networks,
and pods; inspect status and logs; start, stop, restart, enable, or disable a
selected Quadlet; prune unused resources; and run direct Podman, user-systemd,
or user-journal commands through the selected locked account.
`podbin --wipe-all <username>` requires the exact `WIPE <username>`
confirmation, resets every Podman resource for that account, disables linger,
removes subordinate IDs and managed trees, and deletes the system user and its
primary group.

Managed Labwc desktops also install `labwc-podman-menu`. Open **Computer
Management → Container Management** to reach its **Container Management**
Fuzzel launcher for managed user lifecycle, container
start/stop/restart/enable/disable, logs, inspection, SSH or shell access,
image/volume/network/pod views, user import and runtime diagnostics, existing
container adoption, user-systemd and user-journal inspection, shared `podsvc`
Podman/systemd/journal operations, pruning, deletion, and full user wipe
operations.
Every action is passed as fixed arguments to `/usr/local/sbin/podbin` inside
`labwc-terminal`; existing sudo and Podbin confirmation policy remains
authoritative.

## Runtime Inputs

The host policy is split into concrete profiles and shared policy. The
concrete profile under `d-i/forky/hosts/profiles/<family>/<role>.env` or
`d-i/forky/hosts/profiles/override/<name>.env` is the
primary role-specific source of truth for:

- partition slot numbers and `SIZE_*` storage sizing values
- bootprofile labels and GRUB policy such as `GRUB_DEFAULT_ENTRY` and the
  `GRUB_PROFILE_*_FLAGS` sets
- NFT, tmpfs, Secure Boot state, and ZRAM first-boot policy
- installed-system troubleshooting levels through `NFTABLES_LOG_LEVEL`,
  `ZRAM_LOG_LEVEL`, and `SYSTEMD_LOG_LEVEL`; defaults are sparse
  (`none` for nftables generator diagnostics, `error` for zram and systemd/network logs)
- optional boot-time service masks through `GRUB_SYSTEMD_MASK_FLAGS`; NVMe
  Btrfs profiles mask `nvmf-autoconnect.service` by default so NVMe-oF remains
  opt-in, while profiles without masks still define `GRUB_SYSTEMD_MASK_FLAGS=""`
- disk/profile-specific sysctl dirty-writeback and reclaim budgets rendered into the
  staged `25-*.conf` target overrides and the bootprofile-owned
  `profiles/*/50-*.conf` overlays synced into `/run/sysctl.d`

Shared identity, account, runtime path, server-addon policy, layout primitive,
and boot defaults live under `d-i/forky/hosts/shared/*.env`. Desktop-only
Labwc, Waybar, launcher, output, and desktop-addon knobs live directly in each
desktop profile or desktop override; the assembler only layers
`hosts/shared/server.env` for server profiles. `hosts/shared/layout.env` carries the cross-family mount security
fragments, tmpfs policy, common mount fragments, and ephemeral dm-crypt backing
for every profile. `layout-btrfs.env` owns the Btrfs/XFS labels, staging
paths, mount, mkfs, LUKS, and GRUB root policy for `btrfs-*` and `vm-*`, while
`layout-f2fs.env` owns the F2FS/eMMC labels, mount, mkfs, LUKS, and GRUB root
policy. In the F2FS family, installer-time mounts plus the first kernel root
mount intentionally use a conservative F2FS option set, while the installed
system remounts the full tuned compression policy from `fstab` after
userspace is up. Optional `/pool` is still ext4 and uses the
explicit `MNT_EXT4_POOL_OPTS` contract.
`hosts/shared/runtime.env` carries shared sysctl target paths. The selected
`disk` class chooses the host profile and shared storage family; the concrete
profile supplies the rendered storage sysctl values.

The served repository stays read-only. `d-i/forky/scripts/early/dispatch.sh`
selects one of the six concrete host profiles, fetches the assembled
host policy env, fetches account policy separately from
`hosts/shared/account.env`, parses the installer kernel cmdline,
generates the final target hostname once as `SYSTEM_PREFIX-###`, renders the
runtime fragments inside the installer under `/tmp/install-runtime`, and seeds
debconf from that generated runtime state before partman starts. The concrete
profile is sourced before shared policy so shared env files can derive from
role-specific `SIZE_*`, `BOOTPROFILE_*`, `GRUB_*`, and slot values. User and
root account hashes stay in `d-i/forky/hosts/shared/account.env`;
they are not duplicated in tracked answer fragments. Target-side staged assets
now live under `d-i/forky/hooks/shared/target/**`,
`d-i/forky/hooks/hardware/<group>/<class>/target/**`, and optional
`d-i/forky/hooks/role/<role>/target/**`, with the hierarchy beneath each
`target/` root mirroring the installed system directly such as `target/etc/...`
or `target/usr/local/...`. Shared target policy also installs udev, UDisks2,
and ordered polkit rules under `target/etc` so removable-media authorization is
present on the installed system. Desktop USB policy uses the real Forky
UDisks2 action names, including `filesystem-unmount-others`, and target
verification rejects the nonexistent `filesystem-unmount` and obsolete
`drive-eject` identifiers that otherwise route Thunar/GVFS unmount attempts
into the administrator-only fallback. The selected disk class chooses
the shared storage hook family directly: `nvme -> btrfs`, `vm -> vm`
with Btrfs layout policy, and `emmc -> f2fs`.

The runtime hooks derive `INSTALL_DISK_CANDIDATES` and the default
`DEV_INSTALL_DISK` from the selected disk class:

- `nvme` -> `/dev/nvme0n1 /dev/nvme*n* /dev/sd*`, default `/dev/nvme0n1`
- `vm` -> `/dev/nvme0n1 /dev/nvme*n* /dev/vd* /dev/sd* /dev/mmcblk*`, default `/dev/vda`
- `emmc` -> `/dev/mmcblk0 /dev/mmcblk*`, default `/dev/mmcblk0`

If you need to override the target disk, set `DEV_INSTALL_DISK` and optionally
`INSTALL_DISK_CANDIDATES` in the selected concrete host env before serving the
repo. The runtime hooks derive the effective `DEV_PART_*` device paths from the
final disk plus the explicit slot numbers in that host env.

Partition sizing is controlled through the selected concrete profile under `d-i/forky/hosts/profiles/<family>/<role>.env` or `d-i/forky/hosts/profiles/override/<name>.env` plus shared layout policy under `d-i/forky/hosts/shared/*.env`, then materialized into effective `DEV_PART_*_MB` values inside `/tmp/install-runtime/runtime.env`. The runtime sizing logic uses the live install disk, fallback swap policy, hard floors, and explicit target sizes. On a 512 GiB install disk it aims for `/home=80 GiB`, `/data=100 GiB`, `/pool=150 GiB`, and a `32 GiB` raw zram backing partition before any remaining budget is given back to `/`. The F2FS/eMMC profiles keep a small fixed safety reserve so 29.25 GiB media can still fit the reduced F2FS minimum layout. In dual-boot mode the installer measures and validates the reused EFI partition plus every preserved pre-Debian slot before it computes the remaining Debian budget and renders the partman recipe. Tmpfs and zram runtime sizes are no longer emitted into `runtime.env`; they stay target-owned and percentage-based. Runtime device identity is still emitted: `ZRAM_BACKING_RAW_DEVICE` and `SWAP_FALLBACK_RAW_DEVICE` point at the raw partitions, while `ZRAM_BACKING_DEVICE` and `SWAP_FALLBACK_MAPPER` point at the boot-time plain dm-crypt mappers.

The target `zram-setup.service` serializes setup, reset, and stop operations
against the same `/run/zram/zram-writeback.lock` used by writeback passes, and
is ordered to finish before `multi-user.target` without waiting on debugfs. The
setup helper owns bounded waits for the raw by-partuuid backing device and
dm-crypt mapper readiness, so udev-late device nodes fail explicitly instead of
causing the one-shot unit to be skipped by a path condition. Reset uses
`zramctl --reset` first when available, waits for swapoff and open holders to
drain, verifies the device reaches the uninitialized state, and fails hard if
both zramctl and sysfs reset paths are rejected.
Maintenance actions run through one `zram-writeback.service` entrypoint for
timer-driven passes plus `zram-writebackd.service` for adaptive PSI pressure
events. The idle and cold-tier timers both trigger the one-shot service, while
the daemon registers `/proc/pressure/memory` triggers and dispatches only
pressure or emergency passes with cooldown and recovery hysteresis. The Perl
policy chooses `normal`, `pressure`, or `emergency` behavior from MemAvailable
and PSI without spawning separate action-specific interpreters. The generated
`/etc/zram-writeback.conf` owns maintenance policy: feature gates are explicit
`0`/`1` integers, recompression tiers are explicit, and cold-tier `MIN_*_PAGES`
values are real positive trigger counts rather than implicit disable switches.
The setup helper and Perl runtime both derive the effective
`writeback_batch_size` from the selected state target, the configured hard
ceiling, the smallest raw/mapped backing `nr_requests` value, and the
rotational-media cap. Per-pass page volume remains a separate policy limit, so
in-flight I/O depth cannot silently become the amount written in one pressure
pass. Cross-state validation also requires increasingly urgent batch/page
limits, shorter idle ages, stronger PSI thresholds, and no slower emergency
cooldown.
Cold-tier passes first check the configured zram fill percentage before scanning
debugfs block state, then apply independent page caps for idle, huge-idle, and
huge recompression, an explicit incompressible writeback page cap, and a
pages-per-spec cap for generated `page_index`/`page_indexes` writeback chunks.
The default tiering keeps `lz4` as the primary compressor, uses `lzo-rle` at
priority 1 for reusable idle pages, uses `zstd` at priority 2 for huge idle
pages, and uses a smaller priority-3 `zstd` pass for huge non-idle pages only
under pressure or emergency. Normal runs recompress and compact only; pressure
runs can write back incompressible pages when the kernel writeback budget still
has room; emergency runs can additionally write back huge idle pages. When the
budget is exhausted, policy leaves pages in zram and limits the pass to
recompression and compaction.

Lifecycle operations remain shell-owned: `zram-device-setup start`, `stop`,
`reset`, `wait-backing`, and minimal `status` own module loading, dm-crypt
mapper readiness, zram reset, `mkswap`, and `swapon`/`swapoff`. The shell helper
does not execute Perl or print runtime metrics; its status output is limited to
device presence, init state, swap activation, mapper existence/writability, and
zram sysfs presence. Perl owns rich runtime status, parsed swap/backing-device
state, feature support, parsed `mm_stat`/`io_stat`/`bd_stat` fields, and debugfs
`block_state` availability. The Perl maintenance unit remains ordered with
`Requires=` and `After=` on `zram-setup.service` so runtime policy only starts
after the boot device setup has completed. Under the writeback service hardening,
only `/run/zram` is kept writable for lock, budget, and metrics state. The
optional Perl `reset-state` command only removes runtime policy artifacts under
`/run/zram`; it does not swap off devices, reset zram, or close dm-crypt
mappings.

The staged zram policy assumes the installed target uses the repository's
XanMod kernel path, not an older fallback kernel contract. In practice this
means the target must provide `CONFIG_ZRAM_WRITEBACK`,
`CONFIG_ZRAM_MEMORY_TRACKING`, `CONFIG_ZRAM_TRACK_ENTRY_ACTIME`, and
`CONFIG_ZRAM_MULTI_COMP`, plus Linux 7.0+ `writeback` interface semantics that
accept key/value `type=...`, multiple `page_index=...` tokens, and mixed
`page_indexes=LOW-HIGH` ranges in a single call. The setup path intentionally
fails fast when those required zram sysfs capabilities are absent.

## Install Paths

If you do not select the `dualboot` addon class, the installer behaves like the full-disk install path:

- whole-device discard is attempted first when supported
- when discard is unavailable, `wipefs` is used if the installer image provides it; Debian Installer udebs do not ship `wipefs`, so the supported fallback is partition deletion plus a fresh GPT label
- a new GPT label is written
- Debian owns slots `1` through `12`

The detailed slot contract below describes the Btrfs storage family used by the
`btrfs-*` bare-metal NVMe profiles and the `vm-*` VM profiles. The `emmc`
F2FS family uses the reduced full-disk map owned by its concrete profiles
instead. In direct Secure Boot state mode that map is `1=/boot/efi`,
`2=/boot`, `3=/`, optional `4=/home` or `/pool`, `5=/var/log/journal`,
`6=raw swap fallback`, and `7=raw zram writeback`. When
`SECURE_BOOT_STATE_MODE=luks`, the runtime inserts `5=/var/lib/shim-signed`
as LUKS2 + ext4 and shifts the persistent journal, raw swap, and raw zram
partitions to slots `6`, `7`, and `8`.

The Btrfs full-disk slot contract is:

- slot `1`: `/boot/efi`
- slot `2`: `/boot`
- slot `3`: `/`
- slot `4`: `/home`
- slot `5`: `/opt`
- slot `6`: `/data`
- slot `7`: `/pool`
- slot `8`: `/var/tmp`
- slot `9`: `/var/lib/shim-signed` (LUKS2 + ext4)
- slot `10`: `/var/log/journal`
- slot `11`: raw swap fallback partition, opened at boot as `/dev/mapper/swap-fallback`
- slot `12`: raw zram writeback partition, opened at boot as `/dev/mapper/zram-writeback`

Dual-boot is enabled only when the kernel cmdline includes the `dualboot`
addon class and both required slot values:

- `classes=...,dualboot`
- `dualboot_efi=<n>`
- `dualboot_debian=<n>`

Omitting either slot value exits the install before partitioning.

The installer entrypoint accepts any of `url=`, `preseed/url=`, `file=`, or
`preseed/file=` as long as the value points at
`d-i/forky/preseed.cfg`. The runtime normalizes that value back to the served
`d-i/forky/` root before it fetches class fragments, hook assets, and phase
dispatchers.

```text
auto=true priority=critical locale=en_US.UTF-8 language=en country=US url=http://<lan-host>:8000/d-i/forky/preseed.cfg classes=lab,desktop,standard,dhcp,dualboot dualboot_efi=1 dualboot_debian=5
```

Override example:

```text
auto=true priority=critical locale=en_US.UTF-8 language=en country=US url=http://<lan-host>:8000/d-i/forky/preseed.cfg classes=lab,desktop,standard,dhcp,dualboot dualboot_efi=2 dualboot_debian=6
```

The dual-boot contract is UEFI + GPT on the same disk:

- `dualboot_efi=<n>` reuses the existing EFI System Partition at slot `n` and mounts it as `/boot/efi` without formatting it
- `dualboot_debian=<n>` makes Debian `/boot` start at slot `n`
- every slot from `1` up to `dualboot_debian - 1`, except the reused EFI slot, is preserved
- Debian then consumes a storage-family-specific contiguous partition range. The Btrfs/XFS layouts use 11 Debian-owned slots (`/boot`, `/`, `/home`, `/opt`, `/data`, `/pool`, `/var/tmp`, `/var/lib/shim-signed`, `/var/log/journal`, raw swap fallback, raw zram writeback). The F2FS layouts reuse the same `dualboot_efi=<n>` / `dualboot_debian=<n>` contract and allocate the F2FS-specific partition sequence required by the selected profile override.

Example: `classes=...,dualboot dualboot_efi=1 dualboot_debian=5`

- slot `1`: reused ESP
- slots `2`, `3`, `4`: preserved
- slots `5` through `15`: Debian-owned partitions

In dual-boot mode the partman preparation hook preserves the existing GPT label, verifies that `dualboot_efi=<n>` points at a real vfat GPT EFI System Partition, measures every pre-Debian partition slot, and steers partman to the target disk instead of whole-disk partitioning. If Debian-owned slots already exist from an earlier run, the partman option unmounts them, discards each partition when supported, uses `wipefs` only when the installer image already provides it, and deletes only slots from `dualboot_debian` upward through partman before selecting the newly freed span. A failing available `wipefs` still aborts deletion; an unavailable `wipefs` logs a warning and continues with validated partman deletion because Debian Installer udebs do not ship that command. Slots below `dualboot_debian` are never passed to the destructive cleanup path. If no Debian-owned slots exist, the installer selects the largest existing free span on `DEV_INSTALL_DISK`. The generated recipe contains only Debian-owned partitions, so the reused ESP and Windows-side slots are not recreated inside the selected free span; after autopartition succeeds, the partman option marks the existing `DEV_PART_EFI` partition as `method=efi` in partman state so partman-efi and GRUB recognize it without formatting it. When the `dualboot` addon class is selected, `d-i/forky/classes/class-addon/dualboot.cfg` keeps `os-prober` in `pkgsel/include`, flips GRUB installer answers to probe other operating systems, and late-command repairs the package if pkgsel missed it before the final GRUB update. On the target side GRUB is configured for `os-prober` discovery with `GRUB_DISABLE_OS_PROBER=false`, so other supported operating systems are detected by GRUB itself instead of by a hard-coded custom chainloader entry.

## Installer Flow

1. `d-i/forky/preseed.cfg` resolves `url=`, `preseed/url=`, `file=`, or `preseed/file=` to the served tree root, then wires the early, partman, and late dispatchers from that tree.
2. The shared bootstrap helper reuses the resolved seed source, records installer context under `/tmp/install-runtime`, caches fetched seed assets under `/tmp/install-runtime/cache/seed`, and fetches the real phase entrypoint directly for `prepare-context`, `apply`, `early`, `partman`, or `late`. `d-i/forky/scripts/preseed/dispatch.sh` remains only as compatibility glue for direct/manual invocation.
3. `d-i/forky/scripts/preseed/answers.sh` fetches only the selected class fragments under `d-i/forky/classes/**` that actually carry debconf deltas, merges additive `anna/choose_modules` and `pkgsel/include` answers, writes the generated Secure Boot package environment, and applies the generated debconf selections so class fragments do not overwrite one another. Tasksel is explicitly disabled in the active installer path, and any class fragment that tries to seed tasksel now aborts the install instead of silently enabling installer-selected tasks.
4. `d-i/forky/scripts/early/dispatch.sh` calls the shared d-i early hook with the selected storage family, generates the final hostname from `SYSTEM_PREFIX`, renders the identity/account/partman fragments under `/tmp/install-runtime`, and seeds debconf before the installer reaches netcfg, account setup, or partman.
5. `d-i/forky/scripts/partman/dispatch.sh` calls the selected shared partman path, which either wipes the whole disk for the default full-disk install path or preserves the existing pre-Debian slots for dual-boot, then installs a generated shared partman finish hook.
6. The generated shared `99-storage-layout` partman finish hook formats the managed filesystems, preserves the raw swap fallback and zram writeback partitions as block devices, mounts the persistent graph under `/target`, prepares volatile backing directories without mounting tmpfs, writes the target-side fstab, and writes a tmpfs-free partman fstab cache for d-i.
7. A shared installer apt-setup generator at `d-i/forky/hooks/shared/apt-setup/generators/99-apt-preferences` is injected into `/usr/lib/apt-setup/generators/` during d-i early setup so it retrieves `d-i/forky/repo.env`, reads `DEBIAN_APT_PREFERENCES`, and installs the selected managed preference files from the repo preferences directory into `/target/etc/apt/preferences.d` while apt-setup configures target APT state.
8. The shared late-command dispatcher validates the mounted target, stages tracked assets from `d-i/forky/hooks/shared/target/**` and `d-i/forky/hooks/hardware/<group>/<class>/target/**`, runs optional role late hooks from `d-i/forky/hooks/role/<role>/late_command.sh`, applies the kernel/bootloader/storage runtime policy, and finishes the GRUB, zram, journald, APT, and first-boot service configuration. Secure Boot uses a split flow: a shared `pre-pkgsel` hook stages the Secure Boot state mount, managed config, DKMS framework file, `/etc/kernel/*` hooks, and keypair before pkgsel starts, so NVIDIA DKMS postinst can sign modules during package configuration. After the target boot chain is installed and `update-grub` has rendered the managed menu, the storage-family late hooks use the installer-side bridge in `d-i/forky/scripts/late/grub.sh` to run `mokutil --reset` only when `mokutil --list-enrolled | grep Unattended` produces output. When reset is required, it uses the current `primary_user=` value as both MokManager password prompts, falling back to `ACCOUNT_USERNAME` when that cmdline value is absent. The bridge does not export, revoke, or queue individual MOK records. Immediately after the reset command, the target tool directly invokes `mokutil --timeout 900`; the late flow then sets the one-shot MokManager boot, copies `/target/var/lib/shim-signed/secure-boot/*` into `SB_MOK` on the installer USB EFI partition, and runs the final `repair_target_installed_kernels` pass only for kernel images with matching module trees. Service enablement is staged by writing the target systemd symlink graph directly; the installer does not call `systemctl enable`, `systemctl set-default`, or `systemctl is-enabled` inside `/target`.
9. Shared installer hooks at `d-i/forky/hooks/shared/finish-install.d/95-normalize-apt` and `99-normalize-finish` are injected into `/usr/lib/finish-install.d/` during d-i early setup. The repository does not ship, replace, or remove Debian Installer's stock `10clock-setup` or `20final-message` hooks; those stay owned by Debian Installer itself. Clock and timezone questions are owned by the initial preseed and are deliberately excluded from the generated dynamic answer set, so the later `debconf-set-selections` pass cannot disturb clock state after `clock-setup` has completed. Later in the sequence, `99-normalize-finish` runs after `preseed/late_command` and later numbered finish-install hooks. When Secure Boot state mode is `luks`, it unmounts `/target/var/lib/shim-signed` and closes the `secure-boot-mok` mapper before final normalization. It then unmounts any leftover nested target mounts below volatile paths, wipes the backing directories for tmpfs-enabled `/var/log`, `/var/cache`, `/var/lib/apt/lists`, `/data/run`, `/var/lib/systemd/coredump`, and `/dev/shm`, verifies those backing directories are empty, and normalizes `/tmp` immediately before the installer hands off to first boot.

When Secure Boot is enabled, the late hook preserves the managed keypair and DKMS framework setup, then runs `mokutil --list-enrolled | grep Unattended`. It skips `mokutil --reset` unless that pipeline produces output. When reset is needed, it supplies the selected `primary_user=` value, or the fallback `ACCOUNT_USERNAME`, twice on standard input for MokManager's password and confirmation prompts. The installer bridge injects that value through `SECURE_BOOT_MOK_DELETE_PASSWORD`, then directly invokes `mokutil --timeout 900` after the reset command. The target tool does not read `/proc/cmdline`, export certificates, generate hashes, revoke requests, or set shim fallback flags. If EFI variable access is unavailable during installation, no matching enrolled certificate is found and the late flow skips the reset. External modules are signed through the kernel header or kbuild `scripts/sign-file` path resolved for each installed kernel, while bootable kernel images with matching module trees are still signed and verified with `sbsign`/`sbverify`. Before `update-grub`, the late hook signs and verifies every eligible `/boot/vmlinuz-*` image with the generated MOK, forces the removable EFI fallback path to be a byte-for-byte copy of signed shim, patches GRUB's EFI video loader away from `all_video`/legacy UGA paths, and makes the firmware BootOrder/BootNext entry point at shim rather than GRUB. After a successful reset, and only once the target GRUB tooling and menu entries exist, the late hook writes `next_entry=installer-mok-enrollment` into `/boot/grub/grubenv` so the first target boot enters MokManager before trying to execute a MOK-signed kernel against the reset state. The managed GRUB menu keeps both the top-level menu and profile submenus at an indefinite wait. In dual-boot installs, `30_os-prober` remains executable only for the normal final `update-grub`/`grub-mkconfig` run; the managed `40_custom` generator never executes another GRUB generator directly. This preserves GRUB's package-owned execution environment, including `grub-mkconfig_lib`, while letting GRUB include detected foreign OS entries. They appear before the dynamic `Last Boot (<profile>) [<kernel>]` entry, then the `Balanced`, `Performance`, and `Hardened` profile submenus, `BTRFS Snapshots`, `Boot from Rescue USB`, `MOK Enrollment`, and finally `UEFI Firmware Settings`. The installer keeps the GRUB profile generator in `40_custom`, disables duplicate and unmanaged GRUB menu generators including `05_debian_theme`, and writes the same managed menu to `/boot/grub/custom.cfg` without enabling a separate GRUB theme or managed font override. The display drop-in keeps `gfxterm` for the GRUB menu at the 1024x768 firmware mode commonly associated with legacy VGA 766, preloads only `efi_gop` plus `gfxterm` for the signed EFI path, leaves the GRUB menu uncolored, and sets the managed Linux menu payload to text so kernel KMS can re-probe the real runtime display cleanly. When the optional `timeshift` addon is selected on a Btrfs-root host, the late hook also stages managed Timeshift snapshot timers plus a GRUB snapshot refresh helper so `BTRFS Snapshots` loads `/boot/grub/grub-btrfs.cfg` generated from the current Timeshift snapshot set and profile flags. The generated GRUB `Boot from Rescue USB` entry requires UEFI GRUB, derives the installer rescue USB search UUID from the first partition on the USB seed device when available, falls back to a removable-EFI file search otherwise, prints `Rescue USB not plugged in` when the installer media is absent, and chainloads the architecture-specific removable EFI path (`/EFI/BOOT/BOOTX64.EFI` on `amd64`, `/EFI/BOOT/BOOTAA64.EFI` on `arm64`). The generated GRUB `MOK Enrollment` entry documents the existing `/var/lib/shim-signed/secure-boot/MOK.der` certificate, resolves the mounted target ESP to a fixed GRUB GPT device during configuration generation, and directly chainloads the architecture-specific MokManager binary under `EFI/debian` (`mmx64.efi` on `amd64`, `mmaa64.efi` on `arm64`) from that device without a boot-time GRUB `search`, so selecting it starts MokManager against the generated certificate. The same certificate and key bundle are also copied late into `SB_MOK` on the installer USB EFI partition for operator access outside the target. The generated signing certificate intentionally omits shim's module-signing-only EKU OID `1.3.6.1.4.1.2312.16.1.2`, because shim and GRUB ignore that class of key for kernel image validation and would reject installer-signed boot images with `bad shim signature`. Debian still requires any requested MokManager reset to be confirmed on the boot console with the selected account username. When `SECURE_BOOT_STATE_MODE=luks`, open the encrypted Secure Boot state after installation with `luks-mok-open` before any kernel-signing or MOK-management work, close it with `luks-mok-close`, and rotate its passphrase with `luks-mok-passwd`.

For snapshot-only GRUB maintenance while the Secure Boot state is closed, run
`SKIP_MOK_SIGNING=1 update-grub`. This suppresses only the managed MOK
enrollment menu and certificate checks; it does not sign or modify kernels.
The managed `grub-btrfs-refresh.service` exports this value and refreshes only
`/boot/grub/grub-btrfs.cfg`, so Timeshift snapshot events do not need the MOK
state to be open.
The refresh unit now runs in a private mount namespace, reuses the fixed
runtime directory `/run/grub-btrfs-refresh`, and triggers from the Timeshift
runtime snapshot root (`/run/timeshift/*/backup/timeshift-btrfs/snapshots`)
instead of every change under `/run/timeshift`. That keeps refresh work scoped
to one start per Timeshift run and prevents transient GRUB snapshot scans from
leaking global `/run/grub-btrfs-refresh.*` mounts.
The managed snapshot services use a six-hour execution ceiling, idle I/O
priority, and a private umask. The shared `fwupd-refresh.service` drop-in also
preserves upstream success semantics for exit statuses `2` and `101`, so an
already-current metadata refresh is not reported as a failed systemd unit. A
separate package-unit ordering drop-in places `fwupd.service` after
`upower.service` during startup, which reverses to fwupd stopping first when
both participate in shutdown and keeps firmware plugins from querying a
provider already being torn down.

The Btrfs and VM families default to a dedicated encrypted
`/var/lib/shim-signed` partition and the `luks-mok-*` helpers. The F2FS
families stage the same Secure Boot toolchain and GRUB/MOK workflow, and their
state path is selected by `SECURE_BOOT_MODE`/`SECURE_BOOT_STATE_MODE`: `direct` keeps Secure Boot
state on the root filesystem under `/var/lib/shim-signed/secure-boot`, while
`luks` inserts a dedicated LUKS2 + ext4 `/var/lib/shim-signed` partition into
the reduced F2FS partition map and stages the same `luks-mok-*` helpers used by
the Btrfs profiles.

The F2FS root filesystem is created with
`extra_attr,inode_checksum,sb_checksum,inode_crtime,lost_found,compression`,
and optional F2FS `/home` uses the same feature set without `lost_found`.
These filesystems are then mounted with lzo-rle compression in filesystem
mode. The shared F2FS policy compresses root broadly with
`compress_extension=*`, excludes already-compressed media, archives, package
payloads, and disk images with repeated `nocompress_extension=` entries capped
to the current F2FS extension-list limit, and uses `nodiscard` because the
installed system enables `fstrim.timer`.

## Validation

Review the shared hook implementations, hardware target assets, and staged shared target assets
directly under `d-i/forky/**` before serving installer changes. Runtime class,
host-profile, and late-phase consistency checks now live in the installer code
paths themselves instead of in a separate validation script.

## Installer Logs

Installer logging is always active. All installer stages append structured
records to `/tmp/installer.log`; the final finish-install hook writes a
redacted copy to `/var/lib/installer-state/installer.log` on the target.
Records cover boot context, answer-file loading, network and disk discovery,
partman, APT and package operations, bootloader work, late-command target
customization, and desktop staging in one chronological stream.

Log records include fixed stage labels such as `boot`, `preseed_loaded`, `network_configured`, `disk_discovery`, `partman_start`, `partman_done`, `base_install_start`, `apt_config`, `package_install`, `bootloader`, `late_command`, `target_customization`, `first_boot`, and `post_install_validation`.

The same state directory includes bounded, redacted copies of Debian Installer
logs under `/var/lib/installer-state/debian-installer/`, including live
`syslog`, `partman`, and `debootstrap` logs when those files are present. When
a failed install stops before the target archive is complete, the most useful
live logs remain in `/tmp/installer.log` and `/var/log/` inside the installer
environment.

The first boot service stages `/usr/local/sbin/firstboot.sh`, runs ordered
scripts from `/usr/local/lib/firstboot.d/`, leaves initramfs health logs under
`/var/lib/installer-state/logs/initramfs/` with numbered hook-stage names from
`01-init-top.log` through `07-init-bottom.log`, and stores firstboot data under
`/var/lib/installer-state/logs/firstboot/`. The `local-block` stage runs only
when initramfs-tools retries root-device discovery; when no retry is needed,
`04-local-block.log` records that fact explicitly instead of leaving a gap.
Initramfs hooks spool early records under `/run/installer-initramfs-health`;
firstboot copies that spool into the persistent initramfs log directory after
switch-root and writes
`/var/lib/installer-state/firstboot/complete`.

Cleanup is deliberately manual so diagnostic evidence remains available until
an operator reviews it. Run `systemctl start secondboot.service` after
first-boot validation and any required enrollment work is complete. When
`addon/crypto` is selected, the service refuses to run while
`/usr/local/lib/crypto/tpm2-enroll.pending` exists. After successful TPM2
enrollment, automatic cleanup removes the one-time `tpm2-enroll.sh` wrapper, desktop
launcher, shell-login prompt, autostart entry,
`/usr/local/lib/crypto/config.env`, the temporary installer passphrase, and the
cleanup service itself. It deliberately preserves `/etc/crypttab`,
`/etc/cryptsetup-keys.d/crypthome.key`, `/etc/tpm2-cryptroot.conf`, and the
`initramfs-tools` TPM2 hook/local-top script because those remain required for
normal encrypted boot.

The second-boot cleanup removes `/var/lib/installer-state`, completed one-time
CrowdSec/Tailscale bootstrap helpers and units, and any remaining repo-managed
initramfs health hooks, then rebuilds the installed initramfs when those hooks
were present. It removes CrowdSec enrollment artifacts and preserves the
Tailscale helper/defaults/service when Tailscale enrollment is still pending.
Completed
bootstrap markers, status files, logs, and staged secrets are removed together.
Persistent services and operational configuration such as
`tailscaled.service` hardening, `managed-syncthing.service`, dynamic
`podman-rootless-linger*.service` units, CrowdSec engine/bouncer units, and the
CrowdSec bouncer API key remain installed. The cleanup is intentionally
irreversible for removed diagnostics and completed one-time enrollment
material.

## First-Boot Checks

After installation, validate the live storage contract on the target machine:

```bash
findmnt -no FSTYPE,OPTIONS /data
findmnt -no FSTYPE,OPTIONS /data/run
findmnt -no FSTYPE,OPTIONS /pool
xfs_info /data
xfs_info /pool
findmnt -no FSTYPE,OPTIONS /var/log
findmnt -no FSTYPE,OPTIONS /var/log/journal
findmnt -no FSTYPE,OPTIONS /var/tmp
findmnt -no FSTYPE,OPTIONS /var/cache
findmnt -no FSTYPE,OPTIONS /var/lib/apt/lists
findmnt -no FSTYPE,OPTIONS /var/lib/systemd/coredump
cryptsetup status swap-fallback
cryptsetup status zram-writeback
state_mode=$(sed -n 's/^SECURE_BOOT_STATE_MODE=//p' /etc/default/secure-boot.conf | tr -d "'\"")
if [ "$state_mode" = "luks" ]; then
  luks-mok-open
  findmnt -M /var/lib/shim-signed -no SOURCE,FSTYPE,OPTIONS
else
  test -d /var/lib/shim-signed/secure-boot
fi
ls -l "/boot/efi/MOK Enrollment/MOK.der"
ls -l /boot/grub/fonts/dejavu-sans-mono.pf2
if [ "$state_mode" = "luks" ]; then
  luks-mok-close
fi
stat -c '%a %n' /var/tmp /tmp
test -L /data/run/mnt
test "$(readlink /data/run/mnt)" = "/run/media/mcramer"
swapon --show
lsblk -o NAME,FSTYPE,TYPE,MOUNTPOINTS
test -s /boot/grub/grubenv
grub-editenv list
test "$(readlink -f /etc/systemd/system/dbus.service)" = "$(readlink -f /usr/lib/systemd/system/dbus-broker.service)"
test "$(readlink -f /etc/systemd/user/dbus.service)" = "$(readlink -f /usr/lib/systemd/user/dbus-broker.service)"
test -r /etc/systemd/user/dbus-broker.service.d/10-broker-hardening.conf
test ! -e /etc/skel/.config/systemd/user/dbus-broker.service.d/10-broker-hardening.conf
dpkg-query -W dbus-broker dbus-user-session dbus-bin dbus-system-bus-common dbus-session-bus-common
! dpkg-query -W dbus
! dpkg-query -W dbus-daemon
! dpkg-query -W dbus-x11
! grep -q 'dbus-run-session' /usr/local/bin/labwc-greeter-session /usr/local/bin/labwc-session
grep -q 'pam_systemd\.so class=greeter type=wayland desktop=labwc' /etc/pam.d/greetd-greeter
! grep -q 'pam_systemd\.so class=user-light' /etc/pam.d/greetd-greeter
grep -q '^export LABWC_SESSION_OWNER=greeter$' /usr/local/bin/labwc-greeter-session
grep -q 'labwc-greeter-output --configure' /usr/local/libexec/labwc-greeter-client
grep -q 'labwc-greeter-output --watch' /usr/local/libexec/labwc-greeter-client
grep -q 'labwc-greeter-power' /usr/local/libexec/labwc-greeter-client
grep -Fq 'if [ "${LABWC_SESSION_OWNER:-}" != desktop ]; then' /usr/local/bin/labwc-autostart
grep -q '^/usr/bin/labwc -C "\$greeter_config_dir" -S "\$greeter_client"$' /usr/local/bin/labwc-greeter-session
grep -q 'dbus-update-activation-environment' /usr/local/bin/labwc-autostart
grep -q 'import-environment' /usr/local/bin/labwc-autostart
grep -q 'QT_OPENGL QSG_RHI_BACKEND' /usr/local/bin/labwc-autostart
grep -q 'labwc-session.target' /usr/local/bin/labwc-autostart
test ! -e /etc/environment.d/90-labwc-session.conf
test -r /etc/skel/.config/systemd/user/labwc-session.target
for unit in \
  foot-server.service foot-server.socket mako.service hyprpolkitagent.service \
  pipewire.service pipewire-pulse.service pipewire.socket pipewire-pulse.socket \
  wireplumber.service filter-chain.service wayscriber.service \
  xdg-desktop-portal.service xdg-desktop-portal-gtk.service \
  xdg-desktop-portal-wlr.service xdg-desktop-portal-lxqt.service
do
  test -r "/etc/systemd/user/${unit}.d/10-labwc-session.conf"
  test ! -e "/home/mcramer/.config/systemd/user/${unit}.d/10-labwc-session.conf"
done
test ! -e /etc/systemd/user/labwc-kwallet-portal.service
test ! -e /etc/systemd/user/labwc-kwalletd6.service
test -r /home/mcramer/.local/share/dbus-1/services/org.freedesktop.impl.portal.desktop.kwallet.service
test -r /home/mcramer/.local/share/dbus-1/services/org.freedesktop.secrets.service
test -r /home/mcramer/.local/share/dbus-1/services/org.kde.secretservicecompat.service
test -r /home/mcramer/.local/share/dbus-1/services/org.kde.kwalletd6.service
dpkg-query -W bluez rfkill brightnessctl brightness-udev grim slurp wf-recorder libgtk-4-1 libadwaita-1-0
systemctl is-enabled bluetooth-controller-init.service bluetooth.service
systemctl status bluetooth-controller-init.service bluetooth.service --no-pager
grep -q '^AutoEnable=true$' /etc/bluetooth/main.conf
grep -q '^SecureConnections = on$' /etc/bluetooth/main.conf
! grep -q '^KernelExperimental' /etc/bluetooth/main.conf
test "$(stat -c %a /opt/tuta-mail)" = 755
test -x /usr/local/bin/labwc-bluetooth
test -x /usr/local/bin/labwc-brightness-control
test -x /usr/local/bin/labwc-capture
test -x /usr/local/bin/satty
test -x /usr/local/libexec/satty/satty
test -r /usr/local/share/satty/release
test -r /opt/glibc/2.44-1/satty/.managed-release
dpkg-query -W wayscriber
test -x /usr/bin/wayscriber
test -x /usr/local/bin/labwc-wayscriber-toggle
test -r /etc/systemd/user/wayscriber.service.d/10-labwc-session.conf
test -x /usr/local/bin/waypaper
case "$(readlink -f -- /usr/local/bin/waypaper)" in /opt/waypaper/*) ;; *) exit 1 ;; esac
! find /opt/waypaper -xdev \( -type d -o -type f \) \( ! -user root -o ! -group root -o -perm /022 \) -print -quit | grep -q .
! find /opt/waypaper -xdev -type f -perm /6000 -print -quit | grep -q .
test ! -e /opt/waypaper/.pipx-build-home
! getent passwd installer-pipx-build >/dev/null
test ! -e /home/mcramer/.local/bin/waypaper
grep -Fx 'TryExec=/usr/local/bin/waypaper' /home/mcramer/.local/share/applications/waypaper.desktop
grep -Fx 'Exec=/usr/local/bin/waypaper' /home/mcramer/.local/share/applications/waypaper.desktop
test -r /home/mcramer/.local/share/applications/waypaper.desktop
test -r /etc/skel/.config/satty/config.toml
test -r /etc/skel/.config/GottCode/FocusWriter.conf
test -r /etc/skel/.local/share/GottCode/FocusWriter/Themes/managed-word.theme
test -r /etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/thunar.xml
grep -q '"custom/bluetooth"' /etc/skel/.config/waybar/config
grep -q '"custom/backlight"' /etc/skel/.config/waybar/config
grep -q '"custom/screenshot"' /etc/skel/.config/waybar/config
test -r /etc/skel/.config/mako/config
test -r /etc/skel/.config/systemd/user/labwc-health-notify.path
test -x /usr/local/libexec/unattended-upgrades-notify
test -r /etc/systemd/system/apt-daily-upgrade.service.d/50-unattended-upgrades-notify.conf
! grep -Fq '"origin=*"' /etc/apt/apt.conf.d/52unattended-upgrades
grep -Fq '"site=deb.debian.org"' /etc/apt/apt.conf.d/52unattended-upgrades
grep -Fq '"site=security.debian.org"' /etc/apt/apt.conf.d/52unattended-upgrades
grep -Fq '"site=packages.microsoft.com"' /etc/apt/apt.conf.d/52unattended-upgrades
grep -Fq '"^linux($|-).*"' /etc/apt/apt.conf.d/52unattended-upgrades
grep -Fq '"^.*vulkan.*$"' /etc/apt/apt.conf.d/52unattended-upgrades
grep -Fq '"^libegl($|-|[0-9]).*"' /etc/apt/apt.conf.d/52unattended-upgrades
grep -Fq '"^pipewire($|-).*"' /etc/apt/apt.conf.d/52unattended-upgrades
dpkg-query -W udisks2 polkitd
getent group usbmedia
getent group usbadmin
test -r /etc/udisks2/udisks2.conf
test -r /etc/udisks2/mount_options.conf
test -r /etc/udev/udev.conf.d/90-hardening.conf
test -r /etc/udev/rules.d/90-udisks-behavior.rules
# The following rules are desktop-role assets; server roles do not stage them.
for rule in \
  00-admin-identities.rules \
  04-fwupd-refresh.rules \
  05-active-local-gate.rules \
  10-pkexec.rules \
  20-login1-power.rules \
  40-networkmanager.rules \
  50-usb-policy.rules \
  55-software-management.rules \
  60-system-services-identity.rules \
  70-hardware-peripherals.rules
do
  test -r "/etc/polkit-1/rules.d/$rule"
done
systemctl get-default
systemctl is-enabled swap-fallback.service zram-setup.service zram-writebackd.service zram-idle-writeback.timer zram-cold-tier.timer fstrim.timer btrfs-scrub.timer btrfs-balance.timer
test -r /etc/systemd/system/tmpfs-pre-clean.service
systemctl status apt-refresh-lists.service --no-pager  # only when TMPFS_VAR_LIB_APT_LISTS=true
systemctl status fstrim.timer fstrim.service --no-pager
systemctl status swap-fallback.service --no-pager
systemctl status zram-setup.service --no-pager
systemctl status zram-writeback.service --no-pager
test -d "/home/<user>/Workspace"
find /etc /usr/local/sbin /var/lib/installer-state -name '*install*' -print
```

When a layer sets a managed `TMPFS_*` policy to true, late command empties and
normalizes the backing directory before the installed system boots, and the
generated `tmpfs-pre-clean.service` plus mount drop-ins wipe the same backing
directories again on every boot before the tmpfs mounts are attached. `/tmp`
also stays in that boot-time pre-clean set, while `/dev/shm` joins it whenever
`TMPFS_DEV_SHM=true`. This keeps early writers from polluting persistent
backing directories before the volatile mounts land, and it keeps
`systemd-tmpfiles-setup.service` operating on the mounted tmpfs trees instead
of the persistent rootfs copies. The managed tmpfiles fragments only recreate
installer-owned child paths so Debian's vendor tmpfiles fragments keep
ownership of `/run/lock`, `/var/log`, `/var/cache`, and
`/var/lib/systemd/coredump`.

`apt-refresh-lists.service` is staged and enabled only when
`TMPFS_VAR_LIB_APT_LISTS=true`. The `/var/lib/apt/lists` mount drop-in orders it
after the volatile apt-lists mount, and the helper only repairs apt list state,
performs bounded Debian mirror connectivity probing, and runs `apt-get update`.
The service also orders itself after `NetworkManager-dispatcher.service` and
waits briefly for that dispatcher unit to become inactive before refreshing apt
metadata, so network-dispatcher work triggered during first boot is not raced.
The managed `apt-daily.service.d` override no longer depends on
`apt-refresh-lists.service`; it only carries the common noninteractive and
hardening settings.

`fstrim.timer` is enabled with a local four-day interval override, while Btrfs scrub and balance are delegated to `btrfsmaintenance` only on Btrfs targets. The generated Btrfs maintenance config logs to the journal, scrubs `/`, `/home`, and `/opt` monthly, runs a mild monthly balance only for `/`, and leaves trim disabled there because `fstrim.timer` owns discard scheduling.
