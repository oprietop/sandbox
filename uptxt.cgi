#!/usr/bin/perl -wT

use strict;
use CGI;
#use CGI::Carp 'fatalsToBrowser';
$CGI::POST_MAX = 1024 * 500; #50K POSTS
my $path = "/opt/local/networkauthority-inventory/tool-file-store";
my $cgi = new CGI;
print $cgi->header;
my $filename = $cgi->param('Filename') or die $!;
$filename =~ s/\W/_/g;
$filename = quotemeta($filename);
open(LOCAL, ">$path/$filename") or die $!;
my $data = $cgi->param('config_file') or die $!;
while(<$data>) {
    print LOCAL $_;
}
close(LOCAL);
