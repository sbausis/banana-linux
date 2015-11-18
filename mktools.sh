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

mkdir -p ${BUILDDIR}
mkdir -p ${CACHEDIR}
mkdir -p ${SOURCEDIR}

if [ "$FORCEBUILD" == "0" ]; then
	[ -d "${CACHEDIR}/sunxi-tools" ] && rm -Rf ${CACHEDIR}/sunxi-tools
	[ -d "${SOURCEDIR}/sunxi-tools" ] && rm -Rf ${SOURCEDIR}/sunxi-tools
	[ -d "${BUILDDIR}/sunxi-tools" ] && rm -Rf ${BUILDDIR}/sunxi-tools
fi

if [ "$FORCEEXTRACT" == "0" ]; then
	[ -d "${SOURCEDIR}/sunxi-tools" ] && rm -Rf ${SOURCEDIR}/sunxi-tools
	[ -d "${BUILDDIR}/sunxi-tools" ] && rm -Rf ${BUILDDIR}/sunxi-tools
fi

if [ ! -f "${CACHEDIR}/sunxi-tools/sunxi-tools.src.tgz" ]; then
	
	git clone https://github.com/linux-sunxi/sunxi-tools ${TEMPDIR}/sunxi-tools
	tar -cz -C ${TEMPDIR} -f ${TEMPDIR}/sunxi-tools.src.tgz sunxi-tools
	
	[ -d "${CACHEDIR}/sunxi-tools" ] && rm -Rf ${CACHEDIR}/sunxi-tools
	[ -d "${SOURCEDIR}/sunxi-tools" ] && rm -Rf ${SOURCEDIR}/sunxi-tools
	[ -d "${BUILDDIR}/sunxi-tools" ] && rm -Rf ${BUILDDIR}/sunxi-tools
	
	mkdir -p ${CACHEDIR}/sunxi-tools
	mv -f ${TEMPDIR}/sunxi-tools.src.tgz ${CACHEDIR}/sunxi-tools/sunxi-tools.src.tgz
	
	mkdir -p ${SOURCEDIR}/sunxi-tools
	mv -f ${TEMPDIR}/sunxi-tools/* ${SOURCEDIR}/sunxi-tools/
	
fi

if [ ! -d "${SOURCEDIR}/sunxi-tools" ]; then
	
	tar -xz -C ${SOURCEDIR} -f ${CACHEDIR}/sunxi-tools/sunxi-tools.src.tgz
	
	[ -d "${BUILDDIR}/sunxi-tools" ] && rm -Rf ${BUILDDIR}/sunxi-tools
	
fi

if [ ! -d "${BUILDDIR}/sunxi-tools/sunxi-tools_host" ]; then
	
	cd ${SOURCEDIR}/sunxi-tools
	
	make -j1 clean
	make -j5 sunxi-fexc sunxi-bootinfo sunxi-fel sunxi-nand-part
	
	mkdir -p ${BUILDDIR}/sunxi-tools/sunxi-tools_host
	cp -f sunxi-fexc sunxi-bootinfo sunxi-fel sunxi-nand-part ${BUILDDIR}/sunxi-tools/sunxi-tools_host/
	(cd ${BUILDDIR}/sunxi-tools/sunxi-tools_host && ln -fs ./sunxi-fexc ./sunxi-bin2fex)
	(cd ${BUILDDIR}/sunxi-tools/sunxi-tools_host && ln -fs ./sunxi-fexc ./sunxi-fex2bin)
	
fi

if [ ! -d "${BUILDDIR}/sunxi-tools/sunxi-tools_target" ]; then
	
	cd ${SOURCEDIR}/sunxi-tools
	
	make -j1 CC=arm-linux-gnueabi-gcc clean
	make -j5 CC=arm-linux-gnueabi-gcc sunxi-fexc sunxi-bootinfo sunxi-nand-part sunxi-pio
	
	mkdir -p ${BUILDDIR}/sunxi-tools/sunxi-tools_target
	cp -f sunxi-fexc sunxi-bootinfo sunxi-nand-part sunxi-pio ${BUILDDIR}/sunxi-tools/sunxi-tools_target/
	(cd ${BUILDDIR}/sunxi-tools/sunxi-tools_target && ln -fs ./sunxi-fexc ./sunxi-bin2fex)
	(cd ${BUILDDIR}/sunxi-tools/sunxi-tools_target && ln -fs ./sunxi-fexc ./sunxi-fex2bin)
	
fi

STOPTIME=`date +%s`
RUNTIME=$(((STOPTIME-STARTTIME)/60))
echo "Runtime: $RUNTIME min"

sleep 1

clean_up 0

################################################################################
