#!/usr/bin/perl
#The oracle copyright 2004, 2005, Jason Whitehorn
my $version = "0.8.1";  
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
my @parsers = ("./mime_parsers/html.pl");	#put your MIME-type parsers here!


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

use DBI;    #only works with transactional MySQL
use Digest::MD5 qw(md5_hex);
use URI;	#for link absolution
use threads;
use threads::shared;
my $debug = 1;		#output debug messages to console
my $run_ranker = 1;	#run page ranker thread


my $action_fail = 1;
my $action_update = 0;



my $revisit_in = (30 * 24 * 60 * 60);   #30 days....DUN DUN DUNNN!!!!
$running = 1;
share($running);
share($debug);
sub load_handler{
        my $filename = $_[0];
        my $data;
        open FILE, "<$filename";
		while(<FILE>){
                $data = $data . $_;
        }
        close FILE;
        eval($data);
}
sub inputReader{
    #if child
    while(1){
        $input = <STDIN>;
        $input =~ s/\n//g;
        if("$input" eq "stop"){
            print "Stopping...";
            $running = 0;
            return 0;
        }
    }
}
sub Ranker{
	print "[DEBUG::Ranker] Ranker started.\n" unless !$debug;
	$db = DBI->connect("DBI:mysql:$DB:$DBHost", "$DBUser", "$DBPassword")
		or die "Error connecting to database\n";
	while($running){
		my $start = time();
		my %rating = ();
		my %temp = (); 
		my %MD5s = ();
		my @urls = ();
		my $start = 0;
		my $elements = 0;
		my $converge = 0.001;
		$query = "select URL, MD5 from `Sources`;";    #get EVERYTHING...this will take a while
		$sth = $db->prepare($query);
		$sth->execute();
		$elements = $sth->rows;
		my $URL;
		print "[DEBUG::Ranker] Beginning ranking $elements elements.\n" unless !$debug;
		while($rows = $sth->fetchrow_arrayref()){
			$URL = $rows->[0];
			$MD5 = $rows->[1];
			$rating{$URL} = 1.0;
			$MD5s{$URL} = $MD5;
			push @urls, $URL;
		}
		for($i = 0; $i != 10; $i++){
		# print "$i";
		#	print ".";
			foreach (@urls){
				$temp{$_} = $rating{$_};   #make a copy!
			}
			foreach (@urls){
			#    print "|";
				my $voter = $_;
				$MD5 = $MD5s{$voter};
				$MD5 = $db->quote($MD5);
				$query = "select Target from Links where Source=$MD5;";
				$sth = $db->prepare($query);
				$sth->execute();
				while(@row = $sth->fetchrow_array()){
					if(!($row[0] eq $voter)){
						$temp{$row[0]} += $rating{$voter} * $converge;
						if(!$running){
							return;
						}
					}
				}
			}
			foreach(@urls){
				$rating{$_} = $temp{$_};   #copy back...
			}
			print "[DEBUG::Ranker] ", ($i + 1), "/10th done!\n" unless !$debug;
		}

		foreach(@urls){
			#  print $_, "\t", $rating{$_}, "\n";
			$query = "update `Sources` set Rank=";
			$query .= $rating{$_} . " where URL=";
			$query .= $db->quote($_) . ";";
			$db->do($query);
		}
		print "[DEBUG::Ranker] $elements completed in " . (((time() - $start)/60)/60) . " hours\n" unless !$debug;
	}
	$sth->finish;
	$db->disconnect();
}
print "Project Senas (http://www.senas.org), copyright 2004, 2005, Jason Whitehorn.\n";
print "oracle version $version\n";
print "\tTo shutdown, type 'stop'\n\n";
$Ithread = threads->new(\&inputReader) or die "Error creating I thread.\n";
if( $run_ranker) {
	$Rthread = threads->new(\&Ranker) or die "Error creating Ranker thread.\n";
}

do{
    $db = DBI->connect("DBI:mysql:$DB:$DBHost", "$DBUser", "$DBPassword") or die "Error connection!\n";
    while($running){   #run-time loop		
        $db->do("begin;");  #start transaction
        $query = "select URL, Data, LastSeen, Action, Type from incoming order by LastSeen asc limit 1";
        $sth = $db->prepare($query);
        $sth->execute();
        if($sth->rows > 0){	#if the oracle has something to do!!!!
            print "[DEBUG::oracle] Something to do!\n" unless !$debug;
            $rows = $sth->fetchrow_arrayref();
            my $url = $rows->[0];
            my $data = $rows->[1];
            my $LastSeen = $rows->[2];
            my $action = $rows->[3];
            my $type = $rows->[4];
            my $MD5 = md5_hex($data);
            if($action == $action_update){
                print "[DEBUG::oracle] update request for $MD5\n" unless !$debug;
                #We have a valid URL coming in....
                $query = "select MD5 from `Index` where MD5=";
                $query .= $db->quote($MD5) . ";";
                $sth = $db->prepare($query);
                $sth->execute();
                if($sth->rows == 0){ #if this is the first time we have seen this exact data
                    print "[DEBUG::oracle] item is new entry\n" unless !$debug;
					$lnk = $db->quote($url);
					$s = $db->prepare("select MD5 from `Sources` where URL=$lnk;");
					$s->execute();
					if($s->rows > 0){	#we have seen this URL before, and it has changed.			
						$dup = $s->fetchrow_arrayref();
						$chk = $db->quote($dup->[0]);
						print "[DEBUG::oracle] Dup. entry, deleting MD5=", $dup->[0], "\n" unless !$debug;
						$db->do("delete from `Sources` where URL=$lnk;");	#remove this old entry
						$s = $db->prepare("select MD5 from `Sources` where MD5=$chk;");
						$s->execute();
						if($s->rows == 0){	#if this was the only source we just deleted...then
							#print "Index removed\n";
							$db->do("delete from `Index` where MD5=$chk;");
							$db->do("delete from Links where Source=$chk;");
							$db->do("delete from WordIndex where MD5=$chk;");
						}
					}
                    #insert into Index
                    $query = "insert into `Index` (MD5, Cache, TSize) values (";
                    $query .= $db->quote($MD5) . ", " . $db->quote($data) . ", " . length($data) . ");";
                    $sth = $db->prepare($query);
                    $sth->execute();	#insert into index....

					#find a parser for the particular MIME type
					$found_handler = 0;	#we have not found a handler yet, so don't assume anything
					foreach(@parsers){
						print "[DEBUG::oracle] Loading handler ", $_, "\n" unless !$debug;
						load_handler($_);
						if(handler_type() == $type){
							$found_handler = 1;
							handler($db, $data, $url, $MD5);
						}
					}
                    if($found_handler == 0){
							print "[DEBUG::oracle] No parser found for MIME type: $type\n" unless !$debug;
					}
                    #obviously we do not know of this source....so put it in sources
					$query = "insert into Sources (URL, MD5, LastSeen, Type) values (";
                    $query .= $db->quote($url) . ", " . $db->quote($MD5) . ", $LastSeen, ";
                    $query .= $db->quote($type) . ");";
					$db->do($query);	#insert into sources
                }else{   #we have seen this data before
                    $query = "select MD5 from Sources where MD5=";
                    $query .= $db->quote($MD5) . ";";
                    $sth = $db->prepare($query);
                    $sth->execute();
                    if($sth->rows == 0){
                        #IF this is the first time to seen this source...add it to Sources
                        $query = "insert into Sources (URL, MD5, LastSeen, Type) values (";
                        $query .= $db->quote($url) . ", " . $db->quote($MD5) . ", $LastSeen, ";
                        $query .= $db->quote($type) . ");";
                        $db->do($query);
                    }else{
                        #ELSE update the LastSeen value for this source
                        $query = "update `Sources` set LastSeen=$LastSeen where URL=";
                        $query .= $db->quote($url) . ";";
                        $db->do($query);
                        $query = "update `Sources` set Type=" . $db->quote($type);
                        $query .= " where URL=" . $db->quote($url) . ";";
                        $db->do($query);
                    }
                }
            }else{
                if($action == $action_fail){
                    #something we asked for is not valid....
                    #delete it from the DB if it exists in the DB
                }
            }
            #delete item from incoming...so we don't double our work ;-)
            $db->do("delete from incoming where LastSeen=$LastSeen and Data=" . $db->quote($data) . ";");
        }else{  #if there is nothing in the incoming table
            print "[DEBUG::oracle] Nothing to do, sleeping\n" unless !$debug;
            sleep 60 * 2; #we will sleep a little extra this time around...
			
			#insert into outgoing sources we have not seen in $revisit_in time!
        }
        $db->do("commit;");
        $query = "delete from `QueryCache` where `Expire` < " . time() . ";"; 
        $db->do($query);    #delete outdated query cache entries
		#---------HACK below!!!------
#		if($use_hack){
#			print "[DEBUG::oracle] 300 off, 1 on hack begun!\n" unless !$debug;
#			$query = "select MD5 from `Index`;";
#			$sth = $db->prepare($query);
#			$sth->execute();
#			while($row = $sth->fetchrow_arrayref()){
#				my $MD5 = $db->quote($row->[0]);
#				$query = "select MD5 from `Sources` where MD5=$MD5;";
#				$s = $db->prepare($query);
#				$s->execute();
#				if($s->rows == 0){
#					#print $MD5, "\n";
#					$db->do("delete from `Index` where MD5=$MD5;");
#					$db->do("delete from WordIndex where MD5=$MD5;");
#					$db->do("delete from Links where Source=$MD5;");
#				}
#			}
#			$use_hack = 0;
#			exit;
	#	}
		#----------END OF HACK____________
    }#end run-time loop
    $sth->finish();
    $db->disconnect();
    $Ithread->join();
	$Rthread->join();
    print "DONE\n";
    exit(1);
}

#main program
#my $pid = fork();
#if(!defined($pid)){
#    print "Error spawning child!\n";
#    exit $!;
#}
#if($pid == 0){  #child process
#    $stop = 0;
#    my $thread = threads->new(\&index) or die "Error spawning index thread.\n";
#    while(1){
#        sleep 60;
#    }
#}
#exit 1; #parent return
