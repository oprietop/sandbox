#!/usr/bin/perl
# https://docs.atlassian.com/jira/REST/cloud/
# Fields can be checked with http://jirahost/rest/api/2/issue/ISSUENAME

use strict;
use warnings;
use LWP::UserAgent;
use HTTP::Request::Common;
use HTTP::Cookies;
use JSON;

my $user = "xxxxxx";
my $pass = "yyyyyy";
my $host = "jira.fqdn/jira";

my %lines;
foreach my $arg (@ARGV) {
  open my $handle, '<', $arg;
  foreach my $line (<$handle>) {
    chomp($line);
    $lines{$line} = 1;
  }
  close $handle;
}

my $ua = LWP::UserAgent->new( agent         => 'Windows IE 6' # ORLY
                            , show_progress => 1
                            , timeout       => 10
                            , cookie_jar    => HTTP::Cookies->new( autosave => 1 )
                            );

# Auth
my $creds = {'username' => $user, 'password' => $pass};
my $json = encode_json($creds);
my $req = HTTP::Request->new('POST', "http://$host/rest/auth/1/session");
$req->header('Content-Type' => 'application/json');
$req->content($json);
my $resp = $ua->request($req);
print $resp->headers_as_string;

# Post
foreach my $line (keys %lines) {
  print "$line\n";
  my $data = { 'fields' => { 'project'           => {  'id' => 'xxx' }  # http://jirahost/jira/rest/api/2/project/xxx
                           , 'customfield_11451' => [{ 'id' => 'xxx' }] # http://jirahost/jira/rest/api/2/customFieldOption/xxx
                           , 'issuetype'         => {  'id' => 'xxx' }  # http://jirahost/jira/rest/api/2/issuetype/xxx
                           , 'components'        => [{ 'id' => 'xxx' }] # http://jirahost/jira/rest/api/2/component/xxx
                           , 'duedate'           => '2017-11-10'
                           , 'summary'           => $line
                           , 'description'       => $line
                           }
             };
  $json = to_json($data);
  $req = HTTP::Request->new('POST', "http://$host/rest/api/2/issue");
  $req->header('Content-Type' => 'application/json');
  $req->content($json);
  my $resp = $ua->request($req);
  my $out = decode_json($resp->content);
  print $out;
}
