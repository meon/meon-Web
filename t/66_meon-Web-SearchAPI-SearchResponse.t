#!/usr/bin/perl

use strict;
use warnings;
use utf8;

use Test::Most;

use_ok('meon::Web::SearchAPI::SearchResponse') or exit;

subtest 'as_data builds compact pager and prev/next links' => sub {
    my $response_obj = meon::Web::SearchAPI::SearchResponse->new_from_data(
        {   query => 'bike',
            total => 123,
            items => [],
            size  => 10,
            page  => 6,
        }
    );

    my $as_data = $response_obj->as_data;

    cmp_deeply(
        $as_data->{page_prev},
        superhashof(
            { text => 'Prev', href => '?q=bike&page=5' }
        ),
        'page_prev contains previous page link'
    );

    cmp_deeply(
        $as_data->{page_next},
        superhashof(
            { text => 'Next', href => '?q=bike&page=7' }
        ),
        'page_next contains next page link'
    );

    my @pager_text = map { $_->{text} } @{ $as_data->{pager} || [] };
    cmp_deeply(
        \@pager_text,
        [ qw(1 ... 4 5 6 7 8 ... 13) ],
        'pager includes compact page list with ellipsis'
    );

    is(
        $as_data->{pager}[4]{href},
        '?q=bike&page=6',
        'current page item keeps canonical href payload'
    );

    is(
        $as_data->{pager}[4]{class},
        'current-page',
        'current page item is marked with current-page class'
    );
};

subtest 'as_data creates minimal pager and boundary prev/next links' => sub {
    my $response_obj = meon::Web::SearchAPI::SearchResponse->new_from_data(
        {   query => 'road bike',
            total => 8,
            items => [],
            size  => 10,
            page  => 1,
        }
    );

    my $as_data = $response_obj->as_data;

    cmp_deeply(
        $as_data->{pager},
        [ superhashof( { text => '1', href => '?q=road%20bike&page=1' } ) ],
        'single page pager rendered with encoded query link'
    );

    cmp_deeply(
        $as_data->{page_prev},
        superhashof( { text => 'Prev' } ),
        'page_prev has text only when already on first page'
    );
    ok(
        !exists $as_data->{page_prev}{href},
        'page_prev href omitted on first page'
    );

    cmp_deeply(
        $as_data->{page_next},
        superhashof( { text => 'Next' } ),
        'page_next has text only when there is no next page'
    );
    ok(
        !exists $as_data->{page_next}{href},
        'page_next href omitted when there is no next page'
    );
};

subtest 'as_data keeps only display fields in items' => sub {
    my $response_obj = meon::Web::SearchAPI::SearchResponse->new_from_data(
        {   query => 'angel',
            total => 1,
            items => [
                {   url            => '/c/riedellskates/art/111-Set-Wht-Angel',
                    title          => '111 - Angel White Set',
                    breadcrumb     => 'Home > Riedell Skates > Art',
                    score          => '0.9871985',
                    teaser         => 'On every level the Angel skate is designed.',
                    search_content => 'full text should not be serialized',
                    search_type    => 'product',
                    thumbnail      => '/static/img/products/111-thumb.jpg',
                    weight         => '0.000863',
                    index_ts       => '2026-07-29T19:28:02Z',
                },
            ],
            size => 10,
            page => 1,
        }
    );

    my $as_data = $response_obj->as_data;

    cmp_deeply(
        $as_data->{items},
        [
            {
                url        => '/c/riedellskates/art/111-Set-Wht-Angel',
                title      => '111 - Angel White Set',
                breadcrumb => 'Home > Riedell Skates > Art',
                score      => '0.9871985',
                teaser     => 'On every level the Angel skate is designed.',
                search_type => 'product',
                thumbnail  => '/static/img/products/111-thumb.jpg',
                weight     => '0.000863',
            },
        ],
        'items are reduced to pager/search-result presentation fields'
    );
};

done_testing();
