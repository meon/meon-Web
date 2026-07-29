package meon::Web::Search;

use Moose;
use 5.010;
use utf8;
use Carp qw(croak);
use namespace::autoclean;

use meon::Web::Config;
use meon::Web::env;
use meon::Web::SearchItem;
use meon::Web::SearchIndex;
use meon::Web::Util;
use Path::Class qw(dir file);
use XML::Chain  qw(xc);
use URI::Escape qw(uri_escape);
use POSIX       qw(strftime);

has 'hostname' => (
    is       => 'ro',
    isa      => 'Str',
    required => 1,
);
has 'dst_hostname_dir' => (
    is      => 'ro',
    isa     => 'Path::Class::Dir',
    lazy    => 1,
    builder => '_build_dst_hostname_dir',
);
has 'osearch_records' => (
    is      => 'ro',
    isa     => 'ArrayRef[meon::Web::SearchItem]',
    lazy    => 1,
    builder => '_build_osearch_records',
    traits  => ['Array'],
    handles => {
        all_osearch_records => 'elements',
        add_osearch_record  => 'push',
    },
);
has 'index_ts' => (
    is      => 'ro',
    isa     => 'Str',
    lazy    => 1,
    builder => '_build_index_ts',
);
has 'teaser_max_len' => (
    is      => 'ro',
    isa     => 'Int',
    default => 250,
);
has 'search_index' => (
    is      => 'ro',
    isa     => 'meon::Web::SearchIndex',
    lazy    => 1,
    builder => '_build_search_index',
);

sub _build_search_index {
    my ($self) = @_;
    return meon::Web::SearchIndex->new( hostname => $self->hostname );
}

sub _build_dst_hostname_dir {
    my ($self) = @_;

    my $dst_domain      = $self->hostname;
    my $hostname_folder = meon::Web::Config->hostname_to_folder($dst_domain);
    croak 'no such hostname ' . $dst_domain
        unless $hostname_folder;
    my $dst_hostname_dir =
        dir( meon::Web::SPc->srvdir, 'www', 'meon-web', $hostname_folder,
        'content' );
    croak 'no such dir'
        unless -d $dst_hostname_dir;

    return $dst_hostname_dir;
}

sub _build_osearch_records {
    my ($self) = @_;

    my @osearch_records =
        sort {
        _url_depth( $a->url ) <=> _url_depth( $b->url )
            || ( $a->tree_idx <=> $b->tree_idx )
        } (
        @{ $self->_records_from_category_product },
        @{ $self->_records_from_content },
        );

    return \@osearch_records if @osearch_records < 2;

    my $records_count = scalar(@osearch_records);
    my $bucket_count  = $records_count < 1000 ? $records_count : 1000;
    my $denom         = $bucket_count - 1;

    for my $rec_idx ( 0 .. $#osearch_records ) {
        my $rec    = $osearch_records[$rec_idx];
        my $bucket = int( $rec_idx * $bucket_count / $records_count );
        my $weight = 0.001 * ( 1 - ( $bucket / $denom ) );
        $rec->weight( sprintf '%.6f', $weight );
    }

    return \@osearch_records;
}

sub _url_depth {
    my ($url) = @_;
    return scalar grep {length} split m{/+}, $url // '';
}

sub _teaser_from_content {
    my ( $self, $teaser_txt, $content_txt ) = @_;
    my $teaser_limit = $self->teaser_max_len;

    if ( defined $teaser_txt ) {
        $teaser_txt =~ s/\s+/ /g;
        $teaser_txt =~ s/^\s+|\s+$//g;
        return $teaser_txt if length $teaser_txt;
    }

    return unless defined $content_txt;

    $content_txt =~ s/\s+/ /g;
    $content_txt =~ s/^\s+|\s+$//g;

    return undef unless length $content_txt;
    return $content_txt if length($content_txt) <= $teaser_limit;

    my $truncated = substr( $content_txt, 0, $teaser_limit - 1 );
    my $word_boundary = rindex( $truncated, ' ' );
    if ( $word_boundary > 0 ) {
        $truncated = substr( $truncated, 0, $word_boundary );
    }
    $truncated =~ s/^\s+|\s+$//g;
    $truncated = substr( $content_txt, 0, $teaser_limit - 1 )
        unless length $truncated;

    return $truncated . '…';
}

sub _records_from_category_product {
    my ($self) = @_;

    my @osearch_records;

    meon::Web::env->hostname( $self->hostname );
    meon::Web::env->xml_file('_search.xml');
    meon::Web::env->xml( _search_xml() );
    meon::Web::env->apply_includes;

    my $cat_prod_xml = xc( meon::Web::env->transform_xml );
    $cat_prod_xml->reg_global_ns( 'w' => 'http://web.meon.eu/' );
    $cat_prod_xml->find(
        '/w:opensearch/w:search-category-product/w:search-item')->each(
        sub {
            my $cat_prod_el  = $_;
            my $ident        = $cat_prod_el->find('w:ident')->text_content;
            my $cat_prod_uri = $cat_prod_el->find('w:href')->text_content;
            my $title_txt    = $cat_prod_el->find('w:title')->text_content;
            my $xml_teaser_txt = $cat_prod_el->find('w:teaser')->text_content;
            my $desc_txt     = $cat_prod_el->find('w:description')->text_content;
            my $teaser_txt =
                $self->_teaser_from_content( $xml_teaser_txt, $desc_txt );
            my $has_xml_teaser = defined $xml_teaser_txt;
            if ($has_xml_teaser) {
                $xml_teaser_txt =~ s/\s+/ /g;
                $xml_teaser_txt =~ s/^\s+|\s+$//g;
                $has_xml_teaser = length $xml_teaser_txt ? 1 : 0;
            }
            my $tree_idx     = $cat_prod_el->find('w:tree-idx')->text_content;
            my $thumb_uri =
                $cat_prod_el->find('w:thumb-img-src')->text_content;
            my @sub_cat_prod;
            $cat_prod_el->find('w:subcategory-products/w:category-product')
                ->each(
                sub {
                    push( @sub_cat_prod, $_->attr('ident') );
                }
                );

            my $content_txt = join(
                "\n",
                map { meon::Web::Util->norm_tokens($_) } (
                    $title_txt . ( $has_xml_teaser ? ' ' . $teaser_txt : q{} ),
                    $desc_txt
                )
            );

            push(
                @osearch_records,
                meon::Web::SearchItem->new(
                    search_type => ( @sub_cat_prod ? 'category' : 'product' ),
                    ident       => $ident,
                    title       => $title_txt,
                    teaser      => $teaser_txt,
                    search_content => $content_txt,
                    url            => $cat_prod_uri,
                    weight         => 0,
                    tree_idx       => $tree_idx,
                    thumbnail      => $thumb_uri,
                    (   @sub_cat_prod
                        ? ( sub_cat_prod => \@sub_cat_prod )
                        : ()
                    ),
                    index_ts => $self->index_ts,
                )
            );
        }
        );

    # build breadcrumb
    my %ident_to_rec;
    for my $rec (@osearch_records) {
        my $ident = $rec->{ident};
        next unless $ident;
        $ident_to_rec{$ident} = $rec;
    }
    my %ident_parent;
    for my $rec (@osearch_records) {
        next unless $rec->is_sub_cat_prod;
        my $parent_ident = $rec->{ident};
        my $sub_cat_prod = $rec->sub_cat_prod;
        for my $cat_prod_ident (@$sub_cat_prod) {
            $ident_parent{$cat_prod_ident} //= $parent_ident;
        }
    }
    for my $rec (@osearch_records) {
        my $cident = $rec->{ident};
        next unless $cident;
        my @breadcrumb_parts;
        while ( my $parent_ident = $ident_parent{$cident} ) {
            $cident = $parent_ident;
            my $ctitle = $ident_to_rec{$cident}->{title};
            unshift(@breadcrumb_parts, $ctitle);
        }
        if (@breadcrumb_parts) {
            $rec->breadcrumb( join( ' > ', @breadcrumb_parts ) );
            $rec->search_content(
                meon::Web::Util->norm_tokens(
                    join( ' ', @breadcrumb_parts )
                    )
                    . "\n"
                    . $rec->search_content
            );
        }
    }

    return \@osearch_records;
}

sub _records_from_content {
    my ($self) = @_;

    my @osearch_records;
    my $dst_hostname_dir = $self->dst_hostname_dir;
    $dst_hostname_dir->recurse(
        callback => sub {
            my ($file) = @_;
            return if $file->is_dir;
            return if $file !~ m/\.xml$/;
            my $file_mtime = $file->stat->mtime;
            my $rel_file   = $file->stringify;
            $rel_file =~ s/(index)?\.xml$//;
            $rel_file =~ s/^$dst_hostname_dir//;
            return if $rel_file eq '/sitemap';

            my $content_xml = xc($file);
            $content_xml->reg_global_ns( 'w' => 'http://web.meon.eu/' );
            return unless $content_xml->find('/w:page/w:content')->count;

            my $robots_txt =
                $content_xml->find('/w:page/w:meta/w:robots')->text_content;
            return if $robots_txt =~ m/\b noindex \b/xms;

            my $title_txt =
                $content_xml->find('/w:page/w:meta/w:title')->text_content;
            my $content_body_txt =
                $content_xml->find('/w:page/w:content')->text_content;
            my $teaser_txt =
                $self->_teaser_from_content( undef, $content_body_txt );
            my $page_uri = join( '/',
                map { uri_escape($_) } file($rel_file)->components );

            my $thumb_uri;
            if ( my $thumb =
                $content_xml->find('//w:img-thumb')->text_content ) {
                my @thumb_comp;
                if ( $thumb =~ m{^/} ) {
                    @thumb_comp = file($thumb)->components;
                }
                else {
                    @thumb_comp = ( file($rel_file)->components, $thumb );
                }
                $thumb_uri = join( '/', map { uri_escape($_) } @thumb_comp );
            }

            my $content_txt = join(
                "\n",
                map { meon::Web::Util->norm_tokens($_) } (
                    $title_txt,
                    $content_body_txt
                )
            );

            push(
                @osearch_records,
                meon::Web::SearchItem->new(
                    search_type    => 'page',
                    title          => $title_txt,
                    teaser         => $teaser_txt,
                    search_content => $content_txt,
                    url            => $page_uri,
                    weight         => 0,
                    thumbnail      => $thumb_uri,
                    index_ts       => $self->_build_index_ts,
                )
            );
        }
    );

    return \@osearch_records;
}

sub do_indexing {
    my ( $self, @args ) = @_;
    my %args =
        ( @args == 1 && ref( $args[0] ) eq 'HASH' ? %{ $args[0] } : @args, );
    my $dry_run = $args{dry_run} ? 1 : 0;

    $self->search_index->init_index;
    my @ose_records = $self->all_osearch_records;
    while (@ose_records) {
        my @batch = splice( @ose_records, 0, 100 );
        $self->search_index->index_docs( \@batch );
    }
    $self->search_index->switch_active_index
        unless $dry_run;
    return;
}

sub update_schema {
    my ($self) = @_;
    $self->search_index->update_schema;
    return;
}

sub _build_index_ts {
    my ($self) = @_;
    return strftime( '%Y-%m-%dT%H:%M:%SZ', gmtime(time) );
}

sub _search_xml {
    return XML::LibXML->load_xml( string => <<'__XML_SEARCH__' );
<?xml version="1.0" encoding="UTF-8"?>
<page
    xmlns:xhtml="http://www.w3.org/1999/xhtml"
    xmlns="http://web.meon.eu/"
    xmlns:w="http://web.meon.eu/"
>
<meta>
    <title>Search</title>
    <robots>noindex, follow</robots>
    <template>search</template>
</meta>
<content>
    <category-product-search-items/>
</content>
<w:include path="category-products.xml">
    <w:current-category-product ident="home"/>
    <w:category-product-breadcrumb href="home"/>
</w:include>
</page>
__XML_SEARCH__
}

__PACKAGE__->meta->make_immutable;

1;
