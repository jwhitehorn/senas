################################################################
#######            text/html mime type parser            #######
################################################################

use URI;	#for link absolution

sub handler_type{
	my $MIMEtype = "text/html";	#we process HTML
	return $MIMEtype;
}

sub handler{
	my $db = $_[0];			#database handler
	my $data = $_[1];		#data (ie, page) in question
	my $url	= $_[2];		#url
	my $id = $_[3];
	
	my $link_limit = 10;	#pull no more than 40 links from each page
	my $pulled_links = 0;	#none yet

	$data =~ m/<title>(.*)<\/title>/gi;		#pull title
	my $title = $1;
	my $query = "update sources set title=" . $db->quote($title) . " where id=$id;";
	$db->do($query);
	print "[DEBUG::Parser] TEXT::HTML got called!\n";
	while(  ($pulled_links < $link_limit) and ($data =~ m/<a[^>]*href=([^>]*)>/gi) ){
		my $link = $1;
		#start striping links from the page we just got
		$link =~ s/^["']//;
		$link =~ s/['"].*//;
		$link =~ s/\/$//g;
		$link = URI->new_abs($link, $url);  
		$link = URI->new($link)->canonical;
		$link =~ s/\#.*//g;     #no pound signs
		$query = "select lastseen from sources where URL=";
		$query .= $db->quote($link) . ";";
		$sth = $db->prepare($query);
		$sth->execute();
		if($sth->rows == 0){
		#we have NEVER been here..
		#$query = "select Priority from outgoing where URL=";
						$query = "select count(*) from outgoing where URL=";
						$query .= $db->quote($link) . ";";
						$sth = $db->prepare($query);
						$sth->execute();
						$query = $sth->fetchrow_arrayref();
						if($query->[0] == 0){
		#insert into outgoing
							$query = "insert into outgoing (url) values (";
							$query .= $db->quote($link) . ");";
							$db->do($query);
						}
		}#otherwise...we will get back to it later	
		#insert links into Links for ranking pages
		$query = "insert into links (target, source) values ($id, ";
		$query .= $db->quote($link) . ");";
		$db->do($query);
		$pulled_links++;
	}
	$page = $data;  #make a copy
	$page =~ s/\n//g;
	$page =~ m/<body[^>]*>(.*)<\/body>/gi;
	my $body = $1;
	$body =~ s/<[^>]*>/ /g;
	$body =~ s/&[^ ]* / /g;
	$body =~ s/[^a-zA-Z0-9 ]/ /g;
	$i = 0;
	while($body =~ m/([^ ]+)/g){
		#index Words...
		$word = $1;
		$query = "Insert into WordIndex (MD5, Word, Location, Source) values (";
		$query .= $db->quote($MD5) . ", " . $db->quote(lc($word)) . ", $i, 1);";
		$db->do($query);
		$i++;
	}
}