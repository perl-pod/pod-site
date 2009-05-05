#!perl -w

# $Id: pod-spelling.t 4571 2009-03-01 19:23:18Z david $

use strict;
use Test::More;
eval "use Test::Spelling";
plan skip_all => "Test::Spelling required for testing POD spelling" if $@;

add_stopwords(<DATA>);
all_pod_files_spelling_ok();

__DATA__
Kineticode
JavaScript
browsable

