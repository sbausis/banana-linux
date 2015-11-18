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

function clean_up() {
	
	echo "Clean up ..."
	[ -n "$(mount | grep ${TEMPDIR}/dev/pts)" ] && umount -f ${TEMPDIR}/dev/pts
	[ -n "$(mount | grep ${TEMPDIR}/dev)" ] && umount -f ${TEMPDIR}/dev
	[ -n "$(mount | grep ${TEMPDIR}/proc)" ] && umount -f ${TEMPDIR}/proc
	[ -n "$(mount | grep ${TEMPDIR}/sys)" ] && umount -f ${TEMPDIR}/sys
	sync
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
	LC_ALL=C LANGUAGE=C LANG=C DEBIAN_FRONTEND=noninteractive chroot "${DIRECTORY}" /bin/bash -c "apt-get -y -qq install ${PACKAGES}"
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

OUTFILE=""
ARCH=""
SUITE=""
STARTCHROOT=1

while getopts ":O:B:C:S:fxo:a:s:m" opt; do
	case $opt in
		O) OUTDIR="$OPTARG" ;;
		B) BUILDDIR="$OPTARG" ;;
		C) CACHEDIR="$OPTARG" ;;
		S) SOURCEDIR="$OPTARG" ;;
		f) FORCEBUILD=0 ;;
		x) FORCEEXTRACT=0 ;;
		o) OUTFILE="$OPTARG" ;;
		a) ARCH="$OPTARG" ;;
		s) SUITE="$OPTARG" ;;
		m) STARTCHROOT=0 ;;
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

if [ -z "${OUTFILE}" ]; then
	OUTFILE="${BUILDDIR}/rootfs/rootfs.${SUITE}.${ARCH}.tgz"
fi

if [ -z "${SUITE}" ] && [ -z "${ARCH}" ] && [ -z "${OUTDIR}" ] && [ -z "${BUILDDIR}" ] && [ -z "${CACHEDIR}" ] && [ -z "${SOURCEDIR}" ] && [ -z "${OUTFILE}" ]; then
	help_exit
fi

################################################################################

echo "[ ${SCRIPTNAME} ] ${BUILDDIR} ${CACHEDIR} ${SOURCEDIR}"
echo "[ ${SCRIPTNAME} ] ${SUITE} ${ARCH} ${OUTFILE}"
STARTTIME=`date +%s`

if [ "$FORCEBUILD" == "0" ]; then
	[ -d "${CACHEDIR}/rootfs" ] && rm -Rf ${CACHEDIR}/rootfs
	[ -d "${SOURCEDIR}/rootfs" ] && rm -Rf ${SOURCEDIR}/rootfs
	[ -d "${BUILDDIR}/rootfs" ] && rm -Rf ${BUILDDIR}/rootfs
fi

if [ "$FORCEEXTRACT" == "0" ]; then
	[ -d "${SOURCEDIR}/rootfs" ] && rm -Rf ${SOURCEDIR}/rootfs
	[ -d "${BUILDDIR}/rootfs" ] && rm -Rf ${BUILDDIR}/rootfs
fi

if [ ! -f "${OUTFILE}" ]; then
	
	debootstrap --arch=${ARCH} --foreign ${SUITE} ${TEMPDIR}

	if [ "${ARCH}" == "armhf" ]; then
		cp -f /usr/bin/qemu-arm-static ${TEMPDIR}/usr/bin/qemu-arm-static
		test -e /proc/sys/fs/binfmt_misc/qemu-arm || update-binfmts --enable qemu-arm
	fi
	cp -f /etc/resolv.conf ${TEMPDIR}/etc/resolv.conf

	chroot_run ${TEMPDIR} "/debootstrap/debootstrap --second-stage"

	mount -t proc chproc ${TEMPDIR}/proc
	mount -t sysfs chsys "${TEMPDIR}/sys"
	mount -t devtmpfs chdev ${TEMPDIR}/dev || mount --bind /dev ${TEMPDIR}/dev
	mount -t devpts chpts ${TEMPDIR}/dev/pts

	cat <<EOF > ${TEMPDIR}/etc/apt/sources.list
deb http://ftp.ch.debian.org/debian/ ${SUITE} main contrib non-free
deb-src http://ftp.ch.debian.org/debian/ ${SUITE} main contrib non-free
deb http://security.debian.org/ ${SUITE}/updates main contrib non-free
deb-src http://security.debian.org/ ${SUITE}/updates main contrib non-free
deb http://ftp.ch.debian.org/debian/ ${SUITE}-updates main contrib non-free
deb-src http://ftp.ch.debian.org/debian/ ${SUITE}-updates main contrib non-free
EOF
	chroot_run ${TEMPDIR} "apt-key adv --keyserver pgp.mit.edu --recv-keys 0x07DC563D1F41B907"

	if [ "${ARCH}" == "armhf" ]; then
		echo "deb http://apt.armbian.com ${SUITE} main" > ${TEMPDIR}/etc/apt/sources.list.d/armbian.list
		chroot_run ${TEMPDIR} "apt-key adv --keyserver keys.gnupg.net --recv-keys 0x93D6889F9F0E78D5"
	fi
	
	cat <<EOF > ${TEMPDIR}/etc/apt/apt.conf.d/71-no-recommends
APT::Install-Recommends "0";
APT::Install-Suggests "0";
EOF
	
	chroot_run ${TEMPDIR} "apt-get update"

	DEST_LANG="en_US.UTF-8"
	CONSOLE_CHAR="UTF-8"
	chroot_install_packages ${TEMPDIR} "locales"
	sed -i "s/^# $DEST_LANG/$DEST_LANG/" ${TEMPDIR}/etc/locale.gen
	chroot_run ${TEMPDIR} "locale-gen $DEST_LANG"
	chroot_run ${TEMPDIR} "export CHARMAP=$CONSOLE_CHAR FONTFACE=8x16 LANG=$DEST_LANG LANGUAGE=$DEST_LANG DEBIAN_FRONTEND=noninteractive"
	chroot_run ${TEMPDIR} "update-locale LANG=$DEST_LANG LANGUAGE=$DEST_LANG LC_MESSAGES=POSIX"

	chroot_install_packages ${TEMPDIR} "console-setup console-data kbd console-common unicode-data"
	sed -e 's/CHARMAP=".*"/CHARMAP="'$CONSOLE_CHAR'"/g' -i ${TEMPDIR}/etc/default/console-setup
	
	chroot_run ${TEMPDIR} "apt-get clean"
	chroot_run ${TEMPDIR} "sync"
	chroot_run ${TEMPDIR} "unset DEBIAN_FRONTEND"
	
	if [ "${ARCH}" == "armhf" ]; then
		rm -f ${TEMPDIR}/usr/bin/qemu-arm-static
	fi
	rm -f ${TEMPDIR}/etc/resolv.conf
	
	sync

	umount -l ${TEMPDIR}/dev/pts
	umount -l ${TEMPDIR}/dev
	umount -l ${TEMPDIR}/proc
	umount -l ${TEMPDIR}/sys

	KILLPROC=$(ps -uax | pgrep ntpd |        tail -1); if [ -n "$KILLPROC" ]; then kill -9 $KILLPROC; fi  
	KILLPROC=$(ps -uax | pgrep dbus-daemon | tail -1); if [ -n "$KILLPROC" ]; then kill -9 $KILLPROC; fi  
	
	
	FILENAME=$(basename "${OUTFILE}")
	tar -czp -C ${TEMPDIR} -f ${TEMPDIR}/../${FILENAME} --exclude=dev/* --exclude=proc/* --exclude=run/* --exclude=tmp/* --exclude=mnt/* .
	
	[ -d "${CACHEDIR}/rootfs" ] && rm -Rf ${CACHEDIR}/rootfs
	[ -d "${SOURCEDIR}/rootfs" ] && rm -Rf ${SOURCEDIR}/rootfs
	[ -d "${BUILDDIR}/rootfs" ] && rm -Rf ${BUILDDIR}/rootfs
	
	mkdir -p ${CACHEDIR}/rootfs
	mv -f ${TEMPDIR}/../${FILENAME} ${CACHEDIR}/rootfs/${FILENAME}
	
	mkdir -p ${SOURCEDIR}/rootfs
	mv -f ${TEMPDIR}/* ${SOURCEDIR}/rootfs/
	
fi

STOPTIME=`date +%s`
RUNTIME=$(((STOPTIME-STARTTIME)/60))
echo "Runtime: $RUNTIME min"

sleep 1

clean_up 0

if [ "${STARTCHROOT}" == "0" ]; then
	
	mount -t proc chproc ${TEMPDIR}/proc
	mount -t sysfs chsys "${TEMPDIR}/sys"
	mount -t devtmpfs chdev ${TEMPDIR}/dev || mount --bind /dev ${TEMPDIR}/dev
	mount -t devpts chpts ${TEMPDIR}/dev/pts
	
	LC_ALL=C LANGUAGE=C LANG=C chroot "${TEMPDIR}" /bin/bash
	chroot_run ${TEMPDIR} "sync"
	sync
	
	umount -l ${TEMPDIR}/dev/pts
	umount -l ${TEMPDIR}/dev
	umount -l ${TEMPDIR}/proc
	umount -l ${TEMPDIR}/sys

fi

################################################################################
