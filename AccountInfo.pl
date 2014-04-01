#!/usr/bin/perl
#
# Script to dump account/group info from your Docusign account.
# You need this information to plug into DocusignADSync.pl
# bubba@bubba.org
# 
use REST::Client;  
use JSON;

# You need to create a dev account at
# https://www.docusign.com/developer-center/get-started
$apiuser="user\@email.com";
$apipass="pass";
$apikey="XXXX-XXXX-XXXXX-XXXXX-XXXXX-XXXXX";

my $client = REST::Client->new();
my $headers={ 'Accept' => 'application/json', 'Content-Type' => 'application/json', 'X-DocuSign-Authentication' => "<DocuSignCredentials><Username>$apiuser</Username><Password>$apipass</Password><IntegratorKey>$apikey</IntegratorKey></DocuSignCredentials>" };
$endpoint="/restapi/v2/";
$server="https://demo.docusign.net";
$client->setHost($server);

&getAccountInfo;

sub getAccountInfo {
	$client->GET($endpoint."login_information",$headers);
	my $decoded_json = decode_json($client->responseContent());

	foreach(@{$decoded_json->{"loginAccounts"}}) {
		if ($accountId = $_->{'accountId'}) {
			print "AccountID: $accountId\n\n";
		}
	}

	$client->GET($endpoint."accounts/$accountId/groups",$headers);
	$decoded_json = decode_json($client->responseContent());

	foreach(@{$decoded_json->{"groups"}}) {
		if ($groupName= $_->{'groupName'}) {
			print "GroupName: $groupName\n";
		}
		if ($groupId= $_->{'groupId'}) {
			print "GroupID: $groupId\n\n";
		}
	}
}
