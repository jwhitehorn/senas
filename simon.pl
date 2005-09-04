#!/usr/bin/perl
#simon, web spider
#Copyright 2004, 2005, Jason Whitehorn
my $version = 2.0.5;
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

use LWP::RobotUA; 
use DBI;
use POSIX qw(setsid);
use Fcntl;

my $config_file = "/etc/senas.cfg";
my $last_save;

$password;
$username;
$host;
$database;
$path;

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

my $robot = LWP::RobotUA->new('simon/2.0', 'admin@mydomain.com');
$robot->max_size( (60*1024) );	#download upto 60Kbytes
$robot->max_redirect(0);	#no redirects!
my $db = DBI->connect("DBI:mysql:$database:$host", $username, $password)
    or die "Error connecting to database\n";
my $command;
sub allowed{
	my $url = shift;
	my $domain;
	my $try;
	if($mode == 0){
		return 1;
	}
	#mdoe 1
	if($url =~ m/^http:\/\/([^\/]+)\//i){
		$domain = lc($1);
		foreach $try (@allow){
			$try = lc($try) . "\$";
			$try =~ s/\./\\\./g;
			if($domain =~ $try){
				return 1;
			}
		}
	}
	return 0;
}
while(1){
        $command = <FIFO>;
        if($command =~ m/stop/i){
				$db->disconnect();
				close FIFO;
                exit;   #got stop command!
        }else{
			my $key = int(rand()*345789);
			$db->do("begin;");
			if($toggle){
				$query = "select URL from outgoing where id<$key order by Priority desc limit 1;";
				$toggle = 0;
			}else{
				$query = "select URL from outgoing where id>$key order by Priority desc limit 1;";
				$toggle = 1;
			}
			$sth = $db->prepare($query);
			$sth->execute();
			if($sth->rows == 1){
				$rows = $sth->fetchrow_arrayref();
				$url = $rows->[0];
				$query = "delete from outgoing where URL=";
				$query .= $db->quote($url) . ";";
				$db->do($query);
				$db->do("commit;");		
				if($allowed($url)){
					$reply = $robot->get($url);	#attempt to get URL	
					if($reply->is_success){
						#if we got something successfully
						my $page = $reply->content;
						my $time = time();
						my $data = $db->quote($page);
						my $lnk = $db->quote($url);
						my $contentType = $db->quote($reply->content_type);
						my $query = "insert into incoming (URL, Data, LastSeen, Action, Type) values(";
						$query .= "$lnk, $data, $time, $action_update, $contentType);";
						$db->do($query);
					}else{
						$query = "insert into incoming (URL, Action) values (";
						$query .= $db->quote($url) . ", $action_fail);";
						$db->quote($query);
					}
				}
			}else{	#nothing to do
				sleep 10;
			}
			$sth->finish();
        }
        $command = "";
}
#EOF
