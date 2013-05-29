package meon::Web::Util;

use Text::Unidecode 'unidecode';
use Path::Class 'dir';

sub filename_cleanup {
    my ($self, $text) = @_;
    $text = unidecode($text);
    $text =~ s/\s/-/g;
    $text =~ s/-+/-/g;
    $text =~ s/[^A-Za-z0-9\-_]//g;
    return $text;
}

sub username_cleanup {
    my ($self, $username, $folder) = @_;

    $username = unidecode($username);
    $username =~ s/[^A-Za-z0-9]//g;
    while (length($username) < 4) {
        $username .= '0';
    }

    my $base_username = $username;
    my $i = 1;
    while (-d dir($folder, $username)) {
        $i++;
        my $suffix = sprintf('%02d', $i);
        $username = $base_username.$suffix;
    }

    return $username;
}

sub path_fixup {
    my ($self, $c, $path) = @_;

    my $username = (
        $c->user_exists
        ? $username = $c->user->username
        : 'me'
    );

    $path =~ s/{\$USERNAME}/$username/;

    if ($path =~ m/^(.*){\$TIMELINE_NEWEST}/) {
        my $base_dir = dir($c->stash->{xml_file}->dir, (defined($1) ? $1 : ()));
        my $dir = $base_dir;
        while (my @subfolders = sort grep { $_->basename =~ m/^\d+$/ } grep { $_->is_dir } $dir->children(no_hidden => 1)) {
            $dir = pop(@subfolders);
        }
        $dir = $dir->relative($base_dir);
        $dir .= '';
        $path =~ s/{\$TIMELINE_NEWEST}/$dir/;
    }

    return $path;
}

1;
