#!/usr/bin/perl -w

use strict;
use Test::More tests => 149;
#use Test::More 'no_plan';
use File::Spec::Functions qw(tmpdir catdir catfile);
use File::Path qw(remove_tree);
use Test::File;
use Test::XPath;
use utf8;

my $CLASS;
BEGIN {
    $CLASS = 'Pod::Site';
    use_ok $CLASS or die;
}

my $mod_root = catdir qw(t lib);
my $bin_dir  = catdir qw(t bin);
my $tmpdir   = catdir tmpdir, "$$-pod-site-test";
my $doc_root = catdir $tmpdir, 'doc_root';
my $base_uri = '/docs/';

END { remove_tree if -d $tmpdir }

ok my $ps = Pod::Site->new({
    doc_root     => $doc_root,
    base_uri     => $base_uri,
    module_roots => [$mod_root, $bin_dir],
    label        => 'API Browser',
}), 'Create Pod::Site object';

file_not_exists_ok $doc_root, 'Doc root should not yet exist';
ok $ps->build, 'Build the site';
file_exists_ok $doc_root, 'Doc root should now exist';
is_deeply $ps->module_tree, {
    'Heya' => {
        'Man' => {
            'What.pm' => catfile qw(t lib Heya Man What.pm)
        },
        'Man.pm' => catfile qw(t lib Heya Man.pm)
    },
    'Heya.pm' => catfile( qw(t lib Heya.pm)),
    'Foo' => {
        'Bar' => {
            'Baz.pm' => catfile(qw(t lib Foo Bar Baz.pm))
        },
        'Shizzle.pm' => catfile(qw(t lib Foo Shizzle.pm)),
        'Bar.pm' => catfile qw(t lib Foo Bar.pm)
    },
    'Hello.pm' => catfile qw(t lib Hello.pm)
}, 'Should have a module tree';

is_deeply $ps->bin_files, {
    'hello'   => 't/bin/hello',
    'heya.pl' => 't/bin/heya.pl',
    'bar'     => 't/bin/foo/bar',
}, 'Should have bin files';

is $ps->main_module,   'Foo::Bar::Baz', 'Should have a main module';
is $ps->sample_module, 'Foo::Bar::Baz', 'Should have a sample module';
is $ps->title,         'Foo::Bar::Baz', 'Should have default title';

##############################################################################
# Validate the index page.
ok my $tx = Test::XPath->new(
    file    => catfile($doc_root, 'index.html'),
    is_html => 1
), 'Load index.html';

# Some basic sanity-checking.
$tx->is( 'count(/html)',      1, 'Should have 1 html element' );
$tx->is( 'count(/html/head)', 1, 'Should have 1 head element' );
$tx->is( 'count(/html/body)', 1, 'Should have 1 body element' );
$tx->is( 'count(/html/*)', 2, 'Should have 2 elements in html' );
$tx->is( 'count(/html/head/*)', 6, 'Should have 6 elements in head' );

# Check the head element.
$tx->is(
    '/html/head/meta[@http-equiv="Content-Type"]/@content',
    'text/html; charset=UTF-8',
    'Should have the content-type set in a meta header',
);
$tx->is(
    '/html/head/title',
    $ps->main_title,
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
$tx->is(
    '/html/head/meta[@name="generator"]/@content',
    ref($ps) . ' ' . ref($ps)->VERSION,
    'The generator meta tag should be present and correct'
);

# Check the body element.
$tx->is( 'count(/html/body/div)', 2, 'Should have 2 top-level divs' );
$tx->ok( '/html/body/div[@id="nav"]', 'Should have nav div', sub {
    $_->is('./h3', $ps->nav_header, 'Should have title header');

    $_->ok('./ul[@id="tree"]', 'Should have tree ul', sub {
        $_->is('count(./li)', 5, 'Should have five nav list items');

        # Check TOC.
        $_->is('./li[1]/@id', 'toc', 'The first should be the TOC');
        $_->ok('./li[@id="toc"]', 'Should have toc li', sub {
            $_->is('./a[@href="toc.html"]', 'TOC', 'Should have TOC item');
        });

        # Check first nav link.
        $_->is('./li[2]/@id', 'Foo', 'Second li should be Foo');
        $_->is('count(./li[2]/*)', 1, 'It should have one subelement');
        $_->like('./li[2]', qr/Foo\n/, 'It should be labled "Foo"');
        $_->ok('./li[2]/ul', 'It should be an unordered list', sub {
            $_->is(
                'count(./*)', 2,
                'That unordered list should have two subelements'
            );
            $_->is(
                'count(./li)', 2, 'Both should be li elements'
            );
            $_->ok('./li[@id="Foo::Bar"]', 'The first should be the Foo::Bar item', sub {
                $_->is(
                    'count(./*)', 2, 'Which should have two subelements'
                );
                $_->is(
                    './a[@href="Foo/Bar.html"]', 'Bar', 'One should link to Bar'
                );
                $_->ok('./ul', 'The other should be an unordered list', sub {
                    $_->is(
                        'count(./*)', 1, 'It should have 1 subelement'
                    );
                    $_->ok(
                        './li[@id="Foo::Bar::Baz"]', 'Which should be an li', sub {
                            $_->is('count(./*)', 1, 'That li should have one sub');
                            $_->is(
                                './a[@href="Foo/Bar/Baz.html"]', 'Baz',
                                'Which should link to Baz'
                            );
                    });
                });
            });

            $_->ok(
                './li[@id="Foo::Shizzle"]',
                'The second should be the Foo::Shizzle item',
                sub {
                    $_->is(
                        'count(./*)', 1, 'It should have 1 subelement'
                    );
                    $_->is(
                        './a[@href="Foo/Shizzle.html"]', 'Shizzle',
                        'Which should link to Shizzle'
                    );
                },
            );
        });

        # Look at the second nav link.
        $_->is('./li[3]/@id', 'Hello', 'third li should be Hello');
        $_->is('count(./li[3]/*)', 1, 'It should have one subelement');
        $_->is(
            './li/a[@href="Hello.html"]', 'Hello',
            'Which should be a link to Hello'
        );

        # And the fourth nav link.
        $_->is('./li[4]/@id', 'Heya', 'Fourth li should be Heya');
        $_->ok('./li[4]', 'Look at those subelements', sub {
            $_->is('count(./*)', 2, 'It should have two subelements');
            $_->is('./a[@href="Heya.html"]', 'Heya', 'First should link to Heya');
            $_->ok('./ul', 'Second should be a ul', sub {
                $_->is('count(./*)', 1, 'It should have one subelement');
                $_->ok('./li[@id="Heya::Man"]', 'It should be the Heya::Man li', sub {
                    $_->is('count(./*)', 2, 'It should have two subelements');
                    $_->is(
                        './a[@href="Heya/Man.html"]', 'Man',
                        'One should link to Heya::Man'
                    );
                    $_->ok('./ul', 'Second should be a ul', sub {
                        $_->is('count(./*)', 1, 'It should have one subelement');
                        $_->ok(
                            './li[@id="Heya::Man::What"]',
                            'It should be the Heya::Man::What li', sub {
                                $_->is(
                                    './a[@href="Heya/Man/What.html"]', 'What',
                                    'It should link to Heya::Man::What'
                                );
                            }
                        );
                    });
                });
            });
        });

        # And finally the fifth nav link.
        $_->is('./li[5]/@id', 'bin', 'Fifth li should be bin');
        $_->ok('./li[5]', 'Look at its elements', sub {
            $_->is('count(./*)', 1, 'It should have one');
            $_->ok('./ul', 'It should be a ul', sub {
                $_->is('count(./*)', 3, 'Which should have 3 children');
                $_->is('count(./li)', 3, 'All three should be li');

                $_->is('./li[1]/@id', 'bar', 'The first one should be bar');
                $_->is('count(./li[1]/*)', 1, 'Which should have 1 child');
                $_->is('./li[1]/a[@href="bar.html"]', 'bar', 'Which should link to bar');

                $_->is('./li[2]/@id', 'hello', 'The second one should be hello');
                $_->is('count(./li[2]/*)', 1, 'Which should have 1 child');
                $_->is('./li[2]/a[@href="hello.html"]', 'hello', 'Which should link to hello');

                $_->is('./li[3]/@id', 'heya.pl', 'The third one should be heya.pl');
                $_->is('count(./li[3]/*)', 1, 'Which should have 1 child');
                $_->is('./li[3]/a[@href="heya.pl.html"]', 'heya.pl', 'Which should link to heya.pl');
            });
        });
    });
});

# Validate doc div.
$tx->ok('/html/body/div[@id="doc"]', 'Should have doc div', sub {
    $_->is('.', '', 'Which should be empty');
    $_->is('count(./*)', 0, 'And should have no subelements');
});
$tx->is('/html/body/div[last()]/@id', 'doc', 'Which should be last');

diag `cat $doc_root/index.html`;

##############################################################################
# Validate the TOC.
ok $tx = Test::XPath->new(
    file => catfile($doc_root, 'toc.html'),
    is_html => 1
), 'Load toc.html';

# Some basic sanity-checking.
$tx->is( 'count(/html)',      1, 'Should have 1 html element' );
$tx->is( 'count(/html/head)', 1, 'Should have 1 head element' );
$tx->is( 'count(/html/body)', 1, 'Should have 1 body element' );
$tx->is( 'count(/html/*)', 2, 'Should have 2 elements in html' );

# Check the head element.
$tx->is( 'count(/html/head/*)', 3, 'Should have 3 elements in head' );
$tx->is(
    '/html/head/meta[@http-equiv="Content-Type"]/@content',
    'text/html; charset=UTF-8',
    'Should have the content-type set in a meta header',
);

$tx->is( '/html/head/title', $ps->main_title, 'Title should be corect');

$tx->is(
    '/html/head/meta[@name="generator"]/@content',
    ref($ps) . ' ' . ref($ps)->VERSION,
    'The generator meta tag should be present and correct'
);

# Check the body.
$tx->is( 'count(/html/body/*)', 7, 'Should have 7 elements in body' );

# Headers.
$tx->is( 'count(/html/body/h1)', 2, 'Should have 2 h1 elements in body' );

$tx->is( '/html/body/h1[1]', $ps->main_title, 'Should have title in first h1 header');
$tx->is(
    '/html/body/h1[2]', 'Instructions',
    'Should have "Instructions" in second h1 header'
);

$tx->is( 'count(/html/body/h3)', 1, 'Should have 1 h3 element in body' );
$tx->is( '/html/body/h3', 'Classes & Modules', 'h3 should be correct');

# Paragraphs.
$tx->is( 'count(/html/body/p)', 2, 'Should have 2 p elements in body' );
$tx->like(
    '/html/body/p[1]', qr/^Select class names/,
    'First paragraph should look right'
);

$tx->is(
    '/html/body/p[2]', 'Happy Hacking!', 'Second paragraph should be right'
);

# Example list.
$tx->is( 'count(/html/body/ul)', 2, 'Should have 2 ul elements in body' );
$tx->ok('/html/body/ul[1]', sub {
    $_->is('count(./li)', 2, 'Should have two list items');
    $_->is('count(./li/a)', 2, 'Both should have anchors');
    $_->is(
        './li/a[@href="./?Foo::Bar::Baz"]', '/?Foo::Bar::Baz',
        'First link should be correct'
    );
    $_->is(
        './li/a[@href="./Foo::Bar::Baz"]', '/Foo::Bar::Baz',
        'Second link should be correct'
    );
}, 'Should have first unordered list');

# Class list.
$tx->ok('/html/body/ul[2]', 'Should have second unordered list', sub {
    $_->is('count(./*)',  10, 'It should have seven subelements');
    $_->is('count(./li)', 10, 'All of which should be li');

    my $i = 0;
    for my $link(
        [ 'Foo::Bar',        'Get the Foo out of the Bar!'     ],
        [ 'Foo::Bar::Baz',   'Bazzle your Bar, Foo!'           ],
        [ 'Foo::Shizzle',    'Get the Foo out of the Shizzle!' ],
        [ 'Hello',           'Hello World!'                    ],
        [ 'Heya',            "How *you* doin'?"                ],
        [ 'Heya::Man',       'Hey man, wassup?'                ],
        [ 'Heya::Man::What', 'Hey man, wassup, yo?'            ],
        [ 'bar',             'This is the bar, foo'            ],
        [ 'hello',           'Welcome my friend'               ],
        [ 'heya.pl',         'Heya yourself'                   ],
    ) {
        ++$i;
        $_->ok("./li[$i]", "Check li #$i", sub {
            $_->is('count(./*)', 1, 'It should have one subelement');
            $_->is(
                '.', "$link->[0]—$link->[1]",
                q{It should have $link->[0]'s name and abstract}
            );
            (my $url = $link->[0]) =~ s{::}{/}g;
            $_->is(
                "./a[\@href='$url.html'][\@rel='section'][\@name='$link->[0]']",
                $link->[0], "Which should link to $link->[0]",
            );
        });
    }
});
