###############################################################################
#  Name:                                        Youtube Title
#  Author:                                      jotham.read@gmail.com
#  Credits:                                     tinyurl proc taken from
#                                                  tinyurl.tcl by jer@usa.com.
#                                               design inspiration from
#                                                  youtube.tcl by Mookie.
#  Eggdrop Version:     1.6.x
#  TCL version 8.1.1 or newer http://wiki.tcl.tk/450
#
#  Changes:
#  0.6 11/11/14
#    [mina86] Added support for https and youtu.be URLs.  Made the pattern
#    stricter.  Replace JSON parser with standard json TCL package.
#  0.5 01/02/09
#    Added better error reporting for restricted youtube content.
#  0.4 10/11/09
#    Changed title scraping method to use the oembed api.
#    Added crude JSON decoder library.
#  0.3 02/03/09
#    Fixed entity decoding problems in return titles.
#    Added customisable response format.
#    Fixed rare query string bug.
###############################################################################
#
#  Configuration
#
###############################################################################

package require json

# Maximum time to wait for youtube to respond
set youtube(timeout)            "30000"
# Youtube oembed location to use as source for title queries. It is best to use
# nearest youtube location to you.  For example http://uk.youtube.com/oembed
set youtube(oembed_location)    "http://www.youtube.com/oembed"
# Use tinyurl service to create short version of youtube URL. Values can be
# 0 for off and 1 for on.
set youtube(tiny_url)           0
# Response Format
# %botnick%         Nickname of bot
# %post_nickname%   Nickname of person who posted youtube link
# %title%           Title of youtube link
# %youtube_url%     URL of youtube link
# %tinyurl%         Tiny URL for youtube link. tiny_url needs to be set above.
# Example:
#   set youtube(response_format) "\"%title%\" ( %tinyurl% )"
set youtube(response_format) "YouTube Title: \"%title%\""
# Bind syntax, alter as suits your needs
bind pubm - * public_youtube
# Pattern used to patch youtube links in channel public text
set youtube(pattern) {https?://(?:.*\.)?(?:youtube\.com/watch\?(?:.*&)?v=|youtu\.be)([A-Za-z0-9_\-]+)}
# This is just used to avoid recursive loops and can be ignored.
set youtube(maximum_redirects)  2
# The maximum number of characters from a youtube title to print
set youtube(maximum_title_length) 256
###############################################################################

package require http

set gTheScriptVersion "0.6"

proc note {msg} {
  putlog "% $msg"
}

###############################################################################

proc make_tinyurl {url} {
 if {[info exists url] && [string length $url]} {
  if {[regexp {http://tinyurl\.com/\w+} $url]} {
   set http [::http::geturl $url -timeout 9000]
   upvar #0 $http state ; array set meta $state(meta)
   ::http::cleanup $http ; return $meta(Location)
  } else {
   set http [::http::geturl "http://tinyurl.com/create.php" \
     -query [::http::formatQuery "url" $url] -timeout 9000]
   set data [split [::http::data $http] \n] ; ::http::cleanup $http
   for {set index [llength $data]} {$index >= 0} {incr index -1} {
    if {[regexp {href="http://tinyurl\.com/\w+"} [lindex $data $index] url]} {
     return [string map { {href=} "" \" "" } $url]
 }}}}
 error "failed to get tiny url."
}

###############################################################################

proc extract_title {json_blob} {
	global youtube
	set data [::json::json2dict $json_blob]
	set title [string trim [dict get $data title]]
	if {[string length $title] >= $youtube(maximum_title_length)} {
		set title [string range $title 0 $youtube(maximum_title_length)]"…"
	} elseif {[string length $title] == 0} {
		set title "No usable title."
	}
	return $title
}

###############################################################################

proc fetch_title {youtube_uri {recursion_count 0}} {
    global youtube
    if { $recursion_count > $youtube(maximum_redirects) } {
        error "maximum recursion met."
    }
    set query [http::formatQuery url $youtube_uri]
    set response [http::geturl "$youtube(oembed_location)?$query" -timeout $youtube(timeout)]
    upvar #0 $response state
    foreach {name value} $state(meta) {
        if {[regexp -nocase ^location$ $name]} {
            return [fetch_title $value [incr recursion_count]]
        }
    }
	if [expr [http::ncode $response] == 401] {
		error "Location contained restricted embed data."
	} else {
	    set response_body [http::data $response]
	    http::cleanup $response
	    return [extract_title $response_body]
	}
}

proc public_youtube {nick userhost handle channel args} {
    global youtube botnick
    if {[regexp -nocase -- $youtube(pattern) $args match video_id]} {
        note "Fetching title for $match."
        if {[catch {set title [fetch_title $match]} error]} {
            note "Failed to fetch title: $error"
        } else {
            set tinyurl $match
            if { $youtube(tiny_url) == 1 && \
              [catch {set tinyurl [make_tinyurl $match]}]} {
               note "Failed to make tiny url for $match."
            }
            set tokens [list %botnick% $botnick %post_nickname% \
                $nick %title% "$title" %youtube_url% \
                "$match" %tinyurl% "$tinyurl"]
            set result [string map $tokens $youtube(response_format)]
            putserv "PRIVMSG $channel :$result" 
        }
    }
}

###############################################################################

note "youtube_title$gTheScriptVersion: loaded";

