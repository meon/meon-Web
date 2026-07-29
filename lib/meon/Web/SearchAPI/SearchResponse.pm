package meon::Web::SearchAPI::SearchResponse;

use 5.010;
use Moose;

our $VERSION = '0.01';

use Carp qw(croak);
use URI::Escape qw(uri_escape_utf8);

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

    my $items = $self->data->{items};
    return $items unless ref($items) eq 'ARRAY';

    my @safe_items;
    for my $item ( @{$items} ) {
        if ( ref($item) ne 'HASH' ) {
            push @safe_items, $item;
            next;
        }

        push @safe_items,
            {
            map {
                exists $item->{$_}
                    ? ( $_ => $item->{$_} )
                    : ()
            } qw(
                url
                title
                breadcrumb
                score
                teaser
                search_type
                thumbnail
                weight
            )
            };
    }

    return \@safe_items;
}

sub size {
    my ($self) = @_;
    return $self->data->{size} // 10;
}

sub page {
    my ($self) = @_;
    return $self->data->{page} // 1;
}

sub _total_pages {
    my ($self) = @_;

    my $size = $self->size || 0;
    return 0 if $size <= 0;

    my $total = $self->total || 0;
    return int( ( $total + $size - 1 ) / $size );
}

sub _safe_page {
    my ($self) = @_;

    my $total_pages = $self->_total_pages;
    my $page        = $self->page || 1;
    $page = 1 if $page < 1;

    if ( $total_pages > 0 && $page > $total_pages ) {
        $page = $total_pages;
    }

    return $page;
}

sub _href_for_page {
    my ( $self, $page ) = @_;

    my $query = $self->query // '';
    my $q     = uri_escape_utf8($query);
    return '?q=' . $q . '&page=' . $page;
}

sub _pager_pages {
    my ($self) = @_;

    my $total_pages = $self->_total_pages;
    return () if $total_pages <= 0;

    if ( $total_pages <= 10 ) {
        return ( 1 .. $total_pages );
    }

    my $current = $self->_safe_page;
    my @wanted  = (1);

    for my $p ( ( $current - 2 ) .. ( $current + 2 ) ) {
        next if $p <= 1 || $p >= $total_pages;
        push @wanted, $p;
    }
    push @wanted, $total_pages;

    return @wanted;
}

sub _build_pager_items {
    my ($self) = @_;

    my @pages = $self->_pager_pages;
    return [] unless @pages;

    my $current = $self->_safe_page;
    my @pager;
    my $prev;
    for my $page (@pages) {
        if ( defined $prev && ( $page - $prev ) > 1 ) {
            push @pager, { text => '...' };
        }

        my %page_item = (
            text => "$page",
            href => $self->_href_for_page($page),
        );
        if ( $page == $current ) {
            $page_item{class} = 'current-page';
        }

        push @pager,
            \%page_item;
        $prev = $page;
    }

    return \@pager;
}

sub _build_prev_next {
    my ($self) = @_;

    my $total_pages = $self->_total_pages;
    my $current     = $self->_safe_page;

    my %page_prev = ( text => 'Prev' );
    if ( $total_pages > 0 && $current > 1 ) {
        $page_prev{href} = $self->_href_for_page( $current - 1 );
    }

    my %page_next = ( text => 'Next' );
    if ( $total_pages > 0 && $current < $total_pages ) {
        $page_next{href} = $self->_href_for_page( $current + 1 );
    }

    return ( \%page_prev, \%page_next );
}

sub as_data {
    my ($self) = @_;

    my $pager = $self->_build_pager_items;
    my ( $page_prev, $page_next ) = $self->_build_prev_next;

    my %as_data = (
        query     => $self->query,
        total     => $self->total,
        items     => $self->items,
        size      => $self->size,
        page      => $self->page,
        pager     => $pager,
        page_prev => $page_prev,
        page_next => $page_next,
    );

    return \%as_data;
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

=head1 METHODS

=head2 as_data

Returns a hash reference used by templates and XML serialization.

Returned keys:

=over 4

=item * C<query>

Original search phrase.

=item * C<total>

Total count of matched records.

=item * C<items>

Current page result list reduced to presentation fields only:
C<url>, C<title>, C<breadcrumb>, C<score>, C<teaser>, C<search_type>,
C<thumbnail>, and C<weight>.

=item * C<size>

Requested page size.

=item * C<page>

Current page number from input payload.

=item * C<pager>

Array reference for pager navigation. Each item is a hash with mandatory
C<text> and optional C<href> and C<class>. Gap separators are represented as:

    { text => '...' }

Normal page items are represented as:

    { text => '6', href => '?q=bike&page=6' }

The current page item also includes:

    { text => '6', href => '?q=bike&page=6', class => 'current-page' }

=item * C<page_prev>

Hash reference for previous-page link with mandatory C<text> and optional
C<href>. When current page is the first page, only C<text> is returned.

=item * C<page_next>

Hash reference for next-page link with mandatory C<text> and optional
C<href>. When current page is the last page, only C<text> is returned.

=back

=cut
