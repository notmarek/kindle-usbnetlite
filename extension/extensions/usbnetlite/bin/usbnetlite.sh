#!/bin/sh
#
# KUAL USBNetwork actions helper script
#
# $Id: usbnet.sh 19280 2023-10-30 23:59:04Z NiLuJe $
#
##

# Get hackname from the script's path (NOTE: Will only work for scripts called from /mnt/us/extensions/${KH_HACKNAME})
# KH_HACKNAME="${PWD##/mnt/us/extensions/}"
# fuck that 
KH_HACKNAME="usbnetlite"

# Try to pull our custom helper lib
libkh_fail="false"
# Handle both the K5 & legacy helper, so I don't have to maintain the exact same thing in two different places :P
for my_libkh in libkh5 libkh ; do
	_KH_FUNCS="/mnt/us/${KH_HACKNAME}/bin/${my_libkh}"
	if [ -f ${_KH_FUNCS} ] ; then
		. ${_KH_FUNCS}
		# Got it, go away!
		libkh_fail="false"
		break
	else
		libkh_fail="true"
	fi
done

if [ "${libkh_fail}" == "true" ] ; then
	# Pull default helper functions for logging
	_FUNCTIONS=/etc/rc.d/functions
	[ -f ${_FUNCTIONS} ] && . ${_FUNCTIONS}
	# We couldn't get our custom lib, abort
	msg "couldn't source libkh5 nor libkh from '${KH_HACKNAME}'" W
	exit 0
fi

# We need the proper privileges...
if [ "$(id -u)" -ne 0 ] ; then
	kh_msg "unprivileged user, aborting" E v
	exit 1
fi

## Enable a specific trigger file in the hack's basedir
# Arg 1 is exact config trigger file name
##
enable_hack_trigger_file()
{
	if [ $# -lt 1 ] ; then
		kh_msg "not enough arguments passed to enable_hack_trigger_file ($# while we need at least 1)" W v "missing trigger file name"
	fi

	kh_trigger_file="${KH_HACK_BASEDIR}/${1}"

	touch "${kh_trigger_file}"
}

## Remove a specific trigger file in the hack's basedir
# Arg 1 is exact config trigger file name
##
disable_hack_trigger_file()
{
	if [ $# -lt 1 ] ; then
		kh_msg "not enough arguments passed to disable_hack_trigger_file ($# while we need at least 1)" W v "missing trigger file name"
		return 1
	fi

	kh_trigger_file="${KH_HACK_BASEDIR}/${1}"

	rm -f "${kh_trigger_file}"
}

## Check if we're in USBMS mode
check_is_in_usbnet()
{
	if lsmod | grep -q g_ether ; then
		kh_msg "will not edit usbnet config file in usbnet mode, switch to usbms" W v "must be in usbms mode to safely do this"
		return 0
	fi

	# Avoid touching the config while SSHD is up in wifi only mode, too
	if [ "${USE_WIFI_SSHD_ONLY}" == "true" ] ; then
		if [ -f "${SSH_PID}" ] ; then
			kh_msg "will not edit usbnet config file while sshd is up, shut it down" W v "sshd must be down to safely do this"
			return 0
		fi
	fi

	# All good, we're in USBMS mode
	return 1
}

## Check the current USBNET status (in more details than check_is_in_usbnet ;)
check_usbnet_status()
{
	# Source the config to get the wifi only current status
	. "${KH_HACK_BASEDIR}/etc/config"

	if [ "${USE_WIFI_SSHD_ONLY}" == "true" ] ; then
		# Don't do anything fancier (like checking if the pid still exists), because the actual usbnetwork script doesnt ;).
		if [ -f "${SSH_PID}" ] ; then
			kh_msg "wifi only, sshd should be up" I q
			return 3
		else
			kh_msg "wifi only, sshd should be down" I q
			return 4
		fi
	else
		# We're not in wifi only mode, do it like check_is_in_usbnet
		if lsmod | grep -q g_ether ; then
			if [ -f "${SSH_PID}" ] ; then
				kh_msg "currently in usbnet mode, sshd should be up" I q
				return 5
			else
				kh_msg "currently in usbnet mode, but sshd appears to be down!" I q
				return 6
			fi
		else
			if [ -f "${SSH_PID}" ] ; then
				kh_msg "currently in usbms mode, but sshd appears to be up!" I q
				return 7
			else
				kh_msg "currently in usbms mode, sshd should be down" I q
				return 8
			fi
		fi
	fi

	# Huh. Unknown state, shouldn't happen.
	return 1
}

## Check if we're plugged in to something
check_is_plugged_in()
{
	# NOTE: On the KOA2, this is safe. It's so safe that it even helps avoid a kernel crash :D.
	#       Jokes aside, yes, see the relevant comments in usbnet_to_usbms @ usbnet/bin/usbnetwork
	# NOTE: Assume the KOA3 behaves the same, even if there's a chance the kernel has since been fixed...
	[ "${IS_KOA2}" == "true" -o "${IS_KOA3}" == "true" ] && return 1

	# Try to check if we're plugged in...
	is_plugged_in="false"
	# There's no kdb in FW 2.x...
	if [ -d "/etc/kdb" ] ; then
		# The file might not exist when unplugged, silence stderr to avoid flooding KUAL's log.
		if [ "$(cat $(kdb get system/driver/usb/SYS_CONNECTED) 2>/dev/null)" == "1" ] ; then
			is_plugged_in="true"
		fi
	else
		# NOTE: Seems to be more useful than lipc-get-prop -i -e -- com.lab126.powerd isCharging (accurate in USBMS mode)...
		# On the other hand, /sys/devices/platform/arc_udc/connected doesn't seem to be very useful...
		if [ "$(cat /sys/devices/platform/charger/charging 2>/dev/null)" == "1" ] ; then
			is_plugged_in="true"
		fi
	fi
	if [ "${is_plugged_in}" == "true" ] ; then
		kh_msg "will not toggle usbnet while plugged in, unplug your kindle" W v "must not be plugged in to safely do that"
		return 0
	fi

	# All good, (apparently) not plugged in to anything
	return 1
}

## Check if we're a WiFi device (!= K1/K2/DX/DXG)
check_is_wifi_device()
{
	[ "${IS_K1}" == "true" ] && return 1
	# DX & DXG are folded in IS_K2
	[ "${IS_K2}" == "true" ] && return 1

	# We are, all good :)
	return 0
}

## Check if we're a legacy device (< K4)
check_is_legacy_device()
{
	[ "${IS_K1}" == "true" ] && return 0
	[ "${IS_K2}" == "true" ] && return 0
	[ "${IS_K3}" == "true" ] && return 0

	# We're not, all good :)
	return 1
}

## Check if we're a Touch device (>= K5)
check_is_touch_device()
{
	[ "${IS_K5}" == "true" ] && return 0
	[ "${IS_TOUCH}" == "true" ] && return 0
	[ "${IS_PW}" == "true" ] && return 0
	[ "${IS_PW2}" == "true" ] && return 0
	[ "${IS_KV}" == "true" ] && return 0
	[ "${IS_KT2}" == "true" ] && return 0
	[ "${IS_PW3}" == "true" ] && return 0
	[ "${IS_KOA}" == "true" ] && return 0
	[ "${IS_KT3}" == "true" ] && return 0
	[ "${IS_KOA2}" == "true" ] && return 0
	[ "${IS_PW4}" == "true" ] && return 0
	[ "${IS_KT4}" == "true" ] && return 0
	[ "${IS_KOA3}" == "true" ] && return 0
	[ "${IS_PW5}" == "true" ] && return 0
	[ "${IS_KT5}" == "true" ] && return 0
	[ "${IS_KS}" == "true" ] && return 0

	# We're not, all good :)
	return 1
}

## Toggle a specific config switch in the hack's config
# Arg 1 is the exact name of the config switch (var name)
# Arg 2 is the value of the switch (true || false)
##
edit_hack_config()
{    
	if [ $# -lt 2 ] ; then
		kh_msg "not enough arguments passed to disable_hack_trigger_file ($# while we need at least 2)" W v "missing config switch and value"
		return 1
	fi

	# We do NOT want to edit the config file if we're not in USBMS mode, to avoid leaving the hack in an undefined state
	if check_is_in_usbnet ; then
		return 1
	fi

	kh_config_file="${KH_HACK_BASEDIR}/etc/config"

	kh_config_switch_name="${1}"
	kh_config_switch_value="${2}"
	# Sanitize user input
	if ! grep -q "${kh_config_switch_name}" "${kh_config_file}" ; then
		kh_msg "invalid config switch name (${kh_config_switch_name})" W v "invalid config switch"
		return 1
	fi

	# This is slightly overkill, the hack already discards the value if it's not true or false in lowercase...
	case "$kh_config_switch_value" in
		t* | y* | T* | Y* | 1 )
			kh_config_switch_value="true"
		;;
		f* | n* | F* | N* | 0 )
			kh_config_switch_value="false"
		;;
		* )
			kh_msg "invalid config switch value (${kh_config_switch_value})" W v "invalid config value"
			return 1
		;;
	esac

	# Do the deed...
	sed -r -e "s/^(${kh_config_switch_name})(=)([\"'])(.*?)([\"'])$/\1\2\3${kh_config_switch_value}\5/" -i "${kh_config_file}"
}

## Try to toggle USBNetwork
toggle_usbnet()
{
	# All kinds of weird stuff happens if we try to toggle USBNet while plugged in, so, well, don't do it ;)
	if check_is_plugged_in ; then
		return 1
	fi

	kh_msg "Toggle USBNetwork" I a
	${KH_HACK_BINDIR}/usbnetwork
	# NOTE: Send a blank kh_msg to avoid confusing users in verbose mode? That seem counterproductive...
}

## Print the current USBnetwork mode
usbnet_status()
{
	# Check...
	check_usbnet_status
	usbnet_status="$?"

	# Interpret it
	case "${usbnet_status}" in
		3 )
			kh_msg "* SSHD is up (usbms, wifi only) *" I v
		;;
		4 )
			kh_msg "* SSHD is down (usbms, wifi only) *" I v
		;;
		5 )
			kh_msg "* USBNetwork: enabled (usbnet, sshd up) *" I v
		;;
		6 )
			kh_msg "* USBNetwork: enabled (usbnet, sshd down?) *" I v
		;;
		7 )
			kh_msg "* USBNetwork: disabled (usbms, sshd up?) *" I v
		;;
		8 )
			kh_msg "* USBNetwork: disabled (usbms, sshd down) *" I v
		;;
		* )
			# Hu oh...
			kh_msg "* USBNetwork is broken? *" I v
		;;
	esac
}

## Enable SSH at boot
enable_auto()
{
	enable_hack_trigger_file "auto"
	# FIXME: Workaround broken? custom status message by using eips ourselves. Kill this once it works properly.
	kh_msg "Boot the Kindle in USBNet mode" I a
	# On legacy devices, prevent the device from shutting down when hitting the 'YKNR' screen, it might come in handy.
	# NOTE: On newer devices, we have RP+CRP instead ;).
	if ! check_is_touch_device ; then
		touch /mnt/us/DONT_HALT_ON_REPAIR
	fi
}

## Disable SSH at boot
disable_auto()
{
	disable_hack_trigger_file "auto"
	kh_msg "Boot the Kindle in USBMS mode" I a
}

## Enable verbose mode
enable_verbose()
{
	enable_hack_trigger_file "verbose"
	kh_msg "Make USBNetwork verbose" I a
}

## Disable verbose mode
disable_verbose()
{
	disable_hack_trigger_file "verbose"
	kh_msg "Make USBNetwork quiet" I a
}

## Enable complete uninstall flag
enable_uninstall()
{
	enable_hack_trigger_file "uninstall"
	kh_msg "Flag USBNetwork for complete uninstall" I a
}

## Disable complete uninstall flag
disable_uninstall()
{
	disable_hack_trigger_file "uninstall"
	kh_msg "Restore default USBNetwork uninstall behavior" I a
}

## Enable SSH over WiFi
enable_wifi()
{
	# NOTE: Extra safety, this is nonsensical on devices without a WiFi chip ;).
	if ! check_is_wifi_device ; then
		kh_msg "Not applicable to your device" W v
		return 1
	fi

	# Put the kh_msg before the edit, to be able to see the warnings in case of error
	kh_msg "Enable SSH over WiFi" I a

	# In my infinite wisdom, I changed the variable name in the K5 version...
	if check_is_touch_device ; then
		edit_hack_config "USE_WIFI" "true"
	else
		edit_hack_config "K3_WIFI" "true"
	fi
}

## Disable SSH over WiFi
disable_wifi()
{
	if ! check_is_wifi_device ; then
		kh_msg "Not applicable to your device" W v
		return 1
	fi

	kh_msg "Disable SSH over WiFi" I a

	if check_is_touch_device ; then
		edit_hack_config "USE_WIFI" "false"
	else
		edit_hack_config "K3_WIFI" "false"
	fi
}

## Enable SSHD only mode
enable_sshd_only()
{
	if ! check_is_wifi_device ; then
		kh_msg "Not applicable to your device" W v
		return 1
	fi

	kh_msg "Enable SSHD only over WiFi" I a

	if check_is_touch_device ; then
		edit_hack_config "USE_WIFI_SSHD_ONLY" "true"
	else
		edit_hack_config "K3_WIFI_SSHD_ONLY" "true"
	fi
}

## Disable SSHD only mode
disable_sshd_only()
{
	if ! check_is_wifi_device ; then
		kh_msg "Not applicable to your device" W v
		return 1
	fi

	kh_msg "Disable SSHD only over WiFi" I a

	if check_is_touch_device ; then
		edit_hack_config "USE_WIFI_SSHD_ONLY" "false"
	else
		edit_hack_config "K3_WIFI_SSHD_ONLY" "false"
	fi
}

## Move to OpenSSH
use_openssh()
{
	kh_msg "Switch to OpenSSH" I a
	edit_hack_config "USE_OPENSSH" "true"
}

## Move back to Dropbear
use_dropbear()
{
	kh_msg "Switch to DropBear" I a
	edit_hack_config "USE_OPENSSH" "false"
}

## Make dropbear quieter
quiet_dropbear()
{
	kh_msg "Don't let dropbear print the banner file" I a "Make dropbear quieter"
	edit_hack_config "QUIET_DROPBEAR" "true"
}

## Let dropbear print the banner
verbose_dropbear()
{
	kh_msg "Let dropbear print the banner file" I a
	edit_hack_config "QUIET_DROPBEAR" "false"
}

## Unique MAC addresses
tweak_mac()
{
	kh_msg "Use unique MAC addresses" I a
	edit_hack_config "TWEAK_MAC_ADDRESS" "true"
}

## Default MAC addresses
default_mac()
{
	kh_msg "Use default MAC addresses" I a
	edit_hack_config "TWEAK_MAC_ADDRESS" "false"
}

## Let volumd do the low-level heavy-lifting (default on K4, K5 & PW)
use_volumd()
{
	# NOTE: Extra safety, we *really* don't want to run this on anything other than a K2/3
	if ! check_is_legacy_device ; then
		kh_msg "Not supported on your device" W v
		return 1
	fi

	kh_msg "Use volumd" I a
	edit_hack_config "USE_VOLUMD" "true"
}

## Do the kernel module switch & if up ourselves (default on legacy devices)
dont_use_volumd()
{
	if ! check_is_legacy_device ; then
		kh_msg "Not supported on your device" W v
		return 1
	fi

	kh_msg "Do not use volumd" I a
	edit_hack_config "USE_VOLUMD" "false"
}

## Restore the default config file
restore_config()
{
	# Don't touch the config if we're in usbnet mode...
	if check_is_in_usbnet ; then
		return 1
	fi

	if [ -f "${USBNET_BASEDIR}/etc/config.default" ] ; then
		kh_msg "Restore default config file" I a
		cp -f "${USBNET_BASEDIR}/etc/config.default" "${USBNET_BASEDIR}/etc/config"
	else
		kh_msg "No default config file" W v
	fi
}

## Print the version of the hack currently installed
show_version()
{
	if [ -f "${KH_HACK_BASEDIR}/etc/VERSION" ] ; then
		kh_msg "$(cat ${KH_HACK_BASEDIR}/etc/VERSION)" I v
	else
		kh_msg "No version info file" W v
	fi
}

## Main
case "${1}" in
	"toggle_usbnet" )
		${1}
	;;
	"usbnet_status" )
		${1}
	;;
	"enable_auto" )
		${1}
	;;
	"disable_auto" )
		${1}
	;;
	"enable_wifi" )
		${1}
	;;
	"disable_wifi" )
		${1}
	;;
	"restore_config" )
		${1}
	;;
	"show_version" )
		${1}
	;;
	* )
		kh_msg "invalid action (${1})" W v "invalid action"
	;;
esac
