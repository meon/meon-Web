package meon::Web::Form::Search;

use strict;
use warnings;
use 5.010;

use Data::asXML;
use meon::Web::SearchAPI::Client;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';
with 'meon::Web::Role::Form';

has '+name'           => ( default => 'form-search' );
has '+widget_wrapper' => ( default => 'Bootstrap' );
has '+http_method'    => ( default => 'GET' );

has_field 'q' => (
    type     => 'Text',
    required => 1,
    label    => 'Search',
);
has_field 'submit' => (
    type  => 'Submit',
    value => 'Search',
);

has 'search_client' => (
    is      => 'ro',
    isa     => 'Object',
    lazy    => 1,
    builder => '_build_search_client',
);

sub _build_search_client {
    my ($self) = @_;

    return meon::Web::SearchAPI::Client->new(
        base_url => $self->c->req->base->as_string, );
}

sub submitted {
    my ($self) = @_;

    my $query = $self->field('q')->value // '';
    $query =~ s/^\s+|\s+$//g;

    my $search_response =
        $self->search_client->search( { query => $query, } );

    my $search_results_el =
        $self->c->model('ResponseXML')->create_element('search-results');
    my $dxml = Data::asXML->new(
        namespace => 1,
        pretty    => 0,
    );
    $search_results_el->appendChild(
        $dxml->encode( $search_response->as_data ) );

    $self->c->model('ResponseXML')->append_xml($search_results_el);
}

no HTML::FormHandler::Moose;

1;
