#!/usr/bin/perl -w

# $Id: base.t 4571 2009-03-01 19:23:18Z david $

use strict;
#use Test::More tests => 316;
use Test::More 'no_plan';

my $CLASS;
BEGIN {
    $CLASS = 'Pod::Site';
    use_ok($CLASS) or die;
}
