#!/usr/bin/env bash

# FILENAME: youtube-thumbnail-grabber.sh
# AUTHOR: Zachary Krepelka
# DATE: Tuesday, April 2nd, 2024
# ABOUT: a shell script to download YouTube thumbnails in bulk
# ORIGIN: https://github.com/zachary-krepelka/bookmarks.git
# UPDATED: Sunday, April 7th, 2024 at 6:33 PM

usage() { program=$(basename $0); cat << EOF >&2
Usage: $program [options] <file (of urls)>
download YouTube thumbnails in bulk from the command line

Options:
	-q {1,2,3,4,5}	image [q]uality from worst to best
	-b		download [b]est image quality available
	-a		download image in [a]ll qualities
	-f		[f]orcibly overwrite preexisting files
	-c		[c]ount the files as they download
	-h		display this [h]elp message

Example: bash $program -b urls.txt
Documentation: perldoc $program
EOF
exit 0
}

index=1
all=false
best=false
force=false
counting=false
count=0

flags=-q # nonrequisite wget flags

qualities=(
	'default'
	'mqdefault'
	'hqdefault'
	'sddefault'
	'maxresdefault'
)

while getopts abcfhq: option
do
	case $option in

		a) all=true;;
		b) best=true;;
		c) counting=true;;
		f) force=true;;
		h) usage;;
		q) index=$OPTARG;;

	esac
done
shift $((OPTIND-1))

video_id_length=11

video_id_pattern="(?<=v=).{$video_id_length}(?=&|\s|\"|$)"

for video_id in $(grep -oP $video_id_pattern $1 || cut -c -$video_id_length $1)
do
	if $counting
	then
		((count++))
		echo $count
	fi

	url_prefix=https://img.youtube.com/vi/$video_id

	if $all
	then
		for quality in ${qualities[@]}
		do
			image=$video_id-$quality.jpg

			if ! $force && test -f $image
			then continue
			fi

			wget $flags -O $image $url_prefix/$quality.jpg
		done
		continue
	fi

	image=$video_id.jpg

	if ! $force && test -f $image
	then continue
	fi

	if $best
	then
		for i in 4 3 2 1 0
		do
			wget $flags -O $image $url_prefix/${qualities[$i]}.jpg
			test $? -eq 0 && break
		done
		continue
	fi

	wget $flags -O $image $url_prefix/${qualities[index-1]:-default}.jpg
done

: <<='cut'
=pod

=head1 NAME

youtube-thumbnail-grabber.sh - download YouTube thumbnails in bulk

=head1 SYNOPSIS

bash youtube-thumbnail-grabber.sh [options] <file>

=head1 DESCRIPTION

The purpose of this script is to download thumbnails from YouTube videos in
bulk.  The input is a file containing a list of YouTube URLs.  For each video in
that list, this script will download its thumbnail as a jpg file with it's ID as
the filename. For example:

	https://www.youtube.com/watch?v=XqZsoesa55w  -->  XqZsoesa55w.jpg

=head1 OPTIONS

Be mindful that some flags take priority over others.  The order of ascending
priority is q, b, a, and h with c and f being irrelevant.  Flags may be
specified together, e.g., -bcf.

=over

=item B<-h>

Display a [h]elp message and exit.

=item B<-c>

Count the files as they download.  A quick-and-dirty, makeshift progress bar.

=item B<-f>

Forcibly overwrite preexisting files.  Without this flag, the download is
skipped if the image already exists on disk.

=item B<-q> I<NUM>

This flag specifies the [q]uality of the image. The argument is a number ranging
from one to five.  YouTube thumbnails come in five varieties. From worst to
best, they are as follows.

=over

=item 1 default

=item 2 mqdefault (medium quality)

=item 3 hqdefault (high quality)

=item 4 sddefault (standard definition)

=item 5 maxresdefault (maximum resolution)

=back

This script downloads the lowest quality image by default, namely because it's
always guaranteed to exist. Higher quality versions of the thumbnail might not
exist, so be wary when using this flag. You could end up with empty files.

=item B<-b>

Download the [b]est image quality that's available.

=item B<-a>

Download the image in [a]ll possible qualities. There are five.  Hence, the
number of images that this script will download when using this flag is five
times the number of lines in the input file.

	expr 5 \* $(wc -l < urls.txt)

This flag will also induce a different naming scheme on the output files. Here
is an example of how the files will be named when the -a flag is used.

	echo https://www.youtube.com/watch?v=XqZsoesa55w > baby-shark.txt
	bash youtube-thumbnail-grabber.sh -a baby-shark.txt
	ls -1 | grep jpg

		XqZsoesa55w-default.jpg
		XqZsoesa55w-hqdefault.jpg
		XqZsoesa55w-maxresdefault.jpg
		XqZsoesa55w-mqdefault.jpg
		XqZsoesa55w-sddefault.jpg

Higher quality images may not exist. In that case, the files will still be
created, but some of them will consequently be empty.

=back

=head1 EXAMPLES

To download a single thumbnail without creating an input file, you can use
process substitution, like this.

	bash youtube-thumbnail-grabber.sh <(echo YOUR_URL_HERE)

To download thumbnails in bulk, create a file of YouTube URLs.

	FILENAME: urls.txt

	1  https://www.youtube.com/watch?v=abcdefghijk
	2  https://www.youtube.com/watch?v=bcdefghijkl
	3  https://www.youtube.com/watch?v=cdefghijklm
	4  ...

Then just pass the file to the script, like this.

	bash youtube-thumbnail-grabber.sh urls.txt

=head1 NOTES

I remarked that the input file is a list of URLs.  This makes it easy to copy
and paste with CTRL-A CTRL-C CTRL-V from the URL bar of your web browser to a
bare text file.  It does not matter if the URLs are messy.  The videos can even
be part of a list and still parse correctly.  This will also work.

	https://www.youtube.com/watch?v=abcdefghijk&list=lmnopqrstuvwx

If you use the Vimium browser extension, copy-and-pasting YouTube URLs can be
achieved with the B<yf> command. This way is faster; you to not have to follow a
link to copy it, you do not loose focus of the window, and you don't have to use
a mouse. Check out the project here.

	https://github.com/philc/vimium

If you care about disk space, you can also use the video IDs directly.

Compare urls.txt

	https://www.youtube.com/watch?v=abcdefghijk
	https://www.youtube.com/watch?v=bcdefghijkl
	https://www.youtube.com/watch?v=cdefghijklm
	...

Versus video-ids.txt

	abcdefghijk
	bcdefghijkl
	cdefghijklm
	...

The program will first look for YouTube URLs, and if none are found, it will
instead look for video IDs.  You cannot mix video IDs and URLs in the same file.
Otherwise, the full URLs will take priority, thereby ignoring any video IDs.

The latter must be well-formed, but the former does not need to be well-formed.
The YouTube URLs can be spread out sporadically in the file; they don't need to
be in a neat list.  You can even put them all on one line if delimited by
spaces. On the other hand, the video IDs must be formatted as shown.

=head1 SEE ALSO

This script is part of my GitHub repository.

	https://github.com/zachary-krepelka/bookmarks.git

This repository contains various scripts for bookmark management.  I have
included this script in this repository because it can be used on a bookmark
file.

	bash youtube-thumbnail-grabber.sh bookmarks.html

=head1 AUTHOR

Zachary Krepelka L<https://github.com/zachary-krepelka>

=cut

#
