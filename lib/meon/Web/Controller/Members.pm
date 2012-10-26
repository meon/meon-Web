package meon::Web::Controller::Members;
use Moose;
use 5.010;
use utf8;
use namespace::autoclean;

use File::MimeInfo 'mimetype';

BEGIN {extends 'Catalyst::Controller'; }

sub auto : Private {
    my ( $self, $c ) = @_;
}

sub base : Chained('/') PathPart('members') CaptureArgs(0) {
    my ( $self, $c ) = @_;

    $c->detach('/login',[])
        unless $c->user_exists;
}

sub download : Chained('base') PathPart('download') {
    my ( $self, $c, @filename ) = @_;

    my $download_folder = $c->stash->{hostname_folder}->subdir('members', 'download');
    my $file = $download_folder->file(@filename)->absolute->resolve;
    $c->detach('/status_forbidden', [join('/', @filename)])
        unless $download_folder->contains($file);
    $c->detach('/status_not_found', [join('/', @filename)])
        unless -e $file;

    my $mime_type = mimetype($filename[-1]);
    $c->res->content_type($mime_type);
    $c->res->body($file->open('r'));
}

__PACKAGE__->meta->make_immutable;

1;
