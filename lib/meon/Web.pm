package meon::Web;
use Moose;
use namespace::autoclean;

use Path::Class 'file', 'dir';
use meon::Web::SPc;
use meon::Web::Util;
use meon::Web::Config;
use Cache::FileCache;
use Plack::Middleware::Session::Simple 0.05;
use Run::Env;

use Catalyst::Authentication::Store::UserXML 0.03;

use Catalyst::Runtime 5.80;
use Catalyst qw(
    ConfigLoader
    Authentication
    SmartURI
);
extends 'Catalyst';
use Catalyst::View::XSLT 0.10;

our $VERSION = '0.05';

__PACKAGE__->config(
    name => 'meon_web',
    using_frontend_proxy => 1,
    'Plugin::ConfigLoader' => { file => dir(meon::Web::SPc->sysconfdir, 'meon', 'web-config.pl') },
    'Plugin::SmartURI' => { disposition => 'relative', },
    'root' => dir(meon::Web::SPc->datadir, 'meon', 'web', 'www'),
    'authentication' => {
        'userxml' => {
            'folder'             => dir(meon::Web::SPc->sharedstatedir, 'meon-web', 'global-members'),
            'user_folder_file'   => 'index.xml',
            'find_user_fallback' => 'find_user_fallback',
        }
    },
    'Plugin::Authentication' => {
        default_realm => 'members',
        members => {
            credential => {
                class         => 'Password',
                password_type => 'self_check',
            },
            store => {
                class         => 'UserXML',
            }
        }
    },
    default_view => 'XSLT',
    'View::XSLT' => {
        INCLUDE_PATH => [
            dir(meon::Web::SPc->datadir, 'meon-web', 'template', 'xsl')
        ],
        TEMPLATE_EXTENSION => '.xsl',
    },
    'View::JSON' => {
        allow_callback  => 1,
        callback_param  => 'cb',
        expose_stash    => 'json',
    },
);

__PACKAGE__->setup();

sub apply_session_middleware {
    my ($class, $app, %args) = @_;
    my $expires = $args{expires} // meon::Web::Config->session_expires;
    my $secure = exists $args{secure} ? $args{secure} : !Run::Env->dev;
    my $store = $args{store};
    $store //= $class->session_store(%args, expires => $expires);

    return Plack::Middleware::Session::Simple->wrap(
        $app,
        store       => $store,
        cookie_name => 'meon_web_session',
        keep_empty  => 0,
        path        => '/',
        expires     => "+${expires}s",
        secure      => $secure,
        httponly    => 1,
    );
}

sub session_store {
    my ($class, %args) = @_;
    my $expires = $args{expires} // meon::Web::Config->session_expires;
    my $cache_root = $args{cache_root} // '/tmp/meon-web-session';
    return Cache::FileCache->new({
        namespace          => 'meon_web_session',
        cache_root         => $cache_root,
        cache_depth        => 3,
        default_expires_in => $expires,
    });
}

sub session {
    my $c = shift;
    return $c->req->env->{'psgix.session'};
}

sub session_options {
    my $c = shift;
    return $c->req->env->{'psgix.session.options'};
}

sub session_is_valid {
    my $c = shift;
    return defined $c->session && defined $c->session_options->{id};
}

sub sessionid {
    my $c = shift;
    return $c->session_options->{id};
}

sub change_session_id {
    my $c = shift;
    $c->session_options->{change_id} = 1;
    return;
}

sub delete_session {
    my $c = shift;
    %{$c->session} = ();
    $c->session_options->{expire} = 1;
    return;
}

sub static_include_path {
    my $c = shift;

    my $uri      = $c->req->uri;
    my $hostname = $uri->host;
    my $hostname_dir = meon::Web::Config->hostname_to_folder($hostname);

    $c->detach('/status_not_found', ['no such domain '.$hostname.' configured'])
        unless $hostname_dir;

    return [ dir(meon::Web::SPc->srvdir, 'www', 'meon-web', $hostname_dir, 'www') ];
}

sub json_reply {
    my ( $c, $json_data ) = @_;

    $c->res->header('X-Ajax-Controller',1);
    $c->stash->{json} = $json_data;
    $c->detach('View::JSON');
}

sub member {
    my $c = shift;

    my $members_folder = $c->default_auth_store->folder;
    return meon::Web::Member->new(
        members_folder => $members_folder,
        username       => $c->user->username,
        xml            => $c->user->xml,
    );
}

sub traverse_uri {
    my ($c,$path) = @_;

    $path = meon::Web::Util->path_fixup($path);

    # redirect absolute urls with hostname
    if ($path =~ m{^https?://}) {
        return URI->new($path);
    }

    # redirect absolute urls
    if ($path =~ m{^/}) {
        my $new_uri = $c->req->base->clone;
        $new_uri->path($path);
        return $new_uri;
    }

    my $new_uri = $c->req->uri->clone;
    my @segments = $new_uri->path_segments;
    pop(@segments) if length($path); # allow keeping current uri with path set to ''
    $new_uri->path_segments(
        @segments,
        URI->new($path)->path_segments
    );
    return $new_uri;
}

sub format_dt {
    my ($c, $datetime) = @_;

    my $dt = $datetime->clone;

    # FIXME $c->user preferred timezone + format
    $dt->set_time_zone('Europe/Vienna');
    return $dt->strftime('%d.%m.%Y %H:%M:%S');
}

sub find_user_fallback {
    my ($c, $authinfo) = @_;

    my $username = $authinfo->{username};
    my $storage = meon::Web::env->hostname_config->{'auth'}{'storage'} // '';
    if ($storage eq 'session') {
        my $user_xml = $c->session->{meon_Web_user_xml};
        unless ($user_xml) {
            $user_xml =
                '<page xmlns:xhtml="http://www.w3.org/1999/xhtml" xmlns="http://web.meon.eu/" xmlns:w="http://web.meon.eu/">'
                .'<meta><user xmlns="http://search.cpan.org/perldoc?Catalyst%3A%3AAuthentication%3A%3AStore%3A%3AUserXML">'
                .'<username>'.$username.'</username>'
                .'</user></meta>'
                .'<w:member-profile/>'
                .'</page>';

            $c->session->{meon_Web_user_xml} = $user_xml;
        }
        my $user = Catalyst::Authentication::Store::UserXML::User->new({
            xml_filename => file('/'),
            xml          => XML::LibXML->load_xml(string => $user_xml),
        });
        return $user;
    }
    return undef;
}

1;

__END__

=head1 NAME

meon::Web - XML+XSLT file based "CMS"

=head1 SYNOPSIS

    script/run_meon-web_devel

    cpan -i meon::Web
    cd /srv/www/meon-web/localhost/
    tree

    # in apache virtual host
    <Perl>
        use Plack::Handler::Apache2;
        Plack::Handler::Apache2->preload("/usr/local/bin/meon-web.psgi");
    </Perl>
    <Location />
        SetHandler perl-script
        PerlResponseHandler Plack::Handler::Apache2
        PerlSetVar psgi_app /usr/local/bin/meon-web.psgi
    </Location>

=head1 WARNING

Highly experimental at the moment, usable only for real adventurers.

=head1 DESCRIPTION

meon-Web is CMS for designers or publishers that wants to use the whole
power of HTML for their sites, but doesn't want to bother with
programming.

Main implementation goal is be able to have sites as files and go as
far as possible with standard XML+XSLT without database usage.

Each web pages is XML files with content part of given page. Then the
rest of the page (menu + header + footer) are added via XSLT. Any advanced
dynamically generated content on the page can be easily implemented as
special tag, which will be rendered via XSLT.

=head1 FEATURES

=over 4

=item *

multiple domains/websites at once support - stored simple in different folders, switched per request based on "Host:" header.

=item *

login + members area - users + credentials are stored in XML files. Login restriction simply by adding XML tag to meta headers.

=item *

form2email - send form to email address

=back

=head1 SESSION STORAGE

Sessions use C<Plack::Middleware::Session::Simple> with C<Cache::FileCache> at
F</tmp/meon-web-session>. Reading the session is side-effect free. A session ID,
cookie, and cache entry are created only after application code changes the
session.

A successful form POST may create a functional session to carry its
POST/Redirect/GET destination into the following request. When that destination
is the session's only value, consuming it also removes the session cookie and
cache entry.

Set the shared cookie and cache-entry lifetime in the global
F<etc/meon/web-config.ini> file:

    [main]
    session-expires = 4 hours

The value accepts C<Time::Duration::Parse::More> expressions and must resolve
to a positive duration. It defaults to four hours when omitted. Cookies use the
existing C<meon_web_session> name, site-specific domain, and root path, with
HttpOnly and SameSite=Lax attributes. The Secure attribute is enabled outside
the development environment; production requests must therefore use HTTPS.

The C<meon-web-expire-sessions> command purges expired cache entries and is
scheduled hourly by F<etc/cron.d/meon-web>.

=head1 RESTRICTED WEBSITES

To require login by default for a website's XML pages, add this to its
F<config.ini>:

    [main]
    restricted_web = 1

The setting applies per website. Development may load F<config_dev.ini>
instead. It uses Perl truthiness: a missing or empty value, or C<0>, disables
the restriction. All other strings, including C<false> and C<off>, enable it.

Direct C<.xml> requests are interpreted as pages by default. To serve specific
XML paths as static files, list them as values in the website configuration:

    [raw_xml]
    file.1 = /sitemap.xml
    rss = /rss.xml
    atom_feed = /atom.xml

The keys are arbitrary labels and are ignored. Values are exact request paths.
The allowlist applies independently to each website.

To allow anonymous access, add C<public-access> directly to the page metadata:

    <w:page xmlns:w="http://web.meon.eu/">
      <w:meta><w:public-access/></w:meta>
      <w:content>Public content</w:content>
    </w:page>

The default meon Web namespace is also supported. C<members-only> always
requires login and takes precedence over C<public-access>. Both are presence
markers, so their content is ignored. Authenticated users retain existing role
checks. Access is checked before redirects, includes, and forms run.

Login, logout, and root F<403.xml>, F<404.xml>, and F<500.xml> pages remain
public regardless of their metadata. Custom error pages retain their status.

Add C<public-access> to password-reset, activation, and external-registration
pages that must work before login. A protected external-registration page
returns HTTP 403.

Anonymous timelines and directory listings omit protected pages and their
names, content, and archive links. A directory's visibility follows its
F<index.xml>. On restricted websites, listings also omit unreadable XML,
non-XML files, and directories without an index. Authenticated listings are
unchanged.

=head2 Restriction boundary

The restriction covers XML pages resolved by the page controller and public
listings. It does not cover static assets, direct non-XML downloads, explicitly
allowlisted raw XML, or separate API and search responses. XML feeds must be
listed under C<[raw_xml]> to be served without interpretation. Canonical URL
redirects occur first. Hiding a file from a listing does not restrict direct
access to its URL. Raw XML is static content and bypasses page metadata and
role policy, so only intentionally public resources should be allowlisted.

Public pages may expose included fragments marked C<members-only>. Search pages
may expose titles and teasers returned by their backend. Include and search
filtering require separate controls.

=head2 Symlinked public endpoints

Symlinked root login or error pages are public only when their resolved target
is an exception file or their metadata permits anonymous access.

=head1 EXAMPLES

See F<srv/www/meon-web/localhost/> inside this distribution for simple example.

=head1 SEE ALSO

L<Template::Tools::ttree>

=head1 AUTHOR

Jozef Kutej, C<< <jkutej at cpan.org> >>

=head1 CONTRIBUTORS
 
The following people have contributed to the meon::Web by committing their
code, sending patches, reporting bugs, asking questions, suggesting useful
advice, nitpicking, chatting on IRC or commenting on my blog (in no particular
order):

    Andrea Pavlovic
    AI

=head1 LICENSE AND COPYRIGHT

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.

=head1 srv/www/meon-web/bootstrap/

Are examples from L<https://github.com/twbs/bootstrap>, check there for
license and copyright.

=cut
