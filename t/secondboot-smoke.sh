#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/secondboot-smoke.XXXXXX")
TARGET_ROOT="$TMP_DIR/target"
BLOCKED_ROOT="$TMP_DIR/blocked"
CRYPTO_BLOCKED_ROOT="$TMP_DIR/crypto-blocked"
PENDING_ROOT="$TMP_DIR/pending"
PARTIAL_ROOT="$TMP_DIR/partial"
FAILED_FIRSTBOOT_ROOT="$TMP_DIR/failed-firstboot"
TEST_COUNT=10
TEST_INDEX=0
FAIL_COUNT=0
trap 'rm -rf "$TMP_DIR"' EXIT HUP INT TERM

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

unit_file="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/systemd/system/secondboot.service"
helper_file="$ROOT_DIR/d-i/forky/hooks/shared/target/usr/local/libexec/secondboot-cleanup"
system_profile="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/managed-system-wrappers"
runtime_env="$ROOT_DIR/d-i/forky/hosts/shared/runtime.env"
core_helper="$ROOT_DIR/d-i/forky/scripts/late/core.sh"
firstboot_cleanup="$ROOT_DIR/d-i/forky/scripts/firstboot/05-cleanup.sh"
tailscale_helper="$ROOT_DIR/d-i/forky/hooks/shared/target/usr/local/libexec/tailscale-managed-up"
crowdsec_helper="$ROOT_DIR/d-i/forky/hooks/shared/target/usr/local/libexec/crowdsec-firstboot"
tailscale_unit="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/systemd/system/tailscale-managed-bootstrap.service"
crowdsec_unit="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/systemd/system/crowdsec-firstboot.service"
tpm2_helper="$ROOT_DIR/d-i/forky/hooks/shared/target/usr/local/sbin/tpm2-enroll.sh"
firstboot_run_root="$TMP_DIR/firstboot-run"
secondboot_profile_block=$(
  awk '
    $1 == "profile" && $2 == "managed-secondboot-cleanup" {
      in_profile = 1
    }
    in_profile {
      print
    }
    in_profile && /^}/ {
      exit
    }
  ' "$system_profile"
)

if grep -q '^After=local-fs.target firstboot.service crowdsec-firstboot.service tailscale-managed-bootstrap.service$' "$unit_file" &&
   grep -q '^ConditionPathExists=/var/lib/installer-state/firstboot/complete$' "$unit_file" &&
   grep -q '^ConditionPathExists=/usr/local/libexec/secondboot-cleanup$' "$unit_file" &&
   grep -q '^ExecStart=/usr/local/libexec/secondboot-cleanup$' "$unit_file" &&
   grep -q '^NoNewPrivileges=false$' "$unit_file" &&
   ! grep -q '^NoNewPrivileges=true$' "$unit_file" &&
   ! grep -q '^ProtectKernelModules=true$' "$unit_file" &&
   ! grep -q '^ConditionPathExists=!/usr/local/lib/crypto/tpm2-enroll.pending$' "$unit_file" &&
   grep -q '^\[Install\]$' "$unit_file" &&
   grep -q '^WantedBy=multi-user.target$' "$unit_file" &&
   grep -q '^ConditionPathExists=!/usr/local/lib/tailscale/complete$' "$tailscale_unit" &&
   grep -q '^OnSuccess=secondboot.service$' "$tailscale_unit" &&
   grep -q '^OnSuccess=secondboot.service$' "$crowdsec_unit" &&
   ! grep -q 'secondboot.service' "$tailscale_helper" &&
   ! grep -q 'secondboot.service' "$crowdsec_helper" &&
   grep -q 'systemctl start --no-block secondboot.service' "$tpm2_helper" &&
   printf '%s\n' "$secondboot_profile_block" |
     grep -Fqx '  /usr/sbin/update-initramfs rPx -> managed-update-initramfs,' &&
   grep -q '^profile managed-update-initramfs /usr/sbin/update-initramfs ' "$system_profile" &&
   grep -Fqx '  /usr/sbin/update-initramfs rix,' "$system_profile" &&
   ! printf '%s\n' "$secondboot_profile_block" |
     grep -Eq '^  /(usr/lib/modules|usr/lib/firmware|dev)/.*[[:space:]]rwkl,'; then
  pass "successful bootstrap units queue secondboot cleanup without racing their own oneshot exit"
else
  fail "successful bootstrap units queue secondboot cleanup without racing their own oneshot exit"
fi

if FIRSTBOOT_LOG_DIR="$firstboot_run_root/logs" \
   FIRSTBOOT_DATA_DIR="$firstboot_run_root/logs/data" \
   FIRSTBOOT_STATE_DIR="$firstboot_run_root/state" \
   FIRSTBOOT_LOG_FILE="$firstboot_run_root/logs/firstboot.log" \
   FIRSTBOOT_COMPLETE_FILE="$firstboot_run_root/state/complete" \
   FIRSTBOOT_OVERALL_STATUS=0 \
     /bin/sh "$firstboot_cleanup" &&
   grep -q '^status=0$' "$firstboot_run_root/state/complete" &&
   grep -q '^automatic_cleanup_service=secondboot.service$' "$firstboot_run_root/logs/data/cleanup.txt" &&
   grep -q '^FILE_SECONDBOOT_HELPER=' "$runtime_env" &&
   grep -q '^FILE_SECONDBOOT_SERVICE=' "$runtime_env" &&
   grep -q 'usr/local/libexec/secondboot-cleanup' "$core_helper" &&
   grep -q 'etc/systemd/system/secondboot.service' "$core_helper" &&
   grep -q 'stage_target_systemd_unit_enabled secondboot.service system' "$core_helper" &&
   grep -q 'FIRSTBOOT_OVERALL_STATUS' "$firstboot_cleanup" &&
   grep -q 'automatic_cleanup_service=secondboot.service' "$firstboot_cleanup" &&
   ! grep -q 'enable secondboot.service\\|update-initramfs\\|rm -f /etc/systemd/system/firstboot.service' "$firstboot_cleanup"; then
  pass "firstboot records completion and enables automatic post-enrollment cleanup"
else
  fail "firstboot records completion and enables automatic post-enrollment cleanup"
fi

install -d -m 0755 "$BLOCKED_ROOT/var/lib/installer-state" "$BLOCKED_ROOT/usr/local/lib/tailscale"
printf '%s\n' auth-key >"$BLOCKED_ROOT/usr/local/lib/tailscale/auth.key"
if ! SECONDBOOT_ROOT="$BLOCKED_ROOT" /bin/sh "$helper_file" >/dev/null 2>&1 &&
   [ -s "$BLOCKED_ROOT/usr/local/lib/tailscale/auth.key" ]; then
  pass "secondboot cleanup refuses to run before firstboot completes"
else
  fail "secondboot cleanup refuses to run before firstboot completes"
fi

install -d -m 0755 \
  "$CRYPTO_BLOCKED_ROOT/var/lib/installer-state/firstboot" \
  "$CRYPTO_BLOCKED_ROOT/usr/local/lib/crypto"
touch "$CRYPTO_BLOCKED_ROOT/usr/local/lib/crypto/config.env"
printf '%s\n' status=0 >"$CRYPTO_BLOCKED_ROOT/var/lib/installer-state/firstboot/complete"
touch "$CRYPTO_BLOCKED_ROOT/usr/local/lib/crypto/tpm2-enroll.pending"
if SECONDBOOT_ROOT="$CRYPTO_BLOCKED_ROOT" /bin/sh "$helper_file" >/dev/null 2>&1 &&
   [ -e "$CRYPTO_BLOCKED_ROOT/usr/local/lib/crypto/config.env" ] &&
   [ -e "$CRYPTO_BLOCKED_ROOT/usr/local/lib/crypto/tpm2-enroll.pending" ] &&
   [ -e "$CRYPTO_BLOCKED_ROOT/var/lib/installer-state/firstboot/complete" ]; then
  pass "automatic cleanup defers TPM2 enrollment without removing retained installer-state"
else
  fail "automatic cleanup defers TPM2 enrollment without removing retained installer-state"
fi

install -d -m 0755 \
  "$FAILED_FIRSTBOOT_ROOT/etc/default" \
  "$FAILED_FIRSTBOOT_ROOT/etc/systemd/system" \
  "$FAILED_FIRSTBOOT_ROOT/usr/local/lib/crowdsec" \
  "$FAILED_FIRSTBOOT_ROOT/usr/local/lib/tailscale" \
  "$FAILED_FIRSTBOOT_ROOT/usr/local/libexec" \
  "$FAILED_FIRSTBOOT_ROOT/var/lib/installer-state/firstboot"
printf '%s\n' status=1 >"$FAILED_FIRSTBOOT_ROOT/var/lib/installer-state/firstboot/complete"
: >"$FAILED_FIRSTBOOT_ROOT/etc/default/crowdsec-firstboot"
: >"$FAILED_FIRSTBOOT_ROOT/etc/default/tailscale-managed"
: >"$FAILED_FIRSTBOOT_ROOT/etc/systemd/system/crowdsec-firstboot.service"
: >"$FAILED_FIRSTBOOT_ROOT/etc/systemd/system/firstboot.service"
: >"$FAILED_FIRSTBOOT_ROOT/etc/systemd/system/tailscale-managed-bootstrap.service"
: >"$FAILED_FIRSTBOOT_ROOT/usr/local/libexec/crowdsec-firstboot"
: >"$FAILED_FIRSTBOOT_ROOT/usr/local/libexec/firstboot.sh"
: >"$FAILED_FIRSTBOOT_ROOT/usr/local/libexec/tailscale-managed-up"
: >"$FAILED_FIRSTBOOT_ROOT/usr/local/lib/crowdsec/complete"
: >"$FAILED_FIRSTBOOT_ROOT/usr/local/lib/tailscale/complete"
if SECONDBOOT_ROOT="$FAILED_FIRSTBOOT_ROOT" /bin/sh "$helper_file" >/dev/null 2>&1 &&
   [ ! -e "$FAILED_FIRSTBOOT_ROOT/etc/default/crowdsec-firstboot" ] &&
   [ ! -e "$FAILED_FIRSTBOOT_ROOT/etc/default/tailscale-managed" ] &&
   [ ! -e "$FAILED_FIRSTBOOT_ROOT/etc/systemd/system/crowdsec-firstboot.service" ] &&
   [ -e "$FAILED_FIRSTBOOT_ROOT/etc/systemd/system/firstboot.service" ] &&
   [ ! -e "$FAILED_FIRSTBOOT_ROOT/etc/systemd/system/tailscale-managed-bootstrap.service" ] &&
   [ ! -e "$FAILED_FIRSTBOOT_ROOT/usr/local/libexec/crowdsec-firstboot" ] &&
   [ -e "$FAILED_FIRSTBOOT_ROOT/usr/local/libexec/firstboot.sh" ] &&
   [ ! -e "$FAILED_FIRSTBOOT_ROOT/usr/local/libexec/tailscale-managed-up" ] &&
   [ ! -e "$FAILED_FIRSTBOOT_ROOT/usr/local/lib/crowdsec/complete" ] &&
   [ ! -e "$FAILED_FIRSTBOOT_ROOT/usr/local/lib/tailscale/complete" ]; then
  pass "failed firstboot retains shared diagnostics but removes completed CrowdSec and Tailscale bootstrap artifacts"
else
  fail "failed firstboot retains shared diagnostics but removes completed CrowdSec and Tailscale bootstrap artifacts"
fi

install -d -m 0755 \
  "$PENDING_ROOT/etc/default" \
  "$PENDING_ROOT/etc/systemd/system/multi-user.target.wants" \
  "$PENDING_ROOT/usr/local/lib/crowdsec" \
  "$PENDING_ROOT/usr/local/lib/tailscale" \
  "$PENDING_ROOT/usr/local/libexec" \
  "$PENDING_ROOT/var/lib/installer-state/firstboot"
printf '%s\n' status=0 >"$PENDING_ROOT/var/lib/installer-state/firstboot/complete"
printf '%s\n' enroll-token >"$PENDING_ROOT/usr/local/lib/crowdsec/enroll.token"
printf '%s\n' auth-key >"$PENDING_ROOT/usr/local/lib/tailscale/auth.key"
: >"$PENDING_ROOT/etc/default/crowdsec-firstboot"
: >"$PENDING_ROOT/etc/default/tailscale-managed"
: >"$PENDING_ROOT/usr/local/libexec/crowdsec-firstboot"
: >"$PENDING_ROOT/usr/local/libexec/tailscale-managed-up"
for unit_name in crowdsec-firstboot.service tailscale-managed-bootstrap.service; do
  : >"$PENDING_ROOT/etc/systemd/system/$unit_name"
  ln -s "../$unit_name" "$PENDING_ROOT/etc/systemd/system/multi-user.target.wants/$unit_name"
done

if SECONDBOOT_ROOT="$PENDING_ROOT" /bin/sh "$helper_file" >/dev/null 2>&1 &&
   [ -e "$PENDING_ROOT/var/lib/installer-state/firstboot/complete" ] &&
   [ -s "$PENDING_ROOT/usr/local/lib/crowdsec/enroll.token" ] &&
   [ -s "$PENDING_ROOT/usr/local/lib/tailscale/auth.key" ] &&
   [ -e "$PENDING_ROOT/etc/default/crowdsec-firstboot" ] &&
   [ -e "$PENDING_ROOT/etc/default/tailscale-managed" ] &&
   [ -e "$PENDING_ROOT/etc/systemd/system/crowdsec-firstboot.service" ] &&
   [ -e "$PENDING_ROOT/etc/systemd/system/tailscale-managed-bootstrap.service" ] &&
   [ -e "$PENDING_ROOT/usr/local/libexec/crowdsec-firstboot" ] &&
   [ -e "$PENDING_ROOT/usr/local/libexec/tailscale-managed-up" ]; then
  pass "automatic cleanup preserves incomplete CrowdSec and Tailscale enrollment state"
else
  fail "automatic cleanup preserves incomplete CrowdSec and Tailscale enrollment state"
fi

install -d -m 0755 \
  "$PARTIAL_ROOT/etc/default" \
  "$PARTIAL_ROOT/etc/initramfs-tools/scripts/init-top" \
  "$PARTIAL_ROOT/etc/systemd/system/multi-user.target.wants" \
  "$PARTIAL_ROOT/usr/local/lib/crypto" \
  "$PARTIAL_ROOT/usr/local/lib/firstboot.d" \
  "$PARTIAL_ROOT/usr/local/lib/tailscale" \
  "$PARTIAL_ROOT/usr/local/libexec" \
  "$PARTIAL_ROOT/var/lib/installer-state/firstboot"
printf '%s\n' status=0 >"$PARTIAL_ROOT/var/lib/installer-state/firstboot/complete"
: >"$PARTIAL_ROOT/usr/local/lib/crypto/config.env"
: >"$PARTIAL_ROOT/usr/local/lib/crypto/tpm2-enroll.pending"
printf '%s\n' auth-key >"$PARTIAL_ROOT/usr/local/lib/tailscale/auth.key"
: >"$PARTIAL_ROOT/usr/local/lib/tailscale/complete"
: >"$PARTIAL_ROOT/usr/local/lib/tailscale/status.env"
: >"$PARTIAL_ROOT/usr/local/lib/tailscale/bootstrap.log"
: >"$PARTIAL_ROOT/etc/default/tailscale-managed"
: >"$PARTIAL_ROOT/usr/local/libexec/tailscale-managed-up"
: >"$PARTIAL_ROOT/usr/local/libexec/firstboot.sh"
: >"$PARTIAL_ROOT/usr/local/libexec/secondboot-cleanup"
: >"$PARTIAL_ROOT/usr/local/lib/firstboot.d/05-cleanup.sh"
: >"$PARTIAL_ROOT/etc/initramfs-tools/scripts/installer-health-common"
: >"$PARTIAL_ROOT/etc/initramfs-tools/scripts/init-top/90-installer-health"
for unit_name in firstboot.service secondboot.service tailscale-managed-bootstrap.service; do
  : >"$PARTIAL_ROOT/etc/systemd/system/$unit_name"
  ln -s "../$unit_name" "$PARTIAL_ROOT/etc/systemd/system/multi-user.target.wants/$unit_name"
done

if SECONDBOOT_ROOT="$PARTIAL_ROOT" /bin/sh "$helper_file" >/dev/null 2>&1 &&
   [ -e "$PARTIAL_ROOT/usr/local/lib/crypto/config.env" ] &&
   [ -e "$PARTIAL_ROOT/usr/local/lib/crypto/tpm2-enroll.pending" ] &&
   [ ! -e "$PARTIAL_ROOT/etc/default/tailscale-managed" ] &&
   [ ! -e "$PARTIAL_ROOT/etc/systemd/system/tailscale-managed-bootstrap.service" ] &&
   [ ! -e "$PARTIAL_ROOT/usr/local/lib/tailscale/auth.key" ] &&
   [ ! -e "$PARTIAL_ROOT/usr/local/lib/tailscale/complete" ] &&
   [ ! -e "$PARTIAL_ROOT/usr/local/lib/tailscale/status.env" ] &&
   [ ! -e "$PARTIAL_ROOT/usr/local/lib/tailscale/bootstrap.log" ] &&
   [ ! -e "$PARTIAL_ROOT/etc/systemd/system/firstboot.service" ] &&
   [ ! -e "$PARTIAL_ROOT/usr/local/libexec/firstboot.sh" ] &&
   [ ! -e "$PARTIAL_ROOT/usr/local/lib/firstboot.d" ] &&
   [ ! -e "$PARTIAL_ROOT/etc/initramfs-tools/scripts/installer-health-common" ] &&
   [ ! -e "$PARTIAL_ROOT/etc/initramfs-tools/scripts/init-top/90-installer-health" ] &&
   [ -e "$PARTIAL_ROOT/etc/systemd/system/secondboot.service" ] &&
   [ -e "$PARTIAL_ROOT/usr/local/libexec/secondboot-cleanup" ]; then
  pass "pending TPM2 retains only its retry state while completed Tailscale and shared first-boot artifacts are cleaned"
else
  fail "pending TPM2 retains only its retry state while completed Tailscale and shared first-boot artifacts are cleaned"
fi

install -d -m 0755 \
  "$TARGET_ROOT/etc/cryptsetup-keys.d" \
  "$TARGET_ROOT/etc/default" \
  "$TARGET_ROOT/etc/initramfs-tools/hooks" \
  "$TARGET_ROOT/etc/systemd/system/multi-user.target.wants" \
  "$TARGET_ROOT/etc/systemd/system/sysinit.target.wants" \
  "$TARGET_ROOT/etc/systemd/system/tailscaled.service.d" \
  "$TARGET_ROOT/etc/systemd/system/crowdsec-firewall-bouncer.service.d" \
  "$TARGET_ROOT/etc/crowdsec/bouncers" \
  "$TARGET_ROOT/etc/initramfs-tools/scripts/init-top" \
  "$TARGET_ROOT/etc/initramfs-tools/scripts/init-premount" \
  "$TARGET_ROOT/etc/initramfs-tools/scripts/local-top" \
  "$TARGET_ROOT/etc/initramfs-tools/scripts/local-block" \
  "$TARGET_ROOT/etc/initramfs-tools/scripts/local-premount" \
  "$TARGET_ROOT/etc/initramfs-tools/scripts/local-bottom" \
  "$TARGET_ROOT/etc/initramfs-tools/scripts/init-bottom" \
  "$TARGET_ROOT/etc/profile.d" \
  "$TARGET_ROOT/etc/xdg/autostart" \
  "$TARGET_ROOT/usr/local/bin" \
  "$TARGET_ROOT/usr/local/lib/crowdsec" \
  "$TARGET_ROOT/usr/local/lib/crypto" \
  "$TARGET_ROOT/usr/local/lib/firstboot.d" \
  "$TARGET_ROOT/usr/local/lib/podman" \
  "$TARGET_ROOT/usr/local/libexec" \
  "$TARGET_ROOT/usr/local/sbin" \
  "$TARGET_ROOT/usr/local/lib/tailscale" \
  "$TARGET_ROOT/var/lib/installer-state/firstboot" \
  "$TARGET_ROOT/var/lib/installer-state"

printf '%s\n' status=0 >"$TARGET_ROOT/var/lib/installer-state/firstboot/complete"
: >"$TARGET_ROOT/var/lib/installer-state/installer.log"
touch "$TARGET_ROOT/usr/local/lib/crypto/tpm2-enroll.complete"
printf '%s\n' auth-key >"$TARGET_ROOT/usr/local/lib/tailscale/auth.key"
touch "$TARGET_ROOT/usr/local/lib/tailscale/complete"
: >"$TARGET_ROOT/usr/local/lib/tailscale/status.env"
: >"$TARGET_ROOT/usr/local/lib/tailscale/bootstrap.log"
printf '%s\n' enroll-token >"$TARGET_ROOT/usr/local/lib/crowdsec/enroll.token"

for unit_name in \
  firstboot.service \
  crowdsec-firstboot.service \
  secondboot.service \
  tailscale-managed-bootstrap.service \
  podman-rootless-linger.service \
  podman-rootless-linger-runner.service
do
  : >"$TARGET_ROOT/etc/systemd/system/$unit_name"
  ln -s "../$unit_name" "$TARGET_ROOT/etc/systemd/system/multi-user.target.wants/$unit_name"
done

: >"$TARGET_ROOT/etc/default/crowdsec-firstboot"
: >"$TARGET_ROOT/etc/default/tailscale-managed"
: >"$TARGET_ROOT/usr/local/libexec/crowdsec-firstboot"
: >"$TARGET_ROOT/usr/local/libexec/tailscale-managed-up"
: >"$TARGET_ROOT/usr/local/libexec/firstboot.sh"
: >"$TARGET_ROOT/usr/local/libexec/secondboot-cleanup"
: >"$TARGET_ROOT/usr/local/sbin/tpm2-enroll.sh"
: >"$TARGET_ROOT/usr/local/bin/tpm2-enroll-launch"
: >"$TARGET_ROOT/usr/local/lib/firstboot.d/05-cleanup.sh"
: >"$TARGET_ROOT/etc/initramfs-tools/scripts/installer-health-common"
for stage in init-top init-premount local-top local-block local-premount local-bottom init-bottom; do
  : >"$TARGET_ROOT/etc/initramfs-tools/scripts/$stage/90-installer-health"
done
: >"$TARGET_ROOT/etc/initramfs-tools/scripts/init-top/health-init-top"
: >"$TARGET_ROOT/usr/local/lib/crowdsec/complete"
: >"$TARGET_ROOT/usr/local/lib/crowdsec/status.env"
: >"$TARGET_ROOT/usr/local/lib/crowdsec/bootstrap.log"
: >"$TARGET_ROOT/usr/local/lib/crypto/config.env"
: >"$TARGET_ROOT/usr/local/lib/crypto/install-passphrase"
: >"$TARGET_ROOT/etc/profile.d/tpm2-enroll-prompt.sh"
: >"$TARGET_ROOT/etc/xdg/autostart/tpm2-enroll.desktop"
: >"$TARGET_ROOT/usr/local/lib/podman/podman-rootless-linger.done"

: >"$TARGET_ROOT/etc/systemd/system/managed-syncthing.service"
: >"$TARGET_ROOT/etc/systemd/system/tailscaled.service.d/override.conf"
: >"$TARGET_ROOT/etc/systemd/system/crowdsec-firewall-bouncer.service.d/override.conf"
: >"$TARGET_ROOT/etc/crowdsec/bouncers/crowdsec-firewall-bouncer.yaml.local"
: >"$TARGET_ROOT/etc/crypttab"
: >"$TARGET_ROOT/etc/cryptsetup-keys.d/crypthome.key"
: >"$TARGET_ROOT/etc/tpm2-cryptroot.conf"
: >"$TARGET_ROOT/etc/initramfs-tools/hooks/tpm2-cryptroot"
: >"$TARGET_ROOT/etc/initramfs-tools/scripts/local-top/tpm2-cryptroot"

if SECONDBOOT_ROOT="$TARGET_ROOT" /bin/sh "$helper_file" >/dev/null 2>&1 &&
   [ -e "$TARGET_ROOT/var/lib/installer-state/firstboot/complete" ] &&
   [ -e "$TARGET_ROOT/var/lib/installer-state/installer.log" ] &&
   [ ! -e "$TARGET_ROOT/etc/default/crowdsec-firstboot" ] &&
   [ ! -e "$TARGET_ROOT/etc/default/tailscale-managed" ] &&
   [ ! -e "$TARGET_ROOT/etc/systemd/system/crowdsec-firstboot.service" ] &&
   [ ! -e "$TARGET_ROOT/etc/systemd/system/tailscale-managed-bootstrap.service" ] &&
   [ ! -e "$TARGET_ROOT/etc/systemd/system/secondboot.service" ] &&
   [ ! -e "$TARGET_ROOT/usr/local/lib/firstboot.d" ] &&
   [ ! -e "$TARGET_ROOT/usr/local/libexec/crowdsec-firstboot" ] &&
   [ ! -e "$TARGET_ROOT/usr/local/libexec/tailscale-managed-up" ] &&
   [ ! -e "$TARGET_ROOT/usr/local/libexec/secondboot-cleanup" ] &&
   [ ! -e "$TARGET_ROOT/etc/initramfs-tools/scripts/installer-health-common" ] &&
   [ -z "$(find "$TARGET_ROOT/etc/initramfs-tools/scripts" -name 90-installer-health -print)" ]; then
  pass "automatic cleanup removes completed one-time artifacts while retaining installer-state"
else
  fail "automatic cleanup removes completed one-time artifacts while retaining installer-state"
fi

if [ ! -e "$TARGET_ROOT/usr/local/lib/crypto/config.env" ] &&
   [ ! -e "$TARGET_ROOT/usr/local/lib/crypto/install-passphrase" ] &&
   [ ! -e "$TARGET_ROOT/usr/local/lib/crypto/tpm2-enroll.complete" ] &&
   [ ! -e "$TARGET_ROOT/etc/profile.d/tpm2-enroll-prompt.sh" ] &&
   [ ! -e "$TARGET_ROOT/etc/xdg/autostart/tpm2-enroll.desktop" ] &&
   [ ! -e "$TARGET_ROOT/usr/local/sbin/tpm2-enroll.sh" ] &&
   [ ! -e "$TARGET_ROOT/usr/local/bin/tpm2-enroll-launch" ]; then
  pass "secondboot cleanup removes completed one-time TPM2 enrollment helpers"
else
  fail "secondboot cleanup removes completed one-time TPM2 enrollment helpers"
fi

if [ -e "$TARGET_ROOT/etc/systemd/system/managed-syncthing.service" ] &&
   [ ! -e "$TARGET_ROOT/usr/local/lib/tailscale/auth.key" ] &&
   [ ! -e "$TARGET_ROOT/usr/local/lib/tailscale/complete" ] &&
   [ ! -e "$TARGET_ROOT/usr/local/lib/tailscale/status.env" ] &&
   [ ! -e "$TARGET_ROOT/usr/local/lib/tailscale/bootstrap.log" ] &&
   [ ! -e "$TARGET_ROOT/etc/systemd/system/tailscale-managed-bootstrap.service" ] &&
   [ -e "$TARGET_ROOT/etc/systemd/system/podman-rootless-linger.service" ] &&
   [ -e "$TARGET_ROOT/etc/systemd/system/podman-rootless-linger-runner.service" ] &&
   [ -e "$TARGET_ROOT/usr/local/lib/podman/podman-rootless-linger.done" ] &&
   [ -e "$TARGET_ROOT/etc/systemd/system/tailscaled.service.d/override.conf" ] &&
   [ -e "$TARGET_ROOT/etc/systemd/system/crowdsec-firewall-bouncer.service.d/override.conf" ] &&
   [ -e "$TARGET_ROOT/etc/crowdsec/bouncers/crowdsec-firewall-bouncer.yaml.local" ] &&
   [ -e "$TARGET_ROOT/etc/crypttab" ] &&
   [ -e "$TARGET_ROOT/etc/cryptsetup-keys.d/crypthome.key" ] &&
   [ -e "$TARGET_ROOT/etc/tpm2-cryptroot.conf" ] &&
   [ -e "$TARGET_ROOT/etc/initramfs-tools/hooks/tpm2-cryptroot" ] &&
   [ -e "$TARGET_ROOT/etc/initramfs-tools/scripts/local-top/tpm2-cryptroot" ]; then
  pass "secondboot cleanup removes one-time tailscale bootstrap artifacts while preserving podman-linger and encrypted-boot configuration"
else
  fail "secondboot cleanup removes one-time tailscale bootstrap artifacts while preserving podman-linger and encrypted-boot configuration"
fi

[ "$FAIL_COUNT" -eq 0 ]
