#!/usr/local/perl
# Fetch pool and member info using the SOAP api from a F5 device.
# https://devcentral.f5.com/wiki/iControl.LocalLB__Pool.ashx

use strict;
use warnings;

use SOAP::Lite;

my $host = 'hostname';
my $user = 'user';
my $pass = 'pass';
my $soap = SOAP::Lite
           -> uri("urn:iControl:LocalLB/Pool")
           -> proxy("https://$host/iControl/iControlPortal.cgi");

# Skip SSL certificate checks
$soap->{_transport}->{_proxy}->{ssl_opts}->{verify_hostname} = 0;

# Push the credentials into SOAP
sub SOAP::Transport::HTTP::Client::get_basic_credentials { return "$user" => "$pass"; };

# Avoid warnings on the typecast redefine, don't want to use the iControlTypeCast package
{
    no warnings 'redefine';
    sub SOAP::Deserializer::typecast {
        my ($self, $value, $name, $attrs, $children, $type) = @_;
        return $value || undef;
    }
}

# Handle SOAP responses
sub resp {
    my $response = shift;
    die $response->faultcode, " ", $response->faultstring, "\n" if $response->fault;
    return @{ $response->result };
}

# Fill our arrays
my @pool_list      = resp($soap->get_list);
my @pool_members   = resp($soap->get_member_v2(SOAP::Data->name(pool_names => [@pool_list]) ));
my @pool_status    = resp($soap->get_object_status(SOAP::Data->name(pool_names => [@pool_list]) ));
my @members_status = resp($soap->get_member_object_status( SOAP::Data->name(pool_names => [@pool_list])
                                                         , SOAP::Data->name(members    => [@pool_members])
                                                         )
                         );

# Process and print info
for my $i (0 .. $#pool_list) {
    my $pool = $pool_list[$i];
    print "> POOL '$pool'\n";
    my $pool_status = $pool_status[$i];
    print "\t| AVAILABILITY : ".$pool_status->{"availability_status"}."\n";
    print "\t| ENABLED      : ".$pool_status->{"enabled_status"}."\n";
    print "\t| DESCRIPTION  : ".$pool_status->{"status_description"}." \n";
    my @address_array = @{$pool_members[$i]};
    my @status_array = @{$members_status[$i]};
    foreach my $j (0 .. $#address_array) {
        my $address = $address_array[$j];
        my $member_status = $status_array[$j];
        print "\t\t+ MEMBER '".$address->{"address"}.":".$address->{"port"}."'\n";
        print "\t\t\t| AVAILABILITY : ".$member_status->{"availability_status"}."\n";
        print "\t\t\t| ENABLED      : ".$member_status->{"enabled_status"}."\n";
        print "\t\t\t| DESCRIPTION  : ".$member_status->{"status_description"}." \n";
    }
}
