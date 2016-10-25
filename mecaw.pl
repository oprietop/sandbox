#!/usr/bin/perl
#
use strict;
use warnings;
use LWP::UserAgent;
use HTTP::Request::Common;
use XML::Simple;
use Getopt::Long;

binmode(STDOUT, ":utf8");

my $host = 'cmdb.hostname.lol:8080';
my $key  = 'XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX'';

#{{{ parse arguments
$0 =~ s/.*\///g;
my %attrs   = ();
my %rels    = ();
my $verbose = 0;
my $ua      = LWP::UserAgent->new( agent         => 'Mac Safari' # I'm a cool web browser
                                 , timeout       => 5            # Idle timeout (Seconds)
                                 , show_progress => $verbose     # Fancy progressbar
                                 );

GetOptions ( 'attrs=s' => \%attrs
           , 'rels=s'  => \%rels
           , 'verbose' => \$verbose
           );

unless (@ARGV) {
    print "Usage: $0 <ci> --attr <key>=<value>\n";
    print "\t<ci>\tRequired. One of more CIs (case-insensitive) to query or update.\n";
    print "\t-attrs\tOptional. For each CI, change the Attribute <key> to <value>, it can be used multiple times to update at once.\n";
    print "\t-rels\tOptional. For each CI, add a relation to the CIs with the format '<Type of Relation>'='<Destination CI'>\n";
    print "\t-verbose\tOptional. Show XML queries and responses";
    exit 1;
}
#}}}
#{{{ sub trim
sub trim {
    my $str = shift;
    $str =~ s/^\s+|\s+$//g;
    return $str;
}
#}}}
#{{{ sub api_post
sub api_post {
    my $path      = shift || 'ci/list/all';
    my $input     = shift || '';
    my $operation = shift || 'read';
    my $response  = $ua->request( POST "http://$host/api/cmdb/$path"
                                , [ 'TECHNICIAN_KEY' => $key
                                  , 'OPERATION_NAME' => $operation
                                  , 'INPUT_DATA'     => $input
                                  , 'format'         => 'xml'
                                  ]
                                );
    print $response->decoded_content if $verbose;
    return XMLin($response->decoded_content) if $response->is_success;
}
#}}}
#{{{ sub parse_response
sub parse_response {
    my $res = shift;
    my %hash = ();
    my $totalRecords = $res->{response}->{operation}->{Details}->{'field-values'}->{totalRecords};
    if ($totalRecords and $totalRecords != 1 ) {
       print "Error: CI doesn't exist or there are multiple CIs with the same name.\n";
       return %hash
    }
    my @attribute_keys = map { $_->{content} } @{ $res->{response}->{operation}->{Details}->{'field-names'}->{name} };
    my @attribute_values = @{ $res->{response}->{operation}->{Details}->{'field-values'}->{record}->{value} };
    @hash{@attribute_keys} = @attribute_values;
    return %hash;
}
#}}}
#{{{ sub traverse_citype
sub traverse_citype {
    my ($hash, $base) = @_;
    $base = $hash->{'value'} unless $base;
    if (ref $hash->{'sub-record'} eq "HASH") {
        traverse_citype($hash->{'sub-record'}, $base);
    } elsif (ref $hash->{'sub-record'} eq "ARRAY") {
        map { traverse_citype($_, $base) } sort @{ $hash->{'sub-record'} };
    } else {
        return {$hash->{'value'} => $base};
    }
}
#}}}
#{{{ sub get_base_citype_hash
sub get_base_citype_hash {
    my $res = api_post('citype/list/all');
    my $root = $res->{response}->{operation}->{Details}->{'field-values'}->{record}->{'sub-record'};
    my %ci_rel = ();
    map { %ci_rel = (%ci_rel, %{ $_ } ) } map { traverse_citype($_) } sort @{ $root };
    return %ci_rel;
}
#}}}
#{{{ sub get_ci_info
sub get_ci_info {
    my $ci = shift;
    my $res = api_post("ci/$ci");
    return parse_response($res);
}
#}}}
#{{{ sub get_full_ci_info
sub get_full_ci_info {
    my $ci = shift;
    my %base_citypes = get_base_citype_hash;
    my %default_attributes = get_ci_info($ci);
    return unless $default_attributes{'CI Type'};
    my $base_citype = $base_citypes{$default_attributes{'CI Type'}} || $default_attributes{'CI Type'};
    print "$ci, $base_citype\n";
    my $xmlref = { 'citype' => [{ 'criterias' => [{ 'criteria' => [{ 'parameter' => [{ 'value' => [ $ci ]
                                                                                     , 'name'  => [{ 'compOperator' => 'IS'
                                                                                                   , 'content' => 'CI Name'
                                                                                                   }]
                                                                                     }]
                                                                  }]
                                                 }]
                                , 'returnFields' => [{ 'name' => [ '*' ] }]
                                , 'name' => [ $base_citype ]
                                }]
                 };
    my $xml = XMLout($xmlref, RootName => 'API');
    print $xml if $verbose;
    return parse_response(api_post('ci', $xml));
}
#}}}
#{{{ sub get_ci_relationships
sub get_ci_relationships {
    my $ci = shift;
    my $res = api_post("cirelationships/$ci");
    my $relationships = $res->{response}->{operation}->{Details}->{relationships}->{relationship};
    my %hash = ();
    return %hash unless $relationships;
    if ($relationships->{name} and $relationships->{ci}) {
        if ($relationships->{ci}->{name}) {
            $hash{$relationships->{name}}{$relationships->{ci}->{name}} = 1;
        } else {
            map {$hash{$relationships->{name}}{$_} = 1} keys %{ $relationships->{ci} };
        }
    } else {
        foreach my $k ( keys %{ $relationships } ) {
            if ($relationships->{$k}->{ci}->{name}) {
                $hash{$k}{$relationships->{$k}->{ci}->{name}} = 1;
            } elsif ($relationships->{$k}->{ci}) {
                map {$hash{$k}{$_} = 1} keys %{ $relationships->{$k}->{ci} };
            }
        }
    }
    return %hash;
}
#}}}
#{{{ sub update_ci
sub update_ci {
    my $ci = shift;
    my $is_odd  = scalar @_ % 2 == 1;
    return undef if $is_odd;

    my %default_attributes = get_ci_info($ci);
    return 'Failed while fetching default attributes' unless $default_attributes{'CI Type'};

    my %base_citypes = get_base_citype_hash;
    my $base_citype = $base_citypes{$default_attributes{'CI Type'}};
    my @parameters = ();
    foreach my $key (keys %attrs) {
        my $value = $attrs{$key};
        push(@parameters, { 'name ' => [ $key ], 'value' => [ $value ] });
    }
    my $xmlref = { 'citype' => [{ 'newvalue'  => [{ 'record'   => [{ 'parameter' => \@parameters }] }]
                                , 'criterias' => [{ 'criteria' => [{ 'parameter' => [{ 'name' => [{ 'compOperator' => 'IS'
                                                                                                  , 'content' => 'CI Name'
                                                                                                  }]
                                                                                     , 'value' => [ $ci ]
                                                                                     }]
                                                                   }]
                                                  }]
                               , 'name' => [ $base_citype ]
                               }]
                 };

    my $xml = XMLout($xmlref, RootName => 'API');
    print $xml if $verbose;
    my $resp = api_post('ci', $xml, 'update');
    return "\t$resp->{response}->{operation}->{result}->{message}";
}
#}}}
#{{{ sub add_relationship
sub add_relationship {
    my $ci = shift;
    my $is_odd  = scalar @_ % 2 == 1;
    return undef if $is_odd;
    my %rels= @_;
    foreach my $key (keys %rels) {
        my $value = $rels{$key};
        my %default_attributes = get_ci_info($ci);
        return 'Failed while fetching default attributes' unless $default_attributes{'CI Type'};
        my %base_citypes = get_base_citype_hash;
        my $base_citype = $base_citypes{$default_attributes{'CI Type'}} || $default_attributes{'CI Type'};
        my $xmlref = { 'records' => [{ 'relationships' => [{ 'addrelationship' => [{ 'relationshiptype' => [ $key ]
                                                                                   , 'relatedcis'       => [{ 'ci'     => [{ 'name' => [ $value ] }]
                                                                                                            , 'citype' => [ $base_citype ]
                                                                                                            }]
                                                                                   , 'toci'             => [ $ci ]
                                                                                   }]
                                                           }]
                                     }]
                     };
        my $xml = XMLout($xmlref, RootName => 'API');
        print $xml if $verbose;
        my $resp = api_post('cirelationships', $xml,'add');
        my $message = "$resp->{response}->{operation}->{result}->{message}\n";
        print $message;
        return 'error' unless $message =~ /success/;
    }
}
#}}}

my @failed = ();
foreach my $ci (@ARGV) {
    print "# $ci\n";
    if (%attrs) {
        print "- Attribute update:\n";
        my $result = update_ci($ci, %attrs);
        print "$result\n";
        push(@failed, $ci) unless $result =~ /Success/;
    }

    if (%rels) {
        print "- Add Relationships:\n";
        my $result = add_relationship($ci, %rels);
        push(@failed, $ci) if $result;
    } else {
        print "- Attributes list:\n";
        my %result = get_full_ci_info($ci) or next;
        map { print "\t'$_' -> '$result{$_}'\n"; } sort keys %result;
        my %rels = get_ci_relationships($ci) or next;
        print "- Direct Relationships:\n";
        foreach my $rel_type (keys %rels) {
            map { print "\t'$rel_type'='$_'\n"; } sort keys %{ $rels{$rel_type} };
        }
    }
}
print "\nFailed CIs: ".join(' ', @failed)."\n" if @failed;
