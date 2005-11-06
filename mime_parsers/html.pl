################################################################
#######            text/html mime type parser            #######
################################################################

use URI;	#for link absolution
use MIME::Base64;

sub handler_type{
	my $MIMEtype = "text/html";	#we process HTML
	return $MIMEtype;
}

sub handler{
	my $data = $_[0];		#data (ie, page) in question
	my $url	= $_[1];		#url
	my $id = $_[2];
	

	$data =~ m/<title>(.*)<\/title>/gi;		#pull title
	my $title = $1;
	push_title($id, $title);
	print "[DEBUG::Parser] TEXT::HTML got called!\n";
	while($data =~ m/<a[^>]*href=([^>]*)>/gi){
		my $link = $1;
		#start striping links from the page we just got
		$link =~ s/^["']//;
		$link =~ s/['"].*//;
		$link =~ s/\/$//g;
		$link = URI->new_abs($link, $url);  
		$link = URI->new($link)->canonical;
		$link =~ s/\#.*//g;     #no pound signs
		push_link($id, $link);
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
		$word = lc($1);
		push_word($id, $word, $i);
		$i++;
	}
}