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
use DBI;    #only works with transactional DBMSs
use POSIX qw(setsid);
use Fcntl;

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
		$query = "select url, id from sources order by id asc limit 500;";   
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
		$sth->finish;	#done with statement
#		$query = "select source, target from links;";
#		$sth = $db->prepare($query);
#		$sth->execute();
#		while($rows = $sth->fetchrow_arrayref()){
#			push @{$links{$rows->[1]}}, $rows->[0];
#		}
#		$sth->finish;
		for($i = 0; $i != 4; $i++){ #ten count feedback cycle
			foreach $url (@urls){
				$temp{$IDs{$url}} = $rating{$IDs{$url}};   
				#make a copy!
			}
			foreach $voteie (@urls){	#calculate Ri for this loop
#				foreach $source (@{$links{$voter}}){
				$query = "select target from links where ";
				$query .= "source=";
				$query .= $IDs{$voteie} . ";";
				$sth = $db->prepare($query);
				$sth->execute();
				while(@row = $sth->fetchrow_array()){
					$target = $row->[0];
					if(!($target eq $voteie)){
						$temp{$UDs{$voteie}} += $rating{$IDs{$target}} * $converge;	
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
			print scalar(localtime(time())), ":\t Done with cycle $i\n";
		}#end of feekback cycle
		foreach $url (@urls){
			$query = "update sources set rank=";
			$query .= $rating{$IDs{$url}} . " where id=";
			$query .= $IDs{$url} . ";";
			$db->do($query);
		}
		print scalar(localtime(time())), ":\t Bottom of loop!\n";
        }
	sleep 10;
        $command = "";
}
#EOF
