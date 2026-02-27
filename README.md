# YouTube Thumbnail Downloader

<!--
	FILENAME: README.md
	AUTHOR: Zachary Krepelka
	DATE: Saturday, July 19th, 2025
	ORIGIN: https://github.com/zachary-krepelka/youtube-thumbnail-downloader.git
	UPDATED: Friday, February 27th, 2026 at 1:23 AM
-->

A shell script to bulk download YouTube thumbnail images

- [Introduction](#introduction)
- [Overview](#overview)
- [Requirements](#requirements)
- [Installation](#installation)
- [Getting Started](#getting-started)
- [Usage](#usage)
- [Configuration](#configuration)
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

2. `youtube-thumbnail-manager.sh` facilitates not only downloading
   thumbnails but also organizing them on your computer.  It provides a
   workflow-centric solution for managing a large, offline collection of
   YouTube thumbnails with CRUD-like functionality.  This workflow
   supplements the YouTube browsing experience.  The interface of this
   program and the workflow surrounding it are loosely similar to that
   of `git`, the ubiquitous version control system.

For brevity I will refer to these as `grabber` and `manager`.

> [!NOTE]
> `manager` was originally a wrapper around `grabber` but now implements
> its own backend.  Both scripts are self-contained downloaders.
> `grabber` is simpler, more robust, and useful for one-off use cases.
> `manager` is specifically designed for recurrent, ritualistic use with
> common-sense defaults, and it is a more complex program.

The third file with the `.tmux` extension is just a supplemental file.

## Requirements

These are prerequisite.

* As the user, you should have familiarity with the command-line
  interface and its conventions.

* Your system must have the [Bourne Again Shell][2] installed.  This is
  a given on Linux.  MacOS ships with an outdated version of bash
  preinstalled due to licensing issues, so Mac users should probably
  install a more up-to-date version.  Windows users should install the
  Windows Subsystem for Linux.  Note that bash does not have to be the
  login shell; it just has to be present on the system, preferably
  up-to-date.

* There are dependencies.  The two programs in this repository will
  report an error if a dependency is missing, which you can then install
  with your package manager.

## Installation

To demo these programs, you can either clone this repository or download
them directly from GitHub's web interface.  Little to no setup is
required if you have a working command-line environment.

> [!WARNING]
> Responsible GitHub visitors review the
> source code of a script before running it.

For a persistent installation, put the scripts `grabber` and `manager`
in a folder on your path and make them executable with the `chmod`
command.

## Getting Started

A command-line help message is obtained by passing the `-h` flag.

```bash
bash youtube-thumbnail-grabber.sh -h
```

Complete documentation can be read in the terminal by passing the `-H`
flag.  That's a capital H.

```bash
bash youtube-thumbnail-grabber.sh -H
```

This README file is intended to summarize the project altogether.  It
does not go into the specific operation of each script.  You should read
the full documentation with `-H` for full understanding.  You can use
the following command to read the documentation in your terminal without
actually having to save the scripts to your computer.  Copy-and-paste it
with the button to your right.

```bash
for script in grabber manager; do wget -qO- https://raw.githubusercontent.com/zachary-krepelka/youtube-thumbnail-downloader/refs/heads/main/youtube-thumbnail-$script.sh | pod2text | less; done
```

These help flags are available for both scripts.

## Usage

Here is the command-line help message for `grabber`.

<!-- :read !bash youtube-thumbnail-grabber.sh -h <Enter> -->

```text
Bulk Download YouTube Thumbnails From the Command Line

Usage:
  bash youtube-thumbnail-grabber.sh [options] <file (of urls)>

Options:
  -o {DIR}        specifies the [o]utput directory
  -f              [f]orcibly overwrite preexisting files
  -q {1,2,3,4,5}  image [q]uality from worst to best
  -i              select image quality [i]nteractively
  -b              download [b]est image quality available
  -a              download image in [a]ll qualities
  -w              download [w]ebp instead of jpg
  -p              monitor [p]rogress

Documentation:
  -h  display this [h]elp message and exit
  -H  read documentation for this script then exit

Example:
  bash youtube-thumbnail-grabber.sh -bp urls.txt
```

Here is the command-line help message for `manager`.

<!-- :read !bash youtube-thumbnail-manager.sh -h <Enter> -->

```text
Curate an Offline Repository of YouTube Thumbnails

Usage:
  bash youtube-thumbnail-manager.sh [opts] <cmd>

Options:
  -q        silence warnings and errors
  -r <dir>  target <dir> instead of $PWD as the [r]epo
  -d        target [d]efault repo even when $PWD is a repo

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
```

## Configuration

For a seamless experience, you can add these lines to your `.bashrc` or
equivalent.  You may have to alter them depending on your login shell,
e.g., if you use Zsh.

```bash
alias yt=youtube-thumbnail-manager.sh
complete -W 'init index download scrape get stats search absorb troubleshoot dump' yt
export DEFAULT_YOUTUBE_THUMBNAIL_REPOSITORY=/directory/of/your/choice
```

If you define a default repository, it should be initialized before
using the script as shown below.  To be clear, this should be done in an
interactive shell, not in the `.bashrc`.

```bash
cd $DEFAULT_YOUTUBE_THUMBNAIL_REPOSITORY; yt init
```

Tmux users can source the keybindings file to obtain a more convenient
interface around the `manager` script.

* Press `prefix + y` then `g` to get thumbnails.
* Press `prefix + y` then `s` to search thumbnails.

```bash
tmux source-file youtube-thumbnail-keybinds.tmux
```

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
repeating as many times as desired.  When I am done, I just save the
file and close the editor, which closes the pop-up dialog and initiates
the download process in the background.

You can read more about this workflow in the documentation.

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

```bash
bash youtube-thumbnail-grabber.sh -bp -o view-me/ bookmarks.html
```

### Personal Art Gallery

An [internet aesthetic][5] is a thematic style expressed online through
various elements such as color, fashion, imagery, music, objects,
people, settings, etc.  Examples include [Vaporwave][6], [Synthwave][7],
[Cyberpunk][8], [Future Funk][9], [Glitchcore][10], [Dreamcore][11],
[Liminal Spaces][12], [Dark Academia][13], etc.  These aesthetics
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
[3]:  https://archlinux.org/packages/extra/x86_64/moreutils
[4]:  https://en.wikipedia.org/wiki/GNU_Core_Utilities
[5]:  https://en.wikipedia.org/wiki/Internet_aesthetics
[6]:  https://aesthetics.fandom.com/wiki/Vaporwave
[7]:  https://aesthetics.fandom.com/wiki/Synthwave
[8]:  https://aesthetics.fandom.com/wiki/Cyberpunk
[9]:  https://aesthetics.fandom.com/wiki/Future_Funk
[10]: https://aesthetics.fandom.com/wiki/Glitchcore
[11]: https://aesthetics.fandom.com/wiki/Dreamcore
[12]: https://aesthetics.fandom.com/wiki/Liminal_Space
[13]: https://aesthetics.fandom.com/wiki/Dark_Academia
