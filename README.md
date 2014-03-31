DocusignADSync
=======

Perl-based script to sync/create accounts/groups in Docusign based on AD group membership

Requirements
------------
use REST::Client;
use JSON;
use Net::LDAP;

I recommend installing [cpanminus](https://github.com/miyagawa/cpanminus) and installing them that way. 
<pre>
sudo apt-get install curl
curl -L http://cpanmin.us | perl - --sudo App::cpanminus
</pre>	

Then install the modules..
<pre>
sudo cpanm REST::Client JSON Net::LDAP
</pre>

Usage
-----
The goal of this is to create accounts in Docusign automatically so that they can be used via Docusign SSO (SAML).  The issue is that all SSO accounts require users to set an initial password upon activation, even if you're leveraging SSO. The # only way around this is to create the accounts via API AND have your account manager change your Distributor to be a "no activation" distributor.  This way, activation is not required, thus users don't have to give Docusign some password they will never remember or risk losing if Docusign's credentials were to be "lost".  

You need to create a dev account at https://www.docusign.com/developer-center/get-started use AccountInfo.pl to dump your accountid and list of groups. I would create a Signers group and an Initiators group in Docusign (you know, folks who can only sign stuff that is sent to them vs. folks who can start a workflow requesting a signature).  You then need to use accountInfo.pl to dump the list of groups from your account to get the name->ID mappings and transfer them to the script.  Next, create similar groups in Active Directory which you would populate with these signers and initiators.  This is where you update the mappings in the script itself. 

Bugs/Contact Info
-----------------
Bug me on Twitter at [@brianwilson](http://twitter.com/brianwilson) or email me [here](http://cronological.com/comment.php?ref=bubba).


