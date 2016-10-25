#!/usr/bin/perl
# Traverse and count directories recursively via opendir/readdir
# http://www.perlmonks.org/?displaytype=displaycode;node_id=883695

use strict;
use warnings;
use POSIX;

my @paths;
push(@ARGV, ".") if @ARGV == 0;

$|++;  # turn off stdout buffering

for my $path (@ARGV) {
    next unless -d $path;
    print "# Trying '$path'\n";
    $path =~ s:/$::;  # remove trailing slash, if any
    traverse($path);
}

sub traverse {
    my ($dirname) = @_;
    my $dcount = 0;
    my $dh;
    my $starttime = time;
    return if ! opendir($dh, $dirname);
    while (my $file = readdir($dh)) {
        next if $file =~ /^\.{1,2}$/;
        next if -l "$dirname/$file";
        if ( -d _ ) { # http://www.perlmonks.org/?node_id=613625
            traverse("$dirname/$file");
            $dcount++;
        }
    }
    closedir $dh;
    printf("%-6.6s %s (%ss)\n", $dcount, $dirname, time - $starttime);
}

print "We ran for (".(time - $^T)."s)\n";
