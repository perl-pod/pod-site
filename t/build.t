#!/usr/bin/perl -w

use strict;
#use Test::More tests => 16;
use Test::More 'no_plan';
use File::Spec::Functions qw(tmpdir catdir catfile);
use File::Path qw(remove_tree);
use Test::File;
use Test::XPath;

my $CLASS;
BEGIN {
    $CLASS = 'Pod::Site';
    use_ok $CLASS or die;
}

my $mod_root = catdir qw(t dists);
my $tmpdir   = catdir tmpdir, "$$-pod-site-test";
my $doc_root = catdir $tmpdir, 'doc_root';
my $base_uri = '/docs/';

END { remove_tree if -d $tmpdir }

ok my $ps = Pod::Site->new({
    doc_root     => $doc_root,
    base_uri     => $base_uri,
    module_roots => $mod_root,
}), 'Create Pod::Site object';

file_not_exists_ok $doc_root, 'Doc root should not yet exist';
ok !$ps->distros, 'Should have no distro data';
ok $ps->build, 'Build the site';
file_exists_ok $doc_root, 'Doc root should now exist';
ok $ps->distros, 'Should have distro data';
is @{ $ps->distros }, 2, 'Should have found 2 distros';
is $ps->distros->[0]{name}, 'Foo-Bar', 'First distro should be Foo-Bar';
is $ps->distros->[0]{version}, '0.01', 'First distro version should be 0.01';
is $ps->distros->[1]{name}, 'Hello', 'Second distro should be Hello';
is $ps->distros->[1]{version}, '0.42', 'Second distro version should be 0.42';

ok my $tx = Test::XPath->new(
    file => catfile($doc_root, 'index.html'),
    is_html => 1
), 'Load index.html';

# Some basic sanity-checking.
$tx->is( 'count(/html)',      1, 'Should have 1 html element' );
$tx->is( 'count(/html/head)', 1, 'Should have 1 head element' );
$tx->is( 'count(/html/body)', 1, 'Should have 1 body element' );

# Check the head element.
$tx->is(
    '/html/head/meta[@http-equiv="Content-Type"]/@content',
    'text/html; charset=UTF-8',
    'Should have the content-type set in a meta header',
);
$tx->is(
    '/html/head/title',
    "API Browser",
    'Title should be corect'
);
$tx->is(
    '/html/head/meta[@name="base-uri"]/@content',
    $base_uri,
    'base-uri should be corect'
);
$tx->is(
    '/html/head/link[@type="text/css"][@rel="stylesheet"]/@href',
    'podsite.css',
    'Should load the CSS',
);
$tx->is(
    '/html/head/script[@type="text/javascript"]/@src',
    'podsite.js',
    'Should load the JS',
);

# Check the body element.
$tx->is( 'count(/html/body/div)', 2, 'Should have 2 top-level divs' );
$tx->ok( '/html/body/div[@id="nav"]', sub {
    $_->is('./h3', 'API Browser', 'Should have title header');
    $_->ok('./ul[@id="tree"]', sub {
        $_->ok('./li[@id="toc"]', sub {
            $_->is('./a[@href="toc.html"]', 'TOC', 'Should have TOC item');
        }, 'Should have toc li');
    }, 'Should have tree ul')
}, 'Should have nav div');
$tx->ok( '/html/body/div[@id="doc"]', 'Should have doc div');

#diag `cat $doc_root/index.html`;
