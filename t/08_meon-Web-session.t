#!/usr/bin/perl

use strict;
use warnings;

use HTTP::Request::Common qw(GET);
use File::Temp qw(tempdir);
use Plack::Test;
use Run::Env;
use Test::More;

use meon::Web;

{
    package Local::SessionStore;

    sub new {
        return bless { data => {}, get => 0, set => 0, remove => 0 }, shift;
    }

    sub get {
        my ($self, $id) = @_;
        ++$self->{get};
        return $self->{data}{$id};
    }

    sub set {
        my ($self, $id, $session) = @_;
        ++$self->{set};
        $self->{data}{$id} = $session;
        return;
    }

    sub remove {
        my ($self, $id) = @_;
        ++$self->{remove};
        delete $self->{data}{$id};
        return;
    }
}

my $inner = sub {
    my ($env) = @_;
    my $session = $env->{'psgix.session'};
    my $options = $env->{'psgix.session.options'};

    if ($env->{PATH_INFO} eq '/write') {
        $session->{user_id} = 42;
    }
    elsif ($env->{PATH_INFO} eq '/rotate') {
        $options->{change_id} = 1;
    }
    elsif ($env->{PATH_INFO} eq '/logout') {
        %$session = ();
        $options->{expire} = 1;
    }
    else {
        my $ignored = $session->{user_id};
    }

    return [200, ['Content-Type' => 'text/plain'], ['ok']];
};
my $store = Local::SessionStore->new;
my $app = meon::Web->apply_session_middleware(
    $inner,
    store   => $store,
    expires => 3_600,
);

test_psgi app => $app, client => sub {
    my ($client) = @_;

    my $read = $client->(GET 'https://example.test/read');
    is($read->header('Set-Cookie'), undef, 'read-only request sets no cookie');
    is($store->{set}, 0, 'read-only request does not write to the store');
    is($store->{remove}, 0, 'read-only request does not remove from the store');

    my $invalid = GET 'https://example.test/read';
    $invalid->header(Cookie => 'meon_web_session=legacy-session-id');
    my $invalid_res = $client->($invalid);
    is($invalid_res->header('Set-Cookie'), undef, 'invalid old cookie fails safely');
    is($store->{get}, 0, 'invalid old cookie is not sent to the store');

    my $write = $client->(GET 'https://example.test/write');
    my $cookie = $write->header('Set-Cookie');
    like($cookie, qr/\Ameon_web_session=([0-9a-f]{40})/, 'write creates a secure session ID');
    my ($first_id) = $cookie =~ /\Ameon_web_session=([0-9a-f]{40})/;
    like($cookie, qr/; HttpOnly(?:;|\z)/i, 'session cookie is HttpOnly');
    is($store->{set}, 1, 'write persists the session once');
    is($store->{data}{$first_id}{user_id}, 42, 'written session data reaches the store');

    my $stored_read = GET 'https://example.test/read';
    $stored_read->header(Cookie => "meon_web_session=$first_id");
    my $stored_read_res = $client->($stored_read);
    is($stored_read_res->header('Set-Cookie'), undef,
        'reading an existing session does not refresh its cookie');
    is($store->{set}, 1, 'reading an existing session does not rewrite it');

    my $rotate = GET 'https://example.test/rotate';
    $rotate->header(Cookie => "meon_web_session=$first_id");
    my $rotate_res = $client->($rotate);
    my ($second_id) = ($rotate_res->header('Set-Cookie') // '')
        =~ /\Ameon_web_session=([0-9a-f]{40})/;
    ok($second_id && $second_id ne $first_id, 'rotation replaces the session ID');
    ok(!exists $store->{data}{$first_id}, 'rotation removes the old server entry');
    ok(exists $store->{data}{$second_id}, 'rotation stores the replacement entry');

    my $logout = GET 'https://example.test/logout';
    $logout->header(Cookie => "meon_web_session=$second_id");
    my $logout_res = $client->($logout);
    like($logout_res->header('Set-Cookie') // '', qr/expires=/i,
        'logout expires the browser cookie');
    ok(!exists $store->{data}{$second_id}, 'logout removes the server entry');
};

subtest 'session cookie security follows Run::Env' => sub {
    my $running_env = Run::Env->current;

    Run::Env->set_production;
    my $production_app = meon::Web->apply_session_middleware(
        $inner,
        store   => Local::SessionStore->new,
        expires => 3_600,
    );

    Run::Env->set_development;
    my $development_app = meon::Web->apply_session_middleware(
        $inner,
        store   => Local::SessionStore->new,
        expires => 3_600,
    );

    Run::Env::set($running_env);

    test_psgi app => $production_app, client => sub {
        my ($client) = @_;
        my $cookie = $client->(GET 'https://example.test/write')
            ->header('Set-Cookie');
        like($cookie, qr/; secure(?:;|\z)/i,
            'production session cookie is Secure');
    };

    test_psgi app => $development_app, client => sub {
        my ($client) = @_;
        my $cookie = $client->(GET 'https://example.test/write')
            ->header('Set-Cookie');
        unlike($cookie, qr/; secure(?:;|\z)/i,
            'development session cookie omits Secure');
    };
};

subtest 'file store factory supports expiration cleanup' => sub {
    my $factory = meon::Web->can('session_store');
    ok($factory, 'session store factory is available');
    SKIP: {
        skip 'session store factory not implemented', 2 unless $factory;

        my $store = meon::Web->session_store(
            cache_root => tempdir(CLEANUP => 1),
            expires    => 3_600,
        );
        $store->set('expired', { value => 1 }, -1);
        $store->set('active', { value => 2 });
        $store->purge;
        is($store->get('expired'), undef, 'purge removes an expired session');
        is_deeply($store->get('active'), { value => 2 },
            'purge preserves an active session');
    }
};

done_testing;
