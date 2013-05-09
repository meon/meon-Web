package meon::Web::Util;

use Text::Unidecode 'unidecode';
use Path::Class 'dir';

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

    return $path;
}

1;
