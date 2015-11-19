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

function reverse_patch_folder() {
	FOLDER="$1"
	PATCHFILE="$2"
	if [ "$(cd ${FOLDER} && patch --dry-run -t -p1 < ${PATCHFILE} | grep Assuming)" != "" ]; then
		echo " -> reverse-patch ${PATCHFILE} ..."
		(cd ${FOLDER} && patch --batch -t -p1 2>/dev/null < ${PATCHFILE})
	else
		echo " -> reverse-patch ${PATCHFILE} already applied .!."
	fi
}

function patch_folder() {
	FOLDER="$1"
	PATCHFILE="$2"
	if [ "$(cd ${FOLDER} && patch --dry-run --batch -p1 -N < ${PATCHFILE} | grep Skipping)" == "" ]; then
		echo " -> patch ${PATCHFILE} ..."
		(cd ${FOLDER} && patch --batch -p1 -N 2>/dev/null < ${PATCHFILE})
	else
		echo " -> patch ${PATCHFILE} already applied .!."
		
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

echo "[ ${SCRIPTNAME} ] ${BUILDDIR} ${CACHEDIR} ${SOURCEDIR}"
STARTTIME=`date +%s`

if [ "$FORCEBUILD" == "0" ]; then
	[ -d "${CACHEDIR}/linux-sunxi" ] && rm -Rf ${CACHEDIR}/linux-sunxi
	[ -d "${SOURCEDIR}/linux-sunxi" ] && rm -Rf ${SOURCEDIR}/linux-sunxi
	[ -d "${BUILDDIR}/linux-sunxi" ] && rm -Rf ${BUILDDIR}/linux-sunxi
fi

if [ "$FORCEEXTRACT" == "0" ]; then
	[ -d "${SOURCEDIR}/linux-sunxi" ] && rm -Rf ${SOURCEDIR}/linux-sunxi
	[ -d "${BUILDDIR}/linux-sunxi" ] && rm -Rf ${BUILDDIR}/linux-sunxi
fi

if [ ! -f "${CACHEDIR}/linux-sunxi/linux-sunxi.src.tgz" ]; then
	
	git clone https://github.com/Bananian/linux-bananapi.git ${TEMPDIR}/linux-sunxi
	tar -cz -C ${TEMPDIR} -f ${TEMPDIR}/linux-sunxi.src.tgz linux-sunxi
	
	[ -d "${CACHEDIR}/linux-sunxi" ] && rm -Rf ${CACHEDIR}/linux-sunxi
	[ -d "${SOURCEDIR}/linux-sunxi" ] && rm -Rf ${SOURCEDIR}/linux-sunxi
	[ -d "${BUILDDIR}/linux-sunxi" ] && rm -Rf ${BUILDDIR}/linux-sunxi
	
	mkdir -p ${CACHEDIR}/linux-sunxi
	mv -f ${TEMPDIR}/linux-sunxi.src.tgz ${CACHEDIR}/linux-sunxi/linux-sunxi.src.tgz
	
	mkdir -p ${SOURCEDIR}/linux-sunxi
	mv -f ${TEMPDIR}/linux-sunxi/* ${SOURCEDIR}/linux-sunxi/
	
fi

if [ ! -d "${SOURCEDIR}/linux-sunxi" ]; then
	
	tar -xz -C ${SOURCEDIR} -f ${CACHEDIR}/linux-sunxi/linux-sunxi.src.tgz
	
	PATCHFOLDER="${SCRIPTDIR}/files/patches/linux-sunxi"
	for PATCHFILE in `ls ${PATCHFOLDER}/*.patch`; do
		if [ "${PATCHFILE%%*.rev.patch}" == "" ]; then
			reverse_patch_folder "${SOURCEDIR}/linux-sunxi" "${PATCHFILE}"
		else
			patch_folder "${SOURCEDIR}/linux-sunxi" "${PATCHFILE}"
		fi
	done
	
	[ -d "${BUILDDIR}/linux-sunxi" ] && rm -Rf ${BUILDDIR}/linux-sunxi
	
fi

PATCHFOLDER="${SCRIPTDIR}/files/patches/linux-sunxi"
for PATCHFILE in `ls ${PATCHFOLDER}/*.patch`; do
	if [ "${PATCHFILE%%*.rev.patch}" == "" ]; then
		reverse_patch_folder "${SOURCEDIR}/linux-sunxi" "${PATCHFILE}"
	else
		patch_folder "${SOURCEDIR}/linux-sunxi" "${PATCHFILE}"
	fi
done

TMPBUILDDIR=${BUILDDIR}/linux-sunxi/.build
mkdir -p ${TMPBUILDDIR} 2>/dev/null
mkdir -p ${TMPBUILDDIR}/drivers/gpu/mali/mali 2>/dev/null

INSTALL_MOD_PATH=${BUILDDIR}/linux-sunxi/modules
mkdir -p ${INSTALL_MOD_PATH} 2>/dev/null

INSTALL_FW_PATH=${BUILDDIR}/linux-sunxi/firmware
mkdir -p ${INSTALL_FW_PATH} 2>/dev/null

INSTALL_HDR_PATH=${BUILDDIR}/linux-sunxi/headers
mkdir -p ${INSTALL_HDR_PATH} 2>/dev/null

VERSION=$(cd ${SOURCEDIR}/linux-sunxi && make kernelversion)
CROSSARGS="ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf-"
PATHARGS="O=${TMPBUILDDIR} INSTALL_MOD_PATH=${INSTALL_MOD_PATH} INSTALL_FW_PATH=${INSTALL_FW_PATH}  INSTALL_HDR_PATH=${INSTALL_HDR_PATH}"
KBUILDARGS="KBUILD_DEBARCH=armhf KDEB_PKGVERSION=${VERSION} LOCALVERSION=-sun7i"
MKARG="${CROSSARGS} ${PATHARGS} ${KBUILDARGS}"

if [ ! -f "${TMPBUILDDIR}/.config" ]; then
	
	cd ${SOURCEDIR}/linux-sunxi
	
	make -j1 ${MKARG} clean 2>/dev/null
	
	CONFIGFOLDER="${SCRIPTDIR}/files/configs/linux-sunxi"
	cp -f ${CONFIGFOLDER}/bananapro_defconfig ${TMPBUILDDIR}/.config 2>/dev/null
	
	make -j1 ${MKARG} oldconfig 2>/dev/null
	
fi

if [ ! -f "${BUILDDIR}/linux-sunxi/zImage" ]; then
	
	cd ${SOURCEDIR}/linux-sunxi
	
	make -j5 ${MKARG} all zImage 2>/dev/null
	
	cp -f ${TMPBUILDDIR}/arch/arm/boot/zImage ${BUILDDIR}/linux-sunxi/zImage
	
fi

if [ ! -f "${BUILDDIR}/linux-sunxi/linux-image-${VERSION}-sun7i_${VERSION}_armhf.deb" ] || [ ! -f "${BUILDDIR}/linux-sunxi/linux-headers-${VERSION}-sun7i_${VERSION}_armhf.deb" ] || [ ! -f "${BUILDDIR}/linux-sunxi/linux-libc-dev_${VERSION}_armhf.deb" ]; then
	
	cd ${SOURCEDIR}/linux-sunxi
	
	make -j1 ${MKARG} DEBFULLNAME="Simon Pascal Baur" DEBEMAIL="sbausis@gmx.net" deb-pkg 2>/dev/null
	
fi

STOPTIME=`date +%s`
RUNTIME=$(((STOPTIME-STARTTIME)/60))
echo "Runtime: $RUNTIME min"

sleep 1

clean_up 0

################################################################################
