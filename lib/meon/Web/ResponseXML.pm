package meon::Web::ResponseXML;

use strict;
use warnings;

use XML::LibXML;
use Scalar::Util 'blessed';
use Moose;
use 5.010;

has 'dom' => (is=>'rw',isa=>'XML::LibXML::Document',lazy_build=>1);
has '_xml_libxml' => (is=>'rw',isa=>'XML::LibXML',lazy=>1,default=>sub { XML::LibXML->new });
has 'elements' => (
    is      => 'rw',
    isa     => 'ArrayRef[Object]',
    default => sub{[]},
	traits  => ['Array'],
	handles => {
		'push_element' => 'push',
		'elements_all' => 'elements',
	},
);

sub _build_dom {
    my ($self) = @_;

    my $dom = $self->_xml_libxml->createDocument("1.0", "UTF-8");
    my $rxml = $dom->createElement('rxml');
    $rxml->setNamespace('http://www.w3.org/1999/xhtml','xhtml',0);
    $rxml->setNamespace('http://web.meon.eu/','');
    $rxml->setNamespace('http://web.meon.eu/','w');
    $dom->setDocumentElement($rxml);
    return $dom;
}

sub create_element {
    my ($self, $name, $id) = @_;

    my $element = $self->dom->createElementNS('http://web.meon.eu/',$name);
    $element->setAttribute('id'=>$id)
        if defined $id;

    return $element;
}

sub append_xml {
    my ($self, $xml) = @_;

    my $dom    = $self->dom;

    given (ref $xml) {
        when ('') {
            my $parser = $self->_xml_libxml;
            $dom->getDocumentElement->appendChild(
                $parser->parse_balanced_chunk($xml)
            );
        }
        when ('XML::LibXML::Element') {
            $dom->getDocumentElement->appendChild($xml);
        }
        default { die 'what to do with '.$xml.'?'; }
    }

    return $self;
}

sub parse_xhtml_string {
    my ($self, $xml) = @_;

    my $dom    = $self->dom;

    my $parser  = $self->_xml_libxml;
    my $element = $parser->parse_string(
        '<div xmlns="http://www.w3.org/1999/xhtml">'.$xml.'</div>'
    )->getDocumentElement->firstChild;

    return $element;
}

sub push_new_element {
    my ($self, $name, $id) = @_;

    my $element = $self->create_element($name,$id);
    $self->push_element($element);
    return $element;
}

sub get_element {
    my ($self, $id) = @_;

    foreach my $element ($self->elements_all) {
        my $eid = ($element->can('id') ? $element->id : $element->getAttribute('id'));
        return $element
            if (defined($eid) && ($id eq $eid));
    }

    return undef;
}

sub get_or_create_element {
    my ($self, $id, $name) = @_;

    return
        $self->get_element($id)
        || $self->push_new_element($name)
    ;
}

sub add_xhtml_form {
    my ($self, $xml) = @_;

    my $forms = $self->get_or_create_element('forms', 'forms');

    $forms->appendChild(
        $self->parse_xhtml_string($xml)
    );

    return $self;
}

sub add_xhtml_link {
    my ($self, $link) = @_;

    confess 'is '.$link.' a link?'
        unless blessed($link) && $link->isa('eusahub::Data::Link');

    my $forms = $self->get_or_create_element('links', 'links');

    $forms->appendChild($link->as_xml);

    return $self;
}

sub as_string { return $_[0]->as_xml->toString(1); }

sub as_xml {
    my ($self) = @_;

    my $dom = $self->dom;
    my $root_el = $dom->getDocumentElement;
    foreach my $element ($self->elements_all) {
        $element = $element->as_xml
            if $element->can('as_xml');

        $root_el->addChild($element);
    }

    return $dom;
}

1;
