#!/usr/bin/perl -wT
#search.pl 
#copyright 2004, 2005, Jason Whitehorn
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


$| = 1; #turn off output buffer

print "Content-type: text/html\n\n";
use lib ".";
use search;
use Time::HiRes qw( gettimeofday tv_interval );

$ENV{QUERY_STRING} =~ m/query=([^&]*)/i;
my $query = $1;
$query =~ s/\+/ /g;

my $page = 1;
$ENV{QUERY_STRING} =~ m/page=([0-9]+)/ or $page = 0;
if($page == 1){
    $page = $1;
}

my $start = [gettimeofday];
my @results = search::search($query);
search::display(10, $page, $start, $query, @results);
