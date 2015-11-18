#!/bin/bash

set -e
#set -x

export LANGUAGE=en_US.UTF-8
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

SCRIPTNAME=$(basename "$0")
SCRIPTDIR=$(cd `dirname "$0"`; pwd)

################################################################################
## Need Packages

NEEDEDPACKAGES=""
#if [ -z `which debootstrap` ]; then NEEDEDPACKAGES+="debootstrap "; fi
if [ -n "${NEEDEDPACKAGES}" ]; then
	echo "Need ${NEEDEDPACKAGES}, installing them..."
	apt-get -qq -y install ${NEEDEDPACKAGES}
fi

################################################################################
## Need TEMPDIR

TEMPDIR=$(mktemp -d -t ${SCRIPTNAME}.XXXXXXXXXX)
LOCKFILE=${TEMPDIR}.lock
[ -f "${LOCKFILE}" ] && echo "ERROR ${LOCKFILE} already exist. !!!" && exit 255

################################################################################
## Need CleanUp

function clean_up() {
	
	echo "Clean up ..."
	
	rm -Rf "${TEMPDIR}"
	rm -f "${LOCKFILE}"
	
	trap "" SIGHUP SIGINT SIGTERM SIGQUIT EXIT
	if [ "$1" != "0" ]; then
		echo "ERROR ..."
		exit $1
	else
		#echo " -> Done ..."
		exit 0
	fi
}

function print_help() {
	echo "
${SCRIPTNAME}  version 0.1b
Copyright (C) 2015 by Simon Baur (sbausis at gmx dot net)

Usage: ${SCRIPTNAME} [OPTIONS]... -o [OUTFILE]

Options
 -o          set OUTFILE
"
}

function help_exit() {
	print_help
	clean_up 1
}

################################################################################

################################################################################
## Need LOCKFILE

trap "{ clean_up 255; }" SIGHUP SIGINT SIGTERM SIGQUIT EXIT
touch ${LOCKFILE}

################################################################################
## Need Arguments

OUTDIR=""
BUILDDIR=""
CACHEDIR=""
SOURCEDIR=""
FORCEBUILD=1
FORCEEXTRACT=1

while getopts ":O:B:C:S:fx" opt; do
	case $opt in
		O) OUTDIR="$OPTARG" ;;
		B) BUILDDIR="$OPTARG" ;;
		C) CACHEDIR="$OPTARG" ;;
		S) SOURCEDIR="$OPTARG" ;;
		f) FORCEBUILD=0 ;;
		x) FORCEEXTRACT=0 ;;
		\?) echo "Invalid option: -$OPTARG" >&2 && help_exit ;;
		:) echo "Option -$OPTARG requires an argument." >&2 && help_exit ;;
	esac
done

if [ -z "${OUTDIR}" ]; then
	OUTDIR="${SCRIPTDIR}"
fi

if [ -z "${BUILDDIR}" ]; then
	BUILDDIR="${OUTDIR}/.build"
fi

if [ -z "${CACHEDIR}" ]; then
	CACHEDIR="${OUTDIR}/.cache"
fi

if [ -z "${SOURCEDIR}" ]; then
	SOURCEDIR="${OUTDIR}/.source"
fi

if [ -z "${OUTDIR}" ] && [ -z "${BUILDDIR}" ] && [ -z "${CACHEDIR}" ] && [ -z "${SOURCEDIR}" ]; then
	help_exit
fi

################################################################################

echo "[ ${SCRIPTNAME} ] ${BUILDDIR} ${CACHEDIR} ${SOURCEDIR}"
STARTTIME=`date +%s`

if [ "$FORCEBUILD" == "0" ]; then
	[ -d "${CACHEDIR}/u-boot-sunxi" ] && rm -Rf ${CACHEDIR}/u-boot-sunxi
	[ -d "${SOURCEDIR}/u-boot-sunxi" ] && rm -Rf ${SOURCEDIR}/u-boot-sunxi
	[ -d "${BUILDDIR}/u-boot-sunxi" ] && rm -Rf ${BUILDDIR}/u-boot-sunxi
fi

if [ "$FORCEEXTRACT" == "0" ]; then
	[ -d "${SOURCEDIR}/u-boot-sunxi" ] && rm -Rf ${SOURCEDIR}/u-boot-sunxi
	[ -d "${BUILDDIR}/u-boot-sunxi" ] && rm -Rf ${BUILDDIR}/u-boot-sunxi
fi

if [ ! -f "${CACHEDIR}/u-boot-sunxi/u-boot-sunxi.src.tgz" ]; then
	
	git clone https://github.com/linux-sunxi/u-boot-sunxi.git ${TEMPDIR}/u-boot-sunxi
	tar -cz -C ${TEMPDIR} -f ${TEMPDIR}/u-boot-sunxi.src.tgz u-boot-sunxi
	
	[ -d "${CACHEDIR}/u-boot-sunxi" ] && rm -Rf ${CACHEDIR}/u-boot-sunxi
	[ -d "${SOURCEDIR}/u-boot-sunxi" ] && rm -Rf ${SOURCEDIR}/u-boot-sunxi
	[ -d "${BUILDDIR}/u-boot-sunxi" ] && rm -Rf ${BUILDDIR}/u-boot-sunxi
	
	mkdir -p ${CACHEDIR}/u-boot-sunxi
	mv -f ${TEMPDIR}/u-boot-sunxi.src.tgz ${CACHEDIR}/u-boot-sunxi/u-boot-sunxi.src.tgz
	
	mkdir -p ${SOURCEDIR}/u-boot-sunxi
	mv -f ${TEMPDIR}/u-boot-sunxi/* ${SOURCEDIR}/u-boot-sunxi/
	
fi

if [ ! -d "${SOURCEDIR}/u-boot-sunxi" ]; then
	
	tar -xz -C ${SOURCEDIR} -f ${CACHEDIR}/u-boot-sunxi/u-boot-sunxi.src.tgz
	
	[ -d "${BUILDDIR}/u-boot-sunxi" ] && rm -Rf ${BUILDDIR}/u-boot-sunxi
	
fi

if [ ! -f "${BUILDDIR}/u-boot-sunxi/u-boot-sunxi-with-spl.bin" ]; then
	
	cd ${SOURCEDIR}/u-boot-sunxi
	
	make -j1 -s ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- clean
	make -j1 Bananapro_defconfig CROSS_COMPILE=arm-linux-gnueabihf-
	
	touch .scmversion
	
	[ -f .config ] && sed -i 's/CONFIG_LOCALVERSION=""/CONFIG_LOCALVERSION="-armbian"/g' .config
	[ -f .config ] && sed -i 's/CONFIG_LOCALVERSION_AUTO=.*/# CONFIG_LOCALVERSION_AUTO is not set/g' .config
	
	if [ "$(cat .config | grep CONFIG_ARMV7_BOOT_SEC_DEFAULT=y)" == "" ]; then
		echo "CONFIG_ARMV7_BOOT_SEC_DEFAULT=y" >> .config
		echo "CONFIG_OLD_SUNXI_KERNEL_COMPAT=y" >> .config
	fi
	
	make -j5 CROSS_COMPILE=arm-linux-gnueabihf-
	
	mkdir -p ${BUILDDIR}/u-boot-sunxi
	cp -f u-boot-sunxi-with-spl.bin ${BUILDDIR}/u-boot-sunxi/u-boot-sunxi-with-spl.bin
	
fi

VERSION=$(cd ${SOURCEDIR}/u-boot-sunxi && make -s ubootversion)
DEBFOLDER="linux-u-boot-sun7i"
DEBNAME="${DEBFOLDER}_${VERSION}_armhf"
if [ ! -f "${BUILDDIR}/u-boot-sunxi/${DEBNAME}.deb" ]; then
	
	mkdir -p ${TEMPDIR}/${DEBFOLDER}/DEBIAN
	mkdir -p ${TEMPDIR}/${DEBFOLDER}/usr/lib/${DEBNAME}
	
	cat <<EOF > ${TEMPDIR}/${DEBFOLDER}/DEBIAN/postinst
#!/bin/bash
set -e
if [[ \$DEVICE == "" ]]; then DEVICE="/dev/mmcblk0"; fi
( dd if=/usr/lib/${DEBNAME}/u-boot-sunxi-with-spl.bin of=\$DEVICE bs=1024 seek=8 status=noxfer ) > /dev/null 2>&1	
exit 0
EOF
	chmod 755 ${TEMPDIR}/${DEBFOLDER}/DEBIAN/postinst
	
	cat <<EOF > ${TEMPDIR}/${DEBFOLDER}/DEBIAN/control
Package: ${DEBFOLDER}
Version: ${VERSION}
Architecture: armhf
Maintainer: Simon Pascal Baur <sbausis@gmx.net>
Installed-Size: 1
Section: kernel
Priority: optional
Description: Das U-Boot ${VERSION} for sun7i Platform
EOF
	
	cp -f ${BUILDDIR}/u-boot-sunxi/u-boot-sunxi-with-spl.bin ${TEMPDIR}/${DEBFOLDER}/usr/lib/${DEBNAME}/u-boot-sunxi-with-spl.bin
	
	dpkg -b ${TEMPDIR}/${DEBFOLDER} ${TEMPDIR}/${DEBNAME}.deb
	
	FILESIZE=$(wc -c ${TEMPDIR}/${DEBNAME}.deb | cut -f 1 -d ' ')
	[ $(wc -c ${TEMPDIR}/${DEBNAME}.deb | cut -f 1 -d ' ') -lt 50000 ] && (rm -f ${TEMPDIR}/${DEBNAME}.deb; clean_up 2)
	cp -f ${TEMPDIR}/${DEBNAME}.deb ${BUILDDIR}/u-boot-sunxi/${DEBNAME}.deb
	
fi

STOPTIME=`date +%s`
RUNTIME=$(((STOPTIME-STARTTIME)/60))
echo "Runtime: $RUNTIME min"

sleep 1

clean_up 0

################################################################################
