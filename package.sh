#!/bin/bash

### enable toolchain
. ~/koxtoolchain/refs/x-compile.sh khf env

### Build dropbear, sftp-server and xzdec
make -j${grep -c '^processor' /proc/cpuinfo} multi

### Create out folder
mkdir -p out

mkdir -p build/mntus_package
cp -r extension/extensions build/mntus_package
cp -r extension/usbnetlite build/mntus_package
mv build/dropbearmulti build/mntus_package/usbnetlite/bin
mv build/sftp-server build/mntus_package/usbnetlite/bin

mv build/xzdec out


# http://svn.ak-team.com/svn/Configs/trunk/Kindle/Touch_Hacks/Common/lib/libotautils5