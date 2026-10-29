#!/usr/bin/perl

use strict;
use warnings;
use utf8;

use Test::Most;

use FindBin qw($Bin);
use lib "$Bin/lib";

use File::Temp qw(tempdir);
use Path::Class qw(file dir);

use_ok ( 'meon::Web::Util' ) or exit;

subtest 'category_product_short_link' => sub {
    for my $ident ('Prod-1_1.A~', '0') {
        is(meon::Web::Util->category_product_short_link($ident), "/c/$ident",
            'short link preserves the original identifier');
    }
    for my $ident (undef, '', [], '.', '..', 'a/b', 'a?b', 'a#b', 'a%b', 'a b', 'ä') {
        throws_ok { meon::Web::Util->category_product_short_link($ident) }
            qr/invalid category-product ident/, 'rejects identifiers outside a plain URL segment';
    }
};

subtest 'username_cleanup' => sub {
    my $tmp_dir = tempdir( CLEANUP => 1 );
    dir($tmp_dir, 'username')->mkpath;
    dir($tmp_dir, 'username02')->mkpath;
    dir($tmp_dir, 'a000')->mkpath;

    is(
        meon::Web::Util->username_cleanup('username', $tmp_dir),
        'username03',
        'finding username'
    );

    is(
        meon::Web::Util->username_cleanup('Štefan Bučič', $tmp_dir),
        'StefanBucic',
        'finding username'
    );

    is(
        meon::Web::Util->username_cleanup('a', $tmp_dir),
        'axxx',
        'finding username'
    );
};

subtest 'explode_to_4ths' => sub {
    eq_or_diff(meon::Web::Util->explode_to_4ths('a'),    [],                'too short');
    eq_or_diff(meon::Web::Util->explode_to_4ths('ab'),   [qw(ab)],          'len 2');
    eq_or_diff(meon::Web::Util->explode_to_4ths('abc'),  [qw(ab abc)],      'len 3');
    eq_or_diff(meon::Web::Util->explode_to_4ths('abcd'), [qw(ab abc abcd)], 'len 4');
    eq_or_diff(
        meon::Web::Util->explode_to_4ths('abcdefghi'),
        [qw(ab abc abcd bcde cdef defg efgh fghi)],
        'long word'
    );
};

subtest 'explode_for_autocomplete' => sub {
    for my $separator (',', '(', ')', '[', ']', '{', '}', '<', '>', ';', ':', '!', '?', '"', "\x00", "\x1f", "\x7f") {
        eq_or_diff(
            meon::Web::Util->explode_for_autocomplete("foo${separator}bar"),
            meon::Web::Util->explode_for_autocomplete('foo bar'),
            'punctuation and controls preserve word boundaries'
        );
    }
    eq_or_diff(
        meon::Web::Util->explode_for_autocomplete('Quick brown Fox, where are you fox?'),
        [   qw(qu qui quic uick br bro brow rown fo fox wh whe wher here ar are yo you),
            qw(ickb ckbr kbro ownf wnfo nfox foxw oxwh xwhe erea rear eare arey reyo eyou youf oufo ufox),
        ],
        'sentence'
    );
};

subtest 'norm_tokens' => sub {
    is(meon::Web::Util->norm_tokens('<HLS> foo<bar>baz <>'), 'hls foo bar baz',
        'angle brackets separate words and produce no empty tokens');
    is(
        meon::Web::Util->norm_tokens('Heel Lock Stabilizer System (HLS), rolled top comfort '),
        'heel lock stabilizer system hls rolled top comfort',
        'parenthesized acronym is indexed as a standalone word'
    );
    is(meon::Web::Util->norm_tokens(' (HLS), HLS hls '), 'hls',
        'punctuated and plain queries normalize identically and deduplicate');
    is(meon::Web::Util->norm_tokens("foo,bar[baz]{qux};zip:zap!yes?no\"end\x00next\x1fstop\x7ffinal"),
        'foo bar baz qux zip zap yes no end next stop final',
        'delimiters separate adjacent words');
    is(meon::Web::Util->norm_tokens(' (), [] {} ; : ! ? " ... '), '',
        'punctuation produces no empty tokens');
    is(meon::Web::Util->norm_tokens(" AB-12 v1.2 O'Reilly foo... "),
        "ab-12 v1.2 o'reilly foo", 'internal identifiers survive and trailing periods are removed');
};

done_testing();
