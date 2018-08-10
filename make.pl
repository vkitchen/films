#!/usr/bin/env perl

use strict;
use warnings;

use lib './';
use Secrets;
use URI;
use LWP::Simple;
use JSON;
use Data::Dumper;
use HTML::Template;
use Image::Grab;
use Image::Size;
use Text::Xslate;
use Digest::MD5;

my $pinboard_key = $Secrets::pinboard_key;
my $tmdb_key = $Secrets::tmdb_key;

my $img_base = 'http://image.tmdb.org/t/p/';
my $img_size = 'w185/';

mkdir 'cache';
mkdir 'img';
mkdir "img/$img_size";

sub write_file {
    my $file = shift;
    my $data = shift;
    open my $fh, ">", $file or die("Could not open file. $!");
    print $fh $data;
    close $fh;
}

sub read_file {
    my $file = shift;
    local $/ = undef;
    open my $fh, "<", $file or die("Could not open file. $!");
    my $data = <$fh>;
    close $fh;
    return $data;
}

# Make a URL request, cache the result to a file. If the file exists read from that next request
sub cache_request {
  my $url = shift;
  my $cache_file = shift;
  if (-f $cache_file) {
    return decode_json(read_file($cache_file));
  } else {
    my $urlObject = URI->new($url);
    my $data = get($urlObject->as_string);
    if (!defined $data) {
      return undef;
    }
    write_file($cache_file, $data);
    return decode_json($data);
  }
}

sub films_upcoming {
  return cache_request("https://api.pinboard.in/v1/posts/all?tag=film-club-upcoming&format=json&auth_token=$pinboard_key", "cache/film-club-upcoming.json");
}

sub films_seen {
  return cache_request("https://api.pinboard.in/v1/posts/all?tag=film-club-seen&format=json&auth_token=$pinboard_key", "cache/film-club-seen.json");
}

# TODO Misses the second page on multi page responses
# e.g. 'Young & Beautiful'
sub get_movie_info {
  my $title = shift;
  my $year;
  if ($title =~ /(.*) \(([0-9]+)\)/) {
    $title = $1;
    $year = $2;
  }
  $title =~ tr/\//-/;
  my $results;
  if ($year) {
    $results = cache_request("http://api.themoviedb.org/3/search/movie?api_key=$tmdb_key&query=$title&year=$year", "cache/$title ($year).json");
  } else {
    $results = cache_request("http://api.themoviedb.org/3/search/movie?api_key=$tmdb_key&query=$title", "cache/$title.json");
  }
  return resolve_results($title, $results);
}

# Only accept results with same 'title' or 'original_title'
# prefer those with greater 'vote_count'
sub resolve_results {
  my $title = shift;
  my $results = shift;
  my %results = %{$results};
  my @results = @{$results{'results'}};

  my %best_result;
  for my $result (@results) {
    my %result = %{$result};
    if (($result{'title'} eq $title || $result{'original_title'} eq $title)
        && (!%best_result || $result{'vote_count'} > $best_result{'vote_count'})) {
      %best_result = %result;
    }
  }

  return \%best_result;
}

sub get_img {
  my $img = shift;

  my ($x, $y, $iid);
  if ($img && ! -f "img/$img_size$img") {
    my $pic = new Image::Grab;
    $pic->url("$img_base$img_size$img");
    $pic->grab;
    ($x, $y, $iid) = imgsize(\$pic->image);
    write_file("img/$img_size$img", $pic->image);
  } elsif ($img) {
    my $pic = read_file("img/$img_size$img");
    ($x, $y, $iid) = imgsize(\$pic);
  }
  return ($x, $y, $iid);
}

binmode(STDOUT, ":utf8");

sub build_page {
  my $page = shift;
  my $films = shift;
  my @films = @{$films};

  my $tx = Text::Xslate->new();
  my %mlist = (
    page => $page,
    videos => [],
  );

  for my $film (@films) {
    my %film = %{$film};
    my $title = $film{'description'};
    $title =~ s/ - IMDb//;
    my $url = $film{'href'};
    # Get info
    my $info = get_movie_info($title);
    my %info = %{$info};
    $info{'imdb'} = $url;
    # Get Image
    my $img = $info{'poster_path'};
    if (! $img) {
      next;
    }
    my ($x, $y, $iid) = get_img($img);
    $info{'img'} = {
      url => "img/$img_size$img",
      width => $x,
      height => $y,
    };
    push(@{$mlist{'videos'}}, {%info});
  }
  write_file($page, $tx->render('index.tx', \%mlist));
}

sub main {
  my @upcoming = @{films_upcoming()};
  sleep 5;
  my @seen = @{films_seen()};
  build_page('index.html', \@upcoming);
  build_page('seen.html', \@seen);
}

exit main();
