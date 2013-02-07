#!/bin/sh
#run_backup.sh
### Properties ####
# 2013-02-07.12.01.57

SCRIPT_NAME=${0%.*}
LOG_FILE="$(basename ${SCRIPT_NAME}).log"

time=` date +"%Y%m%d %H%M%S"`



### Main ###


echo "Begin backup at: $time" >> ${LOG_FILE}
ndb_mgm --ndb-mgmd-host=${ndb_mgmd[1]},${ndb_mgmd[2]} -e "start backup" 2>&1 >> ${LOG_FILE}
bck_status=$?

if [ $bck_status -gt 0 ]
then
  echo "ERROR on backup" >> ${LOG_FILE}
  logger "Error on backup"
  exit 1
fi

echo "Backups end succesfully. " >> ${LOG_FILE}
echo >> ${LOG_FILE}


# root@MADCJCNPcabeza1:[Thu Jan 17 12:52:37]:[~]$ tail backup.log
# Begin backup at: 20130117 050001
# Connected to Management Server at: 10.101.5.36:1186
# Waiting for completed, this may take several minutes
# Node 3: Backup 105 started from node 6
# Node 3: Backup 105 started from node 6 completed
#  StartGCP: 6738897 StopGCP: 6738900
#  #Records: 719507 #LogRecords: 0
#  Data: 155591956 bytes Log: 0 bytes
# Backups end succesfully. 
