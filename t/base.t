#!/usr/bin/perl -w

use strict;
#use Test::More tests => 316;
use Test::More 'no_plan';

my $CLASS;
BEGIN {
    $CLASS = 'Pod::Site';
    use_ok $CLASS or die;
}

