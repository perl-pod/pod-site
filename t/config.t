#!/usr/bin/perl -w

use strict;
use Test::More tests => 23;
#use Test::More 'no_plan';
use File::Spec::Functions qw(tmpdir catdir);
use File::Path qw(remove_tree);
use Test::MockModule;

my $CLASS;
BEGIN {
    $CLASS = 'Pod::Site';
    use_ok $CLASS or die;
}

my $mod_root = catdir qw(t lib);
my $tmpdir   = catdir tmpdir, "$$-pod-site-test";
my $doc_root = catdir $tmpdir, 'doc_root';
my $base_uri = '/docs/';

END { remove_tree if -d $tmpdir }

my %config = (
    doc_root      => $doc_root,
    base_uri      => [$base_uri],
    module_roots  => [$mod_root],
    verbose       => 0,
    version       => undef,
    css_path      => '',
    js_path       => '',
    index_file    => 'index.html',
    sample_module => undef,
    version_in    => undef,
    man           => undef,
    help          => undef,
    module_name   => undef,
);

DEFAULTS: {
    local @ARGV = ('--doc-root', $doc_root, '--base-uri', $base_uri, $mod_root );
    is_deeply $CLASS->_config, \%config, 'Should have default config';
}

ERRS: {
    my $mock = Test::MockModule->new($CLASS);
    my @args;
    $mock->mock(pod2usage => sub { @args = @_} );
    local @ARGV = ($mod_root);
    ok $CLASS->_config, 'configure with no options';
    is_deeply \@args, [
        $CLASS,
        '-message', 'Missing required --doc-root and --base-uri options',
    ], 'Should have been helped';

    @ARGV = ('--doc-root', $doc_root, $mod_root);
    ok $CLASS->_config, 'configure with no --base_uri';
    is_deeply \@args, [
        $CLASS,
        '-message', 'Missing required --base-uri option',
    ], 'Should have been helped again';

    @ARGV = ('--base-uri', $base_uri, $mod_root);
    ok $CLASS->_config, 'configure with no --base_uri';
    is_deeply \@args, [
        $CLASS,
        '-message', 'Missing required --doc-root option',
    ], 'Should have been helped again';

    @ARGV = ('--doc-root', $doc_root, '--base-uri', $base_uri);
    ok $CLASS->_config, 'configure with no module root';
    is_deeply \@args, [
        $CLASS,
        '-message', 'Missing path to module root',
    ], 'Should have been helped again';
}

MULTIPLES: {
    local @ARGV = (
        '--doc-root' => $doc_root,
        '--base-uri' => $base_uri,
        '--base-uri' => '/whatever',
        $mod_root, '/another/root'
    );
    local $config{base_uri} = [ $base_uri, '/whatever/' ];
    local $config{module_roots} = [ $mod_root, '/another/root' ];
    is_deeply $CLASS->_config, \%config, 'Allow multiple --base-uri';
}

HELP: {
    my $mock = Test::MockModule->new($CLASS);
    my @args;
    $mock->mock(pod2usage => sub { @args = @_} );
    local @ARGV = ('--doc-root', $doc_root, '--base-uri', $base_uri, $mod_root, '--help' );
    ok $CLASS->_config, 'Ask for help';
    is_deeply \@args, [ $CLASS, '-exitval', 0 ], 'Should have been helped';
    @ARGV = ('--doc-root', $doc_root, '--base-uri', $base_uri, $mod_root, '-h' );
    ok $CLASS->_config, 'Ask for help short';
    is_deeply \@args, [ $CLASS, '-exitval', 0 ], 'Should have been helped again';

    @ARGV = ('--doc-root', $doc_root, '--base-uri', $base_uri, $mod_root, '--man' );
    ok $CLASS->_config, 'Ask for man';
    is_deeply \@args, [ $CLASS, '-sections', '.+', '-exitval', 0 ],
        'Should have been manned';
    @ARGV = ('--doc-root', $doc_root, '--base-uri', $base_uri, $mod_root, '-m' );
    ok $CLASS->_config, 'Ask for man short';
    is_deeply \@args, [ $CLASS, '-sections', '.+', '-exitval', 0 ],
        'Should have been manned again';
}

LOTS: {
    local @ARGV = (
        '--doc-root'      => $doc_root,
        '--base-uri'      => $base_uri,
        '--module-name'   => 'Hello',
        '--version-in'    => 'lib/Hi.pm',
        '--sample-module' => 'lib/Hello.pm',
        '--index-file'    => 'default.htm',
        '--css-path'      => '/some/file.css',
        '--js-path'       => '/some/file.js',
        '--verbose', '--verbose', '--verbose',
        $mod_root,
    );

    is_deeply $CLASS->_config, {
        doc_root      => $doc_root,
        base_uri      => [$base_uri],
        module_roots  => [$mod_root],
        verbose       => 3,
        version       => undef,
        css_path      => '/some/file.css',
        js_path       => '/some/file.js',
        index_file    => 'default.htm',
        sample_module => 'lib/Hello.pm',
        version_in    => 'lib/Hi.pm',
        man           => undef,
        help          => undef,
        module_name   => 'Hello',
    }, 'Lots of opts should work';

}

SHORT: {
    local @ARGV = (
        '-d' => $doc_root,
        '-b' => $base_uri,
        '-n' => 'Hello',
        '-i' => 'lib/Hi.pm',
        '-e' => 'lib/Hello.pm',
        '-f' => 'default.htm',
        '-c' => '/some/file.css',
        '-j' => '/some/file.js',
        '-VVV',
        $mod_root,
    );

    is_deeply $CLASS->_config, {
        doc_root      => $doc_root,
        base_uri      => [$base_uri],
        module_roots  => [$mod_root],
        verbose       => 3,
        version       => undef,
        css_path      => '/some/file.css',
        js_path       => '/some/file.js',
        index_file    => 'default.htm',
        sample_module => 'lib/Hello.pm',
        version_in    => 'lib/Hi.pm',
        man           => undef,
        help          => undef,
        module_name   => 'Hello',
    }, 'Lots of short opts should work';

}

POD2USAGE: {
    my $mock = Test::MockModule->new('Pod::Usage');
    my @args;
    $mock->mock(pod2usage => sub { @args = @_} );
    ok $CLASS->pod2usage('hello'), 'Run pod2usage';
    is_deeply \@args, [
        '-verbose'  => 99,
        '-sections' => '(?i:(Usage|Options))',
        '-exitval'  => 1,
        '-input'    => $INC{'Pod/Site.pm'},
        'hello'
    ], 'Proper args should have been passed to Pod::Usage';
}
