package meon::Web::Controller::rAPI;
use Moose;
use 5.010;
use utf8;
use namespace::autoclean;

use meon::Web::Util;
use LWP::UserAgent;
use MIME::Base64 qw(encode_base64);
use JSON::XS;

BEGIN {extends 'Catalyst::Controller'; }

my $json = JSON::XS->new->utf8;

sub auto : Private {
    my ( $self, $c ) = @_;
}

sub base : Chained('/') PathPart('rapi') {
    my ( $self, $c ) = @_;

    my $base_url = meon::Web::env->hostname_config->{'rapi'}{'url'};
    $base_url .= '/'
        unless $base_url =~ m{/$};
    my $path = $c->request->path;
    $path =~ s{^rapi/?}{};
    my $rapi_url = $base_url.$path;
    my ($rapi_ctrl) = split('/', $path);

    my $cfg = meon::Web::env->hostname_config->{'rapi'};

    my $ua = LWP::UserAgent->new(timeout => 30);

    if (my $bauth_usr = $cfg->{bauth_username}) {
        my $bauth_sec = $cfg->{bauth_secret};
        $ua->default_header(
            'Authorization' => 'Basic ' . encode_base64($bauth_usr . ':' . $bauth_sec));
    }
    $ua->default_header('rapi-session-id' => $c->sessionid);
    $ua->default_header('rapi-email' => $c->session->{usr}->{email})
        if $c->session->{usr}->{email};
    $ua->default_header('Content-Type' => 'application/json; charset=utf-8');

    my %post_params = %{$c->req->params};
    if (my $api_data = $c->session->{api_data}->{$rapi_ctrl}) {
        $post_params{session} = $api_data;
    }
    my $a_res = $ua->post($rapi_url, Content => $json->encode(\%post_params));
    unless ($a_res->is_success) {
        $c->res->status($a_res->code);
        $c->json_reply({
            error => {
                code => $a_res->code,
                msg => $a_res->status_line,
            },
        });
        $c->detach;
    }

    my $a_res_data = eval { $json->decode($a_res->decoded_content) };
    unless (ref($a_res_data)) {
        $c->res->status(500);
        $c->json_reply({
            error => {
                code => 500,
                msg => 'Internal server error - broken response from rAPIs',
            },
        });
        $c->detach;
    }

    if (my $session_actions = delete($a_res_data->{session})) {
        if (my $to_add = $session_actions->{add}) {
            for my $add_key (keys %$to_add) {
                $c->session->{backend_user_data}->{$add_key} = $to_add->{$add_key};
            }
            if (my $email = $to_add->{email}) {
                $c->log->info(sprintf('user with %s authenticated', $email));
                my $user = $c->find_user({username => $email});
                $c->set_authenticated($user);
                $c->change_session_id;
            }
        }
        if (my $to_add = $session_actions->{add_api}) {
            for my $add_key (keys %$to_add) {
                $c->session->{api_data}->{$rapi_ctrl}->{$add_key} = $to_add->{$add_key};
            }
        }
    }
    if (my $redirect = $a_res_data->{redirect}) {
        my $redirect_uri = $c->traverse_uri($redirect);
        $redirect_uri = $redirect_uri->absolute
            if $redirect_uri->can('absolute');
        $redirect_uri = $redirect_uri->as_string
            if $redirect_uri->can('as_string');
        $a_res_data->{redirect} = $redirect_uri;
    }

    $c->json_reply($a_res_data);
}


__PACKAGE__->meta->make_immutable;

1;

__END__

=encoding utf8

=head1 NAME

meon::Web::Controller::rAPI - reverse proxy to http APIs

=head1 SYNOPSIS

Hostname-Config:

    [rapi]
    url = http://localhost:5005/v1/
    bauth_username = user
    bauth_secret = secret

=head1 DESCRIPTION

Call to C<http://hostname/rapi/path-to-call> will result in POST call to configured
back-end API C<http://localhost:5005/v1/path-to-call>.

=cut
