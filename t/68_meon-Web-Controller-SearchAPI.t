#!/usr/bin/env perl
use strict;
use warnings;
use utf8;

use Test::More;
use Test::Dirs qw(temp_copy_ok);
use FindBin qw($Bin);
use Path::Class qw(dir);
use File::Copy::Recursive qw(dircopy);
use Monkey::Patch::Action qw(patch_package);
use HTTP::Request::Common qw(GET POST);
use HTTP::Response;
use HTTP::Cookies;
use Plack::Test;
use meon::Web::SPc;
use LWP::UserAgent;
use Encode qw(encode);
use Compress::Zlib qw(compress);
use Async::MicroserviceReq;
use Hash::MultiValue;
use Test::MockTime qw(set_fixed_time restore_time);

my $fixtures = temp_copy_ok(dir($Bin, 'tsp'), 'isolated site fixtures');
my $prefix = dir($fixtures->dirname);
my $sites = $prefix->subdir('srv', 'www', 'meon-web');
my $restricted = $sites->subdir('access_restricted_t');
$prefix->subdir('var', 'lib', 'meon-web', 'global-members')->mkpath;
for my $site (qw(access_disabled_t access_missing_t)) {
    for my $part (qw(content template)) {
        dircopy($restricted->subdir($part), $sites->subdir($site, $part))
            or die "copy $part for $site: $!";
    }
}
for my $site (qw(access_restricted_t access_disabled_t access_missing_t)) {
    $sites->subdir($site, 'content', 'members', 'profile')->mkpath;
    my $profile = $sites->file($site, 'content', 'members', 'profile', 'tester', 'index.xml');
    $profile->dir->mkpath;
    my $fh = $profile->openw or die "open $profile: $!";
    print {$fh} '<page xmlns="http://web.meon.eu/"><meta>'
        . '<user xmlns="http://search.cpan.org/perldoc?Catalyst%3A%3AAuthentication%3A%3AStore%3A%3AUserXML">'
        . '<status>active</status><username>tester</username>'
        . '<password>{CLEARTEXT}autocomplete-password</password></user>'
        . '</meta><content/></page>';
    close $fh or die "close $profile: $!";
}
my $searchapi_url = 'http://127.0.0.1:5001/_mws_1';
my $backend_url = "$searchapi_url/autocomplete";
for my $site (qw(access_restricted_t access_disabled_t)) {
    my $config = $sites->file($site, 'config.ini');
    my $fh = $config->opena or die "open $config: $!";
    print {$fh} "\n[search]\nsearchapi_url = $searchapi_url\n";
    close $fh or die "close $config: $!";
}
my $patch_prefix = patch_package('meon::Web::SPc', 'prefix', 'replace',
    sub { $prefix });

# Replace only outbound HTTP transport; routing and sessions remain real.
my @outbound;
my @ua_settings;
my $transport_failure;
my $negotiate_backend;
my $backend_response = HTTP::Response->new(200, 'OK',
    ['Content-Type' => 'application/json'], '{"query":"bike","total":0,"items":[]}');
my $transport = patch_package('LWP::UserAgent', 'request', 'replace', sub {
    my ($ua, $req) = @_;
    push @outbound, $req->clone;
    push @ua_settings, [$ua->timeout, $ua->max_redirect];
    die "private backend diagnostics\n" if $transport_failure;
    return negotiated_error($req->headers) if $negotiate_backend;
    return $backend_response->clone;
});

require meon::Web;
my $realm = meon::Web->get_auth_realm('default');
$realm->credential(meon::Web->get_auth_realm('members')->credential)
    unless $realm->credential;
my $app = meon::Web->apply_session_middleware(meon::Web->psgi_app,
    cache_root => $prefix->subdir('sessions')->stringify, secure => 0);

test_psgi app => $app, client => sub {
    my ($client) = @_;
    subtest 'unconfigured site disables the endpoint' => sub {
        my $res = $client->(json_post('missing.test', '{"query":"bike"}'));
        is($res->code, 404, 'endpoint is opt-in');
        is(meon::Web::env->request_base, 'http://missing.test/',
            'Root records the current request base for default API clients');
        like($res->header('Content-Type') // '', qr{application/json}, 'JSON error');
        is($res->header('Cache-Control'), 'no-store', 'error cannot be cached');
        is(scalar @outbound, 0, 'disabled endpoint makes no backend request');
    };
    subtest 'authentication gates restricted sites, including malformed JSON' => sub {
        for my $payload ('{"query":"bike"}', '{broken json') {
            my $req = json_post('restricted.test', $payload);
            $req->header(Cookie => 'meon_web_session=' . ('a' x 40));
            my $res = $client->($req);
            is($res->code, 401, 'restricted site rejects anonymous request');
            like($res->header('Content-Type') // '', qr{application/json}, 'JSON error');
            is($res->header('Cache-Control'), 'no-store', 'rejection cannot be cached');
            is($res->header('Set-Cookie'), undef, 'no anonymous session created');
            unlike($res->content, qr/LOGIN_PAGE_CONTENT/, 'does not render HTML login');
        }
        is(scalar @outbound, 0, 'denied requests never reach backend');
    };
    subtest 'old private proxy paths are not aliases' => sub {
        for my $path ('/autocomplete', '/mws_1/autocomplete') {
            my $res = $client->(POST "http://restricted.test$path",
                Content_Type => 'application/json', Content => '{}');
            is($res->code, 404, "$path no longer invokes the private proxy");
        }
        is(scalar @outbound, 0, 'old paths make no backend request');
    };
    subtest 'public sites proxy without authentication' => sub {
        local meon::Web::Config->get->{access_missing_t}{search} = {
            searchapi_url => $searchapi_url,
        };
        for my $host (qw(disabled.test missing.test)) {
            my $payload = '{"query":"bike"}';
            my $before = scalar @outbound;
            my $res = $client->(json_post($host, $payload));
            is($res->code, 200, "$host accepts an anonymous request");
            is($res->content, $backend_response->content, 'backend response preserved');
            is($res->header('Cache-Control'), 'no-store', 'response cannot be cached');
            is($res->header('Set-Cookie'), undef, 'no anonymous session created');
            is(scalar @outbound, $before + 1, 'one backend request');
            if (@outbound > $before) {
                is($outbound[-1]->content, $payload, 'request body preserved');
                is($outbound[-1]->header('Host'), $host, 'website index selected');
            }
        }
    };
    for my $host (qw(restricted.test disabled.test)) {
        subtest "$host authenticated transparent proxy and logout" => sub {
            my $jar = login($client, $host);
            my $payload = encode('UTF-8', qq{ { "query" : "Grün \\u00e4", "limit": 3, "search_type": ["page"] }\n});
            my $req = json_post($host, $payload);
            $req->header('HTTP_X_FORWARDED_HOST' => 'attacker.test');
            $req->header(Authorization => 'Bearer browser-secret');
            my $before = scalar @outbound;
            my $res = request($client, $jar, $req);
            is($res->code, 200, 'authenticated request succeeds');
            is(scalar @outbound, $before + 1, 'exactly one upstream request');
            is($res->content, $backend_response->content, 'response bytes preserved');
            is($res->header('Content-Type'), 'application/json', 'upstream type preserved');
            is($res->header('Cache-Control'), 'no-store', 'success cannot be cached');
            if (@outbound > $before) {
                my $sent = $outbound[-1];
                is($sent->uri->as_string, $backend_url, 'fixed configured backend URL');
                is($sent->method, 'POST', 'upstream method preserved');
                is($sent->content, $payload, 'raw UTF-8 whitespace and escapes preserved');
                is($sent->header('Content-Type'), $req->header('Content-Type'), 'request type preserved');
                is($sent->header('Cookie'), undef, 'no browser cookie forwarded');
                is($sent->header('Authorization'), undef, 'no browser credential forwarded');
                is($sent->header('Host'), $host, 'trusted upstream Host');
                my $pending = 0;
                my $api_req = Async::MicroserviceReq->new(
                    method => $sent->method, headers => $sent->headers,
                    path => '/_mws_1/autocomplete', content => $sent->content,
                    params => Hash::MultiValue->new, static_dir => $prefix,
                    jsonp => '', using_frontend_proxy => 1,
                    server_host => '127.0.0.1', server_port => 5001,
                    pending_ref => \$pending, request_timeout => 30);
                is($api_req->http_host, $host, 'installed API selects the website hostname');
                is_deeply($ua_settings[-1], [30, 0], 'bounded timeout and redirects disabled');
            }
            $before = scalar @outbound;
            my $unknown_host = json_post($host, '{}');
            $unknown_host->header('X-Forwarded-Host' => 'attacker.test');
            $res = request($client, $jar, $unknown_host);
            is($res->code, 404, 'Root rejects an unconfigured forwarded website hostname');
            is(scalar @outbound, $before, 'unknown website never forwarded');
            $res = request($client, $jar, GET "http://$host/_mws_1/autocomplete");
            is($res->code, 405, 'GET is unsupported');
            is($res->header('Allow'), 'POST', 'POST advertised');
            is(scalar @outbound, $before, 'wrong method never forwarded');
            $res = request($client, $jar, GET "http://$host/logout");
            is($res->code, 302, 'real logout succeeds');
            $res = request($client, $jar, json_post($host, $payload));
            if ($host eq 'restricted.test') {
                is($res->code, 401, 'logout revokes restricted-site access');
                is(scalar @outbound, $before, 'logged out request never forwarded');
            }
            else {
                is($res->code, 200, 'public site remains accessible after logout');
                is(scalar @outbound, $before + 1, 'public request forwarded after logout');
            }
        };
    }
    subtest 'upstream response contract, transport failures and configuration' => sub {
        my $jar = login($client, 'restricted.test');
        for my $case (
            [400, 'text/plain', 'query is required', undef],
            [500, 'text/plain', 'search backend query failed', undef],
            [400, 'text/plain', encode('UTF-8', 'Ungültige Suche'), undef],
            [200, 'application/json', encode('UTF-8', '{"title":"Grün"}'), undef],
            [200, 'application/json', compress('{"items":[]}'), 'deflate'],
            [302, 'text/plain', 'upstream redirect', undef],
        ) {
            my ($code, $type, $body, $encoding) = @$case;
            $backend_response = HTTP::Response->new($code, 'Backend status',
                ['Content-Type' => $type, 'Set-Cookie' => 'backend-secret=1',
                 'Cache-Control' => 'public', 'Connection' => 'close',
                 'Location' => 'http://internal.test/redirect'], $body);
            $backend_response->header('Content-Encoding' => $encoding) if $encoding;
            my $before = scalar @outbound;
            my $res = request($client, $jar, json_post('restricted.test', '{broken json'));
            is($res->code, $code, 'upstream status preserved');
            is($res->content, $body, 'upstream bytes preserved');
            is($res->header('Content-Type'), $type, 'upstream type preserved');
            is($res->header('Content-Encoding'), $encoding, 'encoding preserved');
            unlike($res->header('Set-Cookie') // '', qr/backend-secret/, 'backend cookie withheld');
            is($res->header('Cache-Control'), 'no-store', 'backend cache policy overridden');
            is($res->header('Connection'), undef, 'hop-by-hop header withheld');
            is(scalar @outbound, $before + 1, 'no retries or redirect follow-up');
        }
        for my $failure (qw(timeout exception)) {
            $transport_failure = $failure eq 'exception';
            $backend_response = HTTP::Response->new(500, 'read timeout',
                ['Client-Warning' => 'Internal response'], 'private backend diagnostics');
            my $res = request($client, $jar, json_post('restricted.test', '{}'));
            is($res->code, 502, 'transport failure maps to bad gateway');
            like($res->header('Content-Type') // '', qr{application/json}, 'failure is JSON');
            unlike($res->content, qr/private backend|127\.0\.0\.1/, 'internal details withheld');
        }
        $transport_failure = 0;
        my $cfg = meon::Web::Config->get->{access_restricted_t}{search};
        for my $bad_url ('file:///etc/passwd', 'http:', '/autocomplete') {
            local $cfg->{searchapi_url} = $bad_url;
            my $before = scalar @outbound;
            my $res = request($client, $jar, json_post('restricted.test', '{}'));
            is($res->code, 502, 'invalid backend URL fails closed');
            is(scalar @outbound, $before, 'invalid URL makes no outbound request');
        }
    };
    subtest 'configured search API base selects the autocomplete endpoint' => sub {
        my $jar = login($client, 'restricted.test');
        my $cfg = meon::Web::Config->get->{access_restricted_t}{search};
        $backend_response = HTTP::Response->new(200, 'OK',
            ['Content-Type' => 'application/json'], '{"items":[]}');
        for my $base (
            'http://127.0.0.1:5001/mws_1',
            'http://127.0.0.1:5001/_mws_1/',
            'https://backend.test/custom/api',
            'http://127.0.0.1:5001',
        ) {
            local $cfg->{searchapi_url} = $base;
            my $before = scalar @outbound;
            my $res = request($client, $jar, json_post('restricted.test', '{}'));
            is($res->code, 200, "$base proxies successfully");
            is(scalar @outbound, $before + 1, 'one upstream request');
            my $expected = $base;
            $expected =~ s{/+$}{};
            is($outbound[-1]->uri->as_string, "$expected/autocomplete",
                'endpoint appended under configured base') if @outbound > $before;
        }
    };
    subtest 'Accept negotiation matches a direct backend request' => sub {
        my $jar = login($client, 'restricted.test');
        $negotiate_backend = 1;
        for my $accept (undef, 'application/json', 'text/plain') {
            my $req = json_post('restricted.test', '{}');
            $req->header(Accept => $accept) if defined($accept);
            my $direct = negotiated_error($req->headers);
            my $before = scalar @outbound;
            my $res = request($client, $jar, $req);
            is(scalar @outbound, $before + 1, 'one negotiated backend request');
            next unless @outbound > $before;
            is($outbound[-1]->header('Accept'), $accept, 'Accept preserved including absence');
            is($res->code, $direct->code, 'direct validation status preserved');
            is($res->header('Content-Type'), $direct->header('Content-Type'),
                'direct negotiated content type preserved');
            is($res->content, $direct->content, 'direct negotiated body bytes preserved');
        }
        $negotiate_backend = 0;
    };
    subtest 'expired authenticated session cannot proxy' => sub {
        my $now = time;
        set_fixed_time($now);
        my $jar = login($client, 'restricted.test');
        my $req = json_post('restricted.test', '{}');
        $jar->add_cookie_header($req);
        set_fixed_time($now + 5 * 3600);
        my $before = scalar @outbound;
        my $res = $client->($req);
        is($res->code, 401, 'expired server session rejected even with saved cookie');
        is(scalar @outbound, $before, 'expired session never reaches backend');
        restore_time();
    };
};
done_testing;

sub json_post {
    my ($host, $payload) = @_;
    return POST "http://$host/_mws_1/autocomplete",
        Content_Type => 'application/json; charset=utf-8', Content => $payload;
}

sub request {
    my ($client, $jar, $req) = @_;
    $jar->add_cookie_header($req);
    my $res = $client->($req);
    $res->request($req);
    $jar->extract_cookies($res);
    return $res;
}

sub login {
    my ($client, $host) = @_;
    my $jar = HTTP::Cookies->new;
    my $res = request($client, $jar, POST "http://$host/login",
        [username => 'tester', password => 'autocomplete-password']);
    is($res->code, 302, 'real fixture user authenticated');
    like($res->header('Set-Cookie') // '', qr/meon_web_session=/, 'session persisted');
    return $jar;
}

sub negotiated_error {
    my ($headers) = @_;
    my $pending = 0;
    my $api_req = Async::MicroserviceReq->new(
        method => 'POST', headers => $headers, path => '/_mws_1/autocomplete',
        content => '{}', params => Hash::MultiValue->new, static_dir => $prefix,
        jsonp => '', using_frontend_proxy => 1,
        pending_ref => \$pending, request_timeout => 30,
        plack_respond => sub {
            my ($res) = @_;
            return HTTP::Response->new($res->[0], undef, $res->[1], join('', @{$res->[2]}));
        });
    return $api_req->respond(400, [], 'query is required');
}
