#!/bin/sh
# epgbcn4 aka seikath@gmail.com
# is410@epg-mysql-memo1:~/bin/epg.mysql.cluster.restore.sh
# moved to bitbucket : 2013-02-06.15.26.48
# 2013-02-18.10.37.19 - add debug/test mode
# So far on RHEL .. porting to other distors after its done for RHEL 

SCRIPT_NAME=${0%.*}
LOG_FILE="$(basename ${SCRIPT_NAME}).$(date +%Y-%m-%d.%H.%M.%S).log"
CONF_FILE=${SCRIPT_NAME}.conf
TMP_WORL_FILE="/tmp/${HOSTNAME}.$(basename ${SCRIPT_NAME}).tmp"

# Loading configuraion 
if [ -f "${CONF_FILE}" ]
then
        source "${CONF_FILE}"
else 
        logit "Missing config file ${CONF_FILE} !  Exiting now."
        exit 0
fi
# activating debug 
test $DEBUG -eq 1 && set -x

# initialize the tmp file 
test `echo "" >  "${TMP_WORL_FILE}"` && logit "${TMP_WORL_FILE} initialized!"

function logit () {
    echo "$(date)::[${HOSTNAME}] : ${1}"
    echo "$(date)::[${HOSTNAME}] : ${1}" >> "${LOG_FILE}"
}

# getting the user ID, check sudo, ndbd restart command 
check_is_root=$(id | sed '/^uid=0/!d' | wc -l)
user_name=$(id -nu)

local_command_ndbd=$(chkconfig --list| grep ndbd | awk '{print $1}')
command_ndbd="service ${local_command_ndbd} restart-initial"
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
#logit "Got ndbd sercice restart command to be run by user ${user_name} : ${command_restar_ndbd}"

# get the available active IPs:
local_ip_array=$(${add_sudo}ifconfig  | grep "inet addr:" | grep -v grep | awk '{print $2}' | sed 's/^addr://')

# get the ndbd data 
data=$(${add_sudo}ndb_config -c ${ndb_mgmd[1]},${ndb_mgmd[2]} --type=ndbd --query=id,host,datadir -f ' ' -r '\n') 

# get the recent data node ID, its IP and the data directory used
# check the ndbd start-stop command name of all ndbd data nodes
echo "${data}" | \
while read nodeID  nodeIP backupDir
do	
	logit "Getting the ndbd start script name from ${user_name}@${nodeIP}"
	command_ndbd[${nodeID}]=$(echo "${add_sudo}/sbin/chkconfig --list" | ${ssh_command} ${user_name}@${nodeIP}  | grep ndb | awk '{print $1}')
	localHit=0;
	for IP in ${local_ip_array}
        do
		test "${nodeIP}" == "${IP}" && localHit=1 && break;
        done  
        echo -e "${nodeIP}\t${nodeID}\t${backupDir}${LocalBackupDirName}\t${command_ndbd[${nodeID}]}\t${localHit}" >> "${TMP_WORL_FILE}"
done

# load the the recent data node ID, its IP and the data directory used
if [ -f "${TMP_WORL_FILE}" ]
then 
	ndbd_cntr=0;
	while read tmp_IP tmp_nodeID tmp_backupDir tmp_command_ndbd tmp_localHit
	do
		test -z ${tmp_localHit} && continue;
		if [ ${tmp_localHit} -eq 1 ] 
		then
			IP="${tmp_IP}";
			nodeID="${tmp_nodeID}";
			backupDir="${tmp_backupDir}"
			
		fi 
		command_ndbd[${nodeID}]="${tmp_command_ndbd}";
		ndbd_data_node_id[$ndbd_cntr]="${tmp_nodeID}";
		ndbd_data_IP[$ndbd_cntr]="${tmp_IP}";
		ndbd_data_bckp_dir[$ndbd_cntr]="${tmp_backupDir}";
		ndbd_data_cmd[$ndbd_cntr]="${tmp_command_ndbd}";
		ndbd_data_local[$ndbd_cntr]=${tmp_localHit};
		((++ndbd_cntr))
	done < "${TMP_WORL_FILE}"
else
	logit "Missing data collection at ${TMP_WORL_FILE}. Exiting no." && exit 0;	
fi

logit "got Local machine IP ${IP}";
logit "got Local machine MySQL cluster nodeID : ${nodeID}";
logit "got MySQL cluster local backup Dir : ${backupDir}";
logit "got MySQL cluster RHEL local service command : ${local_command_ndbd}";

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
		logit "Proceeding with the condifured nightly backup.."
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
logit "DEBUG : check the content of the backup directory provided [${backupDir}]"
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
	# echo "${NDB_BACKUP_STATUS}"
	logit "Confirmed : ${NDB_BACKUP_DIR} contains consistent backup"
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
		logit "Make sure the database is existing, otherwise the restore will fail and you would need full MySQL initialization restore"
		# add here check of the MySQL cluster data nodes status 
		logit "Fetching the databases from the MySQL cluster ... "
		# Fetch the databases from the MySQL Cluster : 
		data_ndb_databases_online=$(${add_sudo}ndb_show_tables -c ${ndb_mgmd[1]},${ndb_mgmd[2]} -t 2 | awk '$1 ~ /^[[:digit:]]/ && $2 == "UserTable" && $3 == "Online"  {print $5}' | sort | uniq)
		cntr=0;
		for DbName in ${data_ndb_databases_online}
		do 
			((++cntr));
			dbArrayName[${cntr}]="${DbName}";
			comma=" => ";
			test $cntr -gt 9 &&  comma=" : "
			logit "Found database${comma}[${DbName}]";
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
						 	crap[$idx]=0;
							logit "[${ArrayUserDbNames[idx]}] : Confirmed";
							break;
						fi
					done
					DbNameOnly_restrore_string="${DbNameOnly_restrore_string}${commat}${ArrayUserDbNames[idx]}";
					test ${crap[idx]} -eq 1 \
					&& logit "Note : the database ${ArrayUserDbNames[idx]} is missing in the curent MySQL Cluster!" \
					&& logit "We recommend restore witj DDL/metadata" \
					&& logit "After a successfull restore of a MISSING database you HAVE TO CREATE IT by \"mysql> create database ${ArrayUserDbNames[idx]};\"" \
					&& logit "Then all the restored tables and data will be accessible.";
										
				done
				# check if the DDL should be restored as well :
				while [ 1  ]
				do
					read  -r -p "$(date)::[${HOSTNAME}] : Do you want the table metadata to be restored as well? Y/N : "  restoreDDL;
					if [ "${restoreDDL}" != "" ]
					then
						case ${restoreDDL} in
						"Y" | "y" | "yes" | "Yes" | "YES" )
						logit "Including the DDLL/meta table data restore";
						restoreStringInclude="-m --include-databases=${DbNameOnly_restrore_string}";
						break;
						;;
						"N" | "n" | "No" | "NO" | "Non" )
						logit "Skipping the DDL/meta table data restore";
						restoreStringInclude="--include-databases=${DbNameOnly_restrore_string}";
						break;
						;;
						*)
						logit "Please choose [Y]es or [N]O!"
						;;
						esac
					fi
				done 
				#logit "Proceeding with the BACKUP of the database(s) ${DbNameOnly_restrore_string}"
				#logit "DEBUG : restoreStringInclude : ${restoreStringInclude}";
				# restoreStringInclude="--include-databases=${DbNameOnly_restrore_string}";
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
							crap[$idx]=0;
							logit "[${userTables[idx]}] : Confirmed";
							break;
						fi 
					done
					DbNameTable_restrore_string="${DbNameTable_restrore_string}${commat}${userTables[idx]}";
					test ${crap[idx]} -eq 1 && logit "NOTE : Table ${userTables[idx]} is missing in the curent MySQL Cluster!";
				done

				# check if the DDL should be restored as well :
				while [ 1  ]
				do
					read  -r -p "$(date)::[${HOSTNAME}] : Do you want the table metadata to be restored as well? Y/N : "  restoreDDL;
					if [ "${restoreDDL}" != "" ]
					then
						case ${restoreDDL} in
						"Y" | "y" | "yes" | "Yes" | "YES" )
						logit "Including the DDLL/meta table data restore";
						restoreStringInclude="-m --include-tables=${DbNameTable_restrore_string}";
						break;
						;;
						"N" | "n" | "No" | "NO" | "Non" )
						logit "Skipping the DDL/meta table data restore";
						restoreStringInclude="--include-tables=${DbNameTable_restrore_string}";
						break;
						;;
						*)
						logit "Please choose [Y]es or [N]O!"
						;;
						esac
					fi
				done 

				#restoreStringInclude="--include-tables=${DbNameTable_restrore_string}";
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

# Put here the stupid windows question : 
# logit "About to execute the restore procedure with the following options : [${restoreStringInclude}]."
# possible stupid question to add : Do you want to proceed ? Y/N [Y]
# checking the available API nodes :
logit "Checking the available API nodes:"
api_data=$(${add_sudo}ndb_mgm --ndb-mgmd-host=${ndb_mgmd[1]},${ndb_mgmd[2]} -e 'show' | sed  '/^\[mysqld(API)\]/,$!d;/^ *$/d')
# skip the API NODES LISTING # echo "${api_data}"
#get the first node : 
echo "${api_data}" | sed  '/^\[mysqld(API)\]/d' | \
while read  API_NODE_ID API_NODE_IP crap
do
	API_NODE_ID=${API_NODE_ID/*=/}
	test `echo "${crap}" | grep "not connected" | wc -l` -gt 0 && logit "Skipping NOT CONNECTED API Node ID [${API_NODE_ID}] ${API_NODE_IP}{$crap}" && continue;
	API_NODE_IP=${API_NODE_IP/@/}
	logit "Procceding MySQL CLuster API NODE [${API_NODE_ID}] at [${API_NODE_IP}]"
	API_NODE_ID=${API_NODE_ID/*=/}
	# set the API node in single user more :
	case $restore in
	"F" | "f" | "FULL" | "Full" )
		# loop again the data nodes 
		logit "The Full MySQL custer restore has been deactivated at that time. The proceeding will be added after extensive testing."
		exit 0;
		ndbd_initial_status=1;
		for idx in $(seq 0 $((${#ndbd_data_node_id[@]} - 1)))
		do
			ndbd_start_status[$idx]=$(echo "ps aux | grep -v grep | grep -i ndbd | sed '1,1!d'" | ${ssh_command} ${user_name}@${ndbd_data_IP[idx]})
			if [ "${ndbd_start_status[idx]}" != "" -a "${ndbd_start_status[idx]}" != "${ndbd_start_status[idx]/--initial/}" ]
			then
				
				logit "MySQL Cluster NDB DATA NODE [${ndbd_data_node_id[idx]}] runnig in initial mode, no restart needed";
			elif [ "${ndbd_start_status[idx]}" == "" ]
			then
				ndbd_initial_status=0;
				logit "MySQL Cluster NDB DATA NODE [${ndbd_data_node_id[idx]}] is runnig in start mode, restart in initial mode is needed.";
				logit "Executing restart initial at NDBD node [${ndbd_data_node_id[idx]}]";
			else
				ndbd_initial_status=0;
				logit "MySQL Cluster NDB DATA NODE [${ndbd_data_node_id[idx]}] is NOT runnig ";
			fi 
			logit "DEBUG: idx: [${idx}] : ${ndbd_start_status[idx]}";
		done
		if [ ${ndbd_initial_status} -eq 1  ]
		then
			logit "Check MySQL CLuster single user mode status";
			mysql_sluster_status=$(${add_sudo}ndb_mgm --ndb-mgmd-host=${ndb_mgmd[1]},${ndb_mgmd[2]} -e 'show' | sed '/ndbd/,/^ *$/!d;/^ *$/d;/^id/!d;/single user mode/!d' | wc -l)
			if [ ${mysql_sluster_status} -eq $((${#ndbd_data_node_id[@]}-1)) ]
			then
				logit "Setting the MySQL CLuster DATA NODE [${API_NODE_ID}] at ${API_NODE_IP}] in single user mode";
				mysql_sluster_set_sinlge_user_mode=$(${add_sudo}ndb_mgm --ndb-mgmd-host=${ndb_mgmd[1]},${ndb_mgmd[2]} -e 'enter single user mode ${API_NODE_ID}');
			else
				logit "No need to set the single user mode as its already activated";
				logit "Executing FULL restore with table metadata."
				cmd_restore="${add_sudo}ndb_restore -c ${API_NODE_IP}  ${restoreStringInclude} -b ${NDB_BACKUP_NUMBER} -n ${nodeID} -r ${NDB_BACKUP_DIR}"
				logit "${cmd_restore}"
				mysql_sluster_restore_result=$(${cmd_restore})
				echo "${mysql_sluster_restore_result}"


			fi
		else
			logit ""
		fi
		exit 0 ;
		logit "ssh -q -nqtt -p22 ${user_name}@${ndbd[1]} '${command_restar_ndbd}' restart-initial"
		logit "DEBUG : have to find the restart command at the other node !"
		logit "ssh -q -nqtt -p22 ${user_name}@${ndbd[2]} '${command_restar_ndbd}' restart-initial"
		logit "Cheking the status of ndbd at  ${ndbd[1]}"
		logit "${ssh_command} ${user_name}@${ndbd[1]} '${command_restar_ndbd} status'"
		ndbd_status[]echo "${command_restar_ndbd} status" | ${ssh_command} ${user_name}@${ndbd[1]}
		logit "Cheking the status of ndbd at  ${ndbd[2]}"
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
		logit "Starting the restore process for databases(s) ${DbNameOnly_restrore_string}, please wait a bit .. "
		restore_result=$(${add_sudo}ndb_restore  -c ${API_NODE_IP}  ${restoreStringInclude} -b ${NDB_BACKUP_NUMBER} -n ${nodeID} -r "${NDB_BACKUP_DIR}" 2>&1 | tee -a "${LOG_FILE}")
		what_to_see=$(echo ${restore_result} | sed '/^Processing data in table/d')
		if [ "${what_to_see}" != "${what_to_see/NDBT_ProgramExit: 0 - OK/}" ]
		then 
			logit "The restore was successful! detailed log at ${LOG_FILE} ."
			logit "Slackware4File!";
		elif [ "${what_to_see}" != "${what_to_see/Unable to find table:/}" ]
		then 
			logit "The restore FAILED due to missing/broken tables! Detailed log at ${LOG_FILE}"
			logit "We recommed restore the table metadata of $(echo ${what_to_see} | sed 's/^.*Unable to find table:/Unable to find table:/;s/^Unable to find table: //;s/ .*$//' ) table";
		elif [ "${what_to_see}" != "${what_to_see/Missing column/}" ]
		then
			logit "The restore FAILED due to missing/broken fields in a table! Detailed log at ${LOG_FILE}";
			logit "We recommed full full restore with table metadata.";
		elif [ "${what_to_see}" != "${what_to_see/Schema object with given name already exists/}" ]
		then
			logit "The restore FAILED due to attempt to create an exsisting table! Detailed log at ${LOG_FILE}";
			logit "We recommed the following steps:";
			logit "1. Restore without the table metadata OR";
			logit "2. In case the step fails due to missing tables we reccomend FULL restore with dropping the database";
		else
			logit "The restore FAILED";
		fi
	;;
	"T" | "t" )
		logit "Starting the restore process for table(s) ${DbNameTable_restrore_string}, please wait a bit .. "
		restore_result=$(${add_sudo}ndb_restore  -c ${API_NODE_IP}  ${restoreStringInclude} -b ${NDB_BACKUP_NUMBER} -n ${nodeID} -r "${NDB_BACKUP_DIR}" 2>&1 | tee -a "${LOG_FILE}")
		what_to_see=$(echo ${restore_result} | sed '/^Processing data in table/d')
		if [ "${what_to_see}" != "${what_to_see/NDBT_ProgramExit: 0 - OK/}" ]
		then 
			logit "The restore was successful! detailed log at ${LOG_FILE} ."
			logit "Slackware4File!";
		elif [ "${what_to_see}" != "${what_to_see/Unable to find table:/}" ]
		then 
			logit "The restore FAILED due to missing/broken tables! Detailed log at ${LOG_FILE}"
			logit "We recommed full full restore with table metadata.";
		elif [ "${what_to_see}" != "${what_to_see/Missing column/}" ]
		then
			logit "The restore FAILED due to missing/broken fields in a table! Detailed log at ${LOG_FILE}";
 			logit "We recommed the following steps:";
			logit "1. We recommed table restore with DDL/table metadata restore";
			logit "2. In case the step fails due to existing tables we recomend FULL restore with dropping the database";
		elif [ "${what_to_see}" != "${what_to_see/Schema object with given name already exists/}" ]
		then
			logit "The restore FAILED due to attempt to create an exsisting table! Detailed log at ${LOG_FILE}";
			logit "We recommed the following steps:";
			logit "1. Restore without the table metadata OR";
			logit "2. In case the step fails due to missing tables we recomend FULL restore with dropping the database";
		else
			logit "The restore FAILED";
		fi
	;;
	*)
		logit "Nothing to do here"
	;;
	esac
	status=$(${add_sudo}ndb_mgm --ndb-mgmd-host=${ndb_mgmd[1]},${ndb_mgmd[2]} -e 'show' | grep "^id={$nodeID}" | grep "@${IP}")
	logit "Cluster status of ndbd id ${nodeID} : ${status}"
	break; # we execute on the first acive API node
done


