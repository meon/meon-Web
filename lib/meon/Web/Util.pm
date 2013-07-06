package meon::Web::Util;

use Text::Unidecode 'unidecode';
use Path::Class 'dir', 'file';
use XML::LibXML::XPathContext;

sub xpc {
    my $xpc = XML::LibXML::XPathContext->new;
    $xpc->registerNs('x', 'http://www.w3.org/1999/xhtml');
    $xpc->registerNs('w', 'http://web.meon.eu/');
    return $xpc;
}

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
    my ($self, $path) = @_;

    my $username = (
        meon::Web::env->user
        ? $username = meon::Web::env->user->username
        : 'anonymous'
    );

    $path =~ s/{\$USERNAME}/$username/;

    if ($path =~ m/^(.*){\$TIMELINE_NEWEST}/) {
        my $base_dir = dir(meon::Web::env->current_dir, (defined($1) ? $1 : ()));
        my $dir = $base_dir;
        while (my @subfolders = sort grep { $_->basename =~ m/^\d+$/ } grep { $_->is_dir } $dir->children(no_hidden => 1)) {
            $dir = pop(@subfolders);
        }
        $dir = $dir->relative($base_dir);
        $dir .= '';
        $path =~ s/{\$TIMELINE_NEWEST}/$dir/;
    }

    if ($path =~ m/{\$COMMENT_TO}/) {
        my $comment_to = meon::Web::env->stash->{comment_to};
        $path =~ s/{\$COMMENT_TO}/$comment_to/;
    }

    return $path;
}

sub full_path_fixup {
    my ($self, $path) = @_;
    $path = $self->path_fixup($path);
    my $cur_dir = meon::Web::env->current_dir;
    $cur_dir = meon::Web::env->content_dir
        if $path =~ m{^/};
    $path = file($cur_dir, $path)->absolute;
}

1;
