#!/usr/bin/perl

use strict;
use warnings;
use Test::More;
use Test::Dirs qw(temp_copy_ok);
use FindBin qw($Bin);
use File::Copy qw(copy);
use File::Copy::Recursive qw(dircopy);
use Path::Class qw(dir file);
use Monkey::Patch::Action qw(patch_package);
use HTTP::Request::Common qw(GET POST);
use HTTP::Cookies;
use URI;
use XML::LibXML;
use Plack::Test;
use meon::Web::SPc;

# Copy fixtures so sessions, profiles and page variants never modify the source.
my $temp_fixture_dir = temp_copy_ok(dir($Bin, 'tsp'), 'copy fixtures to temporary storage');
my $prefix = dir($temp_fixture_dir->dirname);
my $sites = $prefix->subdir('srv', 'www', 'meon-web');
my $restricted = $sites->subdir('access_restricted_t');
for my $site (qw(access_disabled_t access_missing_t)) {
    for my $part (qw(content template)) {
        dircopy($restricted->subdir($part), $sites->subdir($site, $part))
            or die "copy $part fixtures for $site: $!";
    }
}
$prefix->subdir('var', 'lib', 'meon-web', 'global-members')->mkpath;
for my $site (qw(access_restricted_t access_disabled_t access_missing_t)) {
    $sites->subdir($site, 'content', 'members', 'profile')->mkpath;
    $sites->subdir($site, 'www', 'static')->mkpath;
}
my $patch_prefix = patch_package('meon::Web::SPc', 'prefix', 'replace',
    sub { $prefix });

require meon::Web;
# UserXML creates a legacy default realm without a credential verifier.
# Supply the application's real Password verifier for this isolated fixture;
# without this test-only connection, password submissions return HTTP 500.
my $default_realm = meon::Web->get_auth_realm('default');
$default_realm->credential(meon::Web->get_auth_realm('members')->credential)
    unless $default_realm->credential;
my $external_user;
# Model only the completed external identity-provider step, without networking.
my $auto_action = meon::Web->controller('Root')->action_for('auto');
my $original_auto = $auto_action->code;
$auto_action->code(sub {
        my ($self, $c) = @_;
        my $result = $original_auto->($self, $c);
        $c->session->{external_auth_username} = $external_user
            if defined $external_user;
        return $result;
    });
# Preserve real login forwarding; stop a loop with an observable HTTP failure.
# Wrap registered actions so Catalyst retains routing attributes.
my $login_action = meon::Web->controller('Root')->action_for('login');
my $original_login = $login_action->code;
$login_action->code(sub {
        my ($self, $c) = @_;
        if (++$c->stash->{access_test_login_calls} > 2) {
            $c->res->status(508);
            $c->res->body('ACCESS_TEST_LOGIN_RECURSION');
            $c->detach;
        }
        return $original_login->($self, $c);
    });
meon::Web->config->{'Plugin::Session'}{storage} =
    $prefix->subdir('sessions')->stringify;
my $app = meon::Web->psgi_app;

my @markers = (
    ['unmarked', '', 0],
    ['public', '<public-access/>', 0],
    ['public-zero', '<public-access>0</public-access>', 0],
    ['members', '<members-only/>', 1],
    ['members-zero', '<members-only>0</members-only>', 1],
    ['both', '<public-access/><members-only/>', 1],
    ['both-reversed', '<members-only/><public-access/>', 1],
    ['foreign-public', '<public-access xmlns="urn:other"/>', 0],
    ['nested-public', '<extra><public-access/></extra>', 0],
);
for my $site (qw(access_restricted_t access_disabled_t access_missing_t)) {
    my $root = $sites->subdir($site);
    for my $ns (qw(default prefixed)) {
        for my $marker (@markers) {
            my ($name, $meta) = @$marker;
            write_page($root, "$ns-$name", $meta, 'MATRIX_PAGE_CONTENT', $ns);
        }
    }
    write_page($root, 'role', '<public-access/><access><role>admin</role></access>',
        'ADMIN_PAGE_CONTENT');
    write_page($root, 'members', '<members-only/>', 'MEMBERS_PAGE_CONTENT');
    write_page($root, 'redirect', '<redirect>/destination</redirect>', 'REDIRECT_CONTENT');
    write_page($root, 'include', '', '<include path="snippet.xml"/>');
    write_file($root->file('include', 'snippet.xml'),
        '<snippet xmlns="http://web.meon.eu/">INCLUDED_CONTENT</snippet>');
    write_page($root, 'form', '<form><process>Search</process></form>', 'FORM_PAGE_CONTENT');
    write_file($root->file('www', 'static', 'login.css'), '/* LOGIN_ASSET */');
    write_file($root->file('content', 'robots.txt'), "User-agent: *\nDisallow:\n");
    write_page($root, 'sitemap', '<members-only/>', 'RAW_SITEMAP_CONTENT');
    write_page($root, 'members/profile/tester/index',
        '<user xmlns="http://search.cpan.org/perldoc?Catalyst%3A%3AAuthentication%3A%3AStore%3A%3AUserXML">'
        . '<status>active</status><username>tester</username>'
        . '<password>{CLEARTEXT}access-test-password</password></user>',
        '<member-profile><full-name>Test Member</full-name></member-profile>');
}

test_psgi app => $app, client => sub {
    my ($client) = @_;
    subtest 'isolated website configuration' => sub {
        for my $case (['restricted.test', '1'], ['disabled.test', '0'],
            ['missing.test', undef]) {
            my ($host, $expected) = @$case;
            meon::Web::env->clear;
            meon::Web::env->hostname($host);
            is(meon::Web::env->hostname_config->{main}{restricted_web}, $expected,
                "$host reads its fixture configuration");
        }
    };
    subtest 'anonymous unmarked page on restricted website' => sub {
        my $res = $client->(GET 'http://restricted.test/');
        is($res->code, 200, 'login page response succeeds');
        like($res->content, qr/LOGIN_PAGE_CONTENT/, 'existing login flow runs');
        unlike($res->content, qr/UNMARKED_PAGE_CONTENT/, 'protected body withheld');
    };

    subtest 'INI values use Perl truthiness' => sub {
        for my $case (['', 0], ['0', 0], ['1', 1], ['false', 1],
            ['off', 1], ['00', 1], ['2', 1]) {
            my ($value, $enabled) = @$case;
            my $config_file = $prefix->file('truthiness.ini');
            write_file($config_file, "[main]\nrestricted_web = $value\n");
            local meon::Web::Config->get->{access_restricted_t} =
                Config::INI::Reader->read_file($config_file);
            my $res = $client->(GET 'http://restricted.test/');
            is($res->code, 200, "value '$value': request succeeds");
            my $expected = $enabled ? 'LOGIN_PAGE_CONTENT' : 'UNMARKED_PAGE_CONTENT';
            like($res->content, qr/\Q$expected\E/, "value '$value': Perl truthiness");
        }
    };

    for my $host (qw(restricted.test disabled.test missing.test)) {
        for my $authenticated (0, 1) {
            my $jar = HTTP::Cookies->new;
            if ($authenticated) {
                my $res = request($client, $jar, POST "http://$host/login",
                    [username => 'tester', password => 'access-test-password']);
                is($res->code, 302, "$host: authenticate real fixture user");
            }
            for my $ns (qw(default prefixed)) {
                subtest "$host authenticated=$authenticated namespace=$ns" => sub {
                    for my $marker (@markers) {
                        my ($name, undef, $members) = @$marker;
                        my $protected = !$authenticated && ($members ||
                            ($host eq 'restricted.test' &&
                                $name !~ /\A(?:public|public-zero|both|both-reversed)\z/));
                        my $res = request($client, $jar,
                            GET "http://$host/$ns-$name");
                        is($res->code, 200, "$name: request completes without recursion");
                        if ($protected) {
                            like($res->content, qr/LOGIN_PAGE_CONTENT/, "$name: login required");
                            unlike($res->content, qr/MATRIX_PAGE_CONTENT/, "$name: body withheld");
                        }
                        else {
                            like($res->content, qr/MATRIX_PAGE_CONTENT/, "$name: page accessible");
                            unlike($res->content, qr/LOGIN_PAGE_CONTENT/, "$name: no login forwarding");
                        }
                    }
                };
            }
            if ($authenticated) {
                my $res = request($client, $jar, GET "http://$host/role");
                is($res->code, 403, "$host: public marker does not bypass role denial");
                unlike($res->content, qr/ADMIN_PAGE_CONTENT/, 'role-protected body withheld');
                $res = request($client, $jar, GET "http://$host/login");
                is($res->code, 302, "$host: authenticated login redirects");
                is(URI->new_abs($res->header('Location'), "http://$host/login")->as_string,
                    "http://$host/", 'authenticated login redirects home');
            }
        }
    }

    subtest 'restriction precedes page redirects, includes and forms' => sub {
        my ($include_calls, $form_calls) = (0, 0);
        my $include_probe = patch_package('meon::Web::env', 'apply_includes', 'wrap',
            sub {
                my ($wrapper, @args) = @_;
                ++$include_calls if meon::Web::env->current_path eq '/include';
                return $wrapper->{orig}->(@args);
            });
        my $form_probe = patch_package('HTML::FormHandler', 'process', 'wrap',
            sub {
                my ($wrapper, $self, @args) = @_;
                ++$form_calls if $self->isa('meon::Web::Form::Search');
                return $wrapper->{orig}->($self, @args);
            });
        for my $path (qw(redirect include form)) {
            my $res = $client->(GET "http://restricted.test/$path");
            is($res->code, 200, "$path: login response succeeds");
            like($res->content, qr/LOGIN_PAGE_CONTENT/, "$path: login flow runs first");
            ok(!$res->header('Location'), "$path: no page redirect");
            unlike($res->content, qr/INCLUDED_CONTENT|form-search|FORM_PAGE_CONTENT/,
                "$path: page processing withheld");
        }
        is($include_calls, 0, 'protected page includes never executed');
        is($form_calls, 0, 'protected page form never processed');
        # Positive controls make missing include/form processing visible.
        like($client->(GET 'http://disabled.test/include')->content,
            qr/INCLUDED_CONTENT/, 'unrestricted include is evaluated');
        like($client->(GET 'http://disabled.test/form')->content,
            qr/form-search/, 'unrestricted page form is rendered');
        ok($include_calls > 0, 'include probe observes real processing');
        ok($form_calls > 0, 'form probe observes real processing');
    };

    subtest 'direct and forwarded login, invalid and successful credentials' => sub {
        for my $path ('login', 'members', '') {
            my $url = "http://restricted.test/$path";
            my $res = $client->(GET $url);
            is($res->code, 200, "$path: GET succeeds");
            like($res->content, qr/form_login/, "$path: login form rendered");
            $res = $client->(POST $url,
                [username => 'tester', password => 'wrong-password']);
            is($res->code, 403, "$path: invalid credentials denied");
            like($res->content, qr/form_login/, "$path: invalid login still renders form");
            my $jar = HTTP::Cookies->new;
            $res = request($client, $jar, POST $url,
                [username => 'tester', password => 'access-test-password']);
            is($res->code, 302, "$path: valid login redirects");
            is($res->header('Location'), $url, "$path: original URL retained");
            $res = request($client, $jar, GET 'http://restricted.test/');
            like($res->content, qr/UNMARKED_PAGE_CONTENT/, "$path: session grants access");
            unlike($res->content, qr/LOGIN_PAGE_CONTENT/, "$path: no login after authentication");
        }
    };

    subtest 'login exception takes precedence over metadata' => sub {
        for my $meta ('<members-only/>', '<members-only/><public-access/>') {
            write_page($restricted, 'login', $meta, 'LOGIN_PAGE_CONTENT');
            for my $path (qw(login members)) {
                my $res = $client->(GET "http://restricted.test/$path");
                is($res->code, 200, "$path with $meta: no recursion");
                like($res->content, qr/form_login/, "$path with $meta: form rendered");
            }
        }
        write_page($restricted, 'login', '', 'LOGIN_PAGE_CONTENT');
    };

    subtest 'logout and subsequent home request' => sub {
        write_page($restricted, 'logout', '<members-only/><public-access/>',
            'LOGOUT_XML_MUST_NOT_RENDER');
        for my $authenticated (0, 1) {
            my $jar = HTTP::Cookies->new;
            if ($authenticated) {
                is(request($client, $jar, POST 'http://restricted.test/login',
                    [username => 'tester', password => 'access-test-password'])->code,
                    302, 'logged in before logout');
            }
            my $res = request($client, $jar, GET 'http://restricted.test/logout');
            is($res->code, 302, "authenticated=$authenticated: logout redirects");
            is(URI->new_abs($res->header('Location'), 'http://restricted.test/logout')->as_string,
                'http://restricted.test/', 'redirects home');
            $res = request($client, $jar, GET 'http://restricted.test/');
            like($res->content, qr/LOGIN_PAGE_CONTENT/, 'home requires login after logout');
            unlike($res->content, qr/UNMARKED_PAGE_CONTENT/, 'home body withheld');
            $res = request($client, $jar, GET 'http://restricted.test/members');
            like($res->content, qr/LOGIN_PAGE_CONTENT/, 'previous session cannot access members page');
        }
    };

    subtest 'site isolation across consecutive anonymous requests' => sub {
        for my $host (qw(restricted.test disabled.test missing.test restricted.test)) {
            my $res = $client->(GET "http://$host/");
            my $expected = $host eq 'restricted.test' ? 'LOGIN_PAGE_CONTENT' : 'UNMARKED_PAGE_CONTENT';
            like($res->content, qr/\Q$expected\E/, "$host uses its own setting");
        }
    };

    subtest 'static login assets and non-XML resources remain accessible' => sub {
        my $res = $client->(GET 'http://restricted.test/static/login.css');
        is($res->code, 200, 'login stylesheet accessible');
        like($res->content, qr/LOGIN_ASSET/, 'stylesheet body served');
        $res = $client->(GET 'http://restricted.test/robots.txt');
        is($res->code, 200, 'non-XML content path accessible');
        like($res->content, qr/User-agent/, 'plain text resource served');
    };

    subtest 'direct XML requests require an explicit raw allowlist entry' => sub {
        my $res = $client->(GET 'http://restricted.test/default-unmarked.xml?t=1');
        is($res->code, 200, 'anonymous protected XML request reaches login');
        like($res->content, qr/LOGIN_PAGE_CONTENT/, 'restricted default policy is applied');
        unlike($res->content, qr/MATRIX_PAGE_CONTENT/, 'protected source is withheld');

        $res = $client->(GET 'http://restricted.test/default-members.xml?t=1');
        like($res->content, qr/LOGIN_PAGE_CONTENT/, 'members-only XML request reaches login');
        unlike($res->content, qr/MATRIX_PAGE_CONTENT/, 'members-only source is withheld');

        $res = $client->(GET 'http://restricted.test/default-public.xml?t=1');
        is($res->code, 200, 'public XML request succeeds');
        like($res->content, qr{<html\b[^>]*><body>}, 'public XML is interpreted');
        like($res->content, qr/MATRIX_PAGE_CONTENT/, 'public page content is rendered');

        my $jar = HTTP::Cookies->new;
        is(request($client, $jar, POST 'http://restricted.test/login',
            [username => 'tester', password => 'access-test-password'])->code,
            302, 'authenticate for direct XML requests');
        for my $path (qw(default-unmarked default-members)) {
            $res = request($client, $jar,
                GET "http://restricted.test/$path.xml?t=1");
            is($res->code, 200, "$path XML request succeeds after authentication");
            like($res->content, qr{<html\b[^>]*><body>}, "$path XML is interpreted");
            like($res->content, qr/MATRIX_PAGE_CONTENT/, "$path page content is rendered");
        }
        $res = request($client, $jar, GET 'http://restricted.test/role.xml?t=1');
        is($res->code, 403, 'direct XML request preserves authenticated role denial');
        unlike($res->content, qr/ADMIN_PAGE_CONTENT/, 'role-protected source is withheld');

        for my $authenticated (0, 1) {
            my $raw_jar = HTTP::Cookies->new;
            if ($authenticated) {
                is(request($client, $raw_jar, POST 'http://restricted.test/login',
                    [username => 'tester', password => 'access-test-password'])->code,
                    302, 'authenticate before raw XML request');
            }
            $res = request($client, $raw_jar,
                GET 'http://restricted.test/sitemap.xml?t=1');
            is($res->code, 200, "configured raw XML succeeds authenticated=$authenticated");
            like($res->content, qr/RAW_SITEMAP_CONTENT/, 'configured raw XML body is served');
            unlike($res->content, qr{<html\b[^>]*><body>}, 'configured raw XML is not interpreted');
        }

        my $isolated_jar = HTTP::Cookies->new;
        is(request($client, $isolated_jar, POST 'http://disabled.test/login',
            [username => 'tester', password => 'access-test-password'])->code,
            302, 'authenticate on host without raw XML configuration');
        $res = request($client, $isolated_jar,
            GET 'http://disabled.test/sitemap.xml?t=1');
        is($res->code, 200, 'same XML path succeeds on a different host');
        like($res->content, qr{<html\b[^>]*><body>}, 'raw XML allowlist is isolated per host');
        like($res->content, qr/RAW_SITEMAP_CONTENT/, 'unrestricted host interprets the page');
    };

    subtest 'listing visibility and include-policy observations' => sub {
        write_page($restricted, 'listing/index', '<public-access/>',
            '<timeline class="folder"/><dir-listing path="./"/>');
        for my $entry (['unmarked', ''], ['empty-members', '<members-only/>'],
            ['text-members', '<members-only>1</members-only>']) {
            my ($name, $meta) = @$entry;
            write_page($restricted, "listing/$name", $meta,
                '<timeline-entry><created>2026-01-01T00:00:00</created>'
                . "<title>ENTRY_$name</title><intro>INTRO_$name</intro>"
                . "<text>BODY_$name</text></timeline-entry>");
        }
        my $res = $client->(GET 'http://restricted.test/listing/');
        is($res->code, 200, 'public listing can render');
        for my $name (qw(unmarked empty-members text-members)) {
            diag("timeline $name: " . ($res->content =~ /ENTRY_\Q$name\E/
                ? 'entry content exposed' : 'entry content withheld'));
            diag("directory $name: " . ($res->content =~ /\Q$name\E\.xml/
                ? 'filename exposed' : 'filename withheld'));
        }
        write_page($restricted, 'public-include', '<public-access/>',
            '<include path="private.xml"/>');
        write_file($restricted->file('include', 'private.xml'),
            '<page xmlns="http://web.meon.eu/"><meta><members-only/></meta>'
            . '<content>PRIVATE_INCLUDE_CONTENT</content></page>');
        $res = $client->(GET 'http://restricted.test/public-include');
        is($res->code, 200, 'public include page can render');
        diag('members-only include: ' . ($res->content =~ /PRIVATE_INCLUDE_CONTENT/
            ? 'content exposed' : 'content withheld'));
        # Listing assertions follow. Include visibility remains diagnostic
        # because changing include policy is deferred.
    };

    subtest 'public listings withhold protected files and content' => sub {
        for my $site (['restricted.test', 'access_restricted_t', 1],
            ['disabled.test', 'access_disabled_t', 0]) {
            my ($host, $folder, $restricted_site) = @$site;
            my $root = $sites->subdir($folder);
            write_page($root, 'visibility/index', '<public-access/>',
                '<timeline class="folder"/><dir-listing path="./"/>');
            my @entries = (['unmarked', '', 0], ['public', '<public-access/>', 0],
                ['empty', '<members-only/>', 1], ['zero', '<members-only>0</members-only>', 1],
                ['both', '<members-only/><public-access/>', 1]);
            for my $entry (@entries) {
                my ($name, $meta) = @$entry;
                write_page($root, "visibility/$name", $meta,
                    '<timeline-entry><created>2026-01-01T00:00:00</created>'
                    . "<title>TITLE_$name</title><intro>TEASER_$name</intro>"
                    . "<text>BODY_$name</text></timeline-entry>");
                write_page($root, "visibility/dir-$name/index", $meta, 'DIRECTORY_BODY');
            }
            write_file($root->file('content', 'visibility', 'download.txt'), 'DOWNLOAD_BODY');
            write_file($root->file('content', 'visibility', 'broken.xml'), '<page');
            for my $authenticated (0, 1) {
                my $jar = HTTP::Cookies->new;
                if ($authenticated) {
                    is(request($client, $jar, POST "http://$host/login",
                        [username => 'tester', password => 'access-test-password'])->code,
                        302, 'authenticate for listing');
                }
                my $res = request($client, $jar, GET "http://$host/visibility/");
                is($res->code, 200, "$host: public listing renders");
                for my $entry (@entries) {
                    my ($name, undef, $members) = @$entry;
                    my $hidden = !$authenticated && ($members ||
                        ($restricted_site && $name ne 'public'));
                    for my $pattern ("TITLE_$name", "TEASER_$name", "BODY_$name",
                        "$name.xml", "dir-$name") {
                        if ($hidden) {
                            unlike($res->content, qr/\Q$pattern\E/,
                                "$host anonymous: withhold $pattern");
                        }
                        else {
                            like($res->content, qr/\Q$pattern\E/,
                                "$host authenticated=$authenticated: show $pattern");
                        }
                    }
                }
                if (!$authenticated) {
                    unlike($res->content, qr/broken\.xml/, 'unreadable XML fails closed');
                }
                if ($restricted_site && !$authenticated) {
                    unlike($res->content, qr/download\.txt/, 'restricted listing hides unmarked downloads');
                }
                else {
                    like($res->content, qr/download\.txt/, 'existing download listing available');
                }
            }
            my $empty = meon::Web::TimelineEntry->new(file =>
                $root->file('content', 'visibility', 'empty.xml'));
            ok($empty->members_only, 'TimelineEntry treats empty members-only as present');
        }
    };

    subtest 'public search page: presentation exposure investigation' => sub {
        require meon::Web::Form::Search;
        # Replace only the external search service response. Run the real form,
        # SearchResponse conversion, controller and XSLT renderer.
        my $search_backend = patch_package('meon::Web::SearchAPI::Client', 'search',
            'replace', sub {
                return meon::Web::SearchAPI::SearchResponse->new_from_data({
                    query => 'private', total => 1, size => 10, page => 1,
                    items => [{url => '/members', title => 'PRIVATE_SEARCH_TITLE',
                        teaser => 'PRIVATE_SEARCH_TEASER'}],
                });
            });
        write_page($restricted, 'search',
            '<public-access/><form><process>Search</process><page-size>10</page-size></form>',
            'SEARCH_PAGE_CONTENT');
        my $res = $client->(GET 'http://restricted.test/search?q=private&page=1');
        is($res->code, 200, 'public search page can render');
        diag('protected search result returned by backend: ' .
            ($res->content =~ /PRIVATE_SEARCH_TEASER/ ? 'teaser exposed' : 'teaser withheld'));
    };

    subtest 'custom error pages' => sub {
        for my $meta ('', '<public-access/>',
            '<members-only/><access><role>admin</role></access>') {
            for my $status (403, 404, 500) {
                write_page($restricted, "$status", $meta, "CUSTOM_ERROR_$status");
            }
            my $jar = HTTP::Cookies->new;
            is(request($client, $jar, POST 'http://restricted.test/login',
                [username => 'tester', password => 'access-test-password'])->code,
                302, 'authenticate for role error');
            for my $case ([403, 'role'], [404, 'missing-page'], [500, 'exception-test']) {
                my ($status, $path) = @$case;
                my $res = $status == 403
                    ? request($client, $jar, GET "http://restricted.test/$path")
                    : $client->(GET "http://restricted.test/$path");
                is($res->code, $status, "error $status with '$meta' preserves status");
                like($res->content, qr/CUSTOM_ERROR_$status/, 'custom error body rendered');
            }
        }
    };

    subtest 'timeline links traverse past protected archives' => sub {
        write_page($restricted, 'archive/2025/index', '<members-only/>', 'PRIVATE_ARCHIVE');
        write_page($restricted, 'archive/2026/index', '<public-access/>', '<timeline class="folder"/>');
        write_page($restricted, 'archive/2027/index', '', 'UNMARKED_ARCHIVE');
        my $res = $client->(GET 'http://restricted.test/archive/2026/');
        is($res->code, 200, 'public archive renders');
        unlike($res->content, qr{/archive/2025/|/archive/2027/},
            'navigation is exhausted when all neighbouring archives are protected');

        write_page($restricted, 'archive/2023/index', '<public-access/>', 'OLDER_PUBLIC_ARCHIVE');
        write_page($restricted, 'archive/2024/index', '<members-only/>', 'OLDER_PRIVATE_ARCHIVE');
        write_page($restricted, 'archive/2028/index', '<members-only/>', 'NEWER_PRIVATE_ARCHIVE');
        write_page($restricted, 'archive/2029/index', '<public-access/>', 'NEWER_PUBLIC_ARCHIVE');
        $res = $client->(GET 'http://restricted.test/archive/2026/');
        like($res->content, qr{/archive/2023/}, 'older navigation skips protected archives');
        like($res->content, qr{/archive/2029/}, 'newer navigation skips protected archives');
        unlike($res->content, qr{/archive/2024/|/archive/2025/|/archive/2027/|/archive/2028/},
            'anonymous navigation withholds every protected archive path');

        my $jar = HTTP::Cookies->new;
        is(request($client, $jar, POST 'http://restricted.test/login',
            [username => 'tester', password => 'access-test-password'])->code,
            302, 'authenticate for archive navigation');
        $res = request($client, $jar, GET 'http://restricted.test/archive/2026/');
        like($res->content, qr{/archive/2025/},
            'authenticated older navigation uses the immediate archive');
        like($res->content, qr{/archive/2027/},
            'authenticated newer navigation uses the immediate archive');
        unlike($res->content, qr{/archive/2023/|/archive/2029/},
            'authenticated navigation does not skip visible neighbours');
    };

    subtest 'recovery and registration pages require public markers' => sub {
        for my $path (qw(password-reset activation registration)) {
            write_page($restricted, $path, '', 'RECOVERY_PAGE_CONTENT');
            my $res = $client->(GET "http://restricted.test/$path");
            like($res->content, qr/LOGIN_PAGE_CONTENT/, "$path is protected without marker");
            if ($path eq 'registration') {
                write_page($restricted, $path, '<public-access/>', 'RECOVERY_PAGE_CONTENT');
            }
            else {
                my $fixture = file($Bin, 'tsp', 'srv', 'www', 'meon-web',
                    'access_restricted_t', 'content', "$path.xml");
                copy($fixture, $restricted->file('content', "$path.xml"))
                    or die "copy recovery fixture: $!";
            }
            $res = $client->(GET "http://restricted.test/$path");
            is($res->code, 200, "$path public request succeeds");
            like($res->content, qr/RECOVERY_PAGE_CONTENT/, "$path public marker permits access");
        }
    };

    subtest 'external authentication registration forwarding' => sub {
        my $config = meon::Web::Config->get->{access_restricted_t};
        local $config->{auth} = {external => 1, registration => '/registration'};
        $external_user = 'external-new-user';
        for my $meta ('', '<public-access/>') {
            write_page($restricted, 'registration', $meta, 'REGISTRATION_PAGE_CONTENT');
            my $res = $client->(GET 'http://restricted.test/members');
            if (length $meta) {
                is($res->code, 200, 'public registration forwarding does not recurse');
                like($res->content, qr/REGISTRATION_PAGE_CONTENT/, 'registration page rendered');
            }
            else {
                is($res->code, 403, 'unmarked registration rejected without recursion');
                unlike($res->content, qr/REGISTRATION_PAGE_CONTENT/, 'registration body withheld');
            }
        }
        undef $external_user;
    };

    subtest 'repeated login requirement fails with a plain 403' => sub {
        my $content = $restricted->subdir('content');
        my $login = $content->file('login.xml');
        write_page($restricted, 'protected-login', '', 'PROTECTED_LOGIN_CONTENT');
        unlink($login) or die "unlink $login: $!";
        symlink('protected-login.xml', $login) or die "symlink $login: $!";

        for my $path (qw(login members)) {
            my $res = $client->(GET "http://restricted.test/$path");
            is($res->code, 403, "$path: repeated login requirement is forbidden");
            like($res->content, qr/login loop/i, "$path: response identifies login loop");
            unlike($res->content, qr/ACCESS_TEST_LOGIN_RECURSION/,
                "$path: loop stops before the test recursion guard");
            unlike($res->content, qr/PROTECTED_LOGIN_CONTENT/,
                "$path: protected login body is withheld");
        }

        for my $status (403, 404, 500) {
            my $error = $content->file("$status.xml");
            write_page($restricted, "protected-$status", '', "PROTECTED_ERROR_$status");
            unlink($error) or die "unlink $error: $!";
            symlink("protected-$status.xml", $error) or die "symlink $error: $!";
        }
        for my $case ([403, '403'], [403, 'missing-page'], [403, 'exception-test']) {
            my ($status, $path) = @$case;
            my $res = $client->(GET "http://restricted.test/$path");
            is($res->code, $status, "$path: error-driven login loop is forbidden");
            like($res->content, qr/login loop/i,
                "$path: error-driven response identifies login loop");
            unlike($res->content, qr/PROTECTED_ERROR_|PROTECTED_LOGIN_CONTENT/,
                "$path: protected error and login bodies are withheld");
        }

        write_page($restricted, 'protected-login', '<public-access/>',
            'PROTECTED_LOGIN_CONTENT');
        for my $path (qw(login members)) {
            my $res = $client->(GET "http://restricted.test/$path");
            is($res->code, 200, "$path: public login target succeeds");
            like($res->content, qr/form_login/, "$path: normal login form is rendered");
        }
    };
};
$auto_action->code($original_auto);
$login_action->code($original_login);
done_testing;

sub request {
    my ($client, $jar, $req) = @_;
    $jar->add_cookie_header($req);
    my $res = $client->($req);
    $res->request($req);
    $jar->extract_cookies($res);
    return $res;
}

sub write_page {
    my ($root, $path, $meta, $content, $ns) = @_;
    my $xml = '<page xmlns="http://web.meon.eu/"><meta>' . $meta
        . '</meta><content>' . $content . '</content></page>';
    my $dom = XML::LibXML->load_xml(string => $xml);
    if (($ns // '') eq 'prefixed') {
        for my $node ($dom->findnodes('//*[namespace-uri()="http://web.meon.eu/"]')) {
            $node->setNamespace('http://web.meon.eu/', 'w', 1);
        }
    }
    write_file($root->file('content', "$path.xml"), $dom->toString);
}

sub write_file {
    my ($path, $content) = @_;
    $path->dir->mkpath;
    my $fh = $path->openw or die "open $path: $!";
    print {$fh} $content or die "write $path: $!";
    close $fh or die "close $path: $!";
}

__END__

=head1 TEST HELPERS

=head2 request($client, $jar, $req)

Sends one request through the in-process PSGI client and updates the supplied
cookie jar. Redirects are not followed automatically.

=head2 write_page($root, $path, $meta, $content, $namespace_style)

Writes a parsed XML page under the temporary site's content directory. The
optional C<prefixed> style prefixes only elements in the meon Web namespace,
preserving foreign namespaces used by negative access tests.

=head2 write_file($path, $content)

Creates parent directories and writes a fixture, failing on I/O errors.

=cut
