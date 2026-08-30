package ExternalSoftware::Servicing::Atomic;

use strict;
use warnings;

use Moo;
use MooX::StrictConstructor;

use Fcntl qw(:DEFAULT O_CREAT O_EXCL O_NOFOLLOW);
use File::Basename qw(dirname);
use File::Path qw(make_path);
use File::Spec;

sub assert_absolute_path {
    my ($class, $label, $path) = @_;
    defined $path && $path =~ m{\A/(?:[A-Za-z0-9._@%:+,-]+/)*[A-Za-z0-9._@%:+,-]+\z}
        or die "$label must be a safe absolute path\n";
    return $path;
}

sub assert_child {
    my ($class, $directory, $name) = @_;
    $class->assert_absolute_path('parent directory', $directory);
    defined $name && $name =~ /\A[A-Za-z0-9._:+~,-]+\z/
        or die "unsafe managed filename\n";
    my $path = File::Spec->catfile($directory, $name);
    index($path, "$directory/") == 0 or die "managed path escaped its parent\n";
    return $path;
}

sub ensure_root_directory {
    my ($class, $path, $mode) = @_;
    $class->assert_absolute_path('managed directory', $path);
    if (!-e $path) {
        make_path($path, { mode => $mode }) or die "failed to create $path\n";
    }
    -d $path && !-l $path or die "managed path is not a directory: $path\n";
    my @st = lstat $path or die "failed to stat $path: $!\n";
    $st[4] == 0 or die "managed path must be root-owned: $path\n";
    chmod $mode, $path or die "failed to set mode on $path: $!\n";
    return $path;
}

sub read_limited {
    my ($class, $path, $limit) = @_;
    $class->assert_absolute_path('input path', $path);
    -f $path && !-l $path or die "expected a regular file: $path\n";
    my $size = -s $path;
    defined $size && $size <= $limit or die "input exceeds size limit: $path\n";
    open my $fh, '<:raw', $path or die "failed to read $path: $!\n";
    local $/;
    my $content = <$fh>;
    close $fh or die "failed to close $path: $!\n";
    return defined $content ? $content : q{};
}

sub write_text {
    my ($class, $path, $text, $mode) = @_;
    $class->assert_absolute_path('output path', $path);
    my $directory = dirname($path);
    $class->ensure_root_directory($directory, 0755);
    -l $path and die "output path must not be a symlink: $path\n";
    my $temporary = "$path.tmp.$$";
    sysopen my $fh, $temporary, O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW, $mode
        or die "failed to open temporary output $temporary: $!\n";
    print {$fh} $text or die "failed to write temporary output $temporary: $!\n";
    close $fh or die "failed to close temporary output $temporary: $!\n";
    chmod $mode, $temporary or die "failed to set mode on temporary output $temporary: $!\n";
    rename $temporary, $path or die "failed to publish $path: $!\n";
    return $path;
}

sub remove_tree {
    my ($class, $path) = @_;
    $class->assert_absolute_path('removal path', $path);
    return 1 if !-e $path && !-l $path;
    File::Path::remove_tree($path, { safe => 1, error => \my $errors });
    @{$errors} and die "failed to remove managed path $path\n";
    return 1;
}

1;
