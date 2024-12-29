package meon::Web::SearchItem;

use Moose;
use 5.010;

has 'type'       => (is => 'ro', isa => 'Str', required => 1,);    # 'page|product|category'
has 'ident'      => (is => 'ro', isa => 'Maybe[Str]',);
has 'title'      => (is => 'ro', isa => 'Str',        required => 1,);
has 'breadcrumb' => (is => 'ro', isa => 'Maybe[Str]', required => 0,);
has 'teaser'     => (is => 'ro', isa => 'Maybe[Str]', required => 0,);
has 'content'    => (is => 'ro', isa => 'Maybe[Str]', required => 0,);
has 'uri'        => (is => 'ro', isa => 'Str',        required => 1,);
has 'thumbnail'  => (is => 'ro', isa => 'Maybe[Str]', required => 0,);

__PACKAGE__->meta->make_immutable;

1;
