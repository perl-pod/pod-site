#!perl -w

# $Id: pod.t 4571 2009-03-01 19:23:18Z david $

use strict;
use Test::More;
eval "use Test::Pod 1.20";
plan skip_all => "Test::Pod 1.20 required for testing POD" if $@;
all_pod_files_ok();
