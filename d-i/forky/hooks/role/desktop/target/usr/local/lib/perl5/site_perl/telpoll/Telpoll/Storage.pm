package Telpoll::Storage;

use strict;
use warnings;

use Encode qw(encode);
use Errno qw(EEXIST);
use Fcntl qw(O_NOFOLLOW O_RDONLY);
use File::Path qw(make_path);
use File::Temp qw(tempfile);
use IO::Handle;
use JSON::PP;
use Moo;
use MooX::StrictConstructor;
use MooX::TypeTiny;
use POSIX qw(strftime);
use Types::Standard qw(Str);

has home => (
    is       => 'ro',
    isa      => Str,
    required => 1,
);

has download_dir => (
    is       => 'ro',
    isa      => Str,
    required => 1,
);

sub store_message {
    my ($self, $update) = @_;

    ref($update) eq 'HASH' && ref($update->{message}) eq 'HASH'
        or die "telpoll: Telegram update does not contain a message\n";
    my $message = $update->{message};
    my $message_id = _bounded_integer($message->{message_id}, 'message ID');
    my $epoch = _message_epoch($message->{date});
    my $prefix = strftime('%Y-%m-%d-%H-%M-%S', localtime($epoch)) .
        "-telegram-message-$message_id";

    my $json = JSON::PP->new()->canonical(1)->pretty(1)->utf8(1)->encode($update);
    length($json) <= 1024 * 1024
        or die "telpoll: Telegram update is too large to store\n";
    $self->_store_content("$prefix.json", $json);

    my @text;
    for my $field (qw(text caption)) {
        next if !defined($message->{$field});
        !ref($message->{$field}) && length($message->{$field}) <= 512 * 1024
            or die "telpoll: Telegram message $field is invalid or too large\n";
        push @text, $message->{$field} if length($message->{$field});
    }
    if (@text) {
        my $body = join("\n\n", @text);
        $body =~ s/\r\n?/\n/g;
        $self->_store_content("$prefix.txt", encode('UTF-8', $body . "\n"));
    }
    return $prefix;
}

sub store_error {
    my ($self, $prefix, $message) = @_;

    defined($prefix) && !ref($prefix) &&
        $prefix =~ /\A[0-9A-Za-z._-]+\z/
        or die "telpoll: error artifact prefix is invalid\n";
    $message //= 'Telegram message processing did not complete.';
    $message =~ s/[\p{Cc}\p{Cf}]+/ /gu;
    $message =~ s/\s+/ /gu;
    $message =~ s/\A\s+|\s+\z//gu;
    $message = substr($message, 0, 2_048) if length($message) > 2_048;
    $self->_store_content("$prefix.error.txt", encode('UTF-8', "$message\n"));
    return;
}

sub attachment_name {
    my ($self, $prefix, $kind, $original_name, $remote_path) = @_;

    $prefix =~ /\A[0-9A-Za-z._-]+\z/
        or die "telpoll: attachment prefix is invalid\n";
    $kind =~ /\A[a-z][a-z0-9_-]{0,31}\z/
        or die "telpoll: attachment kind is invalid\n";
    my $name = defined($original_name) && length($original_name)
        ? $original_name
        : _basename($remote_path // q{});
    $name = "$kind.bin" if !length($name);
    $name = _safe_filename($name);
    return "$prefix-$kind-$name";
}

sub store_download {
    my ($self, $name, $expected_size, $maximum_size, $writer) = @_;

    _validate_artifact_name($name);
    ref($writer) eq 'CODE'
        or die "telpoll: download writer is invalid\n";
    defined($expected_size) && "$expected_size" =~ /\A[0-9]{1,16}\z/
        or die "telpoll: expected download size is invalid\n";
    defined($maximum_size) && "$maximum_size" =~ /\A[1-9][0-9]{0,15}\z/
        or die "telpoll: maximum download size is invalid\n";

    my $directory = $self->_ensure_download_directory();
    my $destination = "$directory/$name";
    if (-e $destination) {
        $self->_validate_existing_file($destination, $expected_size, $maximum_size);
        return $destination;
    }

    my ($fh, $temporary) = tempfile(".$name.XXXXXX", DIR => $directory, UNLINK => 0);
    my $ok = eval {
        binmode $fh, ':raw';
        my $written = $writer->($fh);
        defined($written) && "$written" =~ /\A[0-9]{1,16}\z/
            or die "telpoll: download writer returned an invalid size\n";
        $written <= $maximum_size
            or die "telpoll: downloaded file exceeds the size limit\n";
        $expected_size == 0 || $written == $expected_size
            or die "telpoll: downloaded file size does not match Telegram metadata\n";
        $fh->sync()
            or die "telpoll: cannot synchronize downloaded file: $!\n";
        close $fh
            or die "telpoll: cannot close downloaded file: $!\n";
        chmod 0600, $temporary
            or die "telpoll: cannot secure downloaded file: $!\n";
        if (!link $temporary, $destination) {
            if ($! == EEXIST) {
                $self->_validate_existing_file($destination, $expected_size, $maximum_size);
            }
            else {
                die "telpoll: cannot publish downloaded file: $!\n";
            }
        }
        unlink $temporary
            or die "telpoll: cannot remove temporary downloaded file: $!\n";
        1;
    };
    if (!$ok) {
        my $error = $@ || "telpoll: unknown download storage failure\n";
        close $fh if defined(fileno($fh));
        unlink $temporary if defined($temporary) && -e $temporary;
        die $error;
    }
    return $destination;
}

sub _store_content {
    my ($self, $name, $content) = @_;

    _validate_artifact_name($name);
    defined($content) && length($content) <= 1024 * 1024
        or die "telpoll: stored message artifact exceeds the size limit\n";
    my $directory = $self->_ensure_download_directory();
    my $destination = "$directory/$name";
    if (-e $destination) {
        $self->_validate_existing_content($destination, $content);
        return $destination;
    }

    my ($fh, $temporary) = tempfile(".$name.XXXXXX", DIR => $directory, UNLINK => 0);
    my $ok = eval {
        binmode $fh, ':raw';
        print {$fh} $content
            or die "telpoll: cannot write message artifact: $!\n";
        $fh->sync()
            or die "telpoll: cannot synchronize message artifact: $!\n";
        close $fh
            or die "telpoll: cannot close message artifact: $!\n";
        chmod 0600, $temporary
            or die "telpoll: cannot secure message artifact: $!\n";
        if (!link $temporary, $destination) {
            if ($! == EEXIST) {
                $self->_validate_existing_content($destination, $content);
            }
            else {
                die "telpoll: cannot publish message artifact: $!\n";
            }
        }
        unlink $temporary
            or die "telpoll: cannot remove temporary message artifact: $!\n";
        1;
    };
    if (!$ok) {
        my $error = $@ || "telpoll: unknown message storage failure\n";
        close $fh if defined(fileno($fh));
        unlink $temporary if defined($temporary) && -e $temporary;
        die $error;
    }
    return $destination;
}

sub _ensure_download_directory {
    my ($self) = @_;

    my $home = $self->home();
    -d $home && !-l $home && (lstat $home)[4] == $<
        or die "telpoll: HOME must remain a user-owned real directory\n";
    my $downloads = "$home/Downloads";
    if (!-e $downloads) {
        make_path($downloads, { mode => 0700 });
    }
    -d $downloads && !-l $downloads && (lstat $downloads)[4] == $<
        or die "telpoll: Downloads must be a user-owned real directory\n";

    my $directory = $self->download_dir();
    if (!-e $directory) {
        make_path($directory, { mode => 0700 });
    }
    -d $directory && !-l $directory && (lstat $directory)[4] == $<
        or die "telpoll: Telegram download directory must be a user-owned real directory\n";
    chmod 0700, $directory
        or die "telpoll: cannot secure Telegram download directory: $!\n";
    return $directory;
}

sub _validate_existing_file {
    my ($self, $path, $expected_size, $maximum_size) = @_;

    my @stat = lstat $path;
    @stat && -f _ && !-l _ && $stat[4] == $< && ($stat[2] & 0077) == 0
        or die "telpoll: refusing to reuse an unsafe existing artifact\n";
    my $size = $stat[7];
    $size <= $maximum_size
        or die "telpoll: existing artifact exceeds the size limit\n";
    $expected_size == 0 || $size == $expected_size
        or die "telpoll: existing artifact size does not match Telegram metadata\n";
    return;
}

sub _validate_existing_content {
    my ($self, $path, $content) = @_;

    $self->_validate_existing_file($path, length($content), 1024 * 1024);
    sysopen my $fh, $path, O_RDONLY | O_NOFOLLOW
        or die "telpoll: cannot inspect existing message artifact: $!\n";
    my @stat = stat $fh;
    @stat && -f $fh && $stat[4] == $< && ($stat[2] & 0077) == 0 &&
        $stat[7] == length($content)
        or die "telpoll: existing message artifact is unsafe\n";
    local $/;
    my $existing = <$fh>;
    close $fh
        or die "telpoll: cannot close existing message artifact: $!\n";
    defined($existing) && $existing eq $content
        or die "telpoll: existing message artifact content does not match\n";
    return;
}

sub _safe_filename {
    my ($name) = @_;

    $name = _basename($name);
    $name =~ s/[\p{Cc}\p{Cf}]+/_/gu;
    $name =~ s/[^0-9A-Za-z._-]+/_/g;
    $name =~ s/\A[._-]+//;
    $name =~ s/[._-]+\z// if $name !~ /\.[0-9A-Za-z]{1,10}\z/;
    $name = substr($name, 0, 180) if length($name) > 180;
    return length($name) ? $name : 'attachment.bin';
}

sub _basename {
    my ($path) = @_;

    $path //= q{};
    $path =~ s{.*[\\/]}{};
    return $path;
}

sub _validate_artifact_name {
    my ($name) = @_;
    defined($name) && length($name) <= 240 &&
        $name =~ /\A[0-9A-Za-z][0-9A-Za-z._-]*\z/
        or die "telpoll: artifact name is invalid\n";
    return;
}

sub _message_epoch {
    my ($value) = @_;
    my $now = time();
    return int($value)
        if defined($value) && "$value" =~ /\A[0-9]{1,12}\z/ &&
            $value >= 0 && $value <= $now + 86_400;
    return int($now);
}

sub _bounded_integer {
    my ($value, $label) = @_;
    defined($value) && !ref($value) && "$value" =~ /\A[0-9]{1,16}\z/
        or die "telpoll: Telegram $label is invalid\n";
    return "$value";
}

1;
