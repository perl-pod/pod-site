package Pod::Site;

use strict;
use warnings;
use File::Spec;
use Carp;
use Pod::Simple '3.08';
use HTML::Entities;
use File::Path;
use Object::Tiny qw(
    module_roots
    doc_root
    base_uri
    index_file
    css_path
    js_path
    versioned_title
    replace_css
    replace_js
    label
    verbose
    mod_files
    bin_files
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

    if (my @req = grep { !$self->{$_} } qw(doc_root base_uri module_roots)) {
        my $pl = @req > 1 ? 's' : '';
        my $last = pop @req;
        my $disp = @req ? join(', ', @req) . (@req > 1 ? ',' : '')
            . " and $last" : $last;
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

    $self->batch_html;

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
    $self->{base_space} = '      ';
    $self->{spacer} = '  ';
    $self->{uri} = '';

    # Make it so!
    $self->sort_files;
    $self->start_nav($idx_fh);
    $self->start_toc($toc_fh);
    $self->output($idx_fh, $self->mod_files);
    $self->output_bin($idx_fh);
    $self->finish_nav($idx_fh);
    $self->finish_toc($toc_fh);
    $self->copy_etc();

    # Close up shop.
    close $idx_fh or die qq{Could not close "$idx_file": $!\n};
    close $toc_fh or die qq{Could not close "$toc_file": $!\n};
}

sub sort_files {
    my $self = shift;

    # Let's see what the search has found.
    my $stuff = Pod::Site::Search->instance->name2path;

    # Sort the modules from the scripts.
    my (%mods, %bins);
    while (my ($name, $path) = each %{ $stuff }) {
        if ($name =~ /[.]p(?:m|od)$/) {
            # Likely a module.
            _set_mod(\%mods, $name, $stuff->{$name});
        } elsif ($name =~ /[.](?:plx?|bat)$/) {
            # Likely a script.
            (my $script = $name) =~ s{::}{/}g;
            $bins{$script} = $stuff->{$name};
        } else {
            # Look for a shebang line.
            if (open my $fh, '<', $path) {
                my $shebang = <$fh>;
                close $fh;
                if ($shebang && $shebang =~ /^#!.*\bperl/) {
                    # Likely a script.
                    (my $script = $name) =~ s{::}{/}g;
                    $bins{$script} = $stuff->{$name};
                } else {
                    # Likely a module.
                    _set_mod(\%mods, $name, $stuff->{$name});
                }
            } else {
                # Who knows? Default to module.
                _set_mod(\%mods, $name, $stuff->{$name});
            }
        }
    }

    # Save our findings.
    $self->{mod_files} = \%mods;
    $self->{bin_files} = \%bins;
}

sub _set_mod {
    my ($mods, $mod, $file) = @_;
    if ($mod =~ /::/) {
        my @names = split /::/ => $mod;
        my $data = $mods->{shift @names} ||= {};
        my $lln = pop @names;
        for (@names) { $data = $data->{$_} ||= {} }
        $data->{"$lln.pm"} = $file;
    } else {
        $mods->{"$mod.pm"} = $file;
    }
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
                if (my $desc = $self->get_desc($class, $path)) {
                    $item = qq{<a href="$self->{uri}$key.html">$key</a>};
                    $self->_output_navlink($fh, $fn, $path, $class, 1, $desc);
                }
                $self->{seen}{$class} = 1;
            }

            # Now recursively descend the tree.
            print STDERR "Outputting nav link\n" if $self->verbose > 2;
            print $fh $self->{base_space}, $self->{spacer} x $self->{indent},
              qq{<li id="$class">$item\n}, $self->{base_space},
              $self->{spacer} x ++$self->{indent}, "<ul>\n";
            ++$self->{indent};
            $self->{uri} .= "$key/";
            $self->output($fh, $data);
            print $fh $self->{base_space}, $self->{spacer} x --$self->{indent},
                "</ul>\n", $self->{base_space},
                $self->{spacer} x --$self->{indent}, "</li>\n";
            $self->{uri} =~ s|$key/$||;
        } else {
            # It's a class. Create a link to it.
            $self->_output_navlink($fh, $fn, $data, $class)
                unless $self->{seen}{$class};
        }
    }
}

sub output_bin {
    my ($self, $fh) = @_;
    my $files = $self->bin_files;
    return unless %{ $files };

    # Start the list in the tree browser.
    print $fh $self->{base_space}, $self->{spacer} x $self->{indent},
      qq{<li id="bin">bin\n}, $self->{base_space}, $self->{spacer} x ++$self->{indent}, "<ul>\n";
    ++$self->{indent};

    for my $pl (sort { lc $a cmp lc $b } keys %{ $files }) {
        my $file = $files->{$pl};
        $self->_output_navlink($fh, $pl, $file, $pl);
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
    my $batchconv = Pod::Simple::HTMLBatch->new;
    $batchconv->index(1);
    $batchconv->verbose($self->verbose);
    $batchconv->contents_file( undef );
    $batchconv->css_flurry(0);
    $batchconv->javascript_flurry(0);
    $batchconv->html_render_class('Pod::Site::XHTML');
    $batchconv->search_class('Pod::Site::Search');
    $batchconv->batch_convert( $self->module_roots, $self->{doc_root} );
    return 1;
}

sub copy_etc {
    my $self = shift;
    require File::Copy;
    (my $from = __FILE__) =~ s/[.]pm$//;
    for my $ext qw(css js) {
        my $dest = File::Spec->catfile($self->{doc_root}, "podsite.$ext");
        File::Copy::copy(
            File::Spec->catfile( $from, "podsite.$ext" ),
            $self->{doc_root}
        ) unless -e $dest && !$self->{"replace_$ext"};
    }
}

sub _udent {
    my $string = shift;
    $string =~ s/^[ ]{4}//gm;
    return $string;
}

sub _output_navlink {
    my ($self, $fh, $key, $fn, $class, $no_link, $desc) = @_;

    $desc ||= $self->get_desc($class, $fn);
    $desc = "—$desc" if $desc;

    # Output the Tree Browser Link.
    print "Outputting $class nav link\n" if $self->{verbose} > 2;
    print $fh $self->{base_space}, $self->{spacer} x $self->{indent},
      qq{<li id="$class"><a href="$self->{uri}$key.html">$key</a></li>\n}
      unless $no_link;

    # Output the TOC link.
    print "Outputting $class TOC link\n" if $self->{verbose} > 2;
    print {$self->{toc_fh}} $self->{base_space}, $self->{spacer},
      qq{<li><a href="$self->{uri}$key.html" rel="section" name="$class">$class</a>$desc</li>\n};
    return 1;
}

sub get_desc {
    my ($self, $what, $file) = @_;

    open my $fh, '<', $file or die "Cannot open $file: $!\n";
    my $desc;
    local $_;
    # Cribbed from Module::Build::PodParser.
    while (<$fh>) {
        next unless /^=(?!cut)/ .. /^=cut/;  # in POD
        last if ($desc) = /^  (?:  [a-z:]+  \s+ - \s+  )  (.*\S)  /ix;
    }

    close $fh or die "Cannot close $file: $!\n";
    print "$what has no POD or no description in a =head1 NAME section\n"
      if $self->{verbose} && !$desc;
    return $desc || '';
}

sub sample_module {
    my $self = shift;
    $self->{sample_module} ||= $self->main_module;
}

sub main_module {
    my $self = shift;
    $self->{main_module} ||= $self->_find_module;
}

sub _find_module {
    my $self = shift;
    my $search = Pod::Site::Search->instance or return;
    my $bins   = $self->bin_files || {};
    for my $mod (sort {
        lc $a cmp lc $b
    } keys %{ $search->instance->name2path }) {
        return $mod unless $bins->{$mod};
    }
}

sub name {
    my $self = shift;
    $self->{name} || $self->main_module;
}

sub main_title {
    my $self = shift;
    return $self->{main_title} ||= join ' ',
        $self->name,
        ( $self->versioned_title ? $self->version : () ),
        ( $self->label ? $self->label : () );
}

sub nav_header {
    my $self = shift;
    $self->name . ($self->versioned_title ? ' ' . $self->version : '');
}

sub version {
    my $self = shift;
    return $self->{version} if $self->{version};
    require Module::Build::ModuleInfo;
    my $mod  = $self->main_module;
    my $file = Pod::Site::Search->instance->name2path->{$mod}
        or die "Could not find $mod\n";
    my $info = Module::Build::ModuleInfo->new_from_file( $file )
        or die "Could not find $file\n";
    return $self->{version} ||= $info->version;
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
        'name|n=s'           => \$opts{name},
        'doc-root|d=s'       => \$opts{doc_root},
        'base-uri|u=s@'      => \$opts{base_uri},
        'sample-module|s=s'  => \$opts{sample_module},
        'main-module|m=s'    => \$opts{main_module},
        'versioned-title|t!' => \$opts{versioned_title},
        'label|l=s'          => \$opts{label},
        'index-file|i=s'     => \$opts{index_file},
        'css-path|c=s'       => \$opts{css_path},
        'js-path|j=s'        => \$opts{js_path},
        'replace-css'        => \$opts{replace_css},
        'replace-js'         => \$opts{replace_js},
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
        my $disp = @missing ? join(', ', @missing) . (@missing > 1 ? ',' : '')
            . " and $last" : $last;
        $self->pod2usage( '-message' => "Missing required $disp option$pl" );
    }

    # Check for one or more module roots.
    $self->pod2usage( '-message' => "Missing path to module root" )
        unless @ARGV;

    $opts{module_roots} = \@ARGV;

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
    $self->inc(0);
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
    return qq{<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.1//EN"
  "http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd">
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en">
  <head>
    <meta http-equiv="Content-Type" content="text/html; charset=UTF-8" />
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

  -d --doc-root DIRECTORY   Browser document root
  -u --base-uri URI         Browser base URI
  -n --name NAME            Site name
  -t --versioned-title      Include main module version number in title
  -l --label LABEL          Label to append to site title
  -m --main-module MODULE   Primary module for the documentation
  -s --sample-module MODULE Module to use for sample links
  -i --index-file FILENAME  File name for index file
  -c --css-path PATH        Path to CSS file
  -j --js-path PATH         Path to CSS file
     --replace-css          Replace existing CSS file
     --replace-js           Replace existing JavaScript file
  -V --verbose              Incremental verbose mode.
  -h --help                 Print a usage statement and exit.
  -M --man                  Print the complete documentation and exit.
  -v --version              Print the version number and exit.

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

David Wheeler <david@justatheory.com>

=head1 Copyright and License

Copyright (c) 2004-2009 David Wheeler. Some Rights Reserved.

This module is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=cut
