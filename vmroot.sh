#!/bin/bash

set -e
set -x

export LANGUAGE=en_US.UTF-8
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

SCRIPTNAME=$(basename "$0")
SCRIPTDIR=$(cd `dirname "$0"`; pwd)

################################################################################
## Need Packages

NEEDEDPACKAGES=""
if [ -z `which debootstrap` ]; then NEEDEDPACKAGES+="debootstrap "; fi
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

function umount_all() {
	sync
	[ -n "$(mount | grep ${SOURCEDIR}/vmroot/dev/pts)" ] && (umount ${SOURCEDIR}/vmroot/dev/pts || umount -f ${SOURCEDIR}/vmroot/dev/pts)
	[ -n "$(mount | grep ${SOURCEDIR}/vmroot/dev)" ] && (umount ${SOURCEDIR}/vmroot/dev || umount -f ${SOURCEDIR}/vmroot/dev)
	[ -n "$(mount | grep ${SOURCEDIR}/vmroot/proc)" ] && (umount ${SOURCEDIR}/vmroot/proc || umount -f ${SOURCEDIR}/vmroot/proc)
	[ -n "$(mount | grep ${SOURCEDIR}/vmroot/sys)" ] && (umount ${SOURCEDIR}/vmroot/sys || umount -f ${SOURCEDIR}/vmroot/sys)
	[ -n "$(mount | grep ${SOURCEDIR}/vmroot/tmp)" ] && (umount ${SOURCEDIR}/vmroot/tmp || umount -f ${SOURCEDIR}/vmroot/tmp)
}
function clean_up() {
	
	echo "Clean up ..."
	umount_all
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
 -O          set OUTDIR
 -a          set ARCH
 -s          set SUITE
 -f          set FORCEREBUILD
 -m          set STARTCHROOT
"
}

function help_exit() {
	print_help
	clean_up 1
}

################################################################################

function chroot_run() {
	DIRECTORY="$1"
	COMMAND="$2"
	LC_ALL=C LANGUAGE=C LANG=C chroot "${DIRECTORY}" /bin/bash -c "${COMMAND}"
}
function chroot_install_packages() {
	DIRECTORY="$1"
	PACKAGES="$2"
	LC_ALL=C LANGUAGE=C LANG=C DEBIAN_FRONTEND=noninteractive chroot "${DIRECTORY}" /bin/bash -c "apt-get -y -q install ${PACKAGES}"
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

ROOTFSFILE=""
OUTFILE=""
ARCH=""
SUITE=""
STARTCHROOT=1
RUN_SCRIPT=""
RUN_COMMAND=""
SAVE_CHANGES=1
INSTALL_PACKAGES=""

while getopts ":O:B:C:S:fxi:o:a:s:mr:c:pI:" opt; do
	case $opt in
		O) OUTDIR="$OPTARG" ;;
		B) BUILDDIR="$OPTARG" ;;
		C) CACHEDIR="$OPTARG" ;;
		S) SOURCEDIR="$OPTARG" ;;
		f) FORCEBUILD=0 ;;
		x) FORCEEXTRACT=0 ;;
		i) ROOTFSFILE="$OPTARG" ;;
		o) OUTFILE="$OPTARG" ;;
		a) ARCH="$OPTARG" ;;
		s) SUITE="$OPTARG" ;;
		m) STARTCHROOT=0 ;;
		r) RUN_SCRIPT+="$OPTARG " ;;
		c) RUN_COMMAND+="$OPTARG; " ;;
		p) SAVE_CHANGES=0 ;;
		I) INSTALL_PACKAGES+="$OPTARG " ;;
		\?) echo "Invalid option: -$OPTARG" >&2 && help_exit ;;
		:) echo "Option -$OPTARG requires an argument." >&2 && help_exit ;;
	esac
done

if [ -z "${SUITE}" ]; then
	SUITE="wheezy"
fi

if [ -z "${ARCH}" ]; then
	ARCH="armhf"
fi

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

if [ -z "${ROOTFSFILE}" ]; then
	ROOTFSFILE="${CACHEDIR}/rootfs/rootfs.${SUITE}.${ARCH}.tgz"
	if [ -f "${CACHEDIR}/vmroot/vmroot.${SUITE}.${ARCH}.tgz" ]; then
		ROOTFSFILE="${CACHEDIR}/vmroot/vmroot.${SUITE}.${ARCH}.tgz"
	fi
fi

if [ -z "${OUTFILE}" ]; then
	OUTFILE="${CACHEDIR}/vmroot/vmroot.${SUITE}.${ARCH}.tgz"
fi

if [ -n "${RUN_SCRIPT}" ] && [ ! -f "${RUN_SCRIPT}" ]; then
	help_exit
fi

if [ "1" == "${STARTCHROOT}" ] && [ -z "${RUN_SCRIPT}" ] && [ -z "${RUN_COMMAND}" ] && [ "1" == "${SAVE_CHANGES}" ] && [ -z "${INSTALL_PACKAGES}" ]; then
	help_exit
fi

if [ -z "${SUITE}" ] && [ -z "${ARCH}" ] && [ -z "${OUTDIR}" ] && [ -z "${BUILDDIR}" ] && [ -z "${CACHEDIR}" ] && [ -z "${SOURCEDIR}" ] && [ -z "${ROOTFSFILE}" ]; then
	help_exit
fi

################################################################################

echo "[ ${SCRIPTNAME} ] ${BUILDDIR} ${CACHEDIR} ${SOURCEDIR}"
echo "[ ${SCRIPTNAME} ] ${SUITE} ${ARCH} ${OUTFILE}"
STARTTIME=`date +%s`

if [ "$FORCEBUILD" == "0" ]; then
	[ -d "${CACHEDIR}/vmroot" ] && rm -Rf ${CACHEDIR}/vmroot
	[ -d "${SOURCEDIR}/vmroot" ] && rm -Rf ${SOURCEDIR}/vmroot
	[ -d "${BUILDDIR}/vmroot" ] && rm -Rf ${BUILDDIR}/vmroot
fi

if [ "$FORCEEXTRACT" == "0" ]; then
	[ -d "${SOURCEDIR}/vmroot" ] && rm -Rf ${SOURCEDIR}/vmroot
	[ -d "${BUILDDIR}/vmroot" ] && rm -Rf ${BUILDDIR}/vmroot
fi

if [ ! -f "${ROOTFSFILE}" ]; then
	
	echo "build rootfs first .!."
	sleep 1
	clean_up 1
	
fi

if [ ! -d "${SOURCEDIR}/vmroot" ]; then
	
	mkdir -p ${SOURCEDIR}/vmroot
	tar -xpz -C ${SOURCEDIR}/vmroot -f ${ROOTFSFILE}
	
	[ -d "${BUILDDIR}/vmroot" ] && rm -Rf ${BUILDDIR}/vmroot
	
fi

if [ -n "${INSTALL_PACKAGES}" ] || [ -n "${RUN_COMMAND}" ] || [ -n "${RUN_SCRIPT}" ] || [ "${STARTCHROOT}" == "0" ]; then
	
	umount_all
	
	if [ "${ARCH}" == "armhf" ]; then
		cp -f /usr/bin/qemu-arm-static ${SOURCEDIR}/vmroot/usr/bin/qemu-arm-static
		test -e /proc/sys/fs/binfmt_misc/qemu-arm || update-binfmts --enable qemu-arm
	fi
	cp -f /etc/resolv.conf ${SOURCEDIR}/vmroot/etc/resolv.conf
	cp -f /etc/mtab ${SOURCEDIR}/vmroot/etc/mtab
	echo "vmroot" > ${SOURCEDIR}/vmroot/etc/hostname
	
	mount --bind ${TEMPDIR} ${SOURCEDIR}/vmroot/tmp
	mount -t proc chproc ${SOURCEDIR}/vmroot/proc
	mount -t sysfs chsys ${SOURCEDIR}/vmroot/sys
	mount -t devtmpfs chdev ${SOURCEDIR}/vmroot/dev || mount --bind /dev ${SOURCEDIR}/vmroot/dev
	mount -t devpts chpts ${SOURCEDIR}/vmroot/dev/pts
	
	echo "### We are on VM right now ###"
	
	[ -n "${INSTALL_PACKAGES}" ] && chroot_install_packages ${SOURCEDIR}/vmroot "${INSTALL_PACKAGES}"
	
	[ -n "${RUN_COMMAND}" ] && chroot_run ${SOURCEDIR}/vmroot "${RUN_COMMAND}"
	
	[ -n "${RUN_SCRIPT}" ] && chroot_run ${SOURCEDIR}/vmroot "$(cat ${RUN_SCRIPT})"
	
	[ "${STARTCHROOT}" == "0" ] && LC_ALL=C LANGUAGE=C LANG=C chroot ${SOURCEDIR}/vmroot /bin/bash
	
	chroot_run ${SOURCEDIR}/vmroot "sync"
	umount_all
	
	if [ "${ARCH}" == "armhf" ]; then
		rm -f ${TEMPDIR}/usr/bin/qemu-arm-static
	fi
	rm -f ${TEMPDIR}/etc/resolv.conf
	
	KILLPROC=$(ps -uax | pgrep ntpd |        tail -1); [ -n "$KILLPROC" ] && kill -9 $KILLPROC;
	KILLPROC=$(ps -uax | pgrep dbus-daemon | tail -1); [ -n "$KILLPROC" ] && kill -9 $KILLPROC;
	
	test -e /proc/sys/fs/binfmt_misc/qemu-arm || update-binfmts --disable qemu-arm
	
	echo "### DONE - Closed VM ###"
	
fi

if [ "${SAVE_CHANGES}" == "0" ]; then
	
	umount_all
	
	FILENAME=$(basename "${OUTFILE}")
	tar -czp -C ${SOURCEDIR}/vmroot -f ${TEMPDIR}/${FILENAME} --exclude=dev/* --exclude=proc/* --exclude=run/* --exclude=tmp/* --exclude=mnt/* .
	
	[ -d "${CACHEDIR}/vmroot" ] && rm -Rf ${CACHEDIR}/vmroot
	[ -d "${BUILDDIR}/vmroot" ] && rm -Rf ${BUILDDIR}/vmroot
	
	mkdir -p $(dirname ${OUTFILE})
	mv -f ${TEMPDIR}/${FILENAME} ${OUTFILE}
	
fi

STOPTIME=`date +%s`
RUNTIME=$(((STOPTIME-STARTTIME)/60))
echo "Runtime: $RUNTIME min"

sleep 1

clean_up 0

################################################################################
