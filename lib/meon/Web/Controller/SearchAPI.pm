package meon::Web::Controller::SearchAPI;

use Moose;
use namespace::autoclean;
use meon::Web::env;
use LWP::UserAgent;
use HTTP::Request;
use URI;

BEGIN {extends 'Catalyst::Controller'}

sub autocomplete : Path('/_mws_1/autocomplete') Args(0) {
    my ($self, $c) = @_;

    $c->res->header('Cache-Control' => 'no-store');
    my $url = meon::Web::env->hostname_config->{search}{searchapi_url};
    unless (defined($url) && length($url)) {
        $c->res->status(404);
        $c->json_reply({error => 'Autocomplete is not configured'});
    }
    if (meon::Web::env->hostname_config->{main}{restricted_web}
        && !$c->user_exists) {
        $c->res->status(401);
        $c->json_reply({error => 'Authentication required'});
    }
    unless ($c->req->method eq 'POST') {
        $c->res->status(405);
        $c->res->header('Allow' => 'POST');
        $c->json_reply({error => 'POST required'});
    }

    my $uri = URI->new($url);
    unless (($uri->scheme // '') =~ /^https?$/i
        && $uri->can('host')
        && defined($uri->host)
        && length($uri->host)) {
        $c->res->status(502);
        $c->json_reply({error => 'Autocomplete backend is unavailable'});
    }

    my $path = $uri->path;
    $path =~ s{/+$}{};
    $uri->path("$path/autocomplete");

    my $body = $c->req->body;
    if (ref($body)) {
        seek($body, 0, 0) or die "Cannot rewind autocomplete request body: $!";
        local $/;
        $body = <$body>;
    }
    my $req = HTTP::Request->new(POST => $uri);
    $req->content($body // '');
    $req->header('Content-Type' => $c->req->header('Content-Type'))
        if defined $c->req->header('Content-Type');
    $req->header('Accept' => $c->req->header('Accept'))
        if defined $c->req->header('Accept');
    my $host = meon::Web::env->hostname;
    $req->header('Host' => $host, 'HTTP_X_FORWARDED_HOST' => $host);

    my $ua  = LWP::UserAgent->new(timeout => 30, max_redirect => 0);
    my $res = eval {$ua->request($req)};
    if (!$res || ($res->header('Client-Warning') // '') eq 'Internal response') {
        $c->res->status(502);
        $c->json_reply({error => 'Autocomplete backend is unavailable'});
    }
    # The upstream has already encoded its bytes; Catalyst must not encode again.
    $c->clear_encoding;
    $c->res->status($res->code);
    for my $header ('Content-Type', 'Content-Encoding') {
        $c->res->header($header => $res->header($header))
            if defined $res->header($header);
    }
    $c->res->body($res->content);
}

__PACKAGE__->meta->make_immutable;
1;

__END__

=head1 NAME

meon::Web::Controller::SearchAPI - search API proxy with site access control

=head1 SYNOPSIS

Website configuration:

    [search]
    searchapi_url = http://127.0.0.1:5001/_mws_1

Frontend: POST autocomplete JSON to C</_mws_1/autocomplete>.

=head1 DESCRIPTION

Requires a meon::Web session when C<[main] restricted_web> is true. When
the setting is false or absent, anonymous requests are allowed.
C<searchapi_url> specifies the standalone search service base URL;
the controller appends C</autocomplete>, allowing an optional trailing slash.
Preserves request bytes, Accept negotiation, response
status, Content-Type, Content-Encoding, and body bytes. Browser credentials and upstream
cookies are not forwarded; responses cannot be cached.

The standalone service must enable C<USING_FRONTEND_PROXY=1> so it selects the
website's search index. Route restricted-site autocomplete through meon::Web;
prevent direct public access to the standalone service. Deployment details are documented
in L<meon::Web::SearchAPI/Authenticated autocomplete>.

=head1 METHODS

=head2 autocomplete

Catalyst action at C</_mws_1/autocomplete> with no path arguments. Requires a configured
backend URL and, for restricted sites, an authenticated session. Proxies the POST
body to that backend. Rejects other methods and returns JSON errors for unavailable backends.

=cut
