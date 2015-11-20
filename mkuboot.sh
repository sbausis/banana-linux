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
	
	display_alert "info" "Clean up ..."
	
	rm -Rf "${TEMPDIR}"
	rm -f "${LOCKFILE}"
	
	STOPTIME=`date +%s`
	RUNTIME=$(((STOPTIME-STARTTIME)/60))
	
	trap "" SIGHUP SIGINT SIGTERM SIGQUIT EXIT
	if [ "$1" != "0" ]; then
		display_alert "error" "failed ..."
		display_alert "Runtime: $RUNTIME min"
		sleep 1
		exit $1
	else
		display_alert "ok" "Done ..."
		display_alert "Runtime: $RUNTIME min"
		sleep 1
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

display_alert() {
	local STR=""
	[ "$3" != "" ] && STR="[\e[0;33m $3 \x1B[0m]"
	if [ "$1" == "error" ]; then   echo -e "[\e[0;31m error \x1B[0m] $2 $STR"
	elif [ "$1" == "warn" ]; then 	echo -e "[\e[0;36m warn \x1B[0m] $2 $STR"
	elif [ "$1" == "info" ]; then 	echo -e "[\e[0;33m info \x1B[0m] $2 $STR"
	elif [ "$1" == "ok" ]; then 	echo -e "[\e[0;32m o.k. \x1B[0m] $2 $STR"
	else 							  echo -e "[\e[0;34m $1 \x1B[0m] $2 $STR"
	fi
}

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

display_alert "${SCRIPTNAME}" "${BUILDDIR} ${CACHEDIR} ${SOURCEDIR}"
STARTTIME=`date +%s`

if [ "$FORCEBUILD" == "0" ]; then
	display_alert "warn" "Force redownload"
	[ -d "${CACHEDIR}/u-boot-sunxi" ] && rm -Rf ${CACHEDIR}/u-boot-sunxi
	[ -d "${SOURCEDIR}/u-boot-sunxi" ] && rm -Rf ${SOURCEDIR}/u-boot-sunxi
	[ -d "${BUILDDIR}/u-boot-sunxi" ] && rm -Rf ${BUILDDIR}/u-boot-sunxi
fi

if [ "$FORCEEXTRACT" == "0" ]; then
	display_alert "warn" "Force rebuild"
	[ -d "${SOURCEDIR}/u-boot-sunxi" ] && rm -Rf ${SOURCEDIR}/u-boot-sunxi
	[ -d "${BUILDDIR}/u-boot-sunxi" ] && rm -Rf ${BUILDDIR}/u-boot-sunxi
fi

if [ ! -f "${CACHEDIR}/u-boot-sunxi/u-boot-sunxi.src.tgz" ]; then
	
	display_alert "info" "Downloading Sources"
	git clone https://github.com/linux-sunxi/u-boot-sunxi.git ${TEMPDIR}/u-boot-sunxi >/dev/null 2>&1
	display_alert "info" "Save Sources to Cache"
	tar -cz -C ${TEMPDIR} -f ${TEMPDIR}/u-boot-sunxi.src.tgz u-boot-sunxi >/dev/null 2>&1
	
	[ -d "${CACHEDIR}/u-boot-sunxi" ] && rm -Rf ${CACHEDIR}/u-boot-sunxi
	[ -d "${SOURCEDIR}/u-boot-sunxi" ] && rm -Rf ${SOURCEDIR}/u-boot-sunxi
	[ -d "${BUILDDIR}/u-boot-sunxi" ] && rm -Rf ${BUILDDIR}/u-boot-sunxi
	
	mkdir -p ${CACHEDIR}/u-boot-sunxi
	mv -f ${TEMPDIR}/u-boot-sunxi.src.tgz ${CACHEDIR}/u-boot-sunxi/u-boot-sunxi.src.tgz
	
	mkdir -p ${SOURCEDIR}/u-boot-sunxi
	mv -f ${TEMPDIR}/u-boot-sunxi/* ${SOURCEDIR}/u-boot-sunxi/
	
fi

if [ ! -d "${SOURCEDIR}/u-boot-sunxi" ]; then
	
	display_alert "info" "Extracting Sources"
	tar -xz -C ${SOURCEDIR} -f ${CACHEDIR}/u-boot-sunxi/u-boot-sunxi.src.tgz >/dev/null 2>&1
	
	[ -d "${BUILDDIR}/u-boot-sunxi" ] && rm -Rf ${BUILDDIR}/u-boot-sunxi
	
fi

if [ ! -f "${BUILDDIR}/u-boot-sunxi/u-boot-sunxi-with-spl.bin" ]; then
	
	cd ${SOURCEDIR}/u-boot-sunxi
	
	make -j1 -s ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- clean >/dev/null 2>&1
	display_alert "info" "clean Build"
	make -j1 Bananapro_defconfig CROSS_COMPILE=arm-linux-gnueabihf- >/dev/null 2>&1
	display_alert "info" "configure for BananaPro"
	
	touch .scmversion
	
	[ -f .config ] && sed -i 's/CONFIG_LOCALVERSION=""/CONFIG_LOCALVERSION="-sun7i"/g' .config
	[ -f .config ] && sed -i 's/CONFIG_LOCALVERSION_AUTO=.*/# CONFIG_LOCALVERSION_AUTO is not set/g' .config
	
	if [ "$(cat .config | grep CONFIG_ARMV7_BOOT_SEC_DEFAULT=y)" == "" ]; then
		echo "CONFIG_ARMV7_BOOT_SEC_DEFAULT=y" >> .config
		echo "CONFIG_OLD_SUNXI_KERNEL_COMPAT=y" >> .config
	fi
	
	display_alert "ok" "Building u-boot"
	make -j5 CROSS_COMPILE=arm-linux-gnueabihf- 2>/dev/null | (while read LINE; do
		[ -n "${LINE}" ] && [ "${LINE:0:1}" != "#" ] && display_alert "ok" "${LINE}"
		done)
	
	display_alert "ok" "$(echo ${LINE% *} | xargs)" "${LINE##* }"
	display_alert "ok" "u-boot"
	
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
	
	dpkg -b ${TEMPDIR}/${DEBFOLDER} ${TEMPDIR}/${DEBNAME}.deb >/dev/null 2>&1
	
	FILESIZE=$(wc -c ${TEMPDIR}/${DEBNAME}.deb | cut -f 1 -d ' ')
	[ $(wc -c ${TEMPDIR}/${DEBNAME}.deb | cut -f 1 -d ' ') -lt 50000 ] && (rm -f ${TEMPDIR}/${DEBNAME}.deb; clean_up 2)
	cp -f ${TEMPDIR}/${DEBNAME}.deb ${BUILDDIR}/u-boot-sunxi/${DEBNAME}.deb
	display_alert "ok" "deb Package"
	
fi

clean_up 0

################################################################################
