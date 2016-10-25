#!/usr/bin/perl
# List unused ports on a L2/L3 device using SNMP::Info.

use strict;
use warnings;
use SNMP::Info;
use Getopt::Long;
use Term::ANSIColor qw(:constants colored);
use Data::Dumper;
$Term::ANSIColor::AUTORESET = 1;

$0 =~ s/.*\///g;
my $days = 0;
GetOptions ('days=i' => \$days);

unless (@ARGV) {
    print <<EOF;
Usage: $0 <hosts> --days <days>
args:
\t<hosts>\tDevice to interrogate, any extra host specified as an argument will also be queried.
\t--day, -d\tA single or a comma-separated list of <hosts> to ping.
Example:
\t$0 host1.domain.es 6.6.6.6. -d 30
EOF
    exit 1;
}

sub check_ip_host() {
    my $validip = "^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\$";
    my $validhost = "^(([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9\-]*[a-zA-Z0-9])\.)*([A-Za-z]|[A-Za-z][A-Za-z0-9\-]*[A-Za-z0-9])\$";
    @_ ? my @badhosts = grep { $_ !~ /(?:$validip|$validhost)/ } @_ : die "You must specify a host.\n";
    @badhosts ? print RED join(", ", @badhosts)." Have Invalid Hostame/IP.\n" : return 0;
    exit 1 if @badhosts;
}

sub TrueSort() { # http://www.perlmonks.org/?node_id=483462
    my @list = @_;
    return @list[
        map { unpack "N", substr($_,-4) }
        sort
        map {
            my $key= $list[$_];
            $key =~ s[(\d+)][ pack "N", $1 ]ge;
            $key . pack "N", $_
        } 0..$#list
    ];
}

&check_ip_host(@ARGV);

foreach my $host (@ARGV) {
    print BOLD RED "$host\n";

    my $info = new SNMP::Info( AutoSpecify => 1
                             , LoopDetect  => 1
                             , BulkWalk    => 1
                             , DestHost    => $host
                             , Community   => 'public'
                             , Version     => 2
                             , MibDirs     => [ '/usr/share/netdisco/mibs/rfc'
                                              , '/usr/share/netdisco/mibs/net-snmp'
                                              , '/usr/share/netdisco/mibs/cisco'
                                              , '/usr/share/netdisco/mibs/enterasys'
                                              , '/usr/share/netdisco/mibs/juniper'
                                              ]
                             ) or print RED "Can't connect to device '$host'.\n" and exit 1;
    die "SNMP Community or Version probably wrong connecting to device. The error was: '$info->error()'.\n" if defined $info->error();

    my $interfaces = $info->interfaces();
    my $i_type = $info->i_type();
    my $i_up = $info->i_up();
    my $i_lastchange = $info->i_lastchange();
    my $uptime = int(($info->uptime())/100/86400);
    my $req_time = $days || $uptime;
    my $port_count = 0;

    print YELLOW " Hardware uptime:";
    print BOLD BLUE " $uptime Days\n";
    print GREEN " Ports with a disabled state >= than $req_time days:\n";

    foreach my $iid (sort { $a <=> $b } keys %$interfaces) {
        next unless defined $i_type->{$iid} and $i_type->{$iid} eq "ethernetCsmacd";
        next unless defined $i_up->{$iid} and $i_up->{$iid} ne "up";
        my $i_days = int(($info->uptime() - $i_lastchange->{$iid})/100/86400);
        next unless $i_days >= $req_time;
        print GREEN " |- ";
        print BOLD WHITE "$interfaces->{$iid}";
        print BLUE "\t($i_days Days)\n";
        $port_count++;
    }
    print GREEN " + $port_count ports.\n";
}
