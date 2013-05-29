use strict;
use warnings;
use Module::Build::SysPath;

use 5.010;

my $builder = Module::Build::SysPath->new(
    module_name       => 'meon-Web',
    license           => 'perl',
    dist_author       => 'Jozef Kutej <jkutej@cpan.org>',
    dist_version_from => 'lib/meon/Web.pm',

    configure_requires => {
        'Module::Build::SysPath' => 0.13,
        'Module::Build'          => '0.3607',
    },
    build_requires => {
        'Module::Build::SysPath' => 0.13,
        'Test::Most'             => 0,
    },
    requires => {
        'perl'                             => '5.010',
        'Moose'                            => 0,
        'Catalyst::Runtime'                => '5.90007',
        'Catalyst::Plugin::ConfigLoader'   => 0,
        'Catalyst::Plugin::Static::Simple' => 0,
        'Catalyst::Plugin::Session::State::Cookie' => 0,
        'Catalyst::Plugin::Session::Store::File' => 0,
        'Catalyst::Plugin::Authentication' => 0,
        'Catalyst::Plugin::Authentication::Store::UserXML' => '0.02',
        'Catalyst::Action::RenderView'     => 0,
        'namespace::autoclean'             => 0,
        'Catalyst::View::XSLT'             => 0,
        'File::MimeInfo'                   => 0,
        'Email::MIME'                      => 0,
        'Email::Sender::Simple'            => 0,
        'List::MoreUtils'                  => 0,
        'Path::Class'                      => 0.04,    # mkpath()
        'HTML::FormHandler::Moose'         => 0,
        'Catalyst::Model::Factory::PerRequest' => 0,
        'URI::Escape'                      => 0,
        'IO::Any'                          => 0,
        'XML::LibXML'                      => '1.70',
        'Catalyst::Plugin::Unicode::Encoding' => 0,
        'Catalyst::Plugin::SmartURI'       => 0,
        'Config::INI::Reader'              => 0,
        'Data::Dumper'                     => 0,
        'JSON::XS'                         => 0,
        'Class::Load'                      => 0,
        'Text::Unidecode'                  => 0,
        'Data::UUID::LibUUID'              => 0,
        'DateTime::Format::Strptime'       => 0,
        'Email::Valid'                     => 0,
        'Email::Sender::Simple'            => 0,
        'Scalar::Util'                     => 0,
        'Digest::SHA'                      => 0,
        'Imager'                           => 0,
        'Data::asXML'                      => 0,
        'DateTime::Format::Strptime'       => 0,
        'MooseX::Types::Path::Class'       => 0,
        'DateTime::Format::HTTP'           => 0,
    },
    script_files => [qw(
        script/meon-web.psgi
    )],
    add_to_cleanup => [ 'meon-Web-*' ],
    create_readme  => 1,
);

$builder->create_build_script();