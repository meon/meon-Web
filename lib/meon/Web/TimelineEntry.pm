package meon::Web::TimelineEntry;

use meon::Web::Util;
use DateTime::Format::Strptime;
use File::Copy 'copy';
use Path::Class qw();

use Moose;
use MooseX::Types::Path::Class;
use 5.010;
use utf8;

has 'file'           => (is=>'rw', isa=>'Path::Class::File',coerce=>1,lazy_build=>1,);
has 'timeline_dir'   => (is=>'rw', isa=>'Path::Class::Dir',coerce=>1,lazy_build=>1);
has 'xml'            => (is=>'rw', isa=>'XML::LibXML::Document', lazy_build => 1);
has 'title'          => (is=>'ro', isa=>'Str',lazy_build=>1,);
has 'created'        => (is=>'rw', isa=>'DateTime',lazy_build=>1,);
has 'author'         => (is=>'ro', isa=>'Maybe[Str]',lazy_build=>1,predicate=>'has_author');
has 'intro'          => (is=>'ro', isa=>'Maybe[Str]',lazy_build=>1,predicate=>'has_intro');
has 'body'           => (is=>'ro', isa=>'Maybe[Str]',lazy_build=>1,predicate=>'has_body');
has 'comment_to'     => (is=>'ro', isa=>'Maybe[Object]',lazy_build=>1,predicate=>'has_parent');
has 'xc'             => (is=>'ro', isa=>'XML::LibXML::XPathContext',lazy_build=>1,);
has 'category'       => (is=>'ro', isa=>'Str',lazy_build=>1,);

my $strptime_iso8601 = DateTime::Format::Strptime->new(
    pattern => '%FT%T',
    time_zone => 'UTC',
    on_error => 'croak',
);

sub _build_file {
    my ($self) = @_;

    my $year  = $self->created->strftime('%Y');
    my $month = $self->created->strftime('%m');
    my $filename = meon::Web::Util->filename_cleanup($self->title);
    while (length($filename) < 5) {
        $filename .= chr(97+rand(26));
    }
    $filename .= ".xml";
    return $self->timeline_dir->subdir($year)->subdir($month)->file($filename);
}

sub _build_timeline_dir {
    my ($self) = @_;

    return $self->file->dir->parent->parent;
}

sub _build_xml {
    my ($self) = @_;

    return XML::LibXML->load_xml(
        location => $self->file
    );
}

sub _build_xc {
    my ($self) = @_;

    my $xml = $self->xml;
    my $xc = XML::LibXML::XPathContext->new($xml);
    $xc->registerNs('w', 'http://web.meon.eu/');
    $xc->registerNs('x', 'http://www.w3.org/1999/xhtml');
    return $xc;
}

sub _build_title {
    my ($self) = @_;

    my $xml = $self->xml;
    my $xc  = $self->xc;
    my ($title) = $xc->findnodes('/w:page/w:content//w:timeline-entry/w:title');
    die 'missing title in '.$self->file
        unless $title;

    return $title->textContent;
}

sub _build_created {
    my ($self) = @_;

    my $xml = $self->xml;
    my $xc  = $self->xc;
    my ($created_iso8601) = $xc->findnodes('/w:page/w:content//w:timeline-entry/w:created');
    die 'missing created in '.$self->file
        unless $created_iso8601;
    $created_iso8601 = $created_iso8601->textContent;

    return $strptime_iso8601->parse_datetime($created_iso8601);
}

sub _build_author {
    my ($self) = @_;

    my $xml = $self->xml;
    my $xc  = $self->xc;
    my ($author) = $xc->findnodes('/w:page/w:content//w:timeline-entry/w:author');
    return undef unless $author;

    return $author->textContent;
}

sub _build_intro {
    my ($self) = @_;

    my $xml = $self->xml;
    my $xc  = $self->xc;
    my ($intro) = $xc->findnodes('/w:page/w:content//w:timeline-entry/w:intro');
    return undef unless $intro;

    return $intro->textContent;
}

sub _build_body {
    my ($self) = @_;

    my $xml = $self->xml;
    my $xc  = $self->xc;
    my (undef,$body) = $xc->findnodes('/w:page/w:content//w:timeline-entry/w:text');
    return undef unless $body;

    return $body->textContent;
}

sub _build_category {
    my ($self) = @_;

    my $xml = $self->xml;
    my $xc  = $self->xc;
    my ($category) = $xc->findnodes('/w:page/w:content//w:timeline-entry/@category');
    return 'news'
        unless $category;

    return $category->textContent;
}

sub create {
    my ($self) = @_;

    my $created  = DateTime->now(time_zone=>'UTC');
    $self->created($created);
    $created = $created->iso8601;

    my $title      = $self->title;
    my $intro      = $self->has_intro  ? '<w:intro>'.$self->intro.'</w:intro>' : '';
    my $body       = $self->has_body   ? '<w:text>'.$self->body.'</w:text>' : '';
    my $author     = $self->has_author ? '<w:author>'.$self->author.'</w:author>' : '';
    my $comment_to = $self->has_parent ? '<w:parent>'.$self->comment_to->web_uri.'</w:parent>' : '';
    my $category   = $self->category;

    # FIXME instead of direct string interpolation, use setters so that XML special chars are properly escaped
    my $xml = XML::LibXML->load_xml(string => qq{<?xml version="1.0" encoding="UTF-8"?>
<page
    xmlns:xhtml="http://www.w3.org/1999/xhtml"
    xmlns="http://web.meon.eu/"
    xmlns:w="http://web.meon.eu/"
>

<meta>
    <title>$title</title>
    <form>
        <owner-only/>
        <process>Delete</process>
        <redirect>../../</redirect>
    </form>
</meta>

<content><div xmlns="http://www.w3.org/1999/xhtml">

<w:timeline-entry category="$category">
    <w:created>$created</w:created>
    $author
    <w:title>$title</w:title>
    $comment_to
    $intro
    $body

    <w:timeline class="comments">
    </w:timeline>
</w:timeline-entry>


</div></content>

</page>
});
    $self->xml($xml);

    return $self->store;
}

sub store {
    my $self = shift;
    my $xml = $self->xml;
    my $file = $self->file;
    my $dir  = $file->dir;
    my $timeline_dir = $self->timeline_dir;

    $dir->mkpath
        unless -e $dir;
    unless (-e $dir->file('index.xml')) {
        $dir->resolve;
        $timeline_dir->resolve;
        my $list_index_file = Path::Class::file(
            meon::Web::SPc->datadir, 'meon-web', 'template', 'xml','timeline-list-index.xml'
        );
        my $timeline_index_file = Path::Class::file(
            meon::Web::SPc->datadir, 'meon-web', 'template', 'xml','timeline-index.xml'
        );
        copy($list_index_file, $dir->file('index.xml')) or die 'copy failed: '.$!;

        while (($dir = $dir->parent) && $timeline_dir->contains($dir) && !-e $dir->file('index.xml')) {
            copy($timeline_index_file, $dir->file('index.xml')) or die 'copy failed: '.$!;
        }
    }

    # generate new filename if current one already exists
    while (-e $file) {
        if ($file =~ m/^(.+)-(\d{2,}).xml/) {
            $file = $1.'-'.sprintf('%02d', $2+1).'.xml';
        }
        else {
            $file = substr($file,0,-4).'-01.xml';
        }
        $file = Path::Class::file($file);
    }

    $file->spew($xml->toString);
    if ($self->has_parent) {
        my $base_dir = $self->comment_to->_full_path->dir;
        my $path = $file->resolve;
        $path = $path->relative($base_dir);
        $path =~ s/\.xml$//;
        $self->comment_to->add_comment($path);
    }
}

sub element {
    my ($self) = @_;

    my $xml = $self->xml;
    my $xc  = $self->xc;
    my ($el) = $xc->findnodes('/w:page/w:content//w:timeline-entry');
    die 'no timeline entry in '.$self->file
        unless $el;

    return $el;
}

__PACKAGE__->meta->make_immutable;

1;
