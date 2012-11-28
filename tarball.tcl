package require csv
package require struct::matrix


namespace eval txz {


### Common

proc say {nick channel data} {
	puthelp "PRIVMSG $channel :$nick: $data"
}


### FAIF

proc readFaifCSV {filename data} {
	struct::matrix tmp
	tmp add columns 5

	if {[catch {
		set fd [open $filename]
		csv::read2matrix $fd [namespace current]::tmp
		close $fd

		if {[[namespace current]::tmp rows]} {
			$data = [namespace current]::tmp
		}
	} e]} {
		putlog "Error while reading $filename: $e"
	}

	tmp destroy
}

proc refreshFaif {} {
	global faif_topic
	readFaifCSV scripts/data/faif faif
	if {[faif rows]} {
		set row [faif get row 0]
		set faif_topic "[lindex $row 1] <[lindex $row 3]>"
	}
}

proc initFaif {} {
	global faif_topic
	set faif_topic ""

	struct::matrix faif
	faif add columns 5

	struct::matrix sfls
	sfls add columns 5

	readFaifCSV scripts/data/sfls sfls
	refreshFaif

	bind pub - "!faif" [namespace current]::pub:faif
	bind pub - "!sfls" [namespace current]::pub:sfls
	bind pub - "!sflc" [namespace current]::pub:sfls
}

proc findFaif {dataset pattern} {
	if {[$dataset rows] == 0} {
		return {}
	} elseif {[string length $pattern] != 0} {
		set matching {}
		foreach col {1 4} {
			foreach pos [$dataset search -nocase -regexp column $col $pattern] {
				lappend matching [lindex $pos 1]
			}
		}
		return [lsort -unique $matching]
	} else {
		return {0}
	}
}

proc faifShowEntry {nick channel row} {
	say $nick $channel "[lindex $row 1] <[lindex $row 3]> published on [lindex $row 4]"
}

proc faifCommand {dataset nick channel arg} {
	if {[$dataset rows] == 0} {
		say $nick $channel "For some reason, my database is empty."
	} else {
		set matching [findFaif $dataset $arg]
		set n [llength $matching]
		if {$n} {
			for { set i 0 } { $i < $n && $i < 5 } { incr i } {
				faifShowEntry $nick $channel [$dataset get row [lindex $matching $i]]
			}
			if {$i != $n} {
				say $nick $channel "...and [expr $n - $i] more"
			}
		} else {
			say $nick $channel "Nothing found."
		}
	}
}

proc pub:faif {nick uhost handle channel arg} {
	faifCommand faif $nick $channel $arg
}

proc pub:sfls {nick uhost handle channel arg} {
	faifCommand sfls $nick $channel $arg
}


### Slackware

proc readFile {filename} {
	if {[catch {
		set fd [open $filename]
		set data [read $fd]
		close $fd
	} e]} {
		putlog "Error reading $filename: $e"
		return ""
	} else {
		return [string trim $data]
	}
}

proc refreshSlack {} {
	global slack_topic

	set slack [readFile scripts/data/slack]
	set kernel [readFile scripts/data/kernel]

	set slack_topic {}
	if { [string length $slack] } {
		lappend slack_topic "Slackware: $slack"
	}
	if { [string length $kernel] } {
		lappend slack_topic "Linux: $kernel"
	}
	set slack_topic [join $slack_topic "; "]
}

proc initSlack {} {
	global slack_topic
	set slack_topic ""
	refreshSlack
}


### Global

proc setTopic {nick channel topic} {
	set topic [string trim $topic]
	if {[llength $topic]} {
		set current [topic $channel]
		set new [string range $current [expr 1 + [string first "|" $current]] [string length $current]]
		set new "$topic | [string trim $new]"
		if {$new != $current} {
			putmode "PRIVMSG ChanServ :TOPIC $channel $new"
		}
		if {[llength $nick]} {
			say $nick $channel $topic
		}
	} elseif {[llength $nick]} {
		say $nick $channel "I don't have necessary data yet."
	}
}

proc pub:topic {nick uhost handle channel arg} {
	global faif_topic slack_topic
	if {$channel == "#faif"} {
		setTopic $nick $channel $faif_topic
	} elseif {$channel == "#slackware.pl"} {
		setTopic $nick $channel $slack_topic
	} else {
		say $nick $channel "I'm not sure what you want me to do."
	}
}

proc pub:help {nick uhost handle channel arg} {
	say $nick $channel "!google <query> -- perform Google query"
	if {![channel get $channel wiki]} {
		say $nick $channel "!wiki <query> -- perform Wikipedia query"
	}
	if {$channel == "#faif"} {
		say $nick $channel "!faif [<query>] -- look for an episode of Free as in Freedom or get the most recent"
		say $nick $channel "!sfls [<query>] -- look for an episode of Software Freedom Law Show or get the most recent"
		say $nick $channel "!topic -- refresh topic"
	} elseif {$channel == "#slackware.pl"} {
		say $nick $channel "!topic -- refresh topic"
		say $nick $channel "Logs are at http://tarball.mina86.com/"
	} elseif {$channel == "#sprc"} {
		say $nick $channel "Logs are at http://tarball.mina86.com/"
	}
}

proc pub:refresh {nick uhost handle channel arg} {
	if [catch { refresh } e] {
		puthelp "PRIVMSG $nick :There was an error doing a refresh: $e"
	} else {
		puthelp "PRIVMSG $nick :Refresh finished"
	}
}

proc refresh {} {
	global faif_topic slack_topic
	putlog "tarball: Refreshing"
	catch { refreshFaif }
	catch { refreshSlack }
	catch { setTopic {} "#faif" $faif_topic }
	catch { setTopic {} "#slackware.pl" $slack_topic }
}

proc timer {min hour day month year} {
	refresh
}

proc initGlobal {} {
	bind pub - "!topic"   [namespace current]::pub:topic
	bind pub - "!help"    [namespace current]::pub:help
	bind pub n "!refresh" [namespace current]::pub:refresh
	bind time - {?2 *}    [namespace current]::timer
	bind time - {?7 *}    [namespace current]::timer
}


### Main

initFaif
initSlack
initGlobal


}
