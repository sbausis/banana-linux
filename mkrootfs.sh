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

function umount_all() {
	sync
	set +e
	[ -n "$(mount | grep ${TEMPDIR}/dev/pts)" ] && (umount ${TEMPDIR}/dev/pts || umount -f ${TEMPDIR}/dev/pts)
	[ -n "$(mount | grep ${TEMPDIR}/dev)" ] && (umount ${TEMPDIR}/dev || umount -f ${TEMPDIR}/dev)
	[ -n "$(mount | grep ${TEMPDIR}/proc)" ] && (umount ${TEMPDIR}/proc || umount -f ${TEMPDIR}/proc)
	[ -n "$(mount | grep ${TEMPDIR}/sys)" ] && (umount ${TEMPDIR}/sys || umount -f ${TEMPDIR}/sys)
	set -e
}

function clean_up() {
	
	display_alert "info" "Clean up ..."
	umount_all
	
	[ -n "$(mount | grep ${TEMPDIR})" ] && (umount ${TEMPDIR} || umount -f ${TEMPDIR})
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

OUTFILE=""
ARCH=""
SUITE=""
STARTCHROOT=1
MIRROR=""

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
	OUTFILE="${CACHEDIR}/rootfs/rootfs.${SUITE}.${ARCH}.tgz"
fi

if [ -z "${SUITE}" ] && [ -z "${ARCH}" ] && [ -z "${OUTDIR}" ] && [ -z "${BUILDDIR}" ] && [ -z "${CACHEDIR}" ] && [ -z "${SOURCEDIR}" ] && [ -z "${OUTFILE}" ]; then
	help_exit
fi

################################################################################

display_alert "${SCRIPTNAME}" "${BUILDDIR} ${CACHEDIR} ${SOURCEDIR}"
display_alert "${SCRIPTNAME}" "${SUITE} ${ARCH} ${OUTFILE}"
STARTTIME=`date +%s`

if [ "$FORCEBUILD" == "0" ]; then
	display_alert "warn" "Force redownload"
	[ -d "${CACHEDIR}/rootfs" ] && rm -Rf ${CACHEDIR}/rootfs
	[ -d "${SOURCEDIR}/rootfs" ] && rm -Rf ${SOURCEDIR}/rootfs
	[ -d "${BUILDDIR}/rootfs" ] && rm -Rf ${BUILDDIR}/rootfs
fi

if [ "$FORCEEXTRACT" == "0" ]; then
	display_alert "warn" "Force rebuild"
	[ -d "${SOURCEDIR}/rootfs" ] && rm -Rf ${SOURCEDIR}/rootfs
	[ -d "${BUILDDIR}/rootfs" ] && rm -Rf ${BUILDDIR}/rootfs
fi

if [ ! -f "${OUTFILE}" ]; then
	
	umount_all
	mount -t tmpfs -o size=1024M none ${TEMPDIR}
	
	display_alert "info" "download Packages for ${SUITE}" "${ARCH}"
	debootstrap --arch=${ARCH} --foreign ${SUITE} ${TEMPDIR} 2>/dev/null | (while read LINE; do
		LINE="${LINE#I:*}"
		[ -n "${LINE}" ] && [ "${LINE:0:1}" != "#" ] && display_alert "ok" "${LINE}"
		done)

	if [ "${ARCH}" == "armhf" ]; then
		cp -f /usr/bin/qemu-arm-static ${TEMPDIR}/usr/bin/qemu-arm-static
		test -e /proc/sys/fs/binfmt_misc/qemu-arm || update-binfmts --enable qemu-arm
	fi
	cp -f /etc/resolv.conf ${TEMPDIR}/etc/resolv.conf
	#cp /proc/mounts /mnt/etc/mtab
	
	#[ -f /usr/share/keyrings/ubuntu-archive-keyring.gpg ] && cp -f /usr/share/keyrings/ubuntu-archive-keyring.gpg ${TEMPDIR}/usr/share/keyrings/ubuntu-archive-keyring.gpg
	
	display_alert "info" "starting debootstrap Stage 2"
	chroot_run ${TEMPDIR} "/debootstrap/debootstrap --second-stage" 2>/dev/null | (while read LINE; do
		LINE="${LINE#I:*}"
		[ -n "${LINE}" ] && [ "${LINE:0:1}" != "#" ] && display_alert "ok" "${LINE}"
		done)
	#debootstrap --second-stage --second-stage-target=${TEMPDIR} 2>/dev/null | (while read LINE; do
	#	LINE="${LINE#I:*}"
	#	[ -n "${LINE}" ] && [ "${LINE:0:1}" != "#" ] && display_alert "ok" "${LINE}"
	#	done)
	
	display_alert "info" "mount RootFS"
	mount -t proc chproc ${TEMPDIR}/proc
	mount -t sysfs chsys "${TEMPDIR}/sys"
	mount -t devtmpfs chdev ${TEMPDIR}/dev || mount --bind /dev ${TEMPDIR}/dev
	mount -t devpts chpts ${TEMPDIR}/dev/pts
	
	display_alert "info" "updating RootFS Apt-Sources"
	if [ "${SUITE}" == "wheezy" ]; then
	cat <<EOF > ${TEMPDIR}/etc/apt/sources.list
deb http://ftp.ch.debian.org/debian/ ${SUITE} main contrib non-free
deb-src http://ftp.ch.debian.org/debian/ ${SUITE} main contrib non-free
deb http://security.debian.org/ ${SUITE}/updates main contrib non-free
deb-src http://security.debian.org/ ${SUITE}/updates main contrib non-free
deb http://ftp.ch.debian.org/debian/ ${SUITE}-updates main contrib non-free
deb-src http://ftp.ch.debian.org/debian/ ${SUITE}-updates main contrib non-free
EOF
	
	chroot_run ${TEMPDIR} "apt-key adv --keyserver pgp.mit.edu --recv-keys 0x07DC563D1F41B907" >>./mkrootfs.log 2>&1
	
	if [ "${ARCH}" == "armhf" ]; then
		echo "deb http://apt.armbian.com ${SUITE} main" > ${TEMPDIR}/etc/apt/sources.list.d/armbian.list
		chroot_run ${TEMPDIR} "apt-key adv --keyserver keys.gnupg.net --recv-keys 0x93D6889F9F0E78D5" >>./mkrootfs.log 2>&1
	fi
	
	elif [ "${SUITE}" == "trusty" ]; then
	cat <<EOF >> ${TEMPDIR}/etc/apt/sources.list
deb http://ports.ubuntu.com/ubuntu-ports/ trusty main restricted
deb-src http://ports.ubuntu.com/ubuntu-ports/ trusty main restricted
deb http://ports.ubuntu.com/ubuntu-ports/ trusty-updates main restricted
deb-src http://ports.ubuntu.com/ubuntu-ports/ trusty-updates main restricted
deb http://ports.ubuntu.com/ubuntu-ports/ trusty universe
deb-src http://ports.ubuntu.com/ubuntu-ports/ trusty universe
deb http://ports.ubuntu.com/ubuntu-ports/ trusty-updates universe
deb-src http://ports.ubuntu.com/ubuntu-ports/ trusty-updates universe
deb http://ports.ubuntu.com/ubuntu-ports/ trusty-security main restricted
deb-src http://ports.ubuntu.com/ubuntu-ports/ trusty-security main restricted
deb http://ports.ubuntu.com/ubuntu-ports/ trusty-security universe
deb-src http://ports.ubuntu.com/ubuntu-ports/ trusty-security universe
deb http://ports.ubuntu.com/ubuntu-ports/ trusty-security multiverse
deb-src http://ports.ubuntu.com/ubuntu-ports/ trusty-security multiverse
EOF
	chroot_run ${TEMPDIR} "apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 0x2EA8F35793D8809A" >>./mkrootfs.log 2>&1
	fi
	
	cat <<EOF > ${TEMPDIR}/etc/apt/apt.conf.d/71-no-recommends
APT::Install-Recommends "0";
APT::Install-Suggests "0";
EOF
	
	chroot_run ${TEMPDIR} "dpkg-divert --local --rename --add /sbin/initctl; ln -s /bin/true /sbin/initctl" >>./mkrootfs.log 2>&1
	
	display_alert "info" "updating Apt-Sources"
	chroot_run ${TEMPDIR} "apt-get -y -q update" >>./mkrootfs.log 2>&1
	#chroot_run ${TEMPDIR} "apt-get -y -q upgrade"
	
	display_alert "info" "Install RootFS Locales"
	DEST_LANG="en_US.UTF-8"
	CONSOLE_CHAR="UTF-8"
	chroot_install_packages ${TEMPDIR} "locales" >>./mkrootfs.log 2>&1
	display_alert "ok" "Installed Locales"
	
	display_alert "info" "Configuring RootFS Locales"
	[ -f "${TEMPDIR}/etc/locale.gen" ] && sed -i "s/^# $DEST_LANG/$DEST_LANG/" ${TEMPDIR}/etc/locale.gen
	chroot_run ${TEMPDIR} "locale-gen $DEST_LANG" >>./mkrootfs.log 2>&1
	chroot_run ${TEMPDIR} "export CHARMAP=$CONSOLE_CHAR FONTFACE=8x16 LANG=$DEST_LANG LANGUAGE=$DEST_LANG DEBIAN_FRONTEND=noninteractive" >>./mkrootfs.log 2>&1
	display_alert "ok" "Configured Locales"
	
	display_alert "info" "Generating Locales"
	chroot_run ${TEMPDIR} "update-locale LANG=$DEST_LANG LANGUAGE=$DEST_LANG LC_MESSAGES=POSIX" >>./mkrootfs.log 2>&1
	display_alert "ok" "Generated Locales"
	
	display_alert "info" "Install RootFS Console"
	chroot_install_packages ${TEMPDIR} "console-setup console-data kbd console-common unicode-data" >>./mkrootfs.log 2>&1
	[ -f "${TEMPDIR}/etc/default/console-setup" ] && sed -e 's/CHARMAP=".*"/CHARMAP="'$CONSOLE_CHAR'"/g' -i ${TEMPDIR}/etc/default/console-setup
	display_alert "ok" "Installed Console"
	
	
	display_alert "info" "cleanUp RootFS"
	chroot_run ${TEMPDIR} "apt-get clean" >>./mkrootfs.log 2>&1
	chroot_run ${TEMPDIR} "unset DEBIAN_FRONTEND" >>./mkrootfs.log 2>&1
	
	display_alert "info" "set RootFS Hostname"
	chroot_run ${TEMPDIR} "hostname -b vmroot" >>./mkrootfs.log 2>&1
	
	chroot_run ${TEMPDIR} "rm -f /sbin/initctl; dpkg-divert --local --rename --remove /sbin/initctl" >>./mkrootfs.log 2>&1
	
	display_alert "info" "unmount RootFS"
	chroot_run ${TEMPDIR} "sync"
	umount_all
	
	if [ "${ARCH}" == "armhf" ]; then
		rm -f ${TEMPDIR}/usr/bin/qemu-arm-static
	fi
	rm -f ${TEMPDIR}/etc/resolv.conf
	
	KILLPROC=$(ps -uax | pgrep ntpd |        tail -1); [ -n "$KILLPROC" ] && kill -9 $KILLPROC;
	KILLPROC=$(ps -uax | pgrep dbus-daemon | tail -1); [ -n "$KILLPROC" ] && kill -9 $KILLPROC;
	
	display_alert "info" "save rootFS"
	FILENAME=$(basename "${OUTFILE}")
	tar -czp -C ${TEMPDIR} -f ${TEMPDIR}/../${FILENAME} --exclude=dev/* --exclude=proc/* --exclude=run/* --exclude=tmp/* --exclude=mnt/* .
	
	[ -f "${OUTFILE}" ] && rm -f ${OUTFILE}
	[ -d "${SOURCEDIR}/rootfs" ] && rm -Rf ${SOURCEDIR}/rootfs
	[ -d "${BUILDDIR}/rootfs" ] && rm -Rf ${BUILDDIR}/rootfs
	
	mkdir -p $(dirname ${OUTFILE})
	mv -f ${TEMPDIR}/../${FILENAME} ${OUTFILE}
	
	mkdir -p ${SOURCEDIR}/rootfs
	mv -f ${TEMPDIR}/* ${SOURCEDIR}/rootfs/
	
fi

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
