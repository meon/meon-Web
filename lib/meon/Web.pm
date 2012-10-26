package meon::Web;
use Moose;
use namespace::autoclean;

use Path::Class 'file', 'dir';
use meon::Web::SPc;

use Catalyst::Runtime 5.80;
use Catalyst qw(
    ConfigLoader
    Authentication
    Session
    Session::Store::File
    Session::State::Cookie
    Authentication::Store::UserXML
    SmartURI
    Unicode::Encoding
);
extends 'Catalyst';

our $VERSION = '0.01';

__PACKAGE__->config(
    name => 'meon_web',
    'Plugin::ConfigLoader' => { file => dir(meon::Web::SPc->sysconfdir, 'meon', 'web-config.pl') },
    'Plugin::SmartURI' => { disposition => 'relative', },
    'root' => dir(meon::Web::SPc->datadir, 'meon', 'web', 'www'),
    'authentication' => {
        'userxml' => {
            'folder' => dir(meon::Web::SPc->sharedstatedir, 'meon-web', 'global-members'),
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
);

__PACKAGE__->setup();

sub static_include_path {
    my $c = shift;

    my $uri      = $c->req->uri;
    my $hostname = $uri->host;
    my $hostname_folder = meon::Web::Config->hostname_to_folder($hostname);

    $c->detach('/status_not_found', ['no such domain '.$hostname.' configured'])
        unless $hostname_folder;

    return [ dir(meon::Web::SPc->srvdir, 'www', 'meon-web', $hostname_folder, 'www') ];
}

sub xpc {
    my $xpc = XML::LibXML::XPathContext->new;
    $xpc->registerNs('x', 'http://www.w3.org/1999/xhtml');
    $xpc->registerNs('w', 'http://web.meon.eu/');
    return $xpc;
}

1;

__END__

=head1 NAME

meon::Web - XML+XSLT file based CMS

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

=head1 EXAMPLES

See F<srv/www/meon-web/localhost/> inside this distribution for simple example.

=head1 SEE ALSO

L<Template::Tools::ttree>

=head1 AUTHOR

Jozef Kutej, C<< <jkutej at cpan.org> >>

=head1 LICENSE AND COPYRIGHT

Copyright 2012 jkutej@cpan.org

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.


=cut
