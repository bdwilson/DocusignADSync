#!/usr/bin/perl
#
# Script to sync/create accounts in Docusign based on AD group membership
# bubba@bubba.org 
# 
# The goal of this is to create accounts in Docusign automatically so that they
# can be used via Docusign SSO (SAML).  The issue is that all SSO accounts
# require users to set an initial password upon activation, even if you're 
# leveraging SSO. The # only way around this is to create the accounts via 
# API AND have your account manager change your Distributor to be a 
# "no activation" distributor.  This way, activation is not required, thus
# users don't have to give Docusign some password they will never remember or
# risk losing if Docusign's credentials were to be "lost". 
# 
#
use REST::Client;  
use JSON;
use Net::LDAP; 

# You need to create a dev account at
# https://www.docusign.com/developer-center/get-started
# use AccountInfo.pl to dump your accountid and list of groups.
$accountid="XXXXXX";
$apiuser="user\@email.com";
$apipass="pass";
$apikey="XXXX-XXXX-XXXXX-XXXXX-XXXXX-XXXXX";

# Print trace data for Docusign API certification
# $debug=1;

# This will need to be changed once you get your script/apikey moved to
# production
$server="https://demo.docusign.net";

# AD groupname (short group/pre-2000 name) and Docusign group ID use
# AccountInfo.pl to dump the list of groups from Docusign to get the 
# name->ID mappings and transfer here. For me, I have a signers AD group 
# and an initiators group. I then assign permissions to those groups in 
# Docusign. Then I simply add users to the proper groups in AD then run 
# the sync job via cron.  You can add additional groups as you see fit. 
%ADtoDocusign = ("DocusignSigners" => "XXXXXXX", "DocusignInitiators" => "XXXXXXX");

# We're assuming that all the groups we care about are in a single domain 
# at this point, so only need info about that domain, you will need to adjust
# your script if you use multiple domains. This data needs to be accurate in
# order to read user info from AD.  
my %domains = ( domain => {
                                dc => "dc.domain.com",
                                base => "DC=dc,DC=domain,DC=com",
				user => "CN=Anonymous Bind,CN=Users,DC=dc,DC=domain,DC=com",
				pass => 'AnonymousPassword',
                          },
);

########## You probably don't need to edit anything below here ##########

$endpoint="/restapi/v2/";
my $client = REST::Client->new();
my $headers={ 'Accept' => 'application/json', 'Content-Type' => 'application/json', 'X-DocuSign-Authentication' => "<DocuSignCredentials><Username>$apiuser</Username><Password>$apipass</Password><IntegratorKey>$apikey</IntegratorKey></DocuSignCredentials>" };
$client->setHost($server);

# popupate Docusign Users with extended info
# note, we're using userName as the key here for both
# getMembers and getUsers rather than email addr. Using email
# addr caused issues due to lowercase/uppercase. I think this was
# due to the email addrs already being in the docusign system, but
# not 100% sure. userName should be unique across our instance, so
# we shouldn't run into issues. 
%userList = &getUsers;

# populate AD users for groups we care about (ADtoDocusign hash)
# Again, using displayName as key in AD and not mail. See above
# for reasons why.
%users = ();
foreach my $adGroup (keys %ADtoDocusign) {
	&getMembers($adGroup,"domain");
}

# Process Docusign Additions based on our ADtoDocusign mappings
foreach $adGroup (keys %ADtoDocusign) {
	my $groupId=$ADtoDocusign{$adGroup};
	foreach my $name (keys %{$users{$adGroup}}) {
		#print "Processing $name\n";
		if (!$userList{$name}) {
			# user doesn't exist, add them and add to group if successful
			$userData = &createUser($users{$adGroup}{$name}{'mail'},$name);
			if ($userData->{'email'}) {
				&groupChange($groupId,$userData->{'email'},$userData->{'userId'},"ADD");
			}
		} else {
			# user already exists. Check group membership and add if needed
			my $found=0;
			foreach $group (@{$userList{$name}->{'groupList'}}) {
				if ($group->{'groupId'} eq $groupId) {
					$found++;
					last;
					# Name exists in group. skip
				}
			}
			if (!$found) {
				# Name doesn't exist in group, add them
				print "Adding $name to $groupId\n";
				&groupChange($groupId,$userList{$name}->{'userName'},$userList{$name}->{'userId'},"ADD");
			}
		}
	}
}

# process deletions for groups we care about (in ADtoDocusign hash)
foreach $name (keys %userList) {
	foreach $group (@{$userList{$name}->{'groupList'}}) {
		my $groupId = $group->{'groupId'};
		foreach $adGroup (keys %ADtoDocusign) {
			if (($ADtoDocusign{$adGroup} eq $groupId) && (!$users{$adGroup}{$name})) {
			#	print "Need to remove $name from $groupId\n";
				&groupChange($groupId,$userList{$name}->{'userName'},$userList{$name}->{'userId'},"DELETE");
			}
		}
	}
}

# ADD or DELETE a user from a group
sub groupChange {
	my ($groupId,$email,$userId,$type) = @_;
	my %json_data =(
  		users => [{
    			userId => "$userId"
  		}]
	);
	
        my $data = encode_json(\%json_data);
	if ($type eq "DELETE") {
		$client->request("DELETE",$endpoint."accounts/$accountid/groups/$groupId/users",$data,$headers);
	} else {
		$client->PUT($endpoint."accounts/$accountid/groups/$groupId/users",$data,$headers);
	}
        if ($debug) {
                print "=" x 60 . "\n";
                print "Request:\n";
                print Dumper $client->{'_res'}->{'_request'};
                print "Response:\n";
                print Dumper $client->{'_res'}->{'_content'};
                print "Response Headers:\n";
                print Dumper $client->{'_res'}->{'_headers'};
                print "=" x 60 . "\n";
        }
	my $decoded_json = decode_json($client->responseContent());
	foreach(@{$decoded_json->{"users"}}) {
		if ($_->{'errorDetails'}) {
			print $_->{'errorDetails'}->{'message'} . "\n";
			last;
		}
		if ($_->{'userStatus'} eq "created") {
			if (!$debug) {
				print "$type user $email to/from group ($groupId) successful.\n";
			}
		}
	}
}

# Create a user in Docusign w/ random pass. User will still get the initiation
# email unless your account manager disables it.
sub createUser {
	my($email,$userName)=@_;
	my @chars = (a..z, A..Z, 0..9);
	my $password = join '', map { @chars[rand @chars] } 1 .. 20;
	if ($debug) {
		$password = "DebugMode";
	}
	my %json_data =  ( 
		 newUsers =>[{ 
			email => "$email",
			enableConnectForUser => 'false',
			sendActivationOnInvalidLogin => 'false',
			userName => "$userName",
			password => "$password",
			forgottenPasswordInfo => {
				forgottenPasswordAnswer1 => "false",
				forgottenPasswordAnswer2 => "false",
				forgottenPasswordAnswer3 => "false",
				forgottenPasswordAnswer4 => "false",
				forgottenPasswordQuestion1 => "false",
				forgottenPasswordQuestion2 => "false",
				forgottenPasswordQuestion3 => "false",
				forgottenPasswordQuestion4 => "false",
			},
		}]
		);
	
	my $data = encode_json(\%json_data);
	$client->POST($endpoint."accounts/$accountid/users",$data,$headers);
        if ($debug) {
                print "=" x 60 . "\n";
                print "Request:\n";
                print Dumper $client->{'_res'}->{'_request'};
                print "Response:\n";
                print Dumper $client->{'_res'}->{'_content'};
                print "Response Headers:\n";
                print Dumper $client->{'_res'}->{'_headers'};
                print "=" x 60 . "\n";
        }
	my $decoded_json = decode_json($client->responseContent());
	foreach(@{$decoded_json->{"newUsers"}}) {
		if ($_->{'errorDetails'}) {
			print $_->{'errorDetails'}->{'message'} . "\n";
			last;
		}
		if ($userId= $_->{'userId'}) {
			if (!$debug) {
				print "UserID created: $_->{'email'} ($_->{'userId'})\n";
			}
			return $_;
		}
	}
}

# get extended user data from Docusign. store in hash with userName as key (not email :()
sub getUsers {
	$client->GET($endpoint."/accounts/$accountid/users?additional_info=true",$headers);
        if ($debug) {
                print "=" x 60 . "\n";
                print "Request:\n";
                print Dumper $client->{'_res'}->{'_request'};
                print "Response:\n";
                print Dumper $client->{'_res'}->{'_content'};
                print "Response Headers:\n";
                print Dumper $client->{'_res'}->{'_headers'};
                print "=" x 60 . "\n";
        }
	my $decoded_json = decode_json($client->responseContent());
	foreach(@{$decoded_json->{"users"}}) {
			$docusignUsers{$_->{'userName'}}=$_;
	}
	return %docusignUsers;
}

# Dump accountid and group info.
sub getAccountInfo {
	$client->GET($endpoint."login_information",$headers);
        if ($debug) {
                print "=" x 60 . "\n";
                print "Request:\n";
                print Dumper $client->{'_res'}->{'_request'};
                print "Response:\n";
                print Dumper $client->{'_res'}->{'_content'};
                print "Response Headers:\n";
                print Dumper $client->{'_res'}->{'_headers'};
                print "=" x 60 . "\n";
        }
	my $decoded_json = decode_json($client->responseContent());
	foreach(@{$decoded_json->{"loginAccounts"}}) {
		if ($accountId = $_->{'accountId'}) {
			if (!$debug) {
				print "AccountID: $accountId\n\n";
			}
		}
	}

	$client->GET($endpoint."accounts/$accountId/groups",$headers);
        if ($debug) {
                print "=" x 60 . "\n";
                print "Request:\n";
                print Dumper $client->{'_res'}->{'_request'};
                print "Response:\n";
                print Dumper $client->{'_res'}->{'_content'};
                print "Response Headers:\n";
                print Dumper $client->{'_res'}->{'_headers'};
                print "=" x 60 . "\n";
        }
	$decoded_json = decode_json($client->responseContent());
	foreach(@{$decoded_json->{"groups"}}) {
		if (!$debug) {
			if ($groupName= $_->{'groupName'}) {
				print "GroupName: $groupName\n";
			}
			if ($groupId= $_->{'groupId'}) {
				print "GroupID: $groupId\n\n";
			}
		}
	}
}


# query AD and get members of AD groups.
sub getMembers {
	my ($query, $domain) = @_;
	my $dc = $domains{$domain}->{dc};
	my $base = $domains{$domain}->{base};
	my $user = $domains{$domain}->{user};
	my $pass = $domains{$domain}->{pass};
	my $ldap = new Net::LDAP($dc, port => 389);
	$ldap->bind(dn => "$user", password => "$pass");
	my $filter = "(&(objectClass=group)(sAMAccountName=$query))";
	my $attributes = ['distinguishedName'];

	my $msg = $ldap->search(
       	 scope => "sub",
       	 base => $base,
       	 filter => $filter,
       	 attrs => $attributes
	);
       $msg->code;
       my ($entry);
       $count = $msg->count;
       for (my $index = 0; $index < $count; $index++) {
        my $entry = $msg->entry($index);
        foreach my $attr ($entry->attributes) {
                $array = $entry->get($attr);
                for my $var (@{$array}) {
                        $$attr=$var;
                }
          }
        }
        if ($distinguishedName) {
                $dn = $distinguishedName;
        } else {
                $dn = $query;
        }
        #print "DN: $dn\n";
        my $gfilter = "(&(objectCategory=person)(objectClass=user)(memberOf=$dn))",
        #my $gattrs = ['sAMAccountName'];
        my $gattrs = ['sAMAccountName','employeeID','mail','displayName'];
        $mgrmsg = $ldap->search(
                scope => "sub",
                base => $base,
                filter => $gfilter,
                attrs => $gattrs
        );
        $mgrmsg->code; # && die $mgrmsg->error;
        my $mgrcount = $mgrmsg->count;

        for (my $index = 0; $index < $mgrcount; $index++) {
          my $entry = $mgrmsg->entry($index);
          foreach my $attr ($entry->attributes) {
                $array = $entry->get($attr);
                for my $var (@{$array}) {
                        $$attr=$var;
                }
          }
	  $users{$query}{$displayName}{'displayName'}=$displayName;
	  $users{$query}{$displayName}{'mail'}=$mail;
	  $users{$query}{$displayName}{'sAMAccountName'}=$sAMAccountName;
        }
	if (%users) {
                return 1;
        } else {
                return 0;
        }
}
