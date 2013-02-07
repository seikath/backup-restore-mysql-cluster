#!/bin/sh
# epgbcn4 aka seikath@gmail.com
# is410@epg-mysql-memo1:~/bin/epg.mysql.cluster.restore.sh
# moved to bitbucket : 2013-02-06.15.26.48


SCRIPT_NAME=${0%.*}
LOG_FILE="$(basename ${SCRIPT_NAME}).log"
CONF_FILE=${SCRIPT_NAME}.conf
TMP_WORL_FILE="/tmp/${HOSTNAME}.$(basename ${SCRIPT_NAME}).tmp"


# initialize the tmp file 
test `echo "" >  "${TMP_WORL_FILE}"` && logit "${TMP_WORL_FILE} initialized!"

function logit () {
    echo "$(date)::[${HOSTNAME}] : ${1}"
    echo "$(date)::[${HOSTNAME}] : ${1}" >> "${LOG_FILE}"
}

# getting the user ID, check sudo, ndbd restart command 
check_is_root=$(id | sed '/^uid=0/!d' | wc -l)
user_name=$(id -nu)

command_ndbd=$(chkconfig --list| grep ndbd | awk '{print $1}')
command_ndbd="service ${command_ndbd} restart-initial"
command_restar_ndbd="sudo ${command_ndbd}"
test $check_is_root && command_restar_ndbd="${command_ndbd}"

logit "Root check : ${check_is_root}"

logit "Got restart command to be run by user $user_name : ${command_restar_ndbd}"


if [ -f "${CONF_FILE}" ]
then
        source "${CONF_FILE}"
else 
        logit "Missing config file ${CONF_FILE} !  Exiting now."
        #exit 0
fi


# get the available active IPs:
local_ip_array=$(ifconfig  | grep "inet addr:" | grep -v grep | awk '{print $2}' | sed 's/^addr://')

# get the ndbd local ID 
data=$(ndb_config -c ${ndb_mgmd[1]},${ndb_mgmd[2]} --type=ndbd --query=id,host,datadir -f ' ' -r '\n') 


echo "${data}" | \
while read dd
do
        echo "${local_ip_array}" | \
        while read IP
        do
                if [  `echo ${dd} | grep -v grep | grep "${IP}" | wc -l ` -eq 0 ]
                then
                        continue;
                fi
                nodeID=${dd%% *};
                backupDir=${dd##* }/${BackupDirName};
                #logit "break on IP ${IP}";
                #logit "got temp IP ${IP}";
                #logit "got temp nodeID : ${nodeID}";
                #logit "got temp backupDir : ${backupDir}";
                echo -e "${IP}\t${nodeID}\t${backupDir}" > "${TMP_WORL_FILE}"
                break 2;
        done  
done

if [ -f "${TMP_WORL_FILE}" ]
then 
        read  IP nodeID backupDir < "${TMP_WORL_FILE}" 
fi


logit "got IP ${IP}";
logit "got nodeID : ${nodeID}";
logit "got backupDir : ${backupDir}";
 
if [ -d "${backupDir}" ]
then
ls -1rt "${backupDir}/" |  while read crap;do logit "found backup local backup of ndb_mgmd id ${nodeID}::${IP} : [$crap]";done
fi

# choose the backup 
# choose the backup 
while [ 1  ]
do 
        read  -r -p "$(date)::[${HOSTNAME}] : Do you want to choose particular backup forder "  paused
        if [ "$paused" != ""  -a -d "${backupDir}/${paused}" ]
        then
                echo "";
                NDB_BACKUP_NUMBER=${paused/*-/}
                NDB_BACKUP_DIR="${backupDir}/${paused}"
                NDB_BACKUP_LOG="${backupDir}/${paused}/${paused}.${nodeID}.log"
                logit "We are about to proceed with the restore of the backup at ${NDB_BACKUP_DIR}:  $(ls -lrth ${NDB_BACKUP_DIR})"
                break;
        else 
                echo ""
        fi
done


while [ 1  ]
do 
        read  -r -p "$(date)::[${HOSTNAME}] : Please choose backup to restore or hit CTRL+C to terminate..."  paused
        if [ "$paused" != ""  -a -d "${backupDir}/${paused}" ]
        then
                echo "";
                NDB_BACKUP_NUMBER=${paused/*-/}
                NDB_BACKUP_DIR="${backupDir}/${paused}"
                NDB_BACKUP_LOG="${backupDir}/${paused}/${paused}.${nodeID}.log"
                logit "We are about to proceed with the restore of the backup at ${NDB_BACKUP_DIR}:  $(ls -lrth ${NDB_BACKUP_DIR})"
                break;
        else 
                echo ""
        fi
done



# checking the backup consistency:
if [ -d "${NDB_BACKUP_DIR}" ]
then
        logit "Checking the backup consistency:"
        ndb_print_backup_file "${NDB_BACKUP_LOG}"
else 
        logit "ERROR : Missing NDB BACKUP directory ${NDB_BACKUP_DIR}!"
fi

# checking the available API nodes :
logit "Checking the available API nodes:"
api_data=$(ndb_mgm --ndb-mgmd-host=${ndb_mgmd[1]},${ndb_mgmd[2]} -e 'show' | sed  '/^\[mysqld(API)\]/,$!d;/^ *$/d')
echo "${api_data}"
#get the first node : 
echo "${api_data}" | sed  '/^\[mysqld(API)\]/d' | \
while read  API_NODE_ID API_NODE_IP crap 
do
        API_NODE_ID=${API_NODE_ID/*=/}
        # set the API node in single user more :
        logit "Setting the API node [${API_NODE_ID}]"
        logit "ndb_mgms --ndb-mgmd-host=${ndb_mgmd[1]},${ndb_mgmd[2]} -e 'enter single user mode ${API_NODE_ID}'" 
        logit "Cheking the status of ndbd id ${nodeID}"
        # logit "ndb_mgm --ndb-mgmd-host=${ndb_mgmd[1]},${ndb_mgmd[2]} -e 'show' | grep "^id=$nodeID" | grep "@${IP}""
        status=$(ndb_mgm --ndb-mgmd-host=${ndb_mgmd[1]},${ndb_mgmd[2]} -e 'show' | grep "^id=$nodeID" | grep "@${IP}")
        logit "ndbd id ${nodeID} status : ${status}"
#       "id=4    @10.95.109.196  (mysql-5.5.29 ndb-7.2.10, single user mode"
	logit "Restarting the ndbd id ${nodeID} with initial switch"
	logit ""
        logit "In case we have single user mode enabled at ndbd node id ${nodeID} at IP ${IP} we executring the restore"
	
        logit "ndb_restores -c ${API_NODE_IP} -m -b ${NDB_BACKUP_NAME} -n ${API_NODE_ID} -r ${NDB_BACKUP_DIR}"
done
        logit "Exiting the single user more:"
        logit "ndb_mgms --ndb-mgmd-host=${ndb_mgmd[1]},${ndb_mgmd[2]} -e 'exit single user mode'"


