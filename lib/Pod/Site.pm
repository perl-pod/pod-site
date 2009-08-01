package Pod::Site;

use strict;
use warnings;
use File::Spec;
use Pod::Simple '3.08';
use vars '$VERSION';
$VERSION = '0.50';

sub run {
    my $class = shift;
    $class->new( $class->_config )->build;
}

sub new {
    my ( $class, $params ) = @_;
    bless { %{ $params } } => $class;
}

sub build {
    my $self = shift;
    require File::Path;
    File::Path::mkpath($self->{doc_root}, 0, 0755);

    # The index file is the home page.
    my $idx_file = File::Spec->catfile( @{ $self }{qw(doc_root index_file)} );
    open my $idx_fh, '>', $idx_file or die qq{Cannot open "$idx_file": $!\n};

    # The TOC file has the table of contents for all modules and programs in
    # the distribution.
    my $toc_file = File::Spec->catfile( $self->{doc_root}, 'toc.html' );
    open my $toc_fh, '>', $toc_file or die qq{Cannot open "$toc_file": $!\n};

    # Set things up.
    $self->{toc_fh} = $toc_fh;
    $self->{seen} = {};
    $self->{indent} = 1;
    $self->{base_space} = '    ';
    $self->{spacer} = '  ';
    $self->{uri} = '';

    # Make it so!
    $self->_find_version;
    $self->start_browser($idx_fh);
    $self->start_toc($toc_fh);
    $self->output($idx_fh);
    $self->output_bin($idx_fh);
    $self->end_browser($idx_fh);
    $self->end_toc($toc_fh);
    $self->copy_etc();

    # Close up shop.
    close $idx_fh or die qq{Could not close "$idx_file": $!\n};
    close $toc_fh or die qq{Could not close "$toc_file": $!\n};

    $self->batch_html( @{ $self }{qw(doc_root lib bin)} );
}

sub start_browser {
    my ($self, $fh) = @_;
    my $version = Pod::Site->VERSION;
    print "Starting site navigation file\n" if $self->{verbose} > 1;
    my $base = join "\n        ", map { qq{<meta name="base-uri" content="$_" />} } @{ $self->{base_uri} };
    print $fh _udent( <<"    EOF" );
    <!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.1//EN"
    "http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd">
    <html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en">
      <head>
        <meta http-equiv="Content-Type" content="text/html; charset=UTF-8" />
        <title>$self->{module_name} $self->{version} API Browser</title>
        <link rel="stylesheet" type="text/css" href="$self->{css_path}podsite.css" />
        $base
        <script type="text/javascript" src="$self->{js_path}podsite.js"></script>
        <meta name="generator" content="Pod::Site $version" />
      </head>
      <body>
        <div id="nav">
          <h3>$self->{module_name} $self->{version}</h3>
          <ul id="tree">
            <li id="toc"><a href="toc.html">TOC</a></li>
    EOF
}

sub start_toc {
    my ($self, $fh) = @_;

    my $module_as_path = join '/', split /::/, $self->{sample_module};
    my $version = Pod::Site->VERSION;

    print "Starting browser TOC file\n" if $self->{verbose} > 1;
    print $fh _udent( <<"    EOF");
    <!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.1//EN"
    "http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd">
    <html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en">
      <head>
        <meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
        <title>$self->{module_name} $self->{version} API Browser</title>
        <meta name="generator" content="Pod::Site $version" />
      </head>

      <body>
        <h1>$self->{module_name} $self->{version} API Browser</h1>
        <h1>Instructions</h1>

        <p>Select class names from the navigation tree to the left. The tree
           is hierarchical and will show all of the classes in $self->{module_name}. The
           triangles indicate those that have subclasses, while the diamond icon
           represents classes without subclasses.</p>

        <p>You can access the API browser at any time at this URL. But you can
           also link to a particular $self->{module_name} class, and the browser will
           load that class, with the navigation open to and highlighting the
           class. You can use a few different ways of linking to a specific
           class. For example, if you wanted to access $self->{sample_module},
           any of these links will work:</p>

        <ul>
          <li><a href="./?$self->{sample_module}">/?$self->{sample_module}</a></li>
          <li><a href="./$self->{sample_module}">/$self->{sample_module}</a></li>
        </ul>

        <p>Happy Hacking!</p>

        <h3>Classes &amp; Modules</h3>
        <ul>
    EOF
}

sub output {
    my ($self, $fh, $tree) = @_;
    $tree ||= $self->_create_tree;
    for my $key (sort keys %$tree) {
        my $contents = $tree->{$key};
        (my $fn = $key) =~ s/\.[^.]+$//;
        my $class = join ('::', split('/', $self->{uri}), $fn);
        print "Reading $class\n" if $self->{verbose} > 1;
        if (ref $contents) {
            # It's a directory tree. Output a class for it, first, if there
            # is one.
            my $item = $key;
            if ($tree->{"$key.pm"}) {
                my $code = \$tree->{"$key.pm"};
                if (my $desc = $self->get_desc($class, $code, $self)) {
                    $item = qq{<a href="$self->{uri}$key.html">$key</a>};
                    $self->_output_class($fh, $fn, $code, $class, 1, $desc);
                }
                $self->{seen}{$class} = 1;
            }

            # Now recursively descend the tree.
            print "Outputting nav link\n" if $self->{verbose} > 2;
            print $fh $self->{base_space}, $self->{spacer} x $self->{indent},
              qq{<li id="$class">$item\n}, $self->{base_space}, $self->{spacer} x ++$self->{indent}, "<ul>\n";
            ++$self->{indent};
            $self->{uri} .= "$key/";
            $self->output($fh, $contents);
            print $fh $self->{base_space}, $self->{spacer} x --$self->{indent}, "</ul>\n",
              $self->{base_space}, $self->{spacer} x --$self->{indent}, "</li>\n";
            $self->{uri} =~ s|$key/$||;
        } else {
            # It's a class. Create a link to it.
            $self->_output_class($fh, $fn, \$contents, $class) unless $self->{seen}{$class};
        }
    }
}

sub output_bin {
    my ($self, $fh) = @_;
    return unless -d $self->{bin};

    # Start the list in the tree browser.
    print $fh $self->{base_space}, $self->{spacer} x $self->{indent},
      qq{<li id="bin">bin\n}, $self->{base_space}, $self->{spacer} x ++$self->{indent}, "<ul>\n";

    my $rule = File::Find::Rule->file->executable;
    my $tree = File::Slurp::Tree::slurp_tree($self->{bin}, rule => $rule);

    for my $pl (sort keys %$tree) {
        # Skip directories.
        next if ref $tree->{$pl};
        print "Reading $pl\n" if $self->{verbose} > 1;
        # Get the description.
        my $desc = $self->get_desc($pl, \$tree->{$pl}, $pl) or next;

        # Output the Tree Browser Link.
        print "Outputting $pl nav link\n" if $self->{verbose} > 2;
        print $fh $self->{base_space}, $self->{spacer} x $self->{indent},
          qq{<li id="$pl"><a href="$pl.html">$pl</a></li>\n};

        # Output the TOC link.
        print "Outputting toc link\n" if $self->{verbose} > 2;
        print {$self->{toc_fh}} $self->{base_space},
          qq{  <li><a href="$pl.html" rel="section" name="$pl">$pl</a>&#x2014;$desc</li>\n};
    }

    print $fh $self->{base_space}, $self->{spacer} x --$self->{indent}, "</ul>\n",
      $self->{base_space}, $self->{spacer} x --$self->{indent}, "</li>\n";
}

sub end_browser {
    my ($self, $fh) = @_;
    print "Finishing browser navigation file\n" if $self->{verbose} > 1;
    print $fh _udent( <<"    EOF" );
          </ul>
        </div>
        <div id="doc"></div>
      </body>
    </html>
    EOF
}

sub end_toc {
    my ($self, $fh) = @_;
    print "Finishing browser TOC file\n" if $self->{verbose} > 1;
    print $fh _udent( <<"    EOF" );
        </ul>
      </body>
    </html>
    EOF
}

sub batch_html {
    my $self = shift;
    require Pod::Simple::HTMLBatch;
    print "Creating HTML with Pod::Simple::XHTML\n" if $self->{verbose} > 1;
    # XXX Send a patch to get this turned into an accessor like render_class().
    $Pod::Simple::HTMLBatch::SEARCH_CLASS = 'Pod::Site::Search';
    # XXX I'd rather have a way to get this passed to the P::S::XHTML object.
    local $Pod::Site::_instance = $self;
    my $batchconv = Pod::Simple::HTMLBatch->new;
    $batchconv->index(1);
    $batchconv->verbose($self->{verbose});
    $batchconv->contents_file( undef );
    $batchconv->css_flurry(0);
    $batchconv->javascript_flurry(0);
    $batchconv->html_render_class('Pod::Site::XHTML');
    $batchconv->batch_convert( \@_, $self->{doc_root} );
}

sub copy_etc {
    my $self = shift;
    require File::Copy;
    (my $from = __FILE__) =~ s/[.]pm$//;
    for my $ext qw(css js) {
        File::Copy::copy(
            File::Spec->catfile( $from, "podsite.$ext" ),
            $self->{doc_root}
        );
    }
}

sub _udent {
    my $string = shift;
    $string =~ s/^[ ]{4}//gm;
    return $string;
}

sub _output_class {
    my ($self, $fh, $key, $contents, $class, $no_link, $desc) = @_;

    $desc ||= $self->get_desc($class, $contents, $class) or return;

    # Output the Tree Browser Link.
    print "Outputting $class nav link\n" if $self->{verbose} > 2;
    print $fh $self->{base_space}, $self->{spacer} x $self->{indent},
      qq{<li id="$class"><a href="$self->{uri}$key.html">$key</a></li>\n}
      unless $no_link;

    # Output the TOC link.
    print "Outputting $class TOC link\n" if $self->{verbose} > 2;
    print {$self->{toc_fh}} $self->{base_space}, $self->{spacer},
      qq{<li><a href="$self->{uri}$key.html" rel="section" name="$class">$class</a>—$desc</li>\n};
    return 1;
}

sub get_desc {
    my ($self, $what, $contents) = @_;
    my ($desc) = $$contents =~ /=head1 NAME\n\n$what\s+-\s+([^\n]+)\n/i;
    print "$what has no POD or no description in a =head1 NAME section\n"
      if $self->{verbose} && !$desc;
    return $desc;
}

sub _create_tree {
    my $self = shift;
    # We're gonna use these.
    require File::Find::Rule;
    require File::Slurp::Tree;

    my $rule = File::Find::Rule->file->name(
        qr/\.pm$/, qr/\.pod$/
    )->not_name( qr/blib/ );

    return File::Slurp::Tree::slurp_tree($self->{lib}, rule => $rule);
}

sub _find_version {
    my $self = shift;
    my $mod = $self->{version_in} || $self->{module_name};
    require Module::Build::ModuleInfo;
    my $info = $mod =~ m{/}
        ? Module::Build::ModuleInfo->new_from_file( $mod )
        : Module::Build::ModuleInfo->new_from_module(
            $mod, inc => [ @{ $self }{qw(lib bin)} ]
        );

    # If we can't find this, nothing will work.
    die "Could not find $mod\n" unless $info;

    $self->{version} = $info->version || '0';
    print "No version information found\n" if !$self->{version} && $self->{verbose};
    return $self->{version};
}

sub _config {
    my $self = shift;
    require Getopt::Long;
    Getopt::Long::Configure( qw(bundling) );

    my %opts = (
        verbose    => 0,
        css_path   => '',
        js_path    => '',
        index_file => 'index.html',
        base_uri   => undef,
    );

    Getopt::Long::GetOptions(
        'module-root|a=s'   => \$opts{module_root},
        'module-name|n=s'   => \$opts{module_name},
        'doc-root|d=s'      => \$opts{doc_root},
        'base-uri|b=s@'     => \$opts{base_uri},
        'version-in|i=s'    => \$opts{version_in},
        'sample-module|e=s' => \$opts{sample_module},
        'index-file|f=s'    => \$opts{index_file},
        'css-path|c=s'      => \$opts{css_path},
        'js-path|k=s'       => \$opts{js_path},
        'verbose|V+'        => \$opts{verbose},
        'help|h'            => \$opts{help},
        'man|m'             => \$opts{man},
        'version|v'         => \$opts{version},
    ) or $self->_pod2usage;

    # Handle documentation requests.
    $self->pod2usage(
        ( $opts{man} ? ( '-sections' => '.+' ) : ()),
        '-exitval' => 0,
    ) if $opts{help} or $opts{man};

    # Handle version request.
    if ($opts{version}) {
        require File::Basename;
        print File::Basename::basename($0), ' (', __PACKAGE__, ') ',
            __PACKAGE__->VERSION, $/;
        exit;
    }

    # Check required options.
    for my $key qw(module_root module_name doc_root base_uri) {
        next if $opts{$key};
        ( my $opt = $key ) =~ s/_/-/g;
        $self->pod2usage( '-message' => "Missing required --$opt option" );
    }

    # Make sure we can find stuff to convert.
    $opts{bin} = File::Spec->catdir( $opts{module_root}, 'bin' );
    $opts{lib} = File::Spec->catdir( $opts{module_root}, 'lib' );
    $self->pod2usage(
        '-message' => "$opts{module_root} has no 'lib' or 'bin' subdirectory"
    ) unless -d $opts{module_root} && (-d $opts{lib} || -d $opts{bin});

    # Modify options and set defaults as appropriate.
    for (@{ $opts{base_uri} }) { $_ .= '/' unless m{/$}; }
    $opts{sample_module} ||= $opts{module_name};

    return \%opts;
}

sub pod2usage {
    shift;
    require Pod::Usage;
    Pod::Usage::pod2usage(
        '-verbose'  => 99,
        '-sections' => '(?i:(Usage|Options))',
        '-exitval'  => 1,
        '-input'    => __FILE__,
        @_
    );
}

##############################################################################
package Pod::Site::Search;

use base 'Pod::Simple::Search';
use strict;
use warnings;

my $instance;
sub instance { $instance }

sub new {
    my $self = shift->SUPER::new(@_);
    $self->laborious(1);
    $instance = $self;
    return $self;
}

##############################################################################
package Pod::Site::XHTML;

use strict;
use base 'Pod::Simple::XHTML';

sub new {
    my $self = shift->SUPER::new;
    $self->index(1);
    return $self;
}

sub start_L {
    my ($self, $flags) = @_;
    my $search = Pod::Site::Search->instance
        or return $self->SUPER::start_L($self);
    my $to  = $flags->{to} || '';
    my $url = $to? $search->name2path->{$to} : '';
    my $id  = $flags->{section};
    return $self->SUPER::start_L($flags) unless $url || ($id && !$to);
    my $rel = $id ? 'subsection' : 'section';
    $url   .= '#' . $self->idify($id, 1) if $id;
    $to   ||= $self->default_title;
    $self->{scratch} .= qq{<a rel="$rel" href="$url" name="$to">};
}

sub html_header {
    my $self = shift;
    my $title = $self->force_title || $self->title || $self->default_title || '';
    my $version = Pod::Site->VERSION;
    my $site = $Pod::Site::_instance;
    return qq{<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.1//EN"
  "http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd">
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en">
  <head>
    <meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
    <meta name="generator" content="Pod::Site $version" />
    <title>$title</title>
  </head>
  <body onload="resizeframe()" class="pod">};
}

# XXX Workaround for https://rt.cpan.org/Ticket/Display.html?id=43489
HACK: {
    package Pod::Simple::BlackBox;
    my $orig;
    BEGIN { $orig = \&Pod::Simple::BlackBox::_ponder_Verbatim }
    no warnings 'redefine';
    sub _ponder_Verbatim {
        my ($self, $para) = @_;
        (my $spaces = $para->[2]) =~ s/\S.*//;
        for (my $i = 2; $i < @$para; $i++) {
            $para->[$i] =~ s/^$spaces//;
        }
        return $self->$orig($para);
    }
}

1;
__END__

=begin comment

Fake-out Module::Build. Delete if it ever changes to support =head1 headers
other than all uppercase.

=head1 NAME

Pod::Site - Build browsable HTML documentation for your app

=end comment

=head1 Name

Pod::Site - Build browsable HTML documentation for your app

=head1 Usage

  podsite --module-root /path/to/app/root \
          --module-name App               \
          --doc-root /path/to/output/html \
          --base-uri /path/to/browser/home

=head1 Description

This program searches the F<lib> and F<bin> directories of a module
distribution and generates a jQuery-powered documentation browser from all of
the Perl modules and scripts that contain POD. It was originally designed for
the Bricolage project (L<http://www.bricolage.cc/>, but is has evolved for
general use. Visit L<http://www.bricolage.cc/docs/current/api/> to see a
sample documentation browser in action. The documentation browser supports
Safari, Firefox, and IE7 up.

Doc Notes:

* --base-uri can be passed more than once, e.g., for symlinked base URIs
  (/docs/current/api).

* Pod::Simple must be patched with the patch
  [here](https://rt.cpan.org/Ticket/Display.html?id=45839).

* Supported Browsers:

  + Firefox 3 (2?)
  + IE 7 (8?)
  + Safari 3-4

=head1 Options

  -V --verbose             Incremental verbose mode.
  -h --help                Print a usage statement and exit.
  -m --man                 Print the complete documentation and exit.
  -v --version             Print the version number and exit.

=head1 To Do

=over

=item *

Add support for resizing the nav pane.

=back

=head1 Support

This module is stored in an open GitHub repository,
L<http://github.com/theory/pod-site/tree/>. Feel free to fork and contribute!

Please file bug reports at L<http://github.com/theory/pod-site/issues>.

=head1 Author

=begin comment

Fake-out Module::Build. Delete if it ever changes to support =head1 headers
other than all uppercase.

=head1 AUTHOR

=end comment

=over

=item David Wheeler <david@justatheory.com>

=back

=head1 Copyright and License

Copyright (c) 2004-2009 David Wheeler. Some Rights Reserved.

This module is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=cut
