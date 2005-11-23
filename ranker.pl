#!/usr/bin/perl
#The oracle copyright 2004, 2005, Jason Whitehorn
my $version = "1.0";  
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


#Mon Nov  7 23:11:15 2005:        Top of loop!
#Mon Nov  7 23:11:51 2005:        Done fetching 207241 documents
#        Working on cycle 0: [207241/207241]
#Tue Nov  8 01:48:05 2005:        Done with cycle 0
#        Working on cycle 1: [207241/207241]
#Tue Nov  8 04:10:42 2005:        Done with cycle 1
#        Working on cycle 2: [207241/207241]
#Tue Nov  8 06:32:11 2005:        Done with cycle 2
#        Working on cycle 3: [207241/207241]
#Tue Nov  8 09:02:08 2005:        Done with cycle 3
#Tue Nov  8 09:26:06 2005:        Bottom of loop!
#Total elapsed time: 614.25 minutes

use DBI;    #only works with transactional DBMSs
use POSIX qw(setsid);
use Fcntl;
$| = 1;
my $config_file = "/etc/senas.cfg";

$password;
$host;
$database;
$username;
$path;
$type;

do "$config_file" or die "Senas::ranker Error reading $config_file\n";

my $log_file = $path . "/senas/var/senas.log";
my $pipe = $path . "/senas/var/ranker.pipe";
my $debug = 0;
if(lc($ARGV[0]) eq "stop"){
        open FIFO, ">$pipe";
        print FIFO "stop\n";
        close FIFO;
        exit 0;
}
if(lc($ARGV[0]) eq "debug"){
	$ARGV[0] = "start";
	$debug = 1;
}
if(!(lc($ARGV[0]) eq "start")){
        print "Error, invalid argument!\n";
        exit 1;
}
#else... start the daemon

chdir("/") unless $debug;
open STDIN, '/dev/null' unless $debug;
open STDOUT, '>/dev/null' unless $debug;
open STDERR, '>/dev/null' unless $debug;
umask(0) unless $debug;
my $pid;
if(!$debug){
	$pid = fork();
	exit if $pid;   #exit if we are the parent
	setsid or die $!;
}
sysopen(FIFO, "$pipe", O_NONBLOCK|O_RDONLY) or die $!;

my $command;
		#	print "[DEBUG::Ranker] Ranker started.\n" unless !$debug;
$db = DBI->connect("DBI:$type:database=$database;host=$host", "$username", "$password")
				or die "Error connecting to database\n";
$db->do("set enable_seqscan = off;");
while(1){
        $command = <FIFO>;
        if($command =~ m/stop/i){
		$sth->finish;
		$db->disconnect();
		close FIFO;
                exit;   #got stop command!
        }else{
		my $start = time();
		my %rating = ();
		my %temp = (); 
		my %IDs = ();
		my @urls = ();
		my $start = 0;
		my $elements = 0;
		my $converge = 0.001;
		my %links = ();
		print scalar(localtime(time())), ":\t Top of loop!\n";
		$query = "select url, id from sources;";   
		$sth = $db->prepare($query);
		$sth->execute(); #get EVERYTHING...this will take a while
		$elements = $sth->rows;
		my $URL;
		while($rows = $sth->fetchrow_arrayref()){
			$URL = $rows->[0];
			$ID = $rows->[1];
			$rating{$ID} = 1.0;
			$IDs{$URL} = $ID;	#ID to URL mapping
			push @urls, $URL;
		}
		print scalar(localtime(time())), ":\t Done fetching ", $sth->rows, " documents\n";
		my $start = time();
		$sth->finish;	#done with statement
		for($i = 0; $i != 4; $i++){ #ten count feedback cycle
			print "\tWorking on cycle $i: ";
			foreach $url (@urls){
				$temp{$IDs{$url}} = $rating{$IDs{$url}};   
				#make a copy!
			}
			$x = 0;
			my $message;
			foreach $votie (@urls){	#calculate Ri for this loop
				if($x){
					for($j = 0; $j != length($message); $j++){
						print "\b";
					}
				}
				$x++;
				$message = "[$x/" . scalar(@urls) . "]";
				print $message;
				$query = "select source from links where ";
				$query .= "target=";
				$query .= $db->quote($votie) . ";";
				$sth = $db->prepare($query);
				$sth->execute();
				while($row = $sth->fetchrow_arrayref()){
					$voter = $row->[0];
					if(!($votie eq $voter)){
						$temp{$IDs{$votie}} += $rating{$voter} * $converge;
						$command = <FIFO>;	#here is a good time to exit..if
						if($command =~ m/stop/i){	#we get the stop command
							$sth->finish;
							$db->disconnect();
							exit;   #got stop command!
						}
					}
				}
#				$sth->finish;
			}#Ri found
			foreach $url (@urls){
				$rating{$IDs{$url}} = $temp{$IDs{$url}};   
				#copy back...
			}
			print "\n";
			print scalar(localtime(time())), ":\t Done with cycle $i\n";
		}#end of feekback cycle
		$x = 0;
		print "\tUpdating rankings: ";
		foreach $url (@urls){
			if($x){
				for($j = 0; $j != length($message); $j++){
					print "\b";
				}
			}
			$x++;
			$message = "[$x/" . scalar(@urls) . "]";
			print $message;
			$query = "update sources set rank=";
			$query .= $rating{$IDs{$url}} . " where id=";
			$query .= $IDs{$url} . ";";
			$db->do($query);
			#print $IDs{$url}, "\t";
		}
		print "\n";
		print scalar(localtime(time())), ":\t Bottom of loop!\n";
		print "Total elapsed time: ", (time() - $start)/60, " minutes\n";
        }
	sleep 10;
        $command = "";
}
#EOF
