package search;
#search.pm
#copyright 2004, 2005, Jason Whitehorn
my $version = "0.8.0";
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
my $config_file = "/etc/senas.cfg";

my $log_queries = 0;	#not by default anyways
  
$password;
$username;
$host;
$database;
$path;
$type;

do "$config_file" or die "Error opening configuration file.\n";
my $log_file = $path . "/senas/var/search.log";

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
    my $search = $_[0];
    my $start = [gettimeofday];
    my $db = DBI->connect("DBI:$type:database=$database;host=$host", "$username", "$password") or return -1;
	my $query;
	my $term;
	my $i = 0;
	my @terms = ();

	if($log_queries){
		my $buffer = $search;
		$buffer =~ s/:/\\:/g;
		open LOGFILE, ">>$log_file";
		print LOGFILE time(), ":", $buffer, ":";
	}
	#first try and pull it from QueryCache...must faster...thats why its called Cache...
#	$query = "select Results from `QueryCache` where `Query` = " . $db->quote($search) . ";";
#	my $sth = $db->prepare($query);
#	$sth->execute();
#	if($sth->rows != 0){   #we could find it in QueryCache
#		$resultcache = $sth->fetchrow_arrayref();
#		$results = $resultcache->[0];
#		while($results =~ m/([0-9a-f]+):/gi){
#			push @results, $1;
#		}
	if(0){
	}else{#we will have to search for ourselves....
		while($search =~ m/([a-zA-Z0-9]+)/g){
				push @terms, lc($1);
		}
		foreach $term (@terms){
				my @set = ();
				$i++;
				$query = "select distinct docid from ";
				$query .= "wordindex, lexx where ";
				$query .= "lexx.word=" . $db->quote($term);
				$query .= " and";
				$query .= " wordindex.wordid = lexx.id;";
				$sth = $db->prepare($query);
				$sth->execute();
				while($result = $sth->fetchrow_arrayref()){
						if($i == 1){
							push @results, $result->[0];
						}else{
							push @set, $result->[0];
						}
						if($ranks{$result->[0]} < $result->[1]){
							$ranks{$result->[0]} = $result->[1];
						}
				}
				if($i != 1){
					@results = intersect(@results, @set);
				}
		}
		#now we can Cache our findings for future generations.... or probably just minutes
		$query = "insert into `QueryCache` (`Query`, `Results`, `Expire`) values (" . $db->quote($search);
		$query .= ", '";
		foreach (@results){
			$query .= "$_:";
		}
		$query .= "', ";
		$query .= time() + (5 * 60);
		$query .= ");";
		#$db->do($query);
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
    
    my $db = DBI->connect("DBI:$type:database=$database;host=$host", "$username", "$password") or return -1;
    
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
            $query = "select md5, title, size, url, rank, lastseen from sources where id=$item;";
            $sth = $db->prepare($query);
            $sth->execute();
            while($results = $sth->fetchrow_arrayref()){
                my $checksum = $results->[0];
                my $title = $results->[1];
                my $size = $results->[2];
		my $url = $results->[3];
		my $rank = $results->[4];
		my $lastseen = $results->[5];
                while($search =~ m/([a-zA-Z0-9]+)/g){ 
                    $string = "<b>$1</b>";
                    #$title =~ s/$1/$string/ig;   #loses case..BAD!
                }

# here -------
                print "<div class=\"result\">\n";
                print "<div class=\"filename\">";
                print "<a href=\"", $url, "\">", "$title</a></div> ";
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
                print "<div class=checksum>MD5 Checksum: $checksum</div>";
                print "<br>\n";
                print "<div class=\"grey_line\">";
                print "<div class=\"source\">";
                print "<a href=\"", $url, "\">", scale_down($url), "</a> ";
		print "Rank: ", $rank;
                print "</div>";
                print "<div class=\"date\">Last seen: ", scalar localtime($lastseen), " CST</div><br>\n";
                print "</div>";
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
    print "<a href=\"mailto:jason.whitehorn\@gmail.com\">Jason Whitehorn</a>, ";
	print "<a href=\"http://senas.sourceforge.net/\">source code</a> distributed under the";
	print "<a href=\"http://www.gnu.org/licenses/gpl.html\">GNU GPL</a></div></center>";
}

@EXPORT = qw(search, display);
