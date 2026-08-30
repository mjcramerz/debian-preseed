package Telpoll::Config;

use strict;
use warnings;

use Encode qw(FB_CROAK decode);
use Fcntl qw(O_NOFOLLOW O_NONBLOCK O_RDONLY);
use File::Spec;
use Moo;
use MooX::StrictConstructor;
use MooX::TypeTiny;
use Types::Standard qw(Bool Int Str);

my $MAX_CONFIG_BYTES = 32 * 1024;

has enabled => (
    is       => 'ro',
    isa      => Bool,
    required => 1,
);

has config_path => (
    is       => 'ro',
    isa      => Str,
    required => 1,
);

has telegram_config_path => (
    is       => 'ro',
    isa      => Str,
    required => 1,
);

has api_base => (
    is       => 'ro',
    isa      => Str,
    required => 1,
);

has api_key => (
    is       => 'ro',
    isa      => Str,
    required => 1,
);

has chat_id => (
    is       => 'ro',
    isa      => Str,
    required => 1,
);

has home => (
    is       => 'ro',
    isa      => Str,
    required => 1,
);

has state_dir => (
    is       => 'ro',
    isa      => Str,
    required => 1,
);

has download_dir => (
    is       => 'ro',
    isa      => Str,
    required => 1,
);

has poll_seconds => (
    is       => 'ro',
    isa      => Int,
    required => 1,
);

has http_timeout_seconds => (
    is       => 'ro',
    isa      => Int,
    required => 1,
);

has ownership_conflict_backoff_seconds => (
    is       => 'ro',
    isa      => Int,
    required => 1,
);

has max_api_response_bytes => (
    is       => 'ro',
    isa      => Int,
    default  => sub { 4 * 1024 * 1024 },
);

has max_file_bytes => (
    is       => 'ro',
    isa      => Int,
    required => 1,
);

has max_updates => (
    is       => 'ro',
    isa      => Int,
    required => 1,
);

has max_update_attempts => (
    is       => 'ro',
    isa      => Int,
    required => 1,
);

sub from_managed_files {
    my ($class, %args) = @_;

    my $config_path = $args{config_path} // '/etc/telpoll/telpoll.conf';
    my $telegram_config_path =
        $args{telegram_config_path} // '/etc/default/labwc-plans';
    _validate_absolute_path('telpoll configuration', $config_path);
    _validate_absolute_path(
        'managed Telegram configuration',
        $telegram_config_path,
    );
    my $policy = _read_telpoll_config($config_path);

    my $enabled = _config_bool($policy, 'TELPOLL_ENABLED');
    my $poll_seconds =
        _config_int($policy, 'TELPOLL_LONG_POLL_SECONDS', 60, 60);
    my $http_timeout_seconds = _config_int(
        $policy,
        'TELPOLL_HTTP_TIMEOUT_SECONDS',
        $poll_seconds + 5,
        120,
    );
    my $ownership_conflict_backoff_seconds = _config_int(
        $policy,
        'TELPOLL_OWNERSHIP_CONFLICT_BACKOFF_SECONDS',
        60,
        86_400,
    );
    my $max_file_bytes = _config_int(
        $policy,
        'TELPOLL_MAX_FILE_BYTES',
        1,
        20 * 1024 * 1024,
    );
    my $max_updates = _config_int($policy, 'TELPOLL_MAX_UPDATES', 1, 100);
    my $max_update_attempts = _config_int(
        $policy,
        'TELPOLL_MAX_UPDATE_ATTEMPTS',
        1,
        100,
    );

    my ($api_base, $api_key, $chat_id) =
        ('https://api.telegram.org', q{}, q{});
    if ($enabled) {
        my $telegram = _read_telegram_config($telegram_config_path);
        _config_bool($telegram, 'LABWC_PLANS_TELEGRAM_ENABLED')
            or die "telpoll: Telegram is disabled in the managed configuration\n";

        $api_base = $telegram->{LABWC_PLANS_TELEGRAM_API_BASE};
        $api_base eq 'https://api.telegram.org'
            or die "telpoll: Telegram API base must remain https://api.telegram.org\n";

        $api_key = $telegram->{LABWC_PLANS_TELEGRAM_API_KEY};
        $api_key =~ /\A[0-9]{5,16}:[A-Za-z0-9_-]{20,128}\z/
            or die "telpoll: Telegram API key has an invalid format\n";

        $chat_id = $telegram->{LABWC_PLANS_TELEGRAM_CHAT_ID};
        $chat_id =~ /\A-?[0-9]{1,16}\z/
            or die "telpoll: Telegram chat ID has an invalid format\n";
    }

    my $home = _home_directory();
    return $class->new(
        enabled              => $enabled,
        config_path          => $config_path,
        telegram_config_path => $telegram_config_path,
        api_base             => $api_base,
        api_key              => $api_key,
        chat_id              => $chat_id,
        home                 => $home,
        state_dir            => File::Spec->catdir($home, '.local', 'state', 'telpoll'),
        download_dir         => File::Spec->catdir($home, 'Downloads', 'telegram'),
        poll_seconds         => $poll_seconds,
        http_timeout_seconds => $http_timeout_seconds,
        ownership_conflict_backoff_seconds =>
            $ownership_conflict_backoff_seconds,
        max_file_bytes       => $max_file_bytes,
        max_updates          => $max_updates,
        max_update_attempts  => $max_update_attempts,
    );
}

sub _read_telpoll_config {
    my ($path) = @_;

    my $raw = _read_root_config(
        $path,
        'telpoll configuration',
        sub {
            my ($mode) = @_;
            return ($mode & 07133) == 0 && ($mode & 0400) != 0;
        },
    );
    my %wanted = map { $_ => 1 } qw(
        TELPOLL_ENABLED
        TELPOLL_LONG_POLL_SECONDS
        TELPOLL_HTTP_TIMEOUT_SECONDS
        TELPOLL_OWNERSHIP_CONFLICT_BACKOFF_SECONDS
        TELPOLL_MAX_FILE_BYTES
        TELPOLL_MAX_UPDATES
        TELPOLL_MAX_UPDATE_ATTEMPTS
    );
    my %values;
    for my $line (split /\n/, $raw, -1) {
        $line =~ s/\r\z//;
        next if $line eq q{} || $line =~ /\A#/;
        my ($key, $value) =
            _parse_assignment($line, 'telpoll configuration');
        $wanted{$key}
            or die "telpoll: telpoll configuration contains unsupported key $key\n";
        !exists($values{$key})
            or die "telpoll: telpoll configuration defines $key more than once\n";
        $values{$key} = $value;
    }
    _require_config_keys(
        \%values,
        \%wanted,
        'telpoll configuration',
    );
    return \%values;
}

sub _read_telegram_config {
    my ($path) = @_;

    my $raw = _read_root_config(
        $path,
        'managed Telegram configuration',
        sub {
            my ($mode) = @_;
            return $mode == 0640;
        },
    );
    my %wanted = map { $_ => 1 } qw(
        LABWC_PLANS_TELEGRAM_ENABLED
        LABWC_PLANS_TELEGRAM_API_BASE
        LABWC_PLANS_TELEGRAM_API_KEY
        LABWC_PLANS_TELEGRAM_CHAT_ID
    );
    my %values;
    for my $line (split /\n/, $raw, -1) {
        $line =~ s/\r\z//;
        next if $line eq q{} || $line =~ /\A#/;
        my ($candidate) = $line =~ /\A([A-Z][A-Z0-9_]*)=/;
        next if !defined($candidate) || !$wanted{$candidate};
        my ($key, $value) =
            _parse_assignment($line, 'managed Telegram configuration');
        !exists($values{$key})
            or die "telpoll: managed Telegram configuration defines $key more than once\n";
        $values{$key} = $value;
    }
    _require_config_keys(
        \%values,
        \%wanted,
        'managed Telegram configuration',
    );
    return \%values;
}

sub _read_root_config {
    my ($path, $label, $mode_is_safe) = @_;

    sysopen my $fh, $path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK
        or die "telpoll: cannot open the $label: $!\n";
    my @stat = stat $fh;
    @stat && -f $fh
        or die "telpoll: $label is not a regular file\n";
    $stat[4] == 0
        or die "telpoll: $label must be owned by root\n";
    $mode_is_safe->($stat[2] & 07777)
        or die "telpoll: $label has unsafe permissions\n";
    $stat[7] > 0 && $stat[7] <= $MAX_CONFIG_BYTES
        or die "telpoll: $label has an invalid size\n";

    my $raw = q{};
    while (1) {
        my $remaining = $MAX_CONFIG_BYTES + 1 - length($raw);
        $remaining > 0
            or die "telpoll: $label exceeds the size limit\n";
        my $read = sysread $fh, my $chunk, $remaining > 8_192 ? 8_192 : $remaining;
        defined($read)
            or die "telpoll: cannot read the $label: $!\n";
        last if $read == 0;
        $raw .= $chunk;
    }
    close $fh
        or die "telpoll: cannot close the $label: $!\n";
    my $decoded = eval { decode('UTF-8', $raw, FB_CROAK) };
    defined($decoded) && !$@
        or die "telpoll: $label is not valid UTF-8\n";
    return $decoded;
}

sub _parse_assignment {
    my ($line, $label) = @_;

    $line =~ /\A([A-Z][A-Z0-9_]*)=(.*)\z/
        or die "telpoll: $label contains an invalid assignment\n";
    my ($key, $raw_value) = ($1, $2);
    my $value;
    if ($raw_value =~ /\A'([^'\r\n]*)'\z/) {
        $value = $1;
    }
    elsif ($raw_value =~ /\A[A-Za-z0-9._:\/+-]*\z/) {
        $value = $raw_value;
    }
    else {
        die "telpoll: $label contains an invalid value for $key\n";
    }
    return ($key, $value);
}

sub _require_config_keys {
    my ($values, $wanted, $label) = @_;

    for my $key (sort keys %{$wanted}) {
        exists($values->{$key})
            or die "telpoll: $label is missing $key\n";
    }
    return;
}

sub _config_bool {
    my ($values, $key) = @_;

    return 1 if $values->{$key} eq 'true';
    return 0 if $values->{$key} eq 'false';
    die "telpoll: $key must be true or false\n";
}

sub _config_int {
    my ($values, $key, $minimum, $maximum) = @_;

    my $value = $values->{$key};
    defined($value) && $value =~ /\A[0-9]{1,10}\z/
        or die "telpoll: $key must be an integer\n";
    my $number = int($value);
    $number >= $minimum && $number <= $maximum
        or die "telpoll: $key is outside the supported range\n";
    return $number;
}

sub _home_directory {
    my @account = getpwuid($<);
    @account
        or die "telpoll: cannot resolve the current desktop account\n";
    my $home = $account[7] // q{};
    _validate_absolute_path('HOME', $home);
    if (defined($ENV{HOME}) && $ENV{HOME} ne $home) {
        die "telpoll: HOME does not match the desktop account directory\n";
    }
    -d $home && !-l $home && (lstat $home)[4] == $<
        or die "telpoll: HOME must be a user-owned real directory\n";
    return $home;
}

sub _validate_absolute_path {
    my ($label, $path) = @_;

    defined($path) && $path =~ m{\A/} &&
        $path !~ m{\0|(?:\A|/)\.\.(?:/|\z)|//}
        or die "telpoll: $label path is invalid\n";
    return $path;
}

1;
