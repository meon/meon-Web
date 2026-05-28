package meon::Web::SearchIndex;

use Moose;
use 5.010;
use namespace::autoclean;
use meon::Web::Config;
use Future::AsyncAwait;
use Search::Elasticsearch::Async;
use Path::Class qw(dir file);
use JSON::XS;
use Carp qw(croak);
use Digest::SHA qw(sha256_base64);
use List::Util qw(uniq);

has 'hostname' => (
    is       => 'ro',
    isa      => 'Str',
    required => 1,
);

has 'ose' => (
    is      => 'ro',
    isa     => 'Object',
    lazy    => 1,
    builder => '_build_opensearch',
);

has 'index_alias' => (
    is      => 'ro',
    isa     => 'Str',
    lazy    => 1,
    builder => '_build_index_alias',
);

has 'index_a' => (
    is      => 'ro',
    isa     => 'Str',
    lazy    => 1,
    builder => '_build_index_a',
);

has 'index_b' => (
    is      => 'ro',
    isa     => 'Str',
    lazy    => 1,
    builder => '_build_index_b',
);

has 'active_index' => (
    is      => 'ro',
    isa     => 'Str',
    lazy    => 1,
    builder => '_build_active_index',
    clearer => '_clear_active_index',
);

has 'work_index' => (
    is      => 'ro',
    isa     => 'Str',
    lazy    => 1,
    builder => '_build_work_index',
    clearer => '_clear_work_index',
);

has '_index_settings' => (
    is      => 'ro',
    isa     => 'HashRef',
    lazy    => 1,
    builder => '_build__index_settings',
);

has '_index_mapping' => (
    is      => 'ro',
    isa     => 'HashRef',
    lazy    => 1,
    builder => '_build__index_mapping',
);

has '_indices_info' => (
    is      => 'ro',
    isa     => 'HashRef',
    lazy    => 1,
    builder => '_build__indices_info',
    clearer => '_clear__indices_info',
);

sub _build_active_index {
    my ($self) = @_;
    my $indices_info = $self->_indices_info;
    return (
        ( ( $indices_info->{alias} // '' ) eq 'index_a' )
        ? $self->index_a
        : $self->index_b
    );
}

sub _build_work_index {
    my ($self) = @_;
    my $active_index = $self->active_index;
    return (
        ( $active_index eq $self->index_a )
        ? $self->index_b
        : $self->index_a
    );
}

sub _build__index_settings {
    my ($self) = @_;
    my $settings_file = file( meon::Web::SPc->sysconfdir,
        'meon', 'web-opensearch-settings.json' );
    return JSON::XS->new->decode( $settings_file->slurp . '' );
}

sub _build__index_mapping {
    my ($self) = @_;
    my $mapping_file = file( meon::Web::SPc->sysconfdir,
        'meon', 'web-opensearch-schema.json' );
    return JSON::XS->new->decode( $mapping_file->slurp . '' );
}

sub _build_index_alias {
    my ($self) = @_;
    return 'meon-search_'
        . ( meon::Web::Config->hostname_to_folder( $self->hostname )
            // die 'no such hostname ' . $self->hostname );
}

sub _build_index_a {
    my ($self) = @_;
    return $self->index_alias . '_idx_a';
}

sub _build_index_b {
    my ($self) = @_;
    return $self->index_alias . '_idx_b';
}

sub _build_opensearch {
    my ($self) = @_;
    my @ose_nodes =
        split( ',', meon::Web::Config->get->{opensearch}->{nodes} );
    return Search::Elasticsearch::Async->new(
        nodes           => \@ose_nodes,
        request_timeout => 300,
        cxn_pool        => 'Async::Sniff',
    );
}

sub _build__indices_info {
    my ($self)       = @_;
    my $ose          = $self->ose;
    my $index_a_info = $ose->indices->exists( index => $self->index_a )->sync
        && $ose->indices->get( index => $self->index_a )->sync;
    my $index_b_info = $ose->indices->exists( index => $self->index_b )->sync
        && $ose->indices->get( index => $self->index_b )->sync;

    my $index_alias = (
        (          $index_a_info
                && $index_a_info->{ $self->index_a }->{aliases}
                ->{ $self->index_alias }
        ) ? 'index_a'
        : (        $index_b_info
                && $index_b_info->{ $self->index_b }->{aliases}
                ->{ $self->index_alias } ) ? 'index_b'
        : undef
    );

    return {
        index_a => $index_a_info,
        index_b => $index_b_info,
        alias   => $index_alias,
    };
}

sub init_index {
    my $self = shift;

    my $initial_indices_info = $self->_indices_info;

    my $work_index = $self->work_index;
    $self->_delete_index($work_index);
    $self->ose->indices->create(
        index => $work_index,
        body  => {
            settings => $self->_index_settings,
            mappings => $self->_index_mapping,
        }
    )->sync;

    $self->_clear__indices_info;

    return;
}

sub _delete_index {
    my ( $self, $index ) = @_;
    $self->ose->indices->delete( index => $index )->sync
        if $self->ose->indices->exists( index => $index )->sync;
    return;
}

sub switch_active_index {
    my ($self)       = @_;
    my $active_index = $self->active_index;
    my $work_index   = $self->work_index;

    $self->ose->indices->refresh( index => $work_index )->sync;

    my @actions;
    push(
        @actions,
        {   remove => {
                index => $active_index,
                alias => $self->index_alias
            }
        }
    ) if $self->_indices_info->{alias};
    push( @actions,
        { add => { index => $work_index, alias => $self->index_alias } }, );

    # point alias to work index
    $self->ose->indices->update_aliases( body => { actions => \@actions }, )
        ->sync;

    # delete old active index
    $self->_delete_index($active_index);

    # clear indices info cache
    $self->_clear__indices_info;
    $self->_clear_active_index;
    $self->_clear_work_index;

    return;
}

sub index_docs {
    my ($self, $docs) = @_;
    croak 'docs should be an arrayref' unless ref($docs) eq 'ARRAY';
    my $resp = $self->ose->bulk(
        index => $self->work_index,
        body  => [
            map {
                ( +{ index => { _id => sha256_base64( $_->{url} ) } }, $_, )
            }
            map { $_->as_opensearch_record }
            @$docs
        ],
    )->sync;
    my @errors =
        map {
            join( ':',
                $_->{index}->{error}->{type},
                $_->{index}->{error}->{reason} )
        }
        grep { $_->{index}->{error} } @{ $resp->{items} };
    if (@errors) {
        die(sprintf(
                "Errors (%d) during bulk indexing: %s",
                scalar(@errors), join( '; ', uniq @errors )
            )
        );
    }

    return;
}

__PACKAGE__->meta->make_immutable;

1;

package Promises::Promise;

sub sync {
    my ($self) = @_;
    my $cv = AnyEvent->condvar;
    $self->then( sub { $cv->send(@_) },
        sub { $cv->croak( 'failed: ' . $_[0] ) } );
    return $cv->recv;
}

sub ft {
    my $self = shift;
    my $ft   = Future->new;
    Scalar::Util::weaken( my $weak_ft = $ft );
    $self->then(
        sub { $weak_ft->done(@_) if $weak_ft; 1 },
        sub { $weak_ft->fail(@_) if $weak_ft; 1 }
    );
    return $ft;
}

1;
