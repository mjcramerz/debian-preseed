package TimeshiftManaged::Command;

use strict;
use warnings;

use IPC::Open3 qw(open3);
use Moo;
use MooX::StrictConstructor;
use MooX::TypeTiny;
use Symbol qw(gensym);
use Types::Standard qw(ArrayRef Str);

sub status_from_wait {
    my ($status) = @_;

    return 255 if !defined($status) || $status == -1;
    return 128 + ($status & 127) if $status & 127;
    return $status >> 8;
}

sub run {
    my ($self, @argv) = @_;

    die "command is missing\n" if !@argv || !defined($argv[0]) || $argv[0] eq q{};
    system { $argv[0] } @argv;
    return status_from_wait($?);
}

sub capture {
    my ($self, %args) = @_;

    my $argv = $args{argv};
    ref($argv) eq 'ARRAY' && @{$argv}
        or die "capture requires a non-empty argv array\n";
    defined($argv->[0]) && $argv->[0] ne q{}
        or die "capture requires an executable argv[0]\n";

    open my $null, '>', '/dev/null' or die "cannot open /dev/null: $!\n";
    my ($stdin, $stdout);
    my $pid = eval {
        open3($stdin, $stdout, $null, @{$argv});
    };
    die "cannot execute $argv->[0]: $@\n" if !$pid;

    if (defined $args{input}) {
        print {$stdin} $args{input}
            or die "cannot write command input for $argv->[0]: $!\n";
    }
    close $stdin or die "cannot close command input for $argv->[0]: $!\n";

    local $/;
    my $output = <$stdout>;
    close $stdout or die "cannot close command output for $argv->[0]: $!\n";
    waitpid($pid, 0);

    return (status_from_wait($?), defined($output) ? $output : q{});
}

sub find_executable {
    my ($self, $name) = @_;

    defined($name) && $name =~ /\A[A-Za-z0-9][A-Za-z0-9+._-]*\z/
        or die "invalid executable name\n";
    for my $directory (qw(/usr/sbin /usr/bin /sbin /bin)) {
        my $candidate = "$directory/$name";
        return $candidate if -x $candidate && !-d $candidate;
    }
    return undef;
}

1;
