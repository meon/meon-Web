package meon::Web::SearchAPI::SearchResponse;

use 5.010;
use Moose;

our $VERSION = '0.01';

use Carp qw(croak);

use namespace::autoclean;

has 'data' => (
    is       => 'ro',
    isa      => 'HashRef',
    required => 1,
);

sub new_from_data {
    my ( $class, $res_data ) = @_;

    croak 'res_data must be a hashref'
        unless ref($res_data) eq 'HASH';

    return $class->new( data => $res_data );
}

sub query {
    my ($self) = @_;
    return $self->data->{query};
}

sub total {
    my ($self) = @_;
    return $self->data->{total};
}

sub items {
    my ($self) = @_;
    return $self->data->{items};
}

sub as_data {
    my ($self) = @_;
    return $self->data;
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=head1 NAME

meon::Web::SearchAPI::SearchResponse - response object for search API payloads

=head1 SYNOPSIS

    my $res_obj = meon::Web::SearchAPI::SearchResponse->new_from_data($res_data);
    my $total   = $res_obj->total;
    my $items   = $res_obj->items;

=head1 DESCRIPTION

Wraps decoded JSON response data from search APIs into a Moose object,
allowing typed future evolution while preserving access to raw response data.

=cut
