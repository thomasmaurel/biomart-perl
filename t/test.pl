#!/usr/bin/perl -w

# $Id$

use strict;
use FindBin qw($Bin);
use Test::Harness;

my @testfiles = ();
opendir(DIRHANDLE,"$Bin");
(/.*\.t/ and push @testfiles, "$Bin/$_") foreach (readdir(DIRHANDLE));
closedir(DIRHANDLE);

runtests(@testfiles);
