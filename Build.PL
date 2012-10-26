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
        'Catalyst::Plugin::Authentication::Store::UserXML' => 0,
        'Catalyst::Action::RenderView'     => 0,
        'namespace::autoclean'             => 0,
        'Catalyst::View::XSLT'             => 0,
        'File::MimeInfo'                   => 0,
        'Email::MIME'                      => 0,
        'Email::Sender::Simple'            => 0,
        'List::MoreUtils'                  => 0,
        'Path::Class'                      => 0,
        'HTML::FormHandler::Moose'         => 0,
        'Catalyst::Model::Factory::PerRequest' => 0,
        'URI::Escape'                      => 0,
        'IO::Any'                          => 0,
        'XML::LibXML'                      => '1.70',
    },
    script_files => [qw(
        script/meon-web.psgi
    )],
    add_to_cleanup => [ 'meon-Web-*' ],
    create_readme  => 1,
);

$builder->create_build_script();
