################################################################
#######     application/x-bittorrent mime type parser    #######
################################################################

sub handler_type{
	my $MIMEtype = "application/x-bittorrent";	#we process BitTorrents
	return $MIMEtype;
}

sub handler{
	my $db = $_[0];			#database handler
	my $data = $_[1];		#data (ie, page) in question
	my $url	= $_[2];		#url
	my $MD5 = $_[3];
	
	my $i;
	$data =~ m/name([0-9]+):([^:]*)/;
	my $title = substr($2, 0, $1);
	my $comment = "";
#	my $size = 0;
#	while($data =~ m/lengthi([0-9]+)/g){    #calculate target size
#		$size += $1;
#	}
	if($data =~ m/comment([0-9]+):(.*)/i){  #find the comment is one exists
			$comment = substr($2, 0, $1);
			$comment = $db->quote($comment);
	}

	my $query = "update `Index` set Title=" . $db->quote($title) . " where MD5=";
	$query .= $db->quote($MD5) . ";";
	$db->do($query);
	print "[DEBUG::Parser] APPLICATION::X-BITTORRENT got called!\n" unless !$debug;
	$i = 0;
	while($comment =~ m/([^ ]+)/g){
		#index Words...
		$word = $1;
		$query = "Insert into WordIndex (MD5, Word, Location, Source) values (";
		$query .= $db->quote($MD5) . ", " . $db->quote(lc($word)) . ", $i, 1);";
		$db->do($query);
		$i++;
	}
}