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

my $pipe = "/usr/local/senas/var/simon.pipe";
my $config_file = "/etc/senas.cfg";
my $last_save;
my $mysql_user;
my $mysql_server;
my $mysql_pass;
my $mysql_db;

open FILE, "<$config_file";
while(<FILE>){
	if( $_ =~ m/password=([^;]*);/){
		$mysql_pass = $1;
	}
	if( $_ =~ m/username=([^;]*);/){
		$mysql_user = $1;
	}
	if( $_ =~ m/host=([^;]*);/){
		$mysql_server = $1;
	}
	if( $_ =~ m/database=([^;]*);/){
		$mysql_db = $1;
	}
}
close FILE;

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
my $db = DBI->connect("DBI:mysql:$mysql_db:$mysql_server", $mysql_user, $mysql_pass)
    or die "Error connecting to database\n";
my $command;
while(1){
        $command = <FIFO>;
        if($command =~ m/stop/i){
				$db->disconnect();
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
			}else{	#nothing to do
				sleep 10;
			}
			$sth->finish();
        }
        $command = "";
}
close FIFO;

#EOF
