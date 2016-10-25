#!/usr/bin/perl
# https://docs.atlassian.com/jira/REST/latest/

use strict;
use warnings;
use LWP::UserAgent;
use HTTP::Request::Common;

my $user = "jirauser";
my $pass = "jirapass";
my $host = "jirahost.com/jira";

my $ua = LWP::UserAgent->new( agent         => 'Windows IE 6' # ORLY
                            , show_progress => 1
                            , timeout       => 10
                            );

my $resp = $ua->request( POST "http://$user:$pass\@$host/secure/QuickCreateIssue.jspa?decorator=none"
                       , [ pid               => 11111 # http://jirahost.com/jira/rest/api/2/project
                         , issuetype         => 22222 # http://jirahost.com/jira/rest/api/2/issuetype
                         , components        => 33333 # http://jirahost.com/jira/rest/api/2/component/33333
                         , customfield_XXXXX => 44444 # http://jirahost.com/jira/rest/api/2/customFieldOption/44444
                         , duedate           => '31/des./14'
                         , summary           => 'Enter summary gere'
                         , description       => 'Enter description here'
                         ]
                       , 'X-Atlassian-Token' => 'no-check'
                       );

$resp->is_success ? print $resp->as_string : print $resp->headers_as_string."\n";
