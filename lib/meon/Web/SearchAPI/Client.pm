package meon::Web::SearchAPI::Client;

use 5.010;
use Moose;

our $VERSION = '0.01';

use Carp qw(croak);
use JSON::XS;
use LWP::UserAgent;
use meon::Web::SearchAPI::SearchResponse;
use Run::Env;

use namespace::autoclean;

has 'base_url' => (
    is       => 'ro',
    isa      => 'Str',
    required => 1,
);

has 'api_prefix' => (
    is      => 'ro',
    isa     => 'Str',
    default => '/mws_1',
);

has 'user_agent' => (
    is      => 'ro',
    isa     => 'Object',
    lazy    => 1,
    builder => '_build_user_agent',
);

has 'json' => (
    is      => 'ro',
    isa     => 'Object',
    lazy    => 1,
    builder => '_build_json',
);

sub _build_user_agent {
    my ($self) = @_;

    my $ua = LWP::UserAgent->new( timeout => 30 );
    $ua->default_header( 'Accept' => 'application/json' );
    $ua->default_header(
        'Content-Type' => 'application/json; charset=utf-8' );

    return $ua;
}

sub _build_json {
    return JSON::XS->new->utf8(1);
}

sub _join_url {
    my ( $self, @parts ) = @_;

    my $url = shift(@parts) // '';
    $url =~ s{/+$}{};

    for my $part (@parts) {
        next unless defined $part;
        $part =~ s{^/+}{};
        $part =~ s{/+$}{};
        next if $part eq '';
        $url .= '/' . $part;
    }

    return $url;
}

sub search {
    my ( $self, $search_args ) = @_;

    croak 'search_args must be a hashref'
        unless ref($search_args) eq 'HASH';

    my $url =
        $self->_join_url( $self->base_url, $self->api_prefix, 'search' );

    my $res = $self->user_agent->post( $url,
        Content => $self->json->encode($search_args), );

    unless ( $res->is_success ) {
        croak 'search request failed: HTTP '
            . $res->status_line
            . (
            Run::Env->dev ? ' - ' . $url . ' ' . $res->decoded_content : '' );
    }

    my $res_data = eval { $self->json->decode( $res->decoded_content ) };
    if ( $@ || ref($res_data) ne 'HASH' ) {
        croak 'search response is not valid JSON object';
    }

    return meon::Web::SearchAPI::SearchResponse->new_from_data($res_data);
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=head1 NAME

meon::Web::SearchAPI::Client - HTTP client for meon-web search APIs

=head1 SYNOPSIS

    my $client = meon::Web::SearchAPI::Client->new(
        base_url => 'http://localhost:8090',
    );

    my $res = $client->search({
        query => 'product',
        page  => 1,
        size  => 20,
    });

=head1 DESCRIPTION

Simple HTTP client that posts JSON to the search API endpoint
C</mws_1/search> and returns a
C<meon::Web::SearchAPI::SearchResponse> object.

=cut
