#!/usr/bin/env bash

# FILENAME: youtube-thumbnail-manager.sh
# AUTHOR: Zachary Krepelka
# DATE: Sunday, July 28th, 2024
# ABOUT: reposit YouTube thumbnails offline
# ORIGIN: https://github.com/zachary-krepelka/youtube-thumbnail-downloader.git
# UPDATED: Friday, February 27th, 2026 at 1:35 AM

# Variables --------------------------------------------------------------- {{{1

video_id_length=11
declare -A forms=([long]=0 [short]=1) patterns
patterns[${forms[long]}]="(v=|be/)\\K.{$video_id_length}"
patterns[${forms[short]}]="shorts/\\K.{$video_id_length}"

# We use these regular expressions to extract YouTube video IDs from an input
# file containing a list of copy-and-pasted YouTube links.  These patterns
# intend to match IDs from URLs of the form
#
# 	1) https://www.youtube.com/watch?v={id}   (long)
# 	2) https://www.youtube.com/shorts/{id}    (short)
# 	3) https://youtu.be/{id}                  (long)

# NOTE about pattern flexibility
#
#	In constructing these patterns, we must be mindful of the existence of
#	additional query parameters.  We keep the patterns unrestrictive for
#	this reason.  In the case of the first URL type, by excluding the
#	question mark from the regex (compare ?v= versus v=) we effectively
#	allow for URLs with query parameters specified in a non-typical order,
#	e.g.,
#
#		youtube.com/watch?list={id}&index={num}&v={id}

# NOTE about the existence of false positives
#
#	We use the URL to determine the type of content when extracting video
#	IDs.  We expect that URL 2 is reserved for short-form content,  while
#	URLs 1 and 3 are reserved for long-form content.  However, it is
#	possible to rewrite URL 2 in the form of URL 1 or URL 3, whereby a
#	YouTube short will play as if it were a standard YouTube video in a 16:9
#	aspect ratio.  If such a URL is entered, then the short will be falsely
#	identified as a long.

qualities=(
	'default'
	'mqdefault'
	'hqdefault'
	'sddefault'
	'maxresdefault'
)

# YouTube thumbnails are available in five possible qualities, listed here from
# worst to best. The highest quality, maxresdefault, may not exist, but it
# usually does.  We download the highest available quality for each thumbnail by
# checking the existence from best to worst in a loop.

max_download_attempts=1

# When the user invokes the 'download' command, indexed but undownloaded
# thumbnails are tried.  Multiple attempts are not made on one pass, but the
# user is welcome to re-invoke the command if anything failed.  Download
# attempts are counted, and images with download attempts exceeding this number
# are skipped.  A failed download attempt usually indicates that either
#
# 	1) the video was privated, deleted, or taken down, or
# 	2) the user is being rate-limited by the server.

gauge_height=6
gauge_width=50
gauge_percent=0

# These are arguments supplied to the whiptail command when displaying progress
# bars, declared here explicitly to avoid magic numbers.

declare -A ansi=(
	[yellow]=$'\e[0;33m'
	[reset]=$'\e[0m'
)

# ANSI escape codes for colorizing output
# https://en.wikipedia.org/wiki/ANSI_escape_code

program="${0##*/}"
target="$PWD"
database=.yt.db

# used extensively throughout

# Functions --------------------------------------------------------------- {{{1

usage() {
	local message
	IFS= read -r -d '' message <<-EOF || true
	Curate an Offline Repository of YouTube Thumbnails

	Usage:
	  bash $program [opts] <cmd>

	Options:
	  -q        silence warnings and errors
	  -r <dir>  target <dir> instead of \$PWD as the [r]epo
	  -d        target [d]efault repo even when \$PWD is a repo

	Commands:
	  init                  create an empty thumbnail repository in working directory
	  index [file(s)]       add YouTube thumbnails to the index
	                        links are read from [file(s)] if provided;
	                        otherwise, a text editor opens to paste links into
	  download [-p]         downloads thumbnails in the index
	  scrape [-p]           retrieve metadata for (downloaded) thumbnails in the index
	  get [-p] [files(s)]   index + download + scrape
	  stats                 report number of thumbnails and their disk usage
	  search [-cusl]        fuzzy find a thumbnail by its video's title
	                        uses chafa for image previews
	  absorb [-dnp] <repo>  pull in images from another repository

	Documentation:
	  -h  display this [h]elp message and exit
	  -H  read documentation for this script then exit
	EOF
	printf '%s\n' "$message"
}

documentation() {
	pod2text "$0" | less -Sp '^[^ ].*$' +k
}

error() {
	local code="$1" message="$2"
	$opt_quiet || echo "$program: error: $message" >&2
	exit "$code"
}

warn() {
	local message="$1"
	$opt_quiet || echo "$program: warning: $message" >&2
}

error_cmd() {
	local code="$1" message="$2"
	error "$code" "command $cmd: $message"
}

warn_cmd() {
	local message="$1"
	warn "command $cmd: $message"
}

warn_unknown_cmd_opt() {
	warn_cmd "unknown option -$OPTARG"
}

error_on_missing_dependencies() {

	local dependencies=(
		cat chafa column convert cut du
		find fzf grep less ls mkdir
		mktemp nc perl pod2text realpath
		rm rsync sqlite3 tail timeout
		vipe wget whiptail xxd
	)

	local code="${1:-1}" cmd missing=

	for cmd in "${dependencies[@]}"
	do
		if ! command -v "$cmd" &>/dev/null
		then missing+="$cmd, "
		fi
	done

	if test -n "$missing"
	then error "$code" "missing dependencies: ${missing%, }"
	fi
}

has_connection() {

	local website="$1"

	timeout 2 nc -zw1 "$website" 443 &>/dev/null

	# https://unix.stackexchange.com/q/190513
}

has_perl_module() {

	local module="$1"

	perl -M$module -e 1 2>/dev/null

	# https://stackoverflow.com/a/1039262
}

is_repo() {

	local candidate="$1"

	test -f "$candidate/$database"
}

enforce_repo_context() {

	# defines a global variable called repo

	if is_repo "$target"
	then
		repo="$target"

	elif is_repo "$DEFAULT_YOUTUBE_THUMBNAIL_REPOSITORY"
	then
		repo="$DEFAULT_YOUTUBE_THUMBNAIL_REPOSITORY"
		warn 'falling back to default repository'
	else
		error 6 "not a repository: $target"
	fi
}

fzf_load() {
	sqlite3 -separator "$fzf_delim" "$repo/$database" "$fzf_query"
}

fzf_delete() {
	local video_id
	for video_id
	do
		sqlite3 "$repo/$database" <<- SQL
		DELETE FROM content WHERE id is '$video_id';
		SQL
		find "$repo" -name "$video_id.jpg" -exec rm {} \;
	done
}

fzf_preview() {

	local video_id="$1" form="$2" dim flags imagepath

	dim=${FZF_PREVIEW_COLUMNS}x$FZF_PREVIEW_LINES

	if test $form = short
	then flags='-gravity center -crop 9:16'
	else flags='-trim'
	fi

	imagepath="$(find "$repo" -name "$video_id.jpg")"

	convert "$imagepath" $flags jpg:- 2> /dev/null |
		chafa --view-size $dim --align center,center -
}

reverse_lookup() {

	local string="$1" separator="${2:-,}" array

	IFS="$separator" read -a array <<< "$string"

	declare -gA indices

	for i in "${!array[@]}"
	do indices[${array[$i]}]=$((i+1))
	done
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

	find "$@" -maxdepth 1 -type f -iname '*.jpg' -print0 |
	du -ch --files0-from=- |
	tail -1 | cut -f1

	# Preferred over 'du -ch -- *.jpg' so as not to exceed ARG_MAX
}

# Command-line Argument Parsing ------------------------------------------- {{{1

declare opt_{help,doc,quiet,target,default,invalid}=false

while getopts :Hhqr:d opt
do
	case "$opt" in

		H) opt_doc=true;;
		h) opt_help=true;;
		q) opt_quiet=true;;
		r)
			opt_target=true
			opt_default=false
			target="$OPTARG"
		;;
		d)
			opt_default=true
			opt_target=false
		;;
		*) opt_invalid=true; invalid_opt+="$OPTARG";;
	esac
done

# help should always be available,
# regardless of whether preconditions are met

if $opt_help || test $# -eq 0
then
	usage # uses no external binaries
	exit 0
fi

shift $((OPTIND - 1))
cmd="${1,,}"
shift
OPTIND=1

# Precondition Checks ----------------------------------------------------- {{{1

error_on_missing_dependencies 1 # must be called before any external command

has_perl_module HTML::Entities || error 2 'perl module HTML::Entities required'

has_connection img.youtube.com || error 3 'no internet connectivity'

# Option Handling --------------------------------------------------------- {{{1

# Options are handled after they are parsed to enforce a consistent order of
# evaluation.  If actions were performed in the getopts loop, then the
# evaluation order would depend on the order the user passed the flags.

$opt_invalid && warn "unknown global option -$invalid_opt"

if $opt_doc
then
	documentation
	exit 0
fi

if $opt_default
then
	test -v DEFAULT_YOUTUBE_THUMBNAIL_REPOSITORY ||
		error 4 'default repository not defined'

	target="$DEFAULT_YOUTUBE_THUMBNAIL_REPOSITORY"
fi

if $opt_target || $opt_default
then
	test -d "$target" || error 5 "not a directory: $target"

	target="$(realpath -m "$target")" # strip trailing slashes
fi

# Command Processing ------------------------------------------------------ {{{1

case "$cmd" in

	init) # ----------------------------------------------------------- {{{2

		mkdir -p "$target"/{long,short}

		sqlite3 "$target/$database" <<- SQL

		CREATE TABLE content (
			id TEXT PRIMARY KEY,
			form INTEGER NOT NULL,
			title TEXT,
			channel TEXT,
			quality INTEGER,
			attempts INTEGER DEFAULT 0,
			indexed DATETIME DEFAULT CURRENT_TIMESTAMP
		);

		CREATE VIEW content_view AS
		SELECT
			id,
			CASE form
				WHEN 0 THEN 'long'
				WHEN 1 THEN 'short'
			END AS form,
			title,
			channel,
			CASE quality
				WHEN 0 THEN 'default'
				WHEN 1 THEN 'mqdefault'
				WHEN 2 THEN 'hqdefault'
				WHEN 3 THEN 'sddefault'
				WHEN 4 THEN 'maxresdefault'
				ELSE NULL
			END AS quality,
			attempts,
			CASE
				WHEN quality IS NULL THEN FALSE
				ELSE TRUE
			END AS downloaded,
			CASE
				WHEN title IS NULL OR channel IS NULL THEN FALSE
				ELSE TRUE
			END AS scraped
		FROM content;
		SQL
	;;
	get) # ------------------------------------------------------------ {{{2

		msg='under maintenance during reactor, check back later.'
		msg+=' Use commands "index","download", and "scrape" instead.'

		error_cmd 11 "$msg"

		# TODO implement a compound command `get` which executes the
		# `index`, `download`, and `scrape` commands in sequence by
		# falling through the case statement, like this:
		#
		#         case "$cmd" in
		#             get)          ;;&
		#             get|index)    ;;&
		#             get|download) ;;&
		#             get|scrape)   ;;
		#         esac
		#
		# The compound command `get` will have its own set of options
		# and arguments, some of which will propagate through to the
		# constituent commands.  To implement this, a flag can be set in
		# the first case to determine whether "$cmd" is compound or
		# simple.  Argument parsing can be handled in the first case if
		# compound and in subsequent cases if simple.  Here are some
		# ideas for options and arguments to the compound command.
		#
		# Options:
		#   -p  propagate the [p]rogress flag through to
		#       each of `download` and `scrape`
		#   -b  run each of `download` and `scrape` in
		#       the [b]ackground (`index` must run in
		#       the foreground because it prompts the
		#       user to enter text interactively)
		#
		# Arguments:
		#   [files(s)]  propagates through to the `index` command
	;;
	index) # ---------------------------------------------------------- {{{2

		enforce_repo_context

		for candidate
		do test -e "$candidate" || error_cmd 8 "not a file: $candidate"
		done

		# NOTE -e is preferred over -f to allow for process substitution

			# test -e <(echo file contents); echo $?
			# test -f <(echo file contents); echo $?

		urls="$(mktemp)"; trap "rm -f $urls" EXIT

		if test $# -gt 0
		then cat "$@"
		else vipe
		fi > "$urls"

		for form in "${forms[@]}"
		do
			grep -oP "${patterns[$form]}" "$urls" |
				while IFS= read -r id
				do
					sqlite3 "$repo/$database" <<- SQL
					INSERT OR IGNORE
					INTO content (id, form)
					VALUES ('$id', '$form');
					SQL
				done
		done
	;;
	download) #-------------------------------------------------------- {{{2

		enforce_repo_context

		declare opt_progress_bar=false

		while getopts :p opt
		do
			case "$opt" in
				p) opt_progress_bar=true;;
				*) warn_unknown_cmd_opt;;
			esac
		done

		shift $((OPTIND - 1))

		constraint='downloaded IS FALSE'

		constraint+=" AND attempts < $max_download_attempts"

		query="SELECT id,form FROM content_view WHERE $constraint;"

		if $opt_progress_bar
		then
			count_query="${query/id,form/COUNT(*)}"
			total=$(sqlite3 "$repo/$database" "$count_query")
			current=0
		fi

		sqlite3 "$repo/$database" "$query" | while IFS=\| read -r id form
		do
			sqlite3 "$repo/$database" <<- SQL
			UPDATE content
			SET attempts = attempts + 1
			WHERE id = '$id';
			SQL

			imagepath="$repo/$form/$id.jpg"

			url_prefix="https://img.youtube.com/vi/$id"

			for ((i = ${#qualities[@]} - 1; i >= 0; i--))
			do
				url="$url_prefix/${qualities[$i]}.jpg"

				if wget -qO "$imagepath" "$url"
				then
					sqlite3 "$repo/$database" <<- SQL
					UPDATE content
					SET quality = $i
					WHERE id = '$id';
					SQL
					break
				fi
			done

			if $opt_progress_bar
			then
				# TODO compute and report ETA
				percentage=$((++current * 100 / total))
				echo $percentage
			fi
		done |
		if $opt_progress_bar
		then whiptail --gauge 'Downloading Thumbnails' $gauge_{height,width,percent}
		fi
	;;
	scrape) # --------------------------------------------------------- {{{2

		enforce_repo_context

		declare opt_progress_bar=false

		while getopts :p opt
		do
			case "$opt" in
				p) opt_progress_bar=true;;
				*) warn_unknown_cmd_opt;;
			esac
		done

		shift $((OPTIND - 1))

		constraint='scraped IS FALSE AND downloaded IS TRUE'

		query="SELECT id FROM content_view WHERE $constraint;"

		if $opt_progress_bar
		then
			count_query="${query/id/COUNT(id)}"
			total=$(sqlite3 "$repo/$database" "$count_query")
			current=0
		fi

		webpage="$(mktemp)"; trap "rm -f $webpage" EXIT

		sqlite3 "$repo/$database" "$query" | while IFS= read -r id
		do
			# download the webpage

			wget -qO "$webpage" "https://youtu.be/$id"

			# extract the title as a hex-encoded string

			title="$(perl -MHTML::Entities -ne '
				if (/<title>\K([^<]*)/) {
					print unpack("H*", decode_entities(substr($1, 0, -10)));
					last;
				}
			' < "$webpage")"

			# extract the channel name as a hex-encoded string

			channel="$(perl -ne '
				if (/ChannelName":"([^"]*)/) {
					print unpack("H*", $1);
					last;
				}
			' < "$webpage")"

			# interpolate hex-encoded strings to avoid quoting hell

			sqlite3 "$repo/$database" <<- SQL
			UPDATE content
			SET
				title = CAST(x'$title' AS TEXT),
				channel = CAST(x'$channel' AS TEXT)
			WHERE id = '$id';
			SQL

			# update the progress bar

			if $opt_progress_bar
			then
				# TODO compute and report ETA
				percentage=$((++current * 100 / total))
				echo $percentage
			fi

		done |
		if $opt_progress_bar
		then whiptail --gauge 'Scraping Data' $gauge_{height,width,percent}
		fi
	;;
	stats) #----------------------------------------------------------- {{{2

		enforce_repo_context

		for form in long short
		do
			declare ${form}_count=$(jpg_count "$repo"/$form)
			declare ${form}_size=$(jpg_size "$repo"/$form)
		done

		total_count=$((long_count + short_count))
		total_size=$(jpg_size "$repo"/{long,short})

		column -tN ' ',LONGS,SHORTS,TOTAL <<-REPORT
		COUNT $long_count $short_count $total_count
		SIZE  $long_size  $short_size  $total_size
		REPORT
	;;
	search) # --------------------------------------------------------- {{{2

		enforce_repo_context

		declare opt_{channel,long,short,url}=false

		while getopts :clsu opt
		do
			case "$opt" in

				c) opt_channel=true;;
				l)
					opt_long=true
					opt_short=false
				;;
				s)
					opt_short=true
					opt_long=false
				;;
				u) opt_url=true;;
			esac
		done

		shift $((OPTIND - 1))

		fzf_delim=$'\t'
		fzf_fields=id,form,title
		fzf_message="${ansi[yellow]}Enter${ansi[reset]} to choose"
		fzf_message+=" | ${ansi[yellow]}Del${ansi[reset]} to delete"

		reverse_lookup $fzf_fields

		constraint='downloaded IS TRUE AND scraped IS TRUE'

		$opt_long  && constraint+=" AND form IS 'long'"
		$opt_short && constraint+=" AND form IS 'short'"

		if $opt_channel
		then
			selection_set=

			while read -r channel
			do selection_set+="x'$(printf '%s' "$channel" | xxd -p -c0)',"
			done < <(
				sqlite3 -separator $'\t' "$repo/$database" <<-SQL |
				SELECT channel, COUNT(id) AS occurrences
				FROM content_view
				GROUP BY channel
				ORDER BY occurrences DESC, channel ASC;
				SQL
					column \
						--table \
						--table-columns CHANNEL,THUMBNAILS \
						--separator $'\t' \
						--output-separator $'\t' |
					fzf \
						--delimiter $'\t' \
						--multi \
						--nth 1 \
						--accept-nth 1 \
						--header-lines 1)

			constraint+=" AND CAST(channel as BLOB) IN (${selection_set%,})"
		fi

		fzf_query="SELECT $fzf_fields FROM content_view WHERE $constraint;"

		export repo database fzf_{query,delim}
		export -f fzf_{load,delete,preview}

		fzf_load | SHELL="$BASH" fzf \
			--multi \
			--delimiter "$fzf_delim" \
			--with-nth ${indices[title]} \
			--accept-nth ${indices[id]},${indices[form]} \
			--preview "fzf_preview {${indices[id]}} {${indices[form]}}" \
			--bind "del:execute-silent(fzf_delete {+${indices[id]}})+reload(fzf_load)" \
			--bind resize:refresh-preview \
			--header "$fzf_message" |
		while IFS="$fzf_delim" read -r id form
		do
			if $opt_url
			then
				if test $form = short
				then echo https://www.youtube.com/shorts/$id
				else echo https://www.youtube.com/watch?v=$id
				fi
			else find "$repo" -type f -name $id.jpg
			fi
		done
	;;
	absorb) # ---------------------------------------------------------

		enforce_repo_context

		declare opt_{delete,dryrun,progress}=false

		while getopts :dnp opt
		do
			case "$opt" in

				d) opt_delete=true;;
				n) opt_dryrun=true;;
				p) opt_progress=true;;
				*) warn_unknown_cmd_opt;;
			esac
		done

		shift $((OPTIND - 1))

		test $# -eq 1 || error_cmd 9 'exactly one argument is required'

		primary="$repo"
		secondary="$(realpath -m "$1")"

		test -d "$secondary" ||
			error_cmd 10 "not a directory: $1"

		is_repo "$secondary" ||
			error_cmd 10 "not a repository: $1"

		if $opt_dryrun
		then
			for form in long short
			do
				sqlite3 "$primary/$database" <<- SQL |
				ATTACH '${secondary//\'/\'\'}/$database' AS source;
				SELECT COUNT(id) FROM source.content_view
				WHERE id NOT IN (SELECT id FROM main.content_view)
				AND form IS '$form';
				SQL
				{
					read count;

					if test $count -eq 1
					then suffix=
					else suffix=s
					fi

					echo would index $count $form$suffix
				}
			done

			$opt_delete && echo would delete "$secondary"

			# TODO rsync --dry-run ???

			exit 0
		fi

		sqlite3 "$primary/$database" <<- SQL
		BEGIN TRANSACTION;
		ATTACH '${secondary//\'/\'\'}/$database' AS source;
		INSERT OR IGNORE INTO main.content SELECT * FROM source.content;
		COMMIT;
		SQL

		rsync_flags='--archive --ignore-existing'

		$opt_progress && rsync_flags+=' --no-i-r --info=progress2'

		for form in long short
		do
			$opt_progress && echo $form

			rsync $rsync_flags {"$secondary","$primary"}/$form/
		done

		if $opt_delete
		then
			echo rm -rI "$secondary"
			     rm -rI "$secondary" # always prompt
		fi
	;;
	troubleshoot) # --------------------------------------------------- {{{2

		enforce_repo_context

		for form in long short
		do
			query="SELECT COUNT(id) FROM content_view WHERE form IS '$form';"

			declare ${form}s_indexed=$(sqlite3 "$repo/$database" "$query")
			declare ${form}s_downloaded=$(jpg_count "$repo/$form")
			declare ${form}s_diff=$((${form}s_indexed-${form}s_downloaded))
		done

		     indexed=$((longs_indexed + shorts_indexed))
		  downloaded=$((longs_downloaded + shorts_downloaded))
		undownloaded=$((indexed - downloaded))

		column -tN ' ',LONGS,SHORTS,TOTAL <<-REPORT
		INDEXED    $longs_indexed    $shorts_indexed    $indexed
		DOWNLOADED $longs_downloaded $shorts_downloaded $downloaded
		DIFFERENCE $longs_diff       $shorts_diff       $undownloaded
		REPORT
	;;
	dump) # ----------------------------------------------------------- {{{2

		enforce_repo_context

		query='SELECT * FROM content_view;'

		cols=ID,FORM,TITLE,CHANNEL,QUALITY,ATTEMPTS,DOWNLOADED,SCRAPED

		sqlite3 -separator $'\t' "$repo/$database" "$query" |
			column -ts $'\t' -N $cols |
			less -S +k
	;;
	# }}}

	*) error 7 "unknown command \"$cmd\"";;
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

options: [-h] [-H] [-q] [-r <dir> | -d]

commands: init, index, download, scrape, get, stats, search, absorb

=head1 DESCRIPTION

This program allows its user to curate an offline repository of YouTube
thumbnails.  It is a workflow-centric program designed to supplement the YouTube
browsing experience.  This program not only downloads thumbnails but also
facilitates the organization of them on your computer.

=head2 Objective

To incrementally build up an offline collection of YouTube thumbnails organized
into the following file structure, which we call a B<YouTube thumbnail
repository>.

	repo/
	|-- .yt.db
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

Downloaded thumbnails are named with their video's ID.  Representatively, the
file C<aaaaaaaaaaa.jpg> is the downloaded thumbnail image of a YouTube video
whose ID is C<aaaaaaaaaaa>.  This naming scheme is chosen for programmatic
simplicity, not for human readability.  Note that a search command is provided
for finding thumbnails by their video's title.

The hidden file named C<.yt.db> is an SQLite database file which stores
information about the downloaded thumbnails.

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

This program has a concept of a working directory.  The commands that you
execute affect the repository you are in.  You can create multiple repositories,
perhaps to capture different thematic elements in images.

If you execute a command in a directory that is not designated as a thumbnail
repository, you will receive an error.  To alleviate the burden of navigating
your file system, you can also define a I<default> thumbnail repository, so that
if a command is executed outside of a repository, the default repository is
assumed instead of giving an error.

=head1 OPTIONS

There are two types of options: global and specific.

	program [global-options] <subcommand> [specific-options]

Global options apply to the program as a whole.  They appear before the
subcommand on the command line.  Some of them cause the program to exit
prematurely without processing the subcommand (e.g., -h and -H), while others
change the way that the program behaves (e.g., -q, -r, and -d).  In the former
case, the subcommand is not required.  In the latter case, a subcommand is
expected.

Specific options are contingent on the subcommand used.  They appear after the
subcommand and affect its behavior.  These command-specific options are
documented in the COMMANDS section under each respective command.

Enumerated below are the global command-line options.

=over

=item B<-h>

Display a [h]elp message and exit.

=item B<-H>

Display this documentation in a pager and exit after the user quits.  The
documentation is divided into sections.  Each section header is matched with a
search pattern, meaning that you can use navigation commands like C<n> and its
counterpart C<N> to go to the next or previous section respectively.  The
uppercase -H is to parallel the lowercase -h.

=item B<-q>

Be [q]uiet: silence warnings and errors.  Warnings are friendly messages to
alert the user about a non-critical or potential issue.  Error messages indicate
a critical issue that caused the program to exit prematurely.  Output should
still be expected for commands whose explicit purpose is to display information,
e.g., the C<stats> command.

=item B<-r> I<PATH>

Run as if this program was started in I<PATH> instead of in the working
directory.  This option allows the user to change the targeted thumbnail
[r]epository.  As noted earlier, this program has a concept of a working
directory.  The commands that you execute affect the repository you are in.

=item B<-d>

Explicitly target the [d]efault repository, even when the user's working
directory is already a repository.  Usually, the default repository is a
fallback for when commands are issued outside of a repository.  This flag forces
the default repository to be used no matter what.  See the ENVIRONMENT section
for more information.

This flag is mutually exclusive with B<-r>, and if both are provided, the last
one to be specified on the command-line takes priority.

=back

=head1 COMMANDS

=over

=item init

This command initializes the working directory as a YouTube thumbnail
repository.  It is the only command which does not require the working directory
to already be a YouTube thumbnail repository.

Initializing a thumbnail repo means

=over

=item

Creating a hidden database file to store information about thumbnails.  The
presence of this file is what determines whether a given directory is a
thumbnail repository.

=item

Creating two visible folders to separate video thumbnails into, by content type:
shorts and longs.

=back

You can create multiple repositories, one per directory, but you probably
shouldn't nest them.

=item index [files(s)]

This command adds YouTube videos to an index.  The index is just a staging area.
This command does I<not> download the thumbnails; it only marks them to be
downloaded at a later time.

Videos can be added to the index in one of two ways.

=over

=item 1)

When invoked without file arguments, this command opens the command-line text
editor determined by the environment variable EDITOR.  When this editor is
closed, its contents are examined for YouTube video links.  You should
copy-and-paste into it.

=item 2)

When invoked with file arguments, the links are read from those files instead of
opening a text editor for interactive use.

=back

In either method, full URLs should be supplied.  It does not matter what a link
looks like, so long as it points to a YouTube video, either long or short.  The
link can include extra query parameters like timestamps and playlist IDs.  It
can even be link-shortened as L<youtu.be>.  The URLs do not necessarily have to
be supplied line-by-line, but this is most natural.  (Note that this command is
responsible for differentiating videos by their content type.  The link is used
to determine this.)

=item download [-p]

This command downloads thumbnails in the index if they haven't already been
downloaded.  The image is obtained in its best possible quality as a JPEG file.
The B<-p> flag can be supplied to monitor the [p]rogress of the download.

=item scrape [-p]

This command retrieves metadata for thumbnails in the index.  It scrapes each
video's webpage for relevant information.  Currently, the title and channel name
are acquired, and these are used to allow the user to search for a thumbnail in
their repository offline.  Only downloaded thumbnails are scraped, and only if
they haven't already been scraped.  The B<-p> flag can be supplied to monitor
the [p]rogress of the operation.

=item get [-p] [file(s)]

This is a compound command which executes the C<index>, C<download>, and
C<scrape> commands in sequence.  The C<get> command can be regarded as a
high-level command, while the commands C<index>, C<download>, and C<scrape> can
be regarded as low-level.  The user should prefer to use C<get> instead of
C<index>, C<download>, and C<scrape> independently.  A typical workflow will
consist primarily of calling the C<get> and C<search> commands.

The disadvantage of issuing the low-level commands independently is that if they
are issued at different times, then information could be lost.  For example,
adding a thumbnail to the index but downloading it a week later would provide
opportunity for the video to be privated, deleted, or taken down due to
copyright.  This could pollute the repository with empty image files and missing
metadata.  The C<get> command makes everything happen at once, thereby
circumventing these issues.

The B<-p> flag propagates the [p]rogress flag through to each of `download` and
`scrape`.  Any [file(s)] are passed to the C<index> command.  See earlier.

TODO remark on why the commands were implemented separately in the first place

=item stats

This command prints statistics about a thumbnail repository in a table format.
This information includes the total number of thumbnails, how many are shorts
versus longs, and how much disk space is used.  Here is a sample output.

	       LONGS  SHORTS  TOTAL
	COUNT  3014   218     3232
	SIZE   313M   22M     335M

The primary use is to gauge the size of a repository.
Further reporting may be implemented in the future.

=item search [-c] [-u] [-s | -l]

This command launches a text-user interface to search for and preview thumbnail
images in your repository, all from the comfort of your terminal.

                               +----------+
        | thumbnail title here |          |
        | thumbnail title here | image    |
        | thumbnail title here | preview  |
          directions here      | here     |
          ---------------------|          |
        > search query here    +----------+

On the left is a searchable, scrollable list of thumbnails identified by video
title.  On the right is a preview of the currently-selected thumbnail.  The
well-known command-line fuzzy finder C<fzf> is used for searching.  Command-line
image rendering is accomplished with C<chafa>.

You can

=over

=item * search by typing

=item * scroll up and down with the arrow keys

=item * select and de-select images with the tab key

=item * delete selected images by pressing the DEL key

=item * press enter to confirm your selection

=back

Upon pressing enter, the absolute paths of selected images are printed to
standard output line by line.  These can be piped to other tools.  Here is an
example.

	bash youtube-thumbnail-manager.sh search | xargs xdg-open

This would open each image with the system's default image viewer.  By passing
the B<-u> flag, the command will output the [U]RL of each video instead of the
image path to the thumbnail.

	bash youtube-thumbnail-manager.sh search -u | xargs xdg-open

This would open each selected YouTube video with the system's default web
browser.

This covers the basic usage of the command.  The remaining command-line flags
pertain to filtering the search space.  Pass the B<-s> flag to limit the search
to [s]hort-form content.  Pass the B<-l> flag to limit the search to [l]ong-form
content.  These flags are mutually exclusive, and if both are provided, the last
one to be specified on the command-line takes priority.

The B<-c> flag allows the user to restrict the search space to content
originating from particular YouTube [c]hannels.  Prior to displaying the primary
text-user interface, a supplementary instance of fzf launches to allow the user
to select one or more YouTube channels.

	| channel name here       1
	| channel name here       2
	| channel name here       3
	  CHANNEL                 THUMBNAILS
	  ----------------------------------
	> search query here

Two columns are displayed.  The first column is the name of the YouTube channel.
The second column indicates how many thumbnails in the repository originate from
that channel.  This list is sorted first by the number of thumbnails and second
by the channel name, lexicographically.

The B<-c> flag may be compounded with the B<-s> flag or the B<-l> flag to
restrict the search space to either short-form or long-form content respectively
originating from a particular set of channels.

=item absorb [-dnp] <repo>

This command pulls in images from another repository.  Given two thumbnail
repositories I<primary> and I<secondary>, images unique to I<secondary> are
copied into I<primary>.

Like other commands, the I<primary> repository is determined by the operational
context, usually the user's working directory.  The I<secondary> repository is
specified as an argument to the command.  For example, if the working
directory is a thumbnail repository, and you want to pull in images from a
repository in a sibling directory, you would type

	bash youtube-thumbnail-manager.sh absorb ../secondary/

Or by using the B<-r> flag in the parent directory:

	bash youtube-thumbnail-manager.sh -r primary/ absorb secondary/

Only the primary repository is modified, unless you choose to delete the
secondary with B<-d>.  Beyond merely copying image files, this command also
updates the metadata indexes in the primary repository.

To gauge the scale of the ensued operation, do a dry run with B<-n>.

	bash youtube-thumbnail-manager.sh -r pri/ absorb -n -d sec/

This gives a message like this.

	would index n longs
	would index m shorts
	would delete /path/to/secondary

You can monitor the progress of the operation with the B<-p> flag, which is
relevant when the secondary repository is large.

	bash youtube-thumbnail-manager.sh -r pri/ absorb -p sec/

=item troubleshoot

This command identifies discrepancies between indexed and downloaded images.
Its output is a table that looks like this.

		    LONGS  SHORTS  TOTAL
	INDEXED     3170   226     3396
	DOWNLOADED  3170   226     3396
	DIFFERENCE  0      0       0

This table pertains to the success of the C<download> command.  A difference of
zero indicates that nothing is wrong; all indexed images have been downloaded.

This command is purposefully excluded from the command-line help message.  It is
more relevant to me, the programmer, than it is to you, the user.  My own
repositories have grown unwieldy because they carry remnants from earlier stages
in the development of this tool.

=item dump

This command displays the contents of the SQLite database in a pager.  This
command is purposefully excluded from the command-line help message.

=back

=head1 DIAGNOSTICS

The program exits with the following status codes.

=over

=item 0 successful completion

=item 1 missing dependencies

=item 2 missing Perl module HTML::Entities

It can be installed on Arch Linux with this command.

	sudo pacman -S perl-html-parser

=item 3 no internet connectivity

=item 4 default repository not defined

This error occurs when the default repository is explicitly targeted with the
B<-d> flag but the environment variable specifying the default repository is
unset.  See the ENVIRONMENT section.

=item 5 not a directory

This can occur when using B<-d> or B<-r> I<PATH>.

=item 6 not a repository

You have to initialize the targeted directory as a repository prior to use.

	bash youtube-thumbnail-manager.sh -r path/to/dir/ init

=item 7 unknown command

=item 8 command index/get: not a file

A non-file argument was passed to the C<index> or C<get> command.

=item 9 command absorb: exactly one argument is required

=item 10 command absorb: not a directory/repository

The argument supplied to the C<absorb> command is invalid.

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

=head1 AUTHOR

Zachary Krepelka L<https://github.com/zachary-krepelka>

=cut

# vim: tw=80 ts=8 sw=8 noet fdm=marker
