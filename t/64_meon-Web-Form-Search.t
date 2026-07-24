#!/usr/bin/perl

use strict;
use warnings;
use utf8;

use Test::Most;

use meon::Web::ResponseXML;
use meon::Web::SearchAPI::SearchResponse;

{

    package Test::meon::Web::Form::Search::FakeClient;

    sub new {
        my ( $class, %args ) = @_;
        return bless {
            response => $args{response},
            seen     => undef,
        }, $class;
    }

    sub search {
        my ( $self, $args ) = @_;
        $self->{seen} = $args;
        return $self->{response};
    }

    sub seen {
        my ($self) = @_;
        return $self->{seen};
    }
}

{

    package Test::meon::Web::Form::Search::MockC;

    sub new {
        my ( $class, %args ) = @_;
        return bless { response_xml => $args{response_xml} }, $class;
    }

    sub model {
        my ( $self, $name ) = @_;
        die 'unexpected model ' . ( $name // '' )
            unless $name eq 'ResponseXML';
        return $self->{response_xml};
    }
}

use_ok('meon::Web::Form::Search') or exit;

subtest 'submitted appends search-results XML from Data::asXML' => sub {
    my $response_obj = meon::Web::SearchAPI::SearchResponse->new_from_data(
        {   query => 'bike',
            total => 2,
            items => [
                { title => 'Bike 1', url => '/bike-1' },
                { title => 'Bike 2', url => '/bike-2' },
            ],
        }
    );

    my $fake_client = Test::meon::Web::Form::Search::FakeClient->new(
        response => $response_obj, );
    my $response_xml = meon::Web::ResponseXML->new();
    my $mock_c       = Test::meon::Web::Form::Search::MockC->new(
        response_xml => $response_xml, );

    my $form = meon::Web::Form::Search->new(
        c             => $mock_c,
        search_client => $fake_client,
    );

    $form->process( params => { q => ' bike ' } );
    ok( $form->is_valid, 'form is valid with query' );
    $form->submitted;

    is( $fake_client->seen->{query},
        'bike', 'query is trimmed before search call' );

    my $xml = $response_xml->as_xml;
    my ($search_results) = $xml->findnodes(
        '/*[local-name()="rxml"]/*[local-name()="search-results"]');
    ok( $search_results, 'search-results element appended' );

    my $xml_str = $xml->toString;
    like( $xml_str, qr/<search-results\b/, 'has search-results node' );
    like( $xml_str, qr/bike/,   'serialized response contains query text' );
    like( $xml_str, qr/Bike 1/, 'serialized response contains first item' );
};

done_testing();
