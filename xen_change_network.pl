#!/usr/bin/perl
# Batch rename one network for another on every vif of every domu on a dom0 server.

use strict;
use warnings;
use Data::Dumper;
use Term::ANSIColor qw(:constants);
$Term::ANSIColor::AUTORESET = 1;

$| = 1; # No autoflush

sub shell {
    my $cmd = shift;
    my $result = qx{$cmd};
    die RED "ERROR $?:$! launching '$cmd'" if $?;
    chomp($result);
    return $result;
}

# Fetch the and fill our virtual interface hash
my $viflist = shell 'xe vif-list params';
$viflist =~ s/\([ ROW]+\)//g;
my %vifs = ();
while ( $viflist =~ /^uuid[^:]+:\s+([^\n]+)\n(.+?)\n\n/smg ) {
    my ($uuid, $vars) = ($1, $2);
    $vifs{$uuid}{$1} = $2 while $vars =~ /^\s+([^:]+)\s:\s+([^\n]+)\n/smg;
}

# Fill the networks hash
my %networks = ();
map { $networks{$vifs{$_}{'network-uuid'}} = $vifs{$_}{'network-name-label'} } keys %vifs;

# Print our available networks and check the ones we are usind are valid
print BLUE Dumper \%networks;
print "$0 <network-uuid> <network-uuid>\n" and exit 3 unless $#ARGV == 1;
map { die "ERROR: $_ Isn't a valid network-uuid" unless $networks{$_} } @ARGV;

# Do the stuff
print CYAN "Change '$networks{$ARGV[0]}' to '$networks{$ARGV[1]}' on every vm.\n";
foreach my $key (keys %vifs) {
    my %vif = %{ $vifs{$key} };
    next if $vif{'vm-name-label'} eq 'toClone';
    next unless $vif{'network-uuid'} eq $ARGV[0];
    print BOLD WHITE "$vif{'vm-name-label'} has '$networks{$ARGV[0]}' on NIC $vif{device}:\n";
    print YELLOW "\tUnplugging and destroying vif...\n";
    print shell "xe vif-unplug uuid=$key";
    print shell "xe vif-destroy uuid=$key";
    print YELLOW "\tCreating a new vif under NIC $vif{device} with network '$networks{$ARGV[1]}'.\n";
    my $new_uuid = shell "xe vif-create network-uuid=$ARGV[1] vm-uuid=$vif{'vm-uuid'} device=$vif{device}";
    print YELLOW "\tPlugging vif '$new_uuid'.\n";
    print YELLOW shell "xe vif-plug uuid=$new_uuid";
    print BOLD GREEN "\tDone!\n";
}

exit 0;
