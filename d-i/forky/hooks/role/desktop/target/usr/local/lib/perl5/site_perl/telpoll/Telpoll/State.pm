package Telpoll::State;

use strict;
use warnings;

use Fcntl qw(:flock O_CREAT O_NOFOLLOW O_RDONLY O_RDWR);
use File::Path qw(make_path);
use File::Temp qw(tempfile);
use IO::Handle;
use JSON::PP;
use Moo;
use MooX::StrictConstructor;
use MooX::TypeTiny;
use Types::Standard qw(HashRef Int Str);

has directory => (
    is       => 'ro',
    isa      => Str,
    required => 1,
);

has max_bytes => (
    is      => 'ro',
    isa     => Int,
    default => sub { 1024 * 1024 },
);

has data => (
    is      => 'lazy',
    isa     => HashRef,
    builder => '_build_data',
);

has lock_handle => (
    is => 'rw',
);

sub acquire_lock {
    my ($self) = @_;

    my $directory = $self->_ensure_directory();
    my $path = "$directory/daemon.lock";
    sysopen my $fh, $path, O_CREAT | O_NOFOLLOW | O_RDWR, 0600
        or die "telpoll: cannot open daemon lock: $!\n";
    my @stat = stat $fh;
    @stat && -f $fh && $stat[4] == $<
        or die "telpoll: daemon lock is unsafe\n";
    flock($fh, LOCK_EX | LOCK_NB)
        or die "telpoll: another daemon instance is already running\n";
    chmod 0600, $path
        or die "telpoll: cannot secure daemon lock: $!\n";
    $self->lock_handle($fh);
    return;
}

sub offset {
    my ($self) = @_;
    return int($self->data()->{offset});
}

sub pending_for {
    my ($self, $update_id) = @_;

    _validate_update_id($update_id);
    my $key = "$update_id";
    $self->data()->{pending}->{$key} //= {
        attempts        => 0,
        delete_attempts => 0,
        local_complete  => 0,
        delete_message  => 0,
    };
    return $self->data()->{pending}->{$key};
}

sub remove_pending {
    my ($self, $update_id) = @_;
    delete $self->data()->{pending}->{"$update_id"};
    return;
}

sub advance {
    my ($self, $offset) = @_;

    defined($offset) && "$offset" =~ /\A[0-9]{1,16}\z/
        or die "telpoll: update offset is invalid\n";
    $self->data()->{offset} = 0 + $offset;
    return;
}

sub save {
    my ($self) = @_;

    my $directory = $self->_ensure_directory();
    my $content = JSON::PP->new()->canonical(1)->utf8(1)->encode($self->data());
    length($content) <= $self->max_bytes()
        or die "telpoll: daemon state exceeds the size limit\n";

    my ($fh, $temporary) = tempfile('.state.json.XXXXXX', DIR => $directory, UNLINK => 0);
    my $ok = eval {
        binmode $fh, ':raw';
        print {$fh} $content
            or die "telpoll: cannot write temporary daemon state: $!\n";
        $fh->sync()
            or die "telpoll: cannot synchronize temporary daemon state: $!\n";
        close $fh
            or die "telpoll: cannot close temporary daemon state: $!\n";
        chmod 0600, $temporary
            or die "telpoll: cannot secure temporary daemon state: $!\n";
        rename $temporary, "$directory/state.json"
            or die "telpoll: cannot publish daemon state: $!\n";
        1;
    };
    if (!$ok) {
        my $error = $@ || "telpoll: unknown daemon state write failure\n";
        close $fh if defined(fileno($fh));
        unlink $temporary if defined($temporary) && -e $temporary;
        die $error;
    }
    return;
}

sub _build_data {
    my ($self) = @_;

    my $directory = $self->_ensure_directory();
    my $path = "$directory/state.json";
    return {
        version => 1,
        offset  => 0,
        pending => {},
    } if !-e $path;

    sysopen my $fh, $path, O_RDONLY | O_NOFOLLOW
        or die "telpoll: cannot read daemon state: $!\n";
    my @stat = stat $fh;
    @stat && -f $fh && $stat[4] == $< && ($stat[2] & 0077) == 0 &&
        $stat[7] > 0 && $stat[7] <= $self->max_bytes()
        or die "telpoll: daemon state is unsafe or too large\n";
    binmode $fh, ':raw';
    local $/;
    my $raw = <$fh> // q{};
    close $fh
        or die "telpoll: cannot close daemon state: $!\n";
    my $data = eval { JSON::PP->new()->utf8(1)->decode($raw) };
    !$@ && ref($data) eq 'HASH'
        or die "telpoll: daemon state is not valid JSON\n";
    _validate_state($data);
    return $data;
}

sub _ensure_directory {
    my ($self) = @_;

    my $directory = $self->directory();
    if (!-e $directory) {
        make_path($directory, { mode => 0700 });
    }
    -d $directory && !-l $directory && (lstat $directory)[4] == $<
        or die "telpoll: state directory must be a user-owned real directory\n";
    chmod 0700, $directory
        or die "telpoll: cannot secure state directory: $!\n";
    return $directory;
}

sub _validate_state {
    my ($data) = @_;

    defined($data->{version}) && "$data->{version}" eq '1'
        or die "telpoll: daemon state version is unsupported\n";
    defined($data->{offset}) && "$data->{offset}" =~ /\A[0-9]{1,16}\z/
        or die "telpoll: daemon state offset is invalid\n";
    ref($data->{pending}) eq 'HASH' && scalar(keys %{$data->{pending}}) <= 100
        or die "telpoll: daemon pending state is invalid\n";
    for my $update_id (keys %{$data->{pending}}) {
        _validate_update_id($update_id);
        ref($data->{pending}->{$update_id}) eq 'HASH'
            or die "telpoll: daemon pending record is invalid\n";
        my $record = $data->{pending}->{$update_id};
        for my $key (qw(attempts delete_attempts)) {
            defined($record->{$key}) && "$record->{$key}" =~ /\A[0-9]{1,3}\z/
                or die "telpoll: daemon pending record contains invalid $key\n";
        }
        for my $key (qw(local_complete delete_message)) {
            defined($record->{$key}) && "$record->{$key}" =~ /\A[01]\z/
                or die "telpoll: daemon pending record contains invalid $key\n";
        }
        if (defined($record->{stem})) {
            $record->{stem} =~ /\A[0-9]{4}(?:-[0-9]{2}){5}\z/
                or die "telpoll: daemon pending record contains an invalid stem\n";
        }
        if (exists($record->{message_id})) {
            "$record->{message_id}" =~ /\A(?:0|[1-9][0-9]{0,15})\z/
                or die "telpoll: daemon pending record contains an invalid message ID\n";
        }
        if (exists($record->{chat_id})) {
            "$record->{chat_id}" =~ /\A(?:|-?[0-9]{1,16})\z/
                or die "telpoll: daemon pending record contains an invalid chat ID\n";
        }
    }
    return;
}

sub _validate_update_id {
    my ($update_id) = @_;
    defined($update_id) && "$update_id" =~ /\A[0-9]{1,16}\z/
        or die "telpoll: update ID is invalid\n";
    return;
}

1;
