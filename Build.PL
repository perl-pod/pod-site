use strict;
use warnings;
use Module::Build;

my $build = Module::Build->new(
    module_name        => 'Pod::Site',
    license            => 'perl',
    configure_requires => {
        'Module::Build' => '0.35',
    },
    build_requires     => {
        'Module::Build'    => '0.35',
        'Test::File'       => 0,
        'Test::More'       => '0.88',
        'Test::MockModule' => '0.05',
        'Test::XPath'      => '0.12',
    },
    requires           => {
        'perl'              => 5.006002,
        'File::Basename'    => 0,
        'File::Copy'        => 0,
        'File::Path'        => 0,
        'File::Spec'        => 0,
        'Getopt::Long'      => 0,
        'HTML::Entities'    => 0,
        'Module::Build'     => '0.34',
        'Object::Tiny'      => 0,
        'Pod::Simple'       => '3.12',
        'Pod::Usage'        => 0,
    },
    recommends         => {
        'Test::Pod'      => '1.20',
    },
    meta_merge         => {
        resources => {
            homepage   => 'http://search.cpan.org/dist/Pod-Site/',
            bugtracker => 'http://github.com/theory/pod-site/issues/',
            repository => 'http://github.com/theory/pod-site/tree/',
        }
    },
);

$build->add_build_element('js');
$build->add_build_element('css');
$build->create_build_script;
