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

# choose the backup 
# choose the backup 
while [ 1  ]
do 
        read  -r -p "$(date)::[${HOSTNAME}] : Do you want to choose ANOTHER backup forder : Yes/No [y/n] :"  choice
        if [ "$choice" != "" ]
        then
		case $choice in
		"Yes" | "yes" | "y" | "Si" | "si" )
		while [ 1  ]
		do 
			read  -r -p "$(date)::[${HOSTNAME}] : Please choose provide the full name of the backup forder or hit CTRL+C to terminate...: "  chosenDIR
			if [ -d "${chosenDIR}" ]
			then
				echo "";
				NDB_BACKUP_NUMBER=${chosenDIR/*-/}
				NDB_BACKUP_NAME=${chosenDIR##*/}
				backupDir="${chosenDIR}"
				NDB_BACKUP_LOG="${backupDir}/${NDB_BACKUP_NAME}.${nodeID}.log"
				logit "NDB_BACKUP_NUMBER : ${NDB_BACKUP_NUMBER}" 
				logit "NDB_BACKUP_NAME : ${NDB_BACKUP_NAME}" 
				logit "NDB_BACKUP_LOG : ${NDB_BACKUP_LOG}" 
				#logit "We are about to proceed with the restore of the backup at ${NDB_BACKUP_DIR}:  $(ls -lrth ${NDB_BACKUP_DIR})"
				break 2;
			else 
				logit "We can not find the backup forder of ${chosenDIR}"
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

if [ -d "${backupDir}" ]
then
	${add_sudo}ls -1rt "${backupDir}/" |  while read crap; do logit "Found backup local backup of ndb_mgmd id ${nodeID}::${IP} : [$crap]";done
fi

while [ 1  ]
do 
        read  -r -p "$(date)::[${HOSTNAME}] : Please choose backup to restore or hit CTRL+C to terminate...:  "  paused
        if [ "$paused" != ""  -a -d "${backupDir}/${paused}" ]
        then
                NDB_BACKUP_NUMBER=${paused/*-/}
                NDB_BACKUP_DIR="${backupDir}/${paused}"
                NDB_BACKUP_LOG="${backupDir}/${paused}/${paused}.${nodeID}.log"
                break;
        else 
                echo ""
        fi
done

add_sudo="";
logit "Cheking the read permissions of ${NDB_BACKUP_DIR}.."
if [ ! -r "${NDB_BACKUP_DIR}" ]
then 
	logit "User ${user_name} can not read the backup directory of ${NDB_BACKUP_DIR}!";
	logit "Switching to sudo .."
	if [ ${no_passwd_check} -eq 0 ]
	then 
		logit "User ${user_name} can not read the backup directory of ${NDB_BACKUP_DIR}!";
		exit 0;
	else 
		add_sudo="sudo ";
	fi 
fi 


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


# checking the available API nodes :
logit "Checking the available API nodes:"
api_data=$(${add_sudo}ndb_mgm --ndb-mgmd-host=${ndb_mgmd[1]},${ndb_mgmd[2]} -e 'show' | sed  '/^\[mysqld(API)\]/,$!d;/^ *$/d')
echo "${api_data}"
#get the first node : 
echo "${api_data}" | sed  '/^\[mysqld(API)\]/d' | \
while read  API_NODE_ID API_NODE_IP crap 
do
# 	logit "CRAP : [${crap}]"
# 	logit "${API_NODE_IP} $crap"
#	continue;
	logit "API_NODE_ID : [${API_NODE_ID}]"
	if [ `echo "${API_NODE_IP} $crap" | grep "not connected" | wc -l` -gt 0 ] 
	then 
		logit "Skipping NOT CONNECTED API Node ID [${API_NODE_ID}] ${API_NODE_IP}{$crap}";
	else
		logit "API_NODE_IP : [${API_NODE_IP}]"
		API_NODE_ID=${API_NODE_ID/*=/}
		# set the API node in single user more :
		logit "Setting the API node [${API_NODE_ID}]"
		logit "${add_sudo}ndb_mgms --ndb-mgmd-host=${ndb_mgmd[1]},${ndb_mgmd[2]} -e 'enter single user mode ${API_NODE_ID}'" 
		logit "Cheking the status of ndbd id ${nodeID}"
		# logit "ndb_mgm --ndb-mgmd-host=${ndb_mgmd[1]},${ndb_mgmd[2]} -e 'show' | grep "^id=$nodeID" | grep "@${IP}""
		status=$(${add_sudo}ndb_mgm --ndb-mgmd-host=${ndb_mgmd[1]},${ndb_mgmd[2]} -e 'show' | grep "^id=$nodeID" | grep "@${IP}")
		logit "${add_sudo}ndbd id ${nodeID} status : ${status}"
		# "id=4    @10.95.109.196  (mysql-5.5.29 ndb-7.2.10, single user mode"
		logit "Restarting the ndbd id ${nodeID} with initial switch via : ${command_restar_ndbd}"
		logit "${command_restar_ndbd}"
		logit "In case we have single user mode enabled at ndbd node id ${nodeID} at IP ${IP} we executring the restore"
		
		logit "${add_sudo}ndb_restores -c ${API_NODE_IP} -m -b ${NDB_BACKUP_NAME} -n ${API_NODE_ID} -r ${NDB_BACKUP_DIR}"
	fi 
done
        logit "Exiting the single user more:"
        logit "${add_sudo}ndb_mgm --ndb-mgmd-host=${ndb_mgmd[1]},${ndb_mgmd[2]} -e 'exit single user mode'"


