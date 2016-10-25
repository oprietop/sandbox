#!/usr/bin/perl -w
# Cross magicmarket's sellers that have a list of cards.
# Example: magiccardmarket.pl "Jokulhaups" "Obliterate" "Apocalypse"
# Obsolete since magicmarket has now his own way to do that.

use strict;
use warnings;
use LWP::UserAgent;
use HTTP::Request::Common;
use Storable;     # store, retrieve
use Term::ANSIColor qw(:constants);
$Term::ANSIColor::AUTORESET = 1;

my $stored = 0;
my %cards    = ();
my %sellers  = ();
my $args     = ($#ARGV+1);
$stored = 1 unless $args;
my @dontwant = ( 'World Championship Decks'
               , 'International Edition'
               , "Collectors' Edition"
               , 'Commander\'s Arsenal'
#               , 'Revised'
               , 'Fourth Edition'
               , 'Fifth Edition'
               , 'Sixth Edition'
               , 'Seventh Edition'
               , 'Eighth Edition'
               , 'Ninth Edition'
               , 'Foreign White Bordered'
               );
my $ua = LWP::UserAgent->new( agent         => 'Mac Safari'
                            , timeout       => 10
                            , show_progress => 1
                            );

# {{{ sub retrieve_hashes
sub retrieve_hashes() {
    print RED "Missing hashes!\n" and return 0 unless -r "$0.cards.hash" or -r "$0.cards.hash";
    print "Retrieving hashes...\n";
    %cards   = %{retrieve("$0.cards.hash")};
    %sellers = %{retrieve("$0.sellers.hash")};
    return 1;
}
# }}}
# {{{ sub write_hashes
sub write_hashes() {
    print "Storing hashes...\n";
    store(\%cards, "$0.cards.hash") or die "Can't write '$0.cards.hash'. The error was '$!'.\n";
    store(\%sellers, "$0.sellers.hash") or die "Can't write '$0.sellers.hash'. The error was '$!'.\n";
}
# }}}
# {{{ sub traverse_cmd
sub traverse_cmd() {
    my $count = 1;
    foreach my $arg (@ARGV) {
        print "#\n# ($count/$args) Looking for '";
        print GREEN BOLD $arg;
        print "'\n#\n";
        my $temp_hash = &fill_cards($arg);
        $cards{$temp_hash->{cardname}} = $temp_hash;
        $count++;
    }
}
# }}}
# {{{ sub fill_cards
sub fill_cards() {
    my $arg = shift;
    $arg =~ s/\s/+/g;
    my %tmphash = ();
    my $response = $ua->request( GET 'https://www.magiccardmarket.eu/?mainPage=showSearchResult&searchFor='.lc($arg) );
    my $uri = $response->request->uri;
    my $content = $response->content;
    if ($uri =~ /prod$/) {# *.prod urls are final result ones
        while ($content =~ /jpg"\salt="(.+?) \(([^\)]+)\)".+?Rarity:.+?alt="([^"]+)".+?Available items:.+?cell_0_1">(\d+)<.+?From \(EX\+\):.+?cell_1_1">(\d+),(\d+)\s/sg) {
            next unless $5;
            if (length($1) > length ($arg)) {
                print YELLOW "Result '$1' from '$2' is longer than '$arg'. Skiping...\n";
                next;
            }
            print BLUE "$2 [$3]. Got $4 from $5,$6 €\n";
            $tmphash{$2} = { expansion => $2
                         , rarity    => $3
                         , url       => "$uri"
                         , cardname  => $1
                         , available => $4
                         , from      => "$5.$6"
                         , content   => $content
                         };
        }
    } else { # The card is on various expansions
        while ($content =~ /showMsgBox\('(.+?)'\).+?alt="([^"]+)".+?"([^"]+)">([^<]+)<\/a>.+?>[^<]+<\/td>.+?>([^<]+)<\/td>.+?>(\d+),(\d+)\s[^<]+<\/td>/sg) {
            next unless $5;
            if (length($4) > length ($arg)) {
                print YELLOW "Result '$4' is longer than '$arg'. Skiping...\n";
                next;
            }
            print BLUE "$1 [$2]. Got $5 from $6,$7 €\n";
            $tmphash{$1} = { expansion => $1
                         , rarity    => $2
                         , url       => "https://www.magiccardmarket.eu/$3"
                         , cardname  => $4
                         , available => $5
                         , from      => "$6.$7"
                         , content   => 0
                         };
        }
    }

    unless (scalar keys %tmphash) {
        print RED "Could not find any result for ";
        print "'$arg'";
        print RED " in ";
        print "'$uri'\n";
        exit 1;
    }

    # Choose the cheaper expansion leaving aside the non tournament legal and unwanted ones
    my $cheap = 0;
    foreach my $key (sort { $tmphash{$a}{from} <=> $tmphash{$b}{from} } keys %tmphash) {
        next if $key ~~ @dontwant;
        next if $key =~ /^WCD\s\d{4}/; # WDC are gold-bordereded cards
        $cheap = $key unless $cheap;
    }
    print GREEN BOLD $tmphash{$cheap}{cardname};
    print GREEN " is cheaper on '$cheap' at $tmphash{$cheap}{from} €\n";
    return $tmphash{$cheap};
}
# }}}
# {{{ sub traverse_cards
sub traverse_cards() {
    my $count = 1;
    foreach my $card (sort { $cards{$b}{from} <=> $cards{$a}{from} } keys %cards) {
        print "# ($count/$args) Looking sellers for '";
        print GREEN BOLD $card;
        print "' from $cards{$card}{expansion}\n";
        my $temp_hash = &fill_sellers($card);
        print GREEN "Got ";
        print BOLD BLUE scalar keys %{$temp_hash};
        print GREEN " unique sellers.\n";
        $count++;
    }
}
# }}}
# {{{ sub fill_sellers
sub fill_sellers () {
    my $card = shift;
    my $content = $cards{$card}{content};
    unless ($content) {
        my $response = $ua->request( GET $cards{$card}{url} );
        $content = $response->content;
    }
    my $count = 0;
    # 80 -karmacrow- -40786- -Germany- -English- -Near Mint- -17,35- -1- --
    while ($content =~ /idInfoUser=\d+">([^<]+)<\/a> \((\d+)\).+?location: ([^']+)'.+?showLanguageChart[^']+'([^']+)'.+?showCardQualityChart[^']+'([^']+)'.+?>(\d+),(\d+)\s[^>]+<.+?st_ItemCount[^>]+>(\d+)</sg) {
        $count++;
        $sellers{$1}{sells} = $2;
        $sellers{$1}{country} = $3;
        $sellers{$1}{have}{$card}{reference} = { %{$cards{$card}} };
        $sellers{$1}{have}{$card}{count}{$count} = { cardlang  => $4
                                                   , cardstate => $5
                                                   , cardprice => "$6.$7"
                                                   , cardqty   => $8
                                                   };
        $sellers{$1}{have}{$card}{hits} = scalar keys %{$sellers{$1}{have}{$card}{count}};
        $sellers{$1}{hits} = scalar keys %{$sellers{$1}{have}};
        $sellers{$1}{total} = 0;
    }
    return \%sellers;
}
# }}}
# {{{ sub pricelist
sub pricelist() {
    my $utopicprice = 0;
    print "#\n# Pricelist.\n#\n";
    foreach my $card (sort { $cards{$b}{from} <=> $cards{$a}{from} } keys %cards) {
        print BOLD BLUE "$cards{$card}{from} €\t'";
        print BOLD GREEN $card;
        print "' $cards{$card}{rarity} from '$cards{$card}{expansion}'\n";
        $utopicprice += $cards{$card}{from};
    }
    print GREEN "The utopic price for everything is ";
    print BOLD BLUE "$utopicprice €\n";
}
# }}}
# {{{ sub sellerlist
sub sellerlist() {
    my $items = scalar keys %cards;
    print "#\n# Full Seller List from $items items.\n#\n";
    my $cut = ($items/3); # I'll be skipping sellers with only 1/3 hits of our total items if total > 2
    my $ceiling = int($cut) + ($cut != int($cut)); # rounded up
    foreach my $sname (sort { $sellers{$b}{hits} <=> $sellers{$a}{hits} } keys %sellers) {
        if ($items > 2 and $sellers{$sname}{hits} <= $ceiling) {
            delete $sellers{$sname}; # Remove the unwanted sellers from the hash
            next;
        };
        my $total = 0;
        print "$sellers{$sname}{hits} $sname ($sellers{$sname}{sells}) $sellers{$sname}{country}\n";
        foreach my $card (sort keys %{$sellers{$sname}{have}}) {
            print "\t$card $sellers{$sname}{have}{$card}{hits} ($sellers{$sname}{have}{$card}{reference}{from} €)\n";
            my %hitshash = %{$sellers{$sname}{have}{$card}{count}};
            my $cheaper = 0;
            foreach my $hit (sort { $hitshash{$a}{cardprice} <=> $hitshash{$b}{cardprice} } keys %hitshash) {
                unless ($cheaper) { # Get the cheaper one, but favor english if same price
                    $cheaper = $hitshash{$hit}{cardprice};
                    $sellers{$sname}{have}{$card}{cheaper} = $hit;
                } elsif ($hitshash{$hit}{cardprice} == $cheaper and $hitshash{$hit}{cardlang} eq "English") {
                    $cheaper = $hitshash{$hit}{cardprice};
                    $sellers{$sname}{have}{$card}{cheaper} = $hit;
                }
                print "\t\t$hitshash{$hit}{cardstate}, $hitshash{$hit}{cardlang} ($hitshash{$hit}{cardqty}) $hitshash{$hit}{cardprice} €\n";
            }
            $total += $cheaper;
        }
        $sellers{$sname}{total} = $total;
        print "$total €\n"
    }
}
# }}}
# {{{ sub sellerbrief # ph34r the hash double sort
sub sellerbrief() {
    print "#\n# Brief Seller List from ".(scalar keys %cards)." items.\n#\n";
    foreach my $sname (sort { $sellers{$b}{hits} <=> $sellers{$a}{hits} || $sellers{$a}{total} <=> $sellers{$b}{total} } keys %sellers) {
        print BOLD BLUE "$sellers{$sname}{hits} hits ";
        print BOLD GREEN "$sellers{$sname}{total} €";
        print "\t$sname ($sellers{$sname}{sells}) $sellers{$sname}{country}\n";
    }
}
# }}}

# Do Stuff
$stored = &retrieve_hashes if $stored; # if stored retrieve_hashes fails we'll set $stored to false
&traverse_cmd   unless $stored;
&traverse_cards unless $stored;
&write_hashes   unless $stored;
&pricelist;
&sellerlist;
&sellerbrief;
exit 0;
