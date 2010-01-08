#!perl -w

use strict;
use Test::More;
eval "use Test::Pod::Coverage 1.06";
plan skip_all => "Test::Pod::Coverage 1.06 required for testing POD coverage"
  if $@;
plan skip_all => 'Come back to these tests, bokay?';

all_pod_coverage_ok();
