#!/usr/bin/perl
$| = 1;	#no output buffer
my $version = "0.9.1";	#this is the version of Senas...
#this program has no version of it's own
use DBI;
my $path = "";
my $ip;
my $pass;
my $user;
my $db;

my $commands = "";
print "-----------------------------------------\n\n";
print "Senas $version installer\n";
print "Please read INSTALL before continuing, or\n";
print "visit http://www.senas.org for more information.\n";
print "This program will install Senas $version.\n\n";

print "Do you wish to continue? [Y/n]: ";
if(!(<STDIN> =~ m/^y/i)){	#if they did NOT say yes
	print "Sorry to hear that, exiting now.\n";
	exit;
}
print "\n";
print "Where would you like to install Senas?\n";
print "Hint: The directory must already exist.\n";
print ">";
$path = <STDIN>;
chomp($path);
$test =~ s/\/$//;	#remove tailing forward slashes
print "\n";
print "What is the IP address of the system hosting your database?\n";
print "Hint: Type 127.0.0.1 for localhost\n";
print ">";
$ip = <STDIN>;
chomp($ip);
print "\n";
print "What is the name of the database?\n";
print ">";
$db = <STDIN>;
chomp($db);
print "\n";
print "What is your database username?\n";
print ">";
$user = <STDIN>;
chomp($user);
print "\n";
print "What is your database password?\n";
print ">";
$pass = <STDIN>;
chomp($pass);
print "\n";
print "Please wait as we connect to your database...";
my $dbh = DBI->connect("DBI:Pg:database=$db;host=$ip", "$user", "$pass") or die $!;
print "DONE\n";
print "\n";
print "What urls would like you to seed from?\n";
do{
	print "(hit return to continue)>";
	$commands = <STDIN>;
	chomp($commands);
	if(!($commands eq "")){
		$commands = "insert into outgoing (url) values(" . $dbh->quote($commands) . ");";
		$dbh->do($commands);
	}
}while(!($commands eq ""));
$dbh->disconnect();
print "That should be all I need... sit back while I install Senas for you.\n\n";
print "#Senas configuration file...";
open CONFIG, ">/etc/senas.cfg";
print CONFIG "\$password=\"$pass\";\n";
print CONFIG "\$username=\"$user\";\n";
print CONFIG "\$host=\"$ip\";\n";
print CONFIG "\$database=\"$db\";\n";
print CONFIG "\$path=\"$path\";\n";
print CONFIG "\$type=\"Pg\";";
print CONFIG "push \@parsers, \$path . \"/senas/lib/html.pl\";";
close CONFIG;
print "DONE\n";
#install!
print "Making directory structure...";
#setup directory struct
system("mkdir $path/senas");
system("mkdir $path/senas/bin");
system("mkdir $path/senas/lib");
system("mkdir $path/senas/var");
system("mkdir $path/senas/doc");
system("mkfifo /usr/local/senas/var/oracle.pipe");
system("mkfifo /usr/local/senas/var/ranker.pipe");
system("mkfifo /usr/local/senas/var/simon.pipe");
print "DONE\n";
#copy stuff
print "Copying program files...";
system("cp oracle.pl $path/senas/bin/oracle.pl");
system("chmod +x $path/senas/bin/oracle.pl");
system("cp simon.pl $path/senas/bin/simon.pl");
system("chmod +x $path/senas/bin/simon.pl");
system("cp ranker.pl $path/senas/bin/ranker.pl");
system("chmod +x $path/senas/bin/ranker.pl");
system("cp gpl.txt $path/senas/doc/gpl.txt");
system("cp README $path/senas/doc/README");
system("cp INSTALL $path/senas/doc/INSTALL");
#system("cp senas.cfg /etc/senas.cfg");
system("cp ./mime_parsers/* $path/senas/lib/");
print "DONE\n";

#`ln -s /usr/local/senas/bin/oracle.pl /etc/rc.d/rc3.d/S99oracle`;
#`ln -s /usr/local/senas/bin/ranker.pl /etc/rc.d/rc3.d/S99ranker`;
#`ln -s /usr/local/senas/bin/simon.pl /etc/rc.d/rc3.d/S99simon`;
print "\n";
print "Installation complete.\n";
print "Please read INSTALL for post-installation instructions.\n\n";
print "Thank you for installing Senas.\n";