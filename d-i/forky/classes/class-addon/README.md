# Add-on Classes

Place direct `*.cfg` class fragments here for local additive classes. For
example, `testing.cfg` can be selected on the installer kernel command line as
`classes=...,testing`.

`nvidia.cfg` installs the NVIDIA driver and firmware stack when selected as
`classes=...,nvidia` and an NVIDIA PCI display adapter is detected. NVIDIA is
intentionally not auto-selected from PCI detection.

`cuda.cfg` installs the NVIDIA CUDA 13.1 compiler and userspace runtime archive
when selected as `classes=...,nvidia,cuda`. The manifest requires both `addon/nvidia` and
`arch/amd64`, so selecting `cuda` without `nvidia` or on non-amd64 targets is
rejected before install-time package selection.

`nvidia-legacy.cfg` installs the Pascal-capable NVIDIA 580 driver baseline when
selected as `classes=...,nvidia-legacy` and an NVIDIA PCI display adapter is
detected. It is mutually exclusive with the non-legacy `nvidia` and `cuda`
classes.

`cuda-legacy.cfg` installs the Debian 12 CUDA 12.8 and 12.9 compiler/userspace
stacks when selected as `classes=...,nvidia-legacy,cuda-legacy`. The manifest requires both
`addon/nvidia-legacy` and `arch/amd64`, rejects the non-legacy NVIDIA/CUDA
classes, and only stages its packages or temporary CUDA archive wiring when an
NVIDIA PCI display adapter is detected.

`crowdsec.cfg` installs CrowdSec and the nftables firewall bouncer when
selected as `classes=...,crowdsec`. The addon also stages role-aware
acquisition YAML, extra auditd rules, an optional `crowdsec_token=`-driven
console enrollment helper, and target APT preferences that keep the testing
archive preferred over CrowdSec stable for CrowdSec packages only.

`server-suite.cfg` is restricted to `role/server` through
`classes/configs/addons.cfg`. When selected as
`classes=...,server-suite`, it keeps the installer and target package policy on
Debian Trixie, stages the dedicated `95default-server-suite` target APT
default-release asset, and still exposes Debian Forky plus the XanMod archive
as fallback sources for controlled server-side package pulls.

`software.cfg` stages the Microsoft Visual Studio Code, Microsoft Edge,
Vivaldi Browser, Microsoft PowerShell, Mullvad Browser and VPN, and Spotify
archives plus qBittorrent, Telegram Desktop, database client tooling, and the matching
`pkgsel/include` packages when selected as `classes=...,software`. Both this
bundle and the standalone `apps/mullvad` class keep only `mullvad-browser` in
`pkgsel`; the shared late helper captures the installer resolver and then
installs Debian's `systemd-resolved` before it installs `mullvad-vpn` from
Mullvad's official architecture-specific latest Debian artifact. Moving the
resolver ownership transition out of the shared package transaction prevents
it from changing DNS underneath unrelated maintainer scripts. After the
transition, the helper requires the legacy `resolvconf` package to be absent,
validates the `resolvectl` compatibility link and the managed
`/etc/resolv.conf` symlink, seeds the target's own
`/run/systemd/resolve/stub-resolv.conf` from the captured installer DNS, and
probes Mullvad, Bitwarden, and GitHub through a raw chroot. It deliberately
waits until Debian Installer's temporary `/run`-to-`/target/run` bind mount is
gone, so the stub is not written into the installer runtime and discarded
during `in-target` cleanup. The same bounded seed and probe runs again after
`mullvad-vpn` package triggers, producing an explicit late-command failure
instead of allowing later selected-class downloads to continue with a broken
resolver. The seeded `/run` file is only late-command continuity state;
`systemd-resolved` recreates and owns it at boot.

The late helper downloads the matching detached signature and code signing
key, pins the published primary fingerprint, validates the package name and
architecture, and only then installs the local package through target APT. This
prevents a stale Mullvad repository index from making the whole `pkgsel`
transaction depend on a removed versioned pool object; the repository remains
configured for `mullvad-browser` and subsequent package updates. The desktop
role's root-owned `mullvad-daemon.service` drop-in requires
`systemd-resolved.service` and forces Mullvad's supported
`TALPID_DNS_MODULE=systemd` backend. Every tracked Tailscale profile keeps
`TAILSCALE_ACCEPT_DNS=false`, so Tailscale remains available without competing
for resolver ownership. Mullvad's vendor cache format and lifecycle remain
unchanged. No Mullvad account identifier, automatic login, or automatic VPN
connection is staged.
The desktop role separately disables automatic GVFS WSDD discovery through the packaged
`org.gnome.system.wsdd` GLib schema so managed VPN and virtualization
interfaces are not probed.
The software addon's selected-class late helper
also installs the current Bitwarden Desktop, Zoom Workplace, and Filen Desktop
Debian packages from their vendor HTTPS endpoints, installs checksum-pinned
QoreDB `0.1.38` and Gridline `0.7.11`, and installs pinned Obsidian `1.12.7`
and Sleek `2.0.26` amd64 Debian packages from their official GitHub
releases with exact size and SHA-256 checks, extracts the current Postman Linux
archive into `/opt/postman`, and adds the current
Ledger Wallet (Ledger Live) and Tuta Mail AppImages on `amd64`. Ledger is
downloaded from `https://download.live.ledger.com/latest/linux`; the helper
resolves the current stable contract from Ledger's official `latest-linux.yml`,
requires the expected versioned x86-64 filename and size, verifies Ledger's
signed SHA-512 manifest against a pinned public key, and rejects any mismatch
between metadata, signed manifest, and downloaded bytes. Redirecting endpoints are followed only over HTTPS
into an atomic partial file; the final HTTP status, effective URL, content type,
and byte bounds are checked before publication. Vendor Debian downloads are
then rejected unless their archive framing, package name, version, architecture,
payload executable, and desktop entry match the managed contract. Postman's
archive is accepted only when every unique member remains below the single
`Postman/` root, required executable, metadata, sandbox, and icon members are
present, and both member-count and extracted-size ceilings hold. Its root-owned
atomic publication preserves the relative `Postman -> app/Postman` symlink,
enables setuid-root only for the bundled Chromium sandbox, records the resolved
version and SHA-256, and installs a validated launcher that uses the archive's
`Postman/app/resources/app/assets/icon.png`. Sleek is required to be the
`107,065,664`-byte `sleek` `2.0.26` amd64 package with SHA-256
`f2531c41b70c04bbafc27af83e195aa9268845a58d3ead4b58fa58b301223fcb`,
`/opt/sleek/sleek`, and `/usr/share/applications/sleek.desktop` before APT
installs it. The vendor launcher is then replaced with a validated managed
native-Wayland entry that keeps the packaged icon and adds the registered
`Office` category. The Tuta artifact is
verified with Tuta's detached SHA-512/RSA signature and the pinned vendor public
key, extracted into a root-owned read-only `/opt/tuta-mail` tree with a `0755`
AppDir root, and exposed through a managed desktop launcher and icon. Tuta
launches inside bubblewrap with only its dedicated persistent state, the Wayland
socket, mediated desktop portal/notification D-Bus access, and a filtered
session-bus allowlist for the standard FreeDesktop Secret Service name. It does not receive a
system-bus socket. Its nested Electron Chromium sandbox is disabled only inside
the outer bubblewrap namespace in normal and accelerated modes to avoid
conflicting user namespaces while preserving the managed filesystem, process,
D-Bus, and Wayland boundary. The extracted Tuta AppDir is
declared explicitly and Electron uses the `gnome-libsecret` Secret Service
frontend, which does not install or expose a GNOME keyring daemon. The managed
FreeDesktop Secret Service provider initializes secure storage. Every published
AppDir directory is normalized to mode `0755`, files
remain root-owned and non-writable to desktop users, and unused set-ID bits are
removed before launch. Tuta publication is rollback-safe across service
interruption: the weekly updater restores the previous AppDir when shutdown
interrupts the directory swap, repairs the AppDir permissions, and recovers any
preserved backup before the next update. User
launcher synchronization also removes direct, unmanaged Tuta AppRun entries so
all launches continue through the verified `/opt/tuta-mail/AppRun` contract.
Discord is not installed from its current bootstrap-only Debian package. During
the selected-class late phase, the installer resolves Discord's stable Linux
x64 distribution manifest, validates the complete host plus every declared
Brotli-compressed `full.distro` module against the manifest SHA-256 values,
rejects incomplete or unsafe tar payloads, and atomically publishes the
root-owned runtime below `/opt/discord`. The late phase fails if
any required host executable, build metadata file, or retained module is
absent, or if the Chromium sandbox and executable modes are invalid, so the
complete runtime exists before the first desktop login. Current Discord
distributions use the bootstrap host and module layout and do not require the
legacy root `resources/app.asar`; legacy archives that include that additional
regular file remain valid. The same servicing implementation is reused by the
scheduled updater and automatically rebuilds an incomplete runtime from
retained verified artifacts; `/usr/local/libexec/managed-discord-distro` is its
networkless manifest/archive validator and extractor, not a login-time
downloader or compiler.
Bitwarden, Obsidian, Postman, Sleek, Tuta, Filen, Discord, and Vivaldi receive
native Wayland launch paths with Intel and NVIDIA actions. Applications whose
persistent state can be meaningfully isolated also receive OpenGL-only privacy
actions; Obsidian, Postman, Sleek, Tuta, and Discord keep their file-visible
normal and accelerated launch paths only. Every Electron process uses its own
unique V8 old-space ceiling below 2024 MiB in every mode and selects the
`gnome-libsecret` Secret Service frontend; this does not install or expose a
GNOME keyring daemon.
Package Electron applications retain their own root-owned library directories
through named non-scrubbing AppArmor transitions from the launcher's fixed
allowlisted environment; their version-specific `libffmpeg.so` files are not
replaced with one system-wide copy. Filen and Discord keep their
background timers, occluded windows, and renderer processes active so sync,
notifications, and calls do not stall. Zoom and Telegram Desktop use the same
managed native Qt Wayland/OpenGL launcher policy. Managed Chromium/Electron
launches disable Vulkan features, and Qt Quick launchers set
`QSG_RHI_BACKEND=opengl`; no managed launcher selects a Vulkan ICD or backend.
Managed launchers are written
atomically into a primary-account-owned XDG application directory, allowing
Vivaldi to perform its own temporary desktop-entry rewrites without permission
errors. Vivaldi's profile and cache roots are pre-created with private ownership,
and managed application environments select Debian's `/etc/fonts/fonts.conf`
explicitly. Managed Chromium and Electron launches disable the
`WaylandWindowDecorations` client-side fallback; seeded Chromium-family and
Obsidian preferences request native system frames. The managed Obsidian launch
path registers the private `~/Syncthing/obsidian-md` default vault
idempotently using only the installed `$HOME` state, never runtime reads from
`/etc/skel`. It preserves other vault registrations and supplies its
dependency-free `evergreen-notes` theme, UX snippet, structured note folders,
templates, recovery-oriented local trash, and safe core-plugin defaults.
Community plugins and Obsidian-hosted sync or publishing features remain
disabled. A scoped Syncthing ignore rule leaves per-device workspace layouts
unsynchronized without excluding vault content. Visual Studio Code requests a
native title bar, disables its bundled
AI/Copilot features, and applies the managed built-in dark workbench, terminal,
syntax, semantic-token, privacy, and editor UX defaults. The shared Labwc
environment requests compositor
decorations from Qt and GTK with
`QT_WAYLAND_DISABLE_WINDOWDECORATION=1` and `GTK_CSD=0`. Filen has no supported
native-frame preference and hardcodes its own renderer controls, so the
config-only contract can disable Chromium's decoration fallback but cannot
remove Filen's embedded controls without changing the vendor application. The
desktop role does not add this class automatically; select it explicitly when
you want the monolithic external software bundle instead of the per-app
`apps/*` classes.

Before `pkgsel`, the shared installer hooks temporarily divert the target's real
`/usr/bin/unshare` and replace it with a success-only shim. This covers package
maintainer scripts and the later direct vendor Debian transactions that probe
user namespaces from the restricted d-i environment. The final
`99-normalize-finish` hook validates the installer marker, removes the shim, and
restores the diverted real binary before the installed system boots. The five
baseline direct vendor Debian transactions, the class-gated ChatGPT
transaction, and the scheduled managed external-software updater keep
`NEEDRESTART_SUSPEND=1` scoped to their automatic package transactions, so they
never request restart handling for services or user sessions.
Administrator-initiated APT operations and every application or Bubblewrap
sandbox use the real `unshare(1)` binary.

When `addon/crowdsec` is selected, the class keeps LAPI enabled and explicitly
defers package-time CAPI registration to `crowdsec-firstboot.service`. The real
package-provided `/usr/bin/cscli` is never diverted or replaced. First boot
requires the managed Linux and auditd collections, creates CAPI credentials
when absent, and provisions the firewall bouncer key before enabling
remediation. The testing and stable packagecloud feeds and their existing
pinning policy are unchanged.

Installer downloads are confined to `/tmp/installer-software` and removed on
success, failure, or interruption; the managed post-boot updater likewise uses
a private `/tmp/managed-external-software-update.*` workspace. Managed
application payloads use a non-brittle 1 MiB transport floor; Debian archives
are still required to pass archive framing, metadata, architecture, executable,
and desktop-entry validation, while Tuta remains protected by its pinned
signature and executable AppImage checks.
The verified Ledger AppImage is extracted into root-owned `/opt/ledger-live`,
its bundled Chromium sandbox is the only payload granted setuid-root mode, and
the managed launcher keeps native Wayland plus KWallet-backed password storage
without the vendor desktop file's `--no-sandbox` argument. A class-scoped udev
rule covers Ledger Stax and other current `2c97` devices, including
re-enumerated firmware-update modes, while keeping USB and hidraw nodes at
`0660` with `plugdev` plus active-seat `uaccess`; the vendor rule's
world-writable `0666` hidraw mode is not used.

Selecting `addon/software` stages a two-phase managed-external-software
schedule. `managed-external-software-download.timer` checks vendor releases
each Sunday at 01:30 with a bounded randomized delay, validates new artifacts,
and retains them without changing installed applications.
`managed-external-software-update.timer` runs separately at 05:30 and applies
only those already retained artifacts. Both timers catch up after downtime and
share a lock, so a delayed download cannot race an apply action.

Every verified external Debian package, AppImage, Postman tarball, and Discord
distribution artifact is retained below root-owned `/var/lib/software`: Debian
archives live in `debs/`, vendor binaries in `artifacts/`, state markers in
`state/`, and desktop notification events in `events/`. The local APT source
indexes the retained Debian archives for Mullvad VPN, Bitwarden, QoreDB,
Gridline, Obsidian, Zoom, Filen, and Sleek before APT installs them. When
`addon/devops` is selected, its exact root-owned
`state/chatgpt.enabled` marker also admits the validated ChatGPT archive into
the same repository; `addon/software` without that marker does not download,
retain, install, update, repair, or expose ChatGPT. The mutable ChatGPT
`latest` URL is deliberately not paired with or compared against a
release-pinned SHA-256: the updater instead enforces HTTPS, the vendor hostname,
bounded size, Debian archive framing, the `chatgpt` package name, `amd64`
architecture, and required payload paths. SHA-256 values written to the local
APT `Packages` and `Release` metadata are calculated from the exact retained
bytes for APT integrity; they are not an expected upstream release checksum. A
per-host signing-only key is generated under the root-only
`repository-signing/` directory, the public key is exported to
`/etc/apt/keyrings/managed-external-software.gpg`, and each rebuilt `Release`
is published with both `InRelease` and `Release.gpg` signatures. The source is
restricted to that key with `Signed-By`, so those managed packages can be
repaired offline with the explicit `--repair-only` action without disabling
APT authentication. APT indexes and installs the validated local archives, but
the automatic update cadence is owned by the two managed timers: the download
timer fetches and retains validated vendor releases, and the later apply timer
invokes the managed updater to install the selected retained archive. This is
not an unrestricted vendor repository and does not delegate release selection
to `apt-daily` or unattended-upgrades. The software class installs `gpgv`
explicitly so both signatures are verified after every rebuild instead of
relying on APT's package dependencies to provide that executable. Discord
retains its stable manifest plus digest-named
host and module `full.distro` files below `artifacts/discord`; its installed and
pending release records live in `state/`, allowing the same repair action to
rebuild `/opt/discord` without network access. Postman is validated as a
bounded tarball with an allowlisted layout; Ledger and Tuta remain signed,
bounded AppImage paths. Obsidian and Sleek resolve the official latest stable
GitHub release metadata, require one version-matched amd64 Debian asset, and
verify the declared SHA-256 digest and size before staging. The apply action
rejects downgrades and same-version digest substitution, revalidates retained
packages or binaries, and atomically replaces only newer versions.

Update lifecycle events are written to a root-owned queue and delivered by
class-scoped systemd user units copied from
`/etc/skel/.config/systemd/user/` into the desktop account's
`$HOME/.config/systemd/user/`. Those per-account units deliver through
`notify-send` to Mako, including checks, downloaded releases, active applies,
successful updates, failures, and the final summary. Events created while no
Labwc session is active are replayed the next time that user's
`labwc-session.target` starts; no managed-software notification unit is
globally enabled under `/etc/systemd/user/`.

`ssh.cfg` installs the target OpenSSH server package and enables the
shared late-command SSH configuration/key staging path when selected as
`classes=...,ssh`.

`wifi.cfg` is now only a compatibility marker that keeps Wi-Fi firmware loading
explicit without forcing d-i to associate to Wi-Fi during installation. Static
installs prepare the target's deterministic Wi-Fi handoff automatically from
the cmdline-driven static network contract instead.

`tailscale.cfg` installs Tailscale and Syncthing when selected as
`classes=...,tailscale`; its late helper stages the managed Tailscale SSH
bootstrap, Syncthing service/config path, profile-owned Tailscale
tag/route/approval knobs, and the Tailscale-only firewall posture for
Tailscale SSH and Syncthing endpoints. The profile-owned
`TAILSCALE_NETFILTER_MODE=off` delegates packet filtering to the managed
nftables policy: selecting the addon automatically adds the Tailscale transport
and Syncthing overlays, and both `tailscaled.service` and the bounded bootstrap
unit require `nftables.service`. The transport overlay permits the configured
UDP listen port, control-plane HTTP/HTTPS fallback, STUN, and direct UDP
traffic; Tailscale SSH and Syncthing remain restricted to the managed
`tailscale0` interface and tailnet address ranges. Successful bootstrap removes
the staged auth key and queues cleanup, while transient daemon/control-plane
failures retry on systemd-spaced ceilings rather than a tight loop. The addon
does not install or configure `openssh-server`; select `classes=...,ssh`
separately when you explicitly want the conventional OpenSSH daemon alongside
Tailscale.

`devops.cfg` installs an AMD64 desktop development toolchain when selected as
`classes=...,desktop,...,devops`. It enables the upstream `mise` archive and
Cloudflare's official `cloudflared` APT archive without selecting a package
from the latter. Commented `apt-setup/local*` examples retain the official
OpenTofu, HashiCorp Terraform/Packer, Aptly release, and Aptly CI repositories
without activating them during unattended installation. The class installs
the LLVM 24 package family plus `sccache` and Mold, downloads verified
Node 22, 24, and 26 runtime archives into `/usr/local/lib`, enables their
Corepack package-manager shims, and links those system-owned trees into
account-scoped Mise state. It also installs the profile-pinned Deno 2.9.6
archive as `/usr/local/lib/deno/bin/deno` and the official yt-dlp 2026.08.19
Linux AMD64 standalone executable as the private
`/usr/local/lib/yt-dlp/libexec/yt-dlp` payload. The root-owned
`/usr/local/lib/yt-dlp/bin/yt-dlp` wrapper uses only the managed Deno binary,
the official executable's bundled yt-dlp-ejs component, and Debian's
`/usr/bin/ffmpeg`/`ffprobe`; remote EJS component downloads remain disabled.
The class therefore selects the Debian `ffmpeg` package explicitly, and the
installer rejects Deno releases older than yt-dlp-ejs's supported 2.3 minimum.
The late helper also downloads the profile-selected
Rustup bootstrap from its versioned official archive into
`/usr/local/lib/rustup/bin`, requiring the profile's exact byte count and
SHA-256 before execution. It then initializes the account-scoped Rust toolchain
to the profile-selected channel without modifying shell startup files. Once
Rustup is initialized, the late helper runs `rustup component add rustfmt`.
Each desktop profile independently selects
`DEVOPS_DOTSLASH_SOURCE_BUILD=0|1` and `DEVOPS_UV_SOURCE_BUILD=0|1`. A value of
`1` preserves the locked Cargo source build for the profile-selected DotSlash
repository commit or exact uv crates.io version. A value of `0` instead uses a
least-privilege account helper to download the profile-pinned official release
tarball, require its exact byte count and SHA-256, reject links, devices,
duplicate or non-normalized paths, unexpected members, and extraction-limit
violations, and atomically publish `dotslash`, `uv`, and `uvx` into the same
pool-backed `CARGO_INSTALL_ROOT/bin`. The opt-in profile directly exports
`RUSTUP_TOOLCHAIN=nightly` as its current default; no separate
`/etc/devops/toolchain.conf` indirection is rendered. The profile-owned
`DEVOPS_RUSTUP_TOOLCHAIN` installer value is not restricted to `nightly` by the
late helper, so another Rustup-supported toolchain can be selected without a
code-side channel allowlist. Change both managed defaults when the installed
initial toolchain and the opt-in shell default should move together.
Mise is intentionally **Node-only**:
LLVM 24 is installed through `pkgsel/include` and exposed directly from
`/usr/lib/llvm-24/bin`, rather than being resolved through Mise. The managed
Mise configuration selects linked Node 26 as the account-wide fallback.
Mise's standard pool-backed shim directory precedes
`/usr/local/lib/node-26/bin` in `PATH`, so a project-local
`mise use node@22`, `mise use node@24`, or `mise use node@26` selection takes
precedence while Node 26 remains the fallback when no Mise shim is available.
The same opt-in shell keeps Python bytecode outside source worktrees by setting
`PYTHONPYCACHEPREFIX` below the authenticated mode-`0700`
`$XDG_RUNTIME_DIR` (`/run/user/$UID` in the managed desktop session). Python
also starts with `PYTHONSAFEPATH=1` and default-encoding warnings enabled, so it
does not prepend an unsafe current or script directory to `sys.path` and warns
when locale-dependent text encoding is used. Before constructing that managed
state, the profile clears inherited Python home/search/startup, bytecode,
inspection, optimization, hash-seed, and warning controls plus stale virtual
environment markers, preventing caller state from overriding the policy.
Python user installs and interactive history plus pip and uv caches remain
separated under the account's `/pool/build`, `/pool/db`, and `/pool/cache`
roots, so only disposable bytecode state is lost when the user runtime
directory is removed.
The managed
Cargo policy is rendered from the tracked
`hooks/role/desktop/target/etc/skel/.config/cargo/config.toml.tmpl` into
`/etc/skel/.config/cargo/config.toml` using the selected desktop profile. It is
also rendered into the account's pool-backed `CARGO_HOME` during the late
command and invokes Mold through the packaged `clang-24` linker while retaining
`sccache` as Cargo's Rust compiler wrapper. Each concrete desktop profile owns
the bounded Cargo job count and Rust target CPU; the late helper rejects a
target CPU that the installed Rust toolchain does not advertise.

Every one of the 13 concrete desktop profiles carries one byte-identical
managed upstream DevOps policy block. That block owns the Node and Rustup
versions, URLs, exact byte counts, digests, archive names and roots, install
roots, the DotSlash and uv source-build switches, DotSlash repository revision,
and the pinned DotSlash and uv binary-release metadata, plus Deno and yt-dlp
release metadata and all release metadata for Ansible Core, OpenTofu,
Terraform, Packer, Wrangler, Aptly, osc, and obs-build. The shell and Python
executors contain validation allowlists and extraction rules, but no selected
release URL, version, tag, commit, or digest.

After Node 26 is available, one installer-only Python helper downloads and
validates Deno 2.9.6, yt-dlp 2026.08.19 with bundled yt-dlp-ejs, Ansible Core
2.21.3, OpenTofu 1.12.6, Terraform 1.16.0, Packer 1.16.0,
Wrangler 4.127.0, Aptly 1.6.3, osc 1.27.3, and the active obs-build `20260721`
tag pinned to commit
`16992842b3391ecd74d43842fa13f1a81a938ff8`. OpenTofu and Aptly come from their
official Linux AMD64 release ZIPs; Terraform and Packer come from HashiCorp's
official Linux AMD64 release ZIPs; Ansible Core and osc come from their
upstream PyPI wheels; Wrangler comes from the npm registry and is
installed with the managed Node 26 npm; Deno comes from its official single-
binary release ZIP; yt-dlp comes from its official standalone executable; and
obs-build comes from its exact upstream commit archive using the upstream
Makefile. The checksum-pinned `ansible-core` wheel is extracted directly into
its isolated root without invoking `pip`. It provides the normal `ansible`,
`ansible-config`, `ansible-console`, `ansible-doc`, `ansible-galaxy`,
`ansible-inventory`, `ansible-playbook`, `ansible-pull`, `ansible-test`, and
`ansible-vault` commands. `ansible-core` is the upstream Python distribution
name, not a separate command. The full PyPI `ansible` community-distribution
wheel and the generated `ansible-community` wrapper are deliberately not
downloaded or installed.
Exact byte counts and SHA-256 or npm SHA-512 integrity are checked before any
extraction. ZIP, wheel, npm-package, and tar members are bounded and rejected
for traversal, duplicate, escaping-link, special-file, or expanded-size
violations. The helper prepares all ten root-owned trees before publishing
them under `/usr/local/lib/deno`, `/usr/local/lib/yt-dlp`,
`/usr/local/lib/ansible`, `/usr/local/lib/opentufo`,
`/usr/local/lib/hashicorp/terraform`, `/usr/local/lib/hashicorp/packer`,
`/usr/local/lib/wrangler`, `/usr/local/lib/aptly`, `/usr/local/lib/osc`, and
`/usr/local/lib/obs-build`; a failed final verification removes the complete
published set. The tracked Packer template pins the Amazon, Ansible, Azure,
Docker, Google Compute, Proxmox, and QEMU plugins and the late helper runs
`packer init .` with plugin state confined to
`/pool/cache/$USER/hashicorp/packer.d/plugins`. obs-build remains the actively
maintained standalone/OBS build script suite; it complements rather than
replaces the osc service client.

The class installs only the explicit system dependencies for those upstream
tools, including `ffmpeg`/`ffprobe`, Secret Service support, and the Debian
source/binary package toolchain
for account-local publication; the Debian `ansible`, `terraform`, `packer`,
`aptly`, `osc`, and `obs-build` packages are deliberately absent from
`pkgsel/include`. The
repository-only placeholder sources live below
`scripts/late/templates/devops/`, outside every tracked `hooks/**/target/**`
runtime mirror. The late helper fetches those sources and renders only the
final account-owned mode-`0600` files
`/pool/db/$USER/aptly/aptly.conf`, `/pool/db/$USER/osc/oscrc`, and
`/pool/db/$USER/osc/managed.json`; it does not
install a placeholder-named path or shared publication-template directory
anywhere below `/pool`. Aptly keeps its database and package pool below
`/pool/db/$USER/aptly`, while osc uses
`/pool/cache/$USER/osc/packages` and `/pool/build/$USER/osc`. Installer
cmdline values `cf_r2_access_key`, `cf_r2_secret_key`, `obs_username`, and
`obs_password` are staged privately and imported on first use into the
KWallet-backed Secret Service. The selected profile's uppercase 40- or
64-character `DEVOPS_APTLY_REPOSITORY_KEY_FINGERPRINT` is the sole expected
OpenPGP fingerprint; no signing-key fingerprint is accepted from the installer
kernel command line. `dpkg-buildpackage` receives the profile fingerprint
through `DEB_SIGN_KEYID` and signs the generated `.dsc`, `.buildinfo`, and
`.changes` metadata. The oscrc contains only options supported by osc 1.27.3:
HTTPS certificate enforcement, bounded HTTP retries, non-debug logging, rooted
checkout behavior, signature verification, account-local cookie/package/build
paths, and disabled automatic local source services. Wrapper-only project,
workspace, repository, and Secret Service metadata lives in the adjacent JSON
file rather than in unknown oscrc keys; neither file stores a username or
password. Before Aptly imports a source package, `aptly-publish-local` verifies
that every supplied `.dsc` has a valid signature from that fingerprint. Every
Aptly publish or switch operation also requires the matching secret key and
passes the fingerprint with `-gpg-key`.

During the DevOps late command, the selected desktop profile's
`DEVOPS_APTLY_GPG_SIGNING_KEY` must name the matching armored private-key file
directly below `/aptly-signing` on `/dev/sda2`. Every desktop profile owns this
setting independently; the managed default is
`/aptly-signing/aptly-jcramer.xyz-gpg.asc`, but a profile may select another
safe filename in the same directory. The helper allocates a private installer
mountpoint and mounts that exact block device with effective
`ro,nosuid,nodev,noexec` options. It rejects paths outside the fixed directory,
nested paths, symlinked source components, non-regular input, an unexpected
armor header, and input larger than 1 MiB. Before import, GnuPG must report
exactly one primary secret key, no additional primary public or secret key,
and the same fingerprint as the selected profile's validated
`DEVOPS_APTLY_REPOSITORY_KEY_FINGERPRINT`, plus signing capability on a primary
or secret subkey record. The key is then imported as the primary account into
its default account-owned mode-`0700` `$HOME/.gnupg`. After import, GnuPG must
list the same fingerprint and at least one locally available, signing-capable
secret record; public-only, token-reference-only, and stub-only material is
rejected. The helper unmounts the medium before invoking target GnuPG and
removes its random mode-`0600` transient copy on success, failure, or
interruption; no armored source copy is retained in the installed system. A
missing device, missing file, fingerprint mismatch, unsafe path, import
failure, cleanup failure, or unavailable signing-capable secret key aborts
`addon/devops` provisioning instead of leaving publication partly configured.

The managed R2 endpoint is
`https://79cc1f5f831fb7f414638c3e758e9710.r2.cloudflarestorage.com`, bucket
`cf-aptly-r2-prod`, with the internal object prefix `debian/`. The deployed
Worker strips that prefix, so clients use `https://apt.jcramer.xyz/dists/...`
and `https://apt.jcramer.xyz/pool/...`, not a public `/debian` path. Local
repositories `local-stable` and `local-testing` publish signed `main` metadata
with `amd64` and `source` architectures through `s3:r2:`. The opt-in DevOps
environment exports `GOPATH=/pool/build/$USER/go` and
`GOMODCACHE=/pool/cache/$USER/go-mod`, with `GOPATH/bin` on `PATH`. It exposes
`aptly` and `aptly-publish-local` through the dedicated `aptly-publishing`
wrapper backed by `/usr/local/lib/aptly/bin/aptly`, and exposes `osc`,
`obs-checkout-source`, and `obs-publish-source` through the separate
`obs-publishing` wrapper backed by `/usr/local/lib/osc/bin/osc`. Both wrappers
reject a missing, writable, linked, or non-root-owned managed executable and
bound every non-exec publication subprocess. OBS credentials stay in Secret
Service and source commits are restricted to `home:cramerz:debian`, whose local
build default is `Debian_Unstable`. Entering the opt-in DevOps shell appends the
ten upstream bin roots only when present; the prepended publication-wrapper
directories continue to win command lookup for `aptly` and `osc`. Ansible
keeps persistent state under `/pool/db/$USER/ansible`, Galaxy downloads under
`/pool/cache/$USER/ansible`, and temporary/control-socket state below the
private `/run/user/$UID/ansible` tree. Terraform provider downloads use
`/pool/cache/$USER/hashicorp/terraform/plugin-cache`; Packer uses its adjacent
cache plus the managed `packer.d` configuration and plugin roots. Bash and Zsh
load Ansible completions and HashiCorp's external completion protocol only
inside the active DevOps shell.

Deno is likewise visible only inside that opt-in shell. `DENO_DIR` points to
`/pool/cache/$USER/deno`, `DENO_INSTALL_ROOT` points to
`/pool/build/$USER/deno`, its account-installed `bin` directory follows the
managed `/usr/local/lib/deno/bin` runtime on `PATH`, and `DENO_REPL_HISTORY`
points to `/pool/db/$USER/deno/repl_history`. `DENO_NO_UPDATE_CHECK=1` keeps the
checksum-pinned system runtime from performing update checks. Deno has no
separate native global configuration-directory variable to redirect; project
configuration remains project-local while the existing managed
`XDG_CONFIG_HOME=$HOME/.config` contract stays unchanged.

When the same `devops` class is selected, the late helper stages a temporary
installer-side release helper into `/target/tmp` and downloads the profile-
pinned `llama-cuda.tar.gz` or `llama-ram.tar.gz` archive. The archive byte count
and SHA-256 must match profile policy before a bounded extractor accepts only
the expected `bin`, `metadata`, and `share` trees. Absolute paths, traversal,
links, devices, duplicate members, unexpected binaries, excessive members, and
payloads above the extracted-byte ceiling are rejected. The member ceiling is
enforced while archive headers are read, before an unbounded member table can
accumulate. Final `bin`, `metadata`, `share`, and release-record publication is
rollback-safe if any move is interrupted or fails. The CUDA release is linked
against CUDA 12.8 and therefore requires the selected
`addon/cuda-legacy` runtime class. Existing DevOps and CUDA compiler packages,
including `nvcc`, remain installed and available; they are no longer invoked
to build llama during the unattended installation. Both Llama releases are
x86-64 executables, matching the existing `addon/devops` dependency on
`arch/amd64`.

All five release executables (`llama-bench`, `llama-cli`, `llama-gguf-split`,
`llama-quantize`, and `llama-server`) are installed in `/data/llama/bin`.
Release provenance is retained under `/data/llama/metadata`, and the packaged
UI tree is retained under `/data/llama/share`. The selected GGUF remains in
`/pool/cache/llama/models`, while
the tracked `/data/llama/lib/llama` launcher parses strict root-managed runtime
defaults from `/etc/llama/llama.conf` and supplies the corresponding
`LLAMA_ARG_*` values without sourcing the configuration as shell code.
Entering the opt-in `[devops]` terminal shell adds `/data/llama/lib` and
`/data/llama/bin` to `PATH`, plus whichever of the CUDA 13.1, 12.9, and 12.8
toolkit bin directories exist. The title is restored at every managed Zsh
prompt and before each command.
`llama` defaults to `llama-cli`, while the managed desktop account receives
an on-demand `llama-server.service`. The Computer Management launcher starts
or stops that unit explicitly; the service resolves the launcher-selected
model and bounded runtime overrides, and the root-managed wrapper fixes the
server to `127.0.0.1` and the profile-configured port.

The same class installs the profile-pinned managed Codex
`x86_64-unknown-linux-gnu` release archive. The desktop profiles own the
release version, tag, URL, SHA-256 digest, archive layout names, and broad
compressed and extracted byte ceilings. A dedicated installer-only Python
helper rejects duplicate, absolute, traversing, non-normalized, sparse, PAX,
linked, device, or FIFO archive members and never calls blanket extraction.
It ignores other safe archive metadata while it dynamically stream-copies
every direct regular file below the profile-owned archive `bin/` directory,
so a rebuilt checksum-pinned release may add or remove sibling executables
without changing installer code. Those files are installed root-owned with
mode `0755` in `/data/codex/share/bin`. The
profile-owned archive-root schema is parsed as UTF-8 JSON and installed
root-owned with mode `0644` as `/data/codex/config.schema.json`. The profile
release identity, checksum, observed compressed size, safety ceilings, archive
binary directory, schema path, and repository revision are recorded in
`/data/codex/.managed-codex-release`.

The class also clones the pinned `mcr/main` revision of
`https://github.com/mjcramerz/codex-home` directly into `/data/codex/usr` and
copies that repository's `etc/` content into `/etc/codex`. The opt-in DevOps
shell adds only `/data/codex/lib` to the host `PATH`, so
`/data/codex/lib/codex` is the single public managed entrypoint. The wrapper
removes its own directory from the payload `PATH` and injects
`/data/codex/share/bin` only inside the managed runtime. Codex can therefore
find any checksum-pinned sibling helpers added by a future release without
requiring a generated wrapper inventory or risking recursive nested
Bubblewrap launches. ChatGPT applies the same PATH split inside its existing
desktop sandbox. AppArmor attaches direct executable children of the release
directory to the managed Codex runtime and explicitly denies writes to the
root-managed schema, release metadata, wrapper, and binary trees. Those
`wkl` deny masks cover only write, hard-link, and lock permissions; they do
not contain `x` and therefore do not block the separately declared wrapper or
release-binary execution rules.

The wrapper's default Bubblewrap runtime uses a separate `slirp4netns` network
namespace, synthetic identity surfaces, a synthetic kernel release bounded
from `6.7.0` through `7.1.5`, a minimal `/dev`, read-only host files, explicit
writable pool/workspace state, and persistent read-write Codex home and SQLite
state. The wrapper uses one deliberate writable bind for the complete managed
home rather than stacking redundant nested binds. That home includes
`sessions`, `shell_snapshots`, `archived_sessions`, `history.jsonl`,
`session_index.jsonl`, and `external_agent_session_imports.json`, so native
`codex resume` and `codex resume --last` can reuse history across Bubblewrap
launches. The native picker retains Codex's normal working-directory filter;
`codex resume --all` exposes the complete managed session history.
Each Bubblewrap launch separately synthesizes a lowercase UUID in a private
mode-`0700` control directory, writes its `installation_id` file with mode
`0644`, and writable-binds that file over
`$CODEX_HOME/installation_id`. The file is removed with the private launch
directory after exit and does not update a persistent host-side installation
ID. The managed ChatGPT/Codex desktop app uses the same writable per-launch
synthetic-ID and persistent Codex runtime contract.
Before either standalone Codex or the managed ChatGPT/Codex application starts,
its launcher validates the account-owned
`$HOME/.profile.d/71-devops-de.sh` and applies its deterministic noninteractive
DevOps environment. Standalone Codex compares the complete exported environment
against an independently clean activation before passing those exports into
Bubblewrap. The ChatGPT launcher activates the profile inside a clean
environment, and the managed-app runtime validates bounded variable names and
safe absolute PATH entries before copying the complete profile-owned export set.
Neither launcher duplicates a CUDA, LLVM, Node, Rust, Mise, Python, or other
development-tool inventory. Both sandboxes advertise `/bin/zsh` for their
synthetic developer account and
keep the installed `/usr`, `/usr/local`, and `/opt` development toolchains
read-only and bind the real `$HOME/Downloads`, `$HOME/Workspace`, `/pool`,
`/data/codex`, and `/data/downloads` read/write. Normal Unix ownership and mode
checks still apply inside those mounts. Other home paths remain hidden except
for the selected read-only development configuration and managed application
state, while other `/data` paths remain read-only. Root-managed Codex binaries,
release metadata, repository configuration, and the memories Git guard remain
protected. Both sandboxes preserve physical working directories below the
writable roots; standalone Codex rejects `/data/codex/runtime` because that
control-state subtree remains masked inside its sandbox.

The HOME access contract is deliberately path-specific. The authoritative
standalone-Codex arrays
`DEVOPS_READ_ONLY_HOME_DIRECTORIES` and
`DEVOPS_READ_ONLY_HOME_FILES` are byte-for-byte synchronized with
`CHATGPT_DEVOPS_READ_ONLY_HOME_DIRECTORIES` and
`CHATGPT_DEVOPS_READ_ONLY_HOME_FILES`. Read-only directory trees cover the
CMake user package registry at `$HOME/.cmake/packages`, VS Code snippets,
Bazel, Clangd, direnv, FeatherPad, FZF, Git, Micro, Mise, Nano, Neovim, pip,
PowerShell, RetroArch, Satty, Sleek, Taskwarrior, Vim, virt-manager, Yamllint,
`$HOME/.local/bin`, `$HOME/.local/lib`, and PowerShell user modules. File-level
binds cover VS Code settings and keybindings, Cargo's
`$HOME/.config/cargo/config.toml`, the non-secret Containers configuration
files, GitHub CLI `config.yml`, Go's `env`, libvirt client files, the Obsidian
registry, Starship, uv, MIME and XDG terminal/user-directory files, the managed
Vagrantfile, Recoll configuration, editor/linter configuration, and the safe
Bash and Zsh startup files including `.bash_logout` and `.zlogin`. Missing
optional paths are skipped.

Credential-bearing or unnecessarily broad state remains outside both
sandboxes: no `$HOME/.ssh`, `$HOME/.gnupg`, shell histories, `.npmrc`,
`.git-credentials`, Containers `auth.json`, broad `$HOME/.cache`, or
credential-capable Age, npm, sccache, or SOPS configuration is mounted.
ChatGPT persists only its application-owned `$HOME/.cache/Codex` subtree. The
package's `/usr/bin/pwsh` entrypoint and
`/opt/microsoft/powershell/7` payload remain available through the read-only
system toolchain mounts.
The wrapper explicitly preserves the invoking terminal descriptors while
Bubblewrap waits for isolated-network setup, so interactive Codex never
inherits Bash's asynchronous-command `/dev/null` stdin fallback.
The Bash wrapper starts in privileged parsing mode so an ambient `BASH_ENV`
cannot execute before its policy, and the sandbox drops inherited Bash,
dynamic-loader, and Python startup-injection variables before the Codex
payload starts.
The class-gated `/etc/tmpfiles.d/80-codex-storage.conf` policy persists the
ownership contract. `/data/codex` is a root-owned, group-`devops`, sticky
setgid directory at mode `3770`, so members can create work entries without
being able to replace root-owned top-level artifacts through parent-directory
rename or unlink operations. `/data/codex/usr` remains owned by the managed
desktop account with group `devops` at mode `0750`; its home and memories roots
are mode `2770`. The same account owns `/data/codex/log`,
`/data/codex/sqlite`, and `/data/codex/runtime` with group `devops` at mode
`2770`; the private `/data/codex/runtime/.control` subtree remains mode `0700`.
In normal Bubblewrap mode, standalone Codex overlays the desktop-account-owned,
group-`devops` `/var/log/managed/openai/codex` directory onto
`/data/codex/log`. Its root-owned, non-writable parent protects the managed
directory name from replacement. The account-owned `/data/codex/log` path
remains the explicit `--no-bwrap` fallback. The late helper directly installs
and verifies `/data/codex/share`,
`/data/codex/share/bin`, the raw executable, `/data/codex/lib`, and the wrapper
as `root:root` mode `0755`. The cloned repository's `/data/codex/usr/etc`
subtree is also normalized to `root:root`; its validated contents are copied
into the root-owned `/etc/codex` system configuration tree. Codex and ChatGPT
payload AppArmor policy denies write, link, and lock operations against those
root-managed release, executable, and repository-configuration paths. The late
helper also installs the memories `.git` pathname guard as a root-owned
mode-`0444` empty regular file with the immutable inode attribute. Read
permission lets the unprivileged wrapper inspect the inode flags; root
ownership, absent write bits, and immutability keep the pathname blocked
against modification or removal.
The wrapper treats any missing, indirect, or malformed guard as a fatal
deployment error and never deletes or recreates suspicious guard state.
The wrapper no longer intercepts or rewrites `resume` arguments; session
selection remains native Codex behavior over the persistent runtime state. The
`--no-bwrap` wrapper flag is an explicit isolation bypass and is removed before
the raw executable is invoked. Because every desktop exposes a selectable
Hardened boot profile that otherwise disables unprivileged user namespaces,
the DevOps class also installs `/etc/sysctl.d/90-codex-bwrap.conf`. That
class-gated override keeps Bubblewrap available with a bounded
`user.max_user_namespaces=1024`; selecting DevOps therefore intentionally
overrides the Hardened profile's user-namespace prohibition. When
`addon/podman` is selected too, its later rootless-runtime policy retains the
larger namespace ceiling required by Podman.

The same `addon/devops` selection installs the managed ChatGPT/Codex desktop
package through the signed local repository and exposes only its dedicated
native-Wayland launcher. Its Bubblewrap runtime replaces the rest of the
desktop account's home with a private tmpfs, then bind-mounts the real
`$HOME/Downloads` and `$HOME/Workspace` directories back at their identical
paths with `--bind`. Launch fails closed unless both directories are direct,
desktop-user-owned mode-`0755` directories that remain readable, searchable,
and writable. The dedicated parent and Bubblewrap-child AppArmor profiles both
grant the desktop account read/write/create/lock access below those two roots;
the child additionally permits executing project tools there without granting
the shared managed-application profile equivalent write access. The same
dedicated sandbox bind-mounts `/pool`, `/data/codex`, and `/data/downloads`
read/write after validating their fresh-install ownership and modes, then
overlays the desktop-account-owned, group-`openailogger`
`/var/log/managed/openai/chatgpt/runtime` directory onto its internal
`/data/codex/log`. The root-owned, non-writable
`/var/log/managed/openai/chatgpt` parent keeps the final rsyslog output from
being renamed or removed by the desktop account. Standalone Codex and ChatGPT
retain the same managed data roots without exposing the standalone wrapper on
ChatGPT's internal `PATH`. The launcher preserves a physical working directory
below any writable root and otherwise falls back to `$HOME/Workspace`. It
exposes the root-owned `/data/llama` runtime and all `/usr` toolchains,
including LLVM 24, the managed Node runtimes, Rustup, Mise, and Bazelisk,
read-only. Session D-Bus is filtered to the portal, notification, and Secret
Service names, the system bus is filtered to UPower, and audio is carried only
through the account's PipeWire and Pulse sockets; `/dev/snd` is never
bind-mounted.

The outer launcher detaches standard input, output, and error before any
validation, so neither launcher diagnostics nor application output can inherit
a calling terminal, compositor console, or generic session logger. After the
private DevOps environment is validated, the dedicated capture runner starts
`labwc-managed-app` in a new session and captures both output streams from it,
Bubblewrap, Electron, and inheriting Codex helpers. Records are converted to
bounded safe-ASCII chunks and sent through the private
`/run/rsyslog/managed-openai/chatgpt.sock` datagram socket. The application
tree is explicitly denied the host's generic syslog and systemd-journal
sockets, the private ChatGPT socket, the standalone-Codex host log directory,
and the protected rsyslog output file. The application-writable
`/var/log/managed/openai/chatgpt/runtime` directory is exposed only at the
sandbox's `/data/codex/log`; rsyslog remains the only writer to
`/var/log/managed/openai/chatgpt/chatgpt.log`, which is owned by `root:adm`
with mode `0640`. The private ruleset stops every socket record from falling
through to general system or console logging and rate-limits the input to 4,000
records per 60 seconds. Launch fails closed without starting the application
when the socket is unavailable. Rotation is daily, keeps four archives, removes
archives older than seven days, and rotates early at 4 MiB.

Before every launch, `/usr/local/bin/chatgpt` privately sources
`$HOME/.profile.d/71-devops-de.sh`, calls its noninteractive environment
function inside a clean POSIX-shell environment, requires its active marker,
and passes every bounded, safe profile export into Bubblewrap without a second
tool-specific variable or PATH list. The sandbox's synthetic account and
`SHELL` both select `/bin/zsh`. This private
activation does not modify the terminal that started the desktop application.
Each launch receives a stable ChatGPT-specific synthetic machine ID, boot ID,
hostname, and Codex installation ID derived one-way from the installed host
identity and desktop UID. The stable values do not expose the host identifiers,
but they let Chromium recognize its own persistent profile after a failed
launch. A private per-account runtime temp directory carries Chromium's
singleton socket across Bubblewrap launches; concurrent ChatGPT launches
therefore hand off to the live process. A separate lifecycle lock permits
removing only current-user-owned stale `SingletonCookie`, `SingletonLock`, and
`SingletonSocket` symlinks when no managed ChatGPT launcher remains alive.
The account database, resolver view, kernel command line, and selected
proc/sysfs masks remain synthetic. The sandbox still shares the host network
namespace so the application can operate normally, and Intel/NVIDIA
acceleration necessarily exposes the selected GPU devices and some associated
PCI/driver identity. These documented limits mean the synthetic identity is
host-metadata minimization, not network anonymity or complete hardware
anonymity.

The vendor package is prevented from creating its own APT source or key. Its
package-owned `/etc/apparmor.d/chatgpt` file is locally diverted to
`/var/lib/software/vendor/chatgpt.apparmor`; the repository-managed restrictive
profile is restored and syntax-validated without touching the installer kernel
during installation. Post-boot updates, same-version policy repair, and offline
repair perform the live reload only when the running system exposes AppArmor's
security interface; a failed available-interface reload fails the operation.
Direct execution of `/usr/bin/chatgpt`, the package launchers, the Electron
binary, and the embedded Codex helpers therefore fails closed. The managed
`/usr/local/bin/chatgpt` command and desktop entry both enter the dedicated
ChatGPT Bubblewrap child profile, while standalone `/data/codex/lib/codex`
keeps its separate per-launch runtime and can run concurrently.

The managed `devops` shell command is opt-in. Login only defines its toggle
functions; it does not prepend DevOps paths or export DevOps variables.
Running `devops` starts a nested interactive Bash or Zsh in the same terminal
and working directory. Environment construction and the nested shell run in a
subshell, so activation failures and changes made inside the DevOps shell do
not mutate the ordinary parent shell. No temporary handoff file, polling loop,
background launcher, or graphical desktop session is required. The terminal's
existing title is pushed before `[devops]` is applied and restored when the
nested shell ends. Running `devops` again inside that shell prints
`DevOps environment deactivated` and returns to the ordinary shell; `exit` or
end-of-file does the same without the message. Normal shell job-control rules
remain in force, so stopped jobs can make an exit be refused. In particular,
merely sourcing the profile does not add either
`/pool/db/<account>/mise/data/shims` or `/usr/local/lib/node-26/bin` to a
normal terminal's `PATH`. Those paths are added only inside the opt-in DevOps
nested shell or the private ChatGPT launch environment; Mise shims remain
before the Node 26 fallback so project and shell selections win.

Every concrete desktop profile also pins Bazelisk 1.29.0's HTTPS release URL,
SHA-256, byte bounds, `/usr/local/lib/bazelisk/bazel` install path, and
cache-retention policy. The selected `addon/devops` late helper downloads and
verifies that binary directly during installation, without shipping a
target-side installer script. Bazelisk is not configured through Mise and its
raw install directory is not added to the normal terminal `PATH`. The
account-local DevOps profile defines `bazel()` to invoke the pinned binary with
`$HOME/.config/bazel/bazelrc`. The Codex sandboxes use their existing
read-only `/usr` view and selected development-configuration binds, so command
shells can load that same profile helper without adding Bazel-specific logic to
the managed GUI application framework or creating a host-wide executable.
Bazel's disk cache and repository cache resolve to
`/pool/cache/<account>/bazel/{disk,repository}`, its output-user root is under
`/pool/build/<account>/bazel`, and Bazelisk's state is under
`/pool/db/<account>/bazelisk`. The rc uses Bazel's native disk/action-cache GC
settings and repository-cache hardlinks; users tune their selected profile's
`DEVOPS_BAZEL_*` values rather than editing generated user state.
Node 26 is the default linked runtime. Developers override it per project with
commands such as `mise use node@22`, `mise use node@24`, or
`mise use node@26`; LLVM 24 and Bazelisk need no Mise configuration.

`qemu.cfg` installs the desktop virtualization baseline when selected as
`classes=...,qemu`; its late helper stages the managed `/pool/libvirt`,
`/pool/incus`, `/pool/lxc`, and `/pool/vagrant` layout, a reconciled
classic-LXC system config, the `virt-host-managed` post-boot service, a
session-default libvirt client configuration for the primary desktop account,
and a managed nftables guest-network overlay for the libvirt and Incus
bridges. The package contract is Debian's split-driver `libvirtd` stack:
`libvirt-daemon`, `libvirt-daemon-common`, the explicit network, node-device,
nwfilter, QEMU, secret, and storage driver packages, `libvirt-daemon-log`,
`libvirt-daemon-lock`, and `libvirt-daemon-plugin-lockd`.
`libvirt-daemon-system` is deliberately absent. `libvirt-daemon` supplies
`/usr/sbin/libvirtd` and the package-owned `libvirtd.service`; the selected
driver packages supply the `libvirt_driver_*.so` modules loaded by that daemon,
and the log and lock packages supply `/usr/sbin/virtlogd` and
`/usr/sbin/virtlockd`. The late helper verifies every selected package, all
three executables, and the required network, node-device, nwfilter, QEMU,
secret, and storage driver modules before it stages policy.

The package-owned system `libvirtd.service` provides the selected drivers
through `qemu:///system`. Root-owned
`/etc/systemd/system/virt-host-managed.service` starts after it and uses that
URI to define and reconcile the dedicated `virtops` NAT network on
`virbr-virtops`; it rejects the package-owned `default`/`virbr0` pair and
collisions with `lxcbr0`, `incusbr0`, or the managed Tailscale interface. The
managed workflow does not create a system storage pool or system-owned guests.
Drop-ins under
`/etc/systemd/system/{libvirtd,virtlogd,virtlockd}.service.d/` keep the
package-owned daemons on journal-only output with stable identifiers. The
`libvirtd` drop-in requires `virtlockd.socket` and orders after
`virtlockd.service`, while system `virtlogd` rotates at 2 MiB before Debian's
package fallback threshold.

The account services are the static, non-enabled
`managed-libvirt-runtime.service`, `managed-virtlogd.service`,
`managed-virtlockd.service`,
`libvirt-session.service`, and `virt-session-storage.service` units under
`/etc/systemd/user/`. They are root-owned central policy, rendered with
`ConditionUser=<account>`, and intentionally not copied from
`/etc/skel/.config/systemd/user/`; that skeleton path is reserved for mutable
account-owned Labwc units. The administrator-controlled user units have no
`[Install]` section or login-time enablement link. Account-specific libvirt
configuration is separately copied from `/etc/skel/.config/libvirt/`. All
ordinary clients keep `LIBVIRT_AUTOSTART=0`.
`managed-libvirt-runtime.service` is the sole
`$XDG_RUNTIME_DIR/libvirt` owner (`RuntimeDirectory=libvirt`, mode `0700`).
The log, lock, and session daemons require it, so the runtime directory remains
while any dependent is active and no sibling needs
`RuntimeDirectoryPreserve=yes`.

Entering the dedicated interactive `virtops` shell or opening the managed
Virtual Machine Manager launcher explicitly starts the persistent user
runtime owner, `virtlogd`, `virtlockd`, and `libvirtd` chain, followed by
`virt-session-storage.service`. That oneshot requires
`libvirt-session.service`, consumes the rendered
`/etc/libvirt/managed/session-default-pool.xml`, and creates or verifies only
the session-scoped `default` pool at
`/pool/libvirt/session/<account>/images` through `qemu:///session`. Legacy
libvirtd mode exposes one account-owned socket at
`$XDG_RUNTIME_DIR/libvirt/libvirt-sock`. The private image directory remains
account-owned mode `0700`.

Vagrant stores its own home at `/pool/vagrant/<account>/home`, sets both its
normal and `system_uri` provider settings to `qemu:///session`, and uses the
`default` session pool. The account receives only the `kvm`, `incus`, and
`incus-admin` groups; it is intentionally not added to `libvirt`. The account's
session-specific `$HOME/.config/libvirt/libvirt.conf` selects
`remote_mode = "legacy"`, while its `qemu.conf` disables only the unprivileged
daemon's dynamic sVirt security driver and explicitly uses `virtlogd` plus the
`virtlockd` plugin. Managed daemon units send standard output and error only to
journald, never to a console; rsyslog routes the `managed-libvirt-runtime`,
`virt-session-storage`, `libvirtd`, `virtlogd`, `virtlockd`, and
`virt-host-managed` identifiers to
`/var/log/managed/libvirt/daemons.log` and marks those records as handled before
generic facility or emergency-wall rules. The logrotate policy checks that
file daily, retains four rotations for at most seven days, and rotates at
16 MiB.
Session guest logs live below
`/var/log/managed/libvirt/<account>/cache/libvirt/qemu/log`; the user
`virtlogd` cleaner root is the parent `.../cache/libvirt/qemu`, matching its
one-level traversal and enforcing bounded size, backup-count, and age retention
on the actual QEMU log directory.

`72-virt-vagrant.sh` validates the account identity, runtime directory,
session configuration, Vagrant home, and image directory before it exports
`VAGRANT_DEFAULT_PROVIDER=libvirt` and
`LIBVIRT_DEFAULT_URI=qemu:///session` into a nested `virtops` shell in the
caller's current terminal and working directory. `virtops` uses no activation
marker; exiting the nested shell returns to the caller. Ordinary login shells and the `devops` shell
keep `LIBVIRT_AUTOSTART=0`, so an unmanaged client cannot create a persistent
session as a side effect.
`/usr/local/bin/virt-manager-virtops` validates and sources the same managed
DevOps and virtualization profiles, starts the same ordered user services,
verifies `qemu:///session`, and runs `/usr/bin/virt-manager` with an explicit
session connection. The compiled virt-manager GSettings defaults register and
autoconnect only `qemu:///session` and set the default image chooser to the
managed session directory. The managed desktop entry disables D-Bus activation
so package launcher shortcuts cannot bypass that preparation. Desktop
application sandboxes receive only the account-owned
`$XDG_RUNTIME_DIR/libvirt/libvirt-sock`; the privileged
`/run/libvirt/libvirt-sock` remains unavailable.
Their sandboxes expose the installed `/usr` and `/opt` toolchains plus
read-only `/data`, `/pool`, package metadata, and GPU-relevant sysfs. Existing
Codex, build, cache, database, workspace, and Vagrant-home paths retain their
explicit writable overlays. DRM, KFD, accelerator, and selected NVIDIA device
nodes are admitted only when present, while DMI, network, storage, firmware,
machine-ID, hostname, account, and boot-ID identity surfaces remain masked.

The addon also stages the official Zabbly Incus repository with target pinning
for `incus-ui-canonical`. Zabbly does not currently publish a `forky` suite
under `incus/stable/dists/`; the addon therefore uses the published `trixie`
suite for `vagrant`, `vagrant-libvirt`, and the Incus UI package while the rest
of the Incus stack continues to come from Debian.

`whisper.cfg` retains its existing compiler/toolchain and PipeWire package
baseline when selected as `classes=...,whisper`; its manifest now explicitly
requires `arch/amd64` because both release variants contain x86-64 ELF
executables. Its late helper no longer compiles `whisper.cpp`. Instead, it
downloads the profile-pinned
`whisper-cuda.tar.gz` or `whisper-ram.tar.gz`, verifies the exact archive byte
count and SHA-256, and safely installs the two allowed release executables
(`whisper-cli` and `whisper-server`) below `/data/whisper/bin` plus their
release metadata below `/data/whisper/metadata`. Its `bin`, `metadata`, and
release-record publication uses the same partial-move rollback contract. The
CUDA release requires the
unchanged `addon/cuda-legacy` CUDA 12.8 runtime/toolchain class. Confined Llama
and Whisper execution may read-map only the required CUDA 12.8 CUDART and
cuBLAS libraries through the shared desktop-graphics abstraction. The selected
GGML model remains independently pinned to an immutable upstream revision and
verified by SHA-256 before publication below `/pool/cache/whisper/models`.

The helper renders the root-managed runtime policy to
`/etc/whisper/whisper.conf` from the tracked
`target/etc/whisper/whisper.conf.tmpl` source. `WHISPER_PERSISTENT_MEM=1` also
stages a session-bound `whisper-server.service` that preloads the model and
accepts only loopback submissions of completed managed WAV files on the
profile-owned `WHISPER_SERVER_PORT=59178`; the dedicated port avoids the
installer-managed CrowdSec and Llama services that use port 8080. The server
unit explicitly keeps `NoNewPrivileges=false` so its `rCx` transitions can
enter the narrower AppArmor HTTP-client and server child domains; the
controller itself retains no network grant. A value of `0` retains direct
one-shot `whisper-cli` transcription. The public `whisper-cli` command
injects the installed model unless the caller selects one explicitly. Labwc
`WIN+R` and the Waybar microphone right-click toggle the same user-owned
capture, restore microphone mute on every stop path, and automatically finalize
after 15 seconds. The helper creates timestamped 16 kHz mono signed-16-bit WAV
and normalized transcript JSON artifacts under the primary account's
`Music/Whisper` directory and appends recognized speech to the managed Sleek
`whisper.txt` todo.txt file.

`podman.cfg` installs the managed rootless Podman / Buildah package baseline
when selected as `classes=...,podman`; the shared late-command Podman module
then provisions the locked `podsvc` service account, managed `/data/config/podman`
config roots, `/pool/podman` state roots, Quadlet defaults, and the
role-specific rootless API socket bootstrap. On desktop installs the staged
`podbin` helper also lets the daily account manage the hardened `podsvc`
runtime through `sudo podbin --service-*` without converting that account into
an interactive login user.

`ch341a.cfg` installs the firmware extraction and CH341A/CH347 workstation
baseline when selected as `classes=...,ch341a`; its late helper stages a
`usbadmin`-scoped udev rule for supported programmers plus `/pool/firmware`
workspace defaults for captures, unpacked images, and scratch work on the main
desktop account instead of assuming a dedicated firmware lab machine. Debian
Forky does not currently publish a `cramfsprogs` package in the configured APT
indexes, so the addon uses `cramfsswap` as the available cramfs-specific
utility while keeping the rest of the requested toolchain intact.

`dualboot.cfg` enables the reused-ESP dual-boot path when selected as
`classes=...,dualboot`. It requires `dualboot_efi=<n>` and
`dualboot_debian=<n>` on the installer kernel command line, installs
`os-prober`, and flips GRUB installer answers to probe other operating systems.
Both the Btrfs/XFS and F2FS storage families now honor that reused-ESP
dual-boot contract; the concrete slot sequence still comes from the selected
storage profile override.

`crypto.cfg` encrypts both `/` and `/home` as separate LUKS2 containers when
selected as `classes=...,crypto`. The class requires UEFI Secure Boot, a usable
TPM2 device, and a storage profile with a dedicated non-zero `/home` partition.
The installer uses the native `partman-crypto` flow for encrypted root and home
filesystem stanzas. Its custom automatic-partition action completes pending
encrypted-volume setup before partman validates `/`, preserving a direct
LUKS-on-filesystem layout without PV, VG, or LV layers. It generates and
reuses a root-only random bootstrap passphrase, creates AES-XTS LUKS2 containers
with a 512-bit XTS key, and seals the first root boot to PCR 7. The late target
helper verifies Secure Boot with `mokutil` and discovers the usable TPM2 device
through `systemd-cryptenroll` after the required target packages are installed.
The target package set includes `systemd-cryptsetup` and `systemd-tpm`.
Persistent configuration is staged from the installed-path mirror sources
`hooks/shared/target/etc/cryptsetup-initramfs/conf-hook`,
`hooks/shared/target/etc/tpm2-cryptroot.conf.tmpl`, and
`hooks/shared/target/usr/local/lib/crypto/config.env.tmpl`. `/etc/crypttab`
remains a deliberate renderer because it must preserve d-i mappings while
merging fresh-install LUKS UUIDs. The late helper materializes the random
bootstrap passphrase in a root-only file for `cryptsetup`, keeps
`initramfs-tools`, writes UUID-based `crypttab` entries without discarding
unrelated mappings, stores a random `/home` unlock key inside the encrypted root
filesystem, and stages the one-time `tpm2-enroll.sh` post-login flow. The TPM2
local-top script is installed ahead of stock
`cryptroot`, embeds `dm_crypt` and the required TPM2 drivers, and preserves
passphrase fallback without prompting before the TPM attempt. `crypttab`
generates the normal `systemd-cryptsetup@crypthome` activation; no unrelated
`systemd-tpm2-setup*` unit is manually enabled. When the installed helper runs,
it interactively prompts the primary user for a recovery passphrase of at least
20 characters and confirmation, then for a TPM2 PIN and confirmation. It
creates the recovery keyslots with explicitly calibrated Argon2id, replaces the
installer token with PCR 7+14 TPM2+PIN tokens, verifies both hardware unlocks,
then removes the temporary bootstrap keyslots and installer-passphrase file.
Interrupted enrollment can be rerun with the same recovery passphrase even if
some temporary keyslots or the installer-passphrase file were already removed.
Root unlock uses the TPM2 token; `/home` uses the root-resident key so normal
boot requests the PIN only once. If TPM, firmware, Secure Boot, or MOK policy
changes, the recovery passphrase still unlocks root and the root-resident key
unlocks `/home`.

`timeshift.cfg` installs Timeshift and enables the managed Btrfs snapshot /
GRUB snapshot-menu integration when selected as `classes=...,timeshift`. The
class is restricted to Btrfs-root storage profiles through
`classes/configs/addons.cfg` `AllowedHardwareClasses`. The managed systemd
timers own snapshot scheduling, so Timeshift's internal cron scheduler remains
disabled. The late hook enforces the Timeshift-compatible `@` root and Btrfs
top-level default, while a Timeshift backup hook queues the managed GRUB
snapshot-menu refresh after both scheduled and GUI snapshots. Snapshot
completion is relayed to an active Labwc user's Mako notification service
through that user's Wayland D-Bus session rather than attempting root-side X11
D-Bus autolaunch.
