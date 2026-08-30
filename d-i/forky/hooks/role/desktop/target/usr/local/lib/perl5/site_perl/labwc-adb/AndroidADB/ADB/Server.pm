package AndroidADB::ADB::Server;

use strict;
use warnings;

use Fcntl qw(O_CREAT O_NOFOLLOW O_TRUNC O_WRONLY);
use Moo;
use MooX::StrictConstructor;
use MooX::TypeTiny;
use Time::HiRes qw(sleep);
use Types::Standard qw(Object);

use AndroidADB::Validation qw(fail require_value);

use constant SERVER_UNIT => 'labwc-adb-server.service';

has config => (
    is       => 'ro',
    isa      => Object,
    required => 1,
);

has command => (
    is       => 'ro',
    isa      => Object,
    required => 1,
);

sub port_in_use {
    my ($self) = @_;
    my $result = $self->command->capture(
        10,
        $self->config->require_tool('ss'),
        '-H',
        '-ltn',
        'sport = :' . $self->config->adb_server_port,
    );
    return $result->{status} == 0 && $result->{stdout} =~ /\S/ ? 1 : 0;
}

sub is_managed {
    my ($self) = @_;
    my $marker = $self->config->server_marker;
    return -f $marker && !-l $marker && -r $marker ? 1 : 0;
}

sub mark_managed {
    my ($self) = @_;
    my $marker = $self->config->server_marker;
    my $flags = O_WRONLY | O_CREAT | O_TRUNC;
    $flags |= O_NOFOLLOW if O_NOFOLLOW;
    sysopen my $file, $marker, $flags, 0600
        or fail("unable to mark the managed ADB server: $!");
    close $file or fail("unable to close the managed ADB server marker: $!");
    chmod 0600, $marker
        or fail("unable to protect the managed ADB server marker: $!");
    return;
}

sub clear_marker {
    my ($self) = @_;
    my $marker = $self->config->server_marker;
    unlink $marker if -e $marker || -l $marker;
    return;
}

sub probe {
    my ($self) = @_;
    return $self->command->run_quiet(
        $self->config->adb_probe_seconds,
        $self->config->require_tool('adb'),
        'server-status',
    ) == 0 ? 1 : 0;
}

sub wait_for_exit {
    my ($self) = @_;
    for (1 .. 10) {
        if (!$self->port_in_use) {
            $self->clear_marker;
            return 1;
        }
        sleep 1;
    }
    return 0;
}

sub stop {
    my ($self) = @_;
    if (!$self->port_in_use) {
        $self->clear_marker;
        print "ADB server is already stopped.\n";
        return 0;
    }
    $self->is_managed
        or fail(
            'TCP port ' . $self->config->adb_server_port
                . ' is not owned by this managed desktop session',
        );
    $self->probe
        or fail(
            'managed ADB server is unresponsive; refusing process-table discovery or name-wide termination',
        );

    $self->command->run_quiet(
        10,
        $self->config->require_tool('adb'),
        'kill-server',
    );
    $self->wait_for_exit
        or fail(
            'ADB server did not release TCP port '
                . $self->config->adb_server_port
                . ' after kill-server',
        );
    print "ADB server stopped.\n";
    return 0;
}

sub _service_is_active {
    my ($self) = @_;
    my $systemctl = $self->config->require_tool(
        'systemctl',
        'systemctl is not installed',
    );
    return $self->command->run_quiet(
        10,
        $systemctl,
        '--user',
        'is-active',
        '--quiet',
        SERVER_UNIT,
    ) == 0 ? 1 : 0;
}

sub _service_is_failed {
    my ($self) = @_;
    my $systemctl = $self->config->require_tool(
        'systemctl',
        'systemctl is not installed',
    );
    return $self->command->run_quiet(
        10,
        $systemctl,
        '--user',
        'is-failed',
        '--quiet',
        SERVER_UNIT,
    ) == 0 ? 1 : 0;
}

sub _run_service_command {
    my ($self, $operation) = @_;
    $operation =~ /\A(?:start|restart|stop)\z/
        or fail('invalid managed ADB service operation');
    my $systemctl = $self->config->require_tool(
        'systemctl',
        'systemctl is not installed',
    );
    if ($operation ne 'stop' && $self->_service_is_failed) {
        my $reset_status = $self->command->run(
            10,
            $systemctl,
            '--user',
            'reset-failed',
            SERVER_UNIT,
        );
        return $reset_status if $reset_status != 0;
    }
    return $self->command->run(
        $self->config->adb_start_seconds + 70,
        $systemctl,
        '--user',
        $operation,
        SERVER_UNIT,
    );
}

sub start_via_service {
    my ($self) = @_;
    my $operation = $self->_service_is_active ? 'restart' : 'start';
    my $status = $self->_run_service_command($operation);
    return $status if $status != 0;
    $self->_service_is_active
        or fail('managed ADB service did not become active after start');
    return $self->show_status;
}

sub repair_via_service {
    my ($self) = @_;
    my $operation = $self->_service_is_active ? 'restart' : 'start';
    my $status = $self->_run_service_command($operation);
    return $status if $status != 0;
    $self->_service_is_active
        or fail('managed ADB service did not become active after repair');
    return $self->show_status;
}

sub stop_via_service {
    my ($self) = @_;
    return $self->stop if !$self->_service_is_active;

    my $status = $self->_run_service_command('stop');
    return $status if $status != 0;
    $self->port_in_use
        and fail('ADB server remained active after stopping the managed service');
    $self->clear_marker;
    print "ADB server stopped.\n";
    return 0;
}

sub start_once {
    my ($self) = @_;
    if ($self->port_in_use) {
        $self->is_managed
            or fail(
                'TCP port ' . $self->config->adb_server_port
                    . ' is not owned by this managed desktop session',
            );
        return $self->probe;
    }

    my $status = $self->command->run_signal(
        'TERM',
        3,
        $self->config->adb_start_seconds,
        $self->config->require_tool('adb'),
        'start-server',
    );
    return 0 if $status != 0;

    for (1 .. 10) {
        if ($self->port_in_use && $self->probe) {
            $self->mark_managed;
            return 1;
        }
        sleep 1;
    }
    return 0;
}

sub start {
    my ($self) = @_;
    if ($self->port_in_use && $self->is_managed && $self->probe) {
        print "ADB server is already running and responsive.\n";
        return $self->command->run(
            $self->config->adb_probe_seconds,
            $self->config->require_tool('adb'),
            'server-status',
        );
    }

    if ($self->port_in_use) {
        $self->is_managed
            or fail(
                'TCP port ' . $self->config->adb_server_port
                    . ' is not owned by this managed desktop session',
            );
        fail(
            'managed ADB server is unresponsive; explicit session restart is required',
        );
    }

    for my $attempt (1 .. 2) {
        if ($self->start_once) {
            print "ADB server started and passed its responsiveness probe.\n";
            return $self->command->run(
                $self->config->adb_probe_seconds,
                $self->config->require_tool('adb'),
                'server-status',
            );
        }
        print STDERR "ADB server start attempt $attempt failed; retrying without process-table discovery.\n";
        $self->clear_marker;
    }

    fail('ADB server failed to become responsive after two bounded attempts');
}

sub repair {
    my ($self) = @_;
    $self->stop if $self->port_in_use;
    return $self->start;
}

sub ensure_responsive {
    my ($self) = @_;
    if (!$self->port_in_use) {
        $self->clear_marker;
        fail('ADB server is stopped; start it from the Android Debug Bridge launcher');
    }
    $self->is_managed
        or fail(
            'TCP port ' . $self->config->adb_server_port
                . ' is not owned by this managed desktop session',
        );
    return 1 if $self->probe;
    fail(
        'managed ADB server is unresponsive; refusing process-table discovery or name-wide termination',
    );
}

sub show_status {
    my ($self) = @_;
    if (!$self->port_in_use) {
        $self->clear_marker;
        print "ADB server status: stopped.\n";
        print "Use \"Start ADB Server\" in the Android Debug Bridge launcher.\n";
        return 3;
    }
    if (!$self->is_managed) {
        print 'ADB server status: TCP port '
            . $self->config->adb_server_port
            . " is not owned by this managed desktop session.\n";
        return 1;
    }
    if ($self->probe) {
        print "ADB server status: running and responsive.\n";
        return $self->command->run(
            $self->config->adb_probe_seconds,
            $self->config->require_tool('adb'),
            'server-status',
        );
    }

    print "ADB server status: running but unresponsive.\n";
    print "The next device action will repair it automatically, or choose \"Repair / Restart ADB Server\".\n";
    return 1;
}

1;
