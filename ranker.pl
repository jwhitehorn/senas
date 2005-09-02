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

my $config_file = "/etc/senas.cfg";
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
use DBI;    #only works with transactional MySQL
use POSIX qw(setsid);


chdir("/");
open STDIN, '/dev/null';
#open STDOUT, '>/dev/null';
open STDERR, '>/dev/null';
umask(0);
my $pid = fork();
exit if $pid;   #exit if we are the parent
setsid or die $!;

#we are now a daemon... get to work!
my $running = 1;	#go!
sub Ranker{
#	print "[DEBUG::Ranker] Ranker started.\n" unless !$debug;
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
#		print "[DEBUG::Ranker] Beginning ranking $elements elements.\n" unless !$debug;
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
			#print "[DEBUG::Ranker] ", ($i + 1), "/10th done!\n" unless !$debug;
		}

		foreach(@urls){
			#  print $_, "\t", $rating{$_}, "\n";
			$query = "update `Sources` set Rank=";
			$query .= $rating{$_} . " where URL=";
			$query .= $db->quote($_) . ";";
			$db->do($query);
		}
		#print "[DEBUG::Ranker] $elements completed in " . (((time() - $start)/60)/60) . " hours\n" unless !$debug;
		sleep 60;
	}
	$sth->finish;
	$db->disconnect();
}
Ranker();