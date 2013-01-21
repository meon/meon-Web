package meon::Web::Member;

use Moose;
use 5.010;

use Path::Class 'file';
use DateTime;

has 'members_folder' => (is=>'rw',isa=>'Str|Path::Class::Dir',required=>1);
has 'username'       => (is=>'rw',isa=>'Str',required=>1);

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
    <title>$name</title>
    <user xmlns="http://search.cpan.org/perldoc?Catalyst%3A%3APlugin%3A%3AAuthentication%3A%3AStore%3A%3AUserXML">
        <status>registration-pending</status>
        <username>$username</username>
        <password>***DISABLED***</password>
    </user>
    <full-name>$name</full-name>
    <email>$email</email>
    <created>$created</created>
    <address>$address</address>
    <location>
        <lat>$lat</lat>
        <lng>$lng</lng>
    </location>
    <registration-form>$reg_form</registration-form>
</meta>

<content><div xmlns="http://www.w3.org/1999/xhtml">
</div></content>

</page>
});
}

sub member_index_filename {
    my $self = shift;

    return file($self->members_folder, $self->username, 'index.xml');
}

__PACKAGE__->meta->make_immutable;

1;
