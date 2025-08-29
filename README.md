# YouTube Thumbnail Downloader

<!--
	FILENAME: README.md
	AUTHOR: Zachary Krepelka
	DATE: Saturday, July 19th, 2025
	ORIGIN: https://github.com/zachary-krepelka/youtube-thumbnail-downloader.git
	UPDATED: Thursday, August 28th, 2025 at 7:59 PM
-->

A shell script to bulk download YouTube thumbnail images

- [Introduction](#introduction)
- [Overview](#overview)
- [Requirements](#requirements)
- [Installation](#installation)
- [Configuration](#configuration)
- [Getting Started](#getting-started)
- [Usage](#usage)
- [Workflow](#workflow)
- [Use Cases](#use-cases)

## Introduction

There are [plenty of websites][1] that let you download YouTube
thumbnails.  This repository reimagines that functionality in a
feature-rich, command-line form factor suitable for scripting and
automation.  Potential use cases are discussed in the latter-most
section of this document.

## Overview

This repository is the home of two shell scripts.

1. `youtube-thumbnail-grabber.sh` is a program that bulk downloads
   YouTube thumbnail images.  Its input is a file containing YouTube
   video URLs line-by-line.  It handles a wide variety of URLs
   irrespective of clutter.  Options are available to control image
   quality and file format.  It works on YouTube Shorts in addition to
   traditional videos.

2. `youtube-thumbnail-manager.sh` wraps `youtube-thumbnail-grabber.sh`
   to facilitate not only downloading thumbnails but also organizing
   them on your computer.  It provides a workflow-centric solution for
   managing a large, offline collection of YouTube thumbnails.  This
   workflow supplements the YouTube browsing experience.  The interface
   of this program and the workflow surrounding it are loosely similar
   to that of `git`, the ubiquitous version control system.

For brevity I will refer to these as `grabber` and `manager`.

## Requirements

These are prerequisite.

* As the user, you should have familiarity with the command-line
  interface.

* Your system must have the [Bourne Again Shell][2] installed.  This is
  a given on Linux.  MacOS ships with an oudated version of bash
  preinstalled due to lisensing issues, so Mac users should probably
  install a more up-to-date version.  Windows users should install the
  Windows Subsystem for Linux.  Note that bash does not have to be the
  login shell; it just has to be present on the system, preferably
  up-to-date.

* There are dependencies.  The programs will report an error if a
  dependency is missing, which you can then install with your package
  manager.

## Installation

To demo these programs, you can either clone this repository or download
them directly from GitHub's web interface.  Little to no setup is
required if you have a working command-line environment.

> [!WARNING]
> Responsible GitHub visitors review the
> source code of a script before running it.

For a persistent installation, put the script `grabber` in a folder on
your path and make it executable with the `chmod` command.  Optionally,
put `manager` *in the same directory* as `grabber`, again making it
executable.  Note that `grabber` is a self-contained program whereas
`manager` depends on `grabber`.

## Configuration

For a seamless experience, you can add these lines to your `.bashrc` or
equivalent.  You may have to alter them depending on your login shell,
e.g., if you use Zsh.

```bash
alias yt=youtube-thumbnail-manager.sh
complete -W 'init add scrape exec get stats search troubleshoot' yt
export DEFAULT_YOUTUBE_THUMBNAIL_REPOSITORY=/directory/of/your/choice
```

If you define a default repository, it should be initialized before
using the script as shown below.  To be clear, this should be done in an
interactive shell, not in the `.bashrc`.

```bash
cd $DEFAULT_YOUTUBE_THUMBNAIL_REPOSITORY; yt init
```

If you are a tmux user, I would suggest adding this to your
`.tmux.conf`.

```bash
bind y display-popup -w 90% -h 90% -E "bash -i -c 'yt -q get'"
bind Y display-popup -w 90% -h 90% -E "bash -i -c 'yt -q search'"
```

If you decide to rename these programs, perhaps because their names are
too verbose, then you will need to edit the reference to `grabber` in
the source code of `manager`.  CTRL+F should do the trick in a standard
text editor.  I prefer to use an alias as shown above.

Don't worry if this config does not make sense yet.

## Getting Started

`manager` builds on top of `grabber`, so its operation is more complex.
I suggest you start out by trying `grabber` first.  A command-line help
message is obtained by passing the `-h` flag.

```bash
bash youtube-thumbnail-grabber.sh -h
```

Complete documentation can be read in the terminal by passing the `-H`
flag.

```bash
bash youtube-thumbnail-grabber.sh -H
```

Notice that the `-H` flag is capitalized to parallel the `-h` flag.
These flags are available for both scripts.

## Usage

Here is the command-line help message for `grabber`.

```text
usage: youtube-thumbnail-grabber.sh [options] <file (of urls)>
download YouTube thumbnails in bulk from the command line

options:
  -h             display this [h]elp message and exit
  -H             read documentation for this script then exit
  -o {DIR}       specifies the [o]utput directory
  -f             [f]orcibly overwrite preexisting files
  -q {1,2,3,4,5} image [q]uality from worst to best
  -i             select image quality [i]nteractively
  -b             download [b]est image quality available
  -a             download image in [a]ll qualities
  -w             download [w]ebp instead of jpg
  -p             monitor [p]rogress

example: bash youtube-thumbnail-grabber.sh -bp urls.txt
```

Here is the command-line help message for `manager`.

```text
usage: youtube-thumbnail-manager.sh [opts] <cmd>
curate an offline repository of YouTube thumbnails

options:
  -h        display this [h]elp message and exit
  -H        read documentation for this script then exit
  -q        be [q]uiet: silence warnings but not errors
  -r <dir>  use <dir> as the [r]epo instead of $PWD

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
```

This README file is intended to summarize the project altogether.  It
does not go into the specific operation of each script.  I suggest you
read the full documentation to understand what each option and command
does in detail.  The `-H` flag is your friend.

## Workflow

I move back and forth between a web browser and a terminal using my
window manager's keyboard shortcuts `ALT + HJKL`.  In a web browser, I
identify a YouTube video whose thumbnail I want to keep and copy its
link to my clipboard.  For this purpose, I use the Vimium browser
extension, scrolling up and down with `k` and `j` and snagging links
with `yf<hint>`.  In the terminal, I type `CTRL+B Y` to open up a
special tmux pop-up dialog if it is not already open.  The pop-up dialog
opens to a text editor with a blank buffer.  I paste the YouTube link on
my clipboard and move back into the web browser to continue the process,
reapeating as many times as desired.  When I am done, I just save the
file and close the editor, which closes the pop-up dialog and initiates
the download process in the background.

You can read more about this workflow with `yt -H`.

## Use Cases

Why download YouTube thumbnails?  Here are some potential use cases.

### Wallpapers

YouTube thumbnails come in wide varieties.  Some are silly while others
are aesthetic and artful.  This latter kind make for great desktop
wallpapers.  Indeed, YouTube thumbnails can be obtained in a high
quality suitable for this purpose.

### Data Visualization

Bookmarking refers to the practice of saving links to web pages for
future reference.  My script can be invoked on a bookmark file to
download the thumbnails of every bookmarked YouTube video or YouTube
Short.  When viewed in a grid layout using a file explorer, this can
serve to visualize one's collection of bookmarked YouTube videos.

### Personal Art Gallery

An [internet aesthetic][3] is a thematic style expressed online through
various elements such as color, fashion, imagery, music, objects,
people, settings, etc.  Examples include [Vaporwave][4], [Synthwave][5],
[Cyberpunk][6], [Future Funk][7], [Glitchcore][8], [Dreamcore][9],
[Liminal Spaces][10], [Dark Academia][11], etc.  These aesthetics
manifest in YouTube thumbnails.  A collection of thumbnails could
constitute a personal art gallery for a digital native interested in
internet culture.  They could serve to document one's exposure to
different ecosystems of the larger YouTube biosphere.

### Separation of Concerns

Thumbnails are a vital part of the YouTube ecosystem, and by some
stretch, YouTube is just as much of an image board as a video-sharing
platform.  You may be tempted to click on a video because its thumbnail
looks interesting, not because its title intrigued you.  Using my
personal workflow, I have learned to disassociate the appeal of a
YouTube video and the appeal of its thumbnail.  Let's stay focused.
Archive an image if you like it, and choose to watch the video by
evaluating its title and relevancy to your interests or task at hand.

[1]:  https://www.google.com/search?q=youtube+thumbnail+downloader
[2]:  https://en.wikipedia.org/wiki/Bash_(Unix_shell)
[3]:  https://en.wikipedia.org/wiki/Internet_aesthetics
[4]:  https://aesthetics.fandom.com/wiki/Vaporwave
[5]:  https://aesthetics.fandom.com/wiki/Synthwave
[6]:  https://aesthetics.fandom.com/wiki/Cyberpunk
[7]:  https://aesthetics.fandom.com/wiki/Future_Funk
[8]:  https://aesthetics.fandom.com/wiki/Glitchcore
[9]:  https://aesthetics.fandom.com/wiki/Dreamcore
[10]: https://aesthetics.fandom.com/wiki/Liminal_Space
[11]: https://aesthetics.fandom.com/wiki/Dark_Academia
