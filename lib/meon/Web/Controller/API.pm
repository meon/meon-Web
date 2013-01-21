package meon::Web::Controller::API;
use Moose;
use 5.010;
use utf8;
use namespace::autoclean;

use meon::Web::Util;

BEGIN {extends 'Catalyst::Controller'; }

sub auto : Private {
    my ( $self, $c ) = @_;
}

sub base : Chained('/') PathPart('api') CaptureArgs(0) {
    my ( $self, $c ) = @_;

}

sub username : Chained('base') PathPart('username') {
    my ( $self, $c ) = @_;

    my $username = $c->req->param('username');
    $username = meon::Web::Util->username_cleanup($username, $c->default_auth_store->folder);

    $c->json_reply({
        username => $username,
    });
}


__PACKAGE__->meta->make_immutable;

1;
