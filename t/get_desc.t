use strict;
use warnings;
use utf8;
use Encode;
use File::Temp qw/tempdir/;
use Test::More;
use Pod::Site;

my $tmpdir = tempdir CLEANUP => 1;
my $site = Pod::Site->new({
    doc_root     => $tmpdir,
    base_uri     => '/dummy/',
    module_roots => $tmpdir,
});

is do {
    $site->get_desc('MyClass1', \ Encode::encode_utf8(<<'.'));
=head1 Name

MyClass1 - The description of MyClass1

=cut
.
}, Encode::encode_utf8('The description of MyClass1');

done_testing;
