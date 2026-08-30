package AndroidADB::Lock;

use strict;
use warnings;

use File::Path qw(remove_tree);
use File::Spec;
use Moo;
use MooX::StrictConstructor;
use MooX::TypeTiny;
use Types::Standard qw(Object);

use AndroidADB::Validation qw(fail require_value);

has config => (
    is       => 'ro',
    isa      => Object,
    required => 1,
);

has active_lock_path => (
    is      => 'rw',
    default => sub { undef },
);

has active_partial_directory => (
    is      => 'rw',
    default => sub { undef },
);

sub acquire {
    my ($self, $operation_name, $lock_root) = @_;
    require_value(
        (defined($operation_name) && !!($operation_name =~ /\A[a-z0-9-]+\z/)),
        'managed Android operation name is invalid',
    );
    $self->_require_managed_directory($lock_root);

    my $lock_path = File::Spec->catdir($lock_root, 'device-maintenance.lock');
    if (!mkdir($lock_path, 0700)) {
        fail(
            'another managed Android backup, firmware download, or flash action is already running',
        );
    }

    $self->active_lock_path($lock_path);
    print "Acquired managed device-operation lock for $operation_name.\n";
    return $lock_path;
}

sub register_partial_directory {
    my ($self, $directory) = @_;
    $self->_require_managed_directory($directory);
    $self->active_partial_directory($directory);
    return $directory;
}

sub complete_partial_directory {
    my ($self, $directory) = @_;
    if (defined($self->active_partial_directory)
        && $self->active_partial_directory eq $directory) {
        $self->active_partial_directory(undef);
    }
    return;
}

sub release {
    my ($self) = @_;
    my $lock_path = $self->active_lock_path;
    return if !defined($lock_path);

    $self->_require_managed_path($lock_path);
    rmdir $lock_path;
    $self->active_lock_path(undef);
    return;
}

sub cleanup {
    my ($self) = @_;
    my $partial_directory = $self->active_partial_directory;
    if (defined($partial_directory)) {
        $self->_require_managed_path($partial_directory);
        if (-d $partial_directory && !-l $partial_directory) {
            remove_tree($partial_directory, { safe => 1 });
        }
        $self->active_partial_directory(undef);
    }

    $self->release;
    return;
}

sub _require_managed_directory {
    my ($self, $directory) = @_;
    require_value(
        defined($directory) && -d $directory && !-l $directory,
        'managed Android operation directory is invalid',
    );
    $self->_require_managed_path($directory);
    return;
}

sub _require_managed_path {
    my ($self, $path) = @_;
    require_value(
        (
            defined($path)
                && !ref($path)
                && !!($path =~ m{\A/})
                && !!($path !~ /[\r\n]/)
        ),
        'managed Android operation path is invalid',
    );
    my $root = $self->config->output_root;
    require_value(
        $path eq $root || index($path, "$root/") == 0,
        'managed Android operation path escapes the output root',
    );
    return;
}

1;
