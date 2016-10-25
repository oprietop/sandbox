#!/usr/bin/perl -w
# send the netstat tcp values of our nas Control Stations to graphite.

use warnings;
use strict;
use Net::OpenSSH;
#$Net::OpenSSH::debug |= 16; # Debug
use IO::Socket::INET;

my $user  = 'user';
my $pass  = 'pass';
my @hosts = qw/host1 host2/;
my %params = ( carbon_path    => 'collectd.nas.netstat'
             , carbon_server  => 'graphite.host.net'
             , carbon_port    => 2003
             , carbon_proto   => 'tcp'
             , debug          => 0
             );

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

# Initiate and keep a connection to each host.
my %conn = map { $_ => Net::OpenSSH->new( $_
                                        , port    => 22
                                        , user    => $user
                                        , passwd  => $pass
                                        , async   => 1
                                        , timeout => 10
                                        , master_stderr_discard => 1
                                        , master_opts => [-o => "StrictHostKeyChecking=no"]
                                        ) } @hosts;

# Launch commands to each host reusing the connection.
my @pid;
my @results= ();
foreach my $host (sort @hosts) {
    open my($fh), '>', "/tmp/$host" or die "Unable to create file: $!";
    my $pid = $conn{$host}->spawn( { stdout_fh => $fh
                                   , stderr_fh => $fh
                                   }
                                 , '. .bash_profile; server_netstat server_2 -i -p tcp'
                                 );
    push(@pid, $pid) if $pid;
}

# Wait for all the commands to finish.
waitpid($_, 0) for @pid;

# Process the output files.
foreach my $host (sort @hosts) {
    open(FH, "<", "/tmp/$host") or die "Unable to read file: $!";
    foreach my $line (<FH>) {
        putval("$host.$2", $1) if $line =~ /^(\d+)\s(.+)$/;
    }
    close(FH);
    unlink "/tmp/$host";
}

my $date = scalar localtime();
my $runtime=(time - $^T);
print "OK (${runtime}s)\n" and exit 0;
