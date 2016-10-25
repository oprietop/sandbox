#!/usr/bin/perl
# Trying the xenapi http://docs.vmd.citrix.com/XenServer/6.0.0/1.0/en_gb/api/

use warnings;
use strict;
use RPC::XML::Client;
use Data::Dumper;

$RPC::XML::FORCE_STRING_ENCODING=1;

my %dom0 = ( 'POOL' => { HOST => 'localhost'
                       , USER => 'root'
                       , PASS => 'password'
                       , PORT => 443
                       }
           );

sub extractvalue {
    my ($val) = @_;
    $val->{'Status'} eq "Success" ? return $val->{'Value'} : print Dumper $val;
}

foreach my $host (sort keys %dom0) {
    my $xen = RPC::XML::Client->new("http://$dom0{$host}{HOST}:$dom0{$host}{PORT}");
    my $session = extractvalue($xen->simple_request( "session.login_with_password"
                                                   , $dom0{$host}{USER}
                                                   , $dom0{$host}{PASS})
                                                   ) or die "Failed on: $dom0{$host}{HOST}\n";

    my $ms_ref     = extractvalue($xen->simple_request("pool.get_all", $session));
    my $or         = @{$ms_ref}[0];
    my $master_ref = extractvalue($xen->simple_request("pool.get_master", $session, $or));
    my $pool       = extractvalue($xen->simple_request("pool.get_name_label", $session, $or));
    my $hosts_ref  = extractvalue($xen->simple_request("host.get_all", $session));
    foreach my $hostref (@{$hosts_ref}) {
        my $name = extractvalue($xen->simple_request("host.get_name_label", $session, $hostref));
        my $ip = extractvalue($xen->simple_request("host.get_address", $session, $hostref));
        $name .= " (MASTER)" if $hostref eq $master_ref;
        print "$name -> $ip\n";
    }

    my $vms_ref = extractvalue($xen->simple_request("VM.get_all_records", $session));
    print "$host on $dom0{$host}{HOST} ($pool):\n";
    foreach my $vm_ref (keys %{$vms_ref}) {
        my $vm = $vms_ref->{$vm_ref};
        next if $vm->{is_a_template};
        next if $vm->{is_control_domain};
        print "\t$vm->{name_label} - $vm->{uuid}\n";
#        printf( "%2s %6.6s %4.4s %36.36s %-50.50s\n"
#              , $vm->{name_label}
#              , $vm->{power_state}
#              , $vm->{VCPUs_max}
#              , $vm->{memory_dynamic_max}/1024/1024
#              , $vm->{domarch}
#              , $vm->{uuid}
#              , join(",", @{$vm->{tags}})
#              );
    }
}
