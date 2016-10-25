#!/usr/bin/perl
# http://wiki.thorx.net/wiki/DiscID
# http://ftp.freedb.org/pub/freedb/latest/CDDBPROTO
# http://www.sourcefiles.org/Multimedia/MP3/Tools/Rippers/ripx-0.10.pl
# http://freedb.freedb.org/~cddb/cddb.cgi?cmd=cddb+query+$args&hello=joe+my.host.com+xmcd+2.1&proto=5
# http://vgmdb.net/cddb/en?cmd=cddb+query+$args

use strict;
use warnings;
use utf8;
use Encode;
use Audio::FLAC::Header;    # sub create_discid(@)
use LWP::UserAgent;         # sub http($$$)
use HTTP::Cookies;          # Cuquis
use HTML::Entities;         # decode_entities
use Data::Dumper;
use Term::ANSIColor qw(:constants colored);
$Term::ANSIColor::AUTORESET = 1;

my %cddb_hosts = ( VGMDB       => 'http://vgmdb.net/cddb/en'
                 , FREEDB      => 'http://freedb.freedb.org/~cddb/cddb.cgi'
                 , GRACENOTE   => 'http://cddb.cddb.com/~cddb/cddb.cgi'
                 , MUSICBRAINZ => 'http://freedb.musicbrainz.org/~cddb/cddb.cgi'
                 );
my $cddb_handshake = '&hello=joe+my.host.com+xmcd+2.1&proto=6';

#{{{    sub boxify
sub boxify($$) {
    my $text  = shift || 'BOX';
    my $color = shift || 'reset';
    $text =~ s/[\n\r]//g;
    print colored ("#"x(length($text)+4)."\n# ", $color);
    print colored ("$text", "$color BOLD");
    print colored (" #\n"."#"x(length($text)+4)."\n", $color);
}
#}}}
#{{{    sub get_flacs_from_dir
sub get_flacs_from_dir($) {
    my $dir = shift;
    return 0 unless -d $dir;
    opendir(DIR, $dir) || print RED "can't opendir '$dir':w: $!\n";
    my @files=map {"$dir/$_"} grep { !/^\.+$/ && /^.*flac$/i } readdir(DIR);
    closedir DIR;
    return @files
}
#}}}
#{{{    sub http_get
sub http_get($$$) {
    my $url     = shift || return 0;
    my $ua = LWP::UserAgent->new;
    $ua->agent('Mozilla/5.0');
    my $req = HTTP::Request->new('GET' => $url);
    $req->content_type('application/x-www-form-urlencoded');
    my $res = $ua->request($req);   # Pass request to the User Agent and get a response back
    $res->is_success ? return $res : return $res->status_line
}
#}}}
#{{{    sub create_discid
sub create_discid(@) {
    my ($track_count, $current_seconds, $current_offset, $mod10_sum)=(0, 0, 150, 0);
    my @offsets = ();
    foreach (sort {$a cmp $b} @_) {
        my $flac = Audio::FLAC::Header->new($_);
        my $info = $flac->info();
        $track_count++;
        push(@offsets, $current_offset);
        $current_seconds += ($current_offset/75);
        $current_offset += (($info->{TOTALSAMPLES}/$info->{SAMPLERATE})*75);
        my $mod10 = 0;
        while ($current_seconds>0) {
            $mod10 += ($current_seconds%10);
            $current_seconds = int($current_seconds/10);
        }
        $mod10_sum += $mod10;
    }
    return ( discid      => sprintf("%.2x%.4x%.2x", ($mod10_sum%255) , (int($current_offset/75)-2), $track_count)
           , track_count => $track_count
           , offsets     => [@offsets]
           , total_time  => int($current_offset/75)
           );
}
#}}}
#{{{ sub query_cddb
sub query_cddb(%) {
    my $cddb_info = shift;
     my $cddb_query = "$cddb_info->{discid}+$cddb_info->{track_count}+".join('+',@{$cddb_info->{offsets}})."+$cddb_info->{total_time}\n";
    my @hits = ();
    foreach my $host (sort keys %cddb_hosts) {
        boxify($host,'BLUE');
        my $response = &http_get("$cddb_hosts{$host}?cmd=cddb+query+$cddb_query$cddb_handshake");
        my @response_results = &parse_cddb_response($response, 'query');
        foreach (@response_results) {
            $response = &http_get("$cddb_hosts{$host}?cmd=cddb+read+$_->{category}+$_->{discid}$cddb_handshake");
            my @cddb_read_responses = &parse_cddb_response($response, 'read');
            next unless $cddb_read_responses[0];
            $cddb_read_responses[0]{_SERVER} = $host;
            push(@hits, @cddb_read_responses);
        }
    }
    return @hits;
}
#}}}
#{{{    sub parse_cddb_response
sub parse_cddb_response($) {
    my $response = shift;
    my $type     = shift || 'query';
    my @result = ();
    if (ref($response) eq "HTTP::Response" and $response->is_success) {
        my $page = decode_entities($response->decoded_content);
        $page = encode('utf-8', $page);
        $page =~ s/^\s*[\r\n]+//mg; # Remove whitelines
        $page =~ m/^(\d+)\s(.+)$/s || die RED "response code regexp failed";
        my $cddb_resp_code = $1;
        $page = $2;
        if ($cddb_resp_code == 202) {
            print BOLD YELLOW "$cddb_resp_code";
            $page =~ s/[\r\n]//g;
            print YELLOW " $page\n";

        } elsif ($cddb_resp_code <= 211) {
            print BOLD GREEN "$cddb_resp_code";
            if ($type eq 'query') {
                while ($page =~ /([^\s]+?)\s(\w{8})\s([^\n]+)/sg) {
                    print GREEN "\t$1 $2 $3\n";
                    push @result, { category    => $1
                                  , discid      => $2
                                  , album_title => $3
                                  };
                }
            } elsif ($type eq 'read') {
                my %cddb_hash = ();
                my ($songs, $artist_on_track) = (0, 0);
                while ($page =~ /([A-Z\d]+)=([^\r\n]+)/sg) {
                    my ($key, $value) = ($1, $2);
                    $cddb_hash{$key} = $value;
                    if (substr($key,0,6) eq 'TTITLE') {
                        $songs++;
                        $artist_on_track++ if $value =~ /\//;
                     }
                }
                print GREEN " Hashing $cddb_hash{DISCID} $cddb_hash{DTITLE}\n";
                $cddb_hash{_TRACKS} = $songs;
                $cddb_hash{_VA} = $songs if $songs == $artist_on_track;
                push @result, \%cddb_hash if $cddb_hash{TTITLE0};
            }
        } else {
            print BOLD RED "$cddb_resp_code\n";
            print RED $page;
        }
    }
    return @result;
}
#}}}

#
#    main foreach
#
foreach my $dir (@ARGV) {
    my @files = &get_flacs_from_dir($dir);
    my %current_disc = &create_discid(@files);
    my @cddb_results = &query_cddb(\%current_disc);
    foreach my $hit (@cddb_results) {
        print Dumper $hit;

    };
}
