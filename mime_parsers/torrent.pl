################################################################
#######     application/x-bittorrent mime type parser    #######
################################################################

sub handler_type{
	my $MIMEtype = "application/x-bittorrent";	#we process BitTorrents
	return $MIMEtype;
}

sub handler{
	my $data = $_[0];		#data (ie, page) in question
	my $url	= $_[1];		#url
	my $id = $_[2];
	
	my $i;
	$data =~ m/name([0-9]+):([^:]*)/;
	my $title = substr($2, 0, $1);
	push_title($id, $title);
	my $comment = "";
	if($data =~ m/comment([0-9]+):(.*)/i){  #find the comment is one exists
			$comment = substr($2, 0, $1);
			$comment = $db->quote($comment);
	}
	$i = 0;
	while($comment =~ m/([^ ]+)/g){	#index Words...
		$word = $1;
		push_words($id, $word, $i);
		$i++;
	}
}