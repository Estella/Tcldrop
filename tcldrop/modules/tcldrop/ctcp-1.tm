# ctcp/ctcp --
#	Handles:
#		* Provides responses to CTCPs on IRC.
#	Depends: irc.
#
# $Id$
#
# Copyright (C) 2003,2004,2005,2006,2007,2008,2009 Tcldrop Development Team <Tcldrop-Dev@Tcldrop.US>
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program (see gpl.txt); if not, write to the
# Free Software Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.
# Or visit http://www.GNU.Org/licenses/gpl.html
#
# The author of this project can be reached at FireEgl@Tcldrop.US
# Or can be found on IRC (EFNet or FreeNode) as FireEgl.

# This runs all the CTCP binds:
# (They should return 0 if they want tcldrop to continue processing, 1 if not.)

namespace eval ::tcldrop::ctcp {
	variable version {0.1}
	variable script [info script]
	regexp -- {^[_[:alpha:]][:_[:alnum:]]*-([[:digit:]].*)[.]tm$} [file tail $script] -> version
	variable name {ctcp}
	package provide tcldrop::$name $version
	package provide tcldrop::${name}::main $version
	if {![info exists ::tcldrop]} { return }
	variable depends {server irc core::users core}
	variable author {Tcldrop-Dev}
	variable description {Provides responses to CTCPs on IRC.}
	variable commands [list callctcp callctcr callctcps ctcr]
	variable rcsid {$Id$}
	namespace path [list ::tcldrop]
	checkmodule irc
	# Export all the commands that should be available to 3rd-party scripters:
	namespace export {*}$commands
}

proc ::tcldrop::ctcp::callctcp {nick uhost handle dest keyword {text {}}} {
	if {!${::lowercase-ctcp} && [string is lower $keyword]} { return -1 }
	switch -- ${::ctcp-mode} {
		{0} { set allow 1 }
		{1} { set allow [matchattr $handle o] }
		{2} { if {[detectflood ${::flood-ctcp} ctcp $uhost]} { set allow 0 } else { set allow 1 } }
		{-1} - {default} { set allow 0 }
	}
	if {$allow} {
		foreach {type flags mask proc} [bindlist ctcp] {
			# FixMe: If $dest is a channel, make it do a matchattr for that channel.
			#        It needs to distinguish between personal and channel CTCPs anyway.
			if {[bindmatch $mask $keyword] && [matchattr $handle $flags]} {
				if {[catch { $proc $nick $uhost $handle $dest $keyword $text } err]} {
					putlog "[mc {Error in script}]: $proc: $err"
					puterrlog "$::errorInfo"
				} elseif {![string equal {0} $err] || [string equal {1} $err]} {
					break
				}
				countbind $type $mask $proc
			}
		}
	}
}

# Similar to callctcp, this command handles multiple (stacked) CTCPs in $text:
# Example of "stacked" CTCPs: \001VERSION\001\001FINGER\001
proc ::tcldrop::ctcp::callctcps {nick uhost handle dest text} {
	variable CTCRs {}
	foreach {c c} [regexp -all -inline -- {\001(.*)*?\001} $text] {
		callctcp $nick $uhost $handle $dest [lindex [split [string trim $c]] 0] [join [lrange [split [string trim $c]] 1 end]]
		if {[isbotnick $dest]} { set consoledest {-} } else { set consoledest $dest }
		putloglev m $consoledest "CTCP [lindex [split [string trim $c]] 0] [join [lrange [split [string trim $c]] 1 end]] from $nick (${uhost})"
		if {[incr Count] >= ${::answer-ctcp}} { break }
	}
	# binds that used the ctcr command to stack the replies will have the replies in $CTCRs, so we send them here:
	if {$CTCRs ne {}} {
		puthelp "NOTICE $nick :$CTCRs"
		unset CTCRs
	}
}

# CTCP binds can use this command to "stack" the CTCRs (replies).
proc ::tcldrop::ctcp::ctcr {text} {
	variable CTCRs
	if {[info exists CTCRs]} {
		append CTCRs "\001$text\001"
	} else {
		return -code error "[mc {Calling the ctcr command outside of a CTCP bind is not allowed.}]"
	}
}

proc ::tcldrop::ctcp::callctcr {nick uhost handle dest keyword {text {}}} {
	if {!${::lowercase-ctcp} && [string is lower $keyword]} { return -1 }
	foreach {type flags mask proc} [bindlist ctcr] {
		# FixMe: If $dest is a channel, make it do a matchattr for that channel.
		#        It needs to distinguish between personal and channel CTCPs anyway.
		if {[bindmatch $mask $keyword] && [matchattr $handle $flags]} {
			if {[catch { $proc $nick $uhost $handle $dest $keyword $text } err]} {
				putlog "[mc {Error in script}]: $proc: $err"
				puterrlog "$::errorInfo"
			} elseif {![string equal {0} $err] || [string equal {1} $err]} {
				break
			}
			countbind $type $mask $proc
		}
	}
}

proc ::tcldrop::ctcp::ctcp_PING {nick uhost handle dest keyword text} {
	ctcr "$keyword $text"
	return 1
}
proc ::tcldrop::ctcp::ctcp_VERSION {nick uhost handle dest keyword text} {
	ctcr "$keyword ${::ctcp-version}"
	return 1
}
proc ::tcldrop::ctcp::ctcp_FINGER {nick uhost handle dest keyword text} {
	ctcr "$keyword ${::ctcp-finger}"
	return 1
}
proc ::tcldrop::ctcp::ctcp_USERINFO {nick uhost handle dest keyword text} {
	ctcr "$keyword ${::ctcp-userinfo}"
	return 1
}
proc ::tcldrop::ctcp::ctcp_TIME {nick uhost handle dest keyword text} {
	ctcr "TIME [ctime [clock seconds]]"
	return 1
}

# Note: Eggdrop supports:
# CLIENTINFO SED VERSION CLIENTINFO USERINFO ERRMSG FINGER TIME ACTION DCC UTC PING ECHO  :Use CLIENTINFO <COMMAND> to get more specific information

bind load - ctcp ::tcldrop::ctcp::LOAD -priority 0
proc ::tcldrop::ctcp::LOAD {module} {
	# Set here how the ctcp module should answer ctcps. There are 3 possible
	# operating modes:
	#   0: Normal behavior is used.
	#   1: The bot ignores all ctcps, except for CHAT and PING requests
	#      by users with the +o flag.
	#   2: Normal behavior is used, however the bot will not answer more
	#      than X ctcps in Y seconds (defined by 'set flood-ctcp').
	setdefault ctcp-mode 0
	setdefault lowercase-ctcp 0
	setdefault ctcp-version "Tcldrop v$::tcldrop(version)"
	setdefault ctcp-finger "Tcldrop v$::tcldrop(version)"
	setdefault ctcp-userinfo "Tcldrop v$::tcldrop(version)"
	setdefault flood-ctcp 3:61
	setdefault answer-ctcp 1
	# FixMe: Add support for these settings:
	setdefault global-flood-ctcp 9:99
	bind ctcp - PING ::tcldrop::ctcp::ctcp_PING -priority 10000
	bind ctcp - TIME ::tcldrop::ctcp::ctcp_TIME -priority 10000
	bind ctcp - VERSION ::tcldrop::ctcp::ctcp_VERSION -priority 10000
	bind ctcp - FINGER ::tcldrop::ctcp::ctcp_FINGER -priority 10000
	bind ctcp - USERINFO ::tcldrop::ctcp::ctcp_USERINFO -priority 10000
	loadhelp ctcp.help
	loadhelp [file join set ctcp.help]
}

bind unld - ctcp ::tcldrop::ctcp::UNLD -priority 0
proc ::tcldrop::ctcp::UNLD {module} {
	# Need to unbind the ctcp binds, because we don't know if we'll LOAD again:
	unbind ctcp * * ::tcldrop::ctcp::*
	unloadhelp ctcp.help
	unloadhelp [file join set ctcp.help]
	return 0
}
