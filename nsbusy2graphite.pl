#!/usr/bin/perl -w
# Envia el load de las cabinas a graphite usando naviseccli

use strict;
use warnings;

use threads;
use IO::Socket::INET;

my %params = ( carbon_path    => 'collectd.nas'
             , carbon_server  => 'graphite.server.org'
             , carbon_port    => 2003
             , carbon_proto   => 'tcp'
             , debug          => 0
             );

my @ns = qw /ns1 ns2 ns3 ns4/;

sub putval {
    my $time = time();
    my $metric = lc(shift);
    my $value  = shift || 0;
    return 0 unless $value;
    $metric =~ s/[^\w\-\._,|]+/_/g;
    $metric =~ s/_+/_/g;
    $metric = "$params{carbon_path}.$metric ${value} ${time}\n";
    print "$metric" if $params{debug};
    my $sock = IO::Socket::INET->new( PeerAddr => $params{carbon_server}
                                    , PeerPort => $params{carbon_port}
                                    , Proto    => $params{carbon_proto}
                                    );
    $sock->send($metric);
}

my @threads = ();
foreach my $ns (sort @ns) {
    push ( @threads, async( sub { my $result = `naviseccli -h $ns getcontrol -busy`;
                                  putval("$ns.busy_percent", $1) if $result =~ /Prct Busy:\s+(\S+)\n/;
                                }
                          )
         )
}
$_->join() foreach @threads;
