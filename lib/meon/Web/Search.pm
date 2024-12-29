package meon::Web::Search;

use Moose;
use 5.010;
use Carp qw(croak);

use meon::Web::Config;
use meon::Web::env;
use meon::Web::SearchItem;
use Path::Class qw(dir file);
use XML::Chain qw(xc);
use URI::Escape qw(uri_escape);

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
    handles => {
        all_osearch_records => 'elements',
        add_osearch_record  => 'push',
    },
);

sub _build_dst_hostname_dir {
    my ($self) = @_;

    my $dst_domain      = $self->hostname;
    my $hostname_folder = meon::Web::Config->hostname_to_folder($dst_domain);
    croak 'no such hostname ' . $dst_domain
        unless $hostname_folder;
    my $dst_hostname_dir =
        dir(meon::Web::SPc->srvdir, 'www', 'meon-web', $hostname_folder, 'content');
    croak 'no such dir'
        unless -d $dst_hostname_dir;

    return $dst_hostname_dir;
}

sub _build_osearch_records {
    my ($self) = @_;

    return [
        @{$self->_records_from_content},
        @{$self->_records_from_category_product},
    ];
}

sub _records_from_category_product {
    my ($self) = @_;

    my @osearch_records;

    meon::Web::env->hostname($self->hostname);
    meon::Web::env->xml_file('_search.xml');
    meon::Web::env->xml(_search_xml());
    meon::Web::env->apply_includes;

    my $cat_prod_xml = xc(meon::Web::env->transform_xml);
    $cat_prod_xml->reg_global_ns('w' => 'http://web.meon.eu/');
    $cat_prod_xml->find('/w:opensearch/w:search-category-product/w:search-item')->each(
        sub {
            my $cat_prod_el  = $_;
            my $ident        = $cat_prod_el->find('w:ident')->text_content;
            my $cat_prod_uri = $cat_prod_el->find('w:href')->text_content;
            my $title_txt    = $cat_prod_el->find('w:title')->text_content;
            my $teaser_txt   = $cat_prod_el->find('w:teaser')->text_content;
            my $content_txt  = $cat_prod_el->find('w:description')->text_content;
            my $thumb_uri    = $cat_prod_el->find('w:thumb-img-src')->text_content;
            my @sub_cat_prod;
            $cat_prod_el->find('w:subcategory-products/w:category-product')->each(
                sub {
                    push(@sub_cat_prod, $_->attr('ident'));
                }
            );

            push(
                @osearch_records,
                meon::Web::SearchItem->new(
                    type      => (@sub_cat_prod ? 'category' : 'product'),
                    ident     => $ident,
                    title     => $title_txt,
                    teaser    => $teaser_txt,
                    content   => $content_txt,
                    uri       => $cat_prod_uri,
                    thumbnail => $thumb_uri,
                    (@sub_cat_prod ? (sub_cat_prod => \@sub_cat_prod) : ()),
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
        my $sub_cat_prod = $rec->{sub_cat_prod};
        next unless $sub_cat_prod;
        my $parent_ident = $rec->{ident};
        for my $cat_prod_ident (@$sub_cat_prod) {
            $ident_parent{$cat_prod_ident} //= $parent_ident;
        }
    }
    for my $rec (@osearch_records) {
        my $cident = $rec->{ident};
        next unless $cident;
        while (my $parent_ident = $ident_parent{$cident}) {
            $cident = $parent_ident;
            my $ctitle = $ident_to_rec{$cident}->{title};
            if ($rec->{breadcrumb}) {
                $rec->{breadcrumb} = $ctitle.' > '.$rec->{breadcrumb};
            }
            else {
                $rec->{breadcrumb} = $ctitle;
            }
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
            my $rel_file = $file->stringify;
            $rel_file =~ s/(index)?\.xml$//;
            $rel_file =~ s/^$dst_hostname_dir//;
            return if $rel_file eq '/sitemap';

            my $content_xml = xc($file);
            $content_xml->reg_global_ns('w' => 'http://web.meon.eu/');
            return unless $content_xml->find('/w:page/w:content')->count;

            my $robots_txt = $content_xml->find('/w:page/w:meta/w:robots')->text_content;
            return if $robots_txt =~ m/\b noindex \b/xms;

            my $title_txt = $content_xml->find('/w:page/w:meta/w:title')->text_content;
            my $page_uri = join('/', map {uri_escape($_)} file($rel_file)->components);

            my $thumb_uri;
            if (my $thumb = $content_xml->find('//w:img-thumb')->text_content) {
                my @thumb_comp;
                if ($thumb =~ m{^/}) {
                    @thumb_comp = file($thumb)->components;
                }
                else {
                    @thumb_comp = (file($rel_file)->components, $thumb);
                }
                $thumb_uri = join('/', map {uri_escape($_)} @thumb_comp);
            }

            my $content_txt = $content_xml->find('/w:page/w:content')->text_content;

            push(
                @osearch_records,
                meon::Web::SearchItem->new(
                    type      => 'page',
                    title     => $title_txt,
                    content   => $content_txt,
                    uri       => $page_uri,
                    thumbnail => $thumb_uri,
                )
            );
        }
    );

    return \@osearch_records;
}

sub _search_xml {
    return XML::LibXML->load_xml(string => <<'__XML_SEARCH__');
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
