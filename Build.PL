use strict;
use warnings;
use Module::Build;

my $build = Module::Build->new(
    module_name        => 'Pod::Site',
    license            => 'perl',
    configure_requires => {
        'Module::Build' => '0.34',
    },
    build_requires     => {
        'Module::Build' => '0.34',
        'Test::More'    => '0.17',
    },
    requires           => {
        'perl'              => 5.006_002,
        'File::Basename'    => 0,
        'File::Copy'        => 0,
        'File::Find::Rule'  => 0,
        'File::Path'        => 0,
        'File::Slurp::Tree' => 0,
        'File::Spec'        => 0,
        'Getopt::Long'      => 0,
        'Module::Build'     => '0.34',
        'Pod::Simple'       => '3.08',
        'Pod::Usage'        => 0,
    },
    recommends         => {
        'Test::Pod'      => '1.20',
    },
    meta_merge         => {
        resources => {
            homepage    => 'http://search.cpan.org/dist/Pod-Site/',
            bugtracker  => 'http://github.com/theory/pod-site/issues/',
#           MailingList => 'mailto:module-build@perl.org',
            repository  => 'http://github.com/theory/pod-site/tree/',
        }
    },
);

$build->add_build_element('js');
$build->add_build_element('css');
$build->create_build_script;
