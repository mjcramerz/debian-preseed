package ExternalSoftware::Servicing::Notifier;

use strict;
use warnings;

use Moo;
use MooX::StrictConstructor;

use File::Basename qw(basename);
use File::Path qw(make_path);
use File::Spec;
use ExternalSoftware::Servicing::Atomic;

my %APP_LABEL = (
    bitwarden => 'Bitwarden Desktop',
    chatgpt   => 'ChatGPT/Codex Desktop',
    obsidian  => 'Obsidian',
    qoredb    => 'QoreDB',
    gridline  => 'Gridline',
    zoom      => 'Zoom Workplace',
    filen     => 'Filen Desktop',
    discord   => 'Discord',
    sleek     => 'Sleek',
    postman   => 'Postman',
    ledger    => 'Ledger Wallet (Ledger Live)',
    tuta      => 'Tuta Mail',
    all       => 'Managed software',
);

my %FAILURE_BODY = (
    download   => 'The vendor download could not be retrieved safely.',
    validation => 'The downloaded artifact failed package or payload validation.',
    missing    => 'The managed application is no longer installed, so it was not recreated.',
    downgrade  => 'The vendor artifact is older than the installed version and was rejected.',
    install    => 'APT could not install or verify the downloaded package.',
    signature  => 'The vendor signature, checksum, or pinned public key verification failed.',
    extract    => 'The verified AppImage could not be extracted safely.',
    archive    => 'The downloaded archive failed structure or payload validation.',
    payload    => 'The installed package is missing required managed payload files.',
    policy     => 'The managed application security policy could not be restored or verified.',
    publish    => 'The verified AppImage update could not be published atomically.',
    postinstall => 'The installed application failed post-install verification.',
);

has event_dir => (is => 'ro', default => sub { '/var/lib/software/events' });

sub _notify {
    my ($self, $urgency, $icon, $timeout, $summary, $body) = @_;
    system(
        '/usr/bin/notify-send', '-a', 'Software Updater', '-u', $urgency,
        '-i', $icon, '-c', 'system.software-update', '-t', $timeout,
        $summary, $body,
    ) == 0 or die "notify-send failed\n";
}

sub _deliver {
    my ($self, $status, $app, $a, $b) = @_;
    exists $APP_LABEL{$app} or die "unknown managed application event\n";
    if ($status eq 'checking') {
        return $self->_notify('normal', 'software-update-available', 8000, 'Checking managed software updates',
            'Bitwarden, ChatGPT/Codex Desktop, Obsidian, Zoom, Filen, Discord, Sleek, Postman, Ledger, and Tuta Mail are being checked; QoreDB and Gridline remain checksum-pinned for local repair.');
    }
    if ($status eq 'downloading' || $status eq 'downloaded') {
        return $self->_notify('normal', 'software-update-available', 10000,
            $status eq 'downloaded' ? "$APP_LABEL{$app} download ready" : "Downloading $APP_LABEL{$app}",
            "$a -> $b");
    }
    if ($status eq 'updated' || $status eq 'applying') {
        return $self->_notify('normal', 'software-update-urgent', 10000,
            $status eq 'updated' ? "$APP_LABEL{$app} updated" : "Applying $APP_LABEL{$app}", "$a -> $b");
    }
    if ($status eq 'failed') {
        exists $FAILURE_BODY{$a} or die "unknown managed application failure reason\n";
        return $self->_notify('critical', 'dialog-error', 0, "$APP_LABEL{$app} update failed", $FAILURE_BODY{$a});
    }
    if ($status eq 'download-complete') {
        return $self->_notify('normal', 'software-update-available', 12000, 'Managed software download complete', "$a ready; $b failed.");
    }
    if ($status eq 'apply-complete') {
        return $self->_notify('normal', 'software-update-urgent', 12000, 'Managed software update complete', "$a updated; $b failed.");
    }
    if ($status eq 'no-updates') {
        return $self->_notify('normal', 'software-update-available', 8000, 'Managed software is current', 'No updates were available.');
    }
    die "unknown managed application event status\n";
}

sub run {
    my ($self) = @_;
    return 0 if !-x '/usr/bin/notify-send' || !defined $ENV{DBUS_SESSION_BUS_ADDRESS};
    my $events = $self->event_dir();
    -d $events && !-l $events or return 0;
    my @event_stat = lstat $events;
    return 0 if !@event_stat || $event_stat[4] != 0 || ($event_stat[2] & 0022);

    my $root = $ENV{XDG_STATE_HOME} // (($ENV{HOME} // q{}) . '/.local/state');
    ExternalSoftware::Servicing::Atomic->assert_absolute_path('notification state directory', $root);
    my $seen = File::Spec->catdir($root, 'managed-external-software', 'seen');
    make_path($seen, { mode => 0700 }) if !-d $seen;
    -d $seen && !-l $seen or return 0;
    opendir my $dh, $events or return 0;
    my $failed = 0;
    while (my $name = readdir $dh) {
        next if $name !~ /\A[0-9]{10}-[0-9]{10}-[0-9]{4}\.event\z/;
        my $path = File::Spec->catfile($events, $name);
        my $marker = File::Spec->catfile($seen, "$name.seen");
        next if -e $marker;
        my @st = lstat $path;
        next if !@st || !-f _ || -l _ || $st[4] != 0 || ($st[2] & 0022) || $st[7] > 512;
        my $line = eval { ExternalSoftware::Servicing::Atomic->read_limited($path, 512) };
        next if $@ || !defined $line || $line !~ /\A([^|\n]+)\|([^|\n]+)\|([^|\n]+)\|([^|\n]+)\n\z/;
        if (eval { $self->_deliver($1, $2, $3, $4); 1 }) {
            ExternalSoftware::Servicing::Atomic->write_text($marker, q{}, 0600);
        } else {
            $failed = 1;
        }
    }
    closedir $dh;
    return $failed ? 1 : 0;
}

1;
