#!/usr/bin/perl -w
# Feed carbon with snmp counters from hosts from a nagios server.

use strict;
use warnings;
use SNMP;
use IO::Socket::INET;
use LWP::UserAgent;
use HTML::Entities; # decode_entities
use Storable;       # store, retrieve
use Cwd 'abs_path';
use Data::Dumper;
use Time::HiRes qw( gettimeofday );

my %params = ( interval       => 60                             #
             , skip_empty     => 1                              #
             , nagios_url     => "http://doctor.host.es/nagios" #
             , nagios_user    => "user"                         #
             , nagios_pass    => "pass"                         #
             , snmp_community => 'public'                       #
             , snmp_parallel  => 32                             #
             , carbon_path    => 'collectd.coms'                #
             , carbon_server  => 'graphite.host.es'             #
             , carbon_port    => 2003                           #
             , carbon_proto   => 'tcp'                          #
             , debug          => 0                              #
             );

my %communities = ( junos => 'default@uocpublic' );

my %oids = ( '.1.3.6.1.2.1.31.1.1.1.1'            => { 'OID' => 'ifXName' }
           , '.1.3.6.1.2.1.31.1.1.1.6'            => { 'OID' => 'ifHCInOctets' }
           , '.1.3.6.1.2.1.31.1.1.1.10'           => { 'OID' => 'ifHCOutOctets' }
           , '.1.3.6.1.2.1.31.1.1.1.18'           => { 'OID' => 'ifAlias' }
           , '.1.3.6.1.2.1.2.2.1.13'              => { 'OID' => 'ifInDiscards' }
           , '.1.3.6.1.2.1.2.2.1.19'              => { 'OID' => 'ifOutDiscards' }
           , '.1.3.6.1.2.1.2.2.1.14'              => { 'OID' => 'ifInErrors' }
           , '.1.3.6.1.2.1.2.2.1.20'              => { 'OID' => 'ifOutErrors' }
           # CISCO
           , '.1.3.6.1.4.1.9.9.109.1.1.1.1.8'     => { 'OID' => 'cpmCPUTotal5minRev' }
           # ENTERASYS
           , '.1.3.6.1.4.1.5624.1.2.49.1.1.1.1.4' => { 'OID' => 'etsysResourceCpuLoad5min' }
           # IPSO
           , '.1.3.6.1.4.1.94.1.21.1.7.1.0'       => { 'OID' => 'ipsoProcessorUtilization' }
           # F5
           , '.1.3.6.1.4.1.3375.2.1.2.4.4.3.1.1'  => { 'OID' => 'sysInterfaceStatName' }
           , '.1.3.6.1.4.1.3375.2.1.2.4.4.3.1.3'  => { 'OID' => 'sysInterfaceStatBytesIn' }
           , '.1.3.6.1.4.1.3375.2.1.2.4.4.3.1.5'  => { 'OID' => 'sysInterfaceStatBytesOut' }
           , '.1.3.6.1.4.1.3375.2.1.2.4.4.3.1.8'  => { 'OID' => 'sysInterfaceStatErrorsIn' }
           , '.1.3.6.1.4.1.3375.2.1.2.4.4.3.1.9'  => { 'OID' => 'sysInterfaceStatErrorsOut' }
           , '.1.3.6.1.4.1.3375.2.1.2.4.4.3.1.10' => { 'OID' => 'sysInterfaceStatDropsIn' }
           , '.1.3.6.1.4.1.3375.2.1.2.4.4.3.1.11' => { 'OID' => 'sysInterfaceStatDropsOut' }
           );

my $fullpath = abs_path($0);

#{{{ sub timelog
sub timelog {
    my $text = shift;
    my $now = scalar localtime();
    open(LOG, ">> $fullpath.log") || die "Can't redirect stdout";
    print LOG "$now $text\n";
    close(LOG);
    return print "$now $text\n";
}
#}}}
#{{{ sub fetch_hosts
sub fetch_hosts {
    my $ua = LWP::UserAgent->new(timeout => 5);
    my $req = HTTP::Request->new( GET => "$params{nagios_url}/cgi-bin/config.cgi?type=services");
    $req->authorization_basic("$params{nagios_user}", "$params{nagios_pass}");
    my $res = $ua->request($req);
    print $res->headers_as_string."\n" if $params{debug};
    my $page = decode_entities($res->content);
    my @array = ();
    my %tmphash = ();
    while ($page =~ /<A NAME='HC-([^;]+);HC-([^']+)'.+?type=commands#chk_([\w_]+)_[^']+'>[\w_]+!([\w\.\-_]+)/sg) {
        my ($site, $name, $type, $ip) = ($1, $2, $3, $4);
        next if $tmphash{lc($name)};
        push(@array, { SITE => lc($site)
                     , NAME => lc($name)
                     , TYPE => lc($type)
                     , IP   => $ip
                     }
            );
        $tmphash{lc($name)} = 1
    }
    return @array;
}
#}}}
#{{{ sub putval
sub putval {
    my $time = $params{last_run} || timelog("EE Got no time!.");
    my $metric = shift || 0;
    my $value  = shift || 0;
    my $flush  = 0;

    if ($metric) {
        return 0 unless $value and $params{skip_empty};
        $metric = lc($metric);
        $metric =~ s/[^\w\-\._|]+/_/g;
        $metric =~ s/_+/_/g;
        $metric = "$params{carbon_path}.$metric ${value} ${time}";
        timelog("DD $metric") if $params{debug} == 2;
    } elsif ($params{carbon_buffer}) {
        timelog("DD Forcefully flushing buffer to carbon.") if $params{debug} == 2;
        $flush = 1;
    } else {
        timelog("DD Putval called with nothing to do!.") if $params{debug} == 2;
    }

    my $buffsize = length($params{carbon_buffer});
    my $metlen = length($metric);

    if ( $flush or ($buffsize+$metlen) > 1428 ) { # Ethernet - (IPv6 + TCP) = 1500 - (40 + 32) = 1428 bytes
        timelog("DD Sending buffer ($buffsize bytes) to carbon.") if $params{debug} == 2;
        my $sock = IO::Socket::INET->new( PeerAddr => $params{carbon_server}
                                        , PeerPort => $params{carbon_port}
                                        , Proto    => $params{carbon_proto}
                                        );
        timelog("EE Unable to connect to $params{carbon_server}:$params{carbon_port} $params{carbon_proto}, $!.") unless $sock;
        $sock->send($params{carbon_buffer}) unless $params{debug};
        $params{carbon_buffer} = '';
    }

    $params{carbon_buffer} .= "$metric\n";
}
#}}}
#{{{ sub async_snmp
sub async_snmp {
    my $hostref = shift;
    timelog("DD Adding $hostref->{NAME} ($hostref->{IP}).") if $params{debug};
    my $session = new SNMP::Session( 'DestHost'   => $hostref->{IP}
                                   , 'Community'  => $communities{$hostref->{TYPE}} || $params{snmp_community}
                                   , 'Version'    => '2c'    # No bulkwalk on v1
#                                   , 'Timeout'    => 1000000 # Microseconds
#                                   , 'Retries'    => 10
                                   , 'UseNumeric' => 1       # Return dotted decimal OID
                                   );
    my @VarBinds =();
    push @VarBinds, new SNMP::Varbind([$_]) foreach keys %oids;
    my $VarList = new SNMP::VarList(@VarBinds);
    $params{snmp_running}{$hostref->{NAME}} = 1;
    my $reqid = $session->bulkwalk(0, 1, $VarList, [ \&callback, $VarList, $session, $hostref ]);
    timelog("EE Cannot do async bulkwalk: $session->{ErrorStr} ($session->{ErrorNum}).") if $session->{ErrorNum};
}
#}}}
#{{{ sub callback
sub callback {
    my ($VarList, $session, $hostref, $values) = @_;
    my $host = "$hostref->{SITE}.$hostref->{TYPE}.$hostref->{NAME}";
    timelog("DD $host entered callback, got ".keys(%{$params{snmp_running}})." threads left.") if $params{debug};
    if ($session->{ErrorNum}) {
        timelog("EE $host Error ".$session->{ErrorNum}." ".$session->{ErrorStr}." on ".$session->{ErrorInd});
    } else {
        my $i=0;
        my %arrays=();
        for my $vbarr (@$values) {
            my $oid = $$VarList[$i++]->tag();
            foreach my $v (@$vbarr) {
                push(@{ $arrays{$oids{$oid}{OID}}{VAL} }, $v->val);
                push(@{ $arrays{$oids{$oid}{OID}}{DIFF} }, substr($v->name, -(length($v->name)-length($oid)-1)));
            }
        }

        # Generic SNMP counters.
        if ($arrays{ifXName}) {
            my %ifaces;
            @ifaces{@{ $arrays{ifXName}{DIFF} }} = @{ $arrays{ifXName}{VAL} };
            my %aliases;
            if ($arrays{ifAlias}) {
                @aliases{@{ $arrays{ifAlias}{DIFF} }} = @{ $arrays{ifAlias}{VAL} };
            }
            foreach my $index (0..$#{$arrays{ifHCInOctets}{VAL}}) {
                next unless $arrays{ifHCInOctets}{VAL}->[$index];
                my $nic = $ifaces{$arrays{ifHCInOctets}{DIFF}->[$index]};
                my $alias = $aliases{$arrays{ifHCInOctets}{DIFF}->[$index]} || 'none';
                $nic =~ s/[\.]+/-/g;
                putval("${host}.interfaces.${nic}.${alias}.bytes_in",   $arrays{ifHCInOctets}{VAL}->[$index]);
                putval("${host}.interfaces.${nic}.${alias}.bytes_out",  $arrays{ifHCOutOctets}{VAL}->[$index]);
                putval("${host}.interfaces.${nic}.${alias}.errors_in",  $arrays{ifInErrors}{VAL}->[$index]);
                putval("${host}.interfaces.${nic}.${alias}.errors_out", $arrays{ifOutErrors}{VAL}->[$index]);
                putval("${host}.interfaces.${nic}.${alias}.drops_in",   $arrays{ifInDiscards}{VAL}->[$index]);
                putval("${host}.interfaces.${nic}.${alias}.drops_out",  $arrays{ifOutDiscards}{VAL}->[$index]);
            }
        }

        # F5
        foreach my $index (0..$#{$arrays{sysInterfaceStatName}{VAL}}) {
            next unless $arrays{sysInterfaceStatBytesIn}{VAL}->[$index];
            my $nic = $arrays{sysInterfaceStatName}{VAL}->[$index];
            $nic =~ s/[\.]+/-/g;
            putval("${host}.interfaces.${nic}.none.bytes_in",   $arrays{sysInterfaceStatBytesIn}{VAL}->[$index]);
            putval("${host}.interfaces.${nic}.none.bytes_out",  $arrays{sysInterfaceStatBytesOut}{VAL}->[$index]);
            putval("${host}.interfaces.${nic}.none.errors_in",  $arrays{sysInterfaceStatErrorsIn}{VAL}->[$index]);
            putval("${host}.interfaces.${nic}.none.errors_out", $arrays{sysInterfaceStatErrorsOut}{VAL}->[$index]);
            putval("${host}.interfaces.${nic}.none.drops_in",   $arrays{sysInterfaceStatDropsIn}{VAL}->[$index]);
            putval("${host}.interfaces.${nic}.none.drops_out",  $arrays{sysInterfaceStatDropsOut}{VAL}->[$index]);
        }

        # Some system CPU counters
        putval("${host}.system.cpmCPUTotal5minRev",       $arrays{cpmCPUTotal5minRev}{VAL}->[0])       if $arrays{cpmCPUTotal5minRev}{VAL}->[0];
        putval("${host}.system.etsysResourceCpuLoad5min", $arrays{etsysResourceCpuLoad5min}{VAL}->[0]) if $arrays{etsysResourceCpuLoad5min}{VAL}->[0];
        putval("${host}.system.ipsoProcessorUtilization", $arrays{ipsoProcessorUtilization}{VAL}->[0]) if $arrays{ipsoProcessorUtilization}{VAL}->[0];
    }

    delete $params{snmp_running}{$hostref->{NAME}};
    timelog("DD $host left callback, got ".keys(%{$params{snmp_running}})." threads left.") if $params{debug};
    timelog("DD ".keys(%{$params{snmp_running}})." [ ".join(" ", keys %{$params{snmp_running}})." ]") if $params{debug} == 2;

    if( my $hostref = pop(@{$params{nagios_hosts}}) ) {
        async_snmp($hostref);
    }

    if (keys(%{$params{snmp_running}}) <= 0) {
        timelog("DD No threads left, finishing...") if $params{debug};
        return SNMP::finish;
    }
}
#}}}
sub timeout {
    timelog("EE Global SNMP Timeout with ".keys(%{$params{snmp_running}})." remaining threads [ ".join(" ", keys %{$params{snmp_running}})." ]");
    putval('hosts_remaining', scalar keys(%{$params{snmp_running}}));
    return SNMP::finish;
}

sub main {
    my $run_count = 0;
    $params{nagios_hosts}  = [];
    $params{carbon_buffer} = '';
    while (1) {
        $params{snmp_running} = {};
        ($params{last_run}) = gettimeofday(); # test
        my $next_run = $params{last_run} + $params{interval};
        ${run_count}++;
        timelog("DD Begin ${run_count}th run.") if $params{debug};

        timelog("DD Fetching hosts from '$params{nagios_url}'...") if $params{debug};
        @{$params{nagios_hosts}} = fetch_hosts;
        my $hosts_count = @{$params{nagios_hosts}};

        if ($hosts_count) {
            store(\@{$params{nagios_hosts}}, "$fullpath.hosts") or die "Can't store data!\n";
        } elsif (-f "$fullpath.hosts") {
            timelog("EE Could not fetch hosts, retrieving local data.");
            $params{nagios_hosts} = retrieve("$fullpath.hosts");
            $hosts_count = @{$params{nagios_hosts}};
        } else {
            timelog("EE Could not fetch hosts, and got no local data!!");
        }

        timelog("II ${run_count}th run for $hosts_count hosts.");

        while ( my $hostref = pop(@{$params{nagios_hosts}}) ) {
            async_snmp($hostref);
            if (keys(%{$params{snmp_running}}) >= $params{snmp_parallel}) {
                timelog("DD reached snmp_parallel ($params{snmp_running}), won't thread more.") if $params{debug};
                last;
            }
        }

        SNMP::MainLoop( ((5/6)*$params{interval}), \&timeout );

        while ((my $timeleft = ($next_run - time ())) > 0) {
            my $exectime = ($params{interval}-${timeleft});
            timelog("II ${run_count}th run took ${exectime}s, sleeping for ${timeleft}s.");
            putval('execution_time', $exectime);
            putval('host_count', $hosts_count);
            putval(); # Flush the buffer.
            sleep ($timeleft)
        }
    }
} # main

main();

# vim: set filetype=perl fdm=marker tabstop=4 shiftwidth=4 nu:
