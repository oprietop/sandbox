#!/usr/bin/perl
# Trying the xenapi http://docs.vmd.citrix.com/XenServer/6.0.0/1.0/en_gb/api/

use warnings;
use strict;
use RPC::XML::Client;

$RPC::XML::FORCE_STRING_ENCODING=1;

my %dom0 = ( 'POOL' => { HOST => 'localhost'
                       , USER => 'root'
                       , PASS => 'password'
                       , PORT => 443
                       }
           );

sub extractvalue {
    my ($val) = @_;
    $val->{'Status'} eq "Success" ? return $val->{'Value'} : return undef;
}

foreach my $host (sort keys %dom0) {
    my $xen = RPC::XML::Client->new("http://$dom0{$host}{HOST}:$dom0{$host}{PORT}");
    my $session = extractvalue($xen->simple_request( "session.login_with_password"
                                                   , $dom0{$host}{USER}
                                                   , $dom0{$host}{PASS})
                                                   ) or die "Failed on: $dom0{$host}{HOST}\n";
    my $vms_ref = extractvalue($xen->simple_request("VM.get_all_records", $session));
    print "$host on $dom0{$host}{HOST}:\n";
    foreach my $vm_ref (keys %{$vms_ref}) {
        my $vm = $vms_ref->{$vm_ref};
        next if $vm->{is_a_template};
        next if $vm->{is_control_domain};
        printf( "%2s %6.6s %4.4s %36.36s %-50.50s\n"
              , $vm->{name_label}
              , $vm->{power_state}
              , $vm->{VCPUs_max}
              , $vm->{memory_dynamic_max}/1024/1024
              , $vm->{domarch}
              , $vm->{uuid}
              , join(",", @{$vm->{tags}})
              );
    }
}
