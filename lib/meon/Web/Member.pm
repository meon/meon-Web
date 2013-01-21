package meon::Web::Member;

use Moose;
use 5.010;

use Path::Class 'file', 'dir';
use DateTime;
use XML::LibXML;

has 'members_folder' => (is=>'rw',isa=>'Any',required=>1);
has 'username'       => (is=>'rw',isa=>'Str',required=>1);
has 'xml'            => (is=>'ro', isa=>'XML::LibXML::Document', lazy => 1, builder => '_build_xml');
has 'member_meta'    => (is=>'ro', isa=>'XML::LibXML::Node',lazy=>1,builder=>'_build_member_meta');

sub _build_xml {
    my ($self) = @_;

    return XML::LibXML->load_xml(
        location => $self->member_index_filename
    );
}

sub _build_member_meta {
    my ($self) = @_;

    my $xml = $self->xml;
    my $xc = XML::LibXML::XPathContext->new($xml);
    $xc->registerNs('w', 'http://web.meon.eu/');
    my ($member_meta) = $xc->findnodes('//w:meta');
    return $member_meta;
}

sub set_member_meta {
    my ($self, $name, $value) = @_;

    my $meta = $self->member_meta;
    my $xc = XML::LibXML::XPathContext->new($meta);
    $xc->registerNs('w', 'http://web.meon.eu/');
    my ($element) = $xc->findnodes('//w:'.$name);
    foreach my $child ($element->childNodes()) {
        $element->removeChild($child);
    }
    $element->appendText($value);
}

sub create {
    my ($self, %args) = @_;

    my $filename = $self->member_index_filename;
    my $username = $self->username;
    my $name     = $args{name};
    my $email    = $args{email};
    my $address  = $args{address};
    my $lat      = $args{lat};
    my $lng      = $args{lng};
    my $reg_form = $args{registration_form};
    my $created  = DateTime->now('time_zone' => 'UTC')->iso8601;

    # FIXME instead of direct string interpolation, use setters so that XML special chars are properly escaped
    $filename->spew(qq{<?xml version="1.0" encoding="UTF-8"?>
<page
    xmlns:xhtml="http://www.w3.org/1999/xhtml"
    xmlns="http://web.meon.eu/"
    xmlns:w="http://web.meon.eu/"
>

<meta>
    <title></title>
    <user xmlns="http://search.cpan.org/perldoc?Catalyst%3A%3APlugin%3A%3AAuthentication%3A%3AStore%3A%3AUserXML">
        <status>registration-pending</status>
        <username>$username</username>
        <password>***DISABLED***</password>
    </user>
    <full-name></full-name>
    <email></email>
    <created>$created</created>
    <address></address>
    <lat></lat>
    <lng></lng>
    <registration-form></registration-form>
</meta>

<content><div xmlns="http://www.w3.org/1999/xhtml">
</div></content>

</page>
});

    $self->set_member_meta('title',$name);
    $self->set_member_meta('full-name',$name);
    $self->set_member_meta('email',$email);
    $self->set_member_meta('address',$address);
    $self->set_member_meta('lat',$lat);
    $self->set_member_meta('lng',$lng);
    $self->set_member_meta('registration-form',$reg_form);
    $self->store;
}

sub member_index_filename {
    my $self = shift;

    return file($self->members_folder, $self->username, 'index.xml');
}

sub store {
    my $self = shift;

    my $filename = $self->member_index_filename;
    my $xml = $self->xml;
    $filename->spew($xml->toString);
}

__PACKAGE__->meta->make_immutable;

1;
