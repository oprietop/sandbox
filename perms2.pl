#/usr/bin/perl
my $user='nobody';
print "Current Effective UID: $>\n";
print "Current Effective GID: $)\n";
($name, $pass, $uid, $gid, $quota, $comment, $gcos, $dir, $shell, $expire) = getpwnam($user);
print "Requesting $user\'su id ($uid) and ($gid)...\n";
$) = $gid;
$> = $uid;
print "Current Effective UID: $>\n";
print "Current Effective GID: $)\n";
#exec(top);
