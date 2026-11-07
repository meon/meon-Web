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

subtest 'minify_assets' => sub {
    can_ok('meon::Web::Config', 'minify_assets') or return;

    my $tempdir = File::Temp::tempdir(CLEANUP => 1);
    my $site_dir = dir($tempdir, 'testsite');
    my $js_dir = dir($site_dir, 'js');
    my $css_dir = dir($site_dir, 'css');
    my $static_dir = dir($site_dir, 'www', 'static');
    $js_dir->mkpath;
    $css_dir->mkpath;
    $static_dir->mkpath;

    # Write JS files with ES6+ syntax (arrow function, optional chaining, nullish coalescing, UTF-8)
    my $js1 = file($js_dir, '10_first.js');
    $js1->spew(iomode => '>:utf8', "const greet = (name) => `Hallo \${name}`;\n");
    my $js2 = file($js_dir, '20_second.js');
    $js2->spew(iomode => '>:utf8', "const opt = obj?.val ?? 'öäü';\n");

    # Write CSS files with UTF-8
    my $css1 = file($css_dir, '10_base.css');
    $css1->spew(iomode => '>:utf8', "body { margin: 0; padding: 0; }\n");
    my $css2 = file($css_dir, '20_theme.css');
    $css2->spew(iomode => '>:utf8', ".content::before { content: '§'; color: #224455; }\n");

    my $site_cfg = {
        main => {
            'js-dir'  => 'js',
            'css-dir' => 'css',
        },
    };

    my @warnings;
    local $SIG{__WARN__} = sub { push @warnings, @_ };

    # Test clean minification
    meon::Web::Config->minify_assets($site_dir, $site_cfg);
    is(scalar(@warnings), 0, 'no warnings during valid JS/CSS minification');

    my $merged_js = file($static_dir, 'meon-Web-merged.js');
    ok(-f $merged_js, 'meon-Web-merged.js created');
    my $js_content = $merged_js->slurp(iomode => '<:utf8');
    like($js_content, qr/const greet=/, 'JS was minified by esbuild');
    unlike($js_content, qr/\/\* .*10_first\.js \*\//, 'merge comments stripped in minified output');
    like($js_content, qr/Hallo/, 'JS UTF-8 content preserved');

    my $merged_css = file($static_dir, 'meon-Web-merged.css');
    ok(-f $merged_css, 'meon-Web-merged.css created');
    my $css_content = $merged_css->slurp(iomode => '<:utf8');
    like($css_content, qr/body\{margin:0;padding:0\}/, 'CSS was minified by esbuild');
    like($css_content, qr/§/, 'CSS UTF-8 content preserved');

    # Test skipping rebuild when merged file is already newest
    $merged_js->spew("/* untouched */");
    my $now = time();
    utime($now + 10, $now + 10, $merged_js->stringify);

    meon::Web::Config->minify_assets($site_dir, $site_cfg);
    is($merged_js->slurp, "/* untouched */", 'up-to-date merged bundle is not overwritten');

    # Test syntax error fallback and warning with command exit status
    my $bad_js = file($js_dir, '99_syntax_error.js');
    $bad_js->spew("const bad = (\n");
    unlink $merged_js; # force rebuild

    # Suppress child process stderr during intentional syntax error test
    open my $orig_stderr, '>&', \*STDERR or die "Cannot dup STDERR: $!";
    open STDERR, '>', '/dev/null' or die "Cannot redirect STDERR: $!";

    @warnings = ();
    meon::Web::Config->minify_assets($site_dir, $site_cfg);

    open STDERR, '>&', $orig_stderr or die "Cannot restore STDERR: $!";
    close $orig_stderr;

    ok(-f $merged_js, 'merged js fallback file created on minifier failure');
    my $fallback_content = $merged_js->slurp;
    like($fallback_content, qr/\/\* .*99_syntax_error\.js \*\//, 'fallback contains unminified merged content with comments');
    is(scalar(@warnings), 1, 'emitted warning on minification failure');
    like($warnings[0], qr/failed to minify js \(exit 1\)/, 'warning mentions exit 1 status');
};

done_testing();
