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

sub default : Chained('base') PathPart('') {
    my ( $self, $c ) = @_;
    $c->forward('/resolve_xml', []);
}

__PACKAGE__->meta->make_immutable;

1;
