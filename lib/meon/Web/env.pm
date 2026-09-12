package meon::Web::env;

use strict;
use warnings;
use 5.010;

use Carp 'confess';
use XML::LibXML;
use XML::LibXML::XPathContext;
use XML::LibXSLT;
use Scalar::Util 'weaken';
use meon::Web::Config;
use meon::Web::SPc;
use meon::Web::Util;
use Path::Class 'dir', 'file';
use URI::Escape 'uri_escape_utf8';
use meon::Web::Member;
use File::Find::Age;
use HTTP::Exception;
use Class::Load qw(load_class);

my $env = {};
sub get { return $env; }
sub clear { $env = {}; return $env; }

XML::LibXSLT->register_function(
    'http://web.meon.eu/',
    'uri_escape',
    sub { uri_escape_utf8($_[0]) }
);

sub xpc {
    my $self = shift;
    my $xpc = XML::LibXML::XPathContext->new($env->{xml});
    $xpc->registerNs('x', 'http://www.w3.org/1999/xhtml');
    $xpc->registerNs('w', 'http://web.meon.eu/');
    $xpc->registerNs('u', 'http://search.cpan.org/perldoc?Catalyst%3A%3AAuthentication%3A%3AStore%3A%3AUserXML');
    return $xpc;
}

sub hostname {
    my $self = shift;
    $env->{hostname} = shift
        if @_;
    return $env->{hostname} // confess('hostname unset');
}

sub current_dir {
    my $self = shift;
    return file($self->xml_file)->dir;
}

sub current_path {
    my $self = shift;
    $env->{current_path} = shift
        if @_;
    return $env->{current_path} // confess('current_path unset');
}

sub hostname_dir_name {
    my $self = shift;
    $env->{hostname_dir_name} = shift
        if @_;

    unless (defined($env->{hostname_dir_name})) {
        $env->{hostname_dir_name} = meon::Web::Config->hostname_to_folder($self->hostname);
    }
    return $env->{hostname_dir_name};
}

sub hostname_dir {
    my $self = shift;
    $env->{hostname_dir} = shift
        if @_;

    unless (defined($env->{hostname_dir})) {
        my $hostname_dir_name = meon::Web::Config->hostname_to_folder($self->hostname);
        $env->{hostname_dir} = dir(meon::Web::SPc->srvdir, 'www', 'meon-web', $hostname_dir_name)->absolute->resolve;
    }
    return $env->{hostname_dir};
}

sub hostname_subdir {
    my $self = shift;
    my $sub  = shift;

    my $subdir = $self->hostname_dir->subdir($sub)->absolute;
    die 'forbidden'.(Run::Env->dev ? ' '.$self->hostname_dir.' vs '.$subdir : ())
        unless $self->hostname_dir->subsumes($subdir);
    return $subdir;
}

sub content_dir {
    my $self = shift;
    $env->{content_dir} = shift
        if @_;

    $env->{content_dir} //= dir($self->hostname_dir,'content');
    return $env->{content_dir};
}

sub include_dir {
    my $self = shift;
    $env->{include_dir} = shift
        if @_;

    $env->{include_dir} //= dir($self->hostname_dir,'include');
    return $env->{include_dir};
}

sub www_dir {
    my $self = shift;
    $env->{www_dir} = shift
        if @_;

    $env->{www_dir} //= dir($self->hostname_dir,'www');
    return $env->{www_dir};
}

sub static_dir {
    my $self = shift;
    $env->{static_dir} = shift
        if @_;

    $env->{static_dir} //= $self->www_dir->subdir('static');
    return $env->{static_dir};
}

sub profiles_dir {
    my $self = shift;
    $env->{profiles_dir} //= dir($self->content_dir, 'members', 'profile');
    return $env->{profiles_dir};
}

sub xml_file {
    my $self = shift;
    if (@_) {
        $env->{xml_file} = shift;
        delete($env->{xml});
    }
    return $env->{xml_file} // confess('unset');
}

sub xml {
    my $self = shift;
    $env->{xml} = shift(@_) if @_;
    $env->{xml} //= XML::LibXML->load_xml(location => $self->xml_file);
    return $env->{xml};
}

sub stash {
    my $self = shift;
    if (@_) {
        $env->{stash} = shift @_;
        weaken($env->{stash});
    }

    return $env->{stash} // confess('unset');
}

sub user {
    my $self = shift;
    if (@_) {
        $env->{user} = shift @_;
        weaken($env->{user});
    }
    return $env->{user};
}

sub all_members {
    my $self = shift;

    my @members;
    my $profiles_dir = $self->profiles_dir;
    return unless -d $profiles_dir;
    foreach my $username_dir ($profiles_dir->children(no_hidden => 1)) {
        next unless $username_dir->is_dir;

        my $username = $username_dir->basename;
        my $member = meon::Web::Member->new(
            members_folder => $profiles_dir,
            username       => $username,
        );

        push(@members, $member)
            if (eval { $member->xml });
    }
    return @members;
}

sub hostname_config {
    my $self = shift;
    return meon::Web::Config->get->{$self->hostname_dir_name} // {};
}

sub raw_xml {
    my $self = shift;
    unless (defined($env->{raw_xml})) {
        $env->{raw_xml} = {
            map { $_ => 1 }
            values %{$self->hostname_config->{raw_xml} // {}}
        };
    }
    return $env->{raw_xml};
}

sub is_public_endpoint {
    my ($self, $source_file) = @_;
    return 0 unless $source_file;
    return 0 unless -e $source_file;
    my $relative = file($source_file)->absolute->resolve
        ->relative($self->content_dir->absolute->resolve)->stringify;
    return $relative =~ m{\A(?:login|logout|403|404|500)\.xml\z} ? 1 : 0;
}

sub page_requires_login {
    my ($self, $dom, $source_file) = @_;
    return 0 if $self->is_public_endpoint($source_file);
    my $xpc = meon::Web::Util->xpc;
    return 1 if $xpc->findnodes('/w:page/w:meta/w:members-only', $dom)->size;
    my $restricted_web = $self->hostname_config->{main}{restricted_web};
    if ($restricted_web) {
        return !$xpc->findnodes('/w:page/w:meta/w:public-access', $dom)->size;
    }
    return 0;
}

sub static_dir_mtime {
    my $self = shift;
    $env->{static_dir_mtime} = shift
        if @_;

    my (@static_files) = @{File::Find::Age->in($self->static_dir) // []};
    return $env->{static_dir_mtime} = (@static_files ? $static_files[-1]->{mtime} : -1);
}

sub session {
    my $self = shift;
    $env->{session} = shift
        if @_;

    return $env->{session};
}

sub apply_includes {
    my $self = shift;
    my $c    = shift;

    my $include_dir = $self->include_dir;
    my $dom         = $self->xml;
    my $xpc         = meon::Web::Util->xpc;

    # includes
    my $auto_include_dir = dir($include_dir)->subdir('auto');
    if (-d $auto_include_dir) {
        for my $auto_include_xml_file (sort $auto_include_dir->children) {
            my $include_el = $self->create_element('include');
            $include_el->setAttribute(path => $auto_include_xml_file->relative($include_dir));
            $dom->documentElement->appendChild($include_el);
            $dom->documentElement->appendChild(XML::LibXML::Text->new("\n"));
        }
    }
    my (@include_elements) =
        $xpc->findnodes('/w:page//w:include',$dom);
    foreach my $include_el (@include_elements) {
        my $include_path = $include_el->getAttribute('path');
        unless ($include_path) {
            $include_el->appendText('path attribute missing');
            next;
        }
        my $include_rel = dir(meon::Web::Util->path_fixup($include_path));
        my $file = file($include_dir, $include_rel)->absolute;
        unless (-f $file) {
            warn 'can not read include file: '.$file;
            next;
        }
        $file = $file->resolve;
        HTTP::Exception::403->throw(status_message => 'file: ' . $file)
            unless $include_dir->contains($file);
        my $include_xml = eval { XML::LibXML->load_xml(location => $file) };

        my (@include_filter_elements) =
            $xpc->findnodes('//w:apply-filter',$include_xml);
        foreach my $include_filter_el (@include_filter_elements) {
            my $filter_ident = $include_filter_el->getAttribute('ident');
            die 'no filter name specified'
                unless $filter_ident;
            my $filter_class = 'meon::Web::Filter::'.$filter_ident;
            load_class($filter_class);
            my $status = $filter_class->new(
                dom          => $include_xml,
                include_node => $include_el,
                user         => ($c ? $c->user : undef),
            )->apply;
            my $http_status = $status->{status} // 200;
            if ($http_status != 200) {
                my $err_msg = $status->{error} // '';
                if ($http_status == 404) {
                    HTTP::Exception::404->throw(status_message => $err_msg);
                }
                elsif ($http_status == 302) {
                    my $redirect = $status->{href} || die 'no href';
                    my $redirect_uri = $c->traverse_uri($redirect);
                    $redirect_uri = $redirect_uri->absolute
                        if $redirect_uri->can('absolute');
                    HTTP::Exception::302->throw(location => $redirect_uri);
                }
                else {
                    die $err_msg;
                }
            }
            $include_filter_el->parentNode->removeChild($include_filter_el);
        }

        if ($include_xml) {
            $include_el->replaceNode($include_xml->documentElement());
        }
        else {
            die 'failed to load include '.$@;
        }
    }

    return $self->xml;
}

sub create_element {
    my ($self, $name, $id) = @_;

    my $element = $self->xml->createElementNS('http://web.meon.eu/',$name);
    $element->setAttribute('id'=>$id)
        if defined $id;

    return $element;
}

sub template {
    my ($self, $template) = @_;

    $env->{template} = $template
        if $template;

    return $env->{template}
        if $env->{template};

    my ($template_node) = $self->xpc->findnodes('/w:page/w:meta/w:template');
    if ($template_node) {
        my $template_name = $template_node->textContent;
        my $template_file =
            file($self->hostname_dir, 'template', 'xsl', $template_name . '.xsl')->stringify;
        HTTP::Exception::404->throw(status_message => 'no such template ' . $template_name)
            unless -f $template_file;
        return $env->{template} = $template_file;
    }

    return $env->{template} =
        file($self->hostname_dir, 'template', 'xsl', 'default.xsl')->stringify;
}

sub transform_xml {
    my ($self) = @_;

    my $template = $self->template;
    my $xslt     = XML::LibXSLT->new();
    my $xslt_t   = $xslt->parse_stylesheet(XML::LibXML->load_xml(location => $template));

    return $xslt_t->transform($self->xml)
}

1;

__END__

=head1 ACCESS POLICY METHODS

=head2 raw_xml()

Lazily returns a lookup hash of raw XML request paths configured for the
current website. Configuration keys are ignored; each value in C<[raw_xml]>
becomes a lookup key. Clearing the request environment clears this lookup.

=head2 is_public_endpoint($source_file)

Returns whether the resolved source file is a root login, logout, or custom
403/404/500 XML page in the current site's content directory. The source file
identifies forwarded pages independently of the original request URL.
Root endpoint symlinks whose resolved targets are not exception files are not
exempt.

=head2 page_requires_login($dom, $source_file)

Returns whether an anonymous request requires authentication, using the current
site configuration and a parsed XML document. Public endpoints are exempt;
otherwise members-only presence wins over public-access presence. The
restricted_web value uses Perl truthiness. This method does not enforce roles,
parse files, or check containment; callers retain those responsibilities.

=cut
