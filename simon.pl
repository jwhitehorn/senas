#!/usr/bin/perl
#simon, web spider
#Copyright 2004, 2005, Jason Whitehorn
my $version = 2.0.4;
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

use LWP::RobotUA; 
use URI;	#for link absolution
use DBI;
$| = 1;

my $robot = LWP::RobotUA->new('simon/2.0', 'admin@mydomain.com');
$robot->max_size( (60*1024) );	#download upto 60Kbytes
$robot->max_redirect(0);	#no redirects!
my $running = 1;	#turn on by default


my $last_save;# = time();
my $mysql_user;# = "username";
my $mysql_server;# = "127.0.0.1";
my $mysql_pass;# = "password";
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



my $db = DBI->connect("DBI:mysql:$mysql_db:$mysql_server", $mysql_user, $mysql_pass)
    or die "Error connecting to database\n";
    
my $action_fail = 1;
my $action_update = 0;
srand(time());
while($running){
	#run-time loop
	#my $key = int(rand()*4294967295);
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
        print "Getting $url...";
        $reply = $robot->get($url);	#attempt to get URL	
        if($reply->is_success){
            print "OK\n";
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
            print "FAILED\n";
            $query = "insert into incoming (URL, Action) values (";
            $query .= $db->quote($url) . ", $action_fail);";
            $db->quote($query);
        }
#        $query = "delete from outgoing where URL=";
#        $query .= $db->quote($url) . ";";
#        $db->do($query);
#        $db->do("commit;");
    }else{
        #$db->do("commit;");
        #nothing to do
        sleep 10;
    }
}

sub handler_
