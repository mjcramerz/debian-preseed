#!/bin/sh
# Shared runtime helpers for storage-family installer scripts.
# This file is sourced before scripts/runtime/{btrfs,f2fs}.sh.

runtime_fatal() {
  if command -v installer_fatal >/dev/null 2>&1; then
    installer_fatal "$@"
  fi
  echo "fatal: $*" >&2
  exit 1
}

runtime_cmdline() {
  if [ -n "${INSTALLER_CMDLINE:-}" ]; then
    printf '%s\n' "$INSTALLER_CMDLINE"
    return 0
  fi

  if [ "${RUNTIME_CMDLINE_CACHE_READY:-0}" -eq 1 ]; then
    printf '%s\n' "${RUNTIME_CMDLINE_CACHE:-}"
    return 0
  fi

  if [ -n "${INSTALLER_CMDLINE_FILE:-}" ] && [ -r "${INSTALLER_CMDLINE_FILE}" ]; then
    RUNTIME_CMDLINE_CACHE=$(cat "${INSTALLER_CMDLINE_FILE}" 2>/dev/null || true)
  elif [ -r /proc/cmdline ]; then
    RUNTIME_CMDLINE_CACHE=$(cat /proc/cmdline 2>/dev/null || true)
  else
    RUNTIME_CMDLINE_CACHE=
  fi

  RUNTIME_CMDLINE_CACHE_READY=1
  printf '%s\n' "$RUNTIME_CMDLINE_CACHE"
}

runtime_cmdline_value() {
  key=$1
  for arg in $(runtime_cmdline); do
    case "$arg" in
      "$key"=*)
        printf '%s\n' "${arg#*=}"
        return 0
        ;;
    esac
  done
  return 1
}

runtime_class_list_has_addon() {
  runtime_addon_name=$1
  runtime_class_list=${2:-}

  case "$runtime_addon_name" in
    ''|*[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-]*) return 1 ;;
  esac

  for runtime_class_token in $(printf '%s\n' "$runtime_class_list" | tr ';,' ' '); do
    case "$runtime_class_token" in
      "$runtime_addon_name"|addon/"$runtime_addon_name"|addon:"$runtime_addon_name"|addon."$runtime_addon_name"|class-addon/"$runtime_addon_name"|class-addon:"$runtime_addon_name"|class-addon."$runtime_addon_name")
        return 0
        ;;
    esac
  done
  return 1
}

runtime_addon_class_selected() {
  runtime_addon_name=$1

  if [ -n "${INSTALLER_SELECTED_CLASS_REFS:-}" ]; then
    runtime_class_list_has_addon "$runtime_addon_name" "$INSTALLER_SELECTED_CLASS_REFS"
    return $?
  fi

  if command -v installer_selected_class_reference_is_selected >/dev/null 2>&1 &&
    installer_selected_class_reference_is_selected "addon/$runtime_addon_name"
  then
    return 0
  fi

  runtime_classes_raw=$(runtime_cmdline_value classes 2>/dev/null || true)
  if [ -z "$runtime_classes_raw" ]; then
    runtime_classes_raw=$(runtime_cmdline_value auto-install/classes 2>/dev/null || true)
  fi
  runtime_class_list_has_addon "$runtime_addon_name" "$runtime_classes_raw"
}

runtime_dualboot_class_selected() {
  runtime_addon_class_selected dualboot
}

runtime_qemu_class_selected() {
  runtime_addon_class_selected qemu
}

runtime_crypto_class_selected() {
  runtime_addon_class_selected crypto
}

runtime_root_home_crypto_enabled() {
  runtime_crypto_class_selected
}

runtime_validate_root_home_crypto_layout() {
  runtime_root_home_crypto_enabled || return 0

  [ -n "${DEV_PART_ROOT:-}" ] || runtime_fatal "addon/crypto requires a dedicated root partition"
  [ -n "${DEV_PART_HOME:-}" ] || runtime_fatal "addon/crypto requires a dedicated /home partition"
  case "${DEV_PART_HOME_MB:-}" in
    ''|*[!0-9]*|0)
      runtime_fatal "addon/crypto requires a non-zero dedicated /home partition"
      ;;
  esac
}

runtime_bool_is_true() {
  case "${1:-}" in
    1|true|TRUE|yes|YES|on|ON) return 0 ;;
  esac
  return 1
}

runtime_bool_is_false() {
  case "${1:-}" in
    0|false|FALSE|no|NO|off|OFF) return 0 ;;
  esac
  return 1
}

runtime_apply_ssh_from_classes() {
  if ! command -v installer_selected_class_refs >/dev/null 2>&1 ||
    ! command -v installer_selected_class_reference_is_selected >/dev/null 2>&1; then
    runtime_fatal "installer class selection helpers are unavailable for SSH server provisioning"
  fi
  installer_selected_class_refs >/dev/null 2>&1 ||
    runtime_fatal "selected installer classes are unavailable for SSH server provisioning"

  if installer_selected_class_reference_is_selected addon/ssh; then
    SSH_SERVER_ENABLED=true
    runtime_apply_ssh_from_cmdline
  else
    SSH_SERVER_ENABLED=false
  fi
}

runtime_apply_ssh_from_cmdline() {
  [ "${RUNTIME_SSH_CMDLINE_READY:-0}" = 1 ] && return 0

  ssh_port_default=${SSH_PORT_DEFAULT:-}
  ssh_port_raw=$(runtime_cmdline_value ssh_port 2>/dev/null || true)
  if [ -z "$ssh_port_raw" ]; then
    ssh_port_raw=$ssh_port_default
  fi
  runtime_require_positive_integer ssh_port "$ssh_port_raw"
  [ "$ssh_port_raw" -le 65535 ] || runtime_fatal "ssh_port must be 65535 or lower"
  SSH_PORT=$ssh_port_raw
  RUNTIME_SSH_CMDLINE_READY=1
}

runtime_require_integer() {
  runtime_require_integer_label=$1
  runtime_require_integer_value=$2
  case "$runtime_require_integer_value" in
    ''|*[!0-9]*)
      runtime_fatal "${runtime_require_integer_label} must be an integer, got '${runtime_require_integer_value:-unset}'"
      ;;
  esac
}

runtime_require_positive_integer() {
  runtime_require_positive_integer_label=$1
  runtime_require_positive_integer_value=$2
  runtime_require_integer "$runtime_require_positive_integer_label" "$runtime_require_positive_integer_value"
  [ "$runtime_require_positive_integer_value" -gt 0 ] || runtime_fatal "${runtime_require_positive_integer_label} must be greater than zero"
}

runtime_require_nonnegative_integer() {
  runtime_require_nonnegative_integer_label=$1
  runtime_require_nonnegative_integer_value=$2
  runtime_require_integer "$runtime_require_nonnegative_integer_label" "$runtime_require_nonnegative_integer_value"
  [ "$runtime_require_nonnegative_integer_value" -ge 0 ] || runtime_fatal "${runtime_require_nonnegative_integer_label} must be zero or greater"
}

runtime_min() {
  runtime_min_left=$1
  runtime_min_right=$2
  runtime_require_integer runtime_min_left "$runtime_min_left"
  runtime_require_integer runtime_min_right "$runtime_min_right"
  if [ "$runtime_min_left" -le "$runtime_min_right" ]; then
    printf '%s\n' "$runtime_min_left"
  else
    printf '%s\n' "$runtime_min_right"
  fi
}

runtime_max() {
  runtime_max_left=$1
  runtime_max_right=$2
  runtime_require_integer runtime_max_left "$runtime_max_left"
  runtime_require_integer runtime_max_right "$runtime_max_right"
  if [ "$runtime_max_left" -ge "$runtime_max_right" ]; then
    printf '%s\n' "$runtime_max_left"
  else
    printf '%s\n' "$runtime_max_right"
  fi
}

runtime_clamp() {
  runtime_clamp_value=$1
  runtime_clamp_min=$2
  runtime_clamp_max=$3
  runtime_require_integer runtime_clamp_value "$runtime_clamp_value"
  runtime_require_integer runtime_clamp_min "$runtime_clamp_min"
  runtime_require_integer runtime_clamp_max "$runtime_clamp_max"
  if [ "$runtime_clamp_min" -gt "$runtime_clamp_max" ]; then
    runtime_fatal "runtime_clamp requires min <= max, got ${runtime_clamp_min} > ${runtime_clamp_max}"
  fi
  if [ "$runtime_clamp_value" -lt "$runtime_clamp_min" ]; then
    printf '%s\n' "$runtime_clamp_min"
  elif [ "$runtime_clamp_value" -gt "$runtime_clamp_max" ]; then
    printf '%s\n' "$runtime_clamp_max"
  else
    printf '%s\n' "$runtime_clamp_value"
  fi
}

runtime_total_ram_mib() {
  if [ -n "${RUNTIME_MEMTOTAL_MIB_OVERRIDE:-}" ]; then
    runtime_require_positive_integer RUNTIME_MEMTOTAL_MIB_OVERRIDE "$RUNTIME_MEMTOTAL_MIB_OVERRIDE"
    printf '%s\n' "$RUNTIME_MEMTOTAL_MIB_OVERRIDE"
    return 0
  fi

  if [ -r /proc/meminfo ]; then
    mem_kib=
    while IFS=' ' read -r key value _rest || [ -n "${key:-}" ]; do
      [ "$key" = "MemTotal:" ] || continue
      mem_kib=$value
      break
    done </proc/meminfo
    case "$mem_kib" in
      ''|*[!0-9]*|0) ;;
      *)
        printf '%s\n' "$(((mem_kib + 1023) / 1024))"
        return 0
        ;;
    esac
  fi

  runtime_fatal "unable to determine total RAM in MiB"
}

runtime_seed_debconf_value() {
  question=$1
  value=$2

  if command -v debconf-communicate >/dev/null 2>&1; then
    {
      printf 'SET %s %s\n' "$question" "$value"
      printf 'FSET %s seen true\n' "$question"
    } | debconf-communicate >/dev/null 2>&1 || true
    return 0
  fi

  runtime_fatal "no debconf interface is available to seed ${question}"
}

runtime_apply_answers_file() {
  path=$1
  [ -r "$path" ] || runtime_fatal "answer fragment is not readable: ${path}"

  if command -v debconf-set-selections >/dev/null 2>&1; then
    debconf-set-selections "$path"
    return 0
  fi

  runtime_seed_answers_file "$path"
}

runtime_seed_answers_file() {
  path=$1
  [ -r "$path" ] || runtime_fatal "answer fragment is not readable: ${path}"

  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      ''|'#'*) continue ;;
    esac
    # shellcheck disable=SC2086
    set -- $line
    [ "$#" -ge 4 ] || continue
    question=$2
    shift 3
    value=$*
    runtime_seed_debconf_value "$question" "$value"
  done <"$path"
}

runtime_prepare_parent_dir() {
  path=$1
  mode=$2
  parent_dir=$(dirname "$path")
  [ -d "$parent_dir" ] || install -d -m "$mode" "$parent_dir"
}

runtime_shell_quote() {
  printf "'%s'" "$(printf '%s' "${1-}" | sed "s/'/'\\\\''/g")"
}

runtime_validate_printable_single_line() {
  label=$1
  value=$2

  [ -n "$value" ] || runtime_fatal "${label} must not be empty"
  case "$value" in
    *[![:print:]]*|*[[:space:]]*)
      runtime_fatal "${label} must be a single printable token without whitespace"
      ;;
  esac
}

runtime_validate_system_prefix() {
  value=$1

  [ -n "$value" ] || runtime_fatal "SYSTEM_PREFIX must not be empty"
  case "$value" in
    *[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789]*)
      runtime_fatal "SYSTEM_PREFIX must contain only ASCII letters and digits"
      ;;
  esac
  if [ "${#value}" -gt 59 ]; then
    runtime_fatal "SYSTEM_PREFIX must be 59 characters or shorter so SYSTEM_HOSTNAME stays within 63 characters"
  fi
}

runtime_validate_system_domain() {
  value=$1

  [ -n "$value" ] || runtime_fatal "SYSTEM_DOMAIN must not be empty"
  case "$value" in
    *[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789.-]*|.*|*.|*..*)
      runtime_fatal "SYSTEM_DOMAIN must contain only hostname-safe labels"
      ;;
  esac
}

runtime_validate_system_hostname() {
  prefix=$1
  value=$2

  case "$value" in
    ''|*[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-]*|-*|*-)
      runtime_fatal "SYSTEM_HOSTNAME must contain only hostname-safe characters"
      ;;
    "${prefix}"-[0-9][0-9][0-9])
      ;;
    *)
      runtime_fatal "SYSTEM_HOSTNAME must match SYSTEM_PREFIX-###"
      ;;
  esac
}

runtime_apply_identity_from_cmdline() {
  cmdline_domain=$(runtime_cmdline_value netcfg/get_domain 2>/dev/null || true)
  if [ -z "$cmdline_domain" ]; then
    cmdline_domain=$(runtime_cmdline_value domain 2>/dev/null || true)
  fi
  [ -n "$cmdline_domain" ] || return 0
  SYSTEM_DOMAIN=$cmdline_domain
}

runtime_random_hostname_suffix() {
  [ -r /dev/urandom ] || runtime_fatal "unable to generate hostname suffix: /dev/urandom is unavailable"
  # Filter the kernel RNG stream down to ASCII digits so the suffix is always ###.
  raw=$(LC_ALL=C tr -dc '0-9' </dev/urandom | dd bs=3 count=1 2>/dev/null || true)
  case "$raw" in
    [0-9][0-9][0-9])
      ;;
    *)
      runtime_fatal "unable to generate hostname suffix from /dev/urandom"
      ;;
  esac

  printf '%s\n' "$raw"
}

runtime_ensure_system_identity() {
  : "${SYSTEM_PREFIX:?SYSTEM_PREFIX must be set}"
  : "${SYSTEM_DOMAIN:?SYSTEM_DOMAIN must be set}"

  runtime_apply_identity_from_cmdline
  runtime_validate_system_prefix "$SYSTEM_PREFIX"
  runtime_validate_system_domain "$SYSTEM_DOMAIN"

  if [ -n "${SYSTEM_HOSTNAME:-}" ]; then
    runtime_validate_system_hostname "$SYSTEM_PREFIX" "$SYSTEM_HOSTNAME"
    return 0
  fi

  SYSTEM_HOSTNAME="${SYSTEM_PREFIX}-$(runtime_random_hostname_suffix)"
  runtime_validate_system_hostname "$SYSTEM_PREFIX" "$SYSTEM_HOSTNAME"
}

runtime_generate_crypto_bootstrap_key() {
  crypto_bootstrap_key=

  [ -r /proc/sys/kernel/random/uuid ] ||
    runtime_fatal "kernel UUID entropy source is unavailable for the crypto bootstrap key"
  IFS= read -r crypto_bootstrap_key </proc/sys/kernel/random/uuid ||
    [ -n "$crypto_bootstrap_key" ] ||
    runtime_fatal "unable to generate the crypto bootstrap key"

  case "$crypto_bootstrap_key" in
    ????????-????-????-????-????????????) ;;
    *) runtime_fatal "generated crypto bootstrap key has an invalid UUID shape" ;;
  esac
  case "$crypto_bootstrap_key" in
    *[!0123456789abcdefABCDEF-]*)
      runtime_fatal "generated crypto bootstrap key has unsupported characters"
      ;;
  esac

  printf '%s\n' "$crypto_bootstrap_key"
}

runtime_read_or_create_crypto_bootstrap_key() {
  key_file=$1
  key_dir=$(dirname "$key_file")
  key_tmp="${key_file}.tmp.$$"
  crypto_bootstrap_key=

  if [ -e "$key_file" ]; then
    [ -f "$key_file" ] && [ ! -L "$key_file" ] ||
      runtime_fatal "crypto bootstrap key must be a regular non-symlink file: ${key_file}"
    IFS= read -r crypto_bootstrap_key <"$key_file" ||
      [ -n "$crypto_bootstrap_key" ] ||
      runtime_fatal "unable to read crypto bootstrap key: ${key_file}"
  else
    crypto_bootstrap_key=$(runtime_generate_crypto_bootstrap_key)
    (
      umask 077
      printf '%s' "$crypto_bootstrap_key" >"$key_tmp"
    ) || runtime_fatal "unable to write crypto bootstrap key"
    chmod 0400 "$key_tmp" || runtime_fatal "unable to secure crypto bootstrap key"
    mv -f "$key_tmp" "$key_file" || runtime_fatal "unable to install crypto bootstrap key"
  fi

  case "$crypto_bootstrap_key" in
    ????????-????-????-????-????????????) ;;
    *) runtime_fatal "crypto bootstrap key has an invalid UUID shape" ;;
  esac
  case "$crypto_bootstrap_key" in
    *[!0123456789abcdefABCDEF-]*)
      runtime_fatal "crypto bootstrap key has unsupported characters"
      ;;
  esac
  chmod 0400 "$key_file" || runtime_fatal "unable to secure crypto bootstrap key"
  [ -d "$key_dir" ] || runtime_fatal "crypto bootstrap key directory is missing: ${key_dir}"
  printf '%s\n' "$crypto_bootstrap_key"
}

runtime_write_crypto_answers() {
  dest=$1

  runtime_validate_account_settings
  runtime_prepare_parent_dir "$dest" 0700
  crypto_key_file="$(dirname "$dest")/crypto-bootstrap.key"
  crypto_install_passphrase=$(runtime_read_or_create_crypto_bootstrap_key "$crypto_key_file")
  {
    printf '##########  Runtime Crypto Configuration  ##########\n'
    printf '# Generated inside the installer. addon/crypto uses a random bootstrap passphrase.\n'
    printf 'd-i partman-crypto/passphrase password %s\n' "$crypto_install_passphrase"
    printf 'd-i partman-crypto/passphrase seen true\n'
    printf 'd-i partman-crypto/passphrase-again password %s\n' "$crypto_install_passphrase"
    printf 'd-i partman-crypto/passphrase-again seen true\n'
    printf 'd-i partman-crypto/weak_passphrase boolean true\n'
    printf 'd-i partman-crypto/weak_passphrase seen true\n'
    printf 'd-i partman-crypto/confirm boolean true\n'
    printf 'd-i partman-crypto/confirm seen true\n'
    printf 'd-i partman-crypto/confirm_nochanges boolean true\n'
    printf 'd-i partman-crypto/confirm_nochanges seen true\n'
    printf 'd-i partman-crypto/confirm_nooverwrite boolean true\n'
    printf 'd-i partman-crypto/confirm_nooverwrite seen true\n'
  } >"$dest"
  chmod 0600 "$dest"
}

runtime_seed_generated_answers() {
  writer=$1
  shift

  tmp_dir=$(mktemp -d) || runtime_fatal "unable to create temporary answer directory"
  tmp_file="${tmp_dir}/generated.answers"
  status=0

  "$writer" "$tmp_file" "$@" || {
    status=$?
    rm -rf "$tmp_dir"
    return "$status"
  }
  runtime_apply_answers_file "$tmp_file" || {
    status=$?
    rm -rf "$tmp_dir"
    return "$status"
  }

  rm -rf "$tmp_dir"
  return 0
}

runtime_secure_boot_state_uses_luks() {
  [ "$(runtime_secure_boot_state_mode)" = "luks" ]
}

runtime_derive_part_prefix() {
  if [ -n "${DEV_PART_PREFIX:-}" ]; then
    return 0
  fi

  DEV_PART_PREFIX=${DEV_INSTALL_DISK:-}
  case "${DEV_INSTALL_DISK:-}" in
    *[0-9]) DEV_PART_PREFIX="${DEV_INSTALL_DISK}p" ;;
  esac
}

runtime_partition_path() {
  slot=$1
  printf '%s%s\n' "$DEV_PART_PREFIX" "$slot"
}

runtime_device_size_bytes() {
  dev=$1
  if [ ! -b "$dev" ]; then
    echo "fatal: partition device is missing: ${dev}" >&2
    return 1
  fi

  if command -v blockdev >/dev/null 2>&1; then
    bytes=$(blockdev --getsize64 "$dev" 2>/dev/null || true)
    case "$bytes" in
      ''|*[!0-9]*) ;;
      *)
        printf '%s\n' "$bytes"
        return 0
        ;;
    esac
  fi

  sys_name=${dev##*/}
  sectors_file="/sys/class/block/${sys_name}/size"
  if [ -r "$sectors_file" ]; then
    sectors=$(cat "$sectors_file")
    case "$sectors" in
      ''|*[!0-9]*) ;;
      *)
        printf '%s\n' "$((sectors * 512))"
        return 0
        ;;
    esac
  fi

  echo "fatal: unable to determine partition size for ${dev}" >&2
  return 1
}

runtime_device_size_mb() {
  dev=$1
  bytes=$(runtime_device_size_bytes "$dev") || return 1
  size_mb=$(((bytes + 1048575) / 1048576))
  [ "$size_mb" -gt 0 ] || runtime_fatal "partition size for ${dev} resolved to zero MB"
  printf '%s\n' "$size_mb"
}

runtime_install_disk_size_mb() {
  if [ -n "${RUNTIME_INSTALL_DISK_MB_OVERRIDE:-}" ]; then
    runtime_require_positive_integer RUNTIME_INSTALL_DISK_MB_OVERRIDE "$RUNTIME_INSTALL_DISK_MB_OVERRIDE"
    printf '%s\n' "$RUNTIME_INSTALL_DISK_MB_OVERRIDE"
    return 0
  fi

  runtime_device_size_mb "$DEV_INSTALL_DISK"
}

runtime_fill_partition_to_target() {
  current_mb=$1
  target_mb=$2
  budget_mb=$3

  runtime_require_positive_integer runtime_fill_current_mb "$current_mb"
  runtime_require_integer runtime_fill_target_mb "$target_mb"
  runtime_require_integer runtime_fill_budget_mb "$budget_mb"

  if [ "$budget_mb" -le 0 ] || [ "$current_mb" -ge "$target_mb" ]; then
    printf '%s %s\n' "$current_mb" "$budget_mb"
    return 0
  fi

  needed_mb=$((target_mb - current_mb))
  if [ "$needed_mb" -le "$budget_mb" ]; then
    printf '%s %s\n' "$target_mb" "$((budget_mb - needed_mb))"
  else
    printf '%s %s\n' "$((current_mb + budget_mb))" "0"
  fi
}

runtime_apply_fill_result() {
  current_var=$1
  budget_var=$2
  fill_result=$3

  case "$fill_result" in
    *" "*)
      new_current=${fill_result%% *}
      new_budget=${fill_result#* }
      ;;
    *)
      runtime_fatal "runtime fill result must contain '<current> <budget>', got '${fill_result}'"
      ;;
  esac

  runtime_require_integer runtime_apply_fill_current "$new_current"
  runtime_require_integer runtime_apply_fill_budget "$new_budget"
  eval "$current_var=\$new_current"
  eval "$budget_var=\$new_budget"
}

runtime_shrink_partition_to_floor() {
  current_mb=$1
  floor_mb=$2
  overflow_mb=$3

  runtime_require_nonnegative_integer runtime_shrink_current_mb "$current_mb"
  runtime_require_nonnegative_integer runtime_shrink_floor_mb "$floor_mb"
  runtime_require_integer runtime_shrink_overflow_mb "$overflow_mb"
  [ "$floor_mb" -le "$current_mb" ] || runtime_fatal "runtime shrink floor must be <= current size"

  if [ "$overflow_mb" -le 0 ] || [ "$current_mb" -le "$floor_mb" ]; then
    printf '%s %s\n' "$current_mb" "$overflow_mb"
    return 0
  fi

  shrinkable_mb=$((current_mb - floor_mb))
  if [ "$shrinkable_mb" -ge "$overflow_mb" ]; then
    printf '%s %s\n' "$((current_mb - overflow_mb))" "0"
  else
    printf '%s %s\n' "$floor_mb" "$((overflow_mb - shrinkable_mb))"
  fi
}

runtime_compute_raw_zram_partition_mb() {
  runtime_zram_budget_mb=$1
  runtime_zram_relevant_span_mb=$2

  runtime_require_positive_integer runtime_zram_budget_mb "$runtime_zram_budget_mb"
  runtime_require_positive_integer runtime_zram_relevant_span_mb "$runtime_zram_relevant_span_mb"
  runtime_require_positive_integer SIZE_PART_RAW_ZRAM_MB "${SIZE_PART_RAW_ZRAM_MB:-}"
  runtime_require_positive_integer SIZE_PART_RAW_ZRAM_DISK_DIVISOR "${SIZE_PART_RAW_ZRAM_DISK_DIVISOR:-}"
  runtime_require_positive_integer SIZE_PART_RAW_ZRAM_BUDGET_DIVISOR "${SIZE_PART_RAW_ZRAM_BUDGET_DIVISOR:-}"
  runtime_require_positive_integer SIZE_PART_RAW_ZRAM_MAX_MB "${SIZE_PART_RAW_ZRAM_MAX_MB:-}"
  runtime_require_positive_integer SIZE_PART_RAW_ZRAM_MIN_MB "${SIZE_PART_RAW_ZRAM_MIN_MB:-2048}"

  runtime_zram_floor_mb=$(runtime_min "$SIZE_PART_RAW_ZRAM_MB" "${SIZE_PART_RAW_ZRAM_MIN_MB:-2048}")
  runtime_zram_target_mb=$((runtime_zram_relevant_span_mb / SIZE_PART_RAW_ZRAM_DISK_DIVISOR))
  runtime_zram_target_mb=$(runtime_clamp "$runtime_zram_target_mb" "$runtime_zram_floor_mb" "$SIZE_PART_RAW_ZRAM_MAX_MB")
  runtime_zram_budget_cap_mb=$((runtime_zram_budget_mb / SIZE_PART_RAW_ZRAM_BUDGET_DIVISOR))
  if [ "$runtime_zram_budget_cap_mb" -lt "$runtime_zram_floor_mb" ]; then
    runtime_zram_budget_cap_mb=$runtime_zram_floor_mb
  fi

  runtime_min "$runtime_zram_target_mb" "$runtime_zram_budget_cap_mb"
}

runtime_compute_swap_partition_mib() {
  runtime_swap_budget_mb=$1
  runtime_swap_ram_mib=$2

  runtime_require_positive_integer runtime_swap_budget_mb "$runtime_swap_budget_mb"
  runtime_require_positive_integer runtime_swap_ram_mib "$runtime_swap_ram_mib"
  runtime_require_positive_integer SIZE_PART_RAW_SWAP_MB "${SIZE_PART_RAW_SWAP_MB:-}"
  runtime_require_positive_integer SIZE_PART_SWAP_MIN_MIB "${SIZE_PART_SWAP_MIN_MIB:-}"
  runtime_require_positive_integer SIZE_PART_SWAP_MAX_MIB "${SIZE_PART_SWAP_MAX_MIB:-}"
  runtime_require_positive_integer SIZE_PART_SWAP_RAM_DIVISOR "${SIZE_PART_SWAP_RAM_DIVISOR:-}"
  runtime_require_positive_integer SIZE_PART_SWAP_LAYOUT_DIVISOR "${SIZE_PART_SWAP_LAYOUT_DIVISOR:-}"

  runtime_swap_target_mib=$((runtime_swap_ram_mib / SIZE_PART_SWAP_RAM_DIVISOR))
  runtime_swap_target_mib=$(runtime_clamp "$runtime_swap_target_mib" "$SIZE_PART_SWAP_MIN_MIB" "$SIZE_PART_SWAP_MAX_MIB")
  runtime_swap_budget_cap_mib=$((runtime_swap_budget_mb / SIZE_PART_SWAP_LAYOUT_DIVISOR))
  if [ "$runtime_swap_budget_cap_mib" -lt "$SIZE_PART_SWAP_MIN_MIB" ]; then
    runtime_swap_budget_cap_mib=$SIZE_PART_SWAP_MIN_MIB
  fi

  runtime_min "$runtime_swap_target_mib" "$runtime_swap_budget_cap_mib"
}
