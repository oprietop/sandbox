#!/usr/bin/perl
# Redux of the -awesome- check_xenapi.pl script from op5.org
# http://git.op5.org/git/?p=nagios/op5plugins.git;a=blob_plain;f=check_xenapi.pl;hb=HEAD
# VM specific :
#    * cpu - shows cpu info
#        + <number> - CPU core usage
#    * mem - shows memory info
#        + allocated - allocated memory for VM in MB
#        + ballooned - target memory for VM balloon driver in MB
#        + internal - MB free memory available in guest OS
#    * net - shows network info\n"
#        + usage - overall usage of network(send + receive) in KB/s
#        + errors - overall network errors(txerrs + rxerrs)
#        + send - overall transmit in KB/s
#        + receive - overall receive in KB/s
#        + txerrs - overall transmit errors per second/s
#        + rxerrs - overall receive errors per second/s
#    * io - shows disk I/O info\n"
#        + usage - overall disk usage in MB/s
#        + latency - overall latency in ms
#        + read - overall disk read in MB/s
#        + write - overall disk write in MB/s
#        + read_latency - overall disk read latency in ms
#        + write_latency - overall disk write latency in ms

use strict;
use warnings;

use XML::Simple;
use LWP::UserAgent;
use Data::Dumper;

my $user       = 'user';
my $pass       = 'pass';
my $host       = '127.0.0.1';
my $rolluptype = 'AVERAGE';

my $ua = LWP::UserAgent->new( agent         => 'Mac Safari'
                            , show_progress => 1 # Adds fancy progressbars
                            , timeout       => 5
                            , ssl_opts      => { verify_hostname => 0 }
                            );

sub request ($) {
    my $url = shift || die "No url\n";
    my $req = HTTP::Request->new(GET => $url);
    $req->authorization_basic($user, $pass);
    my $resp = $ua->request($req);
    $resp->is_success ? return $resp->content : print $resp->status_line."\n";
    exit 1 unless $resp->is_success;
}

sub parse_xml {
    my $xml = shift;
    my ($columns, $rows, $start, $end, $step, $data);
    my ($host, $vm) = ({}, {});
    my $rrd;
    if ($xml) {
        $rrd = XMLin($xml, ForceArray => [ 'row' ]);
        $columns = $rrd->{meta}->{columns};
        $rows    = $rrd->{meta}->{rows};
        $start   = $rrd->{meta}->{start};
        $end     = $rrd->{meta}->{end};
        $step    = $rrd->{meta}->{step};
        $data    = $rrd->{data}->{row};
        my $pos = 0;
        foreach my $label (@{$rrd->{meta}->{legend}->{entry}}) {
            my ($cf, $vm_or_host, $uuid, $param) = split(/:/, $label, 4);
            if ($vm_or_host eq 'vm') {
                    $vm->{$uuid}->{$param}->{$cf} = $pos;
            } elsif ($vm_or_host eq 'host') {
                    $host->{$uuid}->{$param}->{$cf} = $pos;
            } else {
            }
            $pos++;
        }
    }
    return { columns => $columns
           , rows    => $rows
           , start   => $start
           , end     => $end
           , step    => $step
           , hosts   => $host
           , vms     => $vm
           , data    => $data
           };
}

sub simplify_number {
    my ($number, $cnt) = (@_, 2);
    return sprintf("%.${cnt}f", "$number");
}

sub get_object_data {
    my ($self, $type, $uuid) = @_;
    my $data = [];
    if (exists($self->{data})) {
        my $object = $self->{$type}->{$uuid};
        foreach my $row (@{$self->{data}}) {
            my $perf = {timestamp => $row->{t}, data => {}};
            foreach my $counter (keys(%{$object})) {
                $perf->{data}->{$counter} = {};
                foreach my $rollup (keys(%{$object->{$counter}})) {
                    $perf->{data}->{$counter}->{$rollup} = $row->{v}[$object->{$counter}->{$rollup}];
                }
            }
            push(@{$data}, $perf);
        }
    }
    return $data;
}

sub get_latest_perfdata {
    my ($obj, $uuid) = @_;
    my $rrd = &get_object_data($obj, 'vms', $uuid);
    my $perf = {};
    my $time = 0;
    # get newest perf data
    foreach my $row (@{$rrd}) {
        if ($time < $row->{timestamp}) {
            $time = $row->{timestamp};
            $perf = $row->{data};
        }
    }
    return $perf;
}

sub vm_cpu_info {
    my ($uuid, $perf) = @_;
    my $usage = 0;
    my $i = 0;
    # get all cpu values with keys: cpu0, cpu1, ..., cpu7, ...
    while (my $val = $perf->{"cpu$i"}) {
        $usage += $val->{$rolluptype};
        $i++;
    }
    $usage = simplify_number($usage / $i * 100) if ($i > 0);
    return "VM '" . $uuid . "' cpu: usage = " . $usage . " %";
}

sub vm_mem_info {
    my ($uuid, $perf) = @_;
    my $alloc = 'nan';
    my $target = 'nan';
    my $internal = 'nan';
    $alloc = simplify_number($perf->{memory}->{$rolluptype} / 1024 / 1024) if (exists($perf->{memory}));
    $target = simplify_number($perf->{memory_target}->{$rolluptype} / 1024 / 1024) if (exists($perf->{memory_target}));
    $internal = simplify_number($perf->{memory_internal_free}->{$rolluptype} / 1024) if (exists($perf->{memory_internal_free}));
    return "VM '" . $uuid . "' mem: allocated = " . $alloc . " MB, ballooned = " . $target . " MB, internal = " . $internal . " MB";
}

sub vm_net_info {
    my ($uuid, $perf) = @_;
    my $list = {};
    my $send = 0;
    my $receive = 0;
    my $tx_errors = 0;
    my $rx_errors = 0;
    while (my ($name, $value) = each(%{$perf})) {
        if ($name =~ /^(vif_[^_]+)_(.*)/) {
            $list->{$1} = {} if (!exists($list->{$1}));
            $list->{$1}->{$2} = $value->{$rolluptype};
        }
    }
    while (my ($name, $value) = each(%{$list})) {
        $send += $value->{tx} / 1024 if (exists($value->{tx}));
        $receive += $value->{rx} / 1024 if (exists($value->{rx}));
        $rx_errors += $value->{tx_errors} if (exists($value->{tx_errors}));
        $tx_errors += $value->{rx_errors} if (exists($value->{rx_errors}));
    }
    $send = simplify_number($send);
    $receive = simplify_number($receive);
    return "VM '" . $uuid . "' net: send = " . $send . " KBps, receive = " . $receive . " KBps, send errors = "  . $tx_errors . ", receive errors = " . $rx_errors;
}

sub vm_io_info {
    my ($uuid, $perf) = @_;
    my $list = {};
    my $read = 0;
    my $write = 0;
    my $read_latency = 0;
    my $write_latency = 0;
    while (my ($name, $value) = each(%{$perf})) {
        if ($name =~ /^vbd_([^_]+)_(.*)/) {
            $list->{$1} = {} if (!exists($list->{$1}));
            $list->{$1}->{$2} = $value->{$rolluptype};
        }
    }
    while (my ($name, $value) = each(%{$list})) {
        $read += $value->{read} / 1024 / 1024 if (exists($value->{read}));
        $write += $value->{write} / 1024 / 1024 if (exists($value->{write}));
        $read_latency += $value->{read_latency} if (exists($value->{read_latency}));
        $write_latency += $value->{write_latency} if (exists($value->{write_latency}));
    }
    $read = simplify_number($read);
    $write = simplify_number($write);
    return "VM '" . $uuid . "' disk io: read = " . $read . " MBps, write = " . $write . " MBps, read latency = "  . $read_latency . " ms, write latency = " . $write_latency . " ms";
}

my $epoch = (time() - 10); # Get the mettrics 10 sec metrics
my $xml = &request("http://$host/rrd_updates?start=$epoch");
my $struct = &parse_xml($xml);

foreach my $uuid (keys %{$struct->{vms}}) {
    my $perf = get_latest_perfdata($struct, $uuid);
    my $result = vm_cpu_info($uuid, $perf);
    print "$result\n";
    $result = vm_mem_info($uuid, $perf);
    print "$result\n";
    $result = vm_net_info($uuid, $perf);
    print "$result\n";
    $result = vm_io_info($uuid, $perf);
    print "$result\n";
}

