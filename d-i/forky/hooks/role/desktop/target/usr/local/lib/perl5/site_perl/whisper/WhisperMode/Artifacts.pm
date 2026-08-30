package WhisperMode::Artifacts;

use strict;
use warnings;

use Fcntl qw(:flock O_APPEND O_CREAT O_NOFOLLOW O_RDWR O_WRONLY);
use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempfile);
use JSON::PP qw(decode_json encode_json);
use Moo;
use MooX::StrictConstructor;
use MooX::TypeTiny;
use Types::Standard qw(Int Str);

has home => (
    is      => 'ro',
    isa     => Str,
    lazy    => 1,
    builder => '_build_home',
);
has max_artifacts => ( is => 'ro', isa => Int, default => sub { 20 } );

sub _fatal {
    my ($message) = @_;
    die "whisper-record-toggle: $message\n";
}

sub _build_home {
    my $path = $ENV{HOME};
    defined($path) && $path =~ m{\A/} && $path !~ m{\0|(?:\A|/)\.\.(?:/|\z)|//}
        or _fatal('HOME is invalid');
    -d $path && !-l $path && (lstat $path)[4] == $<
        or _fatal('HOME must be a user-owned real directory');
    return $path;
}

sub _directory {
    my ($self, $label, $path) = @_;
    if (!-e $path) {
        make_path($path, { mode => 0700 }) or _fatal("cannot create $label");
    }
    -d $path && !-l $path && (lstat $path)[4] == $<
        or _fatal("$label must be a user-owned real directory");
    chmod 0700, $path or _fatal("cannot secure $label: $!");
    return $path;
}

sub paths {
    my ($self) = @_;
    my $root = $self->_directory('Whisper root directory', File::Spec->catdir($self->home(), 'Music', 'Whisper'));
    return {
        audio       => $self->_directory('Whisper audio directory', File::Spec->catdir($root, 'audio')),
        transcribed => $self->_directory('Whisper transcription directory', File::Spec->catdir($root, 'transcribed')),
    };
}

sub sleek {
    my ($self) = @_;
    my $directory = $self->_directory('Sleek task directory', File::Spec->catdir($self->home(), 'Syncthing', 'sleek'));
    my $file = "$directory/whisper.txt";
    if (-e $file) {
        -f $file && !-l $file && (lstat $file)[4] == $<
            or _fatal('Sleek task file is unsafe');
    } else {
        $self->_atomic_write($directory, 'whisper.txt', q{});
    }
    chmod 0600, $file or _fatal("cannot secure Sleek task file: $!");
    return { directory => $directory, task_file => $file };
}

sub validate_wav {
    my ($self, $state) = @_;
    my $paths = $self->paths();
    my $expected = "$paths->{audio}/$state->{stem}.wav";
    $state->{wav} eq $expected or _fatal('runtime state recording escaped the managed audio directory');
    return $expected;
}

sub _atomic_write {
    my ($self, $directory, $name, $content) = @_;
    $name =~ /\A[0-9A-Za-z._-]+\z/ or _fatal('unsafe artifact name');
    my ($fh, $temporary) = tempfile(".$name.XXXXXX", DIR => $directory, UNLINK => 0);
    binmode $fh, ':raw';
    print {$fh} $content or _fatal("cannot write temporary artifact: $!");
    close $fh or _fatal("cannot close temporary artifact: $!");
    chmod 0600, $temporary or _fatal("cannot secure temporary artifact: $!");
    rename $temporary, "$directory/$name" or _fatal("cannot publish artifact: $!");
}

sub _validated_stem {
    my ($stem) = @_;
    defined($stem) && $stem =~ /\A[0-9]{4}(?:-[0-9]{2}){5}\z/
        or _fatal('Whisper artifact stem is invalid');
    return $stem;
}

sub _normalized_task_text {
    my ($text) = @_;
    $text //= q{};
    $text =~ s/[\p{Cc}\p{Cf}]+/ /gu;
    $text =~ s/\s+/ /gu;
    $text =~ s/\A\s+|\s+\z//gu;
    return $text;
}

sub store_transcript {
    my ($self, $stem, $text) = @_;
    $stem = _validated_stem($stem);
    $text = _normalized_task_text($text);
    my $paths = $self->paths();
    $self->_atomic_write($paths->{transcribed}, "$stem.json", encode_json({ text => $text }) . "\n");
}

sub append_task {
    my ($self, $stem, $text) = @_;
    $stem = _validated_stem($stem);
    $text = _normalized_task_text($text);
    return if !length $text;
    my $sleek = $self->sleek();
    sysopen my $lock, "$sleek->{directory}/.whisper.txt.lock", O_CREAT | O_NOFOLLOW | O_RDWR, 0600
        or _fatal("cannot open Sleek task lock: $!");
    flock($lock, LOCK_EX) or _fatal("cannot lock Sleek task file: $!");
    sysopen my $fh, $sleek->{task_file}, O_APPEND | O_NOFOLLOW | O_WRONLY
        or _fatal("cannot append Sleek task: $!");
    -f $fh or _fatal('Sleek task file is not a regular file');
    my @stat = stat $fh;
    $stat[4] == $< && ($stat[2] & 0077) == 0
        or _fatal('Sleek task file ownership or mode is unsafe');
    binmode $fh, ':encoding(UTF-8)'
        or _fatal("cannot configure Sleek task encoding: $!");
    print {$fh} substr($stem, 0, 10), " $text +whisper \@voice source:$stem\n"
        or _fatal("cannot write Sleek task: $!");
    close $fh or _fatal("cannot close Sleek task: $!");
}

sub prune {
    my ($self, $directory, $extension) = @_;
    opendir my $dh, $directory or _fatal("cannot read artifact directory: $!");
    my @files = sort { $b cmp $a } grep {
        /\A[0-9]{4}(?:-[0-9]{2}){5}\.\Q$extension\E\z/ &&
        -f "$directory/$_" && !-l "$directory/$_"
    } readdir $dh;
    closedir $dh or _fatal("cannot close artifact directory: $!");
    for my $name (@files[$self->max_artifacts() .. $#files]) {
        unlink "$directory/$name" or _fatal("cannot prune managed artifact: $name");
    }
}

sub read_json {
    my ($self, $path, $limit, $label) = @_;
    -f $path && !-l $path && -s $path <= $limit
        or _fatal("$label is missing, unsafe, or too large");
    open my $fh, '<:raw', $path or _fatal("cannot read $label: $!");
    local $/;
    my $raw = <$fh> // q{};
    close $fh or _fatal("cannot close $label: $!");
    my $data = eval { decode_json($raw) };
    $@ || ref($data) eq 'HASH' or _fatal("$label is not valid JSON");
    return $data;
}

1;
