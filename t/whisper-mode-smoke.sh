#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/whisper-mode-smoke.XXXXXX")
trap 'rm -rf "$TMP_DIR"' EXIT HUP INT TERM

MODULE_ROOT="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/lib/perl5/site_perl/whisper"
ENTRYPOINT="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/libexec/whisper-record-toggle"
OBSOLETE_ENTRYPOINT="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/whisper-record-toggle"
WHISPER_CLI_WRAPPER="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/libexec/whisper-cli-default-model"
INSTALLER="$ROOT_DIR/d-i/forky/scripts/late/whisper.sh"
WHISPER_RUNTIME_TEMPLATE="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/whisper/whisper.conf.tmpl"
APPARMOR_PROFILE="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/managed-desktop-wrappers"
WHISPER_APPARMOR_PROFILE="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/whisper-local-transcription"
GRAPHICS_ABSTRACTION="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/abstractions/managed-desktop-graphics"
RSYSLOG_ROUTE="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/rsyslog.d/37-whisper.conf"
TMPFILES_LOGS="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/tmpfiles.d/60-security-logs.conf"
LOGROTATE_POLICY="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/logrotate.d/whisper"
WAYBAR_TEMPLATE="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/waybar/config.tmpl"
DESKTOP_COMPONENTS="$ROOT_DIR/d-i/forky/scripts/desktop/components.sh"
MUTE_DEFAULT_HELPER="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/libexec/labwc-mute-default-microphone"
MUTE_DEFAULT_UNIT="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/systemd/user/labwc-mute-default-microphone.service"
WHISPER_RECORD_UNIT="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/systemd/user/whisper-record.service"
WHISPER_SERVER_UNIT="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/systemd/user/whisper-server.service"
WHISPER_TRANSCRIBE_UNIT="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/systemd/user/whisper-transcribe.service"
WHISPER_RUNTIME_TMPFILES="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/tmpfiles.d/55-whisper-runtime.conf"
OBSOLETE_MUTE_DEFAULT_UNIT="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/systemd/user/whisper-mute-default.service"
PORTAL_WLR_UNIT="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/systemd/user/xdg-desktop-portal-wlr.service.d/10-labwc-session.conf"
DESKTOP_PACKAGE_CFG="$ROOT_DIR/d-i/forky/classes/class-select/role/desktop.cfg"
WIREPLUMBER_AUDIO_POLICY="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/wireplumber/wireplumber.conf.d/20-managed-audio-policy.conf"
WIREPLUMBER_SKEL_AUDIO_POLICY="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/wireplumber/wireplumber.conf.d/20-managed-audio-policy.conf"
PIPEWIRE_CLIENT_VOLUME_POLICY="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/pipewire/client.conf.d/20-managed-volume-ceiling.conf"
PIPEWIRE_PULSE_VOLUME_POLICY="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/pipewire/pipewire-pulse.conf.d/20-managed-volume-ceiling.conf"
PERL_STUB_ROOT="$TMP_DIR/perl-stubs"
TEST_COUNT=28
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

assert_contains() {
  needle=$1
  path=$2
  grep -Fq -- "$needle" "$path"
}

write_perl_compatibility_modules() {
  mkdir -p "$PERL_STUB_ROOT/MooX" "$PERL_STUB_ROOT/Types"

  cat >"$PERL_STUB_ROOT/Moo.pm" <<'EOF'
package Moo;

use strict;
use warnings;

sub import {
    my ($class) = @_;
    my $caller = caller;
    my %attributes;

    no strict 'refs';
    *{"${caller}::has"} = sub {
        my ($name, @arguments) = @_;
        @arguments % 2 == 0 or die "invalid attribute specification\n";
        my %specification = @arguments;
        $attributes{$name} = \%specification;

        *{"${caller}::${name}"} = sub {
            my ($self, @values) = @_;
            if (@values) {
                $self->{$name} = $values[0];
                return $self->{$name};
            }
            return $self->{$name} if exists $self->{$name};
            if (exists $specification{default}) {
                $self->{$name} = ref($specification{default}) eq 'CODE'
                    ? $specification{default}->($self)
                    : $specification{default};
                return $self->{$name};
            }
            if ($specification{lazy} || ($specification{is} // q{}) eq 'lazy') {
                my $builder = $specification{builder};
                $self->{$name} = ref($builder) eq 'CODE'
                    ? $builder->($self)
                    : $self->$builder();
                return $self->{$name};
            }
            return undef;
        };
        return;
    };
    *{"${caller}::new"} = sub {
        my ($package, @arguments) = @_;
        @arguments % 2 == 0 or die "invalid constructor arguments\n";
        my %values = @arguments;
        return bless \%values, $package;
    };
    return;
}

1;
EOF

  cat >"$PERL_STUB_ROOT/MooX/Options.pm" <<'EOF'
package MooX::Options;

use strict;
use warnings;

sub import {
    my ($class) = @_;
    my $caller = caller;

    no strict 'refs';
    *{"${caller}::option"} = sub {
        my ($name, @arguments) = @_;
        @arguments % 2 == 0 or die "invalid option specification\n";
        my %specification = @arguments;
        delete $specification{doc};
        my $has = \&{"${caller}::has"};
        $has->($name, %specification);
        return;
    };
    *{"${caller}::new_with_options"} = sub {
        my ($package, @arguments) = @_;
        @arguments % 2 == 0 or die "invalid constructor arguments\n";
        my %constructor = @arguments;
        while (@ARGV) {
            my $argument = shift @ARGV;
            if ($argument eq '--help' || $argument eq '-h') {
                $constructor{help} = 1;
                next;
            }
            $argument !~ /\A-/
                or die "unknown option: $argument\n";
            unshift @ARGV, $argument;
            last;
        }
        return $package->new(%constructor);
    };
    return;
}

1;
EOF

  cat >"$PERL_STUB_ROOT/MooX/StrictConstructor.pm" <<'EOF'
package MooX::StrictConstructor;

use strict;
use warnings;

sub import { return; }

1;
EOF

  cat >"$PERL_STUB_ROOT/MooX/TypeTiny.pm" <<'EOF'
package MooX::TypeTiny;

use strict;
use warnings;

sub import { return; }

1;
EOF

  cat >"$PERL_STUB_ROOT/Types/Standard.pm" <<'EOF'
package Types::Standard;

use strict;
use warnings;

sub import {
    my ($class, @symbols) = @_;
    my $caller = caller;

    no strict 'refs';
    for my $symbol (@symbols) {
        *{"${caller}::${symbol}"} = sub { return sub { 1 }; };
    }
    return;
}

1;
EOF
}

compile_mode_payload() {
  module=$1
  PERL5LIB="$PERL_STUB_ROOT:$MODULE_ROOT" \
    /usr/bin/perl -c "$MODULE_ROOT/$module" >/dev/null 2>&1
}

compile_perl_entrypoint() {
  entrypoint=$1
  PERL5LIB="$PERL_STUB_ROOT:$MODULE_ROOT" \
    /usr/bin/perl -c "$entrypoint" >/dev/null 2>&1
}

run_whisper() {
  PERL5LIB="$PERL_STUB_ROOT:$MODULE_ROOT" \
    /usr/bin/perl "$ENTRYPOINT" "$@"
}

printf '1..%s\n' "$TEST_COUNT"

if [ -d "$MODULE_ROOT/WhisperMode" ] &&
   [ ! -e "$MODULE_ROOT/Whisper" ] &&
   [ ! -L "$MODULE_ROOT/Whisper" ]; then
  pass "WhisperMode is the only installed Whisper Perl namespace"
else
  fail "WhisperMode is the only installed Whisper Perl namespace"
fi

expected_modules="$TMP_DIR/expected-modules"
actual_modules="$TMP_DIR/actual-modules"
cat >"$expected_modules" <<'EOF'
WhisperMode/Artifacts.pm
WhisperMode/Audio.pm
WhisperMode/CLI.pm
WhisperMode/Config.pm
WhisperMode/Logger.pm
WhisperMode/Memory.pm
WhisperMode/Recorder.pm
WhisperMode/Runtime.pm
WhisperMode/State.pm
WhisperMode/Systemd.pm
WhisperMode/Transcriber.pm
EOF
(
  cd "$MODULE_ROOT"
  find WhisperMode -type f -name '*.pm' -print | LC_ALL=C sort
) >"$actual_modules"
if cmp -s "$expected_modules" "$actual_modules"; then
  pass "canonical WhisperMode manifest names every and only runtime module"
else
  fail "canonical WhisperMode manifest names every and only runtime module"
fi

mode_extensions_ok=true
for module in \
  WhisperMode/Artifacts.pm \
  WhisperMode/Audio.pm \
  WhisperMode/Config.pm \
  WhisperMode/Memory.pm \
  WhisperMode/Recorder.pm \
  WhisperMode/Runtime.pm \
  WhisperMode/State.pm \
  WhisperMode/Systemd.pm \
  WhisperMode/Transcriber.pm
do
  if ! assert_contains 'use Moo;' "$MODULE_ROOT/$module" ||
     ! assert_contains 'use MooX::StrictConstructor;' "$MODULE_ROOT/$module" ||
     ! assert_contains 'use MooX::TypeTiny;' "$MODULE_ROOT/$module"; then
    mode_extensions_ok=false
    break
  fi
done
if [ "$mode_extensions_ok" = true ] &&
   ! grep -q '^use Moo' "$MODULE_ROOT/WhisperMode/CLI.pm" &&
   assert_contains 'use WhisperMode::Runtime;' "$MODULE_ROOT/WhisperMode/CLI.pm"; then
  pass "WhisperMode runtime classes use Moo while the CLI keeps a narrow dispatch boundary"
else
  fail "WhisperMode runtime classes use Moo while the CLI keeps a narrow dispatch boundary"
fi

if assert_contains 'use WhisperMode::CLI;' "$ENTRYPOINT" &&
   assert_contains 'exit WhisperMode::CLI->run(@ARGV);' "$ENTRYPOINT" &&
   ! grep -Fq 'Whisper::' "$ENTRYPOINT" &&
   ! grep -R -Fq -- 'Whisper::' "$MODULE_ROOT"; then
  pass "Whisper entrypoint dispatches directly to the canonical namespace without aliases"
else
  fail "Whisper entrypoint dispatches directly to the canonical namespace without aliases"
fi

if assert_contains 'whisper_stage_mode_perl_modules' "$INSTALLER" &&
   assert_contains "target/usr/local/lib/perl5/site_perl/whisper/\${whisper_module}" "$INSTALLER" &&
   assert_contains 'target/usr/local/libexec/whisper-record-toggle' "$INSTALLER" &&
   assert_contains 'target/usr/local/libexec/whisper-cli-default-model' "$INSTALLER" &&
   assert_contains 'WHISPER_MODEL_DIR must remain /pool/cache/whisper/models' "$INSTALLER" &&
   assert_contains 'whisper_target_secure_model_directory' "$INSTALLER" &&
   assert_contains 'chown "0:${whisper_model_gid}" "$WHISPER_MODEL_DIR" "$marker_path"' "$INSTALLER" &&
   assert_contains 'chmod 2750 "$WHISPER_MODEL_DIR"' "$INSTALLER" &&
   assert_contains 'chown "0:${whisper_model_gid}" "$final_model"' "$INSTALLER" &&
   assert_contains 'chmod 0640 "$final_model"' "$INSTALLER" &&
   ! grep -Fq 'target/usr/local/bin/whisper-record-toggle' "$INSTALLER" &&
   [ ! -e "$OBSOLETE_ENTRYPOINT" ] &&
   ! grep -Fq "target/usr/local/libexec/whisper/\${whisper_module}" "$INSTALLER"; then
  pass "Whisper installer stages the canonical site_perl payload and sole managed toggle entrypoint"
else
  fail "Whisper installer stages the canonical site_perl payload and sole managed toggle entrypoint"
fi

if assert_contains 'install -d -o 0 -g 0 -m 0755 "$runtime_conf_dir"' "$INSTALLER" &&
   assert_contains 'chown 0:0 "$runtime_conf_tmp"' "$INSTALLER" &&
   assert_contains 'chown 0:0 "$runtime_conf"' "$INSTALLER" &&
   assert_contains 'target/etc/whisper/whisper.conf.tmpl' "$INSTALLER" &&
   assert_contains 's|__WHISPER_CLI__|${WHISPER_BINARY_DIR}/whisper-cli|g' "$INSTALLER" &&
   assert_contains 's|__WHISPER_SERVER__|${WHISPER_BINARY_DIR}/whisper-server|g' "$INSTALLER" &&
   assert_contains 's|__WHISPER_SERVER_PORT__|${WHISPER_SERVER_PORT}|g' "$INSTALLER" &&
   ! grep -Fq 'cat >"$runtime_conf_tmp"' "$INSTALLER" &&
   grep -Fqx 'WHISPER_CLI=__WHISPER_CLI__' "$WHISPER_RUNTIME_TEMPLATE" &&
   grep -Fqx 'WHISPER_SERVER=__WHISPER_SERVER__' "$WHISPER_RUNTIME_TEMPLATE" &&
   grep -Fqx 'WHISPER_SERVER_PORT=__WHISPER_SERVER_PORT__' "$WHISPER_RUNTIME_TEMPLATE" &&
   grep -Fqx 'WHISPER_MODEL=__WHISPER_MODEL__' "$WHISPER_RUNTIME_TEMPLATE" &&
   assert_contains 'chown 0:0 "$whisper_runtime_conf_dir_host" "$whisper_runtime_conf_host"' "$INSTALLER" &&
   grep -Fqx 'd /etc/whisper 0755 root root -' "$WHISPER_RUNTIME_TMPFILES" &&
   grep -Fqx 'z /etc/whisper/whisper.conf 0644 root root -' "$WHISPER_RUNTIME_TMPFILES" &&
   assert_contains 'desktop_stage_role_asset etc/tmpfiles.d/55-whisper-runtime.conf /etc/tmpfiles.d/55-whisper-runtime.conf 0644' "$DESKTOP_COMPONENTS" &&
   grep -Fqx 'After=labwc-session.target pipewire.service pipewire-pulse.service wireplumber.service' "$WHISPER_RECORD_UNIT" &&
   grep -Fqx 'Requisite=labwc-session.target' "$WHISPER_RECORD_UNIT" &&
   grep -Fq '/usr/bin/systemctl --user --quiet is-active labwc-session.target' "$WHISPER_RECORD_UNIT" &&
   grep -Fqx 'ExecStart=/usr/bin/timeout --foreground --signal=INT --kill-after=1s 15s /usr/local/libexec/whisper-record-toggle record-worker' "$WHISPER_RECORD_UNIT" &&
   grep -Fqx 'ExecStopPost=/usr/local/libexec/whisper-record-toggle finalize-recording' "$WHISPER_RECORD_UNIT" &&
   grep -Fqx 'SuccessExitStatus=1 124' "$WHISPER_RECORD_UNIT" &&
   grep -Fqx 'TimeoutStopSec=5s' "$WHISPER_RECORD_UNIT" &&
   grep -Fqx 'Requisite=labwc-session.target' "$WHISPER_SERVER_UNIT" &&
   grep -Fqx 'StartLimitIntervalSec=10min' "$WHISPER_SERVER_UNIT" &&
   grep -Fqx 'StartLimitBurst=3' "$WHISPER_SERVER_UNIT" &&
   grep -Fq '/usr/bin/systemctl --user --quiet is-active labwc-session.target' "$WHISPER_SERVER_UNIT" &&
   grep -Fqx 'Restart=on-failure' "$WHISPER_SERVER_UNIT" &&
   grep -Fqx 'RestartSec=5s' "$WHISPER_SERVER_UNIT" &&
   grep -Fqx 'TimeoutStopSec=5s' "$WHISPER_SERVER_UNIT" &&
   grep -Fqx 'NoNewPrivileges=false' "$WHISPER_SERVER_UNIT" &&
   ! grep -Fqx 'NoNewPrivileges=yes' "$WHISPER_SERVER_UNIT" &&
   grep -Fqx 'Requisite=labwc-session.target' "$WHISPER_TRANSCRIBE_UNIT" &&
   grep -Fq '/usr/bin/systemctl --user --quiet is-active labwc-session.target' "$WHISPER_TRANSCRIBE_UNIT" &&
   grep -Fqx 'Type=exec' "$WHISPER_TRANSCRIBE_UNIT" &&
   grep -Fqx 'TimeoutStartSec=15s' "$WHISPER_TRANSCRIBE_UNIT" &&
   grep -Fqx 'RuntimeMaxSec=30min' "$WHISPER_TRANSCRIBE_UNIT" &&
   grep -Fqx 'TimeoutStopSec=5s' "$WHISPER_TRANSCRIBE_UNIT" &&
   grep -Fqx 'KillSignal=SIGTERM' "$WHISPER_TRANSCRIBE_UNIT" &&
   grep -Fqx 'KillMode=control-group' "$WHISPER_TRANSCRIBE_UNIT" &&
   grep -Fq '$self->wait_inactive($self->record_service(), 50)' "$MODULE_ROOT/WhisperMode/Systemd.pm" &&
   grep -Fq 'recording service did not stop within 5 seconds' "$MODULE_ROOT/WhisperMode/Systemd.pm" &&
   ! grep -Eq '^(SuccessExitStatus|Type=oneshot|TimeoutStartSec=30min)=' "$WHISPER_TRANSCRIBE_UNIT" &&
   ! grep -Eq '^(PrivateTmp|ProtectSystem)=' "$WHISPER_TRANSCRIBE_UNIT" &&
   ! grep -Eq '^(PrivateTmp|ProtectSystem)=' "$WHISPER_SERVER_UNIT"; then
  pass "Whisper preserves runtime ceilings and permits its narrower AppArmor child transitions"
else
  fail "Whisper preserves runtime ceilings and permits its narrower AppArmor child transitions"
fi

server_start_line=$(
  grep -nF 'ExecStart=/usr/local/libexec/whisper-record-toggle server' \
    "$WHISPER_SERVER_UNIT" | cut -d: -f1 || true
)
server_ready_line=$(
  grep -nF 'ExecStartPost=/usr/local/libexec/whisper-record-toggle server-ready' \
    "$WHISPER_SERVER_UNIT" | cut -d: -f1 || true
)
if [ -n "$server_start_line" ] &&
   [ -n "$server_ready_line" ] &&
   [ "$server_ready_line" -gt "$server_start_line" ] &&
   grep -Fq 'server-enabled|server-ready|server]' "$MODULE_ROOT/WhisperMode/CLI.pm" &&
   grep -Fq "if (\$action eq 'server-ready') {" "$MODULE_ROOT/WhisperMode/Runtime.pm" &&
   grep -Fq '$self->_memory()->wait_until_ready();' "$MODULE_ROOT/WhisperMode/Runtime.pm" &&
   grep -Fqx 'TimeoutStartSec=2min' "$WHISPER_SERVER_UNIT"; then
  pass "Whisper server activation waits for the bounded server-ready action"
else
  fail "Whisper server activation waits for the bounded server-ready action"
fi

whisper_toggle_profile=$(
  awk '
    /^profile managed-whisper-record-toggle / { in_profile = 1 }
    in_profile { print }
    in_profile && /^}$/ { exit }
  ' "$APPARMOR_PROFILE"
)
if assert_contains '#include <abstractions/managed-wrapper-perl>' "$APPARMOR_PROFILE" &&
   assert_contains 'profile managed-whisper-cli-default-model /usr/local/libexec/whisper-cli-default-model flags=(attach_disconnected) {' "$APPARMOR_PROFILE" &&
   printf '%s\n' "$whisper_toggle_profile" |
     grep -Fqx '  /usr/local/bin/whisper-server rCx -> whisper-server,' &&
   printf '%s\n' "$whisper_toggle_profile" |
     grep -Fqx '  /data/whisper/bin/whisper-server rCx -> whisper-server,' &&
   printf '%s\n' "$whisper_toggle_profile" |
     grep -Fqx '  /usr/bin/curl rCx -> whisper-http-client,' &&
   printf '%s\n' "$whisper_toggle_profile" |
     grep -Fqx '  /usr/bin/pw-record rCx -> whisper-record,' &&
   printf '%s\n' "$whisper_toggle_profile" |
     grep -Fqx '  profile whisper-server flags=(attach_disconnected) {' &&
   printf '%s\n' "$whisper_toggle_profile" |
     grep -Fqx '    @{PROC}/devices r,' &&
   printf '%s\n' "$whisper_toggle_profile" |
     grep -Fqx '    @{PROC}/sys/vm/mmap_min_addr r,' &&
   grep -Fqx '  @{PROC}/devices r,' "$WHISPER_APPARMOR_PROFILE" &&
   grep -Fqx '  @{PROC}/sys/vm/mmap_min_addr r,' "$WHISPER_APPARMOR_PROFILE" &&
   grep -Fqx '/usr/local/cuda-*/targets/x86_64-linux/lib/lib{cublas,cublasLt,cudart}.so* mr,' "$GRAPHICS_ABSTRACTION" &&
   ! grep -Eq '/usr/local/cuda-[0-9]+([.][0-9]+)+/' "$GRAPHICS_ABSTRACTION" &&
   assert_contains 'owner @{HOME}/** r,' "$APPARMOR_PROFILE" &&
   assert_contains '/usr/local/lib/perl5/site_perl/whisper/** r,' "$APPARMOR_PROFILE" &&
   printf '%s\n' "$whisper_toggle_profile" |
     grep -Fqx '  owner /run/user/[0-9]*/whisper-record-toggle.{lock,recording,state} rwk,' &&
   assert_contains "\$programname == \"whisper-record-toggle\"" "$RSYSLOG_ROUTE" &&
   assert_contains "\$programname == \"systemd\"" "$RSYSLOG_ROUTE" &&
   assert_contains "\$msg contains \"whisper-record.service\"" "$RSYSLOG_ROUTE" &&
   assert_contains "\$msg contains \"whisper-transcribe.service\"" "$RSYSLOG_ROUTE" &&
   assert_contains "\$msg contains \"whisper-server.service\"" "$RSYSLOG_ROUTE" &&
   assert_contains "\$msg contains \"whisper-local-transcription\"" "$RSYSLOG_ROUTE" &&
   assert_contains 'file="/var/log/managed/whisper/whisper.log"' "$RSYSLOG_ROUTE" &&
   grep -Fqx 'd /var/log/managed/whisper 0750 root adm -' "$TMPFILES_LOGS" &&
   grep -Fqx 'f /var/log/managed/whisper/whisper.log 0640 root adm -' "$TMPFILES_LOGS" &&
   grep -Fqx '/var/log/managed/whisper/whisper.log' "$LOGROTATE_POLICY" &&
   assert_contains 'etc/rsyslog.d/37-whisper.conf' "$DESKTOP_COMPONENTS" &&
   assert_contains 'etc/logrotate.d/whisper' "$DESKTOP_COMPONENTS" &&
   for whisper_unit in \
     "$MUTE_DEFAULT_UNIT" \
     "$WHISPER_RECORD_UNIT" \
     "$WHISPER_SERVER_UNIT" \
     "$WHISPER_TRANSCRIBE_UNIT"
   do
     grep -Fqx 'SyslogIdentifier=whisper-record-toggle' "$whisper_unit" &&
       grep -Fqx 'StandardOutput=journal' "$whisper_unit" &&
       grep -Fqx 'StandardError=journal' "$whisper_unit" ||
       exit 1
   done; then
  pass "Whisper helpers and units route bounded diagnostics through rsyslog with managed retention"
else
  fail "Whisper helpers and units route bounded diagnostics through rsyslog with managed retention"
fi

write_perl_compatibility_modules
module_compile_ok=true
while IFS= read -r module; do
  if ! compile_mode_payload "$module"; then
    module_compile_ok=false
    break
  fi
done <"$expected_modules"
if [ "$module_compile_ok" = true ] &&
   compile_perl_entrypoint "$MUTE_DEFAULT_HELPER" &&
   compile_perl_entrypoint "$WHISPER_CLI_WRAPPER"; then
  pass "all canonical WhisperMode modules, microphone helper, and default-model CLI wrapper compile"
else
  fail "all canonical WhisperMode modules, microphone helper, and default-model CLI wrapper compile"
fi

fake_whisper_cli="$TMP_DIR/whisper-cli-real"
fake_whisper_server="$TMP_DIR/whisper-server-real"
fake_whisper_model="$TMP_DIR/ggml-managed-model.bin"
fake_whisper_config="$TMP_DIR/whisper.conf"
fake_whisper_cli_log="$TMP_DIR/whisper-cli.log"
cat >"$fake_whisper_cli" <<'EOF'
#!/bin/sh
set -eu
: "${WHISPER_TEST_CLI_LOG:?}"
printf '%s\n' "$*" >>"$WHISPER_TEST_CLI_LOG"

output_file=
while [ "$#" -gt 0 ]; do
  if [ "$1" = --output-file ]; then
    shift
    [ "$#" -gt 0 ] || exit 64
    output_file=$1
  fi
  shift
done
if [ -n "${WHISPER_TEST_TRANSCRIPT_JSON:-}" ]; then
  [ -n "$output_file" ] || exit 65
  printf '%s\n' "$WHISPER_TEST_TRANSCRIPT_JSON" >"${output_file}.json"
fi
EOF
cat >"$fake_whisper_server" <<'EOF'
#!/bin/sh
set -eu
[ -z "${WHISPER_TEST_SERVER_LOG:-}" ] || printf '%s\n' "$*" >"$WHISPER_TEST_SERVER_LOG"
exit 0
EOF
chmod 0755 "$fake_whisper_cli" "$fake_whisper_server"
: >"$fake_whisper_model"
cat >"$fake_whisper_config" <<EOF
WHISPER_CLI=$fake_whisper_cli
WHISPER_SERVER=$fake_whisper_server
WHISPER_SERVER_PORT=59178
WHISPER_MODEL=$fake_whisper_model
WHISPER_RUNTIME_THREADS=2
WHISPER_PERSISTENT_MEM=0
EOF
chmod 0600 "$fake_whisper_config"

if WHISPER_CONFIG_FILE="$fake_whisper_config" \
     WHISPER_TEST_CLI_LOG="$fake_whisper_cli_log" \
     PERL5LIB="$PERL_STUB_ROOT:$MODULE_ROOT" \
     /usr/bin/perl "$WHISPER_CLI_WRAPPER" "$TMP_DIR/input.wav" &&
   WHISPER_CONFIG_FILE="$fake_whisper_config" \
     WHISPER_TEST_CLI_LOG="$fake_whisper_cli_log" \
     PERL5LIB="$PERL_STUB_ROOT:$MODULE_ROOT" \
     /usr/bin/perl "$WHISPER_CLI_WRAPPER" --model "$TMP_DIR/alternate.bin" "$TMP_DIR/input.wav" &&
   WHISPER_CONFIG_FILE="$fake_whisper_config" \
     WHISPER_TEST_CLI_LOG="$fake_whisper_cli_log" \
     PERL5LIB="$PERL_STUB_ROOT:$MODULE_ROOT" \
     /usr/bin/perl "$WHISPER_CLI_WRAPPER" -mc 64 "$TMP_DIR/input.wav" &&
   [ "$(sed -n '1p' "$fake_whisper_cli_log")" = "--model $fake_whisper_model $TMP_DIR/input.wav" ] &&
   [ "$(sed -n '2p' "$fake_whisper_cli_log")" = "--model $TMP_DIR/alternate.bin $TMP_DIR/input.wav" ] &&
   [ "$(sed -n '3p' "$fake_whisper_cli_log")" = "--model $fake_whisper_model -mc 64 $TMP_DIR/input.wav" ] &&
   [ "$(wc -l <"$fake_whisper_cli_log")" -eq 3 ]; then
  pass "whisper-cli injects the installed model only when the user did not select one"
else
  fail "whisper-cli injects the installed model only when the user did not select one"
fi

cat >"$TMP_DIR/config-owner.pl" <<'EOF'
use strict;
use warnings;

use WhisperMode::Config;

my $untrusted_uid = $< == 0 ? 1 : $< + 1;
WhisperMode::Config::_configuration_owner_is_trusted(0)
    or die "root-owned configuration was rejected\n";
WhisperMode::Config::_configuration_owner_is_trusted($<)
    or die "active-user-owned configuration was rejected\n";
!WhisperMode::Config::_configuration_owner_is_trusted($untrusted_uid)
    or die "unrelated configuration owner was accepted\n";
EOF

if PERL5LIB="$PERL_STUB_ROOT:$MODULE_ROOT" \
     /usr/bin/perl "$TMP_DIR/config-owner.pl"; then
  pass "Whisper accepts root or active-user configuration ownership and rejects unrelated owners"
else
  fail "Whisper accepts root or active-user configuration ownership and rejects unrelated owners"
fi

cat >"$TMP_DIR/server-command.pl" <<'EOF'
use strict;
use warnings;

BEGIN {
    package WhisperMode::Logger;
    sub import {
        my ($class, @symbols) = @_;
        my $caller = caller;
        no strict 'refs';
        *{"${caller}::log_msg"} = sub { return; };
    }
    $INC{'WhisperMode/Logger.pm'} = 1;
}

use WhisperMode::Memory;

{
    package TestServerConfig;
    sub persistent_memory_enabled { return 1; }
    sub thread_count { return 2; }
    sub value {
        my ($self, $key) = @_;
        return $ENV{WHISPER_TEST_SERVER} if $key eq 'WHISPER_SERVER';
        return $ENV{WHISPER_TEST_MODEL} if $key eq 'WHISPER_MODEL';
        return $ENV{WHISPER_TEST_SERVER_PORT} if $key eq 'WHISPER_SERVER_PORT';
        die "unexpected Whisper configuration key: $key\n";
    }
}

WhisperMode::Memory->new(
    config  => bless({}, 'TestServerConfig'),
    systemd => bless({}, 'TestServerSystemd'),
)->run_server();
EOF

if WHISPER_TEST_SERVER="$fake_whisper_server" \
     WHISPER_TEST_MODEL="$fake_whisper_model" \
     WHISPER_TEST_SERVER_PORT=59178 \
     WHISPER_TEST_SERVER_LOG="$TMP_DIR/server-command.log" \
     PERL5LIB="$PERL_STUB_ROOT:$MODULE_ROOT" \
     /usr/bin/perl "$TMP_DIR/server-command.pl" \
       >"$TMP_DIR/server-command.stdout" 2>"$TMP_DIR/server-command.stderr" &&
   [ ! -s "$TMP_DIR/server-command.stdout" ] &&
   [ ! -s "$TMP_DIR/server-command.stderr" ] &&
   [ "$(cat "$TMP_DIR/server-command.log")" = "--host 127.0.0.1 --port 59178 --model $fake_whisper_model --threads 2 --no-timestamps" ]; then
  pass "Whisper server launch uses the configured non-CrowdSec loopback port"
else
  fail "Whisper server launch uses the configured non-CrowdSec loopback port"
fi

fake_ready_curl="$TMP_DIR/curl-ready"
cat >"$fake_ready_curl" <<'EOF'
#!/bin/sh
set -eu

: "${WHISPER_TEST_CURL_COUNTER:?}"
: "${WHISPER_TEST_CURL_LOG:?}"
: "${WHISPER_TEST_CURL_READY_AFTER:?}"

count=0
if [ -r "$WHISPER_TEST_CURL_COUNTER" ]; then
  IFS= read -r count <"$WHISPER_TEST_CURL_COUNTER"
fi
case "$count" in
  ''|*[!0-9]*) exit 64 ;;
esac
count=$((count + 1))
printf '%s\n' "$count" >"$WHISPER_TEST_CURL_COUNTER"
printf '%s\n' "$*" >>"$WHISPER_TEST_CURL_LOG"
[ "$count" -ge "$WHISPER_TEST_CURL_READY_AFTER" ]
EOF
chmod 0755 "$fake_ready_curl"

cat >"$TMP_DIR/server-ready-success.pl" <<'EOF'
use strict;
use warnings;

BEGIN {
    package WhisperMode::Logger;
    sub import {
        my ($class, @symbols) = @_;
        my $caller = caller;
        no strict 'refs';
        *{"${caller}::log_msg"} = sub { return; };
    }
    $INC{'WhisperMode/Logger.pm'} = 1;
}

use WhisperMode::Memory;

{
    package TestReadyConfig;
    sub persistent_memory_enabled { return 1; }
    sub value {
        my ($self, $key) = @_;
        $key eq 'WHISPER_SERVER_PORT' or die "unexpected Whisper configuration key: $key\n";
        return 59178;
    }
}

WhisperMode::Memory->new(
    config                       => bless({}, 'TestReadyConfig'),
    systemd                      => bless({}, 'TestReadySystemd'),
    curl_binary                  => $ENV{WHISPER_TEST_CURL},
    server_ready_retry_seconds   => 0,
    server_ready_timeout_seconds => 5,
)->wait_until_ready();
EOF

expected_ready_args='--disable --fail --silent --output /dev/null --noproxy * --proto =http --connect-timeout 1 --max-time 2 http://127.0.0.1:59178/health'
if WHISPER_TEST_CURL="$fake_ready_curl" \
     WHISPER_TEST_CURL_COUNTER="$TMP_DIR/server-ready-success.counter" \
     WHISPER_TEST_CURL_LOG="$TMP_DIR/server-ready-success.log" \
     WHISPER_TEST_CURL_READY_AFTER=3 \
     PERL5LIB="$PERL_STUB_ROOT:$MODULE_ROOT" \
     /usr/bin/perl "$TMP_DIR/server-ready-success.pl" \
       >"$TMP_DIR/server-ready-success.stdout" 2>"$TMP_DIR/server-ready-success.stderr" &&
   [ ! -s "$TMP_DIR/server-ready-success.stdout" ] &&
   [ ! -s "$TMP_DIR/server-ready-success.stderr" ] &&
   [ "$(cat "$TMP_DIR/server-ready-success.counter")" -eq 3 ] &&
   [ "$(wc -l <"$TMP_DIR/server-ready-success.log")" -eq 3 ] &&
   [ "$(LC_ALL=C sort -u "$TMP_DIR/server-ready-success.log")" = "$expected_ready_args" ]; then
  pass "Whisper server readiness retries bounded direct loopback health probes until success"
else
  fail "Whisper server readiness retries bounded direct loopback health probes until success"
fi

cat >"$TMP_DIR/server-ready-timeout.pl" <<'EOF'
use strict;
use warnings;

BEGIN {
    package WhisperMode::Logger;
    sub import {
        my ($class, @symbols) = @_;
        my $caller = caller;
        no strict 'refs';
        *{"${caller}::log_msg"} = sub { return; };
    }
    $INC{'WhisperMode/Logger.pm'} = 1;
}

use WhisperMode::Memory;

{
    package TestReadyConfig;
    sub persistent_memory_enabled { return 1; }
    sub value {
        my ($self, $key) = @_;
        $key eq 'WHISPER_SERVER_PORT' or die "unexpected Whisper configuration key: $key\n";
        return 59178;
    }
}

my $ready = eval {
    WhisperMode::Memory->new(
        config                       => bless({}, 'TestReadyConfig'),
        systemd                      => bless({}, 'TestReadySystemd'),
        curl_binary                  => $ENV{WHISPER_TEST_CURL},
        server_ready_retry_seconds   => 0,
        server_ready_timeout_seconds => 0,
    )->wait_until_ready();
    1;
};
!$ready && $@ =~ /Whisper server did not become ready before the startup deadline/
    or die "server readiness did not fail at its bounded deadline\n";
EOF

if WHISPER_TEST_CURL="$fake_ready_curl" \
     WHISPER_TEST_CURL_COUNTER="$TMP_DIR/server-ready-timeout.counter" \
     WHISPER_TEST_CURL_LOG="$TMP_DIR/server-ready-timeout.log" \
     WHISPER_TEST_CURL_READY_AFTER=999999 \
     PERL5LIB="$PERL_STUB_ROOT:$MODULE_ROOT" \
     /usr/bin/perl "$TMP_DIR/server-ready-timeout.pl" \
       >"$TMP_DIR/server-ready-timeout.stdout" 2>"$TMP_DIR/server-ready-timeout.stderr" &&
   [ ! -s "$TMP_DIR/server-ready-timeout.stdout" ] &&
   [ ! -s "$TMP_DIR/server-ready-timeout.stderr" ] &&
   [ "$(cat "$TMP_DIR/server-ready-timeout.counter")" -eq 1 ] &&
   [ "$(wc -l <"$TMP_DIR/server-ready-timeout.log")" -eq 1 ] &&
   [ "$(cat "$TMP_DIR/server-ready-timeout.log")" = "$expected_ready_args" ]; then
  pass "Whisper server readiness fails after its monotonic startup deadline"
else
  fail "Whisper server readiness fails after its monotonic startup deadline"
fi

fake_inference_curl="$TMP_DIR/curl-inference"
cat >"$fake_inference_curl" <<'EOF'
#!/bin/sh
set -eu

: "${WHISPER_TEST_CURL_LOG:?}"
printf '%s\n' "$*" >"$WHISPER_TEST_CURL_LOG"

output=
while [ "$#" -gt 0 ]; do
  if [ "$1" = --output ]; then
    shift
    [ "$#" -gt 0 ] || exit 64
    output=$1
  fi
  shift
done
[ -n "$output" ] || exit 65
printf '%s\n' '{"status":"ok"}' >"$output"
EOF
chmod 0755 "$fake_inference_curl"

cat >"$TMP_DIR/persistent-inference.pl" <<'EOF'
use strict;
use warnings;

BEGIN {
    package WhisperMode::Logger;
    sub import {
        my ($class, @symbols) = @_;
        my $caller = caller;
        no strict 'refs';
        *{"${caller}::log_msg"} = sub { return; };
    }
    $INC{'WhisperMode/Logger.pm'} = 1;
}

use WhisperMode::Memory;

{
    package TestPersistentConfig;
    sub persistent_memory_enabled { return 1; }
    sub value {
        my ($self, $key) = @_;
        $key eq 'WHISPER_SERVER_PORT' or die "unexpected Whisper configuration key: $key\n";
        return 59178;
    }

    package TestPersistentSystemd;
    sub server_service { return 'whisper-server.service'; }
    sub is_active {
        my ($self, $service) = @_;
        $service eq 'whisper-server.service'
            or die "unexpected server service: $service\n";
        return 1;
    }
}

WhisperMode::Memory->new(
    config      => bless({}, 'TestPersistentConfig'),
    systemd     => bless({}, 'TestPersistentSystemd'),
    curl_binary => $ENV{WHISPER_TEST_CURL},
)->transcribe($ENV{WHISPER_TEST_WAV}, $ENV{WHISPER_TEST_OUTPUT});
EOF

persistent_wav="$TMP_DIR/persistent-input.wav"
persistent_output="$TMP_DIR/persistent-output.json"
printf '%s\n' 'RIFFtest' >"$persistent_wav"
expected_inference_args="--disable --fail --silent --show-error --noproxy * --proto =http --connect-timeout 10 --max-time 1800 --request POST --form file=@$persistent_wav;type=audio/wav --form response_format=json --output $persistent_output http://127.0.0.1:59178/inference"
if WHISPER_TEST_CURL="$fake_inference_curl" \
     WHISPER_TEST_CURL_LOG="$TMP_DIR/persistent-inference.log" \
     WHISPER_TEST_WAV="$persistent_wav" \
     WHISPER_TEST_OUTPUT="$persistent_output" \
     PERL5LIB="$PERL_STUB_ROOT:$MODULE_ROOT" \
     /usr/bin/perl "$TMP_DIR/persistent-inference.pl" \
       >"$TMP_DIR/persistent-inference.stdout" 2>"$TMP_DIR/persistent-inference.stderr" &&
   [ ! -s "$TMP_DIR/persistent-inference.stdout" ] &&
   [ ! -s "$TMP_DIR/persistent-inference.stderr" ] &&
   [ "$(cat "$TMP_DIR/persistent-inference.log")" = "$expected_inference_args" ] &&
   grep -Fqx '{"status":"ok"}' "$persistent_output"; then
  pass "persistent Whisper inference bypasses curlrc and proxies and posts only to loopback"
else
  fail "persistent Whisper inference bypasses curlrc and proxies and posts only to loopback"
fi

artifact_home="$TMP_DIR/artifact-home"
mkdir -m 0700 "$artifact_home"
cat >"$TMP_DIR/artifact-flow.pl" <<'EOF'
use strict;
use warnings;

use WhisperMode::Artifacts;

my $artifacts = WhisperMode::Artifacts->new(home => $ENV{WHISPER_TEST_HOME});
$artifacts->store_transcript('2026-08-11-12-26-55', "Review\tpackage");
$artifacts->append_task('2026-08-11-12-26-55', "  Review\tpackage\x{200b}  ");
EOF

if WHISPER_TEST_HOME="$artifact_home" \
     PERL5LIB="$PERL_STUB_ROOT:$MODULE_ROOT" \
     /usr/bin/perl "$TMP_DIR/artifact-flow.pl" &&
   grep -Fq '"text":"Review package"' \
     "$artifact_home/Music/Whisper/transcribed/2026-08-11-12-26-55.json" &&
   grep -Fqx '2026-08-11 Review package +whisper @voice source:2026-08-11-12-26-55' \
     "$artifact_home/Syncthing/sleek/whisper.txt"; then
  pass "completed transcripts are stored under Music and appended as valid Sleek todo.txt tasks"
else
  fail "completed transcripts are stored under Music and appended as valid Sleek todo.txt tasks"
fi

transcribe_home="$TMP_DIR/transcribe-home"
transcribe_runtime="$TMP_DIR/transcribe-runtime"
mkdir -m 0700 "$transcribe_home" "$transcribe_runtime"
cat >"$TMP_DIR/transcribe-flow.pl" <<'EOF'
use strict;
use warnings;

BEGIN {
    package WhisperMode::Logger;
    sub import {
        my ($class, @symbols) = @_;
        my $caller = caller;
        no strict 'refs';
        *{"${caller}::log_msg"} = sub { return; };
    }
    $INC{'WhisperMode/Logger.pm'} = 1;
}

use WhisperMode::Artifacts;
use WhisperMode::Config;
use WhisperMode::Transcriber;

{
    package TestTranscribeState;
    sub new {
        my ($class, $recording, $runtime_directory) = @_;
        return bless {
            cleared           => 0,
            recording         => $recording,
            runtime_directory => $runtime_directory,
        }, $class;
    }
    sub read { return $_[0]->{recording}; }
    sub runtime_directory { return $_[0]->{runtime_directory}; }
    sub clear {
        $_[0]->{cleared}++;
        $_[0]->{recording} = undef;
        return;
    }

    package TestTranscribeMemory;
    sub transcribe { die "persistent memory path was used unexpectedly\n"; }
}

my $artifacts = WhisperMode::Artifacts->new(home => $ENV{WHISPER_TEST_HOME});
my $paths = $artifacts->paths();
my $stem = '2026-08-12-13-22-26';
my $wav = "$paths->{audio}/$stem.wav";
open my $wav_fh, '>:raw', $wav or die "create WAV: $!\n";
print {$wav_fh} 'RIFF', ("\0" x 64) or die "write WAV: $!\n";
close $wav_fh or die "close WAV: $!\n";

my $state = TestTranscribeState->new(
    { stem => $stem, wav => $wav },
    $ENV{WHISPER_TEST_RUNTIME},
);
WhisperMode::Transcriber->new(
    artifacts => $artifacts,
    config    => WhisperMode::Config->new(path => $ENV{WHISPER_TEST_CONFIG}),
    memory    => bless({}, 'TestTranscribeMemory'),
    state     => $state,
)->transcribe_pending();
$state->{cleared} == 1 && !defined($state->{recording})
    or die "completed transcription did not clear runtime state\n";
EOF

if WHISPER_TEST_HOME="$transcribe_home" \
     WHISPER_TEST_RUNTIME="$transcribe_runtime" \
     WHISPER_TEST_CONFIG="$fake_whisper_config" \
     WHISPER_TEST_CLI_LOG="$TMP_DIR/transcribe-cli.log" \
     WHISPER_TEST_TRANSCRIPT_JSON='{"transcription":[{"text":"  Review\tpackage  "}]}' \
     PERL5LIB="$PERL_STUB_ROOT:$MODULE_ROOT" \
     /usr/bin/perl "$TMP_DIR/transcribe-flow.pl" &&
   grep -Fq '"text":"Review package"' \
     "$transcribe_home/Music/Whisper/transcribed/2026-08-12-13-22-26.json" &&
   grep -Fqx '2026-08-12 Review package +whisper @voice source:2026-08-12-13-22-26' \
     "$transcribe_home/Syncthing/sleek/whisper.txt" &&
   [ "$(wc -l <"$transcribe_home/Syncthing/sleek/whisper.txt")" -eq 1 ]; then
  pass "Whisper CLI JSON is normalized into one transcript and one valid Sleek todo.txt task"
else
  fail "Whisper CLI JSON is normalized into one transcript and one valid Sleek todo.txt task"
fi

cat >"$TMP_DIR/runtime-behavior.pl" <<'EOF'
use strict;
use warnings;

use WhisperMode::Recorder;
use WhisperMode::Runtime;
use WhisperMode::State;
use WhisperMode::Systemd;

{
    package TestSystemd;
    our @ISA = ('WhisperMode::Systemd');

    sub new {
        my ($class, %arguments) = @_;
        return bless {
            calls          => [],
            reset_status   => $arguments{reset_status} // 0,
            service_failed => $arguments{service_failed} // 0,
            session_active => exists($arguments{session_active})
                ? $arguments{session_active}
                : 1,
        }, $class;
    }

    sub _run {
        my ($self, @arguments) = @_;
        push @{$self->{calls}}, join("\0", @arguments);
        if (@arguments == 3
            && $arguments[0] eq '--quiet'
            && $arguments[1] eq 'is-active'
            && $arguments[2] eq $self->session_target()) {
            return $self->{session_active} ? 0 : 3;
        }
        if (@arguments == 3
            && $arguments[0] eq '--quiet'
            && $arguments[1] eq 'is-failed') {
            return $self->{service_failed} ? 0 : 1;
        }
        if (@arguments == 2 && $arguments[0] eq 'reset-failed') {
            return $self->{reset_status};
        }
        return 0;
    }
}

my $failed_systemd = TestSystemd->new(service_failed => 1);
$failed_systemd->start_transcription();
@{$failed_systemd->{calls}} == 5
    && $failed_systemd->{calls}[0] eq "--quiet\0is-active\0labwc-session.target"
    && $failed_systemd->{calls}[1] eq "--quiet\0is-failed\0whisper-transcribe.service"
    && $failed_systemd->{calls}[2] eq "reset-failed\0whisper-transcribe.service"
    && $failed_systemd->{calls}[3] eq "--quiet\0is-active\0labwc-session.target"
    && $failed_systemd->{calls}[4] eq "--no-block\0start\0whisper-transcribe.service"
    or die "failed transcription state was not reset before asynchronous start\n";

my $healthy_systemd = TestSystemd->new(service_failed => 0);
$healthy_systemd->start_transcription();
@{$healthy_systemd->{calls}} == 4
    && $healthy_systemd->{calls}[0] eq "--quiet\0is-active\0labwc-session.target"
    && $healthy_systemd->{calls}[1] eq "--quiet\0is-failed\0whisper-transcribe.service"
    && $healthy_systemd->{calls}[2] eq "--quiet\0is-active\0labwc-session.target"
    && $healthy_systemd->{calls}[3] eq "--no-block\0start\0whisper-transcribe.service"
    or die "healthy transcription service was reset unnecessarily\n";

my $stopping_systemd = TestSystemd->new(session_active => 0);
$stopping_systemd->start_transcription();
@{$stopping_systemd->{calls}} == 1
    && $stopping_systemd->{calls}[0] eq "--quiet\0is-active\0labwc-session.target"
    or die "transcription was started after the Labwc session began stopping\n";

my $reset_failure_systemd = TestSystemd->new(
    reset_status   => 256,
    service_failed => 1,
);
my $reset_succeeded = eval {
    $reset_failure_systemd->start_transcription();
    1;
};
!$reset_succeeded
    && $@ =~ /cannot reset failed state for whisper-transcribe\.service: exit status 1/
    && @{$reset_failure_systemd->{calls}} == 3
    or die "transcription reset failure was ignored\n";

{
    package TestStopSystemd;
    sub stop_recording { die "stop failed\n"; }

    package TestAudio;
    sub new { return bless { mute_values => [] }, shift; }
    sub set_default_source_muted {
        my ($self, $value) = @_;
        push @{$self->{mute_values}}, $value;
        return;
    }

    package TestState;
    sub read { return undef; }

    package TestArtifacts;
    sub validate_wav { return $_[1]->{wav}; }
}

my $audio = TestAudio->new();
my $recorder = WhisperMode::Recorder->new(
    artifacts => bless({}, 'TestArtifacts'),
    audio     => $audio,
    state     => bless({}, 'TestState'),
    systemd   => bless({}, 'TestStopSystemd'),
);
my $stopped = eval { $recorder->stop(); 1 };
!$stopped && $@ =~ /\Astop failed/
    or die "recorder stop failure was not preserved\n";
@{$audio->{mute_values}} == 1 && $audio->{mute_values}[0] == 1
    or die "microphone mute was not attempted after recorder stop failure\n";

{
    package TestDefaultMuteState;
    sub lock { return bless({}, 'TestDefaultMuteLock'); }

    package TestDefaultMuteSystemd;
    sub new { return bless { recording => $_[1] }, $_[0]; }
    sub is_active { return $_[0]->{recording}; }
    sub record_service { return 'whisper-record.service'; }

    package TestDefaultMuteAudio;
    sub new { return bless { mute_values => [] }, shift; }
    sub set_default_source_muted {
        my ($self, $value) = @_;
        push @{$self->{mute_values}}, $value;
        return 1;
    }

    package TestStartAudio;
    sub new { return bless { mute_values => [] }, shift; }
    sub set_default_source_muted {
        my ($self, $value) = @_;
        push @{$self->{mute_values}}, $value;
        die "whisper-record-toggle: no usable audio capture source became available\n"
            if $value == 0;
        return 1;
    }

    package TestStartState;
    sub new { return bless { writes => 0, clears => 0 }, shift; }
    sub read { return undef; }
    sub write { $_[0]->{writes}++; return; }
    sub clear { $_[0]->{clears}++; return; }

    package TestStartSystemd;
    sub new { return bless { starts => 0 }, shift; }
    sub is_active { return 0; }
    sub record_service { return 'whisper-record.service'; }
    sub start_recording { $_[0]->{starts}++; return; }

    package TestStartArtifacts;
    sub paths { return { audio => $ENV{WHISPER_TEST_AUDIO_DIRECTORY} }; }
    sub validate_wav { return $_[1]; }

    package TestPendingState;
    sub lock { return bless({}, 'TestPendingLock'); }
    sub read {
        return {
            stem => '2026-08-11-12-26-55',
            wav  => $ENV{WHISPER_TEST_PENDING_WAV},
        };
    }

    package TestPendingSystemd;
    sub new { return bless { starts => 0, stops => 0 }, shift; }
    sub is_active { return 0; }
    sub record_service { return 'whisper-record.service'; }
    sub stop_recording { $_[0]->{stops}++; return; }
    sub start_transcription { $_[0]->{starts}++; return; }

    package TestFinalizeState;
    sub new {
        return bless {
            recording => $_[1],
        }, $_[0];
    }
    sub lock { return bless({}, 'TestFinalizeLock'); }
    sub read { return $_[0]->{recording}; }
    sub clear { $_[0]->{recording} = undef; $_[0]->{clears}++; return; }

    package TestFinalizeArtifacts;
    sub validate_wav { return $_[1]->{wav}; }

    package TestFinalizeSystemd;
    sub new {
        return bless {
            starts         => 0,
            session_active => $_[1] // 1,
        }, $_[0];
    }
    sub is_active {
        my ($self, $unit) = @_;
        return $self->{session_active} if $unit eq $self->session_target();
        return 0;
    }
    sub record_service { return 'whisper-record.service'; }
    sub session_target { return 'labwc-session.target'; }
    sub start_transcription { $_[0]->{starts}++; return; }
}

my $start_state = TestStartState->new();
my $start_audio = TestStartAudio->new();
my $start_systemd = TestStartSystemd->new();
my $started = eval {
    WhisperMode::Recorder->new(
        artifacts => bless({}, 'TestStartArtifacts'),
        audio     => $start_audio,
        state     => $start_state,
        systemd   => $start_systemd,
    )->start();
    1;
};
!$started && $@ =~ /no usable audio capture source became available/ &&
    $start_state->{writes} == 0 && $start_systemd->{starts} == 0 &&
    @{$start_audio->{mute_values}} == 1 && $start_audio->{mute_values}[0] == 0
    or die "recorder created pending state or started without an available microphone\n";

my $default_mute_audio = TestDefaultMuteAudio->new();
WhisperMode::Runtime->new(
    audio => $default_mute_audio,
    state => bless({}, 'TestDefaultMuteState'),
    systemd => TestDefaultMuteSystemd->new(0),
)->run('mute-default-source');
@{$default_mute_audio->{mute_values}} == 1 && $default_mute_audio->{mute_values}[0] == 1
    or die "default session mute did not mute the microphone\n";

my $active_recording_audio = TestDefaultMuteAudio->new();
WhisperMode::Runtime->new(
    audio => $active_recording_audio,
    state => bless({}, 'TestDefaultMuteState'),
    systemd => TestDefaultMuteSystemd->new(1),
)->run('mute-default-source');
@{$active_recording_audio->{mute_values}} == 0
    or die "default session mute interrupted an active recording\n";

my $pending_wav = $ENV{WHISPER_TEST_PENDING_WAV};
open my $pending_handle, '>:raw', $pending_wav
    or die "create pending WAV: $!\n";
print {$pending_handle} 'RIFF', ("\0" x 64)
    or die "write pending WAV: $!\n";
close $pending_handle or die "close pending WAV: $!\n";

my $pending_audio = TestDefaultMuteAudio->new();
my $pending_systemd = TestPendingSystemd->new();
WhisperMode::Runtime->new(
    artifacts => bless({}, 'TestArtifacts'),
    audio => $pending_audio,
    state => bless({}, 'TestPendingState'),
    systemd => $pending_systemd,
)->run('toggle');
$pending_systemd->{starts} == 1
    && $pending_systemd->{stops} == 0
    && @{$pending_audio->{mute_values}} == 1
    && $pending_audio->{mute_values}[0] == 1
    or die "pending inactive recording was not remuted and transcribed\n";

my $finalize_wav = $ENV{WHISPER_TEST_FINALIZE_WAV};
open my $finalize_handle, '>:raw', $finalize_wav
    or die "create finalize WAV: $!\n";
print {$finalize_handle} 'RIFF', ("\0" x 64)
    or die "write finalize WAV: $!\n";
close $finalize_handle or die "close finalize WAV: $!\n";

my $finalize_audio = TestDefaultMuteAudio->new();
my $finalize_systemd = TestFinalizeSystemd->new();
WhisperMode::Runtime->new(
    artifacts => bless({}, 'TestFinalizeArtifacts'),
    audio => $finalize_audio,
    state => TestFinalizeState->new({
        stem => '2026-08-11-12-26-56',
        wav  => $finalize_wav,
    }),
    systemd => $finalize_systemd,
)->run('finalize-recording');
@{$finalize_audio->{mute_values}} == 1
    && $finalize_audio->{mute_values}[0] == 1
    && $finalize_systemd->{starts} == 1
    or die "automatic recording finalization did not mute and transcribe\n";

my $shutdown_audio = TestDefaultMuteAudio->new();
my $shutdown_systemd = TestFinalizeSystemd->new(0);
WhisperMode::Runtime->new(
    artifacts => bless({}, 'TestFinalizeArtifacts'),
    audio => $shutdown_audio,
    state => TestFinalizeState->new({
        stem => '2026-08-11-12-26-56',
        wav  => $finalize_wav,
    }),
    systemd => $shutdown_systemd,
)->run('finalize-recording');
@{$shutdown_audio->{mute_values}} == 1
    && $shutdown_audio->{mute_values}[0] == 1
    && $shutdown_systemd->{starts} == 0
    or die "inactive session-target finalization started a new transcription job\n";
EOF

if PERL5LIB="$PERL_STUB_ROOT:$MODULE_ROOT" \
     WHISPER_TEST_AUDIO_DIRECTORY="$TMP_DIR/recordings" \
     WHISPER_TEST_PENDING_WAV="$TMP_DIR/pending.wav" \
     WHISPER_TEST_FINALIZE_WAV="$TMP_DIR/finalize.wav" \
     /usr/bin/perl "$TMP_DIR/runtime-behavior.pl"; then
  pass "Whisper runtime handles microphone failures, pending retries, and shutdown-safe finalization"
else
  fail "Whisper runtime handles microphone failures, pending retries, and shutdown-safe finalization"
fi

if [ "$(grep -Fc '"format": "🔊 {volume}% {format_source}",' "$WAYBAR_TEMPLATE")" -eq 2 ] &&
   [ "$(grep -Fc '"format-muted": "🔇 {volume}% {format_source}",' "$WAYBAR_TEMPLATE")" -eq 2 ] &&
   [ "$(grep -Fc '"format-source": "<span color='\''#6dc4ed'\''></span> {volume}%",' "$WAYBAR_TEMPLATE")" -eq 2 ] &&
   [ "$(grep -Fc '"format-source-muted": "<span color='\''#ffb4a2'\''></span> {volume}%",' "$WAYBAR_TEMPLATE")" -eq 2 ] &&
   [ "$(grep -Fc '"max-volume": 120,' "$WAYBAR_TEMPLATE")" -eq 2 ] &&
   [ "$(grep -Fc '"on-scroll-up": "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+ --limit 1.2",' "$WAYBAR_TEMPLATE")" -eq 2 ] &&
   [ "$(grep -Fc '"on-click-right": "__INSTALLER_LABWC_WAYBAR_PULSEAUDIO_RIGHT_CLICK_COMMAND__",' "$WAYBAR_TEMPLATE")" -eq 2 ] &&
   ! grep -Fq '<span foreground=' "$WAYBAR_TEMPLATE" &&
   ! grep -Fq '⏺' "$WAYBAR_TEMPLATE"; then
  pass "both Waybar outputs show colorful microphone state and cap scroll increases at 120 percent"
else
  fail "both Waybar outputs show colorful microphone state and cap scroll increases at 120 percent"
fi

if assert_contains 'use WhisperMode::Audio;' "$MUTE_DEFAULT_HELPER" &&
   grep -Fqx '    default_source_attempts      => 120,' "$MUTE_DEFAULT_HELPER" &&
   grep -Fqx '    default_source_retry_seconds => 0.5,' "$MUTE_DEFAULT_HELPER" &&
   grep -Fqx '$audio->set_default_source_muted(1);' "$MUTE_DEFAULT_HELPER" &&
   grep -Fqx '$audio->set_available_sources_muted(1);' "$MUTE_DEFAULT_HELPER" &&
   grep -Fqx 'Description=Mute all microphones for the Labwc session' "$MUTE_DEFAULT_UNIT" &&
   grep -Fqx 'ConditionEnvironment=WAYLAND_DISPLAY' "$MUTE_DEFAULT_UNIT" &&
   grep -Fqx 'Requisite=labwc-session.target' "$MUTE_DEFAULT_UNIT" &&
   grep -Fqx 'Wants=pipewire.service pipewire-pulse.service wireplumber.service' "$MUTE_DEFAULT_UNIT" &&
   grep -Fqx 'After=labwc-session.target pipewire.service pipewire-pulse.service wireplumber.service' "$MUTE_DEFAULT_UNIT" &&
   grep -Fqx 'StartLimitIntervalSec=5min' "$MUTE_DEFAULT_UNIT" &&
   grep -Fqx 'StartLimitBurst=4' "$MUTE_DEFAULT_UNIT" &&
   grep -Fqx 'ExecCondition=/bin/sh -eu -c '\''[ -n "${WAYLAND_DISPLAY:-}" ] && [ -n "${XDG_RUNTIME_DIR:-}" ] && [ -S "${XDG_RUNTIME_DIR}/${WAYLAND_DISPLAY}" ] && /usr/bin/systemctl --user --quiet is-active labwc-session.target'\''' "$MUTE_DEFAULT_UNIT" &&
   grep -Fqx 'ExecStart=/usr/local/libexec/labwc-mute-default-microphone' "$MUTE_DEFAULT_UNIT" &&
   grep -Fqx 'Restart=on-failure' "$MUTE_DEFAULT_UNIT" &&
   grep -Fqx 'RestartSec=1s' "$MUTE_DEFAULT_UNIT" &&
   grep -Fqx 'TimeoutStartSec=75s' "$MUTE_DEFAULT_UNIT" &&
   grep -Fqx 'SyslogIdentifier=whisper-record-toggle' "$MUTE_DEFAULT_UNIT" &&
   grep -Fqx 'StandardOutput=journal' "$MUTE_DEFAULT_UNIT" &&
   grep -Fqx 'StandardError=journal' "$MUTE_DEFAULT_UNIT" &&
   grep -Fqx 'WantedBy=labwc-session.target' "$MUTE_DEFAULT_UNIT" &&
   assert_contains 'profile managed-labwc-mute-default-microphone /usr/local/libexec/labwc-mute-default-microphone flags=(attach_disconnected) {' "$APPARMOR_PROFILE" &&
   assert_contains '/usr/local/lib/perl5/site_perl/whisper/WhisperMode/Audio.pm r,' "$APPARMOR_PROFILE" &&
   assert_contains '/usr/bin/wpctl ix,' "$APPARMOR_PROFILE" &&
   grep -Fqx 'Wants=pipewire.service wireplumber.service' "$PORTAL_WLR_UNIT" &&
   grep -Fqx 'After=labwc-session.target pipewire.service wireplumber.service' "$PORTAL_WLR_UNIT" &&
   grep -Fqx 'ExecCondition=/bin/sh -eu -c '\''[ -n "${WAYLAND_DISPLAY:-}" ] && [ -n "${XDG_RUNTIME_DIR:-}" ] && [ -S "${XDG_RUNTIME_DIR}/${WAYLAND_DISPLAY}" ] && /usr/bin/systemctl --user --quiet is-active labwc-session.target pipewire.service wireplumber.service'\''' "$PORTAL_WLR_UNIT" &&
   assert_contains 'usr/local/libexec/labwc-mute-default-microphone /usr/local/libexec/labwc-mute-default-microphone 0755' "$DESKTOP_COMPONENTS" &&
   assert_contains 'usr/local/lib/perl5/site_perl/whisper/WhisperMode/Audio.pm /usr/local/lib/perl5/site_perl/whisper/WhisperMode/Audio.pm 0644' "$DESKTOP_COMPONENTS" &&
   assert_contains 'etc/skel/.config/systemd/user/labwc-mute-default-microphone.service /etc/skel/.config/systemd/user/labwc-mute-default-microphone.service 0644' "$DESKTOP_COMPONENTS" &&
   assert_contains '    labwc-mute-default-microphone.service \' "$DESKTOP_COMPONENTS" &&
   ! grep -Fq -- 'whisper-mute-default.service' "$DESKTOP_COMPONENTS" &&
   ! [ -e "$OBSOLETE_MUTE_DEFAULT_UNIT" ]; then
  pass "the Labwc session mutes every usable microphone without blocking compositor login"
else
  fail "the Labwc session mutes every usable microphone without blocking compositor login"
fi

if assert_contains 'alsa-ucm-conf' "$DESKTOP_PACKAGE_CFG" &&
   grep -Fqx '  alsa.use-ucm = true' "$WIREPLUMBER_AUDIO_POLICY" &&
   grep -Fqx '  device.restore-routes = false' "$WIREPLUMBER_AUDIO_POLICY" &&
   grep -Fqx '  device.routes.default-source-volume = 0.8' "$WIREPLUMBER_AUDIO_POLICY" &&
   grep -Fqx '  node.restore-default-targets = false' "$WIREPLUMBER_AUDIO_POLICY" &&
   grep -Fqx '        node.disabled = true' "$WIREPLUMBER_AUDIO_POLICY" &&
   [ "$(grep -Fc 'node.name = "~.*[Hh][Dd][Mm][Ii].*"' "$WIREPLUMBER_AUDIO_POLICY")" -eq 1 ] &&
   [ "$(grep -Fc 'node.description = "~.*[Hh][Dd][Mm][Ii].*"' "$WIREPLUMBER_AUDIO_POLICY")" -eq 1 ] &&
   [ "$(grep -Fc '[Dd][Ii][Ss][Pp][Ll][Aa][Yy][._ -]?[Pp][Oo][Rr][Tt]' "$WIREPLUMBER_AUDIO_POLICY")" -eq 2 ] &&
   grep -Fqx '        api.acp.max-volume = 1.2' "$WIREPLUMBER_AUDIO_POLICY" &&
   cmp -s "$WIREPLUMBER_AUDIO_POLICY" "$WIREPLUMBER_SKEL_AUDIO_POLICY" &&
   grep -Fqx '  channelmix.max-volume = 1.2' "$PIPEWIRE_CLIENT_VOLUME_POLICY" &&
   grep -Fqx '  channelmix.max-volume = 1.2' "$PIPEWIRE_PULSE_VOLUME_POLICY" &&
   assert_contains 'etc/wireplumber/wireplumber.conf.d/20-managed-audio-policy.conf /etc/wireplumber/wireplumber.conf.d/20-managed-audio-policy.conf 0644' "$DESKTOP_COMPONENTS" &&
   assert_contains 'etc/pipewire/client.conf.d/20-managed-volume-ceiling.conf /etc/pipewire/client.conf.d/20-managed-volume-ceiling.conf 0644' "$DESKTOP_COMPONENTS" &&
   assert_contains 'etc/pipewire/pipewire-pulse.conf.d/20-managed-volume-ceiling.conf /etc/pipewire/pipewire-pulse.conf.d/20-managed-volume-ceiling.conf 0644' "$DESKTOP_COMPONENTS"; then
  pass "desktop audio policy rejects restored sources, disables HDMI and DisplayPort nodes, and bounds analog volume"
else
  fail "desktop audio policy rejects restored sources, disables HDMI and DisplayPort nodes, and bounds analog volume"
fi

cat >"$TMP_DIR/wpctl" <<'EOF'
#!/bin/sh
set -eu

: "${WHISPER_TEST_WPCTL_COUNTER:?}"
: "${WHISPER_TEST_WPCTL_LOG:?}"
: "${WHISPER_TEST_WPCTL_MODE:?}"

printf '%s\n' "$*" >>"$WHISPER_TEST_WPCTL_LOG"
case "$1" in
  get-volume)
    count=0
    if [ -r "$WHISPER_TEST_WPCTL_COUNTER" ]; then
      count=$(cat "$WHISPER_TEST_WPCTL_COUNTER")
    fi
    count=$((count + 1))
    printf '%s\n' "$count" >"$WHISPER_TEST_WPCTL_COUNTER"
    printf '%s\n' "Translate ID error: '-1' is not a valid ID" >&2
    exit 3
    ;;
  list)
    exit 64
    ;;
  status)
    [ "$2" = --name ]
    case "$WHISPER_TEST_WPCTL_MODE" in
      fallback)
        cat <<'STATUS'
PipeWire 'pipewire-0'
Audio
 ├─ Devices:
 │      30. alsa_card.pci-0000_00_1f.3
 │
 ├─ Sinks:
 │  *   31. alsa_output.pci-0000_00_1f.3.analog-stereo [vol: 0.50]
 │
 ├─ Sources:
 │  *   51. alsa_input.usb-Generic_USB_Audio-00.mono-fallback [vol: 0.50]
 │      42. alsa_input.pci-0000_00_1f.3.analog-stereo [vol: 0.80]
 │      60. alsa_output.pci-0000_00_1f.3.analog-stereo.monitor [vol: 0.50]
 │      61. alsa_input.pci-0000_01_00.1.hdmi-stereo [vol: 0.50]
 │      62. DisplayPort capture [vol: 0.50]
 │
 ├─ Filters:
 │
Video
 ├─ Devices:
STATUS
        ;;
      missing)
        cat <<'STATUS'
PipeWire 'pipewire-0'
Audio
 ├─ Sources:
 │      60. alsa_output.pci-0000_00_1f.3.analog-stereo.monitor [vol: 0.50]
 │      61. alsa_input.pci-0000_01_00.1.hdmi-stereo [vol: 0.50]
 │
 ├─ Filters:
STATUS
        ;;
      *)
        exit 64
        ;;
    esac
    ;;
  set-default)
    [ "$WHISPER_TEST_WPCTL_MODE" = fallback ]
    [ "$2" = 42 ]
    ;;
  set-mute)
    [ "$WHISPER_TEST_WPCTL_MODE" = fallback ]
    case "$2" in
      42|51) ;;
      *) exit 65 ;;
    esac
    case "$3" in
      0|1) ;;
      *) exit 66 ;;
    esac
    ;;
  *)
    exit 64
    ;;
esac
EOF
chmod 0755 "$TMP_DIR/wpctl"

cat >"$TMP_DIR/default-source-wait.pl" <<'EOF'
use strict;
use warnings;

use WhisperMode::Audio;

my $audio = WhisperMode::Audio->new(
    default_source_attempts      => 3,
    default_source_retry_seconds => 0,
    wpctl_binary                 => $ENV{WHISPER_TEST_WPCTL},
);

$audio->set_default_source_muted(1) == 1
    or die "fallback microphone was not selected and muted\n";
$audio->set_available_sources_muted(1) == 2
    or die "all usable microphones were not muted\n";
EOF

mkdir -p "$TMP_DIR/recordings"
if WHISPER_TEST_WPCTL="$TMP_DIR/wpctl" \
     WHISPER_TEST_WPCTL_COUNTER="$TMP_DIR/wpctl.counter" \
     WHISPER_TEST_WPCTL_LOG="$TMP_DIR/wpctl.log" \
     WHISPER_TEST_WPCTL_MODE=fallback \
     PERL5LIB="$PERL_STUB_ROOT:$MODULE_ROOT" \
     /usr/bin/perl "$TMP_DIR/default-source-wait.pl" \
       >"$TMP_DIR/default-source-wait.stdout" 2>"$TMP_DIR/default-source-wait.stderr" &&
   [ ! -s "$TMP_DIR/default-source-wait.stdout" ] &&
   [ ! -s "$TMP_DIR/default-source-wait.stderr" ] &&
   ! grep -Fq 'get-volume @DEFAULT_AUDIO_SOURCE@' "$TMP_DIR/wpctl.log" &&
   ! grep -Fq 'list audio sources' "$TMP_DIR/wpctl.log" &&
   [ "$(grep -Fc 'status --name' "$TMP_DIR/wpctl.log")" -eq 2 ] &&
   grep -Fqx 'set-default 42' "$TMP_DIR/wpctl.log" &&
   [ "$(grep -Fc 'set-mute 42 1' "$TMP_DIR/wpctl.log")" -eq 2 ] &&
   grep -Fqx 'set-mute 51 1' "$TMP_DIR/wpctl.log" &&
   ! grep -Eq '^set-(default|mute) (60|61|62)( |$)' "$TMP_DIR/wpctl.log"; then
  pass "Forky wpctl status selects internal capture and mutes every non-HDMI, non-monitor source"
else
  fail "Forky wpctl status selects internal capture and mutes every non-HDMI, non-monitor source"
fi

cat >"$TMP_DIR/pw-record" <<'EOF'
#!/bin/sh
set -eu

: "${WHISPER_TEST_PW_RECORD_LOG:?}"
printf '%s\n' "$*" >>"$WHISPER_TEST_PW_RECORD_LOG"
EOF
chmod 0755 "$TMP_DIR/pw-record"

cat >"$TMP_DIR/record-source.pl" <<'EOF'
use strict;
use warnings;

use WhisperMode::Audio;

WhisperMode::Audio->new(
    default_source_attempts       => 1,
    default_source_retry_seconds => 0,
    wpctl_binary                  => $ENV{WHISPER_TEST_WPCTL},
)->record($ENV{WHISPER_TEST_RECORDING});
EOF

recording_path="$TMP_DIR/recordings/capture.wav"
if WHISPER_TEST_WPCTL="$TMP_DIR/wpctl" \
     WHISPER_TEST_WPCTL_COUNTER="$TMP_DIR/record-source.counter" \
     WHISPER_TEST_WPCTL_LOG="$TMP_DIR/record-source.wpctl.log" \
     WHISPER_TEST_WPCTL_MODE=fallback \
     WHISPER_PW_RECORD_BIN="$TMP_DIR/pw-record" \
     WHISPER_TEST_PW_RECORD_LOG="$TMP_DIR/record-source.pw-record.log" \
     WHISPER_TEST_RECORDING="$recording_path" \
     PERL5LIB="$PERL_STUB_ROOT:$MODULE_ROOT" \
     /usr/bin/perl "$TMP_DIR/record-source.pl" \
       >"$TMP_DIR/record-source.stdout" 2>"$TMP_DIR/record-source.stderr" &&
   [ ! -s "$TMP_DIR/record-source.stdout" ] &&
   [ ! -s "$TMP_DIR/record-source.stderr" ] &&
   [ "$(sed -n '1p' "$TMP_DIR/record-source.wpctl.log")" = 'status --name' ] &&
   [ "$(sed -n '2p' "$TMP_DIR/record-source.wpctl.log")" = 'set-default 42' ] &&
   [ "$(sed -n '3p' "$TMP_DIR/record-source.wpctl.log")" = 'set-mute 42 0' ] &&
   [ "$(wc -l <"$TMP_DIR/record-source.wpctl.log")" -eq 3 ] &&
   grep -Fqx -- "--target=alsa_input.pci-0000_00_1f.3.analog-stereo --rate=16000 --channels=1 --format=s16 $recording_path" \
     "$TMP_DIR/record-source.pw-record.log"; then
  pass "Whisper unmutes the selected source and records from its stable PipeWire node name"
else
  fail "Whisper unmutes the selected source and records from its stable PipeWire node name"
fi

cat >"$TMP_DIR/no-default-source.pl" <<'EOF'
use strict;
use warnings;

use WhisperMode::Audio;

my $audio = WhisperMode::Audio->new(
    default_source_attempts      => 2,
    default_source_retry_seconds => 0,
    wpctl_binary                 => $ENV{WHISPER_TEST_WPCTL},
);

my $muted = eval { $audio->set_default_source_muted(1); 1 };
!$muted && $@ =~ /no usable audio capture source became available/
    or die "missing microphone did not fail the session mute operation\n";
EOF

if WHISPER_TEST_WPCTL="$TMP_DIR/wpctl" \
     WHISPER_TEST_WPCTL_COUNTER="$TMP_DIR/no-default-source.counter" \
     WHISPER_TEST_WPCTL_LOG="$TMP_DIR/no-default-source.log" \
     WHISPER_TEST_WPCTL_MODE=missing \
     PERL5LIB="$PERL_STUB_ROOT:$MODULE_ROOT" \
     /usr/bin/perl "$TMP_DIR/no-default-source.pl" \
       >"$TMP_DIR/no-default-source.stdout" 2>"$TMP_DIR/no-default-source.stderr" &&
   [ ! -s "$TMP_DIR/no-default-source.stdout" ] &&
   [ ! -s "$TMP_DIR/no-default-source.stderr" ] &&
   ! grep -Fq 'get-volume @DEFAULT_AUDIO_SOURCE@' "$TMP_DIR/no-default-source.log" &&
   ! grep -Fq 'list audio sources' "$TMP_DIR/no-default-source.log" &&
   [ "$(grep -Fc 'status --name' "$TMP_DIR/no-default-source.log")" -eq 2 ] &&
   ! grep -Fq 'set-mute ' "$TMP_DIR/no-default-source.log"; then
  pass "Whisper fails a startup mute with no microphone so systemd can retry"
else
  fail "Whisper fails a startup mute with no microphone so systemd can retry"
fi

if assert_contains 'desktop_waybar_pulseaudio_right_click_command() {' "$DESKTOP_COMPONENTS" &&
   assert_contains "  printf '/usr/bin/wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle'" "$DESKTOP_COMPONENTS" &&
   assert_contains '    <keybind key="W-r">' "$DESKTOP_COMPONENTS" &&
   assert_contains '    <keybind key="C-A-r">' "$DESKTOP_COMPONENTS" &&
   assert_contains '      <action name="Execute" command="/usr/local/libexec/whisper-record-toggle toggle" />' "$DESKTOP_COMPONENTS"; then
  pass "both recording shortcuts use Whisper while Waybar right-click only toggles microphone mute"
else
  fail "both recording shortcuts use Whisper while Waybar right-click only toggles microphone mute"
fi

if run_whisper --help >"$TMP_DIR/help.stdout" 2>"$TMP_DIR/help.stderr" &&
   grep -Fq 'usage: whisper-record-toggle' "$TMP_DIR/help.stderr"; then
  pass "canonical Perl entrypoint accepts its bounded help interface"
else
  fail "canonical Perl entrypoint accepts its bounded help interface"
fi

if ! run_whisper unsupported-action >"$TMP_DIR/invalid.stdout" 2>"$TMP_DIR/invalid.stderr" &&
   grep -Fq 'whisper-record-toggle: invalid action' "$TMP_DIR/invalid.stderr"; then
  pass "canonical Perl entrypoint rejects unknown actions before runtime dispatch"
else
  fail "canonical Perl entrypoint rejects unknown actions before runtime dispatch"
fi

if ! run_whisper start stop >"$TMP_DIR/multiple.stdout" 2>"$TMP_DIR/multiple.stderr" &&
   grep -Fq 'whisper-record-toggle: usage:' "$TMP_DIR/multiple.stderr"; then
  pass "canonical Perl entrypoint rejects multiple positional actions"
else
  fail "canonical Perl entrypoint rejects multiple positional actions"
fi

[ "$FAIL_COUNT" -eq 0 ]
