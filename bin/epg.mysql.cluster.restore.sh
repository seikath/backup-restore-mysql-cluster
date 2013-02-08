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
sudo_status=$(sudo -l | tr '\n|\r' ' ' | sed 's/^.*User /User /;s/  */ /g' | grep -i "${user_name}")
no_passwd_check=0
test `echo ${sudo_status} | grep "(ALL) NOPASSWD: ALL" | wc -l ` -gt 0  && no_passwd_check=1

test $check_is_root -eq 1 && command_restar_ndbd="${command_ndbd}"


if [ ${no_passwd_check} -eq 1 ]
then 
	add_sudo="sudo ";
else 
	add_sudo="";
fi 

logit "Root check : ${check_is_root}"
logit "Sudo check : ${sudo_status}"
logit "No Passwd sudo check : ${no_passwd_check}"
logit "Got ndbd sercice restart command to be run by user $user_name : ${command_restar_ndbd}"


if [ -f "${CONF_FILE}" ]
then
        source "${CONF_FILE}"
else 
        logit "Missing config file ${CONF_FILE} !  Exiting now."
        exit 0
fi


# get the available active IPs:
local_ip_array=$(${add_sudo}ifconfig  | grep "inet addr:" | grep -v grep | awk '{print $2}' | sed 's/^addr://')

# get the ndbd local ID 
data=$(${add_sudo}ndb_config -c ${ndb_mgmd[1]},${ndb_mgmd[2]} --type=ndbd --query=id,host,datadir -f ' ' -r '\n') 

# get the recent data node ID, its IP and the data directory used
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
                backupDir=${dd##* }${BackupDirName};
                echo -e "${IP}\t${nodeID}\t${backupDir}" > "${TMP_WORL_FILE}"
                break 2;
        done  
done


# load the the recent data node ID, its IP and the data directory used
if [ -f "${TMP_WORL_FILE}" ]
then 
        read  IP nodeID backupDir < "${TMP_WORL_FILE}" 
fi

logit "got IP ${IP}";
logit "got nodeID : ${nodeID}";
logit "got backupDir : ${backupDir}";

# choose other backup available
while [ 1  ]
do 
        read  -r -p "$(date)::[${HOSTNAME}] : Do you want to choose ANOTHER backup forder : Yes/No [y/n] : "  choice
        if [ "$choice" != "" ]
        then
		case $choice in
		"Yes" | "yes" | "y" | "Si" | "si" )
		while [ 1  ]
		do 
			read  -r -p "$(date)::[${HOSTNAME}] : Please provide the full name of the PARENT backup forder or hit CTRL+C to terminate...: "  chosenDIR
			if [ -d "${chosenDIR}" ]
			then
				echo "";
				backupDir="${chosenDIR}"
				break 2;
			else 
				logit "We can not find the PARENT backup forder of ${chosenDIR}"
				echo ""
			fi
		done
		;; 
		"No" | "n" )
		logit "Proceeding wit the condifured nightly backup.."
		break;
		;;
		*)
		logit "Empty imput, please provide the full name of the backup forder or hit CTRL+C to terminate:"
		;;
		esac
        fi
done

# check read permissions at backupDir
add_sudo="";
logit "Cheking the read permissions of ${backupDir}.."
if [ ! -r "${backupDir}" ]
then 
	logit "User ${user_name} can not read the backup directory of ${backupDir}!";
	logit "Switching to sudo .."
	if [ ${no_passwd_check} -eq 0 ]
	then 
		logit "User ${user_name} can not read the backup directory of ${backupDir} with sudo neither!";
		exit 0;
	else 
		add_sudo="sudo "
	fi 
fi 

# check the content of the backup directory provided 
if [ -d "${backupDir}" ]
then
	${add_sudo}ls -1rt "${backupDir}/" |  while read crap; do logit "Found possible local backup of ndb_mgmd id ${nodeID}::${IP} : [$crap]";done
fi

while [ 1  ]
do 
        read  -r -p "$(date)::[${HOSTNAME}] : Please choose local backup to restore or hit CTRL+C to terminate...:  "  paused
        if [ "$paused" != ""  -a -d "${backupDir}/${paused}" ]
        then
		paused=${paused%%/}
                NDB_BACKUP_NUMBER=${paused/*-/}
                NDB_BACKUP_DIR="${backupDir}/${paused}"
                NDB_BACKUP_LOG="${backupDir}/${paused}/${paused}.${nodeID}.log"
                break;
        else 
                echo ""
        fi
done


# check sudo availability 
add_sudo="";
logit "Cheking the read permissions of ${NDB_BACKUP_DIR}.."
if [ ! -r "${NDB_BACKUP_DIR}" ]
then 
	logit "User ${user_name} can not read the backup directory of ${NDB_BACKUP_DIR}!";
	logit "Switching to sudo .."
	if [ ${no_passwd_check} -eq 0 ]
	then 
		logit "User ${user_name} is missing sudo and can not read the backup directory of ${NDB_BACKUP_DIR}!";
		exit 0;
	else 
		add_sudo="sudo ";
	fi 
fi 

# check if there is backup log file in the backup directory 
logit "Cheking the read permissions of ${NDB_BACKUP_LOG}.."
logit "${add_sudo}ls ${NDB_BACKUP_LOG}  >> /dev/null 2>&1"
${add_sudo}ls ${NDB_BACKUP_LOG}  >> /dev/null 2>&1
test $? -gt 1 && logit "Error : ${NDB_BACKUP_LOG} is missing at ${NDB_BACKUP_DIR} ! Exiting now." && exit 0;

# checking the backup consistency:
if [ -d "${NDB_BACKUP_DIR}" ]
then
	logit "We are about to proceed with the restore of the backup at ${NDB_BACKUP_DIR}:  $(${add_sudo}ls -lrth ${NDB_BACKUP_DIR})"
        logit "Checking the backup consistency:"
        NDB_BACKUP_STATUS=$(${add_sudo}ndb_print_backup_file "${NDB_BACKUP_LOG}")
	test `echo ${NDB_BACKUP_STATUS}  | grep -i "NDBBCKUP" | wc -l ` -eq 0 && logit "${NDB_BACKUP_LOG} is NOT NDB consistane Backup file!" && exit 0
	echo "${NDB_BACKUP_STATUS}"
else 
        logit "ERROR : Missing NDB BACKUP directory ${NDB_BACKUP_DIR}!"
fi

#  choose the restore type: full restore with drop database or table restore

logit "Starting the restore type questionaire: "
exit 0;
while [ 1  ]
do 
        read  -r -p "$(date)::[${HOSTNAME}] :Please choose the restore type : FULL DATABASE restore including database [F] or TABLE [F]restore OR  hit CTRL+C to terminate... [F(ull)]/[T(able)]:  "  restore
        if [ "$restore" != "" ]
        then
		case $restore in
		"Full" | "F" | "f" )
		while [ 1  ]
		do 
			read  -r -p "$(date)::[${HOSTNAME}] : Please provide the full name of the table including the database name like DATABASE.TABLE : "  tableName
			tableName=${tableName}
			if [ -d "${chosenDIR}" ]
			then
				echo "";
				backupDir="${chosenDIR}"
				break 2;
			else 
				logit "We can not find the PARENT backup forder of ${chosenDIR}"
				echo ""
			fi
		done
		;; 
		"No" | "n" )
		logit "Proceeding wit the condifured nightly backup.."
		break;
		;;
		*)
		logit "Empty imput, please provide the full name of the backup forder or hit CTRL+C to terminate:"
		;;
		esac
        fi
done


# checking the available API nodes :
logit "Checking the available API nodes:"
api_data=$(${add_sudo}ndb_mgm --ndb-mgmd-host=${ndb_mgmd[1]},${ndb_mgmd[2]} -e 'show' | sed  '/^\[mysqld(API)\]/,$!d;/^ *$/d')
echo "${api_data}"
#get the first node : 
echo "${api_data}" | sed  '/^\[mysqld(API)\]/d' | \
while read  API_NODE_ID API_NODE_IP crap 
do
	API_NODE_ID=${API_NODE_ID/*=/}
	logit "API_NODE_ID : [${API_NODE_ID}]"
	if [ `echo "${API_NODE_IP} $crap" | grep "not connected" | wc -l` -gt 0 ] 
	then 
		logit "Skipping NOT CONNECTED API Node ID [${API_NODE_ID}] ${API_NODE_IP}{$crap}";
	else
		API_NODE_IP=${API_NODE_IP/@/}
		logit "API_NODE_IP : [${API_NODE_IP}]"
		API_NODE_ID=${API_NODE_ID/*=/}
		# set the API node in single user more :
		logit "Setting the API node [${API_NODE_ID}] in single user mode"
		logit "${add_sudo}ndb_mgm --ndb-mgmd-host=${ndb_mgmd[1]},${ndb_mgmd[2]} -e 'enter single user mode ${API_NODE_ID}'" 
		logit "Cheking the status of ndbd id ${nodeID}"
		logit "ssh -q -nqtt -p22 is410@${ndbd[2]} '${command_restar_ndbd}'"

# is410@epg-mysql-mem																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																								o1 /data/mysqlcluster  $ ssh -q -nqtt -p22 is410@10.95.109.195 'sudo su - -c "service ndbd_3  restart"'
# Stopping ndbd :  failed
# Starting ndbd --ndb-nodeid=3 --ndb-connectstring=10.95.109.216:1186,10.95.109.217:1186 : ok

# sudo ndb_restore --include-tables=connect.auth_group -c 10.95.109.216   -b 8 -n 3 -r /data/mysqlcluster/backup/BACKUP/BACKUP-8

		# logit "ndb_mgm --ndb-mgmd-host=${ndb_mgmd[1]},${ndb_mgmd[2]} -e 'show' | grep "^id=$nodeID" | grep "@${IP}""
		status=$(${add_sudo}ndb_mgm --ndb-mgmd-host=${ndb_mgmd[1]},${ndb_mgmd[2]} -e 'show' | grep "^id={$nodeID}" | grep "@${IP}")
		logit "Cluster status of ndbd id ${nodeID} : ${status}"
		# "id=4    @10.95.109.196  (mysql-5.5.29 ndb-7.2.10, single user mode"
		logit "Restarting the ndbd id ${nodeID} with initial switch via : ${command_restar_ndbd}"
		logit "${command_restar_ndbd}"
		logit "In case we have single user mode enabled at ndbd node id ${nodeID} at IP ${IP} we executing the restore"
		logit "${add_sudo}ndb_restores -c ${API_NODE_IP} -m -b ${NDB_BACKUP_NUMBER} -n ${nodeID} -r ${NDB_BACKUP_DIR}"
		break;
	fi 
done
        logit "Exiting the single user more:"
        logit "${add_sudo}ndb_mgm --ndb-mgmd-host=${ndb_mgmd[1]},${ndb_mgmd[2]} -e 'exit single user mode'"


