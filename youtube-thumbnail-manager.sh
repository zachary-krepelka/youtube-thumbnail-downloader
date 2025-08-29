#!/usr/bin/env bash

# FILENAME: youtube-thumbnail-manager.sh
# AUTHOR: Zachary Krepelka
# DATE: Sunday, July 28th, 2024
# ABOUT: reposit YouTube thumbnails offline
# ORIGIN: https://github.com/zachary-krepelka/youtube-thumbnail-downloader.git
# UPDATED: Thursday, August 28th, 2025 at 6:59 PM

# Functions --------------------------------------------------------------- {{{1

program="${0##*/}"

usage() {
	cat <<-USAGE
	usage: $program [opts] <cmd>
	curate an offline repository of YouTube thumbnails

	options:
	  -h        display this [h]elp message and exit
	  -H        read documentation for this script then exit
	  -q        be [q]uiet: silence warnings but not errors
	  -r <dir>  use <dir> as the [r]epo instead of \$PWD

	commands:
	  init      create an empty thumbnail repository in working directory
	  add       add YouTube thumbnails to the index
	            opens a text editor to paste YouTube links into
	  scrape    retrieve metadata for thumbnails in the index
	  exec      downloads thumbnails in the index
	  get       add + scrape + exec
	  stats     report number of thumbnails and their disk usage
	  search    fuzzy find a thumbnail by its video's title
	            uses chafa for image previews
	USAGE
}

documentation() {
	pod2text "$0" | less -S +k
}

warning() {
	if test -v quiet
	then return
	fi
	local message="$1"
	echo "$program: warning: $message" >&2
}

error() {
	local code="$1"
	local message="$2"
	echo "$program: error: $message" >&2
	exit "$code"
}

check_dependencies() {

	local dependencies=(
		cat chafa column convert cut
		dirname du find fzf grep less ls
		mkdir nc perl pod2text realpath
		sed sort sponge tail tee timeout
		touch vipe wc wget whiptail
		xargs
	)

	local missing=

	for cmd in "${dependencies[@]}"
	do
		if ! command -v "$cmd" &>/dev/null
		then missing+="$cmd, "
		fi
	done

	if test -n "$missing"
	then error 1 "missing dependencies: ${missing%, }"
	fi
}

check_connection() {

	local website="$1"

	timeout 2 nc -zw1 "$website" 443 &>/dev/null ||
		error 2 'no internet connectivity'

	# https://unix.stackexchange.com/q/190513
}

cut_down() {

	local minuend="$1"
	local subtrahend="$2"

	grep -Fxvf "$subtrahend" "$minuend"

	# https://proofwiki.org/wiki/Definition:Set_Difference
}

integrate_into() {

	local file="$1"

	cat "$file" - | sort -u | sponge "$file"
}

repo_exists() {

	test -d "$repo" && test -d "${repo%/}/$meta"
}

#  +--DISCLAIMER----------------------------------- |
#  | I'm aware that parsing the output of ls is     |
#  | discouraged.  It should not be a problem here  |
#  | because the function is called in a controlled |
#  | context.  The directory is expected to contain |
#  | files with a rigid filename character set.     |
#  | However, maybe this would be better?           |
#  |                                                |
#  |       local count=0                            |
#  |       for jpg in ${directory%/}/*.jpg          |
#  |       do ((count++))                           |
#  |       done                                     |
#  |       echo $count                              |
#  |                                                |
#  | https://mywiki.wooledge.org/ParsingLs          |
#  +----------------------------------------------- |

jpg_count() {

	local directory="$1"

	# Find is too slow here. We use ls.

	command ls -1p "$directory" | grep -ci jpg$

	# Preferred over 'ls -1  -- *.jpg' so as not to exceed ARG_MAX
	# The flag -p prevents directories ending in jpg from matching.
}

jpg_size() {

	find $* -maxdepth 1 -type f -iname '*.jpg' -print0 |
	du -ch --files0-from=- |
	tail -1 | cut -f1

	# Preferred over 'du -ch -- *.jpg' so as not to exceed ARG_MAX
}

scrape_youtube_video_title() {

	local video_id="$1"

	wget -qO- "https://youtu.be/$video_id" |
		grep -Pom1 '<title>\K[^<]*' |
		sed 's/.\{10\}$//' |
		perl -MHTML::Entities -pe 'decode_entities($_);'

	# Magic number 10 is the length of the string ' - YouTube'
}

# Precondition Checks ----------------------------------------------------- {{{1

check_dependencies # must be called before any external command

check_connection img.youtube.com

wrapper="$(realpath "$0")"
wrappee="$(dirname "$wrapper")/youtube-thumbnail-grabber.sh"

if test ! -f "$wrappee"
then error 3 'missing base script'
fi

# Command-line Argument Parsing ------------------------------------------- {{{1

repo="$PWD"
meta=.thumbnails

while getopts :hHr:q opt
do
	case "$opt" in
		h) usage; exit 0;;
		H) documentation; exit 0;;
		q) quiet=;;
		r) repo="$OPTARG";;
		*) warning "unknown option -$OPTARG";;
	esac
done

shift $((OPTIND - 1))
cmd="${1,,}"
shift

# Location Handling ------------------------------------------------------- {{{1

if ! repo_exists
then
	repo="$DEFAULT_YOUTUBE_THUMBNAIL_REPOSITORY" # Environment Variable

	if repo_exists
	then warning 'using default repository'
	else error 4 'not a repository'
	fi
fi

cd "$repo"

# Command Processing ------------------------------------------------------ {{{1

case "$cmd" in

	init) # ----------------------------------------------------------- {{{2

		mkdir -p $meta longs shorts
		touch $meta/{longs,shorts,titles}
	;;
	add) # ------------------------------------------------------------ {{{2

		vipe | tee \
			>(
				grep -oP 'shorts/\K.{11}' |
					integrate_into $meta/shorts
			 ) \
			>(
				grep -oP '(be/|v=)\K.{11}' |
					integrate_into $meta/longs
			 ) \
			> /dev/null

			# Our magic number 11 is the number of
			# characters in a YouTube video ID.
	;;
	scrape) # --------------------------------------------------------- {{{2

		cut_down <(cat $meta/{longs,shorts}) <(cut -f1 $meta/titles) |
		while read -r video_id
		do echo "$video_id"$'\t'"$(scrape_youtube_video_title $video_id)"
		done | integrate_into $meta/titles
	;;
	exec) # ----------------------------------------------------------- {{{2

		for fmt in longs shorts
		do bash "$wrappee" -bo $fmt $meta/$fmt
		done
	;;
	get) # ------------------------------------------------------------ {{{2

		bash "$wrapper" add
		bash "$wrapper" scrape
		bash "$wrapper" exec
	;;
	stats) # ---------------------------------------------------------- {{{2

		for fmt in longs shorts
		do
			declare ${fmt}_cnt=$(jpg_count $fmt)
			declare ${fmt}_size=$(jpg_size $fmt)
		done

		# shellcheck disable=2154
		{
		total_cnt=$((longs_cnt + shorts_cnt))
		total_size=$(jpg_size longs shorts)

		column -tN ' ',LONGS,SHORTS,TOTAL <<-REPORT
		COUNT $longs_cnt  $shorts_cnt  $total_cnt
		SIZE  $longs_size $shorts_size $total_size
		REPORT
		}
	;;
	search) # --------------------------------------------------------- {{{2

		fzf -m --with-nth=2.. --bind ctrl-space:refresh-preview --preview '
			imagepath="$(
				echo {} |
				cut -f1 |
				xargs -I video_id \
					find ~+ -name '"'"'video_id.jpg'"'"')";
			type="$(dirname "$imagepath")";
			type="${type##*/}";
			if test "$type" = shorts
			then convert "$imagepath" -gravity center -crop 9:16 -
			else cat "$imagepath"
			fi |
			chafa \
			--view-size ${FZF_PREVIEW_COLUMNS}x$FZF_PREVIEW_LINES \
			--align center,center -
		' < $meta/titles |
		cut -f1 |
		xargs -I video_id find ~+ -name 'video_id.jpg'
	;;
	troubleshoot) # --------------------------------------------------- {{{2

		for fmt in longs shorts
		do
			declare ${fmt}_indexed=$(wc -l < $meta/$fmt)
			declare ${fmt}_downloaded=$(jpg_count $fmt)
			declare ${fmt}_diff=$((${fmt}_indexed-${fmt}_downloaded))
		done

		# shellcheck disable=2154
		column -tN ' ',LONGS,SHORTS <<-REPORT
		INDEXED    $longs_indexed    $shorts_indexed
		DOWNLOADED $longs_downloaded $shorts_downloaded
		DIFFERENCE $longs_diff       $shorts_diff
		REPORT
	;;

	# }}}

	*) error 5 "unknown command \"$cmd\"";;
esac

# Documentation ----------------------------------------------------------- {{{1

# https://charlotte-ngs.github.io/2015/01/BashScriptPOD.html
# http://bahut.alma.ch/2007/08/embedding-documentation-in-shell-script_16.html

: <<='cut'
=pod

=head1 NAME

youtube-thumbnail-manager.sh - reposit YouTube thumbnails offline

=head1 SYNOPSIS

 bash youtube-thumbnail-manager.sh [options] <command>

options: [-h] [-H] [-q] [-r <dir>]

commands: init, add, scrape, exec, get, stats, search

=head1 DESCRIPTION

This program allows its user to curate an offline repository of YouTube
thumbnails.  It is a workflow-centric program designed to supplement the YouTube
browsing experience.  As a wrapper around another shell script, this program not
only downloads thumbnails but also facilitates the organization of them on your
computer.

=head2 Objective

To incrementally build up an offline collection of YouTube thumbnails organized
into the following file structure, which we call a B<YouTube thumbnail
repository>.

	repo/
	|-- .thumbnails/
	|   |-- longs
	|   |-- shorts
	|   `-- titles
	|-- longs/
	|   |-- aaaaaaaaaaa.jpg
	|   |-- bbbbbbbbbbb.jpg
	|   `-- ccccccccccc.jpg
	`-- shorts/
	    |-- xxxxxxxxxxx.jpg
	    |-- yyyyyyyyyyy.jpg
	    `-- zzzzzzzzzzz.jpg

=head2 File Structure and Naming Conventions

Downloaded thumbnails are automatically organized into two folders depending on
their content type: short-form or long-form.

=over

=item

A long-form YouTube video is presented in a horizontal, 16:9 aspect ratio.
These are traditional YouTube videos.

=item

A short-form YouTube video is presented in a vertical, 9:16 aspect ratio.
These are videos of restricted duration.

=back

Downloaded thumbnails are named after their video's ID.  Representatively, the
file C<aaaaaaaaaaa.jpg> is the downloaded thumbnail image of a YouTube video
whose ID is C<aaaaaaaaaaa>.  This naming scheme is chosen for programmatic
simplicity, not for human readability.  Note that a search command is provided
for finding thumbnails by their video's title.

There is also a hidden directory called C<.thumbnails> containing metadata.
This metadata directory can be used to reconstruct / re-download the whole
repository if the images themselves are later deleted.  It can be packaged and
distributed to share collections of images with a common theme.

The files C<longs> and C<shorts> are indexes recording the thumbnails in the
repository.  The file C<titles> records the title of the video of each
thumbnail.

=head2 Workflow

This workflow presumes that you have a web browser and a terminal open on your
computer at the same time.  This is not unusual for programmers.  Note that this
program uses a Swiss-army-knife style command-line interface, i.e., it employs
subcommands.  Each sub command embodies a different workflow component.  Users
of git will find this familiar.

=over

=item Step 1

One begins by initializing a thumbnail repository in their current working
directory.  This sets up a directory to store thumbnails.

	bash youtube-thumbnail-manager.sh init

=item Step 2

While browsing YouTube, identify a video whose thumbnail you want to save.  Copy
the link to that video and return to your terminal.  Then type the following
command.

	bash youtube-thumbnail-manager.sh get

A command-line text editor will open.  Paste the link into the text editor.
When you are done, exit the text editor.  This will initiate a download process.

You do not have to stop at just one link.  You an paste as many URLs into the
text editor as you want before exiting to initiate the download process.  You
may move back and forth between your terminal and web browser, perhaps using
your window manager's keyboard shortcuts for efficiency.

The C<get> command is actually a compound command.  More on this later.

=item Step 3

After having amassed a worthwhile collection, you will most certainly want to
explore it.  For this purpose, you can use the following command.

	bash youtube-thumbnail-manager.sh search

This will open a text-user interface for searching and previewing thumbnails.
You can also gauge the size of your collection using this command.

	bash youtube-thumbnail-manager.sh stats

=item Step 4

Repeat steps 2 and 3 across different browsing sessions to amass a large
collection of images.

=back

=head2 Working Directory

Note that this program has a concept of a working directory.  The commands
that you execute affect the repository you are in.  You can create multiple
repositories, perhaps to capture different thematic elements in images.

If you execute a command in a directory that is not designated as a thumbnail
repository, you will receive an error.  To alleviate the burden of navigating
your file system, you can also define a I<default> thumbnail repository, so that
if a command is executed outside of a repository, the default repository is
assumed instead of giving an error.

=head1 OPTIONS

Global command-line options are specified before subcommands.  Some of them
cause the program to exit without processing the subcommand (e.g., -h and -H),
while others change the way that the program behaves (e.g., -q and -r).  In the
former case, the subcommand is not required.  In the latter case, a subcommand
is expected.  In the future, I may also implement subcommand-specific options
which are contingent on the subcommand used.  These will be documented in the
COMMANDS section.  Currently there are none.

	program [global-options] <subcommand> [specific-options]

Enumerated below are the global command-line options in the same order as shown
in the command-line help message for this program.

=over

=item B<-h>

Display a [h]elp message and exit.

=item B<-H>

Display this documentation in a pager and then exit.  The uppercase B<-H> is to
parallel the lowercase B<-h> in that they both provide help.

=item B<-q>

Be [q]uiet: silence warnings but not errors.  Warnings are friendly messages to
alert the user about a non-critical or potential issue.  Error messages indicate
a critical issue that caused the program to exit prematurely.

=item B<-r> I<PATH>

Run as if this program was started in I<PATH> instead of in the current working
directory.  This option allows the user to change the targeted thumbnail
[r]epository.  As noted earlier, this program has a concept of a working
directory.  The commands that you execute affect the repository you are in.

=back

=head1 COMMANDS

=over

=item init

This command initializes the current working directory as a YouTube thumbnail
repository.  It is the only command which does not require the current working
directory to be a YouTube thumbnail repository.

Initializing a thumbnail repo means

=over

=item

Creating a hidden metadata directory to index thumbnails.  The presence of this
subdirectory is what determines whether a given directory is a thumbnail
repository.

=item

Creating two visible folders to separate video thumbnails into, by content type:
shorts and longs.

=back

You can create multiple repositories, one per directory.  You could probably
even nest them (I haven't vetted this myself).

=item add

This command adds YouTube videos to an index.  The index is just a record /
to-do list.  This command does I<not> download the thumbnails; it only marks
them to be downloaded at a later time.

It works by opening the command-line text editor determined by the environment
variable EDITOR.  When this editor is closed, its contents are examined for
YouTube video links.

Full URLs should be pasted.  It does not matter what the link looks like, so
long as it points to a YouTube video, either long or short.  The link can
include extra query parameters like timestamps and playlist IDs.  It can even be
link-shortened as L<youtu.be>.  The URLs do not necessarily have to be pasted
line-by-line, but this is most natural.

This command is responsible for differentiating videos by their content type.
The link is used to determine this.

=item scrape

This command retrieves metadata for thumbnails in the index.  It scrapes each
video's webpage for relevant information.  As of now, only the title of the
video is acquired.  The titles will be used to allow the user to search for a
thumbnail in their repository offline.

=item exec

This command downloads YouTube thumbnails in the index if they haven't already
been downloaded.  The image is obtained in its best possible quality as a JPEG
file.

This command delegates the task of downloading thumbnails to another shell
script, the program which this one wraps.  This command executes that script,
hence the name.

=item get

This is a composite command which executes the C<add>, C<scrape>, and C<exec>
commands in sequence.  The C<get> command can be regarded as a high-level
command, while the commands C<add>, C<scrape>, and C<exec> can be regarded as
low-level.  The user should prefer to use C<get> instead of C<add>, C<scrape>,
and C<exec> independently.  A typical workflow will consist primarily of calling
the C<get> and C<search> commands.

The disadvantage of issuing the low-level commands independently is that if they
are issued at different times, then information could be lost.  For example,
adding a thumbnail to the index but downloading it a week later would provide
opportunity for the video to be privated, deleted, or taken down due to
copyright.  This could pollute the repository with empty image files.

The C<get> command makes everything happen at once.

=item stats

This command prints statistics about a thumbnail repository in a table format.
This information includes the total number of thumbnails, how many are shorts
versus longs, and how much disk space is used.  Here is a sample output.

	       LONGS  SHORTS  TOTAL
	COUNT  3014   218     3232
	SIZE   313M   22M     335M

The primary use is to gauge the size of a repository.
Further reporting may be implemented in the future.

=item search

The C<search> command is this program's most sophisticated and noteworthy
command.  It launches a text-user interface to search for and preview thumbnail
images in your repository, all from the comfort of your terminal.

On the left is a searchable, scrollable list of thumbnails identified by video
title.  On the right is a preview of the currently-selected thumbnail.  The
well-known command-line fuzzy finder C<fzf> is used for searching.  Command-line
image rendering is accomplished with C<chafa>.

You can

=over

=item * search by typing

=item * scroll up and down with the arrow keys

=item * select and de-select images with the tab key

=item * press enter to confirm your selection

=item *

zoom in and out while pressing CTRL+SPACE to refresh the image preview to view a
thumbnail at differing resolutions.  Zooming functionality is contingent on your
terminal emulator.  Possibly try CTRL+- and CTRL+=.

=back

The absolute paths of selected images are printed to standard output line by
line.  In the case of selecting a single image, this allows you to use the
command as part of a command substitution.

	xdg-open "$(bash youtube-thumbnail-manager.sh search)"

Currently piping doesn't work.  This is a bug.  Otherwise, you would be able to
do

	bash youtube-thumbnail-manager.sh search | xargs xdg-open

=item troubleshoot

Use this command to identify discrepancies between indexed and downloaded
images.  This is relevant when the C<add> and C<exec> commands are used in a
fashion as described in the documentation for the C<get> command.  See earlier.

The output of this command is a table like this.

		    LONGS  SHORTS
	INDEXED     3014   218
	DOWNLOADED  3014   218
	DIFFERENCE  0      0

A difference of zero indicates that nothing is wrong; all indexed images have
been downloaded.

=back

=head1 DIAGNOSTICS

The program exits with the following status codes.

=over

=item 0 successful completion

=item 1 missing dependencies

=item 2 no internet connectivity

=item 3 missing base script

=item 4 not a repository

=item 5 unknown command

=back

=head1 EXAMPLES

=head2 Example 1

Halloween roles around and your YouTube feed fills up with Lo-fi music videos
thumbnailed with images of skeletons, ghosts, jack-o'-lanterns, bats, and black
cats.  You think these images are fascinating, especially in that they exhibit a
unified theme, so you decide to collect them.

=over

=item 1)

You create a directory on your computer.

	cd internet-pics
	mkdir halloween
	cd halloween

=item 2)

You initialize a thumbnail repository in that directory.

	bash youtube-thumbnail-manager.sh init

=item 3)

While still in the same directory, you use the get command to download the
thumbnails.

	bash youtube-thumbnail-manager.sh get

A text editor opens, and you copy-and-paste several YouTube links into it before
closing the editor.

=item 4)

To confirm that the images are downloaded on your computer, you use the search
command.

	bash youtube-thumbnail-manager.sh search

Scrolling up and down with the arrow keys, you preview each image from the
comfort of your command-line.

=back

=head2 Example 2

You discover the wonderful world of art commentary on YouTube.  These videos are
often thumbnailed with the painting that they commentate on.  You can now keep
your own gallery of paintings.

	cd internet-pics
	mkdir paintings && cd paintings
	bash youtube-thumbnail-manager.sh init
	# and so on

=head1 ENVIRONMENT

The program cares about the following environment variables.

=over

=item EDITOR

The editor used to paste YouTube links into.

=item DEFAULT_YOUTUBE_THUMBNAIL_REPOSITORY

The directory used when the current directory is not a YouTube thumbnail
repository.

=back

=head1 CAVEATS

It was noted that the presence of the metadata subdirectory named C<.thumbnails>
is what determines whether a given directory is a thumbnail repository.

It is possible to have a false-positive if another application creates a
directory with the name C<.thumbnails>.  If this is an issue, you can change the
name of the metadata directory in the source code of this program.  It is easy
to change since it is defined as a variable.  As an example, C<.yt-thumbs> would
be more unique, but I prefer C<.thumbnails> as a matter of aesthetics.

=head1 BUGS

There are a few.

=over

=item

The B<-r> option does not work with the B<init> command.

=item

The B<-r> option has poor error messages.  Its behavior in regard to falling
back to the default repository is unintuitive and poorly documented.

=item

Only a handful of subcommands require internet connectivity, yet this script
errors on no connection irrespective of the command used.  This behavior should
be redesigned so that the script only errors when internet connectivity is
strictly required.  (The commands which require internet connectivity are
scrape, exec, and get.)

=back

=head1 AUTHOR

Zachary Krepelka L<https://github.com/zachary-krepelka>

=cut

# vim: tw=80 ts=8 sw=8 noet fdm=marker
