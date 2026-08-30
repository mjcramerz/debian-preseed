package LabwcNetworkScanAction::Command;

use strict;
use warnings;

use Fcntl qw(O_CREAT O_EXCL O_WRONLY);
use IPC::Open3 qw(open3);
use Moo;
use MooX::StrictConstructor;
use MooX::TypeTiny;
use Types::Standard qw(Int Str);

has capture_limit_bytes => (
    is      => 'ro',
    isa     => Int,
    default => sub { 1_048_576 },
);

has path => (
    is      => 'ro',
    isa     => Str,
    default => sub { $ENV{PATH} // '/usr/local/bin:/usr/bin:/bin' },
);

sub _status {
    my ($status) = @_;

    return 255 if !defined($status) || $status == -1;
    return 128 + ($status & 127) if $status & 127;
    return $status >> 8;
}

sub executable {
    my ($self, $name) = @_;

    defined($name) && $name =~ /\A[A-Za-z0-9][A-Za-z0-9+._-]*\z/
        or die "invalid executable name\n";
    for my $directory (split /:/, $self->path()) {
        next if $directory !~ m{\A/};
        my $candidate = "$directory/$name";
        return $candidate if -x $candidate && !-d $candidate;
    }
    return undef;
}

sub require_executable {
    my ($self, $name) = @_;

    my $program = $self->executable($name);
    defined($program)
        or die "required network scanning command is not installed: $name\n";
    return $program;
}

sub run {
    my ($self, @argv) = @_;

    @argv && defined($argv[0]) && $argv[0] ne q{}
        or die "cannot run an empty command\n";
    system { $argv[0] } @argv;
    return _status($?);
}

sub run_or_die {
    my ($self, $label, @argv) = @_;

    my $status = $self->run(@argv);
    $status == 0
        or die "$label failed with status $status\n";
    return;
}

sub exec {
    my ($self, @argv) = @_;

    @argv && defined($argv[0]) && $argv[0] ne q{}
        or die "cannot execute an empty command\n";
    CORE::exec { $argv[0] } @argv;
    die "cannot execute $argv[0]: $!\n";
}

sub capture {
    my ($self, %args) = @_;

    my $argv = $args{argv};
    ref($argv) eq 'ARRAY' && @{$argv}
        or die "capture requires a non-empty argv array\n";

    open my $null, '>', '/dev/null' or die "cannot open /dev/null: $!\n";
    my ($stdin, $stdout);
    my $pid = eval { open3($stdin, $stdout, $null, @{$argv}) };
    die "cannot execute $argv->[0]: $@\n" if !$pid;
    close $stdin or die "cannot close command input for $argv->[0]: $!\n";

    my $output = q{};
    while (1) {
        my $read = read $stdout, my $buffer, 65_536;
        defined($read)
            or die "cannot read command output for $argv->[0]: $!\n";
        last if $read == 0;
        length($output) + $read <= $self->capture_limit_bytes()
            or do {
                kill 'TERM', $pid;
                waitpid($pid, 0);
                die "command output for $argv->[0] exceeds the managed capture limit\n";
            };
        $output .= $buffer;
    }
    close $stdout or die "cannot close command output for $argv->[0]: $!\n";
    waitpid($pid, 0);
    return (_status($?), $output);
}

sub run_to_new_file {
    my ($self, $path, @argv) = @_;

    defined($path) && $path =~ m{\A/} && $path !~ /[\x00\r\n]/
        or die "capture output path must be a safe absolute path\n";
    @argv && defined($argv[0]) && $argv[0] ne q{}
        or die "cannot run an empty command\n";

    sysopen my $output, $path, O_WRONLY | O_CREAT | O_EXCL, 0600
        or die "cannot create capture file $path: $!\n";
    binmode $output;
    my $pid = fork();
    defined($pid)
        or die "cannot fork capture writer: $!\n";
    if ($pid == 0) {
        open STDOUT, '>&', $output
            or die "cannot redirect capture output: $!\n";
        close $output or die "cannot close capture output: $!\n";
        CORE::exec { $argv[0] } @argv;
        die "cannot execute $argv[0]: $!\n";
    }
    close $output or die "cannot close capture output: $!\n";
    waitpid($pid, 0);
    return _status($?);
}

1;
