#!/bin/sh
# epgbcn4 aka seikath@gmail.com
# is410@epg-mysql-memo1:~/bin/epg.mysql.cluster.restore.sh
# moved to bitbucket : 2013-02-06.15.26.48

# So far on RHEL .. porting to other distors after its done for RHEL 

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

# check initial credential 
logit "UID check : ${user_name}"
logit "Sudo check : ${sudo_status}"
test ${no_passwd_check} -eq 1 && logit "No Passwd sudo check : Confirmed!"
test ${no_passwd_check} -eq 0 && logit "No Passwd sudo check : NOTE -> Missing passwordless sudo!"
logit "Got ndbd sercice restart command to be run by user ${user_name} : ${command_restar_ndbd}"

# Loading configuraion 
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

logit "got Local machine IP ${IP}";
logit "got Local machine MySQL cluster nodeID : ${nodeID}";
logit "got MySQL cluster backup Dir : ${backupDir}";

# choose other backup available
while [ 1  ]
do 
        read  -r -p "$(date)::[${HOSTNAME}] : Do you want to choose ANOTHER backup forder : Yes/No [y/n] : "  choice
        if [ "$choice" != "" ]
        then
		case $choice in
		"Yes" | "yes" | "y" | "Si" | "si" | "Y")
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
		"No" | "n" | "N" )
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

restoreStringInclude="";
while [ 1  ]
do 
        read  -r -p "$(date)::[${HOSTNAME}] : Please choose the restore type : FULL MySQL cluster [F], DATABASE [D] or TABLE [T] to restore OR hit CTRL+C to terminate : "  restore
        if [ "$restore" != "" ]
        then
		case $restore in
		"F" | "f" | "FULL" | "Full" )
		restoreStringInclude="-m"; # restore MySQL cluster table metadata 
		logit "Proceeding with the FULL MySQL BACKUP restore.";
		break;
		;; 
		"D" | "d" | "Database" | "DATABASE" )
		logit "Make sure the database is existing, otherwise the restore will fail."
		logit "Fetching the databases from the MySQL cluster ... "
		# Fetch the databases from the MySQL Cluster : 
		data_ndb_databases_online=$(${add_sudo}ndb_show_tables -c ${ndb_mgmd[1]},${ndb_mgmd[2]} -t 2 | awk '$1 ~ /^[[:digit:]]/ && $2 == "UserTable" && $3 == "Online"  {print $5}' | sort | uniq)
		cntr=0;
		for DbName  in ${data_ndb_databases_online}
		do 
			((++cntr));
			dbArrayName[${cntr}]="${DbName}";
			comma="  : ";
			test $cntr -gt 9 &&  comma=" : "
			logit "[${cntr}]${comma}[${DbName}]";
			lastdbArrayName="${DbName}";
		done

		# Get the users Database choice
		while [ 1  ]
		do 
			logit "You may provide a comma separated list of databases to restore.";
			test ${#dbArrayName[@]} -gt 1 && logit "Example: ${dbArrayName[1]},${lastdbArrayName}";
			test ${#dbArrayName[@]} -eq 1 && logit "Example: ${dbArrayName[1]}";
			read  -r -p "$(date)::[${HOSTNAME}] : Please provide the DATABASE NAMES OR hit CTRL+C to terminate : "  userDbNames;
			if [ "${userDbNames}" != "" ]
			then
				# Read the user choices
				IFS=', ' read -a ArrayUserDbNames <<< "${userDbNames}"
				# checking the user data consistency
				logit "Checking the databases.."
				DbNameOnly_restrore_string="";
				for idx in "${!ArrayUserDbNames[@]}"
				do
					crap[$idx]=1;

					for DbNameOnly  in ${data_ndb_databases_online}
					do
						if [ "${ArrayUserDbNames[idx]}" == "${DbNameOnly}" ]
						then 
							commat="";
							test "${DbNameOnly_restrore_string}" != "" && commat=",";
							DbNameOnly_restrore_string="${DbNameOnly_restrore_string}${commat}${ArrayUserDbNames[idx]}";
						 	crap[$idx]=0;
							logit "[${ArrayUserDbNames[idx]}] : Confirmed";
							logit "[DbNameOnly_restrore_string[${idx}]] : ${DbNameOnly_restrore_string}";
							break;
						fi
					done
					test ${crap[idx]} -eq 1 && logit "Database ${ArrayUserDbNames[idx]} is missing in the curent MySQL Cluster! Exiting now." && exit 0;
				done
				logit "Proceeding with the BACKUP of the database(s) ${DbNameOnly_restrore_string}"
				restoreStringInclude="--include-databases=${DbNameOnly_restrore_string}";
				break 2;
			else 
				logit "Empry database(s) name to be restored!"
			fi
		done 

		logit "Proceeding with the FULL DATABASE BACKUP. To be done just like the table backup"
		break;
		;; 
		"T" | "t" )
		logit "Make sure the database.table is existing, otherwise the restore will fail."
		logit "Fetching the databases and its tables from the MySQL cluster ... "
		# get the database.table list from the mysql cluster
		data_ndb_databases_tables_online=$(${add_sudo}ndb_show_tables -c ${ndb_mgmd[1]},${ndb_mgmd[2]} -t 2 | awk  ' ($1 ~ /^[[:digit:]]/ && $7 !~ /^NDB\$BLOB/) {print $5"."$7}' | sort | uniq)		cntr=0
		# print a list of the db.tables available atm 
		cntr=0;
		for DbNameAndTable  in ${data_ndb_databases_tables_online}
		do 
			((++cntr));
			dbArray[${cntr}]="${DbNameAndTable}";
			comma="  : ";
			test $cntr -gt 9 &&  comma=" : "
			logit "[${cntr}]${comma}[${DbNameAndTable}]";
			lastdbArray="${DbNameAndTable}";
		done
		# Get the users Database and table choice
		DbNameTable_restrore_string="";
		while [ 1  ]
		do 
			logit "You may provide a comma separated list of tables to restore.";
			test ${#dbArray[@]} -gt 1 && logit "Example: ${dbArray[1]},${lastdbArray}";
			test ${#dbArray[@]} -eq 1 && logit "Example: ${dbArray[1]}";
			read  -r -p "$(date)::[${HOSTNAME}] : Please provide the full name of the table(s) OR hit CTRL+C to terminate : "  tableName;
			if [ "${tableName}" != "" ]
			then
				# Read the user choices
				IFS=', *' read -a userTables <<< "${tableName}"
				# checking the user data consistency
				logit "Checking the tables.."
				for idx in "${!userTables[@]}"
				do
					crap[$idx]=1;
					for DbNameAndTable  in ${data_ndb_databases_tables_online}
					do
						if [ "${userTables[idx]}" == "${DbNameAndTable}" ]
						then
							commat="";
							test "${DbNameTable_restrore_string}" != "" && commat=",";
							DbNameTable_restrore_string="${DbNameTable_restrore_string}${commat}${userTables[idx]}";
							crap[$idx]=0;
							logit "[${userTables[idx]}] : Confirmed";
							break;
						fi 
					done
					test ${crap[idx]} -eq 1 && logit "Table ${userTables[idx]} is missing in the curent MySQL Cluster! Exiting now." && exit 0;
				done
				restoreStringInclude="--include-tables=${DbNameTable_restrore_string}";
				logit "Proceeding with the BACKUP of the tables ${DbNameTable_restrore_string}"
				break 2;
			else 
				logit "Empry table name to be restored!"
			fi
		done 
		;;
		*)
		logit ": Please choose the restore type : FULL DATABASE restore including database [F] or TABLE [T]restore OR hit CTRL+C to terminate... [F(ull)]/[T(able)]:  "
		;;
		esac
        fi
done

logit "About to execute the restore procedure with the following options : [${restoreStringInclude}]."
# exit 0;

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
		case $restore in
		"F" | "f" | "FULL" | "Full" )
			logit "ssh -q -nqtt -p22 ${user_name}@${ndbd[2]} '${command_restar_ndbd}' restart-initial"
			logit "Cheking the status of ndbd id ${nodeID}"
			logit "ssh -q -nqtt -p22 ${user_name}@${ndbd[2]} '${command_restar_ndbd} status'"
			logit "Setting the API node [${API_NODE_ID}] in single user"
			# possible check if the user wants to clean up the mysql cluster DB like executing drop database ... create database
			logit "${add_sudo}ndb_mgms --ndb-mgmd-host=${ndb_mgmd[1]},${ndb_mgmd[2]} -e 'enter single user mode ${API_NODE_ID}'" 
			status=$(${add_sudo}ndb_mgm --ndb-mgmd-host=${ndb_mgmd[1]},${ndb_mgmd[2]} -e 'show' | grep "^id={$nodeID}" | grep "@${IP}")
			logit "Cluster status of ndbd id ${nodeID} : ${status}"
			logit "${add_sudo}ndb_restores  -c ${API_NODE_IP}  ${restoreStringInclude} -b ${NDB_BACKUP_NUMBER} -n ${nodeID} -r ${NDB_BACKUP_DIR}"
			logit "Exiting the single user more:"
			logit "${add_sudo}ndb_mgms --ndb-mgmd-host=${ndb_mgmd[1]},${ndb_mgmd[2]} -e 'exit single user mode'"
		;;
		"D" | "d" | "Database" | "DATABASE" )
			logit "${add_sudo}ndb_restores  -c ${API_NODE_IP}  ${restoreStringInclude} -b ${NDB_BACKUP_NUMBER} -n ${nodeID} -r ${NDB_BACKUP_DIR}"
			restore_result=$(${add_sudo}ndb_restore  -c ${API_NODE_IP}  ${restoreStringInclude} -b ${NDB_BACKUP_NUMBER} -n ${nodeID} -r "${NDB_BACKUP_DIR}" | tee -a "${LOG_FILE}")
			what_to_see=$(echo ${restore_result} | sed '/^Processing data in table/d')
			restore_status=$(echo ${restore_result} | grep "NDBT_ProgramExit: 0 - OK" | grep -v grep)
			test "${restore_status}" != "" && logit "The restore was successful! detailed log at ${LOG_FILE}." && logit "Slackware4File!"
			test "${restore_status}" == "" && logit "The restore FAILED! detailed log at ${LOG_FILE}."

		;;
		"T" | "t" )
			logit "Starting the restore process, please wait a bit .. "
			restore_result=$(${add_sudo}ndb_restore  -c ${API_NODE_IP}  ${restoreStringInclude} -b ${NDB_BACKUP_NUMBER} -n ${nodeID} -r "${NDB_BACKUP_DIR}" | tee -a "${LOG_FILE}")
			what_to_see=$(echo ${restore_result} | sed '/^Processing data in table/d')
			restore_status=$(echo ${restore_result} | grep "NDBT_ProgramExit: 0 - OK" | grep -v grep)
			test "${restore_status}" != "" && logit "The restore was successful! detailed log at ${LOG_FILE}." && logit "Slackware4File!"
			test "${restore_status}" == "" && logit "The restore FAILED! detailed log at ${LOG_FILE}."
		;;
		*)
			logit "Nothing to do here"
		;;
		esac
		#logit "Setting the API node [${API_NODE_ID}] in single user mode IF we go"
		#logit "${add_sudo}ndb_mgm --ndb-mgmd-host=${ndb_mgmd[1]},${ndb_mgmd[2]} -e 'enter single user mode ${API_NODE_ID}'" 
		#logit "Cheking the status of ndbd id ${nodeID}"
		#logit "ssh -q -nqtt -p22 ${user_name}@${ndbd[2]} '${command_restar_ndbd}'"

		# sudo ndb_restore --include-tables=connect.auth_group -c  ${ndb_mgmd[1]},${ndb_mgmd[2]}  -b 8 -n 3 -r /data/mysqlcluster/backup/BACKUP/BACKUP-8

		# logit "ndb_mgm --ndb-mgmd-host=${ndb_mgmd[1]},${ndb_mgmd[2]} -e 'show' | grep "^id=$nodeID" | grep "@${IP}""
		status=$(${add_sudo}ndb_mgm --ndb-mgmd-host=${ndb_mgmd[1]},${ndb_mgmd[2]} -e 'show' | grep "^id={$nodeID}" | grep "@${IP}")
		logit "Cluster status of ndbd id ${nodeID} : ${status}"
		# "id=4    @10.95.109.196  (mysql-5.5.29 ndb-7.2.10, single user mode"
		#logit "Restarting the ndbd id ${nodeID} with initial switch via : ${command_restar_ndbd}"
		#logit "${command_restar_ndbd}"
		#logit "In case we have single user mode enabled at ndbd node id ${nodeID} at IP ${IP} we executing the restore"
		#logit "${add_sudo}ndb_restores ${restoreStringInclude} -c ${API_NODE_IP} -m -b ${NDB_BACKUP_NUMBER} -n ${nodeID} -r ${NDB_BACKUP_DIR}"
		break;
	fi 
done


# test table restore initial 
# mysql root@epg-mysql-head2:[Wed Feb 13 12:37:31 2013][connect]> delete from django_session;
# Query OK, 628 rows affected, 2 warnings (0.26 sec)
# 
# mysql root@epg-mysql-head2:[Wed Feb 13 12:37:38 2013][connect]> delete from django_content_type;
# Query OK, 11 rows affected, 2 warnings (0.00 sec)
# 
# mysql root@epg-mysql-head2:[Wed Feb 13 12:37:43 2013][connect]> delete from django_admin_log;
# Query OK, 366 rows affected, 3 warnings (0.13 sec)
