package search;
#search.pm
#copyright 2004, 2005, Jason Whitehorn
my $version = "0.7.11";
#This program is free software; you can redistribute it and/or
#modify it under the terms of the GNU General Public License
#as published by the Free Software Foundation; either version 2
#of the License, or (at your option) any later version.
#
#This program is distributed in the hope that it will be useful,
#but WITHOUT ANY WARRANTY; without even the implied warranty of
#MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#GNU General Public License for more details.
#
#You should have received a copy of the GNU General Public License
#along with this program; if not, write to the Free Software
#Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
my $config_file = "senas.cfg";

my $log_file = "/var/log/senas.log";
my $log_queries = 0;	#not by default anyways
  
my $DBPassword;# = "password";
my $DBHost;# = "127.0.0.1";
my $DB;# = "search";
my $DBUser;# = "username";
open FILE, "<$config_file";
while(<FILE>){
	if( $_ =~ m/password=([^;]*);/){
		$DBPassword = $1;
	}
	if( $_ =~ m/username=([^;]*);/){
		$DBUser = $1;
	}
	if( $_ =~ m/host=([^;]*);/){
		$DBHost = $1;
	}
	if( $_ =~ m/database=([^;]*);/){
		$DB = $1;
	}
}
close FILE;


use DBI;
use Time::HiRes qw( gettimeofday tv_interval );
use POSIX qw(ceil);

sub scale_down{
    my $string = shift;
    my $max = 60;
    if(length($string) > $max){
        my $head;
        my $tail;
        $string =~ m/(^http:\/\/[^\/]+\/)/i;
        $head = $1;
        $string =~ m/(\/[^\/]+)$/i;
        $tail = $1;
        $string = "$head...$tail";
        if(length($string) > $max){
            $tail = substr($tail, (length($string) - $max), (length($tail)-(length($string) - $max)));
            $string = "$head.../...$tail";
        }
    }
    return $string;
}

sub search{
    my @results = ();
    my $term = 0;
    my $search = $_[0];
    my $start = [gettimeofday];
    my $db = DBI->connect("DBI:mysql:$DB:$DBHost", "$DBUser", "$DBPassword") or return -1;
	if($log_queries){
		my $buffer = $search;
		$buffer =~ s/:/\\:/g;
		open LOGFILE, ">>$log_file";
		print LOGFILE time(), ":", $buffer, ":";
	}
    $query = "select Results from `QueryCache` where `Query` = " . $db->quote($search) . ";";
    my $sth = $db->prepare($query);
    $sth->execute();
    my $old = 0;
    if($sth->rows != 0){   #we could find it in QueryCache
        $resultcache = $sth->fetchrow_arrayref();
        $results = $resultcache->[0];
        while($results =~ m/([0-9a-f]+):/gi){
            push @results, $1;
        }
    }else{  #we could not find the query in QueryCache
#        $old = 1;
#    }
#    if($old){  #old code!!!
        while($search =~ m/([a-zA-Z0-9]+)/g){    #loop for every query word
            $word = lc($1);
            $term++;
            $db->do("create temporary table word$term type=heap select MD5 from `WordIndex` where Word='$word' order by Location asc;");
            push @terms, $word;
        }
        # select word1.MD5 from word1, word2 where word1.MD5 = word2.MD5;
        # select word1.MD5 from word1, word2, word3 where word1.MD5 = word2.MD5 and word1.MD5 = word3.MD5;
        if($term > 1){
            my $where = "";
            my @queries = ();
            $query = "select word1.MD5 from word1";
            for($i = 2; $i <= $term; $i++){
                $query = "$query, word$i";
                $where = "$where AND (word1.MD5 = word$i.MD5)";
                if($term > 2){
                    push @queries, "select word1.MD5 from word1, word$i where word1.MD5 = word$i.MD5;";
                }
            }
            $where =~ s/^ AND//;    #remove first AND
            $query = "$query where $where;";
            $sth = $db->prepare($query);
            $sth->execute();
            while($results = $sth->fetchrow_arrayref()){
                my $used = 0;
                foreach (@results){
                    if("$_" eq "$results->[0]"){
                        $used = 1;
                        last;   #stop NOW!
                    }
                }
                push @results, $results->[0] unless $used;
            }
            if($term > 2){
                foreach $query (@queries){
                    my $sth = $db->prepare($query);
                    $sth->execute();
                    while($results = $sth->fetchrow_arrayref()){
                        my $used = 0;
                        foreach (@results){
                            if("$_" eq "$results->[0]"){
                                $used = 1;
                                last;   #stop NOW!
                            }
                        }
                        push @results, $results->[0] unless $used;
                    }
                }
            }
        }else{ #only 1 term
            $query = "select word1.MD5 from word1, `Sources` where Sources.MD5=word1.MD5 order by Sources.Rank desc;";
            my $sth = $db->prepare($query);
            $sth->execute();
            while($results = $sth->fetchrow_arrayref()){
                my $used = 0;
                foreach (@results){
                    if("$_" eq "$results->[0]"){
                        $used = 1;
                        last;   #stop NOW!
                    }
                }
                push @results, $results->[0] unless $used;
            }
        }
        $query = "insert into `QueryCache` (`Query`, `Results`, `Expire`) values (" . $db->quote($search);
        $query .= ", '";
        foreach (@results){
            $query .= "$_:";
        }
        $query .= "', ";
        $query .= time() + (5 * 60);
        $query .= ");";
        $db->do($query);
    }
	if($log_queries){
		print LOGFILE scalar(@results), ":", tv_interval($start), "\n";
		close LOGFILE;
	}
    return @results;
}
sub display{
    my $elements = shift @_;
    my $page = shift @_;
    my $start = shift @_;
    my $search = shift @_;
    my @results = @_;
    
    my @prefix = ("", "kilo", "mega", "giga", "tera", "peta");
    
    my $db = DBI->connect("DBI:mysql:$DB:$DBHost", "$DBUser", "$DBPassword") or return -1;
    
    print "<html><head>\n";
    print "<title>";
    print "Senas search: $search</title>\n";
    print "<link rel=StyleSheet href=\"../style.css\" type=\"text/css\">\n";
    print "<META NAME=\"ROBOTS\" CONTENT=\"NOINDEX, NOFOLLOW\">";   #prevent search pages from being indexed
    print "</head><body OnLoad=document.search.query.focus();>\n";

    print "<form name=\"search\" action=\"../cgi-bin/search.pl\" method=\"get\">";
    print "<a style='color: white;' href=\"../\"><img src=\"../images/senas.jpg\"></a>";
    print "<input type=\"text\" value=\"$search\" name=\"query\" size=45>";
    print "<input type=\"submit\" value=\"Search\">";
    print "</form>";
    
    print "<div class=\"hrule\">("; #display horizontal rule
    my $stop = tv_interval($start);
    $stop =~ s/^([0-9]*\.[0-9]?[0-9]?).*$/$1/;
    print scalar(@results), " results in $stop seconds) \n";
    print "Displaying page ", ($page+1);
    my $max = ceil(scalar(@results) / $elements);
    if(scalar(@results) >= $elements){
        print " of $max pages";
    }
    print "</div><br>";

    if(scalar(@results) == 0){
        #if we do not have any results
        print "<center>No results found, please check your query for spelling errors.</center>\n";
    }else{
        #print "<div class=\"SideBar\">SideBar</div>";
        my $results;
        #all results are in @results...display them
        #foreach $item (@results){  #loop for all the results
        for($i = ($elements*$page); $i != ($elements+($elements*$page)); $i++){
            $item = $results[$i];
            $query = "select MD5, Cache, Title, TSize from `Index` where MD5='$item';";
            $sth = $db->prepare($query);
            $sth->execute();
            while($results = $sth->fetchrow_arrayref()){
                my $checksum = $results->[0];
                my @cache = $results->[1];
                my $filename = $results->[2];
                my $size = $results->[3];
              #  my $comment = $results->[4];
                while($search =~ m/([a-zA-Z0-9]+)/g){ 
                    $string = "<b>$1</b>";
                    $filename =~ s/$1/$string/ig;   #loses case..BAD!
                    $comment =~ s/$1/$string/ig;
                }

# here -------
                $query = "select URL, LastSeen, Rank from `Sources` where MD5='$checksum' order by Rank desc;";
                $sub = $db->prepare($query);
                $sub->execute();
                my $s = "";
                if($sub->rows > 1){
                    $s = "s";
                }
                $sources = $sub->fetchrow_arrayref();
                print "<div class=\"result\">\n";
                print "<div class=\"filename\">";
                print "<a href=\"", $sources->[0], "\">", "$filename</a></div> ";
                $prefix = 0;
                while($size > 1024){
                    $size = $size / 1024;
                    $prefix++;
                }
                $size =~ s/\..*$//;
                my $suffix = "";
                if($size > 1){
                    $suffix = "s";
                }
                $size =~ s/(\d)(?=(\d\d\d)+(?!\d))/$1,/g;
                print "<div class=\"size\">Target size: $size " . @prefix[$prefix] . "byte$suffix</div><br>";
                print "<div class=checksum>MD5 Checksum: $checksumk</div>";
                if( !($comment eq "") ){
                    print "Comment: <div class=\"comment\" style=\"font-size: 10pt;\">$comment</div>";
                }
                print "<div class=\"source_list\"><b>", $sub->rows, " known source$s";
      #          print " (<a href=\"../cgi-bin/piracyreport.pl?md5=$checksum\" style=\"font-size: 8pt;\">report piracy</a>):</b></div>";
                print "</b></div>";
                print "<!--<div class=\"cache\"><a href=\"download.pl?checksum=$checksum\">cache</a></div>--><br>\n";
                $color = 0;
                do{    #display all the known sources for a given checksum
                    if(($color % 2) == 0){
                        print "<div class=\"grey_line\">";
                    }else{
                        print "<div class=\"white_line\">";
                    }
                    print "<div class=\"source\">";
                    print "<a href=\"", $sources->[0], "\">", scale_down($sources->[0]), "</a> ";
					print "Rank: ", $sources->[2];
                    print "</div>";
                    print "<div class=\"date\">Last seen: ", scalar localtime($sources->[1]), " CST</div><br>\n";
                    print "</div>";
                    $color++;
                }while($sources = $sub->fetchrow_arrayref());
                print "</div><br>";
            }
        }
    }
    print "<hr>";
    $ENV{QUERY_STRING} =~ m/query=([^&]*)/i;
    print "<center>";
    if($page > 0){
        print "<a href=\"../cgi-bin/search.pl?query=", $1, "&page=", ($page-1), "\">PREV</a> | \n";
    }else{
        print "PREV | ";
    }
    if($page < ($max-1)){
        print "<a href=\"../cgi-bin/search.pl?query=", $1, "&page=", ($page+1), "\">NEXT</a><br>\n";
    }else{
        print "NEXT";
    }
    #print "<div class=\"search\">";
    print "<form name=\"bottom_search\" action=\"../cgi-bin/search.pl\" method=\"get\">";
    print "<input type=\"text\" name=\"query\" size=45 value=\"$search\">";
    print "<input type=\"submit\" value=\"Search\">";
    print "</form>";
    print "</center>";
    #print "</div>";
    print "<center>";
    print "<div class=\"comment\">Search.pm version $version :: Copyright 2004-2005 ";
    print "<a href=\"mailto:jason.whitehorn@gmail.com\">Jason Whitehorn</a>, ";
	print "<a href=\"http://senas.sourceforge.net/\">source code</a> distributed under the";
	print "<a href=\"http://www.gnu.org/licenses/gpl.html\">GNU GPL</a></div></center>";
}

@EXPORT = qw(search, display);
