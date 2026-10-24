#!/usr/bin/env perl
use strict;
use warnings;
use utf8;

use Test::Most;
use Future;
use JSON::XS ();
use FindBin qw($Bin);
use Path::Class qw(dir file);
use Monkey::Patch::Action qw(patch_package);
use Scalar::Util qw(refaddr);
use Storable qw(dclone);
use Plack::Test;
use HTTP::Request::Common qw(POST);
use lib file($Bin, 'testlib')->stringify;

use meon::Web::SPc;

my $patch_prefix = patch_package(
    'meon::Web::SPc', 'prefix', 'replace',
    sub { dir(Sys::Path->find_distribution_root('meon::Web::SPc'), 't', 'tsp') }
);
require meon::Web::SearchAPI;

subtest 'standalone API routes use the infrastructure prefix' => sub {
    my $api = meon::Web::SearchAPI->new(
        static_dir => dir($Bin), using_frontend_proxy => 1);
    test_psgi app => sub { $api->plack_handler(@_) }, client => sub {
        my ($client) = @_;
        for my $route (qw(search autocomplete)) {
            my $res = $client->(POST "http://search-test.local/_mws_1/$route",
                Content_Type => 'application/json', Content => '{}');
            is($res->code, 400, "$route reaches validation under the new prefix");
            is($res->content, 'query is required', 'empty request reaches API validation');
            $res = $client->(POST "http://search-test.local/mws_1/$route",
                Content_Type => 'application/json', Content => '{}');
            is($res->code, 302, 'old prefix does not execute the API');
            like($res->header('Location'), qr{/_mws_1/$}, 'old prefix redirects to new root');
        }
    };
};

{
    package Local::SearchAPI::Request;
    sub new { my ($class, %args) = @_; bless \%args, $class }
    sub json_content {
        die "invalid json body\n" if $_[0]->{invalid_json};
        return $_[0]->{content};
    }
    sub http_host { $_[0]->{host} // 'search-test.local' }
}

{
    package Local::SearchAPI::Response;
    sub new { my ($class, $future) = @_; bless { future => $future }, $class }
    sub ft { $_[0]->{future} }
}

{
    package Local::SearchAPI::Backend;
    sub new { bless { requests => [], result => $_[1] }, $_[0] }
    sub search {
        my ($self, %request) = @_;
        push @{ $self->{requests} }, \%request;
        die "backend unavailable\n" if $self->{fail};
        my $result = ref($self->{result}) eq 'CODE'
            ? $self->{result}->(%request)
            : $self->{result};
        return Local::SearchAPI::Response->new(Future->done($result));
    }
}

sub request {
    my ($content, %extra) = @_;
    return Local::SearchAPI::Request->new(
        content => $content,
        host    => 'search-test.local',
        %extra,
    );
}

sub invoke {
    my ($method, $api, $req) = @_;
    return $api->$method($req, {})->get;
}

sub new_api {
    my ($result) = @_;
    my $backend = Local::SearchAPI::Backend->new($result);
    return ( meon::Web::SearchAPI->new(ose => $backend), $backend );
}

sub dis_max_query {
    my ($body) = @_;
    my $must = $body->{query}{bool}{must};
    return unless ref($must) eq 'ARRAY';
    for my $clause (@$must) {
        return $clause->{dis_max} if ref($clause) eq 'HASH' && ref($clause->{dis_max}) eq 'HASH';
    }
    return;
}

sub role {
    my ($branch) = @_;
    my $ss = $branch->{script_score} || {};
    my $match = $ss->{query}{match} || {};
    return 'title_all' if exists $match->{title_ngram} && ($match->{title_ngram}{operator} // '') eq 'and';
    return 'title_partial' if exists $match->{title_ngram} && ($match->{title_ngram}{operator} // '') eq 'or';
    return 'content_search' if exists $match->{search_content} && !$ss->{script}{params}{use_weight};
    return 'content_autocomplete' if exists $match->{search_content} && $ss->{script}{params}{use_weight};
    return 'unrecognized';
}

sub result_empty {
    return { hits => { total => { value => 0 }, hits => [] }, took => 1 };
}

sub error_result {
    my ($method, $api, $request) = @_;
    my $result = invoke($method, $api, $request);
    is(ref($result), 'ARRAY', "$method returns an error tuple");
    return $result;
}

subtest 'search and autocomplete use shared query roles and scoring' => sub {
    my $result = { hits => { total => { value => 0 }, hits => [] }, took => 1 };
    my ($api, $backend) = new_api($result);

    invoke('POST_search', $api, request({ query => 'Blue   Widget' }));
    invoke('POST_autocomplete', $api, request({ query => 'Blue   Widget' }));

    my ($search, $autocomplete) = map { $_->{body} } @{ $backend->{requests} };
    my $search_dis_max = dis_max_query($search);
    ok($search_dis_max, 'search query has the shared dis_max union')
        or diag explain $search->{query};
    my $autocomplete_dis_max = dis_max_query($autocomplete);
    ok($autocomplete_dis_max, 'autocomplete query has the shared dis_max union')
        or diag explain $autocomplete->{query};

    if ($search_dis_max) {
        is($search_dis_max->{tie_breaker}, 0, 'search tie breaker is zero');
        is_deeply(
            [ map { role($_) } @{ $search_dis_max->{queries} } ],
            [qw(title_all content_search title_partial content_autocomplete)],
            'search profile orders all shared roles'
        );
    }
    if ($autocomplete_dis_max) {
        is($autocomplete_dis_max->{tie_breaker}, 0, 'autocomplete tie breaker is zero');
        is_deeply(
            [ map { role($_) } @{ $autocomplete_dis_max->{queries} } ],
            [qw(title_all title_partial content_autocomplete content_search)],
            'autocomplete profile orders all shared roles'
        );
    }
    if ($search_dis_max && $autocomplete_dis_max) {
        my ($search_content) = grep { role($_) eq 'content_search' } @{ $search_dis_max->{queries} };
        my ($autocomplete_content) = grep { role($_) eq 'content_search' } @{ $autocomplete_dis_max->{queries} };
        my ($autocomplete_weighted_content) = grep { role($_) eq 'content_autocomplete' } @{ $autocomplete_dis_max->{queries} };
        is_deeply($search_content->{script_score}{query}, $autocomplete_content->{script_score}{query},
            'search and autocomplete relevance roles share the content predicate');
        is_deeply($search_content->{script_score}{query}, $autocomplete_weighted_content->{script_score}{query},
            'weighted and unweighted content roles share the match predicate');
    }
    for my $entry (
        [ $search_dis_max, [40, 30, 20, 10], [1, 0, 1, 1], 'search' ],
        [ $autocomplete_dis_max, [40, 30, 20, 10], [1, 1, 1, 0], 'autocomplete' ],
    ) {
        next unless $entry->[0];
            my ($union, $bases, $weights, $profile) = @$entry;
            for my $i (0 .. 3) {
                my $script = $union->{queries}[$i]{script_score}{script};
                is($script->{params}{base}, $bases->[$i], "$profile role $i has its planned base");
                is($script->{params}{use_weight}, $weights->[$i], "$profile role $i has its planned weight flag");
                is(JSON::XS->new->encode($script->{params}{use_weight}),
                    $weights->[$i] ? 'true' : 'false',
                    "$profile role $i passes a JSON boolean weight flag");
                is($script->{source}, q{params.base + (params.use_weight ? doc['weight'].value : 0.0) + (_score / (1.0 + _score))},
                    "$profile role $i uses shared score script");
            }
    }

};

subtest 'search request defaults, host, normalization, and pagination' => sub {
    my ($api, $backend) = new_api(result_empty());
    my $response = invoke('POST_search', $api, request({ query => ' Blue   Widget ' }));
    is($response->{query}, 'blue widget', 'response query is normalized');
    is($response->{page}, 1, 'default search page is one');
    is($response->{size}, 20, 'default search size is twenty');
    is($backend->{requests}[0]{index}, 'meon-search_search_t', 'search selects host index alias');
    is($backend->{requests}[0]{body}{from}, 0, 'default search offset is zero');
    is($backend->{requests}[0]{body}{size}, 20, 'default search backend size is twenty');

    invoke('POST_search', $api, request({ query => 'Second Product', page => 3, size => 7 }));
    is($backend->{requests}[1]{body}{from}, 14, 'page and size calculate search offset');
    is($backend->{requests}[1]{body}{size}, 7, 'requested size reaches backend');
    my $union = dis_max_query($backend->{requests}[1]{body});
    my ($content_role) = $union
        ? grep { role($_) eq 'content_search' } @{ $union->{queries} }
        : ();
    is($content_role->{script_score}{query}{match}{search_content}{query},
        'second product', 'search content predicate uses normalized query')
        if $content_role;
};

subtest 'autocomplete defaults, bounds, host, and title normalization' => sub {
    my ($api, $backend) = new_api(result_empty());
    invoke('POST_autocomplete', $api, request({ query => 'Blue-Widget' }));
    is($backend->{requests}[0]{index}, 'meon-search_search_t', 'autocomplete selects host index alias');
    is($backend->{requests}[0]{body}{size}, 10, 'default autocomplete limit is ten');
    my $union = dis_max_query($backend->{requests}[0]{body});
    ok($union, 'autocomplete request contains union');
    if ($union) {
        my @matches = map { $_->{script_score}{query}{match} } @{ $union->{queries} };
        like($matches[0]{title_ngram}{query}, qr/^bl/, 'title query uses exploded normalized terms');
        is($matches[0]{title_ngram}{operator}, 'and', 'all-title predicate requires every ngram');
        is($matches[1]{title_ngram}{operator}, 'or', 'partial-title predicate uses any ngram');
        is($matches[1]{title_ngram}{minimum_should_match}, '85%', 'partial-title predicate retains threshold');
        is($matches[2]{search_content}{query}, 'blue-widget', 'content predicate uses normalized original query');
        is($matches[2]{search_content}{operator}, 'and', 'content predicate requires all normalized tokens');
    }
    invoke('POST_autocomplete', $api, request({ query => 'Blue Widget', limit => 100 }));
    is($backend->{requests}[1]{body}{size}, 100, 'maximum autocomplete limit is accepted');
    invoke('POST_autocomplete', $api, request({ query => 'Blue Widget', limit => 1 }));
    is($backend->{requests}[2]{body}{size}, 1, 'minimum autocomplete limit is accepted');
};

subtest 'type filters remain outside the union and all supported types are accepted' => sub {
    for my $method (qw(POST_search POST_autocomplete)) {
        my ($api, $backend) = new_api(result_empty());
        invoke($method, $api, request({ query => 'blue', search_type => [qw(page product category)] }));
        my $bool = $backend->{requests}[0]{body}{query}{bool};
        is_deeply($bool->{filter}, [ { terms => { search_type => [qw(page product category)] } } ],
            "$method places all supported type filters at bool level");
        my $union = dis_max_query($backend->{requests}[0]{body});
        ok($union, "$method retains the role union alongside type filter");
        ok(!exists $union->{filter}, "$method does not put type filter inside dis_max") if $union;

        invoke($method, $api, request({ query => 'blue', search_type => [] }));
        my $empty_bool = $backend->{requests}[1]{body}{query}{bool};
        ok(!exists $empty_bool->{filter}, "$method omits filter for empty list");

        invoke($method, $api, request({ query => 'blue' }));
        my $omitted_bool = $backend->{requests}[2]{body}{query}{bool};
        ok(!exists $omitted_bool->{filter}, "$method omits filter when search_type is absent");
    }
};

subtest 'requests are fresh when query, filter, and endpoint profile change' => sub {
    my ($api, $backend) = new_api(result_empty());
    invoke('POST_search', $api, request({ query => 'first query', search_type => ['page'] }));
    my $first = $backend->{requests}[0];
    my $first_snapshot = dclone($first);
    invoke('POST_autocomplete', $api, request({ query => 'second query', search_type => ['product'] }));
    my $second = $backend->{requests}[1];
    is_deeply($first, $first_snapshot, 'later request leaves first captured request intact');
    is($first->{body}{query}{bool}{filter}[0]{terms}{search_type}[0], 'page', 'later filter does not alter first request');
    is($second->{body}{query}{bool}{filter}[0]{terms}{search_type}[0], 'product', 'second request has its own filter');
    my $second_union = dis_max_query($second->{body});
    my ($second_content) = $second_union
        ? grep { exists $_->{script_score}{query}{match}{search_content} } @{ $second_union->{queries} }
        : ();
    ok($second_content, 'second request retains a content role');
    is($second_content->{script_score}{query}{match}{search_content}{query},
        'second query', 'second profile uses its own normalized query text') if $second_content;
    isnt(refaddr($first->{body}), refaddr($second->{body}), 'endpoint requests have distinct body structures');
    isnt(refaddr($first->{body}{query}), refaddr($second->{body}{query}), 'endpoint requests have distinct query structures');
};

subtest 'successful responses preserve endpoint fields and item mapping' => sub {
    my $hit = {
        _score => 12.5,
        _source => {
            title => 'Blue Widget', url => '/blue', search_type => 'page',
            breadcrumb => ['Home'], teaser => 'A widget', thumbnail => '/blue.png',
            weight => 0.0005, index_ts => '2026-10-01T00:00:00Z', search_content => 'blue widget',
        },
    };
    my $backend_result = { hits => { total => { value => 8, relation => 'eq' }, hits => [$hit] }, took => 17 };
    my ($api) = new_api($backend_result);
    my $search = invoke('POST_search', $api, request({ query => 'Blue Widget' }));
    is($search->{query}, 'blue widget', 'search response includes normalized query');
    is($search->{total}, 8, 'search response includes total hit count');
    is($search->{took_ms}, 17, 'search response includes backend duration');
    is($search->{items}[0]{title}, 'Blue Widget', 'search maps item title');
    is($search->{items}[0]{url}, '/blue', 'search maps item URL');
    is($search->{items}[0]{search_type}, 'page', 'search maps item type');
    is($search->{items}[0]{score}, 12.5, 'search maps numeric score');
    is($search->{items}[0]{index_ts}, '2026-10-01T00:00:00Z', 'search maps index timestamp');
    is($search->{items}[0]{search_content}, 'blue widget', 'search maps searchable content');

    my $autocomplete = invoke('POST_autocomplete', $api, request({ query => 'Blue Widget' }));
    is($autocomplete->{query}, 'blue widget', 'autocomplete response includes normalized query');
    is($autocomplete->{total}, 1, 'autocomplete total is returned hit count');
    is($autocomplete->{items}[0]{title}, 'Blue Widget', 'autocomplete maps item title');
    is($autocomplete->{items}[0]{score}, 12.5, 'autocomplete maps numeric score');
    ok(!exists $autocomplete->{items}[0]{index_ts}, 'autocomplete omits search-only timestamp');
    ok(!exists $autocomplete->{items}[0]{search_content}, 'autocomplete omits search-only content');
};

subtest 'invalid bodies, arguments, hosts, and backend responses retain status and body' => sub {
    my ($api, $backend) = new_api(result_empty());
    for my $method (qw(POST_search POST_autocomplete)) {
        for my $case (
            [ 'invalid JSON', request({}, invalid_json => 1), 'invalid json body' ],
            [ 'non-object JSON', request([]), 'invalid json body' ],
            [ 'missing query', request({}), 'query is required' ],
            [ 'empty query', request({ query => '  ' }), 'query is required' ],
            [ 'reference query', request({ query => [] }), 'query is required' ],
            [ 'invalid type argument', request({ query => 'blue', search_type => 'page' }), 'search_type must be an array with valid values' ],
            [ 'invalid type member', request({ query => 'blue', search_type => ['unknown'] }), 'search_type must be an array with valid values' ],
            [ 'unknown host', request({ query => 'blue' }, host => 'unknown.invalid'), 'search backend query failed' ],
        ) {
            my ($label, $req, $body) = @$case;
            my $error;
            if ($label eq 'unknown host') {
                local $SIG{__WARN__} = sub { };
                $error = error_result($method, $api, $req);
            }
            else {
                $error = error_result($method, $api, $req);
            }
            is($error->[0], $label eq 'unknown host' ? 500 : 400, "$method $label status");
            is($error->[2], $body, "$method $label error body");
        }
    }

    for my $bad_limit (0, 101, '1.5', 'abc') {
        my $error = error_result('POST_autocomplete', $api, request({ query => 'blue', limit => $bad_limit }));
        is($error->[0], 400, "autocomplete limit '$bad_limit' status");
        is($error->[2], 'limit must be integer in range 1..100', "autocomplete limit '$bad_limit' body");
    }
    for my $bad_args (
        [ { query => 'blue', page => 0 }, 'page must be integer >= 1' ],
        [ { query => 'blue', page => '1.5' }, 'page must be integer >= 1' ],
        [ { query => 'blue', size => 0 }, 'size must be integer in range 1..200' ],
        [ { query => 'blue', size => 201 }, 'size must be integer in range 1..200' ],
        [ { query => 'blue', size => '1.5' }, 'size must be integer in range 1..200' ],
    ) {
        my $error = error_result('POST_search', $api, request($bad_args->[0]));
        is($error->[0], 400, 'invalid search pagination status');
        is($error->[2], $bad_args->[1], 'invalid search pagination body');
    }
    is(scalar @{ $backend->{requests} }, 0, 'invalid requests do not reach backend');

    my $failed_backend = Local::SearchAPI::Backend->new(result_empty());
    $failed_backend->{fail} = 1;
    my $failed_api = meon::Web::SearchAPI->new(ose => $failed_backend);
    for my $method (qw(POST_search POST_autocomplete)) {
        my $error;
        {
            local $SIG{__WARN__} = sub { };
            $error = error_result($method, $failed_api, request({ query => 'blue' }));
        }
        is($error->[0], 500, "$method backend exception status");
        is($error->[2], 'search backend query failed', "$method backend exception body");
    }
    my ($bad_result_api) = new_api('not a hash');
    for my $method (qw(POST_search POST_autocomplete)) {
        my $error;
        { local $SIG{__WARN__} = sub { }; $error = error_result($method, $bad_result_api, request({ query => 'blue' })); }
        is($error->[0], 500, "$method invalid backend result status");
        is($error->[2], 'search backend query failed', "$method invalid backend result body");
    }
};

done_testing();
