package Pod::Site;

use strict;
use warnings;
use File::Spec;
use Carp;
use Pod::Simple '3.08';
use HTML::Entities;
use File::Path;
use File::Find::Rule;
use File::Slurp::Tree;
use Object::Tiny qw(
    module_roots
    doc_root
    base_uri
    index_file
    css_path
    js_path
    versioned_title
    label
    verbose
);

use vars '$VERSION';
$VERSION = '0.50';

sub run {
    my $class = shift;
    $class->new( $class->_config )->build;
}

sub new {
    my ( $class, $params ) = @_;
    my $self = bless {
        index_file => 'index.html',
        verbose    => 0,
        js_path    => '',
        css_path   => '',
        %{ $params || {} }
    } => $class;

    if (my @missing = grep { !$self->{$_} } qw(doc_root base_uri module_roots)) {
        my $pl = @missing > 1 ? 's' : '';
        my $last = pop @missing;
        my $disp = @missing ? join(', ', @missing) . (@missing > 1 ? ',' : '') . " and $last" : $last;
        croak "Missing required parameters $disp";
    }

    my $roots = ref $self->{module_roots} eq 'ARRAY'
        ? $self->{module_roots}
        : ( $self->{module_roots} = [$self->{module_roots}] );
    for my $path (@{ $roots }) {
        croak "The module root $path does not exist\n" unless -e $path;
        croak "The module root $path is not a directory\n" unless -d $path;
    }

    $self->{base_uri} = [$self->{base_uri}] unless ref $self->{base_uri};
    return $self;
}

sub build {
    my $self = shift;
    File::Path::mkpath($self->{doc_root}, 0, 0755);

    # The index file is the home page.
    my $idx_file = File::Spec->catfile( $self->doc_root, $self->index_file );
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
    $self->start_nav($idx_fh);
    $self->start_toc($toc_fh);
    $self->output($idx_fh);
    # $self->output_bin($idx_fh);
    $self->finish_nav($idx_fh);
    $self->finish_toc($toc_fh);
    # $self->copy_etc();

    # Close up shop.
    close $idx_fh or die qq{Could not close "$idx_file": $!\n};
    close $toc_fh or die qq{Could not close "$toc_file": $!\n};

#    $self->batch_html( @{ $self }{qw(doc_root lib bin)} );
}

sub start_nav {
    my ($self, $fh) = @_;
    my $class   = ref $self;
    my $version = __PACKAGE__->VERSION;
    my $title   = encode_entities $self->main_title;
    my $head    = encode_entities $self->nav_header;

    print STDERR "Starting site navigation file\n" if $self->verbose > 1;
    my $base = join "\n        ", map {
        qq{<meta name="base-uri" content="$_" />}
    } @{ $self->{base_uri} };


    print $fh _udent( <<"    EOF" );
    <!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.1//EN"
    "http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd">
    <html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en">
      <head>
        <meta http-equiv="Content-Type" content="text/html; charset=UTF-8" />
        <title>$title</title>
        <link rel="stylesheet" type="text/css" href="$self->{css_path}podsite.css" />
        $base
        <script type="text/javascript" src="$self->{js_path}podsite.js"></script>
        <meta name="generator" content="$class $version" />
      </head>
      <body>
        <div id="nav">
          <h3>$head</h3>
          <ul id="tree">
            <li id="toc"><a href="toc.html">TOC</a></li>
    EOF
}

sub start_toc {
    my ($self, $fh) = @_;

    my $sample  = encode_entities $self->sample_module;
    my $version = Pod::Site->VERSION;
    my $title   = encode_entities $self->main_title;

    print STDERR "Starting browser TOC file\n" if $self->verbose > 1;
    print $fh _udent( <<"    EOF");
    <!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.1//EN"
    "http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd">
    <html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en">
      <head>
        <meta http-equiv="Content-Type" content="text/html; charset=UTF-8" />
        <title>$title</title>
        <meta name="generator" content="Pod::Site $version" />
      </head>

      <body>
        <h1>$title</h1>
        <h1>Instructions</h1>

        <p>Select class names from the navigation tree to the left. The tree
           shows a hierarchical list of modules and programs. In addition to
           this URL, you can link directly to the page for a particular module
           or program. For example, if you wanted to access
           $sample, any of these links will work:</p>

        <ul>
          <li><a href="./?$sample">/?$sample</a></li>
          <li><a href="./$sample">/$sample</a></li>
        </ul>

        <p>Happy Hacking!</p>

        <h3>Classes &amp; Modules</h3>
        <ul>
    EOF
}

sub output {
    my ($self, $fh, $tree) = @_;
    $tree ||= $self->module_tree;
    for my $key (sort keys %{ $tree }) {
        my $data = $tree->{$key};
        (my $fn = $key) =~ s/\.[^.]+$//;
        my $class = join ('::', split('/', $self->{uri}), $fn);
        print STDERR "Reading $class\n" if $self->verbose > 1;
        if (ref $data) {
            # It's a directory tree. Output a class for it, first, if there
            # is one.
            my $item = $key;
            if ($tree->{"$key.pm"}) {
                my $path = $tree->{"$key.pm"};
                if (my $desc = $self->get_desc($class, $path, $self)) {
                    $item = qq{<a href="$self->{uri}$key.html">$key</a>};
                    $self->_output_class($fh, $fn, $path, $class, 1, $desc);
                }
                $self->{seen}{$class} = 1;
            }

            # Now recursively descend the tree.
            print STDERR "Outputting nav link\n" if $self->verbose > 2;
            print $fh $self->{base_space}, $self->{spacer} x $self->{indent},
              qq{<li id="$class">$item\n}, $self->{base_space}, $self->{spacer} x ++$self->{indent}, "<ul>\n";
            ++$self->{indent};
            $self->{uri} .= "$key/";
            $self->output($fh, $data);
            print $fh $self->{base_space}, $self->{spacer} x --$self->{indent}, "</ul>\n",
              $self->{base_space}, $self->{spacer} x --$self->{indent}, "</li>\n";
            $self->{uri} =~ s|$key/$||;
        } else {
            # It's a class. Create a link to it.
            $self->_output_class($fh, $fn, $data, $class) unless $self->{seen}{$class};
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

    for my $pl (sort keys %{ $tree }) {
        # Skip directories.
        next if ref $tree->{$pl};
        print "STDERR Reading $pl\n" if $self->verbose > 1;
        # Get the description.
        my $desc = $self->get_desc($pl, $tree->{$pl}, $pl) or next;

        # Output the Tree Browser Link.
        print STDERR "Outputting $pl nav link\n" if $self->verbose > 2;
        print $fh $self->{base_space}, $self->{spacer} x $self->{indent},
          qq{<li id="$pl"><a href="$pl.html">$pl</a></li>\n};

        # Output the TOC link.
        print STDERR "Outputting toc link\n" if $self->verbose > 2;
        print {$self->{toc_fh}} $self->{base_space},
          qq{  <li><a href="$pl.html" rel="section" name="$pl">$pl</a>&#x2014;$desc</li>\n};
    }

    print $fh $self->{base_space}, $self->{spacer} x --$self->{indent}, "</ul>\n",
      $self->{base_space}, $self->{spacer} x --$self->{indent}, "</li>\n";
}

sub finish_nav {
    my ($self, $fh) = @_;
    print STDERR "Finishing browser navigation file\n" if $self->verbose > 1;
    print $fh _udent( <<"    EOF" );
          </ul>
        </div>
        <div id="doc"></div>
      </body>
    </html>
    EOF
}

sub finish_toc {
    my ($self, $fh) = @_;
    print STDERR "finishing browser TOC file\n" if $self->verbose > 1;
    print $fh _udent( <<"    EOF" );
        </ul>
      </body>
    </html>
    EOF
}

sub batch_html {
    my $self = shift;
    require Pod::Simple::HTMLBatch;
    print STDERR "Creating HTML with Pod::Simple::XHTML\n" if $self->verbose > 1;
    # XXX I'd rather have a way to get this passed to the P::S::XHTML object.
    local $Pod::Site::_instance = $self;
    my $batchconv = Pod::Simple::HTMLBatch->new;
    $batchconv->index(1);
    $batchconv->verbose($self->{verbose});
    $batchconv->contents_file( undef );
    $batchconv->css_flurry(0);
    $batchconv->javascript_flurry(0);
    $batchconv->html_render_class('Pod::Site::XHTML');
    $batchconv->search_class('Pod::Site::Search');
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
    my ($self, $fh, $key, $fn, $class, $no_link, $desc) = @_;

    $desc ||= $self->get_desc($class, $fn, $class) or return;

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
    my ($self, $what, $file) = @_;

    open my $fh, '<', $file or die "Cannot open $file: $!\n";
    my $desc;
    while (<$fh>) {
        next unless /^=head1 NAME$/i;
        while (<$fh>) {
            last if /^=\w+/;
            next unless /\Q$what\E\s+-\s+([^\n]+)$/i;
            $desc = $1;
            last;
        }
        last;
    }

    close $fh or die "Cannot close $file: $!\n";
    print "$what has no POD or no description in a =head1 NAME section\n"
      if $self->{verbose} && !$desc;
    return $desc;
}

sub module_tree {
    my $self = shift;
    return $self->{module_tree} if $self->{module_tree};

    my $tree = $self->{module_tree} = {};
    my $rule = File::Find::Rule->file->name(qr/\.p(?:m|od)$/);

    for my $lib (@{ $self->module_roots }) {
        (my $top = $lib) =~ s{/$}{};
        for my $file ( $rule->in( $lib ) ) {
            next if $file eq $top;
            (my $rel = $file) =~ s{^\Q$top\E/}{};
            next unless $rel; # it's /

            my @elems = split m{/}, $rel;

            # go to the top of the tree
            my $node = $tree;
            # and walk along the path
            while (my $elem = shift @elems) {
                # on the path || a dir
                if (@elems || -d $file) {
                    $node = $node->{ $elem } ||= {};
                }
                else {
                # a file, remember it.
                    $node->{ $elem } ||= $file;
                }
            }
        }
    }

    return $tree;
}

sub sample_module {
    my $self = shift;
    $self->{sample_module} ||= $self->main_module;
}

sub main_module {
    my $self = shift;
    $self->{main_module} ||= $self->_find_module($self->module_tree);
}

sub title {
    my $self = shift;
    $self->{title} ||= $self->_find_title;
}

sub main_title {
    my $self = shift;
    return $self->label
        ? $self->title . ' ' . $self->label
        : $self->title;
}

sub nav_header {
    shift->title;
}

sub _find_module {
    my ($self, $tree) = @_;
    for my $key ( sort keys %{ $tree }) {
        if ($key =~ s/[.]p(?:m|od)$//) {
            return $key;
        } elsif (my $mod = $self->_find_module($tree->{$key})) {
            return $key . "::$mod";
        }
    }
}

sub _main_module_file {
    my $self = shift;
    my $mod = $self->main_module;
    return $mod if $mod =~ /[.]p(?:m|od)$/;
    my @parts = split /::/, $mod;
    my $last = pop @parts;
    my $tree = $self->module_tree;
    while (@parts) {
        $tree = $tree->{shift @parts};
    }
    return $tree->{"$last.pm"} || $tree->{"$last.pod"};
}

sub _find_title {
    my $self = shift;
    require Module::Build::ModuleInfo;
    my $mod_file = $self->_main_module_file;
    my $info = Module::Build::ModuleInfo->new_from_file( $mod_file )
        or die "Could not find $mod_file\n";
    return $info->name unless $self->versioned_title && $info->version;
    return $info->name . ' ' . $info->version;
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
        'title|t=s'          => \$opts{title},
        'doc-root|d=s'       => \$opts{doc_root},
        'base-uri|u=s@'      => \$opts{base_uri},
        'sample-module|s=s'  => \$opts{sample_module},
        'main-module|m=s'    => \$opts{main_module},
        'versioned-title|n!' => \$opts{versioned_title},
        'label|l=s'          => \$opts{label},
        'index-file|i=s'     => \$opts{index_file},
        'css-path|c=s'       => \$opts{css_path},
        'js-path|j=s'        => \$opts{js_path},
        'verbose|V+'         => \$opts{verbose},
        'help|h'             => \$opts{help},
        'man|M'              => \$opts{man},
        'version|v'          => \$opts{version},
    ) or $self->pod2usage;

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
    if (my @missing = map {
        ( my $opt = $_ ) =~ s/_/-/g;
        "--$opt";
    } grep { !$opts{$_} } qw(doc_root base_uri)) {
        my $pl = @missing > 1 ? 's' : '';
        my $last = pop @missing;
        my $disp = @missing ? join(', ', @missing) . (@missing > 1 ? ',' : '') . " and $last" : $last;
        $self->pod2usage( '-message' => "Missing required $disp option$pl" );
    }

    # Check for one or more module roots.
    unless (@ARGV) {
        $self->pod2usage( '-message' => "Missing path to module root" );
    }

    $opts{module_roots} = \@ARGV;

    # Make sure we can find stuff to convert.
    # $opts{bin} = File::Spec->catdir( $opts{module_root}, 'bin' );
    # $opts{lib} = File::Spec->catdir( $opts{module_root}, 'lib' );
    # $self->pod2usage(
    #     '-message' => "$opts{module_root} has no 'lib' or 'bin' subdirectory"
    # ) unless -d $opts{module_root} && (-d $opts{lib} || -d $opts{bin});

    # Modify options and set defaults as appropriate.
    for (@{ $opts{base_uri} }) { $_ .= '/' unless m{/$}; }

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
    my $url = $to ? $search->name2path->{$to} : '';
    my $id  = $flags->{section};
    return $self->SUPER::start_L($flags) unless $url || ($id && !$to);
    my $rel = $id ? 'subsection' : 'section';
    $url   .= '#' . $self->idify($id, 1) if $id;
    $to   ||= $self->title || $self->default_title || '';
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

# Future-proof against Pod::Simple::XHTML implementing
# batch_mode_page_object_init(). It doesn't currently, but since
# Pod::Simple::HTMLBatch calls it if it exists (as it does here in our
# subclass), it might be added in the future, so be sure to call it if it gets
# added.

my $orig;
BEGIN { $orig = __PACKAGE__->can('batch_mode_page_object_init') };

sub batch_mode_page_object_init {
    my $self = shift;

    # Call the superclass method if it exists.
    $orig->($self, @_) if $orig;

    # Strip leading spaces from verbatim blocks equivalent to the indent of
    # the first line.
    $self->strip_verbatim_indent(sub {
        my $lines = shift;
        (my $indent = $lines->[0]) =~ s/\S.*//;
        return $indent;
    });
    return $self;
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

  podsite --module-name App               \
          --doc-root /path/to/output/html \
          --base-uri /path/to/browser/home \
          /path/to/app/root

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
