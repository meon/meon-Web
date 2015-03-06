package meon::Web::Form::CategoryProduct;

use meon::Web::Util;
use meon::Web::env;
use meon::Web::Data::CategoryProduct;
use Path::Class 'file';
use File::Copy 'copy';

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';
with 'meon::Web::Role::Form';

has '+name' => (default => 'form-category-product');
has '+widget_wrapper' => ( default => 'Bootstrap' );
has '+enctype' => ( default => 'multipart/form-data');
sub build_form_element_class { ['form-horizontal'] };

has_field 'action' => ( type => 'Hidden', required => 1, );
has_field 'ident'  => ( type => 'Text',   required => 0, );

has 'configured_field_list' => (is=>'ro',isa=>'ArrayRef',lazy_build=>1);

sub default_action {
    return meon::Web::env->session->{'form-category-product'}->{'values'}->{'action'} // 'none';
}
sub default_ident {
    return meon::Web::env->session->{'form-category-product'}->{'values'}->{'ident'} // '';
}

sub _build_configured_field_list {
    my $self = shift;

    my $xpc = meon::Web::Util->xpc;

    my $dom   = meon::Web::env->xml;
    my $ident = $self->default_ident;
    my %defaults;
    if ($ident) {
        my ($current_category_product) = $xpc->findnodes(
            '/w:page/w:category-products/w:category-product[@ident="'.$ident.'"]',
            $dom
        );
        if ($current_category_product) {
            my @nodes = $xpc->findnodes('w:*',$current_category_product);
            foreach my $node (@nodes) {
                my $name  = $node->localname;
                my @sub_nodes    = $xpc->findnodes('w:*',$node);
                my @sub_cp_nodes = $xpc->findnodes('w:category-product',$node);
                my ($xhtml_node) = $xpc->findnodes('xhtml:*',$node);
                my $value = (
                    @sub_nodes
                    ? join("\n", (map {
                        $_->localname eq 'category-product'
                        ? $_->getAttribute('ident')
                        : $_->toString
                    } @sub_nodes))
                    : $xhtml_node
                    ? $xhtml_node->toString
                    : $node->textContent()
                );
                $defaults{$name} = $value;
            }
            $defaults{href} = $current_category_product->getAttribute('href');
        }
        else { die $dom->toString };
    }

    my $form_config = $self->config;
    my @fields = map {
        my $name      = $_->getAttribute('name');
        my $type      = $_->getAttribute('type');
        my $label     = $_->getAttribute('label');
        my $multi     = $_->getAttribute('multiple');
        my $disabled  = $_->getAttribute('disabled');
        my $data_type = $_->getAttribute('data-type');
        my @options;

        if ($type eq 'Select') {
             @options = $xpc->findnodes('w:option',$_);
        }

        (
            $name => {
                type     => $type,
                value    => '',
                required => !!$_->getAttribute('required'),
                default  => $defaults{$name},
                (defined($label) ? (label => $label) : ()),
                (defined($multi) ? (multiple => $multi) : ()),
                (defined($disabled) ? (disabled => $disabled) : ()),
                (defined($data_type) ? (element_attr => { 'data-type' => $data_type }) : ()),
                (@options ? (
                    options => [
                        map {+{
                            label => $_->textContent,
                            value => $_->getAttribute('value'),
                        }} @options
                    ],
                ) : ()),
            }
        )
    } $xpc->findnodes('w:fields/w:field',$form_config);
    die 'no fields provided' unless @fields;

    return \@fields;
}

sub field_list {
    my $self = shift;
    return [
        @{$self->configured_field_list},
        submit => {
            type => 'Submit',
            value => 'Update',
            element_class => 'btn btn-primary',
        }
    ];
}

sub submitted {
    my $self = shift;

    my $redirect = $self->get_config_text('redirect');
    my $action = $self->field('action')->value // '';

    if ($action eq 'none') {
        delete meon::Web::env->session->{'form-category-product'};
        $self->redirect($redirect);
    }
    elsif ($action eq 'create') {
        meon::Web::env->session->{'form-category-product'}->{'values'}->{'action'} = 'create';
        $self->redirect($redirect);
    }

    my $ident = $self->field('ident')->value // '';
    $self->redirect($redirect)
        unless $ident;

    if ($action eq 'edit') {
        meon::Web::env->session->{'form-category-product'} //= {};
        meon::Web::env->session->{'form-category-product'}->{'values'}->{'action'} = 'save';
        meon::Web::env->session->{'form-category-product'}->{'values'}->{'ident'}  = $ident;
        $self->redirect($redirect);
    }
    elsif ($action eq 'save') {
        meon::Web::env->session->{'form-category-product'} //= {};
        meon::Web::env->session->{'form-category-product'}->{'values'}->{'action'} = 'edit';

        my @field_names;
        my @field_list = @{$self->configured_field_list};
        while (@field_list) {
            push(@field_names,shift(@field_list));
            shift(@field_list);
        }

        my $data_xml = meon::Web::Data::CategoryProduct->new(ident => $ident);
        foreach my $field_name (@field_names) {
            my $field = $self->field($field_name);
            next if $field->disabled;

            if ($field->type eq 'Upload') {
                my $src_field_name = $field_name;
                $src_field_name =~ s/-upload$//;
                my $upload = $field->value;
                next unless $upload;
                my $filename = join(
                    '-',
                    $ident,
                    $src_field_name,
                    file($upload->filename)->basename
                );
                my $upload_to = eval { $self->get_config_folder('upload-folder-'.$field->element_attr->{'data-type'}) };
                die 'can not find folder for '.$field->element_attr->{'data-type'}.(Run::Env->dev ? ' '.$@ : ())
                    unless $upload_to;
                die 'no such upload folder '.$upload_to
                    unless -d $upload_to;

                my $upload_file = $upload_to->file($filename);
                copy($upload->tempname, $upload_file) or die $!;
                my $href = $upload_file->basename;
                if (meon::Web::env->www_dir->contains($upload_file)) {
                    $href = substr($upload_file,length(meon::Web::env->www_dir));
                }
                if (meon::Web::env->content_dir->contains($upload_file)) {
                    $href = substr($upload_file,length(meon::Web::env->content_dir));
                }

                $data_xml->set_element($src_field_name, $href);
                my $src_field = $self->field($src_field_name);
                $src_field->disabled(1) if $src_field;
            }
            else {
                my $field_value = $field->value;
                $data_xml->set_element($field_name, $field_value);
            }
        }

        $data_xml->store;
        $self->redirect($redirect);
    }

    die 'unknown action '.$action;
}

before 'render' => sub {
    my ($self) = @_;

    my $action_fld = $self->field('action');
    my $action = $action_fld->value // '';
    $action_fld->value('save')
        if $action eq 'edit';
};

no HTML::FormHandler::Moose;

1;
