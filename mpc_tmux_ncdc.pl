#!/usr/bin/perl

use strict;
use warnings;

my $host = $ARGV[0] || "127.0.0.1";
my ($name, $artist, $album, $date, $title, $track, $time, $file, $stats, $footer) = split("\n", `mpc -f "%name%\n%artist%\n%album%\n%date%\n%title%\n%track%\n%time%\n%file%" -h $host 2>/dev/null`);
if ($stats and $track and $artist and $title and $album) {
    $artist =~ s/\s\/\s[^,]+//g if length($artist) > 60;
    $artist = 'V.A.'if length($artist) > 60;
    my $line = sprintf("\r/me %s %02d - %s - %s, from the album \'%s\'\n", $stats, $track, $artist, $title, $album);
    $line =~ s/ +/ /g;
    `tmux send-keys -t ncdc "$line" 2>/dev/null`;
}
