use strict;
use warnings;
use Module::Build;

Module::Build->new(
    module_name        => 'Pod::Site',
    license            => 'perl',
    create_makefile_pl => 'passthrough',
    create_readme      => 1,
    configure_requires => {
        'Module::Build' => '0.2701',
    },
    build_requires     => {
        'Module::Build' => '0.2701',
        'Test::More'    => '0.17',
    },
    requires           => {
        'perl'              => 5.006_002,
        'Getopt::Long'      => 0,
        'Pod::Usage'        => 0,
        'File::Slurp::Tree' => 0,
        'Pod::Simple'       => '3.06',
        'File::Find::Rule'  => 0,
        'File::Spec'        => 0,
        'File::Basename'    => 0,
        'File::Path'        => 0,
        'Module::Build'     => '0.2701',
    },
    recommends         => {
        'Test::Pod'      => '1.20',
    },

)->create_build_script;
