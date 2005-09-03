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
use DBI;    #only works with transactional MySQL
use POSIX qw(setsid);
use Fcntl;

my $pipe = "/usr/local/senas/var/ranker.pipe";
my $config_file = "/etc/senas.cfg";
my $log_file = "/usr/local/senas/var/senas.log";

my $DBPassword;
my $DBHost;
my $DB;
my $DBUser;

open FILE, "<$config_file" or die "Senas::ranker Error reading $config_file\n";
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
open LOG, ">>$log_file" or die $!;

my $command;
		#	print "[DEBUG::Ranker] Ranker started.\n" unless !$debug;
$db = DBI->connect("DBI:mysql:$DB:$DBHost", "$DBUser", "$DBPassword")
				or die "Error connecting to database\n";
while(1){
        $command = <FIFO>;
        if($command =~ m/stop/i){
				$sth->finish;
				$db->disconnect();
				close LOG;
                exit;   #got stop command!
        }else{
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
			while($rows = $sth->fetchrow_arrayref()){
				$URL = $rows->[0];
				$MD5 = $rows->[1];
				$rating{$URL} = 1.0;
				$MD5s{$URL} = $MD5;
				push @urls, $URL;
			}
			for($i = 0; $i != 10; $i++){
				foreach (@urls){
					$temp{$_} = $rating{$_};   #make a copy!
				}
				foreach (@urls){
					my $voter = $_;
					$MD5 = $MD5s{$voter};
					$MD5 = $db->quote($MD5);
					$query = "select Target from Links where Source=$MD5;";
					$sth = $db->prepare($query);
					$sth->execute();
					while(@row = $sth->fetchrow_array()){
						if(!($row[0] eq $voter)){
							$temp{$row[0]} += $rating{$voter} * $converge;
							
							$command = <FIFO>;	#here is a good time to exit..if
							if($command =~ m/stop/i){	#we get the stop command
								$sth->finish;
								$db->disconnect();
								exit;   #got stop command!
							}
						}
					}
				}
				foreach(@urls){
					$rating{$_} = $temp{$_};   #copy back...
				}
			}
			foreach(@urls){
				$query = "update `Sources` set Rank=";
				$query .= $rating{$_} . " where URL=";
				$query .= $db->quote($_) . ";";
				$db->do($query);
			}
			print LOG "[Ranker] $elements completed in " . (((time() - $start)/60)/60) . " hours\n";
        }
		sleep 10;
        $command = "";

}
close FIFO;
