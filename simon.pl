#!/usr/bin/perl
#simon, web spider
#Copyright 2004, 2005, Jason Whitehorn
#http://www.senas.org
my $version = 2.1.0;
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
$| = 1;

use LWP::RobotUA; 
use DBI;
use POSIX qw(setsid);
use Fcntl;
use URI;
use MIME::Base64;

my $config_file = "/etc/senas.cfg";
my $last_save;

$password;
$username;
$host;
$database;
$path;
$type;

$mode;	#mode 0 = allow everything, mode 1 = allow only specified domains
@allow = ();

do "$config_file" or die "Error opening configuration file.\n";
my $pipe = $path . "/senas/var/simon.pipe";

my $action_fail = 1;		#const
my $action_update = 0;		#const
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

my $robot = LWP::RobotUA->new('simon/2.1', 'admin@domain.com');
$robot->max_size( (60*1024) );	#download upto 60Kbytes
$robot->max_redirect(0);	#no redirects!
$robot->delay(0/60);		
$robot->timeout(25);
#$robot->use_sleep(0);
my $delay = 20 * 60;
my $db = DBI->connect("DBI:$type:database=$database;host=$host", $username, $password)
    or die "Error connecting to database\n";
$db->{AutoCommit} = 0;	#turn on transactions
$db->{RaiseError} = 0;	#non-commital error handle
my $command;
sub allowed{
	my $url = shift;
	my $domain;
	my $try;
	my $i;
	if($url eq ""){
		return 0;
	}
	if($mode == 0){
		return 1;
	}
	#mdoe 1
	if($url =~ m/^http:\/\/([^\/]+)\//i){
		$domain = lc($1);
		foreach $i (@allow){
			$try = lc($i) . "\$";
			$try =~ s/\./\\\./g;
			if($domain =~ $try){
				return 1;
			}
		}
	}
	return 0;
}

my @urls = ();
my %log = ();
my $lowThresh = 8900;
my $highThresh = 9000;

sub getNetloc{
	my $url = shift;
	my $add = URI->new($url);
	if(($add->scheme eq "http") or ($add->scheme eq "https")){
	return $add->host . ":" . $add->port;
	}
}
sub ttRetry{
	my $netloc = shift;
	my $ttr = 0; 
	if(exists($log{$netloc})){
		$ttr = $delay - (time() - $log{$netloc});
		if($ttr < 0){
			$ttr = 0;
		}
	}
	return $ttr;
}

sub nextURL{
	my $lowest = time() + 400;	#big...
	my $url = "";
	my $location = -1;
	my $add;
	my $i = 0;
	print "Size: ", scalar(@urls), "\n";
	foreach $possible (@urls){
		#print "Possibly $possible\n";
		if( ttRetry(getNetloc($possible)) < $lowest){
			$lowest = ttRetry(getNetloc($possible));
			$url = $possible;
			$location = $i;
			if($lowest == 0){
				splice @urls, $location, 1;
				print "Lowest delay: $lowest **\n";	
				$log{getNetloc($possible)} = time();
				return $possible;
			}
		}
		$i++;
	}
	if($location != -1){
		splice @urls, $location, 1;
		print "Lowest delay: $lowest\n";
		sleep $lowest;
		$log{getNetloc($url)} = time();
	}
	return $url;
}
while(1){
	print "*******\n";
        $command = <FIFO>;
        if($command =~ m/stop/i){
		foreach $url (@urls){
			$query = "insert into outgoing (URL) values(";
			$query .= $db->quote($url);
			$query .= ");";
			$db->do($query);
			$db->commit;
		}
		$db->disconnect();
		close FIFO;
                exit;   #got stop command!
        }else{
	#			my $key = int(rand()*345789);
		if(scalar(@urls) < $lowThresh){
			$query = "select URL from outgoing order by priority ";
			$query .= "desc limit " . ($highThresh - scalar(@urls));
			$query .= ";";
			$sth = $db->prepare($query);
			$sth->execute();
			print "Refilling buffer...";
			$query = "delete from outgoing where URL= ?;";
			$st = $db->prepare($query);
			while($rows = $sth->fetchrow_arrayref()){
				$url = $rows->[0];
				$used = 0;
				foreach $possible (@urls){
					if($possible eq $url){
						$used = 1;
					}
				}
				if(!$used){
					push @urls, $url;
				}
				$st->execute($url);
			}
			$db->commit;
			$sth->finish();
			$st->finish();
			print "DONE\n";
			if(scalar(@urls) == 0){
				sleep 30;
			}
		}
		$url = nextURL();		
		print "NExt: $url\n";
		if( (allowed($url)) ){
			$reply = $robot->get($url);	#attempt to get URL	
			if($reply->is_success){
				print "GOT IT!\n";
				#if we got something successfully
				my $page = $reply->content;
				my $time = time();
				my $data = $db->quote(encode_base64($page));
				my $lnk = $db->quote($url);
				my $contentType = $db->quote($reply->content_type);
				my $query = "insert into incoming (url, cache, lastseen, action, type) values(";
				$query .= "$lnk, $data, $time, $action_update, $contentType);";
				$db->do($query);
			}else{
				print "FAILED\n";
				$query = "insert into incoming (url, action, cache, lastseen) values (";
				$query .= $db->quote($url) . ", $action_fail, " . $db->quote("foo") . ", " . time() . ");";
				$db->do($query);
			}
			$db->commit;
		}
        }
	$command = "";
}
#EOF
