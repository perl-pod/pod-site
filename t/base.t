#!/usr/bin/perl -w

use strict;
use Test::More tests => 22;
#use Test::More 'no_plan';
use File::Spec::Functions qw(tmpdir catdir);
use File::Path qw(remove_tree);

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

can_ok $CLASS, qw(
    doc_root
    base_uri
    module_roots
    index_file
    css_path
    js_path
    verbose
    title

    run
    new
    build
    start_nav
    start_toc
    output
    output_bin
    finish_nav
    finish_toc
    batch_html
    get_desc
    module_tree
    main_module
    sample_module
    pod2usage
);

isa_ok 'Pod::Site::Search', 'Pod::Simple::Search';
can_ok 'Pod::Site::Search', qw(
    instance
    new
);

isa_ok 'Pod::Site::XHTML', 'Pod::Simple::XHTML';
can_ok 'Pod::Site::XHTML', qw(
    new
    start_L
    html_header
    batch_mode_page_object_init
);

eval { $CLASS->new };
ok my $err = $@, 'Should catch exception';
like $err, qr{Missing required parameters doc_root, base_uri, and module_roots},
    'Should have the proper error message';

isa_ok my $ps = $CLASS->new({
    doc_root     => $doc_root,
    base_uri     => $base_uri,
    module_roots => $mod_root,
}), $CLASS, 'new object';

is $ps->index_file, 'index.html', 'Should have defautl index file';
is $ps->verbose, 0, 'Should have default verbosity';
is $ps->js_path, '', 'Should have default js_path';
is $ps->css_path, '', 'Should have default css_path';

is_deeply $ps->module_roots, [$mod_root],
    'module_roots should be converted to an array';
is_deeply $ps->base_uri, [$base_uri],
    'base_uri should be converted to an array';

isa_ok $ps = $CLASS->new({
    doc_root     => $doc_root,
    base_uri     => $base_uri,
    module_roots => [$mod_root],
    base_uri     => [$base_uri],
}), $CLASS, 'another object';

is_deeply $ps->module_roots, [$mod_root],
    'module_roots array should be retained';
is_deeply $ps->base_uri, [$base_uri],
    'base_uri array should be retained';

my $path = "$$-" . __FILE__ . time;
eval { $CLASS->new({
    doc_root     => $doc_root,
    base_uri     => $base_uri,
    module_roots => $path,
}) };

ok $err = $@, 'Should catch exception';
like $err, qr{The module root \E$path\Q does not exist},
    'Should be non exist error';

$path = 'Build.PL';
eval { $CLASS->new({
    doc_root     => $doc_root,
    base_uri     => $base_uri,
    module_roots => $path,
}) };

ok $err = $@, 'Should catch another exception';
like $err, qr{The module root \E$path\Q is not a directory},
    'Should be not directory error';
