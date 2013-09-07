#!/bin/sh
#run_backup.sh
### Properties ####
# 2013-02-07.12.01.57

SCRIPT_NAME=${0%.*}
LOG_FILE="$(basename ${SCRIPT_NAME}).log"
CONF_FILE=${SCRIPT_NAME}.conf


function logit () {
    echo "$(date)::[${HOSTNAME}] : ${1}"
    echo "$(date)::[${HOSTNAME}] : ${1}" >> "${LOG_FILE}"
}

if [ -f "${CONF_FILE}" ]
then
        source "${CONF_FILE}"
else 
        logit "Missing config file ${CONF_FILE} !  Exiting now."
        exit 0
fi


logit "Begin backup now."
logit "ndb_mgm --ndb-mgmd-host=${ndb_mgmd[1]},${ndb_mgmd[2]} -e \"start backup\""

ndb_mgm --ndb-mgmd-host=${ndb_mgmd[1]},${ndb_mgmd[2]} -e "start backup" 2>&1 >> ${LOG_FILE}
if [ $? -gt 0 ]
then
	logit "ERROR on backup"
else 
	logit "Backups end succesfully!"
fi

