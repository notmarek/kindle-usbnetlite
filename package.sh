#!/bin/bash
HACKNAME="usbnetlite"
VERSION="1.0.M"
COMMIT=$(git rev-parse --short HEAD)
KT_PM_FLAGS=( "-xPackageName=${HACKNAME}" "-xPackageVersion=${VERSION}-r${COMMIT}" "-xPackageAuthor=Marek" "-xPackageMaintainer=Marek" "-X" )
### enable toolchain
. ~/koxtoolchain/refs/x-compile.sh khf env

### Build dropbear, sftp-server and xzdec
make -j$(grep -c '^processor' /proc/cpuinfo) multi

### Create out folder
mkdir -p out

mkdir -p build/mntus_package
cp -r extension/extensions build/mntus_package
cp -r extension/${HACKNAME} build/mntus_package
echo "USBNETLite ${VERSION}-r${COMMIT}" > build/mntus_package/${HACKNAME}/etc/VERSION

mv build/dropbearmulti build/mntus_package/${HACKNAME}/bin
mv build/sftp-server build/mntus_package/${HACKNAME}/bin
cp build/xzdec build/mntus_package/${HACKNAME}/bin # i guess you might want it for something :)

mv build/xzdec out
cp extension/install.sh out
cp extension/${HACKNAME}.conf out
cp extension/${HACKNAME}-preinit.conf out

wget https://svn.ak-team.com/svn/Configs/trunk/Kindle/Touch_Hacks/Common/lib/libotautils5 -O out/libotautils5

tar --hard-dereference --owner root --group root --exclude-vcs -cvf ./out/${HACKNAME}.tar ./build/mntus_package/${HACKNAME} ./build/mntus_package/extensions
xz ./out/${HACKNAME}.tar

cd out
chmod +x install.sh
kindletool create ota2 "${KT_PM_FLAGS[@]}" -d paperwhite4 -d basic3 -d oasis3 -d paperwhite5 -d basic4 -d scribe libotautils5 install.sh ${HACKNAME}.tar.xz xzdec ${HACKNAME}-preinit.conf ${HACKNAME}.conf Update_${HACKNAME}_${VERSION}_install_khf.bin
cd ..

mv out/Update_${HACKNAME}_${VERSION}_install_khf.bin .
rm -rf out 
mkdir -p out 
mv Update_${HACKNAME}_${VERSION}_install_khf.bin out