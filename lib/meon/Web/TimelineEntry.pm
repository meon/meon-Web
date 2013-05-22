package meon::Web::TimelineEntry;

use meon::Web::Util;
use DateTime::Format::Strptime;

use Moose;
use MooseX::Types::Path::Class;
use 5.010;

has 'file'           => (is=>'rw', isa=>'Path::Class::File',coerce=>1,lazy_build=>1,);
has 'timeline_dir'   => (is=>'rw', isa=>'Path::Class::Dir',coerce=>1,lazy_build=>1);
has 'xml'            => (is=>'rw', isa=>'XML::LibXML::Document', lazy_build => 1);
has 'title'          => (is=>'ro', isa=>'Str',lazy_build=>1,);
has 'created'        => (is=>'rw', isa=>'DateTime',lazy_build=>1,);
has 'author'         => (is=>'ro', isa=>'Maybe[Str]',lazy_build=>1,predicate=>'has_author');
has 'intro'          => (is=>'ro', isa=>'Maybe[Str]',lazy_build=>1,predicate=>'has_intro');
has 'body'           => (is=>'ro', isa=>'Maybe[Str]',lazy_build=>1,predicate=>'has_body');
has 'xc'             => (is=>'ro', isa=>'XML::LibXML::XPathContext',lazy_build=>1,);

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
    my ($title) = $xc->findnodes('/w:page/w:content//x:h1');
    die 'missing title in '.$self->file
        unless $title;

    return $title->textContent;
}

sub _build_created {
    my ($self) = @_;

    my $xml = $self->xml;
    my $xc  = $self->xc;
    my ($created_iso8601) = $xc->findnodes('/w:page/w:content//x:span[@class="created"]');
    die 'missing created in '.$self->file
        unless $created_iso8601;
    $created_iso8601 = $created_iso8601->textContent;

    return $strptime_iso8601->parse_datetime($created_iso8601);
}

sub _build_author {
    my ($self) = @_;

    my $xml = $self->xml;
    my $xc  = $self->xc;
    my ($author) = $xc->findnodes('/w:page/w:meta/w:author');
    return undef unless $author;

    return $author->textContent;
}

sub _build_intro {
    my ($self) = @_;

    my $xml = $self->xml;
    my $xc  = $self->xc;
    my ($intro) = $xc->findnodes('/w:page/w:content//x:p');
    return undef unless $intro;

    return $intro->textContent;
}

sub _build_body {
    my ($self) = @_;

    my $xml = $self->xml;
    my $xc  = $self->xc;
    my (undef,$body) = $xc->findnodes('/w:page/w:content//x:p');
    return undef unless $body;

    return $body->textContent;
}

sub create {
    my ($self) = @_;

    my $created  = DateTime->now(time_zone=>'UTC');
    $self->created($created);
    $created = $created->iso8601;

    my $title    = $self->title;
    my $intro    = $self->has_intro  ? '<p>'.$self->intro.'</p>' : '';
    my $body     = $self->has_body   ? '<p>'.$self->body.'</p>' : '';
    my $author   = $self->has_author ? '    <author>'.$self->author.'</author>' : '';

    # FIXME instead of direct string interpolation, use setters so that XML special chars are properly escaped
    my $xml = XML::LibXML->load_xml(string => qq{<?xml version="1.0" encoding="UTF-8"?>
<page
    xmlns:xhtml="http://www.w3.org/1999/xhtml"
    xmlns="http://web.meon.eu/"
    xmlns:w="http://web.meon.eu/"
>

<meta>
$author
    <title>$title</title>
    <form>
        <owner-only/>
        <process>Delete</process>
        <redirect>../../</redirect>
    </form>
</meta>

<content><div xmlns="http://www.w3.org/1999/xhtml">
<div class="timeline-entry">
<span class="created">$created</span>
<h1>$title</h1>
$intro
$body
</div>

<div class="delete-confirmation"><w:form copy-id="form-delete"/></div>

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
    
    unless (-e $file->dir) {
        die 'FIXME create index.xml in '.$file->dir;
        $file->dir->mkpath;
    }

    $file->spew($xml->toString);
}

sub previous_month {
}

__PACKAGE__->meta->make_immutable;

1;
