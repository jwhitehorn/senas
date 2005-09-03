#!/usr/bin/perl
#The oracle copyright 2004, 2005, Jason Whitehorn
my $version = "0.8.5";  
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
use POSIX qw(setsid);
use Fcntl;
use DBI;    #only works with transactional MySQL
use Digest::MD5 qw(md5_hex);
use URI;	#for link absolution

my $config_file = "/etc/senas.cfg";
my $action_fail = 1;	#const
my $action_update = 0;	#const

my $password;
my $username;
my $host;
my $database;
my $path;
my @parsers = ();
my $revisit_in = (30 * 24 * 60 * 60);   #30 days....DUN DUN DUNNN!!!!

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

do "$config_file" or die "Error opening configuration file.\n";
my $pipe = $path . "/senas/var/oracle.pipe";


if(lc($ARGV[0]) eq "stop"){
        open FIFO, ">$pipe";
        print FIFO "stop\n";
        close FIFO;
        exit 0;
}
if(!(lc($ARGV[0]) eq "start")){
        print "Error, invalid argument!\n";
        exit 1;
}
#else... start the daemon

chdir("/");
open STDIN, '/dev/null';
open STDOUT, '>/dev/null';
open STDERR, '>/dev/null';
umask(0);
my $pid = fork();
exit if $pid;   #exit if we are the parent
setsid or die $!;
sysopen(FIFO, "$pipe", O_NONBLOCK|O_RDONLY) or die $!;

my $debug = 0;
my $command;
my $db = DBI->connect("DBI:mysql:$DB:$DBHost", "$DBUser", "$DBPassword") or die "Error connection!\n";
while(1){
        $command = <FIFO>;
        if($command =~ m/stop/i){
				$sth->finish();
				$db->disconnect();
                exit;   #got stop command!
        }else{
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
						foreach $handler (@parsers){
							print "[DEBUG::oracle] Loading handler ", $handler, "\n" unless !$debug;
							load_handler($handler);
							if(handler_type() == $type){
								$found_handler = 1;
								handler($db, $data, $url, $MD5);
							}
						}
						if($found_handler == 0){
								print "[DEBUG::oracle] -->> No parser found for MIME type: $type\n" unless !$debug;
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
        }
        $command = "";

}
close FIFO;

