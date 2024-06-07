#!/bin/sh
#
# USBNetwork installer
#
# $Id: install.sh 18668 2021-08-03 18:37:41Z NiLuJe $
#
##

HACKNAME="usbnetlite"

# Pull libOTAUtils for logging & progress handling
[ -f ./libotautils5 ] && source ./libotautils5


HACKVER="0.1.M"

# Directories
USBNET_BASEDIR="/mnt/us/usbnetlite"
USBNET_BINDIR="${USBNET_BASEDIR}/bin"
USBNET_SBINDIR="${USBNET_BASEDIR}/sbin"
USBNET_LIBEDIR="${USBNET_BASEDIR}/libexec"
USBNET_LIBDIR="${USBNET_BASEDIR}/lib"

USBNET_LOG="${USBNET_BASEDIR}/usbnetwork_install.log"

KINDLE_TESTDIR="/usr/local/bin"
KINDLE_USBNETBIN="${KINDLE_TESTDIR}/usbnetwork.sh"
USBNET_USBNETBIN="${USBNET_BINDIR}/usbnetwork.sh"

# Result codes
OK=0
ERR=${OK}

otautils_update_progressbar

# Install our hack's custom content
# But keep the user's custom content...
if [ -d /mnt/us/${HACKNAME} ] ; then
    logmsg "I" "install" "" "our custom directory already exists, checking if we have custom content to preserve"
    # Custom IP config
    if [ -f /mnt/us/${HACKNAME}/etc/config ] ; then
        cfg_expected_md5="ea5d57ffaa30e34c9232a54523f95163"
        cfg_current_md5=$( md5sum /mnt/us/${HACKNAME}/etc/config | awk '{ print $1; }' )
        cfg_md5_match="false"
        for cur_exp_md5 in ${cfg_expected_md5} ; do
            if [ "${cfg_current_md5}" == "${cur_exp_md5}" ] ; then
                cfg_md5_match="true"
            fi
        done
        if [ "${cfg_md5_match}" != "true" ] ; then
            HACK_EXCLUDE="${HACKNAME}/etc/config"
            logmsg "I" "install" "" "found custom ip config, excluding from archive"
        fi
   fi
fi

otautils_update_progressbar

# Okay, now we can extract it. Since busybox's tar is very limited, we have to use a tmp directory to perform our filtering
logmsg "I" "install" "" "installing custom directory"
# Make sure our xzdec binary is executable first...
chmod +x ./xzdec
./xzdec ${HACKNAME}.tar.xz | tar -xvf -
# Do check if that went well
_RET=$?
if [ ${_RET} -ne 0 ] ; then
    logmsg "C" "install" "code=${_RET}" "failed to extract custom directory in tmp location"
    return 1
fi

otautils_update_progressbar

cd src
# Make a copy of the default config...
cp -f usbnetlite/etc/config usbnetlite/etc/config.default
# And now we filter the content to preserve user's custom content
for custom_file in ${HACK_EXCLUDE} ; do
    if [ -f "./${custom_file}" ] ; then
        logmsg "I" "install" "" "preserving custom content (${custom_file})"
        rm -f "./${custom_file}"
    fi
done
# Finally, unleash our filtered dir on the live userstore
cp -af . /mnt/us/
_RET=$?
if [ ${_RET} -ne 0 ] ; then
    logmsg "C" "install" "code=${_RET}" "failure to update userstore with custom directory"
    return 1
fi
cd - >/dev/null
rm -rf src

otautils_update_progressbar

# Here we go
echo >> ${USBNET_LOG}
echo "usbnetwork v${HACKVER}, $( date )" >> ${USBNET_LOG}


otautils_update_progressbar

# Make sure our custom binaries are executable -- does this matter on fat32?
LIST="dropbearmulti usbnet-link usbnetwork libkh5 usbnetwork.sh sftp-server"
for var in ${LIST} ; do
    [ -x ${USBNET_BINDIR}/${var} ] || chmod +x ${USBNET_BINDIR}/${var} >> ${USBNET_LOG} 2>&1 || exit ${ERR}
done

otautils_update_progressbar

# Make sure the /usr/local/bin directory exists
logmsg "I" "install" "" "creating the ${KINDLE_TESTDIR} directory if need be"
[ -d ${KINDLE_TESTDIR} ] || mkdir -p ${KINDLE_TESTDIR} >> ${USBNET_LOG} 2>&1 || exit ${ERR}

otautils_update_progressbar

# Setup SSH server
logmsg "I" "install" "" "installing SSH server"
LIST="/usr/sbin/dropbearmulti /usr/bin/dropbear /usr/bin/dbclient /usr/bin/dropbearkey /usr/bin/dropbearconvert /usr/bin/dbscp"
for var in ${LIST} ; do
    if [ -L ${var} ] ; then
        echo "symbolic link ${var} -> $( readlink ${var} ) already exists, skipping..." >> ${USBNET_LOG}
    else
        if [ -x ${var} ] ; then
            echo "Binary ${var} already exists, skipping..." >> ${USBNET_LOG}
        else
            ln -fs ${USBNET_BINDIR}/dropbearmulti ${var} >> ${USBNET_LOG} 2>&1 || exit ${ERR}
        fi
    fi
done

otautils_update_progressbar

# Setup ;usbnetwork command script
logmsg "I" "install" "" "setting up usbnetwork command script"
# Save existing script in case it already exists
if [ -f ${KINDLE_USBNETBIN} ] ; then
    echo "${KINDLE_USBNETBIN} exists, saving..." >> ${USBNET_LOG}
    cp ${KINDLE_USBNETBIN} ${USBNET_USBNETBIN}-save.${HACKVER} >> ${USBNET_LOG} 2>&1 || exit ${ERR}
    rm -f ${KINDLE_USBNETBIN} >> ${USBNET_LOG} 2>&1 || exit ${ERR}
fi

# Copy our own script
cp -f ${USBNET_USBNETBIN} ${KINDLE_USBNETBIN} >> ${USBNET_LOG} 2>&1 || exit ${ERR}
chmod 0755 ${KINDLE_USBNETBIN} >> ${USBNET_LOG} 2>&1 || exit ${ERR}

otautils_update_progressbar

# Setup mac tweaks companion startup script
logmsg "I" "install" "" "installing preinit upstart job"
cp -f ${HACKNAME}-preinit.conf /etc/upstart/${HACKNAME}-preinit.conf >> ${USBNET_LOG} 2>&1 || exit ${ERR}

otautils_update_progressbar

# Setup auto USB network startup script
logmsg "I" "install" "" "installing upstart job"
cp -f ${HACKNAME}.conf /etc/upstart/${HACKNAME}.conf >> ${USBNET_LOG} 2>&1 || exit ${ERR}

otautils_update_progressbar

logmsg "I" "install" "" "cleaning up"
rm -f ${HACKNAME}-preinit.conf ${HACKNAME}.conf ${HACKNAME}.tar.xz xzdec

otautils_update_progressbar

echo "Done!" >> ${USBNET_LOG}
logmsg "I" "install" "" "done"

otautils_update_progressbar

return ${OK}
