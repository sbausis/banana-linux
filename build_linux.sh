#!/bin/bash

set -e
#set -x

export LC_ALL=C LANGUAGE=C LANG=C

SCRIPTNAME=$(basename "$0")
BASE=$(cd `dirname $0` && pwd)

mkdir -p ${BASE}/.build
LOGFILE=${BASE}/.build/${SCRIPTNAME}.log
DIALOGTITLE="# Banana-Debian Build"

STARTTIME=`date +%s`

clear

bash ${BASE}/mklinux.sh $@  | tee -a ${LOGFILE} | dialog --backtitle "${DIALOGTITLE}" --progressbox "build Linux ..." 20 70

STOPTIME=`date +%s`

RUNTIME=$(((STOPTIME-STARTTIME)/60))
echo "Runtime: $RUNTIME min"

exit 0
