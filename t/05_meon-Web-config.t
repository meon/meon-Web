#!/usr/bin/perl

use strict;
use warnings;
use utf8;

use Test::Most;

use FindBin qw($Bin);
use lib "$Bin/tlib";

use Path::Class qw(file dir);
use Monkey::Patch::Action qw(patch_package);

use_ok ( 'meon::Web::SPc' ) or exit;

my $patch_prefix = patch_package('meon::Web::SPc', 'prefix', 'replace',
    sub {dir(Sys::Path->find_distribution_root('meon::Web::SPc'), 't', 'tsp')});

use_ok ( 'meon::Web::Config' ) or exit;


subtest 'basic' => sub {
    ok(meon::Web::Config->get, 'get()');
    is(meon::Web::Config->hostname_to_folder('includes'), 'includes_t', 'hostname_to_folder()');
};

subtest 'environment placeholders' => sub {
    can_ok( 'meon::Web::Config', 'expand_inplace' ) or return;
    local $ENV{MEON_TEST_CONFIG_HOST} = 'search.example:9200';
    local $ENV{MEON_TEST_CONFIG_AUTH} = 'test-user:pa:ss@word';
    local $ENV{MEON_TEST_CONFIG_EMPTY} = '';
    local $ENV{MEON_TEST_CONFIG_ZERO} = '0';
    local $ENV{MEON_TEST_CONFIG_LITERAL} = '${env:MEON_TEST_CONFIG_HOST}';
    local $ENV{MEON_TEST_CONFIG_MISSING};
    delete $ENV{MEON_TEST_CONFIG_MISSING};

    for my $case (
        [ undef, undef, 'undefined optional value' ],
        [ '', '', 'empty value' ],
        [ 'localhost:9200', 'localhost:9200', 'plain string' ],
        [ '${other:MEON_TEST_CONFIG_HOST}', '${other:MEON_TEST_CONFIG_HOST}',
            'unrelated placeholder' ],
        [ '${env:MEON_TEST_CONFIG_HOST}', 'search.example:9200', 'host' ],
        [ '${env:MEON_TEST_CONFIG_AUTH}', 'test-user:pa:ss@word',
            'credentials inserted literally' ],
        [ '${env:MEON_TEST_CONFIG_EMPTY}', '', 'empty environment value' ],
        [ '${env:MEON_TEST_CONFIG_ZERO}', '0', 'zero environment value' ],
        [ '${env:MEON_TEST_CONFIG_LITERAL}', '${env:MEON_TEST_CONFIG_HOST}',
            'replacement is not recursively expanded' ],
        [ '${env:MEON_TEST_CONFIG_HOST}/${env:MEON_TEST_CONFIG_HOST}',
            'search.example:9200/search.example:9200', 'multiple placeholders' ],
    ) {
        my ( $input, $expected, $name ) = @$case;
        is( meon::Web::Config->expand_inplace($input), $expected, $name );
        is( $input, $case->[0], "$name leaves input unchanged" );
    }

    throws_ok {
        meon::Web::Config->expand_inplace('${env:MEON_TEST_CONFIG_MISSING}');
    } qr/^Environment variable MEON_TEST_CONFIG_MISSING is not set\n/,
        'missing environment value reports only its key';
};

subtest 'session expiration' => sub {
    my $main = meon::Web::Config->get->{main};
    local $main->{'session-expires'};
    is(meon::Web::Config->session_expires, 14_400,
        'session expiration defaults to four hours');

    for my $case (
        [14_400, 14_400, '14,400 numeric seconds'],
        ['30s', 30, 'seconds suffix'],
        ['5m', 300, 'minutes suffix'],
        ['4h', 14_400, 'hours suffix'],
        ['3d', 259_200, 'days suffix'],
    ) {
        my ($value, $expected, $name) = @$case;
        $main->{'session-expires'} = $value;
        my $seconds = eval { meon::Web::Config->session_expires };
        is($seconds, $expected, "$name is parsed to seconds");
    }

    $main->{'session-expires'} = 'nonsense';
    throws_ok { meon::Web::Config->session_expires }
        qr/Could not parse 'nonsense'/,
        'duration parser exception propagates for malformed input';

    for my $invalid (0, '-1h') {
        $main->{'session-expires'} = $invalid;
        throws_ok { meon::Web::Config->session_expires }
            qr/session-expires must be greater than zero/,
            "non-positive session expiration '$invalid' is rejected";
    }
};

done_testing();
