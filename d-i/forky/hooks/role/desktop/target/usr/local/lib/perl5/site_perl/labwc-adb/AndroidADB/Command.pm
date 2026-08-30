package AndroidADB::Command;

use strict;
use warnings;

use Errno qw(EINTR);
use Fcntl qw(O_CREAT O_EXCL O_NOFOLLOW O_TRUNC O_WRONLY);
use IO::Select;
use IPC::Open3 qw(open3);
use Moo;
use MooX::StrictConstructor;
use MooX::TypeTiny;
use POSIX ();
use Symbol qw(gensym);
use Types::Standard qw(Int Object);

use AndroidADB::Validation qw(fail require_value);

has config => (
    is       => 'ro',
    isa      => Object,
    required => 1,
);

has capture_limit_bytes => (
    is      => 'ro',
    isa     => Int,
    default => sub { 8 * 1024 * 1024 },
);

sub run {
    my ($self, $timeout_seconds, @argv) = @_;
    return $self->run_signal('TERM', 5, $timeout_seconds, @argv);
}

sub run_signal {
    my ($self, $signal, $kill_after_seconds, $timeout_seconds, @argv) = @_;
    my @command = $self->_timeout_argv(
        $signal,
        $kill_after_seconds,
        $timeout_seconds,
        @argv,
    );
    return $self->_system_status(@command);
}

sub run_unbounded {
    my ($self, @argv) = @_;
    $self->_validate_argv(@argv);
    return $self->_system_status(@argv);
}

sub run_quiet {
    my ($self, $timeout_seconds, @argv) = @_;
    return $self->run_quiet_signal('TERM', 5, $timeout_seconds, @argv);
}

sub run_quiet_signal {
    my ($self, $signal, $kill_after_seconds, $timeout_seconds, @argv) = @_;
    my @command = $self->_timeout_argv(
        $signal,
        $kill_after_seconds,
        $timeout_seconds,
        @argv,
    );
    return $self->_fork_exec(
        \@command,
        stdout_path => '/dev/null',
        stderr_path => '/dev/null',
    );
}

sub capture {
    my ($self, $timeout_seconds, @argv) = @_;
    return $self->capture_signal('TERM', 5, $timeout_seconds, @argv);
}

sub capture_signal {
    my ($self, $signal, $kill_after_seconds, $timeout_seconds, @argv) = @_;
    my @command = $self->_timeout_argv(
        $signal,
        $kill_after_seconds,
        $timeout_seconds,
        @argv,
    );
    return $self->_capture(@command);
}

sub run_to_file {
    my ($self, $timeout_seconds, $stdout_path, $stderr_path, @argv) = @_;
    return $self->run_to_file_signal(
        'TERM',
        5,
        $timeout_seconds,
        $stdout_path,
        $stderr_path,
        @argv,
    );
}

sub run_to_file_signal {
    my (
        $self,
        $signal,
        $kill_after_seconds,
        $timeout_seconds,
        $stdout_path,
        $stderr_path,
        @argv,
    ) = @_;
    my @command = $self->_timeout_argv(
        $signal,
        $kill_after_seconds,
        $timeout_seconds,
        @argv,
    );
    return $self->_fork_exec(
        \@command,
        stdout_path => $stdout_path,
        stderr_path => $stderr_path,
        exclusive   => 1,
    );
}

sub _timeout_argv {
    my ($self, $signal, $kill_after_seconds, $timeout_seconds, @argv) = @_;
    require_value(
        (
            defined($timeout_seconds)
                && !!($timeout_seconds =~ /\A[1-9][0-9]*\z/)
        ),
        'Android command timeout must be a positive integer',
    );
    require_value(
        (
            defined($kill_after_seconds)
                && !!($kill_after_seconds =~ /\A[1-9][0-9]*\z/)
        ),
        'Android command kill-after timeout must be a positive integer',
    );
    require_value(
        (defined($signal) && !!($signal =~ /\A(?:TERM|INT)\z/)),
        'Android command timeout signal is invalid',
    );
    $self->_validate_argv(@argv);
    return (
        $self->config->require_tool('timeout'),
        "--signal=$signal",
        "--kill-after=${kill_after_seconds}s",
        "${timeout_seconds}s",
        @argv,
    );
}

sub _validate_argv {
    my ($self, @argv) = @_;
    require_value(@argv > 0, 'Android command is missing');
    require_value(
        (defined($argv[0]) && !ref($argv[0]) && !!($argv[0] =~ m{\A/})),
        'Android command executable must be an absolute path',
    );
    for my $argument (@argv) {
        require_value(
            (defined($argument) && !ref($argument) && !!($argument !~ /\0/)),
            'Android command contains an invalid argument',
        );
    }
    return 1;
}

sub _system_status {
    my ($self, @argv) = @_;
    $self->_validate_argv(@argv);
    my $status = system { $argv[0] } @argv;
    return _normalize_status($status);
}

sub _capture {
    my ($self, @argv) = @_;
    $self->_validate_argv(@argv);

    my ($stdin, $stdout);
    my $stderr = gensym();
    my $pid = eval { open3($stdin, $stdout, $stderr, @argv) };
    if (!$pid) {
        my $error = $@ || 'unknown process-launch failure';
        chomp $error;
        fail("unable to start Android command: $error");
    }

    close $stdin or fail('unable to close Android command standard input');
    my $selector = IO::Select->new($stdout, $stderr);
    my %stream_name = (
        fileno($stdout) => 'stdout',
        fileno($stderr) => 'stderr',
    );
    my %captured = (
        stdout => q{},
        stderr => q{},
    );

    while ($selector->count) {
        for my $handle ($selector->can_read) {
            my $bytes_read = sysread($handle, my $chunk, 65_536);
            if (!defined($bytes_read)) {
                next if $! == EINTR;
                $self->_terminate_child($pid);
                fail("unable to read Android command output: $!");
            }
            if ($bytes_read == 0) {
                $selector->remove($handle);
                close $handle;
                next;
            }

            my $name = $stream_name{ fileno($handle) };
            $captured{$name} .= $chunk;
            if (length($captured{stdout}) + length($captured{stderr})
                > $self->capture_limit_bytes) {
                $self->_terminate_child($pid);
                fail('Android command output exceeds the managed capture limit');
            }
        }
    }

    waitpid($pid, 0);
    return {
        status => _normalize_status($?),
        stdout => $captured{stdout},
        stderr => $captured{stderr},
    };
}

sub _fork_exec {
    my ($self, $argv, %options) = @_;
    $self->_validate_argv(@{$argv});

    my $pid = fork();
    defined($pid) or fail("unable to fork Android command: $!");
    if ($pid == 0) {
        _redirect_handle(
            'STDOUT',
            $options{stdout_path},
            $options{exclusive} // 0,
        );
        _redirect_handle(
            'STDERR',
            $options{stderr_path},
            $options{exclusive} // 0,
        );
        exec { $argv->[0] } @{$argv}
            or POSIX::_exit(127);
    }

    waitpid($pid, 0);
    return _normalize_status($?);
}

sub _redirect_handle {
    my ($name, $path, $exclusive) = @_;
    return if !defined($path);

    my $flags = O_WRONLY;
    if ($path eq '/dev/null') {
        open my $null, '>', '/dev/null'
            or POSIX::_exit(127);
        if ($name eq 'STDOUT') {
            open STDOUT, '>&', $null
                or POSIX::_exit(127);
        }
        else {
            open STDERR, '>&', $null
                or POSIX::_exit(127);
        }
        return;
    }

    $flags |= O_CREAT;
    $flags |= $exclusive ? O_EXCL : O_TRUNC;
    $flags |= O_NOFOLLOW if O_NOFOLLOW;
    sysopen my $file, $path, $flags, 0600
        or POSIX::_exit(127);
    if ($name eq 'STDOUT') {
        open STDOUT, '>&', $file
            or POSIX::_exit(127);
    }
    else {
        open STDERR, '>&', $file
            or POSIX::_exit(127);
    }
}

sub _terminate_child {
    my ($self, $pid) = @_;
    kill 'TERM', $pid;
    waitpid($pid, 0);
    return;
}

sub _normalize_status {
    my ($status) = @_;
    return 255 if !defined($status) || $status == -1;
    return 128 + ($status & 127) if $status & 127;
    return $status >> 8;
}

1;
