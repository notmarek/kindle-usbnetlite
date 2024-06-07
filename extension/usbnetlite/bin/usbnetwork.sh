#!/bin/sh
#
# ;usbnetwork command script
#
# $Id: usbnetwork.sh 11150 2014-11-23 20:44:26Z NiLuJe $
#
##

USBNETLITE_BASEDIR="/mnt/us/usbnetlite"
USBNETLITE_BINDIR="${USBNETLITE_BASEDIR}/bin"
USBNETLITE_SCRIPT="${USBNETLITE_BINDIR}/usbnetwork"

# If we're an unprivileged user, try to remedy that...
if [ "$(id -u)" -ne 0 -a -x "/var/local/mkk/gandalf" ] ; then
	exec /var/local/mkk/su -s /bin/ash -c ${USBNETLITE_SCRIPT}
else
	exec ${USBNETLITE_SCRIPT}
fi

return 0
