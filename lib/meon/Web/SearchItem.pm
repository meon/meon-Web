package meon::Web::SearchItem;

use Moose;
use 5.010;
use namespace::autoclean;
use meon::Web::Util;

has 'search_type' => ( is => 'ro', isa => 'Str', required => 1, )
    ;    # 'page|product|category'
has 'ident'          => ( is => 'ro', isa => 'Maybe[Str]', );
has 'title'          => ( is => 'rw', isa => 'Str',        required => 1, );
has 'breadcrumb'     => ( is => 'rw', isa => 'Maybe[Str]', required => 0, );
has 'teaser'         => ( is => 'rw', isa => 'Maybe[Str]', required => 0, );
has 'search_content' => ( is => 'rw', isa => 'Maybe[Str]', required => 0, );
has 'url'            => ( is => 'rw', isa => 'Str',        required => 1, );
has 'index_ts'       => ( is => 'rw', isa => 'Str',        required => 1, );
has 'weight'         => ( is => 'rw', isa => 'Num',        default  => 1, );
has 'title_ngram' => (
    is      => 'rw',
    isa     => 'Str',
    lazy    => 1,
    builder => '_build_title_ngram',
);
has 'thumbnail' => ( is => 'rw', isa => 'Maybe[Str]', required => 0, );

# Internal helper field for breadcrumb construction in Search.pm.
has 'sub_cat_prod' => (
    is        => 'rw',
    isa       => 'Maybe[ArrayRef[Str]]',
    required  => 0,
    predicate => 'is_sub_cat_prod',
);

sub _build_title_ngram {
    my ($self) = @_;

    return join(' ', @{ meon::Web::Util->explode_for_autocomplete( $self->title ) });
}

sub as_opensearch_record {
    my ($self) = @_;

    my $clean_search_content = $self->search_content // '';
    $clean_search_content =~ s/\s+/ /g;
    $clean_search_content =~ s/^\s+|\s+$//g;

    return {
        search_type    => $self->search_type,
        title          => $self->title,
        breadcrumb     => $self->breadcrumb,
        teaser         => $self->teaser,
        search_content => $clean_search_content,
        url            => $self->url,
        index_ts       => $self->index_ts,
        weight         => $self->weight,
        thumbnail      => $self->thumbnail,
        title_ngram    => $self->title_ngram,
    };
}

__PACKAGE__->meta->make_immutable;

1;
