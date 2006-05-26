#         TrackStat::Statistics::LeastPlayed module
#    Copyright (c) 2006 Erland Isaksson (erland_i@hotmail.com)
# 
#    This program is free software; you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation; either version 2 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program; if not, write to the Free Software
#    Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA


use strict;
use warnings;
                   
package Plugins::TrackStat::Statistics::LeastPlayed;

use Date::Parse qw(str2time);
use Fcntl ':flock'; # import LOCK_* constants
use File::Spec::Functions qw(:ALL);
use File::Basename;
use XML::Parser;
use DBI qw(:sql_types);
use Class::Struct;
use FindBin qw($Bin);
use POSIX qw(strftime ceil);
use Slim::Utils::Strings qw(string);
use Plugins::TrackStat::Statistics::Base;


if ($] > 5.007) {
	require Encode;
}

my $driver;
my $distinct = '';

sub init {
	$driver = Slim::Utils::Prefs::get('dbsource');
    $driver =~ s/dbi:(.*?):(.*)$/$1/;
    
    if($driver eq 'mysql') {
    	$distinct = 'distinct';
    }
}

sub getStatisticItems {
	my %statistics = (
		leastplayed => {
			'webfunction' => \&getLeastPlayedTracksWeb,
			'playlistfunction' => \&getLeastPlayedTracks,
			'id' =>  'leastplayed',
			'namefunction' => \&getLeastPlayedTracksName
		},
		leastplayedartists => {
			'webfunction' => \&getLeastPlayedArtistsWeb,
			'playlistfunction' => \&getLeastPlayedArtistTracks,
			'id' =>  'leastplayedartists',
			'name' => string('PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDARTISTS')
		},
		leastplayedalbums => {
			'webfunction' => \&getLeastPlayedAlbumsWeb,
			'playlistfunction' => \&getLeastPlayedAlbumTracks,
			'id' =>  'leastplayedalbums',
			'namefunction' => \&getLeastPlayedAlbumsName
		}
	);
	return \%statistics;
}

sub getLeastPlayedTracksName {
	my $params = shift;
	if(defined($params->{'artist'})) {
	    my $ds = Slim::Music::Info::getCurrentDataStore();
	    my $artist = $ds->objectForId('artist',$params->{'artist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYED_FORARTIST')." ".$artist->{name};
	}elsif(defined($params->{'album'})) {
	    my $ds = Slim::Music::Info::getCurrentDataStore();
	    my $album = $ds->objectForId('album',$params->{'album'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYED_FORALBUM')." ".$album->{title};
	}else {
		return string('PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYED');
	}
}

sub getLeastPlayedTracksWeb {
	my $params = shift;
	my $listLength = shift;
	my $orderBy = Plugins::TrackStat::Statistics::Base::getRandomString();
	my $sql;
	if(defined($params->{'artist'})) {
		my $artist = $params->{'artist'};
	    $sql = "select tracks.url,track_statistics.playCount,track_statistics.added,track_statistics.lastPlayed,track_statistics.rating from tracks join contributor_track on tracks.id=contributor_track.track and contributor_track.contributor=$artist left join track_statistics on tracks.url = track_statistics.url where tracks.audio=1 order by track_statistics.playCount asc,tracks.playCount asc,$orderBy limit $listLength;";
	    if(Slim::Utils::Prefs::get("plugin_trackstat_fast_queries")) {
	    	$sql = "select tracks.url,track_statistics.playCount,track_statistics.added,track_statistics.lastPlayed,track_statistics.rating from tracks, track_statistics, contributor_track where tracks.url = track_statistics.url and tracks.id=contributor_track.track and contributor_track.contributor=$artist and tracks.audio=1 order by track_statistics.playCount asc,tracks.playCount asc,$orderBy limit $listLength;";
	    }
	    $params->{'statisticparameters'} = "&artist=$artist";
	}elsif(defined($params->{'album'})) {
		my $album = $params->{'album'};
	    $sql = "select tracks.url,track_statistics.playCount,track_statistics.added,track_statistics.lastPlayed,track_statistics.rating from tracks left join track_statistics on tracks.url = track_statistics.url where tracks.audio=1 and tracks.album=$album order by track_statistics.playCount asc,tracks.playCount asc,$orderBy limit $listLength;";
	    if(Slim::Utils::Prefs::get("plugin_trackstat_fast_queries")) {
	    	$sql = "select tracks.url,track_statistics.playCount,track_statistics.added,track_statistics.lastPlayed,track_statistics.rating from tracks, track_statistics where tracks.url = track_statistics.url and tracks.audio=1 and tracks.album=$album order by track_statistics.playCount asc,tracks.playCount asc,$orderBy limit $listLength;";
	    }
	    $params->{'statisticparameters'} = "&album=$album";
	}else {
	    $sql = "select tracks.url,track_statistics.playCount,track_statistics.added,track_statistics.lastPlayed,track_statistics.rating from tracks left join track_statistics on tracks.url = track_statistics.url where tracks.audio=1 order by track_statistics.playCount asc,tracks.playCount asc,$orderBy limit $listLength;";
	    if(Slim::Utils::Prefs::get("plugin_trackstat_fast_queries")) {
	    	$sql = "select tracks.url,track_statistics.playCount,track_statistics.added,track_statistics.lastPlayed,track_statistics.rating from tracks, track_statistics where tracks.url = track_statistics.url and tracks.audio=1 order by track_statistics.playCount asc,tracks.playCount asc,$orderBy limit $listLength;";
	    }
	}
    Plugins::TrackStat::Statistics::Base::getTracksWeb($sql,$params);
}

sub getLeastPlayedTracks {
	my $listLength = shift;
	my $limit = shift;
	my $orderBy = Plugins::TrackStat::Statistics::Base::getRandomString();
    my $sql = "select tracks.url from tracks left join track_statistics on tracks.url = track_statistics.url where tracks.audio=1 order by track_statistics.playCount asc,tracks.playCount asc,$orderBy limit $listLength;";
    if(Slim::Utils::Prefs::get("plugin_trackstat_fast_queries")) {
    	$sql = "select tracks.url from tracks, track_statistics where tracks.url = track_statistics.url and tracks.audio=1 order by track_statistics.playCount asc,tracks.playCount asc,$orderBy limit $listLength;";
    }
    return Plugins::TrackStat::Statistics::Base::getTracks($sql,$limit);
}

sub getLeastPlayedAlbumsName {
	my $params = shift;
	if(defined($params->{'artist'})) {
	    my $ds = Slim::Music::Info::getCurrentDataStore();
	    my $artist = $ds->objectForId('artist',$params->{'artist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDALBUMS_FORARTIST')." ".$artist->{name};
	}else {
		return string('PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDALBUMS');
	}
}

sub getLeastPlayedAlbumsWeb {
	my $params = shift;
	my $listLength = shift;
	my $orderBy = Plugins::TrackStat::Statistics::Base::getRandomString();
	my $sql;
	if(defined($params->{'artist'})) {
		my $artist = $params->{'artist'};
	    $sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating, avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks join contributor_track on tracks.id=contributor_track.track and contributor_track.contributor=$artist left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id group by tracks.album order by avgcount asc,avgrating asc,$orderBy limit $listLength";
	    if(Slim::Utils::Prefs::get("plugin_trackstat_fast_queries")) {
	    	$sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating, avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks, track_statistics,albums,contributor_track where tracks.url = track_statistics.url and tracks.album=albums.id and tracks.id=contributor_track.track and contributor_track.contributor=$artist group by tracks.album order by avgcount asc,avgrating asc,$orderBy limit $listLength";
	    }
	    $params->{'statisticparameters'} = "&artist=$artist";
	}else {
	    $sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating, avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id group by tracks.album order by avgcount asc,avgrating asc,$orderBy limit $listLength";
	    if(Slim::Utils::Prefs::get("plugin_trackstat_fast_queries")) {
	    	$sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating, avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks, track_statistics,albums where tracks.url = track_statistics.url and tracks.album=albums.id group by tracks.album order by avgcount asc,avgrating asc,$orderBy limit $listLength";
	    }
	}
    Plugins::TrackStat::Statistics::Base::getAlbumsWeb($sql,$params);
    my @statisticlinks = ();
    push @statisticlinks, {
    	'id' => 'leastplayed',
    	'name' => string('PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYED_FORALBUM_SHORT')
    };
    $params->{'substatisticitems'} = \@statisticlinks;
}

sub getLeastPlayedAlbumTracks {
	my $listLength = shift;
	my $limit = undef;
	my $orderBy = Plugins::TrackStat::Statistics::Base::getRandomString();
    my $sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating, avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id group by tracks.album order by avgcount asc,avgrating asc,$orderBy limit $listLength";
    if(Slim::Utils::Prefs::get("plugin_trackstat_fast_queries")) {
    	$sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating, avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks, track_statistics,albums where tracks.url = track_statistics.url and tracks.album=albums.id group by tracks.album order by avgcount asc,avgrating asc,$orderBy limit $listLength";
    }
    return Plugins::TrackStat::Statistics::Base::getAlbumTracks($sql,$limit);
}

sub getLeastPlayedArtistsWeb {
	my $params = shift;
	my $listLength = shift;
	my $orderBy = Plugins::TrackStat::Statistics::Base::getRandomString();
    my $sql = "select contributors.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks left join track_statistics on tracks.url = track_statistics.url join contributor_track on tracks.id=contributor_track.track join contributors on contributors.id = contributor_track.contributor group by contributors.id order by sumcount asc,avgrating asc,$orderBy limit $listLength";
    if(Slim::Utils::Prefs::get("plugin_trackstat_fast_queries")) {
    	$sql = "select contributors.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks , track_statistics , contributors, contributor_track where tracks.url = track_statistics.url and tracks.id=contributor_track.track and contributors.id = contributor_track.contributor group by contributors.id order by sumcount asc,avgrating asc,$orderBy limit $listLength";
    }
    Plugins::TrackStat::Statistics::Base::getArtistsWeb($sql,$params);
    my @statisticlinks = ();
    push @statisticlinks, {
    	'id' => 'leastplayed',
    	'name' => string('PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYED_FORARTIST_SHORT')
    };
    push @statisticlinks, {
    	'id' => 'leastplayedalbums',
    	'name' => string('PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDALBUMS_FORARTIST_SHORT')
    };
    $params->{'substatisticitems'} = \@statisticlinks;
}

sub getLeastPlayedArtistTracks {
	my $listLength = shift;
	my $limit = Plugins::TrackStat::Statistics::Base::getNumberOfTypeTracks();
	my $orderBy = Plugins::TrackStat::Statistics::Base::getRandomString();
    my $sql = "select contributors.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks left join track_statistics on tracks.url = track_statistics.url join contributor_track on tracks.id=contributor_track.track join contributors on contributors.id = contributor_track.contributor group by contributors.id order by sumcount asc,avgrating asc,$orderBy limit $listLength";
    if(Slim::Utils::Prefs::get("plugin_trackstat_fast_queries")) {
    	$sql = "select contributors.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks , track_statistics , contributors, contributor_track where tracks.url = track_statistics.url and tracks.id=contributor_track.track and contributors.id = contributor_track.contributor group by contributors.id order by sumcount asc,avgrating asc,$orderBy limit $listLength";
    }
    return Plugins::TrackStat::Statistics::Base::getArtistTracks($sql,$limit);
}

sub strings()
{
	return "
PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYED
	EN	Least played songs

PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYED_FORARTIST_SHORT
	EN	Songs

PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYED_FORARTIST
	EN	Least played songs by: 

PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYED_FORALBUM_SHORT
	EN	Songs

PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYED_FORALBUM
	EN	Least played songs from: 

PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDALBUMS
	EN	Least played albums

PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDALBUMS_FORARTIST_SHORT
	EN	Albums

PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDALBUMS_FORARTIST
	EN	Least played albums by: 

PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDARTISTS
	EN	Least played artists
";
}

1;

__END__
