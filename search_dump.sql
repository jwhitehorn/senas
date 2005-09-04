# CocoaMySQL dump
# Version 0.5
# http://cocoamysql.sourceforge.net
#
# Host: 192.168.1.2 (MySQL 4.0.18-log)
# Database: search
# Generation Time: 2005-08-21 15:34:44 -0500
# ************************************************************

# Dump of table Index
# ------------------------------------------------------------

DROP TABLE IF EXISTS `Index`;

CREATE TABLE `Index` (
  `MD5` varchar(64) NOT NULL default '',
  `Cache` longblob,
  `Title` varchar(255) default NULL,
  `TSize` int(11) default NULL,
  PRIMARY KEY  (`MD5`)
) TYPE=MyISAM;



# Dump of table Links
# ------------------------------------------------------------

DROP TABLE IF EXISTS `Links`;

CREATE TABLE `Links` (
  `Source` varchar(64) default NULL,
  `Target` mediumblob
) TYPE=MyISAM;



# Dump of table QueryCache
# ------------------------------------------------------------

DROP TABLE IF EXISTS `QueryCache`;

CREATE TABLE `QueryCache` (
  `Query` varchar(255) NOT NULL default '',
  `Results` mediumblob,
  `Expire` bigint(20) default NULL,
  PRIMARY KEY  (`Query`)
) TYPE=MyISAM;



# Dump of table Sources
# ------------------------------------------------------------

DROP TABLE IF EXISTS `Sources`;

CREATE TABLE `Sources` (
  `URL` mediumblob,
  `MD5` varchar(64) default NULL,
  `LastSeen` bigint(20) default NULL,
  `Type` varchar(255) default NULL,
  `Rank` double default '0',
  `LastAction` bigint(20) default NULL,
  `Failures` int(11) default '0'
) TYPE=MyISAM;



# Dump of table WordIndex
# ------------------------------------------------------------

DROP TABLE IF EXISTS `WordIndex`;

CREATE TABLE `WordIndex` (
  `Word` varchar(255) NOT NULL default '',
  `MD5` varchar(64) NOT NULL default '',
  `Location` int(11) default NULL,
  `Source` int(5) default NULL,
  KEY `Word` (`Word`)
) TYPE=MyISAM;



# Dump of table incoming
# ------------------------------------------------------------

DROP TABLE IF EXISTS `incoming`;

CREATE TABLE `incoming` (
  `URL` mediumblob,
  `Data` blob,
  `LastSeen` bigint(20) default NULL,
  `Action` smallint(6) default NULL,
  `Type` varchar(255) default NULL,
  KEY `LastSeen` (`LastSeen`),
  KEY `LastSeen_2` (`LastSeen`)
) TYPE=MyISAM;



# Dump of table outgoing
# ------------------------------------------------------------

DROP TABLE IF EXISTS `outgoing`;

CREATE TABLE `outgoing` (
  `URL` mediumblob,
  `Priority` smallint(6) default '0',
  `id` bigint(32) unsigned NOT NULL auto_increment,
  PRIMARY KEY  (`id`)
) TYPE=MyISAM;



