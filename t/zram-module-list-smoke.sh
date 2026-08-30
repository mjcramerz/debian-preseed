#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/zram-module-list.XXXXXX")
trap 'rm -rf "$TMP_DIR"' EXIT HUP INT TERM

TEST_COUNT=3
TEST_INDEX=0

pass() {
  TEST_INDEX=$((TEST_INDEX + 1))
  printf 'ok %s - %s\n' "$TEST_INDEX" "$1"
}

fail() {
  TEST_INDEX=$((TEST_INDEX + 1))
  printf 'not ok %s - %s\n' "$TEST_INDEX" "$1"
  if [ "$#" -gt 1 ] && [ -n "${2:-}" ] && [ -r "$2" ]; then
    sed 's/^/# /' "$2"
  fi
}

printf '1..%s\n' "$TEST_COUNT"

expected="$TMP_DIR/expected.txt"
actual="$TMP_DIR/actual.txt"
diff_out="$TMP_DIR/diff.txt"

(
  CDPATH='' cd -- "$ROOT_DIR" &&
  find d-i/forky/hooks/shared/target/usr/local/lib/perl5/site_perl/zram-writeback -type f -name '*.pm' -print |
    sed 's#^d-i/forky/hooks/shared/target/usr/local/lib/perl5/site_perl/zram-writeback/##' |
    sort
) >"$expected"

(
  # shellcheck disable=SC1090
  . "$ROOT_DIR/d-i/forky/scripts/late/zram-swap.sh"
  zram_perl_modules | sed '/^[[:space:]]*$/d' | sort
) >"$actual"

if diff -u "$expected" "$actual" >"$diff_out"; then
  pass "zram staged Perl module list matches the runtime module tree"
else
  fail "zram staged Perl module list matches the runtime module tree" "$diff_out"
fi

runtime_module="$ROOT_DIR/d-i/forky/hooks/shared/target/usr/local/lib/perl5/site_perl/zram-writeback/Zram/Runtime.pm"
if grep -Fqx 'use Types::Standard qw(ArrayRef Str);' "$runtime_module" &&
   grep -Fqx '    isa     => \&_assert_non_empty_string,' "$runtime_module" &&
   ! grep -Fq 'NonEmptyStr' "$runtime_module"; then
  pass "zram runtime keeps a local non-empty action invariant without importing an unavailable Types::Standard symbol"
else
  fail "zram runtime keeps a local non-empty action invariant without importing an unavailable Types::Standard symbol" "$runtime_module"
fi

stub_root="$TMP_DIR/perl-stubs"
mkdir -p "$stub_root/MooX" "$stub_root/Types" "$stub_root/Zram"
cat >"$stub_root/Moo.pm" <<'EOF'
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
        my %specification = @arguments;
        $attributes{$name} = \%specification;
        *{"${caller}::${name}"} = sub { return $_[0]->{$name}; };
        return;
    };
    *{"${caller}::new"} = sub {
        my ($package, @arguments) = @_;
        my %values = @arguments;
        for my $name (keys %attributes) {
            my $specification = $attributes{$name};
            exists($values{$name}) || !$specification->{required}
                or die "$name is required\n";
            next if !exists($values{$name}) || ref($specification->{isa}) ne 'CODE';
            $specification->{isa}->($values{$name});
        }
        return bless \%values, $package;
    };
    return;
}

1;
EOF
for module in HandlesVia StrictConstructor TypeTiny; do
  cat >"$stub_root/MooX/$module.pm" <<EOF
package MooX::$module;
sub import { return; }
1;
EOF
done
cat >"$stub_root/Types/Standard.pm" <<'EOF'
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
cat >"$stub_root/Zram/Command.pm" <<'EOF'
package Zram::Command;
use Exporter qw(import);
our @EXPORT_OK = qw(dispatch requires_lock requires_sysfs);
sub dispatch { return 0; }
sub requires_lock { return 0; }
sub requires_sysfs { return 0; }
1;
EOF
cat >"$stub_root/Zram/Config.pm" <<'EOF'
package Zram::Config;
use Exporter qw(import);
our @EXPORT_OK = qw(validate_config);
sub new { return bless {}, shift; }
sub load { return; }
sub validate_config { return; }
1;
EOF
cat >"$stub_root/Zram/Lock.pm" <<'EOF'
package Zram::Lock;
use Exporter qw(import);
our @EXPORT_OK = qw(acquire_lock);
sub acquire_lock { return; }
1;
EOF

module_root="$ROOT_DIR/d-i/forky/hooks/shared/target/usr/local/lib/perl5/site_perl/zram-writeback"
if PERL5LIB="$stub_root:$module_root" \
     /usr/bin/perl -c "$runtime_module" >/dev/null 2>&1 &&
   PERL5LIB="$stub_root:$module_root" /usr/bin/perl -MZram::Runtime -e '
     eval { Zram::Runtime->new(config_path => "/tmp/test", action => ""); 1 }
       and exit 1;
     $@ =~ /action must be a non-empty string/ or exit 1;
     Zram::Runtime->new(config_path => "/tmp/test", action => "daemon");
   '; then
  pass "zram runtime compiles and rejects an empty action through the compatibility harness"
else
  fail "zram runtime compiles and rejects an empty action through the compatibility harness" "$runtime_module"
fi
