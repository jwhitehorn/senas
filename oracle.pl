#!/usr/bin/perl
#The oracle copyright 2004, 2005, Jason Whitehorn
#Project Senas http://www.senas.org
my $version = "0.9.1";  
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
use MIME::Base64;
use threads;
use threads::shared;
#use Compress::Bzip2;

my $config_file = "/etc/senas.cfg";
my $action_fail = 1;	#const
my $action_update = 0;	#const

my $debug = 0;			#do you want to run in debug mode? TRUE/FALSE
my $compress_cache = 0;	#you probably want this!
my $idle_delay = 20;	#in one second increments
$password;
$username;
$host;
$database;
$path;
$type;

@parsers = ();
my $revisit_in = (30 * 24 * 60 * 60);   #30 days....DUN DUN DUNNN!!!!
my $allowed_failures = 3;				#a page can fail this many times, before being deleted
my $time_between_retries = (30 * 60);	#30 minutes
my %parserBuffer = ();
sub load_handler{
        my $filename = $_[0];
	if(defined($parserBuffer{$filename})){
		return eval($parserBuffer{$filename});
	}
        my $data;
        open FILE, "<$filename";
		while(<FILE>){
                $data = $data . $_;
        }
        close FILE;
	$parserBuffer{$filename} = $data;
        return eval($data);
}

do "$config_file" or die "Error opening configuration file.\n";
my $pipe = $path . "/senas/var/oracle.pipe";


if(lc($ARGV[0]) eq "stop"){
        open FIFO, ">$pipe";
        print FIFO "stop\n";
        close FIFO;
        exit 0;
}
if(lc($ARGV[0]) eq "debug"){
	$ARGV[0] = "start";
	$debug = 1;
}else{
	$debug = 0;
}
if(!(lc($ARGV[0]) eq "start") ){
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
my @toDo = ();
share(@toDo);
my $db = DBI->connect("DBI:$type:database=$database;host=$host", "$username", "$password") or die "Error connection!\n";
$db->{AutoCommit} = 0;	#turn on transactions
$db->{RaiseError} = 1;	#non-commital error handle
$db->do("set enable_seqscan = off;");
my %lexx = ();	#"Keanu Reeves in: My Own Private Airfield."	-Tom Servo
sub wordid{
	my $word = shift;
	my $done = 1;
	if(!defined($lexx{$word})){
		do{
			eval{
				my $query = "select id from lexx where word=";
				$query .= $db->quote($word) . ";";
				my $sth = $db->prepare($query);
				$sth->execute();
				if($sth->rows == 0){
					$sth->finish;
					$query = "insert into lexx (word) values(";
					$query .= $db->quote($word) . ");";
					$db->do($query);
					$db->commit;
					$query = "select id from lexx where word=";
					$query .= $db->quote($word) . ";";
					$sth = $db->prepare($query);
					$sth->execute();
				}
				my $rows = $sth->fetchrow_arrayref();
				$lexx{$word} = $rows->[0];
				$db->commit;
			};
			if($@){
				$db->rollback;
				$done = 0;
			}else{ $done = 1; }
		}while(!$done);	#loop while we have commit errors
		$sth->finish;
	}
	return $lexx{$word};
}
sub push_link{
	my $id = $_[0];
	my $link = $_[1];
	my $query;
	$query =  "insert into links (source, target) values ($id, ";
	$query .= $db->quote($link) . ");";
	unshift @toDo, $query;
#	$query = "insert into outgoing (url) values (";
#	$query .= $db->quote($link) . ");";
#	unshift @toDo, $query;
}
sub push_word{
	my $id = $_[0];
	my $word = $_[1];
	my $location = $_[2];
	my $wordid = wordid($word);
	my $query = "insert into wordindex (wordid, docid, location) values(";
	$query .= "$wordid, $id, $location);";
	unshift @toDo, $query;
}
sub push_title{
	my $id = $_[0];
	my $title = $_[1];
	my $query = "update sources set title=";
	$query .= $db->quote($title) . " where id=$id;";
	unshift @toDo, $query;
}
my $running = 2;
share($running);
my $queue_lock;
share($queue_lock);
print "oracle $version has been started in debug mode\n" unless !$debug;
print "to stop, issue 'oracle.pl stop' from another terminal.\n\n" unless !$debug;
sub db_whore{
	my $db = DBI->connect("DBI:$type:database=$database;host=$host", "$username", "$password") or die "Error connection!\n";
	while($running){
		if(!$queue_lock and scalar(@toDo)){
			$db->do(pop @toDo);
		}else{
			sleep 1;
		}
	}
	while(scalar(@toDo)){ $db->do(pop @toDo); }
}
sub controll{
	my $command;
	sysopen(FIFO, "$pipe", O_NONBLOCK|O_RDONLY) or die $!;
	while(1){
		$command = <FIFO>;
		if($command =~ m/stop/i){
			close FIFO;
			$running--;
			return 0;   #got stop command!
		}else{
			sleep 1;
		}
		$command = "";
	}
}
my @threads = ();
$queue_lock = 0;
$threads[0] = threads->new(\&db_whore);
$threads[1] = threads->new(\&controll);
my $start_time = time()-1;
my $count = 0;
while($running > 1){
	eval{
		$query = "select url, cache, lastseen, action, type from incoming limit 1;";
		$sth = $db->prepare($query);
		$sth->execute();
		if($sth->rows > 0){	#if the oracle has something to do!!!!
			$count++;
			print "[DEBUG::oracle] Something to do!\n" unless !$debug;
			$rows = $sth->fetchrow_arrayref();
			my $url = $rows->[0];
			my $data = decode_base64($rows->[1]);
			my $LastSeen = $rows->[2];
			my $action = $rows->[3];
			my $type = $rows->[4];
			my $MD5 = md5_hex($data);
			$sth->finish;
			#$queue_lock = 1;
			$db->do("delete from incoming where url=" . $db->quote($url) . ";");
			$db->commit;
			if($action == $action_update){
				print "[DEBUG::oracle] update request for $MD5\n" unless !$debug;
				#We have a valid URL coming in....
				$query = "select id, md5 from sources where url=";
				$query .= $db->quote($url) . ";";
				$sth = $db->prepare($query);
				$sth->execute();
				if($sth->rows == 0){ 
					#if this is the first time we have seen this exact data
					$row = $sth->fetchrow_arrayref();
					if(!($row->[1] eq $MD5)){
						#if the url has changed...
						$db->do("delete from sources where url=" . $db->quote($url) . ";");
					}
					$sth->finish;
					print "[DEBUG::oracle] item is new entry\n" unless !$debug;
					#insert into Index
					$query = "insert into sources (md5, cache, encoding, size, url, lastseen, lastaction, type) values (";
					$query .= $db->quote($MD5) . ", ";
					$query .= $db->quote(encode_base64($data));
					$query .=", 0";
					$query .= ", " . length($data) . ", ";
					$query .= $db->quote($url) . ", ";
					$query .= "$LastSeen, $LastSeen, " . $db->quote($type) . ");";
						$db->do($query);
						$db->commit;
						#find id of last insert...
						$query = "select id from sources where url=" . $db->quote($url) . ";";
						$sth = $db->prepare($query);
						$sth->execute();
						$rows = $sth->fetchrow_arrayref();
						$id = $rows->[0];
						$sth->finish;
						#$queue_lock = 0;
						#find a parser for the particular MIME type
						$found_handler = 0;	#we have not found a handler yet, so don't assume anything
						foreach $handler (@parsers){
							print "[DEBUG::oracle] Loading handler ", $handler, "\n" unless !$debug;
							load_handler($handler);
							if(handler_type() eq $type){
								$found_handler = 1;
								handler($data, $url, $id);
							}
						}
						if($found_handler == 0){
							print "[DEBUG::oracle] -->> No parser found for MIME type: $type\n" unless !$debug;
						}
							#$queue_lock = 1;
				}else{   #we have seen this data before
					$row = $sth->fetchrow_arrayref();
					$id = $row->[0];
					$db->do("update sources set lastseen=$LastSeen where id=$id;");
					$db->do("update sources set lastaction=$LastSeen where id=$id");
					$db->do("update sources set type=" . $db->quote($type) . " where id=$id;");
					$db->do("update sources set failures=0 where id=$id;");
					$sth->finish;
				}
			}else{
				if($action == $action_fail){
					#something we asked for is not valid....
					print "[DEBUG::oracle] Action failure for $url\n" unless !$debug;
					$query = "select id, failures from sources where url=" . $db->quote($url) . ";";
					$sth = $db->prepare($query);
					$sth->execute();
					if($sth->rows != 0){
						$rows = $sth->fetchrow_arrayref();
						$id = $rows->[0];
						my $fails = $rows->[1];
						if($fails > $allowed_failures){
							print "[DEBUG::oracle] deleting source\n" unless !$debug;
							$db->do("delete from sources where id=$id;");
						}else{
							#it has not reached critical...just give it a mark
							print "[DEBUG::oracle] failure noted\n" unless !$debug;
							$query = "update sources set failures=";
							$query = $query . ($fails + 1);
							$query = $query . " where id=$id;";
							$db->do($query);
						}
					}
				}
			}
		}else{  #if there is nothing in the incoming table
			$sth->finish;
			while(scalar(keys(%lexx))){
				delete $lexx{(keys(%lexx))[0]};	#remove a cached lexx
			}
			print "[DEBUG::oracle] Nothing to do, sleeping\n" unless !$debug;
			sleep 20; #we will sleep a little extra this time around...
			#insert into outgoing sources we have not seen in $revisit_in time!
			$query = "select url, id from sources where lastseen<" . (time()-$revisit_in);
			$query = $query . " and lastaction<" . (time() - $time_between_retries) . " limit 40;";
			$sth = $db->prepare($query);
			$sth->execute();
			while($rows = $sth->fetchrow_arrayref()){	#for each return source
				$url = $rows->[0];
				$id = $rows->[1];
				$sth->finish();
				$query = "select priority from outgoing where url=" . $db->quote($url) . ";";
				$sth = $db->prepare($query);
				$sth->execute();
				if($sth->rows == 0){
					print "[DEBUG::oracle] request revist of $url\n" unless !$debug;
					$query = "insert into outgoing (url, priority) values(";
					$query = $query . $db->quote($url) . ", 4);";
					$db->do($query);
					$query = "update sources set lastaction=" . time();
					$query = $query . " where id=$id;";
					$db->do($query);
				}
			}
		}	#end SELECT IF/ELSE Block
		$db->commit;
	};
	if($@){	#if we failed to commit
		print "[DEBUG::oracle] error commiting, rolling back\n" unless !$debug;
		$db->rollback;
	}
	print "[DEBUG::oracle] doc/sec: ", $count / (time()-$start_time), "\n" unless !$debug;
	print "[DEBUG::oracle] command queue size: ", scalar(@toDo), "\n" unless !$debug;
	while(scalar(@toDo) > 4000){ 
		sleep 1;
		print "[DEBUG::oracle] command queue size: ", scalar(@toDo), "\n" unless !$debug;
	}
	#$queue_lock = 0;
}
$sth->finish();
$db->disconnect();
$threads[1]->join;
$running = 0;
$threads[0]->join;
#EOF

