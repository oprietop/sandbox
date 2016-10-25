#!/usr/bin/perl
# Rebuild the contents of the collections.json file using the search indexes database (Index.db) of a Kindle DX.
#
# 1: Mount the device
# 2: Backup the collections.json file if you want.
# 2: perl kindle_collections.pl /media/KINDLE/system/Search\ Indexes/Index.db > /media/KINDLE/system/collections.json (use the apropiated paths)
# 3: Reboot the device (Home->Menu->Settings->Menu->restart)

use strict;
use Digest::SHA1 qw(sha1_hex);

my $hash = undef;
$/ = undef;

while (<>) {
    while (/([\040-\176\s]{4,})/g) {
        if ($1 =~ /(\/mnt\/us\/(.+)\/([^\/]+\.(:?pdf|mobi|txt)))sq/i) {
            map {$hash->{ucfirst(lc($_))}->{sha1_hex($1)} = $1} split("/", $2);
        }
    }
}

print "{\"".join (',"', map {"$_\@en-US\":{\"items\":[\"*".join ('","*', keys %{$hash->{$_}})."\"],\"lastAccess\":0}"} sort keys %{$hash})."}";
