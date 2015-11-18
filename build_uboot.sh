#!/bin/bash

set -e
#set -x

export LC_ALL=C LANGUAGE=C LANG=C

SCRIPTNAME=$(basename "$0")
BASE=$(cd `dirname $0` && pwd)

LOGFILE=${BASE}/${SCRIPTNAME}.log
DIALOGTITLE="# Banana-Debian Build"

STARTTIME=`date +%s`

clear

bash ${BASE}/mkuboot.sh $@ | tee -a ${LOGFILE} | dialog --backtitle "${DIALOGTITLE}" --progressbox "build Uboot ..." 20 70

STOPTIME=`date +%s`

RUNTIME=$(((STOPTIME-STARTTIME)/60))
echo "Runtime: $RUNTIME min"

exit 0
