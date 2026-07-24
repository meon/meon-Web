#!/usr/bin/perl

use strict;
use warnings;
use utf8;

use Test::Most;
use JSON::XS;

my $json = JSON::XS->new->utf8(1)->canonical(1);

{

    package Test::meon::Web::SearchAPI::Client::FakeResponse;

    sub new {
        my ( $class, %args ) = @_;
        return bless {%args}, $class;
    }

    sub is_success      { return shift->{is_success}; }
    sub code            { return shift->{code}; }
    sub status_line     { return shift->{status_line}; }
    sub decoded_content { return shift->{decoded_content}; }
}

{

    package Test::meon::Web::SearchAPI::Client::FakeUA;

    sub new {
        my ( $class, %args ) = @_;
        return bless {
            response  => $args{response},
            last_url  => undef,
            last_args => undef,
        }, $class;
    }

    sub post {
        my ( $self, $url, %args ) = @_;
        $self->{last_url}  = $url;
        $self->{last_args} = \%args;
        return $self->{response};
    }

    sub last_url  { return shift->{last_url}; }
    sub last_args { return shift->{last_args}; }
}

use_ok('meon::Web::SearchAPI::Client')         or exit;
use_ok('meon::Web::SearchAPI::SearchResponse') or exit;

subtest 'search sends POST to /mws_1/search' => sub {
    my $resp = Test::meon::Web::SearchAPI::Client::FakeResponse->new(
        is_success      => 1,
        code            => 200,
        status_line     => '200 OK',
        decoded_content => $json->encode(
            { query => 'second product', total => 2, items => [] }
        ),
    );

    my $ua =
        Test::meon::Web::SearchAPI::Client::FakeUA->new( response => $resp );

    my $client = meon::Web::SearchAPI::Client->new(
        base_url   => 'http://example.test',
        user_agent => $ua,
    );

    my $res = $client->search(
        {   query => 'second product',
            page  => 2,
            size  => 5,
        }
    );

    is( $ua->last_url,
        'http://example.test/mws_1/search',
        'calls search endpoint'
    );

    is( $json->decode( $ua->last_args->{Content} )->{query},
        'second product',
        'query is sent in payload'
    );
    isa_ok( $res, 'meon::Web::SearchAPI::SearchResponse' );
    is( $res->total, 2, 'returns response object with total value' );
};

subtest 'search dies on non-success response' => sub {
    my $resp = Test::meon::Web::SearchAPI::Client::FakeResponse->new(
        is_success      => 0,
        code            => 502,
        status_line     => '502 Bad Gateway',
        decoded_content => 'upstream failed',
    );
    my $ua =
        Test::meon::Web::SearchAPI::Client::FakeUA->new( response => $resp );

    my $client = meon::Web::SearchAPI::Client->new(
        base_url   => 'http://example.test/',
        user_agent => $ua,
    );

    throws_ok(
        sub {
            $client->search( { query => 'test' } );
        },
        qr/HTTP 502 Bad Gateway/,
        'dies with upstream status'
    );
};

done_testing();
