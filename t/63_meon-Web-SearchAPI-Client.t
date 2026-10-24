#!/usr/bin/perl

use strict;
use warnings;
use utf8;

use Test::Most;
use JSON::XS;
use HTTP::Response;
use Monkey::Patch::Action qw(patch_package);
use Async::MicroserviceReq;
use Hash::MultiValue;
use Path::Class qw(dir);
use meon::Web::env;

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

subtest 'search sends POST to /_mws_1/search' => sub {
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
        'http://example.test/_mws_1/search',
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

subtest 'lazy client sends search to configured API or request base' => sub {
    meon::Web::env->clear;
    my $lazy_client;
    lives_ok { $lazy_client = meon::Web::SearchAPI::Client->new() }
        'no-argument construction does not need a request environment';
    meon::Web::env->hostname('website.test');
    meon::Web::env->request_base('https://website.test:8443/app/');
    my @urls;
    my $transport = patch_package('LWP::UserAgent', 'post', 'replace', sub {
        my ($ua, $url) = @_;
        push @urls, $url;
        return HTTP::Response->new(200, 'OK',
            ['Content-Type' => 'application/json'], '{"query":"bike","total":0,"items":[]}');
    });
    for my $case (
        [{}, 'https://website.test:8443/app/_mws_1/search'],
        [{search => {}}, 'https://website.test:8443/app/_mws_1/search'],
        [{search => {searchapi_url => undef}}, 'https://website.test:8443/app/_mws_1/search'],
        [{search => {searchapi_url => ''}}, 'https://website.test:8443/app/_mws_1/search'],
        [{search => {searchapi_url => 'http://127.0.0.1:5001/_mws_1'}},
            'http://127.0.0.1:5001/_mws_1/search'],
        [{search => {searchapi_url => 'http://127.0.0.1:5001/mws_1/'}},
            'http://127.0.0.1:5001/mws_1/search'],
        [{search => {searchapi_url => 'https://backend.test:9443/custom/api/'}},
            'https://backend.test:9443/custom/api/search'],
        [{search => {searchapi_url => 'http://[::1]:5001/mws_1'}},
            'http://[::1]:5001/mws_1/search'],
        [{search => {searchapi_url => 'http://backend.test:5001'}},
            'http://backend.test:5001/search'],
    ) {
        my ($config, $expected) = @$case;
        my $url = $config->{search} ? $config->{search}{searchapi_url} : undef;
        my $config_patch = patch_package('meon::Web::env', 'hostname_config',
            'replace', sub { $config });
        my $client = $lazy_client // meon::Web::SearchAPI::Client->new();
        undef $lazy_client;
        $client->search({query => 'bike'});
        is($urls[-1], $expected, 'search selects ' . $expected);
        my $ua = $client->user_agent;
        is(scalar $ua->default_header('Host'), undef,
            'client leaves Host selection to LWP');
        is(scalar $ua->default_header('HTTP_X_FORWARDED_HOST'), $url ? 'website.test' : undef,
            'configured client forwards website hostname');
        if ($url) {
            my $pending = 0;
            my $request = Async::MicroserviceReq->new(
                method => 'POST', headers => $ua->default_headers,
                path => '/search', content => '{}', params => Hash::MultiValue->new,
                static_dir => dir('.'), jsonp => '', using_frontend_proxy => 1,
                server_host => '127.0.0.1', server_port => 5001,
                pending_ref => \$pending, request_timeout => 30,
            );
            is($request->http_host, 'website.test', 'installed backend selects website using forwarded host');
        }
        my $explicit = meon::Web::SearchAPI::Client->new(
            base_url => 'https://explicit.test', api_prefix => '/chosen');
        $explicit->search({query => 'bike'});
        is($urls[-1], 'https://explicit.test/chosen/search',
            'explicit base and prefix override configuration');
    }
    meon::Web::env->clear;
};

done_testing();
