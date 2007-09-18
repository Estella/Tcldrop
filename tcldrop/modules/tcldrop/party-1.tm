# party.tcl --
#	Handles:
#		* This module provides the core partyline support.
#
# $Id: partyline.tcl,v 1.6 2005/05/19 03:55:42 fireegl Exp $
#
# Copyright (C) 2003,2004,2005 FireEgl (Philip Moore) <FireEgl@Tcldrop.Org>
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
# The author of this project can be reached at FireEgl@Tcldrop.Org
# Or can be found on IRC (EFNet or FreeNode) as FireEgl.
#
#	partyline module for tcldrop.  (REQUIRED)

namespace eval ::tcldrop::party {
	variable name {party}
	variable version {0.1}
	variable script [info script]
	regexp -- {^[_[:alpha:]][:_[:alnum:]]*-([[:digit:]].*)[.]tm$} [file tail $script] -> version
	package provide tcldrop::$name $version
	package provide tcldrop::${name}::main $version
	package provide tcldrop::partyline $version
	variable depends {console bots core::users core::dcc core::conn core}
	variable author {Tcldrop-Dev}
	variable description {Core partyline support.}
	variable commands [list callparty getparty setparty party whom dccbroadcast dccputchan getdccaway setdccaway whomlist callchjn callchpt callaway callchat callact callbcst]
	variable rcsid {$Id$}
	# This makes sure we're loading from a tcldrop environment:
	if {![info exists ::tcldrop]} { return }
	# Export all the commands that should be available to 3rd-party scripters:
	namespace export {*}$commands
}


# FixMe: When a bot unlinks, we should remove anything we know about the users on that bot from the Users array.
#    (25) DISC (stackable)
#         bind disc <flags> <mask> <proc>
#         proc-name <botname>
#
#         Description: triggered when a bot disconnects from the botnet for
#           whatever reason. Just like the link bind, flags are ignored; mask
#           is matched against the botnetnick of the bot that unlinked.
#           Wildcards are supported in mask.
#         Module: core
bind disc - * ::tcldrop::party::DISC -priority -1000
proc ::tcldrop::party::DISC {bot {reason {Unlinked.}}} {
	callparty quit *:*@$bot line $reason
	callparty disc $bot line $reason
}

bind link - * ::tcldrop::party::LINK -priority -1000
proc ::tcldrop::party::LINK {bot via} {
	callparty link $bot handle $bot bot $bot via $via
}

bind chon - * ::tcldrop::party::CHON -priority 0
proc ::tcldrop::party::CHON {handle idx} {
	if {[set chan [getchan $idx]] != -1} {
		callparty connect ${idx}:${handle}@${::botnet-nick} idx $idx handle $handle bot ${::botnet-nick} chan $chan line {Join.}
	}
}

bind chof - * ::tcldrop::party::CHOF -priority 0
proc ::tcldrop::party::CHOF {handle idx} {
	if {[set chan [getchan $idx]] != -1} {
		callparty disconnect ${idx}:${handle}@${::botnet-nick} idx $idx handle $handle bot ${::botnet-nick} chan $chan line {Join.}
	}
}


#  whom <chan>
#    Returns: list of people on the botnet who are on that channel. 0 is
#      the default party line. Each item in the list is a sublist with six
#      elements: nickname, bot, hostname, access flag ('-', '@', '+', or
#      '*'), minutes idle, and away message (blank if the user is not away).
#      If you specify * for channel, every user on the botnet is returned
#      with an extra argument indicating the channel the user is on.
#    Module: core
# {FireEgl KEEEEEEEL Proteus-D@adsl-220-213-190.bhm.bellsouth.net * 0 {zzz . . .}}
proc ::tcldrop::party::whom {{chan {*}} {usermask {*:*@*}}} {
	global party_users
	set list [list]
	foreach u [array names party_users $usermask] {
		array set userinfo $party_users($u)
		if {[string match -nocase $chan $userinfo(chan)]} {
			lappend list [list $userinfo(handle) $userinfo(bot) $userinfo(userhost) $userinfo(flag) $userinfo(chan) $userinfo(idletime) $userinfo(away)]
		}
		array unset userinfo
	}
	return $list
}

proc ::tcldrop::party::whomlist {{chan {*}} {usermask {*:*@*}}} {
	global party_users
	set list [list]
	foreach u [array names party_users $usermask] {
		array set userinfo $party_users($u)
		if {[string match -nocase $chan $userinfo(chan)]} {
			lappend list $u $party_users($u)
		}
		array unset userinfo
	}
	return $list
}

#  dccbroadcast <message>
#    Description: sends a message to everyone on the party line across the
#      botnet, in the form of "*** <message>" for local users and
#      "*** (Bot) <message>" for users on other bots
#    Returns: nothing
#    Module: core
proc ::tcldrop::party::dccbroadcast {message} { callparty broadcast ${::botnet-nick} line $message }

#  dccputchan <channel> <message>
#    Description: sends your message to everyone on a certain channel on the
#      botnet, in a form exactly like dccbroadcast does. Valid channels are 0
#      through 99999.
#    Returns: nothing
#    Module: core
proc ::tcldrop::party::dccputchan {channel message} { callparty chat ${::botnet-nick} chan $channel line $message }

#  boot <user@bot> [reason]
#     Description: Sends a request to boot a user from the partyline.
#     Returns: nothing
#     Module: core

#  getdccaway <idx>
#    Returns: away message for a dcc chat user (or "" if the user is not
#      set away)
#    Module: core
proc ::tcldrop::party::getdccaway {idx} {
	foreach u [array names ::party_users [string tolower ${idx}:*@${::botnet-nick}]] {
		array set userinfo $::party_users($u)
		if {[info exists userinfo(away)] && $userinfo(away) != {}} { return $userinfo(away) }
		array unset userinfo
	}
}

#  setdccaway <idx> <message>
#    Description: sets a party line user's away message and marks them away.
#     If set to "", the user is marked as no longer away.
#    Returns: nothing
#    Module: core
proc ::tcldrop::party::setdccaway {idx text} { callparty away ${idx}:*@${::botnet-nick} line $text }

proc ::tcldrop::party::callparty {command usermask args} { CallParty $command $usermask $args }
proc ::tcldrop::party::CallParty {command usermask arguments} {
	global party_users
	foreach u [array names party_users [string tolower $usermask]] {
		array set userinfo [list command $command line {} idx 0 handle {} bot {} flag {} chan 0 userhost {Uknown@Uknown} chans [list] source {}]
		array set userinfo $party_users($u)
		array set userinfo $arguments
		set userinfo(idletime) [clock seconds]
		set party_users($u) [array get userinfo]
		foreach {type flags mask proc} [bindlist party] {
			if {[string match -nocase $mask $command]} {
				if {[catch { $proc $command $u $party_users($u) } err]} {
					putlog "error in script: $proc: $err"
					puterrlog "$::errorInfo"
				}
				countbind $type $mask $proc
			}
		}
		# Do special things for each command, mainly call the Eggdrop-style partyline binds:
		switch -- $command {
			{join} - {chjn} {
				callchjn $userinfo(bot) $userinfo(handle) $userinfo(chan) $userinfo(flag) $userinfo(idx) $userinfo(userhost)
			}
			{part} - {chpt} {
				callchpt $userinfo(bot) $userinfo(handle) $userinfo(idx) $userinfo(chan) $userinfo(line)
			}
			{quit} - {disconnect} - {sign} {
				callchpt $userinfo(bot) $userinfo(handle) $userinfo(idx) $userinfo(chan) $userinfo(line)
				unset party_users($u)
			}
			{chat} {
				callchat $userinfo(handle) $userinfo(chan) $userinfo(line)
			}
			{action} - {act} {
				callact $userinfo(handle) $userinfo(chan) $userinfo(line)
			}
			{away} {
				callaway $userinfo(bot) $userinfo(idx) $userinfo(line)
			}
			{broadcast} - {bcst} {
				callbcst $userinfo(bot) $userinfo(line)
			}
		}
		array unset userinfo
	}
}

# Makes changes to the ::partyline array.
proc ::tcldrop::party::party {command usermask args} {
	switch -- $command {
		{add} {
			array set userinfo [list command $command line {} idx 0 handle {} bot {} flag {} chan 0 userhost $usermask chans [list] source {} idletime [clock seconds]]
			array set userinfo $args
			set ::party_users($usermask) [array get userinfo]
		}
		{set} {
		}
		{unset} {
		}
		{delete} - {remove} - {quit} - {sign} - {disconnect} {
			after idle [list unset -nocomplain ::party_users($usermask)]
		}
		{get} { }
		{info} { }
		{default} { }
	}
	CallParty $command $usermask $args
}

# Sets partyline related info about a chan/user/chanuser ($type).
# $what is $idx:$handle@$botnet-nick for the "user" type..
# $what will be an integer for a "chan" type.  (Eggdrop only supports integers)  The assoc module will be used to convert the int to a channel name if needed.
# $what will be <integer>,<$idx:$handle@$botnet-nick> for a "chanuser" type.
proc ::tcldrop::party::setparty {type what args} {
	foreach u [array names ::party_users $idx:*@*] {
	}
}

proc ::tcldrop::party::getparty {type what args} {

}


bind chon - * ::tcldrop::party::CHON
proc ::tcldrop::party::CHON {handle idx} {
	party add ${idx}:${handle}@${::botnet-nick} idx $idx handle $handle bot ${::botnet-nick}
}


# The following are Eggdrop partyline binds,
# they should not be used by any of Tcldrop's modules,
# instead, the "party" bind should be used.

#    (35) CHJN (stackable)
#         bind chjn <flags> <mask> <proc>
#         proc-name <botname> <handle> <channel#> <flag> <idx> <user@host>
#
#         Description: when someone joins a botnet channel, it invokes this
#           binding. The mask is matched against the channel and can contain
#           wildcards. flag is one of: * (owner), + (master), @ (op), or %
#           (botnet master).
#         Module: core
# CHJN: Stupito FireEgl 0 * 9 Proteus-D@adsl-220-213-190.bhm.bellsouth.net
proc ::tcldrop::party::callchjn {bot handle chan flag idx userhost args} {
	foreach {type flags mask proc} [bindlist chjn] {
		if {[string match -nocase $mask $chan]} {
			if {[catch { $proc $bot $handle $chan $flag $idx $userhost } err]} {
				putlog "error in script: $proc: $err"
				puterrlog "$::errorInfo"
			} else {
				countbind $type $mask $proc
			}
		}
	}
}

#    (36) CHPT (stackable)
#         bind chpt <flags> <mask> <proc>
#         proc-name <botname> <handle> <idx> <channel#>
#
#         Description: when someone parts a botnet channel, it invokes this
#           binding. flags are ignored; the mask is matched against the
#           channel and can contain wildcards.
#         Module: core
proc ::tcldrop::party::callchpt {bot handle idx {chan {}} {reason {}}} {
	foreach {type flags mask proc} [bindlist chpt] {
		if {[string match -nocase $mask $chan]} {
			if {[llength [info args $proc]] >= 5} {
				if {[catch { $proc $bot $handle $idx $chan $reason } err]} {
					putlog "error in script: $proc: $err"
					puterrlog "$::errorInfo"
				} else {
					countbind $type $mask $proc
				}
			} else {
				if {[catch { $proc $bot $handle $idx $chan } err]} {
					putlog "error in script: $proc: $err"
					puterrlog "$::errorInfo"
				} else {
					countbind $type $mask $proc
				}
			}
		}
	}
}

#    (38) AWAY (stackable)
#         bind away <flags> <mask> <proc>
#         proc-name <botname> <idx> <text>
#
#         Description: triggers when a user goes away or comes back on the
#           botnet. text is the reason than has been specified (text is ""
#           when returning). mask is matched against the botnet-nick of the
#           bot the user is connected to and supports wildcards. flags are
#           ignored.
#         Module: core
proc ::tcldrop::party::callaway {bot idx {text {}}} {
	foreach {type flags mask proc} [bindlist away] {
		if {[string match -nocase $mask $bot]} {
			if {[catch { $proc $bot $idx $text } err]} {
				putlog "error in script: $proc: $err"
				puterrlog "$::errorInfo"
			} else {
				countbind $type $mask $proc
			}
		}
	}
}

#    (23) CHAT (stackable)
#         bind chat <flags> <mask> <proc>
#         proc-name <handle> <channel#> <text>
#
#         Description: when someone says something on the botnet, it invokes
#           this binding. Flags are ignored; handle could be a user on this
#           bot ("DronePup") or on another bot ("Eden@Wilde") and therefore
#           you can't rely on a local user record. The mask is checked against
#           the entire line of text and supports wildcards.
#         Module: core
proc ::tcldrop::party::callchat {handle chan text} {
	foreach {type flags mask proc} [bindlist chat] {
		if {[string match -nocase $mask $text]} {
			if {[catch { $proc $handle $chan $text } err]} {
				putlog "error in script: $proc: $err"
				puterrlog "$::errorInfo"
			} else {
				countbind $type $mask $proc
			}
		}
	}
}

#    (32) ACT (stackable)
#         bind act <flags> <mask> <proc>
#         proc-name <handle> <channel#> <action>
#
#         Description: when someone does an action on the botnet, it invokes
#           this binding. flags are ignored; the mask is matched against the
#           text of the action and can support wildcards.
#         Module: core
proc ::tcldrop::party::callact {handle chan text} {
	foreach {type flags mask proc} [bindlist act] {
		if {[string match -nocase $mask $text]} {
			if {[catch { $proc $handle $chan $text } err]} {
				putlog "error in script: $proc: $err"
				puterrlog "$::errorInfo"
			} else {
				countbind $type $mask $proc
			}
		}
	}
}

#    (34) BCST (stackable)
#         bind bcst <flags> <mask> <proc>
#         proc-name <botname> <text>
#
#         Description: when a bot broadcasts something on the botnet (see
#           'dccbroadcast' above), it invokes this binding. flags are ignored;
#           the mask is matched against the message text and can contain
#           wildcards.
#         Module: core
proc ::tcldrop::party::callbcst {bot text} {
	foreach {type flags mask proc} [bindlist bcst] {
		if {[string match -nocase $mask $text]} {
			if {[catch { $proc $bot $text } err]} {
				putlog "error in script: $proc: $err"
				puterrlog "$::errorInfo"
			} else {
				countbind $type $mask $proc
			}
		}
	}
}

proc ::tcldrop::party::LOG {levels channel text} {
	global party_users idxlist botnet-nick
	foreach u [array names party_users "*:*@${botnet-nick}"] {
		array set userinfo $party_users($u)
		if {[info exists idxlist($userinfo(idx))]} {
			array set userinfo $idxlist($userinfo(idx))
			if {[info exists userinfo(console-channel)] && ([string match -nocase $channel $userinfo(console-channel)] || [string match -nocase $userinfo(console-channel) $channel]) && [info exists userinfo(console-levels)] && [checkflags $levels $userinfo(console-levels)]} {
				putdcc $userinfo(idx) $text
			}
			array unset userinfo
		} else {
			# FixMe: This is the wrong place for this:
			callparty quit $u
		}
	}
}

bind load - party ::tcldrop::party::LOAD -priority 0
proc ::tcldrop::party::LOAD {module} {
	# This variable will store all the users who are on the partyline, each array name is in the form: 14:FireEgl@Botname
	setdefault party_users {} -array 1 -protect 1
	setdefault party_chans {} -array 1 -protect 1
	setdefault party_chanusers {} -array 1 -protect 1
}

bind evnt - loaded ::tcldrop::party::EVNT_loaded -priority 0
proc ::tcldrop::party::EVNT_loaded {event} {
	bind log - * ::tcldrop::party::LOG
}

bind unld - party ::tcldrop::party::UNLD -priority 0
proc ::tcldrop::party::UNLD {module} {
	return 1
}