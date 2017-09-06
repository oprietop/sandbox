#!/usr/local/bin/perl
# This will search for flac files on directories then will try to copy/tag them in the current directory via direct http queries to vgmdb.net, (or not).
#my $content ="action=advancedsearch&albumtitles=Valkyrie+Profile+Covenant+of+the+Plume+Arrange+Album&catalognum=&composer=&arranger=&performer=&lyricist=&publisher=&game=&trackname=&notes=&anyfield=&releasedatemodifier=is&day=0&month=0&year=0&discsmodifier=is&discs=&albumadded=&albumlastedit=&scanupload=&tracklistadded=&tracklistlastedit=&sortby=albumtitle&orderby=ASC&childmodifier=0&dosearch=Search+Albums+Now";

use strict;
use warnings;
use utf8;
use Encode;
use Audio::FLAC::Header;    # Para sub hashfiles(@)
use LWP::UserAgent;         # Para sub http($$$)
use HTTP::Cookies;          # Cuquis
use HTML::Entities;         # Para decode_entities
use File::Copy;             # para copy en &rename
use Data::Dumper;
use Getopt::Long qw(:config bundling);
use Term::ANSIColor qw(:constants);
$Term::ANSIColor::AUTORESET = 1;

$0 =~ s/.*\///g;
my $username   = 'XXXXXXXXXX';
my $password   = 'XXXXXXXXXX';
my $force      = 0;
my $ktitle     = 0;
my $id         = 0;
my $threshold  = 5;
my $filelength = 255;
my %cd=();
my %vgm=();
my @catnums=();
my @log=();
my $vgmuserid  = 0;
my $cookie_jar = HTTP::Cookies->new( autosave => 1 );
$cookie_jar->set_cookie(0, 'gfa_nsfw', 'show', '/', 'vgmdb.net', 80);

GetOptions ( 'force=i'     => \$force
           , 'ktitle'      => \$ktitle
           , 'id=i'        => \$id
           , 'threshold=i' => \$threshold
           );

unless (@ARGV) {
    print <<EOF;
Usage: $0 <DIR1> <DIR2> ...
$0 will or won't:
1) Search on every DIR for flac files.
2) Launch a query to vcgmdb.net based on DIR's name.
3) Crawl through all results looking for the matching disc based on the length of each track.
4) If a match is found, it will copy and itag the files in the current directory
5) The schema is: ALBUM [CATALOG NUMBER]/TRACK_NUMBER - TITLE.flac

$0 Requires Audio::FLAC::Header and LWP::UserAgent.
EOF
exit 1;
}

$) = 2222;
$> = 2222;
print "Current Effective UID: $>\n";
print "Current Effective GID: $)\n";

#{{{    sub dprint
sub dprint {
    my ($line) = @_;
    print $line;
    push(@log, $line);
}
#}}}
#{{{    sub error
sub error($) {
    my $message = shift;
    chomp ($message);
    dprint RED BOLD "#\n#\t$message\n#\n";
    open(LOG, ">> errors.txt") || die "Can't redirect stdout";
    print LOG scalar localtime()." # $message\n";
    close(LOG);
}
#}}}
#{{{    sub http
sub http($$$) {
    my $url     = shift || return 0;
    my $method  = shift || "GET";
    my $content = shift || 0;
    my $referer = shift || '127.0.0.1';

    my $ua = LWP::UserAgent->new;   # User Agent creation
    $ua->agent('Mozilla/5.0');      # IMMAFAKE
    $ua->cookie_jar( $cookie_jar ); # We should have a jar somewhere
    my $req = HTTP::Request->new($method => $url); # Create a request
    $req->content_type('application/x-www-form-urlencoded');
    $req->referer($referer);
    $req->content($content) if $content;
    my $res = $ua->request($req);   # Pass request to the User Agent and get a response back
    # We'll use the whole response hash if OK, manily for $res->decoded_content and $res->headers.
    $res->is_success ? return $res : return $res->status_line
}
#}}}
#{{{    sub authenticate
sub authenticate() {
   return 0 unless $username and $password;
   dprint YELLOW "Trying to authenticate to vgmdb.net... ";
   if ($vgmuserid) {
       dprint BOLD GREEN "Using existing cookie.\n";
       return $vgmuserid;
   }
   &http( 'http://vgmdb.net/forums/login.php'
        , 'POST'
        , "vb_login_username=${username}&cookieuser=1&vb_login_password=${password}&securitytoken=guest&do=login"
        );
    $vgmuserid = $cookie_jar->{'COOKIES'}->{'vgmdb.net'}->{'/'}->{'vgmuserid'}->[1];
    if ($vgmuserid) {
        dprint BOLD GREEN "OK!\n";
        return $vgmuserid;
    } else {
        dprint BOLD RED "NOK!,"; dprint " We won't be able to fetch artwork,\n";
        return 0;
    }
}
#}}}
#{{{    sub prepareresp
sub prepareresp(%) {
    my $resp = shift;
    if (ref($resp) eq "HTTP::Response" and $resp->is_success) {
        my $page = decode_entities($resp->decoded_content);
        $page = encode('utf-8', $page);
        return $page;
    } else {
        return $resp;
    }
}
#}}}
#{{{    sub savefile
sub savefile($$$) {
    my $url      = shift || return 0;
    my $filename = shift || 'folder';
    my $dir      = shift || '.';
    unless (-f "$dir/$filename") {
        mkdir "$dir" unless -d $dir;
        my $resp = &http($url, "HEAD"); # Only get the headers, then download the file IF necessary.
        if (ref($resp) eq "HTTP::Response" and $resp->is_success) {
            my %my_content_types = ( 'image/gif'  => 'gif'
                                   , 'image/jpeg' => 'jpg'
                                   , 'image/png'  => 'png'
                                   , 'image/tiff' => 'tif'
                                   , 'text/html'  => 'html'
                                   );
            my $headers = $resp->headers;
            my $content_length = $headers->{'content-length'};
            my $extension = $my_content_types{$headers->{'content-type'}};
            unless ($extension) {
                &error("Can't find '$headers->{'content-type'}' in our content-type hash when fetching '$url' to write '$filename'");
                return 0;
            }
            my $ffile = "$dir/$filename.$extension";
            my $bytes = -s "$ffile";
            if ($bytes and $bytes == "$content_length") {
                dprint YELLOW BOLD "The file '$filename.$extension' ($content_length bytes)' already exists, skipping!\n";
                return 0;
            }
            dprint YELLOW "Downloading '$filename.$extension' ($content_length bytes) from: "; dprint "'$url'... ";
            my $resp = &http($url); # Now we get the full response via GET
            if (ref($resp) eq "HTTP::Response" and $resp->is_success) {
               open (IMG, "> $ffile") || die "Can't redirect stdout to $ffile";
               print IMG $resp->decoded_content;
               close (IMG);
               $bytes = -s "$ffile";
               if ("$bytes" == "$content_length") {
                   dprint BOLD GREEN "OK! ($bytes bytes).\n";
                   return $bytes;
               } else {
                   &error("NOK! '$filename.$extension' should be $content_length bytes but we got $bytes!");
                   return 0;
               }
            } else {
               &error("The response from '$url' using GET to write '$ffile' wasn't succesfull.");
               return 0;
            }
        } else { # if
           &error("The response from '$url' using HEAD to write '$filename' wasn't succesfull.");
           return 0;
        }
    } # unless
} # sub
#}}}
#{{{    sub escapename
sub escapename($$) { # http://kobesearch.cpan.org/htdocs/File-Util/File/Util.pm.html#escape_filename-
    my($file,$escape,$also) = @_;
    return '' unless defined $file;
    $escape = '-' if !defined($escape);
    if ($also) { $file =~ s/\Q$also\E/$escape/g }
    my $DIRSPLIT    = qr/[\x5C\/\:]/;
    my $ILLEGAL_CHR = qr/[\x5C\/\|\r\n\t\013\*\"\?\<\:\>]/;
    $file =~ s/$ILLEGAL_CHR/$escape/g;
    $file =~ s/$DIRSPLIT/$escape/g;
    return $file;
}
#}}}
#{{{    sub hashfiles
sub hashfiles(@) {
    %cd=();
    my $curalbum = "NULL";
    my $count=1;
    foreach (sort {$a cmp $b} @_) {
        my $flac = Audio::FLAC::Header->new($_);
        my $info = $flac->info();
        my $tags = $flac->tags();
        my $secsre = $info->{TOTALSAMPLES} / $info->{SAMPLERATE};
        $secsre =~ s/\.\d+$//g;
        my $secs = sprintf ("%.2d:%.2d", $secsre/60%60, $secsre%60);
        my $tnumber = "";
        $tnumber = $count unless $tnumber =~ /^\d\d$/;
        $tnumber = sprintf ("%02d", $tnumber) if length($tnumber) == 1;
        $count++;
        $cd{$tnumber} = {  TIME   => $secs
                        ,  TIMES  => $secsre
                        ,  FNAME  => $_
                        };
        map {$cd{$tnumber}{uc($_)} = $tags->{$_}} keys  %{ $tags };
        $curalbum = $tags->{ALBUM} || $tags->{album} || "";
    }
    dprint BLUE BOLD "\n"."=" x (23+length($curalbum)+length(keys(%cd)))."\n";
    dprint BLUE BOLD "Album: '$curalbum' with ".keys(%cd)." tracks.\n";
    dprint BLUE BOLD "=" x (23+length($curalbum)+length(keys(%cd)))."\n\n";
    dprint GREEN "TRK TITLE                                        TIME  YEAR GENRE       ARTIST\n";
    dprint GREEN "=" x (80)."\n";
    foreach (sort {$a <=> $b} keys %cd ){
        next unless ref($cd{$_}) eq "HASH";
            dprint sprintf ("%-3.3s %-44.44s %5.5s %4.4s %-10.10s %-16s \n", $_, $cd{$_}{TITLE}, $cd{$_}{TIME}, $cd{$_}{DATE}, $cd{$_}{GENRE}, $cd{$_}{ARTIST});
    } # foreach %cd
    dprint GREEN "=" x (80)."\n";
} # sub hashfiles
#}}}
#{{{   sub vgmdbsearch
sub vgmdbsearch($) {
    my $album = shift;
    dprint YELLOW "\nOur DirName: '$album'\n";
    $album =~ s/^.*?\s-\s\d{4}\s-\s/+/g;
    $album =~ s/\sdis[kc]|ost|cd\w/+/gi;
    $album =~ s/[\[\{\(].*?[\)\}\]]/+/gi;
    $album =~ s/\++/+/g;
    $album =~ s/\+*$//g;
    dprint YELLOW "Parsed Name: '$album'\n";
    dprint BLUE BOLD "\n"."=" x (23+length($album))."\n";
    dprint BLUE BOLD "Querying VGMDB with: '$album'\n";
    dprint BLUE BOLD "=" x (23+length($album))."\n";
    my $response = &http('http://vgmdb.net/search?do=results', 'POST', "action=advancedsearch&albumtitles=$album&sortby=release&orderby=ASC&childmodifier=1",'http://vgmdb.net/search');
    my $page = decode_entities($response->decoded_content);
    $page = encode('utf-8', $page); # A lo bestia.
    my %results=();
    dprint GREEN "\nCATALOG NUM    ID   YEAR TYPE                  NAME\n";
    dprint GREEN "=" x (80)."\n";

    my %types = ( 'album-game'    => 'Official Release'
                , 'album-bonus'   => 'Enclosure / Promo'
                , 'album-doujin'  => 'Doujin / Fanmade'
                , 'album-works'   => 'Works'
                , 'album-anime'   => 'Video / Animation & Film'
                , 'album-demo'    => 'Demo Scene'
                , 'album-bootleg' => 'Bootleg'
                , 'album-drama'   => 'Drama'
                , 'album-print'   => 'Other'
                , 'album-cancel'  => 'Cancelled Release'
                );

    while ($page =~ /<span class="catalog ([^"]+)">(.+?)<\/span>.+?\/album\/(\d+)" title=.(.+?).>.+?(\d+)(?:|<\/a>)<\/td><\/tr>/sg ) {
        dprint sprintf ("%-13.13s %5.5s %4.4s %-21.21s %s \n", $2, $3, $5, $types{$1}, $4);
#        next unless $3 == 657;
        $results{$3} = {title =>$4, type =>$1};
    }
    dprint GREEN "=" x (80)."\n";
    return \%results;
}
#}}}
#{{{    sub vgmid
sub vgmdbid(@) {
    %vgm=();
    $vgm{ID}= shift;
    $vgm{TYPE}= shift;
    $vgm{URL}="http://vgmdb.net/album/$_";
    my $page = &prepareresp(&http($vgm{URL}));

    if ($page =~ /<div id="coverart".+?style="background-image: url\(\'([^\']+)\'/) {
    #if ($page =~ /<img id="coverart" style="background-image: url\(\'([^\']+)\'/) {
        $vgm{COVER}=$1;
        dprint BLUE BOLD "Cover Art:\t"; dprint "'$vgm{COVER}'\n";
    }

    if (my ($coverlist) = $page =~ /<div class="covertab" id="cover_list" style="[^"]+">(.+?)<\/div>/s) {
        while ($coverlist =~ /<a href="([^"]+)">([^<]+)<\/a>/sg){
            my ($url, $name) = ($1, $2);
            $name = &escapename($name, '-');
            $name =~ s/\s/_/g;
            my ($imgid) = $url =~ /(\d+)$/;
            # IMG Example: http://vgmdb.net/db/covers-full.php?id=106034
            $vgm{SCANS}{$name} = "http://vgmdb.net/db/covers-full.php?id=$imgid";
            dprint BLUE BOLD "Scan:\t"; dprint "'$name' => http://vgmdb.net/db/covers-full.php?id=$imgid\n";
        }
    }

    if ($page =~ /<span class="albumtitle" lang="en" style="display:inline">(.*?)<\/span>/) {
        dprint MAGENTA BOLD "\n"."=" x length($1)."\n";
        dprint MAGENTA BOLD "$1\n";
        dprint MAGENTA BOLD "=" x length($1)."\n\n";
        $vgm{ALBUM}=$1;
    }
    if ($page =~ /<div style="padding: 10px" class="smallfont">(.+?)<\/div>/) {
        $vgm{NOTES}=$1;
        $vgm{NOTES} =~ s/<br \/>/\n/g;
        $vgm{NOTES} =~ s/[\xa0\xc2]+/\t/g;
    }
    while ($page =~ /<div id="rightfloat"(.*?)<\/div><\/div>/sg){
        my $asd = $1;
        $asd =~ s/[\n\r]//g;    # Oneline pls
        $asd =~ s/<script.*?\/script>//g;   # Noscript
        $asd =~ s/\s*<[^>]+[^b]>//g;   # Fuera tags html excepto b limpiando espacios a la izquierda
        while ($asd =~ />([^<]+)<\/b>([^<]+)</sg) {
            dprint BLUE BOLD "$1:\t";
            dprint "'$2'\n";
            $vgm{$1} = $2;
        }
    }

    @catnums=();
    if ($vgm{'Media Format'} and $vgm{'Media Format'} =~ /^(\d+).*$/) { ;
        $vgm{TOTALDISCS} = $1;
    } else {
        $vgm{TOTALDISCS} = 1;
    }

    if ( $vgm{'Catalog Number'} =~ /(\w+\W)(\d+)~(\d+)$/) {
        my $pref = $1;
        my $last = substr($2, 0, -length($3))."$3";
        foreach ($2..$last) {
            push (@catnums, "$pref$_");
        }
    } else {
        if ($vgm{TOTALDISCS} == 1) {
            push (@catnums, $vgm{'Catalog Number'});
        } else {
            foreach (1..$vgm{TOTALDISCS}) {
                push (@catnums, "$vgm{'Catalog Number'} Disc ".sprintf ("%02d", $_));
            }
        }
    }

    my @result = split('\n', $page);
    my ($disc,$track,$name,$time,$secs)=();
    foreach (@result) {
        if ($_ =~ /<b>Disc\s(\d+)/) {
            $disc="$1";
            dprint MAGENTA BOLD "\n\tDisc $disc, Cat Number: $catnums[$disc-1]\n\n";
            dprint GREEN "TRK TITLE                                                          TIME    SECS\n";
            dprint GREEN "=" x (80)."\n";
        }
        $track = $1 if $_ =~ /class="smallfont"><span class="label">(\d+)<\/span><\/td>.$/;
        $name  = decode_entities($1) if $_ =~ /class="smallfont" width="100%">(.*?)<\/td>.$/;
        if ( $_ =~ /class="time">([\d:]*)<\/span><(?:\/td|div)/ ) {
            my $time = $1;
            if ($time =~ /(\d+):(\d+)/) {
                $secs = ($1*60)+$2;
            } else {
                $time="NULL";
                $secs=0;
            }
            dprint sprintf ("%-3.3s %-62.62s %-8.8s %-4.4s\n", $track, $name, $time, $secs);
            next if $name =~ /data track/i;
            next unless $secs or $force;
            $vgm{"CD$disc"}{$track} = { TITLE => $name
                                      , TIME  => $time
                                      , SECS  => $secs
                                      };
            ($track,$name)=(0,0);
        }
        if ( $_ =~ /\s+<span class="time">([\d:]+)<\/span>/ ) {
            dprint GREEN "=" x 59; dprint YELLOW BOLD " Disc Length = $1\n";
        }

        last if $_ =~ /<\/h4><\/span>/;
    } #foreach @result
} # sub vgmdbtitle
#}}}
#{{{    sub compare
sub compare() {
    dprint BLUE BOLD "\n"."=" x (39)."\n";
    dprint BLUE BOLD "Comparing last results with our tracks:\n";
    dprint BLUE BOLD "=" x (39)."\n\n";
    foreach my $vgmcd (sort keys %vgm) {
        next if ($force and "CD${force}" ne "$vgmcd");
        next unless ref($vgm{$vgmcd}) eq "HASH" and $vgmcd =~ /^CD\d+$/; # Only the CDX hashes
        my $mark=0;
        my %current = %{$vgm{$vgmcd}};
        dprint "$vgmcd has ".keys(%current)." tracks and I got ".keys(%cd)." files...\t";
        if (keys(%current) ne keys(%cd) and not $force) {
            dprint RED BOLD "SKIPPING\n";
            next;
        } else {
            dprint GREEN BOLD "OK!\n";
            dprint GREEN "\n  This CD -> Our Files:\n=========================\n";
            foreach (sort { $a <=> $b } keys %cd) {
                $current{$_}{SECS} = 0 unless $current{$_}{SECS};
                $current{$_}{TIMES} = 0 unless $current{$_}{TIMES};
                dprint sprintf ("(%02d) % 4d -> (%02d) % 4d ", $_, $current{$_}{SECS}, $_, $cd{$_}{TIMES});
                my $subs = $current{$_}{SECS} - $cd{$_}{TIMES};
                $cd{$_}{NTITLE} = $current{$_}{TITLE} || $cd{$_}{TITLE};
                if ($subs == 0) {
                    dprint GREEN BOLD "(0 secs) OK!\n";
                } elsif ($subs > 0 and $subs < $threshold) {
                    dprint YELLOW BOLD "($subs secs) OK!\n";
                } elsif ($subs < 0 and $subs > -$threshold) {
                    dprint YELLOW BOLD "($subs secs) OK!\n";
                } else {
                    dprint RED BOLD "($subs secs) NOK!\n";
                    $mark=1;
                }
            }
            if ($mark and not "CD${force}" eq "$vgmcd") {
                dprint RED BOLD"\n$vgmcd FAILED!\n";
            } else {
                dprint GREEN BOLD "\nOK! '";
                dprint "$vgm{ALBUM}";
                dprint GREEN BOLD "' passed our requirements!\n";
                $vgmcd =~ s/\D//g;
                return $catnums[$vgmcd-1] || 'Extra Disc';
            }
        }
    } # foreach keys %vgm
    return 0;
} # compare
#}}}
#{{{    sub rename
sub rename($) {
    dprint BLUE BOLD "\n"."=" x (20)."\n";
    dprint BLUE BOLD "Copying and Tagging:\n";
    dprint BLUE BOLD "=" x (20)."\n\n";
    my $vgmcd = shift;
    my $cdnum = 1;
    foreach (@catnums) {
        last if $_ eq $vgmcd;
        $cdnum++;
    }
    my $dir   = shift;
    my $basedir = "$vgm{ALBUM} [$vgm{'Catalog Number'}]";
    $basedir =~ s/[\/:|]/,/g;
    $basedir =~ s/"/'/g;
    $basedir =~ s/ , /, /g;
    $basedir =~ s/[\*?<>]//g;
    $basedir =~ s/\s+/ /g;
    $basedir = &escapename($basedir, '-');
    dprint YELLOW "Base directory to create/use: "; dprint "'$basedir'\n";
    mkdir "$basedir" unless -d $basedir;
    my $cddir = $basedir;
    my $albumname = "$vgm{ALBUM} [$vgm{'Catalog Number'}]";
    if ( $#catnums > 0 ) {
        $cddir = "$basedir/".sprintf ("Disc_%.2d", $cdnum);
        $albumname = "$vgm{ALBUM} [$vgmcd]";
        mkdir $cddir;
    }

    foreach my $track (sort {$a<=>$b} keys %cd) {
        # Header
        dprint "\n / Inside "; dprint BLUE BOLD "'$cddir'\n";

        # Fill the tracknumber with zeroes
        my $zerofill = length(scalar keys %cd);
        my $ztrack = sprintf("%0${zerofill}d", $track);

        # Prepare/sanitize our title nam
        $cd{$track}{NTITLE} = $cd{$track}{TITLE} if $ktitle and $cd{$track}{TITLE};
        $cd{$track}{NTITLE} = &escapename($cd{$track}{NTITLE}, '-');
        $cd{$track}{NTITLE} =~ s/[\/:|]/, /g; # and proper
        $cd{$track}{NTITLE} =~ s/\s+/ /g;     # formatting

        # Check if the file is short enough, trim if necessary
        my $titlelength = length($cd{$track}{NTITLE}) + (9);
        if ($titlelength > $filelength) {
            my $excess = ($titlelength - $filelength + 9);
            dprint " | "; dprint YELLOW BOLD "We will be adding up to 9 extra chars: 'XXX <name>.flac' so the length will be $titlelength chars, longer than (filelength).\n";
            dprint " | "; dprint YELLOW BOLD "The song's name needs to be shortened $excess characters.\n";
            $cd{$track}{NTITLE} = substr($cd{$track}{NTITLE}, 0, $titlelength - $excess);
        }

        my $destfile = "$cddir/$ztrack $cd{$track}{NTITLE}.flac";
        $destfile =~ s/[\:*?<>|]//g; # NTFS Valid file?
        my $bytes=-s $cd{$track}{FNAME};
        dprint " | We will copy "; dprint YELLOW "'$cd{$track}{NTITLE}.flac' ($bytes bytes)\n";
        dprint " | as "; dprint YELLOW "'$ztrack $cd{$track}{NTITLE}.flac'\n";

        if (-B $destfile) {
            dprint " | "; dprint YELLOW BOLD "WARNING! File already exists, skipping!\n";
        } else {
            copy ($cd{$track}{FNAME}, "$destfile") or die $!;
            $bytes=-s $destfile;
            dprint " | "; dprint BOLD GREEN "OK! ($bytes bytes).\n";
        }

        if (-B $destfile) {
            dprint " | "; dprint "Now we will tag it:\n";
            my $flac = Audio::FLAC::Header->new($destfile);
            my $tags = $flac->tags();
            %{$tags} = ();
            my $result = $flac->write();

            unless ($result) {
                dprint RED "Unable to clean tags on $cd{$track}{NTITLE}.flac\n";
                return 0;
            }

            my $genre = $vgm{'Classification'} || 'VGM';
            if ($vgm{'TYPE'} and $vgm{'TYPE'} eq "album-anime") {
                $genre="Anime";
            } else {
                my @genres = map {"VGM($_)"} sort split (', ', $genre);
                $genre = join ('; ', @genres);
            }

            my $date   = $vgm{'Release Date'} || 'XXXX';
            #$date = $& if $date =~ /\d+$/; # Only year MAN
            my $version = "Type:$vgm{'Publish Format'}, Media:$vgm{'Media Format'}, Price:$vgm{'Release Price'}";
            my $description = "Catalog:$vgm{'Catalog Number'} URL:$vgm{URL}";
            my $aartist = $vgm{'Arranged by'};
            $aartist = $vgm{'Composed by'} unless $aartist;
            $aartist = "Not Available" unless $aartist;
            $aartist =~ s/,.*$//g;
            $vgm{'Arranged by'} = $aartist unless $vgm{'Arranged by'};
            $aartist =~ s/\s\/.*//g;

            $tags->{TRACKNUMBER}    = $ztrack               || "Not Available";
            $tags->{TOTALTRACKS}    = keys(%cd)             || "Not Available";
            $tags->{ALBUM}          = $albumname            || "Not Available";
            $tags->{TITLE}          = $cd{$track}{'NTITLE'} || "Not Available";
            $tags->{GENRE}          = $genre                || "Not Available";
            $tags->{DATE}           = $date                 || "Not Available";
            $tags->{'ALBUM ARTIST'} = $aartist              || "Not Available";
            $tags->{ARTIST}         = $vgm{'Arranged by'}   || "Not Available";
            $tags->{COMPOSER}       = $vgm{'Composed by'}   || "Not Available";
            $tags->{PERFORMER}      = $vgm{'Performed by'}  || "Not Available";
            $tags->{TOTALDISCS}     = $vgm{TOTALDISCS}      || "Not Available";
            $tags->{DISCNUMBER}     = $cdnum                || "Not Available";
            $tags->{COMMENT}        = $description          || "Not Available";
            $tags->{VERSION}        = $version              || "Not Available";
            $tags->{COPYRIGHT}      = $vgm{'Published by'}  || "Not Available";

            # Hacemos un resumen de los tags para el log
            foreach my $key (sort keys %{ $tags }) {
                dprint sprintf (" |-- %-12.12s = '%s'\n", $key, $tags->{$key});
            }

            # Voy a meter las notas como TAG, pero no quiero logearlo
#            $vgm{NOTES} = encode('utf-8', $vgm{NOTES});
#            $tags->{NOTES} = $vgm{NOTES} || "Not Available";

            # OK, escribimos!
            $result = $flac->write();
            if ($result) {
                dprint " \\ "; dprint GREEN BOLD "OK! Tagging done!\n";
            } else {
                dprint " \\ "; dprint RED BOLD "No se pudo tagear $cd{$track}{NTITLE}.flac debidamente.\n";
                return 0;
            }
        } else {
            dprint " \\ "; dprint RED BOLD "El fichero '$destfile' no existe o no es binario";
            return 0;
        }
    } # foreach my $track

    if ($vgm{COVER}) {
        dprint BLUE BOLD "\n"."=" x (15)."\n";
        dprint BLUE BOLD "Fetching Cover:\n";
        dprint BLUE BOLD "=" x (15)."\n\n";
        &savefile($vgm{COVER}, 'folder', $cddir);
    }

    if ($vgmuserid and $cdnum == 1) {
        dprint BLUE BOLD "\n"."=" x (17)."\n";
        dprint BLUE BOLD "Fetching Artwork:\n";
        dprint BLUE BOLD "=" x (17)."\n\n";
        foreach my $name (sort keys %{$vgm{SCANS}}) {
            &savefile($vgm{SCANS}{$name}, $name, "$basedir/Scans");
        }
    }

    dprint GREEN BOLD "#\n#\tAll OK!\n#\n";
    unless ( -f "$cddir/log_ansi.txt") {
        open(LOG, "> $cddir/log_ansi.txt") || die "Can't redirect stdout";
        map {print LOG $_} @log;
        close(LOG);
    }
    unless ( -f "$cddir/log.txt") {
        open(LOG, "> $cddir/log.txt") || die "Can't redirect stdout";
        map {s/.\[\d+m//g; print LOG $_} @log;
        close(LOG);
    }

    if ($vgm{NOTES}) {
        open(LOG, "> $basedir/notes_$vgm{ID}.txt") || die "Can't redirect stdout";
        print LOG "$vgm{URL} (".scalar localtime().")\n";
        print LOG "$vgm{NOTES}\n";
        close(LOG);
    }

    if ($force) {
        open(LOG, "> $cddir/forced_$vgm{ID}.txt") || die "Can't redirect stdout";
        print LOG "$vgm{URL} (".scalar localtime().")\n";
        close(LOG);
    }

    return $basedir;
} # sub rename
#}}}

#
#   main foreach
#
foreach my $dir (@ARGV) {
    if (-d $dir) {
        @log=();
        my $vgmcd=0;
        my @files=();
        opendir(DIR, $dir) || dprint RED "can't opendir $dir: $!\n";
        @files=map {"$dir/$_"} grep { !/^\.+$/ && /^.*flac$/i } readdir(DIR);
        closedir DIR;
        &hashfiles(@files);
        my ($dirname) = $dir =~ /([^\/]+)(?:|\/)$/;
        my $ids = {};
        if ($id) {
            $ids->{$id}->{title} = "Forced VGMID";
        } else {
            $ids = &vgmdbsearch($dirname);
        }

        unless (keys(%$ids)) {
            &error("No results on VGMDB for $dirname, skipping...");
            next;
        }
        &authenticate;
        foreach (sort { $ids->{$a}{type} cmp $ids->{$b}{type} } keys %$ids) {
            %vgm=();
            dprint BLUE BOLD"\nTrying ($_) - $ids->{$_}{title}\n\n";
            &vgmdbid($_, $ids->{$_}{type});
            $vgmcd = &compare;
            if ($vgmcd) {
                my $result = &rename($vgmcd,$dir);
                last if $result;
            }
        }
        unless ($vgmcd) {
            &error("No match for '$dirname'.");
        }
    } # if -d dir
} # foreach my dir
