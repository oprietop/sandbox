#!/usr/bin/perl -w
# Reliability of the interface as a fraction of 255 (255/255 is 100 percent reliability), calculated as an exponential average over 5 minutes.
# txload/rxload=Load on the interface as a fraction of 255 (255/255 is completely saturated), calculated as an exponential average over 5 minutes.

use strict;
use SNMP;
use Net::Telnet;

$0 =~ s/.*\///g;
print "Usage: $0 <host/s>\n" and exit 1 unless @ARGV;

my %chuis =();
$chuis{'.1.3.6.1.4.1.2467.4.3'} = {name => 'CSS1150' ,user => 'xxxxx' ,pass => 'xxxxx' ,runcmd => 'terminal length 65535'};

my @communities = qw/public readonly/;

sub getSNMP() {
    my $machine   = shift || 'localhost';
    my $community = shift || 'public';
    my $oid       = shift || '.1.3.6.1.2.1.1.2.0';
    my $session   = new SNMP::Session( DestHost   => $machine
                                     , Community  => $community
                                     , Retrien    => 0
                                     , Version    => 2
                                     , UseNumeric => 1
                                     );
    if ($session) {
        my $result = $session->get($oid);
        $result ? return $result : print "#\tNo SNMP response from '$machine' using '$community'.\n" and return 0
    } else {
        die "#\tNo SNMP session from '$machine'\n";
    }
}

foreach my $host (@ARGV) {
    my $sysObjectID = 0;
    print "#\tTrying '$host'...\n";
    foreach (@communities) {
        $sysObjectID = &getSNMP($host, $_);
            last if $sysObjectID;
    }

    if ($sysObjectID) {
        $chuis{$sysObjectID}{name} ? print "#\tHardware: $chuis{$sysObjectID}{name} ($sysObjectID)\n" : die "#\t$sysObjectID no está en el hash:\n";
    } else {
        die "#\tNo SNMP response from '$host'.\n";
    }

    my $telnet = new Net::Telnet ( Timeout => 10
                                 , Errmode => 'return'
                                 , Prompt  => '/(?m:.*[\w.-]+\s?(?:\(config[^\)]*\))?\s?[\+\$#>]\s?(?:\(enable\))?\s*$)/'
                                 );
    $telnet->open($host);
    $telnet->login($chuis{$sysObjectID}{user}, $chuis{$sysObjectID}{pass});

    my $prompt = $telnet->last_prompt;
    $prompt =~ tr/\015//d;
    $prompt ? print "#\tPrompt: '$prompt'\n" : die "#\tUnable to get prompt.\n";

    if ($chuis{$sysObjectID}{enable}) {
        $telnet->print('enable');
        $telnet->waitfor('/password/i');
        $telnet->cmd($chuis{$sysObjectID}{enable});
        if ($telnet->lastline =~ /denied/i) {
            print " NOK\n#\tSkipping Host '$host'\n";
            next;
        }
    }

    $telnet->cmd($chuis{$sysObjectID}{runcmd}) if $chuis{$sysObjectID}{runcmd};

    my $output = join('', $telnet->cmd("show interfaces"));
    while ($output =~ /([^\n]+) is up, l.+?y (\d+)\/255, txload (\d+)\/255, rxload (\d+)\/255/sg) {
        printf("%-24s Reliability: %2d%% txload: %2d%% rxload: %2d%%\n", $1, int(($2*100)/255), int(($3*100)/255), int(($4*100)/255));
    }
}
exit 0;
